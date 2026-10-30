//
//  Copyright (C) 2002-2022   The FreeCol Team
//
//  This file is part of FreeCol.
//
//  FreeCol is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 2 of the License, or
//  (at your option) any later version.
//
//  FreeCol is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with FreeCol.  If not, see <http://www.gnu.org/licenses/>.
//

import FreeColCore
import FreeColServer

/// What the Europe panel, the cargo panels and the unit menu do
/// (EuropePanel, CargoPanel, QuickActionMenu, and the client
/// InGameController's recruitUnitInEurope, trainUnitInEurope, buyGoods,
/// sellGoods, loadCargo, unloadCargo, payArrears, boardShip,
/// leaveShip, unload, moveTo and equipUnitForRole).
extension PlayController {

    // MARK: Europe

    /// Recruit one of the emigrants waiting at the docks (0 to 2).
    func recruit(_ index: Int) {
        guard ourTurn, Europe.MigrationType.validMigrantIndex(index), view.player.isColonial else { return }
        if !view.player.checkGold(view.player.europeanRecruitPrice) {
            tell(.key("info.notEnoughGold"))
            return
        }
        if command(.emigrateUnit(slot: String(Europe.MigrationType.migrantIndexToSlot(index)))) { updateGUI() }
    }

    /// Train or buy a unit in Europe.
    func train(_ unitTypeId: String) {
        guard ourTurn, let type = view.game.specification?.getUnitType(unitTypeId),
              let europe = view.player.europe else { return }
        if !view.player.checkGold(europe.unitPrice(type)) {
            tell(.key("info.notEnoughGold"))
            return
        }
        if command(.trainUnitInEurope(unitType: unitTypeId)) { updateGUI() }
    }

    /// Load goods onto a carrier: bought in Europe, or from its colony
    /// or another carrier (loadCargo and askLoadGoods), as much as fits.
    func load(_ goodsTypeId: String, _ amount: Int, onto carrierId: String, from sourceId: String? = nil) {
        guard ourTurn, amount > 0, let carrier = unit(carrierId), carrier.isCarrier,
              let type = view.game.specification?.getGoodsType(goodsTypeId) else { return }
        let player = view.player
        let source: (any Location)?
        if carrier.isInEurope {
            source = player.europe
        } else if let sourceId {
            source = view.game.getFreeColGameObject(sourceId) as? any Location
        } else {
            source = carrier.colony
        }
        guard let source, carrier.tradeLocation != nil else { return }
        let amount = min(amount, carrier.loadableAmount(type))
        if carrier.isInEurope {
            if !player.canTrade(type) { return }
            if !player.checkGold(player.market?.bidPrice(type, amount) ?? 0) {
                tell(.key("info.notEnoughGold"))
                return
            }
        }
        let old = carrier.goodsCount(type)
        if command(.loadGoods(location: source.id, type: goodsTypeId, amount: String(amount), carrier: carrierId)),
           unit(carrierId)?.goodsCount(type) != old {
            updateGUI()
        }
    }

    /// Unload goods from a carrier: sold in Europe (if boycotted, the
    /// player may pay the arrears or dump them), or into its colony, or
    /// dumped (unloadCargo, sellGoods, MarketPanel).
    func unload(_ goodsTypeId: String, _ amount: Int, from carrierId: String) {
        guard ourTurn, amount > 0, let carrier = unit(carrierId),
              let type = view.game.specification?.getGoodsType(goodsTypeId) else { return }
        if carrier.isInEurope && !view.player.canTrade(type) {
            guard let europe = view.player.europe else { return }
            let t = StringTemplate.template("boycottedGoods.text").addNamed("%goods%", type)
                .addStringTemplate("%europe%", .key(europe.nameKey)).addAmount("%amount%", view.player.arrears(type))
            switch ask(PlayQuestion(id: "boycott:\(goodsTypeId)", text: Messages.message(t) ?? "",
                                    choices: [PlayChoice(id: "pay", label: Messages.message("payArrears")),
                                              PlayChoice(id: "dump", label: Messages.message("boycottedGoods.dumpGoods")),
                                              PlayChoice(id: "cancel", label: Messages.message("cancel"))])) {
            case "pay": payArrears(goodsTypeId)
            case "dump": break
            default: return
            }
            if answers["boycott:\(goodsTypeId)"] == "pay" { return }
        }
        let old = carrier.goodsCount(type)
        if command(.unloadGoods(type: goodsTypeId, amount: String(amount), carrier: carrierId)),
           unit(carrierId)?.goodsCount(type) != old {
            updateGUI()
        }
    }

    /// Pay the arrears on a boycotted goods type, if the player can and
    /// agrees (payArrears).
    func payArrears(_ goodsTypeId: String) {
        guard ourTurn, let type = view.game.specification?.getGoodsType(goodsTypeId) else { return }
        let arrears = view.player.arrears(type)
        if arrears <= 0 { return }
        if !view.player.checkGold(arrears) {
            tell(StringTemplate.template("payArrears.noGold").addAmount("%amount%", arrears))
            return
        }
        let t = StringTemplate.template("payArrears.text").addAmount("%amount%", arrears)
        if !confirm("payArrears:\(goodsTypeId)", nil, t, "ok", "cancel") { return }
        if command(.payArrears(goodsType: goodsTypeId)) { updateGUI() }
    }

    /// Board a carrier where the unit is (boardShip, askEmbark).
    func board(_ unitId: String, _ carrierId: String) {
        guard ourTurn, let u = unit(unitId), !u.isCarrier, let carrier = unit(carrierId), carrier.canCarryUnits,
              u.isAtLocation(carrier.location) else { return }
        if command(.embark(unit: unitId, carrier: carrierId, direction: nil)), unit(unitId)?.location?.id == carrierId {
            updateGUI()
        }
    }

    /// Leave a carrier, onto the docks or the colony's tile (leaveShip).
    func leaveShip(_ unitId: String) {
        guard ourTurn, let u = unit(unitId), let carrierId = u.carrier?.id else { return }
        if command(.disembark(unit: unitId)), unit(unitId)?.location?.id != carrierId {
            _ = checkCashInTreasureTrainFromShip(unitId)
            updateGUI()
        }
    }

    private func checkCashInTreasureTrainFromShip(_ unitId: String) -> Bool {
        guard let u = unit(unitId), u.canCarryTreasure, u.canCashInTreasureTrain else { return false }
        return command(.cashInTreasureTrain(unit: unitId))
    }

    /// Unload everything from a carrier (EuropePanel.unloadAction and
    /// InGameController.unload): goods sold in Europe (paying arrears
    /// for the boycotted), or unloaded into the colony; units off.
    func unloadAll(_ carrierId: String) {
        guard ourTurn, let carrier = unit(carrierId), carrier.isCarrier else { return }
        let inEurope = carrier.isInEurope
        for g in carrier.compactGoodsList {
            guard let id = g.type?.id, let type = g.type else { continue }
            if inEurope && !view.player.canTrade(type) {
                payArrears(id)
            } else {
                unload(id, g.amount, from: carrierId)
            }
            if question != nil { return }
        }
        for id in (unit(carrierId)?.units ?? []).compactMap(\.id) { leaveShip(id) }
    }

    /// Sail a ship from Europe for a destination, or towards Europe
    /// (DestinationPanel.add): asking first if colonists would be left
    /// on the docks with room aboard.
    func sail(_ carrierId: String, to destinationId: String) {
        guard ourTurn, let ship = unit(carrierId), ship.isNaval, let europe = view.player.europe else { return }
        if ship.tradeRoute != nil && (!confirmClearTradeRoute(carrierId) || !assignRoute(carrierId, nil)) { return }
        if destinationId == europe.id {
            if ship.isInEurope { return }
            if command(.moveTo(unit: carrierId, destination: destinationId)) { updateGUI() }
            return
        }
        if ship.isInEurope, europe.units.contains(where: { !$0.isNaval }), ship.hasSpaceLeft {
            // Named for the panel the ship was dropped on: the New World.
            let t = StringTemplate.template("europePanel.leaveColonists")
                .addStringTemplate("%newWorld%", locationLabel(view.game.map, for: view.player))
            if !confirm("leaveColonists:\(carrierId)", carrierId, t, "ok", "cancel") { return }
        }
        if command(.moveTo(unit: carrierId, destination: destinationId)) { updateGUI() }
    }

    // MARK: Roles

    /// Change a unit's role, buying or selling the equipment in Europe,
    /// or taking it from or giving it to the colony (equipUnitForRole).
    func equip(_ unitId: String, _ roleId: String, _ count: Int) {
        guard ourTurn, let u = unit(unitId), let role = view.game.specification?.getRole(roleId),
              count >= 0, count <= role.maximumCount else { return }
        if role === u.role && count == u.roleCount { return }
        let player = view.player
        let req = u.goodsDifference(role, count)
        if u.isInEurope {
            for ag in req {
                guard let type = ag.type else { continue }
                if !player.canTrade(type) {
                    payArrears(type.id ?? "")
                    if !view.player.canTrade(type) { return }
                }
            }
            guard let europe = view.player.europe, let price = try? europe.priceGoods(req),
                  view.player.checkGold(price) else { return }
        } else if let colony = u.colony {
            for ag in req {
                guard let type = ag.type, colony.goodsCount(type) < ag.amount else { continue }
                tell(StringTemplate.template("equipUnit.impossible").addName("%colony%", colony.name)
                    .addNamed("%equipment%", type).addStringTemplate("%unit%", u.label(.national)))
                return
            }
        } else {
            return
        }
        if command(.equipForRole(unit: unitId, role: roleId, count: String(count))), unit(unitId)?.role?.id == roleId {
            updateGUI()
        }
    }
}

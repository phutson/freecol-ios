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

// What Java's Europe panel shows and allows, and the unit menu's role
// changes, as plain values made on the player's copy of the game.

/// Europe as its panel shows it (EuropePanel).
public struct EuropeScreen: Sendable, Equatable {
    public let gold: Int
    /// Recruiting (RecruitPanel): the price, the turns until the next
    /// emigrant, the three waiting, and whether the player can pay.
    public let recruitPrice: Int
    public let recruitTurns: Int
    public let canRecruit: Bool
    public let recruitables: [Recruitable]
    /// The unit types trained and bought, cheapest first (TrainPanel,
    /// PurchasePanel).
    public let train: [UnitOffer]
    public let purchase: [UnitOffer]
    /// The market, for the storable goods.
    public let market: [MarketEntry]
    /// The units on the docks, the ships in port, and those sailing.
    public let docks: [String]
    public let inPort: [String]
    public let toEurope: [String]
    public let toAmerica: [String]
    /// What each ship in port holds and could take.
    public let carriers: [CarrierInPort]

    public func carrier(_ id: String) -> CarrierInPort? { carriers.first { $0.id == id } }
}

public struct Recruitable: Sendable, Equatable {
    public let typeId: String
    public let roleId: String?
    public let label: String
}

public struct UnitOffer: Sendable, Equatable {
    public let typeId: String
    public let name: String
    public let price: Int
    public let affordable: Bool
}

/// A goods type in the market (MarketLabel): what it sells for, what it
/// costs, whether it is boycotted, and the arrears.
public struct MarketEntry: Sendable, Equatable {
    public let typeId: String
    public let paidForSale: Int
    public let costToBuy: Int
    public let canTrade: Bool
    public let arrears: Int
}

/// A ship in port: its goods and units, its space, what a drag from the
/// market would load of each goods type (a hold at most) and its price,
/// and which units on the docks could board.
public struct CarrierInPort: Sendable, Equatable {
    public let id: String
    public let goods: [GoodsAmount]
    public let unitIds: [String]
    public let spaceLeft: Int
    public let loads: [String: LoadOffer]
    public let canBoard: [String]
}

public struct LoadOffer: Sendable, Equatable {
    public let amount: Int
    public let price: Int
}

/// A role change the unit menu offers (QuickActionMenu.addRoleItems):
/// the role, its count, the price (negative for what selling the
/// equipment pays), and the menu's text.
public struct RoleChoice: Sendable, Equatable {
    public let roleId: String
    public let count: Int
    public let price: Int
    public let text: String
}

extension PlayerView {

    /// The amount a drag of goods moves (GoodsContainer.CARGO_SIZE).
    static let cargoSize = 100

    /// The player's Europe, as its panel shows it.
    func europeScreen() -> EuropeScreen? {
        guard let europe = player.europe, let market = player.market,
              let spec = game.specification else { return nil }
        let production = player.totalImmigrationProduction
        var turns = 100
        if production > 0 {
            let required = player.immigrationRequired - player.immigration
            turns = required / production
            if required % production > 0 { turns += 1 }
        }
        let recruitPrice = player.europeanRecruitPrice
        let recruitables = europe.expandedRecruitables(full: false).map {
            Recruitable(typeId: $0.id ?? "", roleId: $0.roleId, label: Messages.message($0.singleLabel) ?? "")
        }
        func offers(_ types: [UnitType]) -> [UnitOffer] {
            types.enumerated().sorted { a, b in
                let pa = europe.unitPrice(a.element), pb = europe.unitPrice(b.element)
                return pa < pb || (pa == pb && a.offset < b.offset)
            }.map { _, ut in
                let price = europe.unitPrice(ut)
                return UnitOffer(typeId: ut.id ?? "", name: Messages.name(ut), price: price,
                                 affordable: player.checkGold(price))
            }
        }
        let goods = spec.storableGoodsTypeList.map { gt in
            MarketEntry(typeId: gt.id ?? "", paidForSale: market.paidForSale(gt), costToBuy: market.costToBuy(gt),
                        canTrade: player.canTrade(gt), arrears: player.arrears(gt))
        }
        var docks: [String] = [], port: [Unit] = []
        for u in europe.units {
            if !u.isNaval {
                docks.append(u.id ?? "")
            } else if [.active, .fortified, .fortifying, .sentry, .skipped].contains(u.state) {
                port.append(u)
            }
        }
        var toEurope: [String] = [], toAmerica: [String] = []
        for u in player.highSeas?.units ?? [] {
            let d = u.destination
            if d === europe { toEurope.append(u.id ?? "") }
            if d === game.map || d?.tile != nil { toAmerica.append(u.id ?? "") }
        }
        let carriers = port.map { ship in
            var loads: [String: LoadOffer] = [:]
            for gt in spec.storableGoodsTypeList {
                let amount = min(Self.cargoSize, ship.loadableAmount(gt))
                loads[gt.id ?? ""] = LoadOffer(amount: amount, price: market.bidPrice(gt, amount))
            }
            return CarrierInPort(
                id: ship.id ?? "",
                goods: ship.compactGoodsList.map { GoodsAmount(typeId: $0.type?.id ?? "", amount: $0.amount) },
                unitIds: ship.units.compactMap(\.id), spaceLeft: ship.spaceLeft, loads: loads,
                canBoard: europe.units.filter { !$0.isNaval && ship.canAdd($0) }.compactMap(\.id))
        }
        return EuropeScreen(
            gold: player.gold, recruitPrice: recruitPrice, recruitTurns: turns,
            canRecruit: player.checkGold(recruitPrice), recruitables: recruitables,
            train: offers(spec.unitTypesTrainedInEurope(player)),
            purchase: offers(spec.unitTypesPurchasedInEurope(player)), market: goods, docks: docks,
            inPort: port.compactMap(\.id), toEurope: toEurope, toAmerica: toAmerica, carriers: carriers)
    }

    /// The role changes the unit menu offers a unit in Europe or a
    /// settlement (QuickActionMenu.addRoleItems).
    func roleChoices(_ unit: Unit) -> [RoleChoice] {
        let role = unit.role
        let roleCount = unit.roleCount
        let uloc: UnitLocation? = unit.isInEurope ? unit.owner?.europe : unit.settlement
        guard let uloc else { return [] }
        var ret: [RoleChoice] = []
        for r in unit.availableRoles(nil) where r !== role {
            if r.isDefaultRole {
                ret.append(choice(role, roleCount, r, 0, 0))
                continue
            }
            var count = r.maximumCount
            while count > 0 {
                let req = unit.goodsDifference(r, count)
                if let price = try? uloc.priceGoods(req), unit.owner?.checkGold(price) == true {
                    ret.append(choice(role, roleCount, r, count, price))
                    break
                }
                count -= 1
            }
        }
        return ret
    }

    private func choice(_ from: Role?, _ fromCount: Int, _ to: Role, _ toCount: Int, _ price: Int) -> RoleChoice {
        var key = "model.role.change." + (to.suffix ?? "")
        if !Messages.containsKey(key) { key = "model.role.change." + (from?.suffix ?? "") + "." + (to.suffix ?? "") }
        var text = Messages.message(key)
        if price > 0 {
            text += " (" + (Messages.message(StringTemplate.template("goldAmount").addAmount("%amount%", price)) ?? "") + ")"
        } else if price < 0 {
            text += " (" + (Messages.message(StringTemplate.template("goldAmount").addAmount("%amount%", -price)) ?? "")
                + " (" + Messages.message("income") + "))"
        }
        return RoleChoice(roleId: to.id ?? "", count: toCount, price: price, text: text)
    }
}

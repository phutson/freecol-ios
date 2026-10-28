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
import FreeColUtil

// What Java's colony panel shows and decides, as plain values made on
// the player's copy of the game.

/// A colony as its panel shows it (ColonyPanel).
public struct ColonyScreen: Sendable, Equatable {
    public let id: String
    public let name: String
    public let position: MapPosition
    /// The population (PopulationPanel): units, sons of liberty (in
    /// percent), rebels, the production bonus and the change in size
    /// that would move it.
    public let unitCount: Int
    public let sonsOfLiberty: Int
    public let rebels: Int
    public let bonus: Int
    public let sizeChange: Int
    public let warehouseCapacity: Int
    /// The buildings in the panel's order, with empty sites.
    public let buildings: [ColonyBuildingSlot]
    /// The colony's tiles, the centre first.
    public let tiles: [ColonyTileView]
    /// The net production of the goods that change, in the rules'
    /// order.
    public let net: [GoodsAmount]
    /// The storable goods held, in the rules' order.
    public let warehouse: [GoodsAmount]
    /// What is being built, and the goods it needs.
    public let building: String?
    public let needs: [BuildNeed]
    public let queue: [String]
    /// The names of what is queued.
    public let queueNames: [String]
    /// What the build queue panel offers, with why each is locked.
    public let buildingChoices: [BuildChoice]
    public let unitChoices: [BuildChoice]
    /// Where each unit in the colony or outside it could work.
    public let places: [UnitPlaces]
    /// The colonists outside the colony on its tile, and the carriers
    /// in port.
    public let outsideUnitIds: [String]
    public let inPortUnitIds: [String]

    public func places(_ unitId: String) -> [WorkPlace] {
        places.first { $0.unitId == unitId }?.places ?? []
    }
}

/// A building, or the site of one not built (BuildingPanel).
public struct ColonyBuildingSlot: Sendable, Equatable {
    /// For an empty site, the first level's type.
    public let site: String?
    public let id: String?
    public let typeId: String?
    public let name: String
    public let unitIds: [String]
    /// The production shown: the goods, the amount and the most it
    /// could make.
    public let output: ShownProduction?
    public let upkeep: Int?
}

public struct ShownProduction: Sendable, Equatable {
    public let typeId: String
    public let amount: Int
    public let maximum: Int
}

/// A tile of the colony's (ASingleTilePanel).
public struct ColonyTileView: Sendable, Equatable {
    public let id: String
    public let position: MapPosition
    public let unitIds: [String]
    /// What each unit makes here (UnitLabel), if it works anything.
    public let made: [GoodsAmount?]
    /// The centre tile's production.
    public let centre: [GoodsAmount]
    public let isCentre: Bool
}

/// Goods a building needs (ConstructionPanel): needed, held, and made
/// each turn.
public struct BuildNeed: Sendable, Equatable {
    public let typeId: String
    public let needed: Int
    public let held: Int
    public let net: Int
}

/// Something the build queue panel offers, and why it is locked, if
/// it is.
public struct BuildChoice: Sendable, Equatable {
    public let typeId: String
    public let name: String
    public let locked: String?
}

/// Where a unit could work.
public struct UnitPlaces: Sendable, Equatable {
    public let unitId: String
    public let places: [WorkPlace]
}

/// A work place, for a unit: why it can not go there (Java's
/// NoAddReason name, NONE if it can), the work it would do, and, for a
/// tile the colony does not own, why it could not be claimed.
public struct WorkPlace: Sendable, Equatable {
    public let workLocationId: String
    public let noAddReason: String
    public let workTypeId: String?
    public let claimReason: String?
}

extension PlayerView {

    /// A colony of the player's as its panel shows it.
    func colonyScreen(_ colony: Colony) -> ColonyScreen? {
        guard let spec = colony.specification, let tile = colony.tile, let id = colony.id else { return nil }
        colony.invalidateCache()
        let uc = colony.unitCount
        let sol = colony.sonsOfLiberty

        // The buildings, shuffled by the colony's place, as the panel
        // lays them out.
        var order = spec.buildingTypeList.filter { $0.upgradesFrom == nil }
        let random = JavaRandom(seed: Int64(13 * tile.x + 23 * tile.y))
        var i = order.count
        while i > 1 {
            order.swapAt(i - 1, Int(random.nextInt(Int32(i))))
            i -= 1
        }
        var slots: [ColonyBuildingSlot] = []
        for bt in order where !bt.isDefenceType && !bt.hasAbility(Ability.produceInWater) {
            guard let building = colony.buildings.first(where: { $0.type?.firstLevel === bt }) else {
                slots.append(ColonyBuildingSlot(site: bt.id, id: nil, typeId: nil, name: Messages.name(bt),
                                                unitIds: [], output: nil, upkeep: nil))
                continue
            }
            var shown: ShownProduction?
            if let info = building.productionInfo, let first = info.production.first, first.amount > 0,
               let goodsType = first.type {
                var amount = first.amount
                if building.hasAbility(Ability.avoidExcessProduction) {
                    let stored = colony.goodsCount(goodsType)
                    let capacity = colony.warehouseCapacity
                    if amount + stored > capacity { amount = capacity - stored }
                }
                let maximum = info.maximumProduction.first?.amount ?? amount
                shown = ShownProduction(typeId: goodsType.id ?? "", amount: amount, maximum: maximum)
            }
            let upkeep = spec.getBoolean(GameOptions.enableUpkeep) && (building.type?.upkeep ?? 0) > 0
                ? building.type?.upkeep : nil
            slots.append(ColonyBuildingSlot(site: nil, id: building.id, typeId: building.type?.id,
                                            name: building.type.map { Messages.name($0) } ?? "",
                                            unitIds: building.units.compactMap(\.id), output: shown,
                                            upkeep: upkeep))
        }

        let tiles = colony.colonyTiles.map { ct -> ColonyTileView in
            let wt = ct.workTile
            let made = ct.units.map { u -> GoodsAmount? in
                u.workType.map { GoodsAmount(typeId: $0.id ?? "", amount: ct.totalProduction(of: $0)) }
            }
            let centre = ct.isColonyCenterTile
                ? (colony.productionInfo(of: ct)?.production ?? []).map {
                    GoodsAmount(typeId: $0.type?.id ?? "", amount: $0.amount)
                }
                : []
            return ColonyTileView(id: ct.id ?? "", position: MapPosition(x: wt?.x ?? 0, y: wt?.y ?? 0),
                                  unitIds: ct.units.compactMap(\.id), made: made, centre: centre,
                                  isCentre: ct.isColonyCenterTile)
        }

        let net = spec.goodsTypeList.compactMap { gt -> GoodsAmount? in
            let amount = colony.adjustedNetProduction(of: gt)
            return amount == 0 ? nil : GoodsAmount(typeId: gt.id ?? "", amount: amount)
        }
        let warehouse = spec.storableGoodsTypeList.map {
            GoodsAmount(typeId: $0.id ?? "", amount: colony.goodsCount($0))
        }
        let building = colony.currentlyBuilding
        let needs = (building?.requiredGoods ?? []).compactMap { ag -> BuildNeed? in
            guard let gt = ag.type else { return nil }
            return BuildNeed(typeId: gt.id ?? "", needed: ag.amount, held: colony.goodsCount(gt),
                             net: colony.adjustedNetProduction(of: gt))
        }
        let (buildingChoices, unitChoices) = buildChoices(colony)

        // Where each colonist, in the colony or outside on its tile,
        // could work.
        var units = colony.unitList
        units += tile.units.filter(\.isPerson)
        units.sort { ($0.id ?? "") < ($1.id ?? "") }
        let places = units.map { u in
            UnitPlaces(unitId: u.id ?? "", places: colony.availableWorkLocations.map { wl in
                var claim: String?
                if let ct = wl as? ColonyTile, let t = ct.workTile, t.owningSettlement !== colony {
                    claim = player.canClaimForSettlementReason(t).javaName
                }
                return WorkPlace(workLocationId: wl.id ?? "", noAddReason: wl.noAddReason(u).javaName,
                                 workTypeId: wl.work(for: u)?.id, claimReason: claim)
            })
        }

        return ColonyScreen(
            id: id, name: colony.name ?? "", position: MapPosition(x: tile.x, y: tile.y),
            unitCount: uc, sonsOfLiberty: sol, rebels: Colony.calculateRebelCount(uc, sol),
            bonus: colony.productionBonus, sizeChange: colony.preferredSizeChange,
            warehouseCapacity: colony.warehouseCapacity, buildings: slots, tiles: tiles, net: net,
            warehouse: warehouse, building: building?.id, needs: needs,
            queue: colony.buildQueue.values.compactMap(\.id),
            queueNames: colony.buildQueue.values.map { Messages.name($0) }, buildingChoices: buildingChoices, unitChoices: unitChoices,
            places: places, outsideUnitIds: tile.units.filter(\.isPerson).compactMap(\.id),
            inPortUnitIds: tile.units.filter(\.isCarrier).compactMap(\.id))
    }

    /// The buildings and units the build queue panel offers, with why
    /// each is locked, the queue as it is (BuildQueuePanel.updateAllLists,
    /// as if all were shown).
    func buildChoices(_ colony: Colony) -> ([BuildChoice], [BuildChoice]) {
        guard let spec = colony.specification else { return ([], []) }
        let current = colony.buildQueue.values
        let queued = FeatureContainer()
        for bt in current { queued.addFeatures(of: bt) }

        func choice(_ bt: BuildableType, _ reasons: [String]) -> BuildChoice {
            BuildChoice(typeId: bt.id ?? "", name: Messages.name(bt), locked: reasons.isEmpty ? nil
                : Messages.message(StringTemplate.template("buildQueuePanel.requires")
                    .addName("%string%", reasons.joined(separator: "/"))))
        }
        // Abilities the colony and the queue do not give (checkAbilities).
        func checkAbilities(_ bt: BuildableType, _ reasons: inout [String]) -> Bool {
            let old = reasons.count
            for (id, value) in bt.requiredAbilityList
            where queued.hasAbility(id) != value && colony.hasAbility(id) != value {
                reasons.append(spec.typesProviding(id, value).first.map { Messages.name($0) } ?? Messages.name(bt))
            }
            return reasons.count == old
        }
        func hasBuildingType(_ bt: BuildingType) -> Bool {
            var bt = bt
            while true {
                guard let b = colony.building(bt) else { return false }
                if b.type === bt { return true }
                guard let up = bt.upgradesTo else { return false }
                bt = up
            }
        }
        func populationTooSmall(_ n: Int) -> String {
            Messages.message(StringTemplate.template("buildQueuePanel.populationTooSmall").addAmount("%number%", n))
                ?? ""
        }

        var buildings: [BuildChoice] = []
        var unbuildable: [ObjectIdentifier] = []
        for bt in spec.buildingTypeList {
            if unbuildable.contains(ObjectIdentifier(bt)) { continue }
            if let up = bt.upgradesFrom, unbuildable.contains(ObjectIdentifier(up)) {
                unbuildable.append(ObjectIdentifier(bt))
                continue
            }
            if !bt.needsGoodsToBuild { continue }
            if current.contains(where: { $0 === bt }) || hasBuildingType(bt) { continue }
            var reasons: [String] = []
            if bt.hasAbility(Ability.coastalOnly) && !(colony.tile?.isCoastland ?? false) {
                reasons.append(Messages.message(StringTemplate.template("buildQueuePanel.coastalOnly")) ?? "")
            }
            if bt.requiredPopulation > colony.unitCount { reasons.append(populationTooSmall(bt.requiredPopulation)) }
            for limit in bt.limits where !limit.evaluate(colony) { reasons.append(Messages.description(limit.id)) }
            if !checkAbilities(bt, &reasons) { unbuildable.append(ObjectIdentifier(bt)) }
            if let up = bt.upgradesFrom, !current.contains(where: { $0 === up }),
               colony.building(bt)?.type !== up {
                reasons.append(Messages.name(up))
            }
            buildings.append(choice(bt, reasons))
        }

        var units: [BuildChoice] = []
        unbuildable = []
        let turn = colony.game?.turn
        for ut in spec.buildableUnitTypes {
            if unbuildable.contains(ObjectIdentifier(ut)) { continue }
            var reasons: [String] = []
            if ut.requiredPopulation > colony.unitCount { reasons.append(populationTooSmall(ut.requiredPopulation)) }
            for limit in ut.limits where !limit.evaluate(colony) { reasons.append(Messages.description(limit.id)) }
            if !checkAbilities(ut, &reasons) { unbuildable.append(ObjectIdentifier(ut)) }
            if !queued.hasAbility(Ability.build, for: ut) && !colony.hasAbility(Ability.build, for: ut, turn: turn) {
                let source = spec.abilities(Ability.build).first { a in
                    a.appliesTo(ut) && a.value && a.source != nil
                        && !unbuildable.contains(ObjectIdentifier(a.source!))
                }?.source
                reasons.append(source.map { s in (s as? Named).map { Messages.name($0) } ?? Messages.name(s.id) }
                    ?? Messages.name(ut))
            }
            units.append(choice(ut, reasons))
        }
        return (buildings, units)
    }
}

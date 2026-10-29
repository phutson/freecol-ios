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

import FreeColUtil

// The model's labels: the StringTemplates naming units, players,
// places and goods (the getLabel and getLocationLabel methods of
// common/model).  Messages.message turns them into text.

extension Direction: Named {
    public var nameKey: String { Messages.nameKey("model." + key) }
}

extension Player.Stance: Named {
    /// "stance.peace" and so on.
    public var key: String { "stance." + Messages.enumKey(javaName) }
    public var nameKey: String { Messages.nameKey("model." + key) }
    /// The message key for a player declaring this stance.
    public var stanceChangeKey: String { "model.player." + key + ".declared" }
    /// The message key for others hearing of the change.
    public var otherStanceChangeKey: String { "model.player." + key + ".others" }
}

extension Tension: Named {
    public var nameKey: String { Messages.nameKey("model." + key) }
}

extension Unit.UnitState {
    /// "unitState.inColony" and so on.
    public var key: String { "unitState." + Messages.enumKey(javaName) }
}

extension TileItem: Named {
    /// The item's name key: its type's, or the rumour's.
    public var nameKey: String {
        if let r = self as? Resource { return r.type?.nameKey ?? "null.name" }
        if let i = self as? TileImprovement { return i.type?.nameKey ?? "null" }
        return Messages.nameKey("model.lostCityRumour")
    }
}

// MARK: Locations

/// The label of a location (Location.getLocationLabel).
public func locationLabel(_ loc: (any Location)?) -> StringTemplate? {
    switch loc {
    case nil: return nil
    case let europe as Europe: return StringTemplate.key(europe.nameKey)
    case is HighSeas: return StringTemplate.key("model.tile.highSeas.name")
    case is Map: return StringTemplate.key("newWorld")
    case let tile as Tile: return tile.settlement.map { locationLabel($0)! } ?? tile.detailedLocationLabel
    case let settlement as Settlement: return StringTemplate.name(settlement.name)
    case let building as Building:
        return StringTemplate.template("model.building.locationLabel").add("%location%", building.type?.nameKey)
    case let colonyTile as ColonyTile:
        guard let workTile = colonyTile.workTile, let colony = colonyTile.colony else { return nil }
        return workTile.colonyTileLocationLabel(colony)
    case let unit as Unit: return StringTemplate.template("model.unit.onBoard").addStringTemplate("%unit%", unit.label)
    case let loc?: return StringTemplate.key(loc.id)
    }
}

/// The label of a location as a player sees it
/// (Location.getLocationLabelFor).
public func locationLabel(_ loc: (any Location)?, for player: Player?) -> StringTemplate? {
    switch loc {
    case let map as Map:
        return player?.newLandName.map(StringTemplate.name) ?? locationLabel(map)
    case let tile as Tile:
        if let settlement = tile.settlement { return locationLabel(settlement, for: player) }
        return tile.detailedLocationLabel(for: player)
    case let colony as Colony: return StringTemplate.name(colony.name ?? "?")
    case let settlement as IndianSettlement:
        return player == nil || settlement.hasContacted(player) ? StringTemplate.name(settlement.name)
            : StringTemplate.key("model.indianSettlement.nameUnknown")
    case let wl as WorkLocation:
        return wl.owner === player ? locationLabel(wl) : locationLabel(wl.colony, for: player)
    default:
        return locationLabel(loc)
    }
}

extension Tile {

    /// What the tile is, with its finished improvements and resources.
    public var label: StringTemplate {
        var label = type.map { StringTemplate.key($0) } ?? StringTemplate.key("unexplored")
        let items = completeItems
        if !items.isEmpty, let type {
            label = StringTemplate.label("/").addNamed(type)
            for item in items { label.addNamed(item) }
        }
        return label
    }

    /// "(x, y)".
    public var simpleLabel: StringTemplate {
        StringTemplate.template("model.tile.simpleLabel").addAmount("%x%", x).addAmount("%y%", y)
    }

    private func nearLocationLabel(_ direction: Direction, _ location: StringTemplate?) -> StringTemplate {
        StringTemplate.template("model.tile.nearLocation").addNamed("%direction%", direction)
            .addStringTemplate("%location%", location)
    }

    private func addTypeName(_ t: StringTemplate) -> StringTemplate {
        if let type { return t.addNamed("%name%", type) }
        return t.add("%name%", "unexplored")
    }

    /// The tile placed by the nearest named settlement, or its region,
    /// or its position.
    var detailedLocationLabel: StringTemplate {
        for tile in surroundingTiles(Tile.nearRadius) {
            guard let near = tile.settlement, let name = near.name else { continue }
            let t = StringTemplate.template("model.tile.nameLocation")
            if let d = Map.roughDirection(tile, self) {
                t.addStringTemplate("%location%", nearLocationLabel(d, locationLabel(near)))
            } else {
                t.addName("%location%", name)
            }
            return addTypeName(t)
        }
        return regionOrSimpleLabel
    }

    /// The same for a player, by the nearest settlement it has met.
    func detailedLocationLabel(for player: Player?) -> StringTemplate {
        for tile in surroundingTiles(Tile.nearRadius) {
            guard let near = tile.settlement, near.hasContacted(player) else { continue }
            let d = Map.roughDirection(tile, self)
            let nearLabel = locationLabel(near, for: player)
            let t = StringTemplate.template("model.tile.nameLocation")
                .addStringTemplate("%location%", d.map { nearLocationLabel($0, nearLabel) } ?? nearLabel)
            return addTypeName(t)
        }
        return regionOrSimpleLabel
    }

    private var regionOrSimpleLabel: StringTemplate {
        guard let region, region.name != nil, let type else { return simpleLabel }
        return StringTemplate.template("model.tile.nameLocation").addNamed("%name%", type)
            .addStringTemplate("%location%", region.label)
    }

    /// The tile as a colony tile: its direction from the colony (or the
    /// centre) and its type.
    public func colonyTileLocationLabel(_ colony: Colony) -> StringTemplate? {
        let t = StringTemplate.template("model.tile.nameLocation")
        if colony.tile === self {
            t.addStringTemplate("%location%", StringTemplate.key("colonyCenter"))
        } else {
            guard let ct = colony.tile, let d = map?.direction(ct, self) else { return nil }
            t.addNamed("%location%", d)
        }
        return addTypeName(t)
    }
}

extension Region {
    /// The region's name: its key's message, its given name, or its
    /// type's unknown name.
    public var label: StringTemplate {
        if let key { return StringTemplate.key(Messages.nameKey(key)) }
        if let name { return StringTemplate.name(name) }
        return StringTemplate.key(type?.unknownKey)
    }
}

// MARK: Players

extension Player {

    public var rulerNameKey: String { Messages.rulerKey(nationId) }

    /// "<ruler> (<nation>)".
    public var label: StringTemplate {
        StringTemplate.label("").add(rulerNameKey).addName(" (").addStringTemplate(nationLabel).addName(")")
    }

    /// The nation's name, or the independent nation's.
    public var nationLabel: StringTemplate {
        playerType == .rebel || playerType == .independent
            ? StringTemplate.name(independentNationName) : StringTemplate.key(Messages.nameKey(nationId))
    }

    /// The country's name, or the new land's after independence.
    public var countryLabel: StringTemplate {
        playerType == .rebel || playerType == .independent
            ? StringTemplate.name(newLandName)
            : StringTemplate.template("countryName").addStringTemplate("%nation%", nationLabel)
    }

    public var forcesLabel: StringTemplate {
        StringTemplate.template("model.player.forces").addStringTemplate("%nation%", nationLabel)
    }

    public var waitingLabel: StringTemplate {
        StringTemplate.template("model.player.waitingFor").addStringTemplate("%nation%", nationLabel)
    }

    /// The player's market: its Europe's, or the independent market.
    public var marketName: StringTemplate {
        europe == nil ? StringTemplate.key("model.player.independentMarket") : StringTemplate.key(europeNameKey)
    }

    /// Why independence can not be declared, or nil if it can.
    public var checkDeclareIndependence: StringTemplate? {
        guard playerType == .colonial else { return StringTemplate.template("model.player.colonialIndependence") }
        guard let event = specification?.getEvent("model.event.declareIndependence"),
              let limit = event.limitValues.first(where: { !$0.evaluate(self) }) else { return nil }
        let value = game.flatMap { limit.rightHandSide.value(in: $0) }
        return StringTemplate.template(limit.descriptionKey).addName("%limit%", value.map(String.init) ?? "null")
    }

    /// When the last sale of goods somewhere was, and its price.
    public func lastSaleTip(_ location: any Location, _ what: GoodsType) -> StringTemplate? {
        guard let data = lastSale(location, what), let when = data.when, let spec = specification else { return nil }
        return StringTemplate.template("model.indianSettlement.lastSale").addNamed("%goodsType%", what)
            .addAmount("%price%", data.price).addStringTemplate("%turn%", when.label(spec.turnCalendar))
    }
}

extension Turn {
    /// "Spring 1600", or "1492" before seasons.
    public func label(_ calendar: TurnCalendar) -> StringTemplate {
        let t = StringTemplate.label("")
        let season = calendar.season(of: self)
        if season >= 0 {
            t.addName(Messages.seasonName(season))
            t.addName(" ")
        }
        return t.addName(String(calendar.year(of: self)))
    }
}

// MARK: Units

extension Unit {

    /// How much a unit label says (Unit.UnitLabelType).
    public enum UnitLabelType {
        /// Just the basics.
        case plain
        /// With the nation.
        case national
        /// With the equipment and extras.
        case full
    }

    public var label: StringTemplate? {
        label(.plain)
    }

    /// The unit's name, type and role, with its nation or equipment as
    /// asked.
    public func label(_ ult: UnitLabelType) -> StringTemplate? {
        guard let type, let role, let owner else { return nil } // Probably disposed
        switch ult {
        case .plain:
            return Messages.unitLabel(name, type.id, 1, nil, role.id, nil)
        case .national where role.maximumCount <= 1:
            return Messages.unitLabel(name, type.id, 1, owner.nationId, role.id, nil)
        case .national, .full:
            // Java falls through from NATIONAL for roles with counts.
            var extra: StringTemplate?
            if role.isDefaultRole {
                if canCarryTreasure {
                    extra = StringTemplate.template("goldAmount").addAmount("%amount%", treasureAmount)
                } else {
                    for someRole in type.expertRoles {
                        let key = (someRole.id ?? "null") + ".noequipment"
                        if Messages.containsKey(key) {
                            extra = StringTemplate.key(key)
                            break
                        }
                    }
                }
            } else {
                let equipmentKey = (role.id ?? "null") + ".equipment"
                if Messages.containsKey(equipmentKey) {
                    extra = AbstractGoods.abstractLabel(equipmentKey, 1)
                } else {
                    let label = StringTemplate.label("")
                    for (i, ag) in role.requiredGoods(count: roleCount).enumerated() {
                        if i > 0 { label.addName(" ") }
                        label.addStringTemplate(ag.label)
                    }
                    extra = label
                }
            }
            return Messages.unitLabel(name, type.id, 1, owner.nationId, role.id, extra)
        }
    }

    /// The owner's nation, or the unknown enemy's for a privateer.
    public var apparentOwnerName: StringTemplate? {
        (isOwnerHidden ? game?.unknownEnemy : owner)?.nationLabel
    }

    /// The odds of attacking a tile, as a percentage or "??".
    public func combatLabel(_ tile: Tile) -> StringTemplate {
        let odds = game?.combatModel.calculateCombatOdds(self, tile.defendingUnit(self))
            ?? CombatModel.CombatOdds(CombatModel.CombatOdds.unknownOdds)
        let unknown = odds.win == CombatModel.CombatOdds.unknownOdds || tile.hasSettlement
        return StringTemplate.template("model.unit.attackTileOdds")
            .addName("%chance%", unknown ? "??" : String(JavaMath.toInt(odds.win * 100)))
    }

    public var destinationLabel: StringTemplate? {
        let type = isPerson ? "person" : isNaval ? "ship" : "other"
        return Unit.unitDestinationLabel(type, destination, owner)
    }

    public static func unitDestinationLabel(_ tag: String, _ destination: (any Location)?,
                                            _ player: Player?) -> StringTemplate {
        StringTemplate.template("model.unit.goingTo").addTagged("%type%", tag)
            .addStringTemplate("%location%", locationLabel(destination, for: player))
    }

    public var repairLabel: StringTemplate {
        StringTemplate.template("model.unit.underRepair").addAmount("%turns%", turnsForRepair)
    }

    /// What the unit is doing, as its owner sees it, or what others can
    /// tell.
    public func occupationLabel(_ player: Player?, _ full: Bool) -> StringTemplate {
        guard let player, player.owns(self) else {
            return isNaval ? StringTemplate.name(String(visibleGoods))
                : StringTemplate.key("model.unit.occupation.activeNoMovesLeft")
        }
        func withDetail(_ key: String, _ detail: String?) -> StringTemplate {
            full ? StringTemplate.label(":").add(key).addName(detail) : StringTemplate.key(key)
        }
        if isDamagedAndUnderForcedRepair {
            return withDetail("model.unit.occupation.underRepair", String(turnsForRepair))
        }
        if let tradeRoute {
            return withDetail("model.unit.occupation.inTradeRoute", tradeRoute.name)
        }
        if state == .active && movesLeft == 0 && !isInEurope {
            return StringTemplate.key("model.unit.occupation.activeNoMovesLeft")
        }
        if state == .improving, let improvement = workImprovement {
            return withDetail("\(improvement.type?.id ?? "null").occupationString", String(workTurnsLeft))
        }
        if destination != nil { return StringTemplate.key("model.unit.occupation.goingSomewhere") }
        return StringTemplate.key("model.unit." + state.key)
    }
}

extension AbstractUnit {
    /// "<number> <unit>".
    public func label(_ spec: Specification?) -> StringTemplate {
        StringTemplate.template("model.abstractUnit.label").addAmount("%number%", number)
            .addStringTemplate("%unit%", Messages.unitLabel(nil, id, number, nil, roleId, nil))
    }

    public var singleLabel: StringTemplate {
        Messages.unitLabel(nil, id, 1, nil, roleId, nil)
    }

    public static func listLabel(_ base: String, _ units: [AbstractUnit]) -> StringTemplate {
        let template = StringTemplate.label(base)
        for au in units { template.addStringTemplate(au.label(nil)) }
        return template
    }
}

// MARK: Goods, buildings and settlements

extension AbstractGoods {
    /// "<amount> <goods>".
    public var label: StringTemplate {
        StringTemplate.template("model.abstractGoods.label").add("%goods%", type?.nameKey)
            .addAmount("%amount%", amount)
    }

    /// The label, or the boycotted label.
    public func label(sellable: Bool) -> StringTemplate {
        sellable ? label : StringTemplate.template("model.abstractGoods.boycotted")
            .add("%goods%", type?.nameKey).addAmount("%amount%", amount)
    }

    public static func abstractLabel(_ key: String, _ amount: Int) -> StringTemplate {
        StringTemplate.template("model.abstractGoods.label").add("%goods%", key).addAmount("%amount%", amount)
    }
}

extension GoodsType {
    public var label: StringTemplate { StringTemplate.key(nameKey) }
}

extension BuildableType {
    public var currentlyBuildingLabel: StringTemplate {
        StringTemplate.template("model.buildableType.currentlyBuilding").addNamed("%buildable%", self)
    }
}

extension Building: Named {
    /// A building is named by its type.
    public var nameKey: String {
        type?.nameKey ?? "null.name"
    }
}

extension Building {
    public var label: StringTemplate? { type.map { StringTemplate.key($0) } }
}

extension ColonyTile {
    public var label: StringTemplate? { workTile?.label }

    /// What claiming the tile involves: nothing for the centre, else its
    /// direction.
    public var claimTemplate: StringTemplate {
        guard !isColonyCenterTile, let d = colony?.tile.flatMap({ t in workTile.flatMap { t.direction(to: $0) } })
        else { return StringTemplate.name("") }
        return StringTemplate.template("model.colonyTile.claim").addNamed("%direction%", d)
    }
}

extension Colony {
    /// How the owner stands towards a player.
    public func alarmLevelLabel(_ player: Player) -> StringTemplate {
        let stance = owner?.stance(player) ?? .uncontacted
        return StringTemplate.template("model.colony." + stance.key)
            .addStringTemplate("%nation%", owner?.nationLabel)
    }

    /// Why the colony can not shrink further, or nil.
    public var reducePopulationMessage: StringTemplate? {
        if canReducePopulation { return nil }
        guard let min = modifiers(Modifier.minimumColonySize).first else { return nil }
        var source = min.source
        if let bt = source as? BuildingType { source = building(bt)?.type }
        return StringTemplate.template("model.colony.minimumColonySize").addName("%object%", source)
    }
}

extension IndianSettlement {
    public func learnableSkillLabel(_ visited: Bool) -> StringTemplate {
        StringTemplate.key(visited ? (learnableSkill?.nameKey ?? "model.indianSettlement.skillNone")
                                   : "model.indianSettlement.skillUnknown")
    }

    public func mostHatedLabel(_ contacted: Bool) -> StringTemplate {
        guard contacted else { return StringTemplate.key("model.indianSettlement.mostHatedUnknown") }
        return mostHated?.countryLabel ?? StringTemplate.key("model.indianSettlement.mostHatedNone")
    }

    /// How the settlement feels about a player.
    public func alarmLevelLabel(_ player: Player) -> StringTemplate {
        let key = !player.hasContacted(owner) ? "model.indianSettlement.tension.wary"
            : !hasContacted(player) ? "model.indianSettlement.tension.unknown"
            : "model.indianSettlement." + (alarm(player)?.key ?? "tension.happy")
        return StringTemplate.template(key).addStringTemplate("%nation%", owner?.nationLabel)
    }
}

// MARK: Trade routes

extension TradeRouteStop {
    public func label(_ key: String, _ player: Player?) -> StringTemplate {
        StringTemplate.template(key).addStringTemplate("%location%", locationLabel(location, for: player))
    }

    public func invalidStopLabel(_ player: Player?) -> StringTemplate {
        label("model.tradeRoute.invalidStop", player)
    }
}

extension TradeRoute {
    /// Why the route is unusable, or nil if it is fine.
    public var verify: StringTemplate? {
        guard let key = verifyKey else { return nil }
        switch key {
        case "model.tradeRoute.invalidStop":
            let stop = stopList.first { !TradeRoute.isStopValid(owner, $0) }
            return stop?.invalidStopLabel(owner)
        case "model.tradeRoute.alwaysPresent":
            // Java's first goods of a HashSet: the first stop's cargo
            // present everywhere, in hash order.
            let always = stopList.reduce(stopList[0].cargo) { acc, stop in
                acc.filter { gt in stop.cargo.contains { $0 === gt } }
            }
            var set = JavaHashMap<GoodsType, Bool>(javaHash: { $0.javaHashCode })
            for gt in always { _ = set.put(gt, true) }
            return StringTemplate.template(key).addNamed("%goodsType%", set.keys[0])
        default:
            return StringTemplate.template(key)
        }
    }

    public var verifyUniqueName: StringTemplate? {
        verifyUniqueNameKey.map { StringTemplate.template($0).addName("%name%", name) }
    }
}

extension Player.Stance {
    /// Whether natives may be incited against a player of this stance
    /// (isIncitable).
    public var isIncitable: Bool {
        self == .ceaseFire || self == .peace
    }

    /// The stance a tension calls for (getStanceFromTension): cease fire
    /// from war, then peace, as tension falls; war from peace as it
    /// rises.
    public func stance(fromTension tension: Tension) -> Player.Stance {
        let value = tension.value
        switch self {
        case .war:
            if value <= Tension.Level.content.limit - Tension.delta { return .ceaseFire }
        case .ceaseFire:
            if value <= Tension.Level.happy.limit - Tension.delta { return .peace }
            if value > Tension.Level.hateful.limit + Tension.delta { return .war }
        case .alliance, .peace:
            if value > Tension.Level.hateful.limit + Tension.delta { return .war }
        case .uncontacted:
            break
        }
        return self
    }
}

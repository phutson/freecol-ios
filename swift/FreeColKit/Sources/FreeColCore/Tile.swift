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
import FreeColXML

/// One square of the map (common/model/Tile).
///
/// The map holds its tiles.  A tile holds its item container and the
/// settlement on it; its owner, owning settlement and region are weak
/// references (the game holds players, players will hold settlements
/// from step 7, and the map holds regions).
///
/// The tile holds the units on it (as a UnitLocation), and each
/// European player's view of it: the tile itself, or a copy of what the
/// player last saw (in Defence.swift).
///
/// Not yet ported:
/// - the colony site warnings (getBuildColonyWarnings, for the client:
///   Phase 5);
/// - labels and name keys, which need StringTemplate and players;
/// - copyIn and checkIntegrity.
public final class Tile: UnitLocation, GameObjectReadable, Ownable {

    public static let tag = "tile"

    /// Items drawn above everything else, then forests, resources and
    /// rumours (the z-index of the items).
    public static let overlayZIndex = 100
    public static let forestZIndex = 200
    public static let resourceZIndex = 400
    public static let rumourZIndex = 500

    /// The radius in which a settlement counts as near.
    public static let nearRadius = 8

    public var type: TileType?
    public private(set) var x = 0
    public private(set) var y = 0
    public weak var owner: Player?
    private var settlementHere: Settlement?
    /// A player's view of a tile (see cachedTile).
    enum CachedView {
        /// The tile itself.
        case current
        /// A detached copy of what the player last saw.
        case copy(Tile)
    }

    /// What a player knows of a native settlement on the tile.
    struct IndianSettlementInternals {
        var skill: UnitType?
        var wantedGoods: [GoodsType?]?
    }

    /// Each European player's view of this tile, by player.
    var cachedTiles: [ObjectIdentifier: CachedView] = [:]
    /// What each European player knows of the settlement here.
    var playerIndianSettlements: [ObjectIdentifier: IndianSettlementInternals] = [:]
    /// The settlement that owns this tile.
    public weak var owningSettlement: Settlement?
    public var tileItemContainer: TileItemContainer?
    public weak var region: Region?
    /// The number of tiles to the high seas, or -1 if not connected;
    /// only coastal land tiles have a non-negative count.
    public var highSeasCount = -1
    /// Whether moving from here goes to Europe, when set explicitly.
    public var moveToEurope: Bool?
    /// The terrain style, for drawing.
    public var style = 0
    /// The land or water mass this tile belongs to, or -1.
    public var contiguity = -1

    /// A new tile with a fresh identifier.
    public init(game: Game, type: TileType?, x: Int, y: Int) {
        self.type = type
        self.x = x
        self.y = y
        super.init(game: game)
    }

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    public override var xmlTagName: String {
        Tile.tag
    }

    // MARK: Basic queries

    public var isExplored: Bool {
        type != nil
    }

    public var isLand: Bool {
        type.map { !$0.isWater } ?? false
    }

    public var isForested: Bool {
        type?.isForested ?? false
    }

    /// The map of this tile's game.
    public var map: Map? {
        game?.map
    }

    public var hasSettlement: Bool {
        settlement != nil
    }

    /// The finished items.
    public var completeItems: [TileItem] {
        tileItemContainer?.completeItems ?? []
    }

    /// The nearest discoverable region containing this tile.
    public var discoverableRegion: Region? {
        region?.discoverableRegion
    }

    public var isHighSeasConnected: Bool {
        highSeasCount >= 0
    }

    /// Whether this is land next to water connected to the high seas.
    public var isCoastland: Bool {
        isLand && highSeasCount > 0
    }

    /// Whether moving from here can take a ship to the high seas.
    public var isDirectlyHighSeasConnected: Bool {
        moveToEurope ?? type?.isDirectlyHighSeasConnected ?? false
    }

    /// Whether the rivers near this tile meet at a corner.
    public var isRiverCorner: Bool {
        let tiles = surroundingTiles(0, 1).filter(\.isOnRiver)
        switch tiles.count {
        case 0, 1:
            return false
        case 2:
            return tiles[0].isAdjacent(tiles[1])
        case 3:
            return tiles[0].isAdjacent(tiles[1]) || tiles[1].isAdjacent(tiles[2])
                || tiles[2].isAdjacent(tiles[0])
        default:
            return true
        }
    }

    /// The distance to the nearest map edge.
    public var edgeDistance: Int {
        guard let map else { return 0 }
        return min(min(x, map.width - x), min(y, map.height - y))
    }

    /// The first settlement of an owner (or anyone) within a radius,
    /// nearest first, and connected by land or water if asked
    /// (getNearestSettlement).
    public func nearestSettlement(_ owner: Player?, _ radius: Int, _ same: Bool) -> Settlement? {
        guard let map = game?.map else { return nil }
        for t in map.circleTiles(self, filled: true, radius: radius <= 0 ? Constants.infinity : radius) {
            if t === self || (same && !isConnected(to: t)) { continue }
            if let settlement = t.settlement, owner == nil || owner!.owns(settlement) { return settlement }
        }
        return nil
    }

    /// Whether another tile is in the same land or water mass.
    public func isConnected(to other: Tile) -> Bool {
        contiguity == other.contiguity
    }

    /// The neighbouring tiles in a land or water mass.
    public func contiguityAdjacent(_ contiguity: Int) -> Set<Tile> {
        Set(surroundingTiles(1, 1).filter { $0.contiguity == contiguity })
    }

    /// The neighbouring tiles in a land or water mass, in the order of
    /// Java's HashSet of them.
    public func contiguityAdjacentInJavaOrder(_ contiguity: Int) -> [Tile] {
        var set = JavaHashMap<Tile, Bool>(javaHash: { $0.javaGameObjectHash })
        for t in surroundingTiles(1, 1) where t.contiguity == contiguity { _ = set.put(t, true) }
        return set.keys
    }

    /// Whether this tile is on a great river, but not on the coast.
    public var isOnRiver: Bool {
        let greatRiver = specification?.getTileType("model.tile.greatRiver")
        let ocean = specification?.getTileType("model.tile.ocean")
        var ret = type === greatRiver
        for t in surroundingTiles(1) {
            if t.type === ocean { return false }
            ret = ret || t.type === greatRiver
        }
        return ret
    }

    // MARK: Items

    public var tileImprovements: [TileImprovement] {
        tileItemContainer?.improvements ?? []
    }

    public var completeTileImprovements: [TileImprovement] {
        tileItemContainer?.completeImprovements ?? []
    }

    /// Whether a finished improvement of a type is here.  For a type
    /// that changes the tile type, whether it could have produced this
    /// tile's type.
    public func hasTileImprovement(_ type: TileImprovementType) -> Bool {
        type.isChangeType ? type.changeContainsTarget(self.type)
            : tileItemContainer?.hasImprovement(type) ?? false
    }

    public func tileImprovement(_ type: TileImprovementType?) -> TileImprovement? {
        tileItemContainer?.improvement(type)
    }

    public var hasLostCityRumour: Bool {
        lostCityRumour != nil
    }

    public var lostCityRumour: LostCityRumour? {
        tileItemContainer?.lostCityRumour
    }

    public var hasResource: Bool {
        resource != nil
    }

    public var resource: Resource? {
        tileItemContainer?.resource
    }

    public var hasRiver: Bool {
        river != nil
    }

    public var river: TileImprovement? {
        tileItemContainer?.river
    }

    public var riverStyle: TileImprovementStyle? {
        river?.style
    }

    public var hasRoad: Bool {
        road != nil
    }

    public var road: TileImprovement? {
        tileItemContainer?.road
    }

    @discardableResult
    private func addTileItem(_ item: TileItem?) -> Bool {
        guard let item, let game else { return false }
        if tileItemContainer == nil {
            tileItemContainer = TileItemContainer(game: game, tile: self)
        }
        return tileItemContainer!.tryAddTileItem(item) != nil
    }

    @discardableResult
    private func removeTileItem<T: TileItem>(_ item: T?) -> T? {
        guard let item else { return nil }
        return tileItemContainer?.removeTileItem(item)
    }

    public func addLostCityRumour(_ rumour: LostCityRumour) {
        addTileItem(rumour)
    }

    @discardableResult
    public func removeLostCityRumour() -> LostCityRumour? {
        removeTileItem(lostCityRumour)
    }

    /// Add a river and connect it as a style says.
    ///
    /// - Returns: The river, which may be an existing one it was merged
    ///   into, or nil.
    @discardableResult
    public func addRiver(_ magnitude: Int, _ conns: String?) -> TileImprovement? {
        guard magnitude != TileImprovement.noRiver, let game,
              let riverType = specification?.getTileImprovementType("model.improvement.river")
        else { return nil }
        let river = TileImprovement(game: game, tile: self, type: riverType,
                                    style: TileImprovementStyle(TileImprovement.emptyRiverStyle))
        river.turnsToComplete = 0
        river.magnitude = magnitude
        river.updateRiverConnections(conns)
        return addTileItem(river) ? self.river : nil
    }

    public func removeRiver() {
        guard let river else { return }
        river.updateRiverConnections(nil)
        removeTileItem(river)
    }

    /// Add an unfinished road.
    @discardableResult
    public func addRoad() -> TileImprovement? {
        guard let game,
              let roadType = specification?.getTileImprovementType("model.improvement.road")
        else { return nil }
        let road = TileImprovement(game: game, tile: self, type: roadType,
                                   style: TileImprovementStyle(TileImprovement.emptyRoadStyle))
        road.magnitude = 1
        return addTileItem(road) ? road : nil
    }

    @discardableResult
    public func removeRoad() -> TileImprovement? {
        guard let road else { return nil }
        road.updateRoadConnections(false)
        return removeTileItem(road)
    }

    public func addResource(_ resource: Resource) {
        addTileItem(resource)
    }

    @discardableResult
    public func removeResource() -> Resource? {
        removeTileItem(resource)
    }

    /// The turns of work an improvement needs here, or -1 if it is
    /// already here.
    public func workAmount(_ workType: TileImprovementType?) -> Int {
        guard let workType, tileImprovement(workType) == nil else { return -1 }
        return (type?.basicWorkTurns ?? 0) + workType.addWorkTurns
    }

    /// Whether an improvement of a type could be started or continued.
    public func isImprovementTypeAllowed(_ type: TileImprovementType?) -> Bool {
        guard let type, let tileType = self.type, type.isTileTypeAllowed(tileType) else { return false }
        return !(tileImprovement(type)?.isComplete ?? false)
    }

    /// Whether an improvement could be made, including the improvement
    /// it requires.
    public func isImprovementAllowed(_ tip: TileImprovement) -> Bool {
        guard let type = tip.type, isImprovementTypeAllowed(type) else { return false }
        if let req = type.requiredImprovementType, tileImprovement(req) == nil { return false }
        return !(tileImprovement(type)?.isComplete ?? false)
    }

    /// The disasters that can strike here, with their weights.
    public var disasterChoices: [RandomChoice<Disaster>] {
        (type?.disasters ?? []) + completeTileImprovements.flatMap(\.disasters)
    }

    // MARK: Geography

    public func distance(to tile: Tile) -> Int {
        map?.distance(self, tile) ?? 0
    }

    /// The direction to an adjacent tile, or nil.
    public func direction(to tile: Tile) -> Direction? {
        map?.direction(self, tile)
    }

    /// The tile one step in a direction, or nil off the map.
    public func neighbour(_ direction: Direction) -> Tile? {
        map?.adjacentTile(x, y, direction)
    }

    public func isAdjacent(_ tile: Tile?) -> Bool {
        guard let tile else { return false }
        return surroundingTiles(1, 1).contains { $0 === tile }
    }

    /// The colonies on this tile and the tiles next to it.
    public var adjacentColonies: [Colony] {
        surroundingTiles(0, 1).compactMap(\.colony)
    }

    public var isPolar: Bool {
        map?.isPolar(self) ?? false
    }

    /// Whether this is land surrounded by land.
    public var isLandLocked: Bool {
        isLand && surroundingTiles(1, 1).allSatisfy(\.isLand)
    }

    /// Whether a neighbour is land where this is water, or the reverse.
    public var isShore: Bool {
        surroundingTiles(1, 1).contains { $0.isLand != isLand }
    }

    /// Whether the map generator could raise hills here.
    public var isGoodHillTile: Bool {
        // Not too close to water, which leaves good colony sites on shore.
        isLand && !(type?.isElevation ?? false) && surroundingTiles(1, 1).allSatisfy(\.isLand)
    }

    /// Whether the map generator could raise mountains here.
    public var isGoodMountainTile: Bool {
        // Not too close to an existing mountain range.
        isGoodHillTile && !surroundingTiles(1, 3).contains { $0.type?.isMountains ?? false }
    }

    /// Whether the map generator could start a river here.
    public func isGoodRiverTile(_ riverType: TileImprovementType) -> Bool {
        // Not too close to the sea.
        type.map(riverType.isTileTypeAllowed) ?? false && surroundingTiles(1, 1).allSatisfy(\.isLand)
    }

    /// The tiles within a range, nearest first, not including this one.
    public func surroundingTiles(_ range: Int) -> Map.CircleTiles {
        map!.circleTiles(self, filled: true, radius: range)
    }

    /// The tiles at distances from rangeMin to rangeMax, nearest first;
    /// this tile is included if rangeMin is 0.
    public func surroundingTiles(_ rangeMin: Int, _ rangeMax: Int) -> [Tile] {
        var result: [Tile] = []
        if rangeMin > rangeMax || rangeMin < 0 { return result }
        if rangeMin == 0 { result.append(self) }
        if rangeMax > 0 { result += surroundingTiles(rangeMax) }
        if rangeMin > 1 {
            // Java removes the first occurrence of each nearer tile.
            for t in surroundingTiles(rangeMin - 1) {
                if let i = result.firstIndex(where: { $0 === t }) { result.remove(at: i) }
            }
        }
        return result
    }

    public var hasUnexploredAdjacent: Bool {
        !surroundingTiles(1, 1).allSatisfy(\.isExplored)
    }

    /// The number of neighbours that are land if this is, or water if
    /// this is.
    public var availableAdjacentCount: Int {
        surroundingTiles(1, 1).filter { $0.isLand == isLand }.count
    }

    /// The defence multiplier of the tile type.
    public var defenceValue: Double {
        guard let type else { return 0 }
        return Double(FeatureContainer.applyModifiers(1, turn: nil, type.defenceModifiers))
    }

    /// The tile type's defence bonus as a percentage.
    public var defenceBonusPercentage: Int {
        Int(JavaMath.toInt(type!.apply(100, turn: game?.turn, Modifier.defence))) - 100
    }

    /// An enemy offensive unit on a tile owned by a settlement whose
    /// owner is at war with it, or nil.
    public var occupyingUnit: Unit? {
        guard let unit = firstUnit, let settlementOwner = owningSettlement?.owner,
              unit.owner !== settlementOwner, unit.owner?.atWar(with: settlementOwner) ?? false
        else { return nil }
        return unitList.first(where: \.isOffensiveUnit)
    }

    public var isOccupied: Bool {
        occupyingUnit != nil
    }

    /// Whether the colony owning this tile has a unit working it.
    public var isInUse: Bool {
        (owningSettlement as? Colony)?.isTileInUse(self) ?? false
    }

    /// Change the tile type, removing items the new type does not allow
    /// and any settlement left in the water, and update the colony
    /// working it.
    public func changeType(_ type: TileType?) {
        self.type = type
        tileItemContainer?.removeIncompatibleImprovements()
        if !isLand { settlement = nil }
        updateColonyTiles()
    }

    /// Update the production of the colony tile working this tile.
    private func updateColonyTiles() {
        let wl = (game?.allColonies(excluding: nil) ?? [])
            .lazy.flatMap(\.availableWorkLocations).first { $0.workTile === self }
        wl?.updateProductionType()
    }

    /// Change the settlement owning this tile, keeping the settlements'
    /// lists of owned tiles right.
    public func changeOwningSettlement(_ settlement: Settlement?) {
        owningSettlement?.removeTile(self)
        owningSettlement = settlement
        settlement?.addTile(self)
    }

    /// Change the owner and the owning settlement.
    public func changeOwnership(_ player: Player?, _ settlement: Settlement?) {
        owner = player
        changeOwningSettlement(settlement)
    }

    // MARK: Production

    /// Whether this tile can produce goods, through its type or items.
    public func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        (type?.canProduce(goodsType, unitType) ?? false)
            || (tileItemContainer?.canProduce(goodsType, unitType) ?? false)
    }

    /// The basic production of farmed goods, before modifiers.
    public func baseProduction(_ productionType: ProductionType?, _ goodsType: GoodsType?,
                               _ unitType: UnitType?) -> Int {
        guard let type, let goodsType, goodsType.isFarmed else { return 0 }
        return max(0, type.baseProduction(productionType, goodsType, unitType))
    }

    /// The production of goods by a unit type here (or with no unit, as
    /// a colony center), with no colony or owner modifiers.
    public func potentialProduction(_ goodsType: GoodsType, _ unitType: UnitType?) -> Int {
        let tpc = TileProductionCalculator(owner: nil, colonyProductionBonus: 0)
        let productionType = ProductionType.bestProductionType(
            goodsType, in: type!.availableProductionTypes(unattended: unitType == nil))
        let pi = tpc.basicProductionInfo(self, turn: game?.turn,
                                         WorkerAssignment(unitType, productionType),
                                         colonyCenterTile: unitType == nil)
        return pi.production.first { $0.type === goodsType }?.amount ?? 0
    }

    /// The production modifiers of the items, where this tile can
    /// produce the goods.
    public func productionModifiers(_ goodsType: GoodsType?, _ unitType: UnitType?) -> [Modifier] {
        guard let tileItemContainer, canProduce(goodsType, unitType) else { return [] }
        return tileItemContainer.productionModifiers(goodsType, unitType)
    }

    private func maximumPotential(_ goodsType: GoodsType, _ unitType: UnitType?,
                                  _ tileType: TileType) -> Int {
        var potential = Float(tileType.potentialProduction(goodsType, unitType))
        if tileType === type, let resource {
            // The resource only counts if the type does not change.
            potential = Float(resource.applyBonus(goodsType, unitType, Int(JavaMath.toInt(potential))))
        }
        // Apply every possible improvement that is not natural.
        if canProduce(goodsType, unitType) {
            for ti in specification?.tileImprovementTypeList ?? []
            where !ti.isNatural && ti.isTileTypeAllowed(tileType) && ti.bonus(goodsType) > 0 {
                potential = ti.productionModifier(goodsType)!.applyTo(potential)
            }
        }
        return Int(JavaMath.toInt(potential))
    }

    /// The production of goods here with every possible improvement,
    /// including those that change the tile type.
    public func maximumPotential(_ goodsType: GoodsType, _ unitType: UnitType?) -> Int {
        guard let type else { return 0 }
        let improvements = specification?.tileImprovementTypeList ?? []
        let tileTypes = [type] + improvements.compactMap { ti in
            ti.isNatural ? nil : ti.change(type)
        }
        return tileTypes.map { maximumPotential(goodsType, unitType, $0) }.max() ?? Int(Int32.min)
    }

    /// The goods this tile produces unattended, most first.
    public var sortedAutoPotential: [AbstractGoods] {
        sortedPotential(nil, useExperts: false)
    }

    /// The goods this tile produces with an expert for each, most first.
    public var sortedPotential: [AbstractGoods] {
        sortedPotential(nil, useExperts: true)
    }

    /// The goods a unit type produces here, most first.
    public func sortedPotential(_ unitType: UnitType?) -> [AbstractGoods] {
        sortedPotential(unitType, useExperts: false)
    }

    /// The goods a unit produces here, most valuable first in its
    /// owner's market (or most first, without one).
    public func sortedPotential(_ unit: Unit) -> [AbstractGoods] {
        guard let market = unit.owner?.market else { return sortedPotential(unit.type) }
        return sortedPotential(unit.type, useExperts: false) { market.compareSalePrice($0, $1) }
    }

    private func sortedPotential(_ unitType: UnitType?, useExperts: Bool,
                                 _ compare: (AbstractGoods, AbstractGoods) -> Int
                                     = AbstractGoods.compareDescendingAmount) -> [AbstractGoods] {
        // Defend against calls while partially read.
        guard type != nil, let spec = specification else { return [] }
        // Every farmed goods type, as a resource may give the tile goods
        // its type does not produce.
        let goods: [AbstractGoods] = spec.farmedGoodsTypeList.compactMap { gt in
            let ut = unitType ?? (useExperts ? spec.expert(producing: gt) : nil)
            let amount = potentialProduction(gt, ut)
            return amount > 0 ? AbstractGoods(gt, amount) : nil
        }
        return goods.stableSorted { compare($0, $1) < 0 }
    }

    /// The best unattended food production.
    public var bestFoodProduction: AbstractGoods? {
        let outputs = (type?.availableProductionTypes(unattended: true) ?? []).flatMap(\.outputs)
        var best: AbstractGoods?
        var bestAmount = 0
        for ag in outputs where ag.type?.isFoodType ?? false {
            let amount = ag.type.map { potentialProduction($0, nil) } ?? 0
            if best == nil || amount > bestAmount {
                best = ag
                bestAmount = amount
            }
        }
        return best
    }

    /// The food an expert could produce here with every improvement.
    public var maximumPotentialFoodProductionWithExpert: AbstractGoods? {
        guard let spec = specification else { return nil }
        var best: AbstractGoods?
        for gt in spec.foodGoodsTypeList {
            let ag = AbstractGoods(gt, maximumPotential(gt, spec.expert(producing: gt)))
            if best == nil || ag.amount > best!.amount { best = ag }
        }
        return best
    }

    // MARK: Location

    /// The settlement on this tile.
    public override var settlement: Settlement? {
        get { settlementHere }
        set { settlementHere = newValue }
    }

    public override var tile: Tile? {
        self
    }

    /// Add a tile item, or a unit (which becomes active).
    @discardableResult
    public override func add(_ locatable: any Locatable) -> Bool {
        if let item = locatable as? TileItem { return addTileItem(item) }
        if let unit = locatable as? Unit {
            guard super.add(unit) else { return false }
            unit.setState(.active)
            return true
        }
        return super.add(locatable)
    }

    @discardableResult
    public override func remove(_ locatable: any Locatable) -> Bool {
        if let item = locatable as? TileItem { return removeTileItem(item) === item }
        return super.remove(locatable)
    }

    public override func contains(_ locatable: any Locatable) -> Bool {
        if let item = locatable as? TileItem { return tileItemContainer?.contains(item) ?? false }
        return super.contains(locatable)
    }

    /// Units that can enter, and improvements the type allows.
    public override func canAdd(_ locatable: any Locatable) -> Bool {
        if let unit = locatable as? Unit { return unit.isTileAccessible(self) }
        if let ti = locatable as? TileImprovement {
            return type.map { ti.type?.isTileTypeAllowed($0) ?? false } ?? false
        }
        return false
    }

    public override func up() -> any Location {
        if let settlement { return settlement }
        return self
    }

    public var position: Map.Position {
        Map.Position(x, y)
    }

    /// Tiles rank by position, row by row.
    public override var rank: Int {
        x + y * map!.width
    }

    // MARK: FreeColObject

    /// Scopes naming a type match the tile type.
    public override var scopeType: FreeColSpecObjectType? {
        type
    }

    /// The tile methods scopes can name.
    public override func scopeMethodValue(_ methodName: String) -> String? {
        switch methodName {
        case "isLand": "\(isLand)"
        case "isForested": "\(isForested)"
        case "isExplored": "\(isExplored)"
        case "isCoastland": "\(isCoastland)"
        case "isPolar": "\(isPolar)"
        case "hasSettlement": "\(hasSettlement)"
        case "isHighSeasConnected": "\(isHighSeasConnected)"
        default: super.scopeMethodValue(methodName)
        }
    }

    /// A tile's abilities are its type's.
    public override func abilities(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                                   turn: Turn? = nil) -> [Ability] {
        type?.abilities(id, for: target, turn: turn) ?? []
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let game = game!
        x = xr.attribute("x", default: 0)
        y = xr.attribute("y", default: 0)
        type = try specification.flatMap { try xr.getType($0, "type", TileType.self) }
        guard type != nil else {
            // Unexplored
            style = 0
            highSeasCount = -1
            owner = nil
            region = nil
            moveToEurope = nil
            contiguity = -1
            owningSettlement = nil
            return
        }
        style = xr.attribute("style", default: 0)
        if let str = xr.attribute("connected", default: nil as String?), !str.isEmpty {
            highSeasCount = JavaString.parseInt(str).map(Int.init) ?? -1
        } else {
            highSeasCount = -1
        }
        owner = try xr.findFreeColGameObject(game, "owner", Player.self, required: false)
        region = try xr.findFreeColGameObject(game, "region", Region.self, required: false)
        moveToEurope = xr.hasAttribute("moveToEurope") ? xr.attribute("moveToEurope", default: false) : nil
        contiguity = xr.attribute("contiguity", default: -1)
        // The map adds tiles to their settlements, once all are read.
        owningSettlement = try xr.getLocationAttribute(game, "owningSettlement", make: true) as? Settlement
    }

    // MARK: Writing XML

    /// Write the tile as a client sees it: its view of the tile if it
    /// has one, the tile if explored, or just the position.
    public override func toXML(_ xw: FreeColXMLWriter, tag: String) {
        guard let player = xw.clientPlayerObject else {
            internalToXML(xw, tag)
            return
        }
        if let tile = cachedTile(player) {
            tile.internalToXML(xw, tag)
        } else if isExploredBy(player) {
            internalToXML(xw, tag)
        } else {
            xw.writeStartElement(tag)
            xw.writeAttribute(FreeColObject.idTag, id: id)
            xw.writeAttribute("x", x)
            xw.writeAttribute("y", y)
            xw.writeEndElement()
        }
    }

    private func internalToXML(_ xw: FreeColXMLWriter, _ tag: String) {
        xw.writeStartElement(tag)
        writeAttributes(xw)
        writeChildren(xw)
        xw.writeEndElement()
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("x", x)
        xw.writeAttribute("y", y)
        xw.writeAttribute("type", type)
        xw.writeAttribute("owner", owner)
        if let owningSettlement {
            if owningSettlement.isDisposed || owningSettlement.id == nil {
                self.owningSettlement = nil
            } else {
                xw.writeAttribute("owningSettlement", owningSettlement)
            }
        }
        xw.writeAttribute("style", style)
        xw.writeAttribute("region", region)
        if let moveToEurope { xw.writeAttribute("moveToEurope", moveToEurope) }
        if highSeasCount >= 0 { xw.writeAttribute("connected", highSeasCount) }
        if contiguity >= 0 { xw.writeAttribute("contiguity", contiguity) }
    }

    /// The units (if the client can see them), the settlement, the
    /// items and, in a saved game, each player's view.  A view of a
    /// tile with a native settlement is saved as a copy even when it is
    /// the tile itself, so the player's knowledge of the settlement is
    /// kept; writing the tile for that player gives the same copy.
    public override func writeChildren(_ xw: FreeColXMLWriter) {
        let player = xw.clientPlayerObject
        if (player == nil || player!.canSee(self))
            && (settlement == nil || xw.validFor(settlement?.owner)) {
            super.writeChildren(xw)
        }
        settlement?.toXML(xw)
        tileItemContainer?.toXML(xw)
        guard xw.validForSave, let game else { return }
        for p in game.liveEuropeanPlayers {
            guard let t = cachedTile(p) else { continue }
            let copied = t !== self || indianSettlement != nil
            xw.writeStartElement("cachedTile")
            xw.writeAttribute("player", p)
            xw.writeAttribute("copied", copied)
            if copied {
                let ws = xw.replaceScope(.toClient(p))
                t.internalToXML(xw, Tile.tag)
                xw.replaceScope(ws)
            }
            xw.writeEndElement()
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        settlementHere = nil
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let game = game!
        switch xr.localName {
        case "cachedTile":
            // A player's view of the tile: the tile itself, or a copy
            // of what the player last saw, read without registering it.
            let player = try xr.findFreeColGameObject(game, "player", Player.self, required: true)
            if xr.attribute("copied", default: false) {
                let intern = xr.replaceScope(intern: false)
                defer { xr.replaceScope(intern: intern) }
                var copy: Tile?
                while try xr.moreTags() {
                    if copy == nil && xr.localName == Tile.tag {
                        copy = try xr.readFreeColObject(game, Tile.self)
                    } else {
                        try xr.expectTag(Tile.tag)
                    }
                }
                if let player, let copy {
                    // Java's workaround for BR#2618: a copied colony
                    // must show some units.
                    if let colony = copy.colony, colony.apparentUnitCount <= 0 {
                        xr.warn("Copied colony \(colony.id ?? "null") display unit count set to 1")
                        colony.displayUnitCount = 1
                    }
                    if let settlement = copy.indianSettlement {
                        setIndianSettlementInternals(player, settlement.learnableSkill, settlement.wantedGoods)
                    } else {
                        removeIndianSettlementInternals(player)
                    }
                    setCachedTile(player, copy)
                }
            } else {
                if let player { setCachedTile(player, self) }
                try xr.closeTag("cachedTile")
            }
        case "playerExploredTile":
            // @compat 0.11.0: no longer read, but the player has a view.
            let player = try xr.findFreeColGameObject(game, "player", Player.self, required: true)
            try xr.swallowTag(xr.localName)
            if let player { setCachedTile(player, self) }
        case Colony.tag:
            settlementHere = try xr.readFreeColObject(game, Colony.self)
        case IndianSettlement.tag:
            settlementHere = try xr.readFreeColObject(game, IndianSettlement.self)
        case TileItemContainer.tag, TileItemContainer.oldTag:
            tileItemContainer = try xr.readFreeColObject(game, TileItemContainer.self)
        default:
            try super.readChild(xr)
        }
    }

    // MARK: Description

    /// "x,y-suffix", such as "3,4-plains".
    public override var shortDescription: String {
        "\(x),\(y)-\(type?.suffix ?? "?")"
    }

    public override var description: String {
        "[\(id ?? "null") \(type?.suffix ?? "unknown") \(x),\(y)"
            + (settlement.map { " \($0.name ?? "null")" } ?? "") + "]"
    }
}

extension Sequence {
    /// The elements sorted, keeping the order of equal elements (as
    /// Java's sorts do).
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            areInIncreasingOrder(a.element, b.element)
                || (!areInIncreasingOrder(b.element, a.element) && a.offset < b.offset)
        }.map(\.element)
    }
}

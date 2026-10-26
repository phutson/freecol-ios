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

/// A colony or native settlement (common/model/Settlement).
///
/// The settlement holds the units in it and its goods (as a
/// GoodsLocation), and its features; its owner and tile are weak
/// references, and so are the tiles it owns (the map holds them).
///
/// Not yet ported: copyIn and checkIntegrity.  Defence
/// and plunder are in Defence.swift.
open class Settlement: GoodsLocation, Ownable {

    /// The food needed to grow a new colonist.
    public static let foodPerColonist = 200

    private final class WeakTile {
        weak var tile: Tile?
        init(_ tile: Tile) { self.tile = tile }
    }

    public private(set) var type: SettlementType?
    public var name: String?
    public private(set) weak var owner: Player?
    private weak var tileHere: Tile?
    private var ownedTileList: [WeakTile] = []
    private let features = FeatureContainer()

    public override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// A new settlement of the owner's usual (not capital) type.
    ///
    /// - Parameters:
    ///   - game: The game, which issues the identifier.
    ///   - owner: The owner.
    ///   - name: The settlement's name.
    ///   - tile: Where it is.
    public init(game: Game, owner: Player, name: String?, tile: Tile) {
        super.init(game: game)
        self.owner = owner
        self.name = name
        tileHere = tile
        changeType(owner.nationType?.settlementType(capital: false))
    }

    public func setType(_ newType: SettlementType?) {
        type = newType
    }

    /// The immigration points made here (only colonies make any).
    open var immigration: Int {
        0
    }

    /// The liberty made here (only colonies make any).
    open var liberty: Int {
        0
    }

    public var isLandLocked: Bool {
        tile?.isLandLocked ?? false
    }

    private func changeType(_ newType: SettlementType?) {
        if let type { removeFeatures(of: type) }
        setType(newType)
        if let newType { addFeatures(of: newType) }
    }

    public var isCapital: Bool {
        type?.isCapital ?? false
    }

    public func setCapital(_ capital: Bool) {
        if isCapital != capital {
            changeType(owner?.nationType?.settlementType(capital: capital))
        }
    }

    /// The tiles this settlement owns, in the order of Java's copy of
    /// its HashSet (getOwnedTiles, which is `new HashSet<>(set)`: a table
    /// of at least 16, filled in the set's order).  The set is rebuilt
    /// from the order the tiles were added in, so it has the capacity of
    /// its present size, not of the largest it ever was (which Java's
    /// keeps).
    public var ownedTiles: [Tile] {
        var set = JavaHashMap<Tile, Bool>(javaHash: { $0.javaGameObjectHash })
        for t in ownedTileList.compactMap(\.tile) { _ = set.put(t, true) }
        let n = set.count
        var copy = JavaHashMap<Tile, Bool>(initialCapacity: max(Int(Float(n) / 0.75) + 1, 16),
                                           javaHash: { $0.javaGameObjectHash })
        for t in set.keys { _ = copy.put(t, true) }
        return copy.keys
    }

    public func addTile(_ tile: Tile) {
        if !ownedTileList.contains(where: { $0.tile === tile }) { ownedTileList.append(WeakTile(tile)) }
    }

    public func removeTile(_ tile: Tile) {
        ownedTileList.removeAll { $0.tile === tile }
    }

    /// How far the settlement claims land.
    public var radius: Int {
        type?.claimableRadius ?? 0
    }

    public var lineOfSight: Int {
        Int(JavaMath.toInt(apply(Float(type?.visibleRadius ?? 0), turn: game?.turn,
                                 Modifier.lineOfSightBonus)))
    }

    /// The tiles this settlement can see.
    public var visibleTileSet: Set<Tile> {
        guard let tile else { return [] }
        return Set(tile.surroundingTiles(0, lineOfSight))
    }

    /// Whether the settlement is next to water connected to the high
    /// seas.
    public var isConnectedPort: Bool {
        tile?.surroundingTiles(1, 1).contains { !$0.isLand && $0.isHighSeasConnected } ?? false
    }

    /// The lowest high seas count of the neighbouring sea tiles.
    public var highSeasCount: Int {
        var best: Tile?
        for t in tile?.surroundingTiles(1, 1) ?? [] where !t.isLand && t.highSeasCount >= 0 {
            if best == nil || t.highSeasCount < best!.highSeasCount { best = t }
        }
        return best?.highSeasCount ?? Constants.infinity
    }

    /// What the units here consume of a goods type.
    open func consumption(of goodsType: GoodsType) -> Int {
        max(0, unitList.reduce(0) { $0 + ($1.type?.consumption(of: goodsType) ?? 0) })
    }

    public func consumption(of goodsTypes: [GoodsType]?) -> Int {
        (goodsTypes ?? []).reduce(0) { $0 + consumption(of: $1) }
    }

    public var foodConsumption: Int {
        consumption(of: specification?.foodGoodsTypeList)
    }

    /// Whether goods can be spared, keeping enough to breed.
    open func canProvideGoods(_ goods: [AbstractGoods]) -> Bool {
        goods.allSatisfy { ag in
            guard let type = ag.type else { return false }
            var available = goodsCount(type)
            if type.breedingNumber != Constants.infinity { available -= type.breedingNumber }
            return available >= ag.amount
        }
    }

    public var warehouseCapacity: Int {
        goodsCapacity
    }

    public var canBombardEnemyShip: Bool {
        !isLandLocked && hasAbility(Ability.bombardShips)
    }

    /// The units here and on the settlement's tile.
    public var allUnitsList: [Unit] {
        unitList + (tile?.unitList ?? [])
    }

    // MARK: Placing

    /// Put the settlement on its tile: claim the tile (and, if maximal,
    /// all the tiles the owner can claim around it) and add a virtual
    /// road.
    public func placeSettlement(_ maximal: Bool) {
        guard let tile, let owner else { return }
        let tiles = maximal ? owner.claimableTiles(tile, radius) : [tile]
        tile.settlement = self
        for t in tiles { t.changeOwnership(owner, self) }
        if !tile.hasRoad, let road = tile.addRoad() {
            road.turnsToComplete = 0
            road.isVirtual = true
            road.updateRoadConnections(true)
        }
    }

    /// Give the settlement and its tiles to another player, of the same
    /// kind (native or European).  The units in it are not changed.
    public func changeOwner(_ newOwner: Player) {
        let oldOwner = owner
        precondition(newOwner.isIndian == (oldOwner?.isIndian ?? newOwner.isIndian),
                     "Can not transfer settlements between native and European players: "
                     + "\(oldOwner?.description ?? "null") -> \(newOwner)")
        game?.notifyOwnerChanged(self, oldOwner, newOwner)
        owner = newOwner
        game?.checkOwners(self, oldOwner: oldOwner)
        for t in ownedTiles { t.changeOwnership(newOwner, self) }
    }

    /// Take the settlement off the map, releasing its tiles and
    /// removing its virtual road.
    public func exciseSettlement() {
        guard let settlementTile = tile else { return }
        for t in ownedTiles { t.changeOwnership(nil, nil) }
        settlementTile.settlement = nil
        settlementTile.changeOwnership(nil, nil)
        if let road = settlementTile.road, road.isVirtual { settlementTile.removeRoad() }
    }

    /// The better military role a unit could take with the goods here,
    /// if any.
    public func canImproveUnitMilitaryRole(_ unit: Unit) -> Role? {
        guard let spec = specification else { return nil }
        var military = spec.militaryRolesList
        if let role = unit.role, let index = military.firstIndex(where: { $0 === role }) {
            military = Array(military[..<index])
        }
        return unit.availableRoles(military).first { canProvideGoods(unit.goodsDifference($0, 1)) }
    }

    // MARK: Disposal

    open override func disposeResources() {
        // Java keeps the owner, as display code may still need it.
        owner?.removeSettlement(self)
        super.disposeResources()
    }

    // MARK: For subclasses (abstract in Java)

    open var sonsOfLiberty: Int { fatalError("abstract") }

    open var upkeep: Int { fatalError("abstract") }

    open func totalProduction(of goodsType: GoodsType) -> Int { fatalError("abstract") }

    open func hasContacted(_ player: Player?) -> Bool { fatalError("abstract") }

    // MARK: Features

    public override var featureContainer: FeatureContainer? {
        features
    }

    /// Scopes naming a type match the settlement type.
    open override var scopeType: FreeColSpecObjectType? {
        type
    }

    open override func scopeMethodValue(_ methodName: String) -> String? {
        switch methodName {
        case "isConnectedPort": "\(isConnectedPort)"
        case "isCapital": "\(isCapital)"
        case "isLandLocked": "\(isLandLocked)"
        default: super.scopeMethodValue(methodName)
        }
    }

    // MARK: Location

    public override var tile: Tile? {
        tileHere
    }

    public override var settlement: Settlement? {
        self
    }

    /// Colonies and native settlements are their own top location.
    public override func up() -> any Location {
        self
    }

    /// A settlement ranks as its tile.
    public final override var rank: Int {
        LocationRank.of(tile)
    }

    public override var shortDescription: String {
        name ?? "null"
    }

    /// Only the owner's units may enter, and goods can always be added
    /// (any excess is removed at the end of the turn).
    /// Goods here cost nothing, if they are here.
    ///
    /// - Throws: FreeColException if some are missing.
    open override func priceGoods(_ goods: [AbstractGoods]) throws -> Int {
        if let missing = goods.first(where: { goodsCount($0.type) < $0.amount }) {
            throw FreeColException("Goods missing: \(missing)")
        }
        return 0
    }

    /// Equip a unit from the settlement's goods.
    @discardableResult
    open override func equipForRole(_ unit: Unit, _ role: Role, _ roleCount: Int) -> Bool {
        guard unit.roleIsAvailable(role) else { return false }
        let req = unit.goodsDifference(role, roleCount)
        guard (try? priceGoods(req)) != nil else { return false }
        for ag in req {
            if let type = ag.type { addGoods(type, -ag.amount) }
        }
        unit.changeRole(role, roleCount)
        return true
    }

    open override func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        if let unit = locatable as? Unit {
            if unit.owner !== owner { return .ownedByEnemy }
        } else if locatable is Goods {
            return .none
        }
        return super.noAddReason(locatable)
    }

    // MARK: Writing XML

    /// The name is written by the subclasses.
    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("owner", owner)
        xw.writeAttribute("tile", tileHere)
        xw.writeAttribute("settlementType", type)
    }

    /// The contents and features, only for the owner.
    open override func writeChildren(_ xw: FreeColXMLWriter) {
        guard xw.validFor(owner) else { return }
        super.writeChildren(xw)
        for ability in sortedAbilities where ability.isIndependent { ability.toXML(xw) }
        let turn = game?.turn
        for modifier in sortedModifiers {
            if modifier.hasIncrement && modifier.isOutOfDate(turn) { continue }
            if modifier.isIndependent { modifier.toXML(xw) }
        }
    }

    // MARK: Reading XML

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let game = game!
        name = xr.attribute("name", default: nil as String?)
        let oldOwner = owner
        owner = try xr.findFreeColGameObject(game, "owner", Player.self, required: true)
        tileHere = try xr.findFreeColGameObject(game, "tile", Tile.self, required: true)
        type = owner?.nationType?.settlementType(id: xr.attribute("settlementType", default: nil as String?))
        if xr.shouldIntern { game.checkOwners(self, oldOwner: oldOwner) }
    }

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        features.clear()
        try super.readChildren(xr)
        // The type's features are not saved, so add them back.
        if let type { addFeatures(of: type) }
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case Ability.tag:
            let ability = try Ability(xr, specification: specification)
            if ability.isIndependent { addAbility(ability) }
        case Modifier.tag:
            let modifier = try Modifier(xr, specification: specification)
            if modifier.isIndependent { addModifier(modifier) }
        default:
            try super.readChild(xr)
        }
    }
}

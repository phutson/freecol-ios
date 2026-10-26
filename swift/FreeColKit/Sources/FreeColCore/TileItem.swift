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

/// Something on a tile: an improvement, a resource or a rumour
/// (common/model/TileItem).
///
/// The tile's item container holds its items; the reference back to
/// the tile is weak.
///
open class TileItem: FreeColGameObject, Locatable {

    /// The tile this item is on.
    public weak var tile: Tile?

    /// A new item with a fresh identifier.
    public init(game: Game, tile: Tile) {
        self.tile = tile
        super.init(game: game)
    }

    /// An item that is about to be read.
    public init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    // MARK: Locatable

    public var location: (any Location)? {
        tile
    }

    /// Move to a tile, or nowhere.
    @discardableResult
    public func setLocation(_ newLocation: (any Location)?) -> Bool {
        guard newLocation == nil || newLocation is Tile else {
            preconditionFailure("newLocation is not a Tile: \(newLocation!)")
        }
        tile = newLocation as? Tile
        return true
    }

    public var isInEurope: Bool {
        false
    }

    public var spaceTaken: Int {
        0
    }

    // MARK: For subclasses

    /// Where this item is drawn, and so where it sits in the container:
    /// higher first.
    open var zIndex: Int { fatalError("abstract") }

    /// Whether this item can be on a tile type.
    open func isTileTypeAllowed(_ tileType: TileType) -> Bool { fatalError("abstract") }

    /// The production potential with this item's bonus applied.
    open func applyBonus(_ goodsType: GoodsType, _ unitType: UnitType?, _ potential: Int) -> Int {
        fatalError("abstract")
    }

    /// Whether this item lets a tile produce goods.
    open func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        fatalError("abstract")
    }

    /// The production modifiers this item gives.
    open func productionModifiers(_ goodsType: GoodsType?, _ unitType: UnitType?) -> [Modifier] {
        fatalError("abstract")
    }

    /// Whether this item is natural, such as a river.
    open var isNatural: Bool { fatalError("abstract") }

    /// Whether this item is finished.
    open var isComplete: Bool { fatalError("abstract") }

    /// The map layer this item belongs to.
    open var layer: Map.Layer { fatalError("abstract") }
}

/// The items on a tile, highest z-index first
/// (common/model/TileItemContainer).
///
/// Not yet ported: invalidating the cache of a colony using the tile,
/// which comes with Colony, and checkIntegrity.
public final class TileItemContainer: FreeColGameObject, GameObjectReadable {

    public static let tag = "tileItemContainer"
    // @compat 0.11.3
    public static let oldTag = "tileitemcontainer"

    /// The tile holding this container.
    public private(set) weak var tile: Tile?

    private var tileItems: [TileItem] = []

    /// A new empty container with a fresh identifier.
    public init(game: Game, tile: Tile) {
        self.tile = tile
        super.init(game: game)
    }

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    public override var xmlTagName: String {
        TileItemContainer.tag
    }

    /// All the items, highest first.
    public var items: [TileItem] {
        tileItems
    }

    /// Replace all the items.
    public func setTileItems(_ items: [TileItem]) {
        tileItems = items
    }

    /// Add an item below the items with the same or a higher z-index.
    private func addTileItem(_ item: TileItem) {
        let i = tileItems.firstIndex { $0.zIndex < item.zIndex } ?? tileItems.count
        tileItems.insert(item, at: i)
    }

    /// Add an item.  An improvement of a type already here is merged
    /// into the existing one, which keeps the larger magnitude.
    ///
    /// - Returns: The item added or merged into, or nil.
    @discardableResult
    public func tryAddTileItem(_ item: TileItem?) -> TileItem? {
        guard let item else { return nil }
        if let newTip = item as? TileImprovement {
            for oldItem in tileItems {
                guard let oldTip = oldItem as? TileImprovement else { continue }
                if oldTip.type?.id == newTip.type?.id {
                    if oldTip.magnitude < newTip.magnitude {
                        oldTip.magnitude = newTip.magnitude
                        oldTip.style = newTip.style
                        oldTip.isVirtual = newTip.isVirtual
                    }
                    return oldItem
                } else if oldItem.zIndex > item.zIndex {
                    break // The new item goes under the old one, no merging
                }
            }
        }
        addTileItem(item)
        return item
    }

    /// Remove an item.
    ///
    /// - Returns: The item, or nil if it was not here.
    @discardableResult
    public func removeTileItem<T: TileItem>(_ item: T?) -> T? {
        guard let item, let i = tileItems.firstIndex(where: { $0 === item }) else { return nil }
        tileItems.remove(at: i)
        item.tile = nil
        return item
    }

    /// Remove every item of a class.
    public func removeAll<T: TileItem>(_ type: T.Type) {
        tileItems.removeAll { $0 is T }
    }

    /// The finished items.
    public var completeItems: [TileItem] {
        tileItems.filter(\.isComplete)
    }

    /// The improvement of a type, finished or not.
    public func improvement(_ type: TileImprovementType?) -> TileImprovement? {
        tileItems.lazy.compactMap { $0 as? TileImprovement }.first { $0.type === type }
    }

    /// All the improvements.
    public var improvements: [TileImprovement] {
        tileItems.compactMap { $0 as? TileImprovement }
    }

    /// The finished improvements.
    public var completeImprovements: [TileImprovement] {
        improvements.filter(\.isComplete)
    }

    public var lostCityRumour: LostCityRumour? {
        tileItems.lazy.compactMap { $0 as? LostCityRumour }.first
    }

    public var resource: Resource? {
        tileItems.lazy.compactMap { $0 as? Resource }.first
    }

    public var road: TileImprovement? {
        improvements.first(where: \.isRoad)
    }

    public var river: TileImprovement? {
        improvements.first(where: \.isRiver)
    }

    /// Whether a finished improvement of a type is here.
    public func hasImprovement(_ type: TileImprovementType?) -> Bool {
        improvement(type)?.isComplete ?? false
    }

    /// Remove the items the tile's type no longer allows, after the
    /// type changes.  A river left on land loses its connections first.
    public func removeIncompatibleImprovements() {
        guard let tileType = tile?.type else { return }
        if let river, !river.isTileTypeAllowed(tileType), !tileType.isWater {
            river.updateRiverConnections(nil)
        }
        tileItems.removeAll { !$0.isTileTypeAllowed(tileType) }
    }

    /// A potential with every item's bonus (or only the natural ones)
    /// applied in turn.
    public func totalBonusPotential(_ goodsType: GoodsType, _ unitType: UnitType?,
                                    _ potential: Int, onlyNatural: Bool) -> Int {
        tileItems.filter { !onlyNatural || $0.isNatural }
            .reduce(potential) { $1.applyBonus(goodsType, unitType, $0) }
    }

    /// The production modifiers of all the items.
    public func productionModifiers(_ goodsType: GoodsType?, _ unitType: UnitType?) -> [Modifier] {
        tileItems.flatMap { $0.productionModifiers(goodsType, unitType) }
    }

    /// Whether any item lets the tile produce goods.
    public func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        tileItems.contains { $0.canProduce(goodsType, unitType) }
    }

    /// The cost of moving onto the target tile from a neighbour, as
    /// lowered by finished improvements such as roads and rivers.
    public func moveCost(from fromTile: Tile, to targetTile: Tile, _ basicMoveCost: Int) -> Int {
        var moveCost = basicMoveCost
        for item in completeImprovements {
            guard let direction = targetTile.direction(to: fromTile) else { return Constants.infinity }
            moveCost = min(moveCost, item.moveCost(direction, moveCost))
        }
        return moveCost
    }

    /// Replace the items with copies of another container's items, up
    /// to a layer.  Only natural improvements are copied below ALL.
    public func copyFrom(_ other: TileItemContainer, layer: Map.Layer) {
        guard let game, let tile, let spec = specification else { return }
        var result: [TileItem] = []
        for item in other.tileItems where layer >= item.layer {
            if let resource = item as? Resource {
                if let type = spec.getResourceType(resource.type?.id) {
                    result.append(Resource(game: game, tile: tile, type: type,
                                           quantity: resource.quantity))
                }
            } else if let rumour = item as? LostCityRumour {
                result.append(LostCityRumour(game: game, tile: tile, type: rumour.type,
                                             name: rumour.name))
            } else if let improvement = item as? TileImprovement {
                if layer >= .all || (improvement.type?.isNatural ?? false),
                   let type = spec.getTileImprovementType(improvement.type?.id) {
                    let copy = TileImprovement(game: game, tile: tile, type: type,
                                               style: improvement.style)
                    copy.magnitude = improvement.magnitude
                    result.append(copy)
                }
            }
        }
        setTileItems(result)
    }

    /// Whether an item is here.
    public func contains(_ item: TileItem) -> Bool {
        tileItems.contains { $0 === item }
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        tile = try xr.findFreeColGameObject(game!, "tile", Tile.self, required: true)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("tile", tile)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for item in tileItems { item.toXML(xw) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        tileItems = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let game = game!
        switch xr.localName {
        case LostCityRumour.tag:
            if let lcr = try xr.readFreeColObject(game, LostCityRumour.self) { addTileItem(lcr) }
        case Resource.tag:
            if let resource = try xr.readFreeColObject(game, Resource.self) { addTileItem(resource) }
        case TileImprovement.tag, TileImprovement.oldTag:
            if let ti = try xr.readFreeColObject(game, TileImprovement.self) { addTileItem(ti) }
        default:
            try super.readChild(xr)
        }
    }

    public override var description: String {
        "[\(id ?? "null")" + tileItems.map { " \($0)" }.joined() + "]"
    }
}

/// A natural resource that raises production, such as fish or ore
/// (common/model/Resource).
public final class Resource: TileItem, GameObjectReadable {

    public static let tag = "resource"

    /// The quantity of an inexhaustible resource.
    private static let unlimited = -1

    public private(set) var type: ResourceType?
    /// The amount left, or -1 for no limit.
    public var quantity = 0

    /// A new resource with a fresh identifier.
    public init(game: Game, tile: Tile, type: ResourceType, quantity: Int? = nil) {
        self.type = type
        self.quantity = quantity ?? type.maxValue
        super.init(game: game, tile: tile)
    }

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    public override var xmlTagName: String {
        Resource.tag
    }

    public var isUnlimited: Bool {
        quantity == Resource.unlimited
    }

    public var bestGoodsType: GoodsType? {
        type?.bestGoodsType
    }

    /// Use up the extra production this resource gave.
    ///
    /// - Returns: The quantity left.
    @discardableResult
    public func useQuantity(_ goodsType: GoodsType, _ unitType: UnitType?, _ potential: Int) -> Int {
        let used = applyBonus(goodsType, unitType, potential) - potential
        if quantity == Resource.unlimited {
            // No change
        } else if quantity >= used {
            quantity -= used
        } else {
            quantity = 0 // Java logs this as severe
        }
        return quantity
    }

    // MARK: TileItem

    public override var zIndex: Int {
        Tile.resourceZIndex
    }

    public override func isTileTypeAllowed(_ tileType: TileType) -> Bool {
        type.map(tileType.canHaveResourceType) ?? false
    }

    public override func applyBonus(_ goodsType: GoodsType, _ unitType: UnitType?,
                                    _ potential: Int) -> Int {
        let mods = type?.modifiers(goodsType.id, for: unitType) ?? []
        let amount = -potential + Int(JavaMath.toInt(
            FeatureContainer.applyModifiers(Float(potential), turn: nil, mods)))
        return potential + ((quantity == Resource.unlimited || quantity > amount) ? amount : quantity)
    }

    public override func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        guard goodsType != nil else { return false }
        return JavaMath.toInt(FeatureContainer.applyModifiers(
            0, turn: game?.turn, productionModifiers(goodsType, unitType))) > 0
    }

    public override func productionModifiers(_ goodsType: GoodsType?,
                                             _ unitType: UnitType?) -> [Modifier] {
        guard let goodsType else { return [] }
        return type?.modifiers(goodsType.id, for: unitType) ?? []
    }

    public override var isNatural: Bool { true }

    public override var isComplete: Bool { true }

    public override var layer: Map.Layer { .resources }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        tile = try xr.findFreeColGameObject(game!, "tile", Tile.self, required: true)
        type = try specification.flatMap { try xr.getType($0, "type", ResourceType.self) }
        quantity = xr.attribute("quantity", default: 0)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("tile", tile)
        xw.writeAttribute("type", type)
        xw.writeAttribute("quantity", quantity)
    }

    public override var description: String {
        let typeId = type?.id ?? "NOTYPE"
        return quantity == Resource.unlimited ? typeId : "\(quantity) \(typeId)"
    }
}

/// A rumour of a lost city, explored by moving onto it
/// (common/model/LostCityRumour).
///
/// The message for finding nothing is the server's (it needs the
/// name cache).
public final class LostCityRumour: TileItem, GameObjectReadable {

    public static let tag = "lostCityRumour"

    /// What a rumour turns out to be.
    public enum RumourType: JavaEnum, CustomStringConvertible {
        case noSuchRumour, burialGround, expeditionVanishes, nothing, learn
        case tribalChief, colonist, mounds, ruins, cibola, fountainOfYouth

        public var javaName: String {
            switch self {
            case .noSuchRumour: "NO_SUCH_RUMOUR"
            case .burialGround: "BURIAL_GROUND"
            case .expeditionVanishes: "EXPEDITION_VANISHES"
            case .nothing: "NOTHING"
            case .learn: "LEARN"
            case .tribalChief: "TRIBAL_CHIEF"
            case .colonist: "COLONIST"
            case .mounds: "MOUNDS"
            case .ruins: "RUINS"
            case .cibola: "CIBOLA"
            case .fountainOfYouth: "FOUNTAIN_OF_YOUTH"
            }
        }

        public var description: String {
            javaName
        }

        private var key: String {
            "lostCityRumour." + Messages.enumKey(javaName)
        }

        public var descriptionKey: String {
            Messages.descriptionKey("model." + key)
        }

        public func alternateDescriptionKey(_ variant: String) -> String {
            Messages.descriptionKey("model." + key + "." + variant)
        }
    }

    /// The type, or nil until the rumour is explored.
    public var type: RumourType?
    /// The name, for a city of Cibola.
    public private(set) var name: String?

    /// A new rumour with a fresh identifier.
    public init(game: Game, tile: Tile, type: RumourType? = nil, name: String? = nil) {
        self.type = type
        self.name = name
        super.init(game: game, tile: tile)
    }

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    public override var xmlTagName: String {
        LostCityRumour.tag
    }

    /// What exploring the rumour turns out to be, at random by the
    /// difficulty's chances of good and bad results, the unit's bonus,
    /// and what is possible here (chooseType).
    public func chooseType(_ unit: Unit?, _ random: JavaRandom) -> RumourType? {
        guard let spec = specification, let tile else { return nil }
        // Burial grounds on native land; Fountains of Youth for colonial
        // players; learning for the units that can; experts never vanish.
        let allowBurial = tile.owner?.isIndian ?? false
        let allowFoY = unit?.owner?.playerType == .colonial
        let allowLearn = unit.map { !spec.unitChanges(UnitChangeType.lostCity, $0.type).isEmpty } ?? false
        let allowVanish = !(unit?.hasAbility(Ability.expertScout) ?? false)

        var percentBad = spec.getInteger(GameOptions.badRumour) ?? 0
        var percentGood = spec.getInteger(GameOptions.goodRumour) ?? 0
        if !allowBurial && !allowVanish {
            percentBad = 0
        } else if let unit {
            if unit.owner?.hasAbility(Ability.rumoursAlwaysPositive) ?? false {
                // De Soto.
                percentBad = 0
                percentGood = 100
            } else {
                let mod = unit.apply(1.0, turn: game?.turn, Modifier.exploreLostCityRumour)
                percentBad = Int(JavaMath.round(Float(percentBad) / mod))
                percentGood = Int(JavaMath.round(Float(percentGood) * mod))
            }
        }
        let percentNeutral = max(0, 100 - percentBad - percentGood)

        var c: [RandomChoice<RumourType>] = []
        if percentGood > 0 {
            if allowFoY { c.append(RandomChoice(.fountainOfYouth, 2 * percentGood)) }
            if allowLearn {
                c.append(RandomChoice(.learn, 30 * percentGood))
                c.append(RandomChoice(.tribalChief, 30 * percentGood))
                c.append(RandomChoice(.colonist, 20 * percentGood))
            } else {
                c.append(RandomChoice(.tribalChief, 50 * percentGood))
                c.append(RandomChoice(.colonist, 30 * percentGood))
            }
            c.append(RandomChoice(.mounds, 8 * percentGood))
            c.append(RandomChoice(.ruins, 6 * percentGood))
            c.append(RandomChoice(.cibola, 4 * percentGood))
        }
        if percentBad > 0 {
            var cbad: [RandomChoice<RumourType>] = []
            if allowBurial { cbad.append(RandomChoice(.burialGround, 25 * percentBad)) }
            if allowVanish { cbad.append(RandomChoice(.expeditionVanishes, 75 * percentBad)) }
            RandomChoice.normalize(&cbad, 100)
            c += cbad
        }
        if percentNeutral > 0 { c.append(RandomChoice(.nothing, 100 * percentNeutral)) }
        return RandomChoice.weightedRandom("Choose rumour", c, random)
    }

    // MARK: TileItem

    public override var zIndex: Int {
        Tile.rumourZIndex
    }

    public override func isTileTypeAllowed(_ tileType: TileType) -> Bool {
        !tileType.isWater
    }

    /// Rumours give no bonus.
    public override func applyBonus(_ goodsType: GoodsType, _ unitType: UnitType?,
                                    _ potential: Int) -> Int {
        potential
    }

    public override func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        false
    }

    public override func productionModifiers(_ goodsType: GoodsType?,
                                             _ unitType: UnitType?) -> [Modifier] {
        []
    }

    public override var isNatural: Bool { false }

    public override var isComplete: Bool { true }

    public override var layer: Map.Layer { .rumours }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        tile = try xr.findFreeColGameObject(game!, "tile", Tile.self, required: true)
        type = xr.attribute("type", RumourType.self, default: nil)
        name = xr.attribute("name", default: nil as String?)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("tile", tile)
        if let type { xw.writeAttribute("type", type) }
        xw.writeAttribute("name", id: name)
    }
}

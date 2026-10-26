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

/// Somewhere units or goods can be: a tile, a unit, a settlement,
/// Europe, the high seas or the map (common/model/Location).
///
/// The location labels are functions in Labels.swift.
public protocol Location: AnyObject {
    var id: String? { get }

    /// The tile this location is on, or nil (Europe, the high seas).
    var tile: Tile? { get }

    /// Add a unit, goods or a tile item.
    ///
    /// - Returns: Whether it was added (or was already here).
    @discardableResult
    func add(_ locatable: any Locatable) -> Bool

    /// Remove a unit, goods or a tile item.
    @discardableResult
    func remove(_ locatable: any Locatable) -> Bool

    func contains(_ locatable: any Locatable) -> Bool

    func canAdd(_ locatable: any Locatable) -> Bool

    var unitCount: Int { get }

    var unitList: [Unit] { get }

    var goodsContainer: GoodsContainer? { get }

    var settlement: Settlement? { get }

    var colony: Colony? { get }

    var indianSettlement: IndianSettlement? { get }

    /// The location that best describes this one to a player: a
    /// settlement rather than its tile, a carrier's location, and so on.
    func up() -> any Location

    /// The order of locations: distinct tile ranks, then the high
    /// seas, Europe and nowhere.
    var rank: Int { get }

    /// A short description for logs (Java's toShortString).
    var shortDescription: String { get }
}

/// The ranks of locations other than tiles.
public enum LocationRank {
    public static let nowhere = -3
    public static let europe = -2
    public static let highSeas = -1

    /// A location's rank, or nowhere for none (Location.rankOf).
    public static func of(_ loc: (any Location)?) -> Int {
        loc?.rank ?? nowhere
    }
}

/// Something with a location: a unit, goods or a tile item
/// (common/model/Locatable).
public protocol Locatable: AnyObject {
    var location: (any Location)? { get }

    /// Move to a location.
    ///
    /// - Returns: Whether the move happened.
    @discardableResult
    func setLocation(_ newLocation: (any Location)?) -> Bool

    var isInEurope: Bool { get }

    var tile: Tile? { get }

    /// The space this takes on a carrier.
    var spaceTaken: Int { get }
}

/// Something owned by a player (common/model/Ownable).
public protocol Ownable: AnyObject {
    var owner: Player? { get }
}

/// Why a unit or goods cannot be added to a location
/// (UnitLocation.NoAddReason), in Java's order.
public enum NoAddReason: JavaEnum, CustomStringConvertible {
    case none, alreadyPresent, wrongType, capacityExceeded, occupiedByEnemy
    case ownedByEnemy, anotherColony, colonyCenter, missingAbility, missingSkill
    case minimumSkill, maximumSkill, claimRequired, workerDamaged

    public var javaName: String {
        switch self {
        case .none: "NONE"
        case .alreadyPresent: "ALREADY_PRESENT"
        case .wrongType: "WRONG_TYPE"
        case .capacityExceeded: "CAPACITY_EXCEEDED"
        case .occupiedByEnemy: "OCCUPIED_BY_ENEMY"
        case .ownedByEnemy: "OWNED_BY_ENEMY"
        case .anotherColony: "ANOTHER_COLONY"
        case .colonyCenter: "COLONY_CENTER"
        case .missingAbility: "MISSING_ABILITY"
        case .missingSkill: "MISSING_SKILL"
        case .minimumSkill: "MINIMUM_SKILL"
        case .maximumSkill: "MAXIMUM_SKILL"
        case .claimRequired: "CLAIM_REQUIRED"
        case .workerDamaged: "WORKER_DAMAGED"
        }
    }

    public var description: String {
        javaName
    }
}

/// A location that holds units (common/model/UnitLocation): the base
/// of tiles, units, settlements, Europe and the high seas.
///
/// A location holds its units; a unit's reference to its location is
/// weak.
///
/// Not yet ported: copyIn.
open class UnitLocation: FreeColGameObject, Location {

    public private(set) var units: [Unit] = []

    /// A new location with a fresh identifier.
    public override init(game: Game) {
        super.init(game: game)
    }

    /// A location that is about to be read.
    public init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    /// The units here go with the location.
    open override var disposables: [FreeColGameObject] {
        units.flatMap(\.disposables) + super.disposables
    }

    open override func disposeResources() {
        units.removeAll()
        super.disposeResources()
    }

    @discardableResult
    private func addUnit(_ u: Unit?) -> Bool {
        guard let u else { return false }
        u.setLocationNoUpdate(self)
        units.append(u)
        return true
    }

    // MARK: Utilities

    public final var isEmpty: Bool {
        unitCount == 0
    }

    public final var isFull: Bool {
        unitCount >= unitCapacity
    }

    public final var firstUnit: Unit? {
        unitList.first
    }

    public final var lastUnit: Unit? {
        unitList.last
    }

    /// The units here, and the units they carry.
    open var totalUnitCount: Int {
        unitList.reduce(0) { $0 + 1 + $1.unitCount }
    }

    /// Whether a carrier here, not under repair, has space left.
    public func hasCarrierWithSpace(_ space: Int) -> Bool {
        unitList.contains { $0.isCarrier && !$0.isDamagedAndUnderForcedRepair && $0.spaceLeft >= space }
    }

    public var navalUnits: [Unit] {
        unitList.filter(\.isNaval)
    }

    /// The first unit here that could carry a unit.
    public func carrier(for unit: Unit) -> Unit? {
        unitList.first { $0.couldCarry(unit) }
    }

    // MARK: Location

    open var tile: Tile? {
        nil
    }

    @discardableResult
    open func add(_ locatable: any Locatable) -> Bool {
        if let unit = locatable as? Unit {
            if contains(unit) { return true }
            return canAdd(unit) && addUnit(unit)
        } else if let goods = locatable as? Goods {
            // Dumping goods is allowed.
            goods.setLocation(nil)
            return true
        }
        // Java logs a warning.
        return false
    }

    @discardableResult
    open func remove(_ locatable: any Locatable) -> Bool {
        guard let unit = locatable as? Unit,
              let i = units.firstIndex(where: { $0 === unit }) else { return false }
        units.remove(at: i)
        unit.setLocationNoUpdate(nil)
        return true
    }

    open func contains(_ locatable: any Locatable) -> Bool {
        guard let unit = locatable as? Unit else { return false }
        return units.contains { $0 === unit }
    }

    open func canAdd(_ locatable: any Locatable) -> Bool {
        noAddReason(locatable) == .none
    }

    /// The price of goods here.  A plain location has none to sell.
    ///
    /// - Throws: FreeColException if goods are not available.
    open func priceGoods(_ goods: [AbstractGoods]) throws -> Int {
        guard let first = goods.first else { return 0 }
        throw FreeColException("Not available: \(first)")
    }

    /// Equip a unit for a role with what is here.
    ///
    /// - Returns: Whether the unit was equipped.
    @discardableResult
    open func equipForRole(_ unit: Unit, _ role: Role, _ roleCount: Int) -> Bool {
        false
    }

    open var unitCount: Int {
        units.count
    }

    open var unitList: [Unit] {
        units
    }

    open var goodsContainer: GoodsContainer? {
        nil
    }

    open var settlement: Settlement? {
        nil
    }

    public final var colony: Colony? {
        settlement as? Colony
    }

    public final var indianSettlement: IndianSettlement? {
        settlement as? IndianSettlement
    }

    /// Subclasses say where they belong; Java leaves this abstract.
    open func up() -> any Location {
        fatalError("up() not implemented for \(type(of: self))")
    }

    /// Subclasses say where they rank; Java leaves this abstract.
    open var rank: Int {
        fatalError("rank not implemented for \(type(of: self))")
    }

    open var shortDescription: String {
        id ?? "null"
    }

    // MARK: For subclasses

    /// The space the units here take.
    open var spaceTaken: Int {
        unitList.reduce(0) { $0 + $1.spaceTaken }
    }

    /// Move a unit here to the front of the list.
    public func moveToFront(_ u: Unit) {
        guard let i = units.firstIndex(where: { $0 === u }) else { return }
        units.insert(units.remove(at: i), at: 0)
    }

    public func clearUnitList() {
        units = []
    }

    /// Why something could not be added here, or .none.
    open func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        guard let unit = locatable as? Unit else { return .wrongType }
        if !isEmpty && firstUnit?.owner !== unit.owner { return .occupiedByEnemy }
        if contains(unit) { return .alreadyPresent }
        if unit.spaceTaken + spaceTaken > unitCapacity { return .capacityExceeded }
        return .none
    }

    /// How many units fit here.
    open var unitCapacity: Int {
        Int(Int32.max)
    }

    // MARK: Writing XML

    /// Write the units, fixing any whose location is wrong, as Java
    /// does.
    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for unit in units {
            if unit.location !== self { unit.setLocationNoUpdate(self) }
            unit.toXML(xw)
        }
    }

    // MARK: Reading XML

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        clearUnitList()
        try super.readChildren(xr)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == Unit.tag {
            addUnit(try xr.readFreeColObject(game!, Unit.self))
        } else {
            try super.readChild(xr)
        }
    }
}

/// A location that holds goods as well as units
/// (common/model/GoodsLocation): units and settlements.
///
/// The location holds its goods container.
open class GoodsLocation: UnitLocation {

    private var storedGoodsContainer: GoodsContainer?

    public final func setGoodsContainer(_ goodsContainer: GoodsContainer?) {
        storedGoodsContainer = goodsContainer
    }

    /// The goods container goes with the location.
    open override var disposables: [FreeColGameObject] {
        (storedGoodsContainer?.disposables ?? []) + super.disposables
    }

    public final override var goodsContainer: GoodsContainer? {
        storedGoodsContainer
    }

    @discardableResult
    public final func addGoods(_ goods: AbstractGoods) -> Bool {
        guard let type = goods.type else { return false }
        return addGoods(type, goods.amount)
    }

    @discardableResult
    public final func addGoods(_ goods: [AbstractGoods]) -> Bool {
        goods.allSatisfy { addGoods($0) }
    }

    @discardableResult
    public final func removeGoods(_ goods: AbstractGoods) -> Goods? {
        guard let type = goods.type else { return nil }
        return removeGoods(type, goods.amount)
    }

    /// Remove all goods of a type.
    @discardableResult
    public final func removeGoods(_ type: GoodsType) -> Goods? {
        removeGoods(type, goodsCount(type))
    }

    public final func goodsCount(_ type: GoodsType?) -> Int {
        storedGoodsContainer?.goodsCount(type) ?? 0
    }

    public final func containsGoods(_ goods: [AbstractGoods]) -> Bool {
        goods.allSatisfy { $0.amount <= goodsCount($0.type) }
    }

    public final func removeAllGoods() {
        guard let storedGoodsContainer else { return }
        storedGoodsContainer.removeAll()
        invalidateCache()
    }

    /// The goods here in loads of at most 100.
    open var goodsList: [Goods] {
        storedGoodsContainer?.goodsList ?? []
    }

    /// The goods here, one entry per type.
    open var compactGoodsList: [Goods] {
        storedGoodsContainer?.compactGoodsList ?? []
    }

    /// Move goods between locations.
    public static func moveGoods(_ src: GoodsLocation?, _ goodsType: GoodsType, _ amount: Int,
                                 _ dst: GoodsLocation?) {
        GoodsContainer.moveGoods(src?.goodsContainer, goodsType, amount, dst?.goodsContainer)
    }

    // MARK: Location

    @discardableResult
    open override func add(_ locatable: any Locatable) -> Bool {
        if let goods = locatable as? Goods { return addGoods(goods) }
        return super.add(locatable)
    }

    @discardableResult
    open override func remove(_ locatable: any Locatable) -> Bool {
        if let goods = locatable as? Goods { return removeGoods(goods) != nil }
        return super.remove(locatable)
    }

    open override func contains(_ locatable: any Locatable) -> Bool {
        if let goods = locatable as? Goods {
            // Java fails without a container.
            return storedGoodsContainer!.contains(goods)
        }
        return super.contains(locatable)
    }

    open override func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        if let goods = locatable as? Goods {
            let taken = goods.spaceTaken + (storedGoodsContainer?.spaceTaken ?? 0)
            return taken > goodsCapacity ? .capacityExceeded : .none
        }
        return super.noAddReason(locatable)
    }

    // MARK: For subclasses

    /// Forget anything cached about the goods here.
    open func invalidateCache() {
        fatalError("invalidateCache not implemented for \(type(of: self))")
    }

    /// How many goods fit here.
    open var goodsCapacity: Int {
        fatalError("goodsCapacity not implemented for \(type(of: self))")
    }

    /// Add goods, creating the container if needed.
    @discardableResult
    open func addGoods(_ type: GoodsType, _ amount: Int) -> Bool {
        if storedGoodsContainer == nil {
            storedGoodsContainer = GoodsContainer(game: game!, parent: self)
        }
        let ret = storedGoodsContainer!.addGoods(type, amount)
        invalidateCache()
        return ret
    }

    @discardableResult
    open func removeGoods(_ type: GoodsType, _ amount: Int) -> Goods? {
        guard let storedGoodsContainer else { return nil }
        let ret = storedGoodsContainer.removeGoods(type, amount)
        invalidateCache()
        return ret
    }

    // MARK: Writing XML

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        storedGoodsContainer?.toXML(xw)
    }

    // MARK: Reading XML

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        storedGoodsContainer?.removeAll()
        try super.readChildren(xr)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == GoodsContainer.tag {
            storedGoodsContainer = try xr.readFreeColObject(game!, GoodsContainer.self)
            storedGoodsContainer?.setLocation(self)
        } else {
            try super.readChild(xr)
        }
    }
}

/// A model operation that could not be done (common/FreeColException).
public struct FreeColException: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

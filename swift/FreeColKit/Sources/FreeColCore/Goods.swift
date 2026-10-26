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

/// The goods stored at a location, with a copy saved at the start of a
/// change so the change can be undone or reported
/// (common/model/GoodsContainer).
///
/// The goods are kept in maps that iterate in Java's HashMap order,
/// since the goods lists and the description follow it.  The reference
/// to the parent location is weak.
///
/// Not yet ported: fireChanges (property change listeners, for the
/// UI) and copyIn.
public final class GoodsContainer: FreeColGameObject, GameObjectReadable, Ownable {

    public static let tag = "goodsContainer"

    /// The goods in a full cargo hold.
    public static let cargoSize = 100
    /// More goods than any location will hold.
    public static let hugeCargoSize = 100 * cargoSize

    private static func newStorage() -> JavaHashMap<GoodsType, Int> {
        // GoodsType.hashCode() is its id's hash code.
        JavaHashMap(javaHash: { JavaString.hashCode($0.id ?? "") })
    }

    private var storedGoods = GoodsContainer.newStorage()
    private var oldStoredGoods = GoodsContainer.newStorage()
    public private(set) weak var parent: (any Location)?

    /// A new empty container with a fresh identifier.
    public init(game: Game, parent: any Location) {
        self.parent = parent
        super.init(game: game)
    }

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    public override var xmlTagName: String {
        GoodsContainer.tag
    }

    /// Set the location holding this container.
    public func setLocation(_ location: any Location) {
        parent = location
    }

    /// The stored goods, in Java's HashMap order.
    public var storedEntries: [(type: GoodsType, amount: Int)] {
        storedGoods.entries.map { (type: $0.key, amount: $0.value) }
    }

    /// The goods as saved by saveState, in Java's HashMap order.
    public var oldStoredEntries: [(type: GoodsType, amount: Int)] {
        oldStoredGoods.entries.map { (type: $0.key, amount: $0.value) }
    }

    /// Whether at least an amount of goods is here.
    public func contains(_ goods: AbstractGoods) -> Bool {
        goodsCount(goods.type) >= goods.amount
    }

    public func goodsCount(_ type: GoodsType?) -> Int {
        type.flatMap { storedGoods[$0] } ?? 0
    }

    public func oldGoodsCount(_ type: GoodsType?) -> Int {
        type.flatMap { oldStoredGoods[$0] } ?? 0
    }

    @discardableResult
    public func addGoods(_ goods: AbstractGoods) -> Bool {
        guard let type = goods.type else { return false }
        return addGoods(type, goods.amount)
    }

    /// Add (or with a negative amount, remove) goods.  It is an error
    /// to leave a negative amount.
    @discardableResult
    public func addGoods(_ type: GoodsType, _ amount: Int) -> Bool {
        let newAmount = goodsCount(type) + amount
        precondition(newAmount >= 0, "Operation would leave \(newAmount) goods of type"
            + " \(type.id ?? "null") in Location \(parent?.id ?? "null")")
        if newAmount == 0 {
            storedGoods.removeValue(forKey: type)
        } else {
            storedGoods.put(type, newAmount)
        }
        invalidateCache()
        return true
    }

    @discardableResult
    public func removeGoods(_ goods: AbstractGoods) -> Goods? {
        guard let type = goods.type else { return nil }
        return removeGoods(type, goods.amount)
    }

    /// Remove all the goods of a type.
    @discardableResult
    public func removeGoods(_ type: GoodsType) -> Goods? {
        removeGoods(type, Constants.infinity)
    }

    /// Remove up to an amount of goods.
    ///
    /// - Returns: The goods removed, with no location, or nil if there
    ///   were none.
    @discardableResult
    public func removeGoods(_ type: GoodsType, _ amount: Int) -> Goods? {
        let oldAmount = goodsCount(type)
        guard oldAmount > 0, let game else { return nil }
        let newAmount = oldAmount - amount
        let removed: Goods
        if newAmount > 0 {
            removed = Goods(game: game, location: nil, type: type, amount: amount)
            storedGoods.put(type, newAmount)
        } else {
            removed = Goods(game: game, location: nil, type: type, amount: oldAmount)
            storedGoods.removeValue(forKey: type)
        }
        invalidateCache()
        return removed
    }

    private func invalidateCache() {
        (parent as? GoodsLocation)?.invalidateCache()
    }

    /// Set the amount of a type of goods.
    public func setAmount(_ goodsType: GoodsType, _ newAmount: Int) {
        if newAmount == 0 {
            storedGoods.removeValue(forKey: goodsType)
        } else {
            storedGoods.put(goodsType, newAmount)
        }
        invalidateCache()
    }

    public func removeAll() {
        storedGoods.removeAll()
        invalidateCache()
    }

    /// The goods go with the container, as in Java.
    public override func disposeResources() {
        clearContainers()
        super.disposeResources()
    }

    private func clearContainers() {
        storedGoods.removeAll()
        oldStoredGoods.removeAll()
    }

    /// Cut storable goods down to an amount.  Goods that ignore the
    /// warehouse limit are kept.  An amount of 0 or less removes
    /// everything.
    public func removeAbove(_ newAmount: Int) {
        if newAmount <= 0 {
            // Java returns without invalidating the cache here.
            storedGoods.removeAll()
            return
        }
        for (type, amount) in storedGoods.entries
        where type.isStorable && !type.limitIgnored && amount > newAmount {
            storedGoods.put(type, newAmount)
        }
        invalidateCache()
    }

    /// Whether any storable goods are over an amount.
    public func hasReachedCapacity(_ amount: Int) -> Bool {
        storedGoods.entries.contains { $0.key.isStorable && !$0.key.limitIgnored && $0.value > amount }
    }

    /// The holds the goods take: one per started 100 of each type.
    public var spaceTaken: Int {
        storedGoods.values.reduce(0) { total, amount in
            total + (amount % GoodsContainer.cargoSize == 0 ? amount / GoodsContainer.cargoSize
                : amount / GoodsContainer.cargoSize + 1)
        }
    }

    /// The goods in loads of at most 100.
    public var goodsList: [Goods] {
        guard let game else { return [] }
        var result: [Goods] = []
        for (type, total) in storedGoods.entries {
            var amount = total
            while amount > 0 {
                result.append(Goods(game: game, location: parent, type: type,
                                    amount: min(amount, GoodsContainer.cargoSize)))
                amount -= GoodsContainer.cargoSize
            }
        }
        return result
    }

    /// The goods, one entry per type.
    public var compactGoodsList: [Goods] {
        guard let game else { return [] }
        return storedGoods.entries.filter { $0.value > 0 }.map {
            Goods(game: game, location: parent, type: $0.key, amount: $0.value)
        }
    }

    /// Remember the goods, to undo a change or report it.
    public func saveState() {
        oldStoredGoods.removeAll()
        oldStoredGoods.putAll(storedGoods)
    }

    /// Go back to the remembered goods.
    public func restoreState() {
        storedGoods.removeAll()
        storedGoods.putAll(oldStoredGoods)
    }

    /// Whether the goods differ from the remembered goods.
    public var hasChanged: Bool {
        (specification?.goodsTypeList ?? []).contains { oldGoodsCount($0) != goodsCount($0) }
    }

    /// Move goods between containers, remembering both first.
    public static func moveGoods(_ src: GoodsContainer?, _ goodsType: GoodsType, _ amount: Int,
                                 _ dst: GoodsContainer?) {
        if let src {
            src.saveState()
            src.removeGoods(goodsType, amount)
        }
        if let dst {
            dst.saveState()
            dst.addGoods(goodsType, amount)
        }
    }

    // MARK: Ownable

    /// The owner of the parent location.
    public var owner: Player? {
        (parent as? Ownable)?.owner
    }

    // MARK: Reading XML

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        clearContainers()
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "oldStoredGoods": try readStorage(xr, &oldStoredGoods)
        case "storedGoods": try readStorage(xr, &storedGoods)
        default: try super.readChild(xr)
        }
    }

    private func readStorage(_ xr: FreeColXMLReader, _ storage: inout JavaHashMap<GoodsType, Int>) throws {
        let spec = game?.specification
        while try xr.moreTags() {
            let tag = xr.localName
            guard tag == Goods.tag else {
                throw FreeColXMLError("Bogus GoodsContainer tag: \(tag)")
            }
            // Java stores a missing type under null.
            if let spec, let type = try xr.getType(spec, "type", GoodsType.self) {
                storage.put(type, xr.attribute("amount", default: 0))
            }
            try xr.closeTag(tag)
        }
    }

    // MARK: Writing XML

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if xw.validFor(owner) {
            writeStorage(xw, "storedGoods", storedGoods)
            writeStorage(xw, "oldStoredGoods", oldStoredGoods)
        }
    }

    private func writeStorage(_ xw: FreeColXMLWriter, _ tag: String, _ storage: JavaHashMap<GoodsType, Int>) {
        if storage.isEmpty { return }
        xw.writeStartElement(tag)
        for type in sortedById(storage.keys) {
            xw.writeStartElement(Goods.tag)
            xw.writeAttribute("type", type)
            xw.writeAttribute("amount", storage[type] ?? 0)
            xw.writeEndElement()
        }
        xw.writeEndElement()
    }

    /// Java's toString, including its slip: with no goods it cuts the
    /// last two characters of what came before.
    public override var description: String {
        func cut(_ s: inout [UInt16]) { s.removeLast(min(2, s.count)) }
        func entry(_ type: GoodsType, _ amount: Int) -> [UInt16] {
            Array(((type.id ?? "null") + "=" + String(amount) + ", ").utf16)
        }
        var sb = Array(("[" + (id ?? "null") + " [").utf16)
        for (type, amount) in storedGoods.entries { sb += entry(type, amount) }
        cut(&sb)
        sb += Array("][".utf16)
        for (type, amount) in oldStoredGoods.entries { sb += entry(type, amount) }
        cut(&sb)
        sb += Array("]]".utf16)
        return String(decoding: sb, as: UTF16.self)
    }
}

/// Goods at a location (common/model/Goods).  Goods are not game
/// objects: they are made as needed, such as for each load in a hold.
///
/// The references to the game and location are weak.
///
/// Not yet ported: copyIn.
public final class Goods: AbstractGoods, Locatable, Ownable {

    public static let tag = "goods"

    private weak var gameReference: Game?
    public private(set) weak var location: (any Location)?

    /// Goods of a type at a location, which must hold goods.
    public init(game: Game, location: (any Location)?, type: GoodsType, amount: Int) {
        precondition(location == nil || location?.goodsContainer != nil,
                     "Can not store goods at: \(location?.id ?? "null")")
        gameReference = game
        self.location = location
        super.init(type, amount)
    }

    /// Read goods from the element a reader is on.
    public init(game: Game, reading xr: FreeColXMLReader) throws {
        gameReference = game
        super.init(nil, 0)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        Goods.tag
    }

    /// Cut the amount down to what the location holds.
    public func adjustAmount() {
        guard let type, let gc = location?.goodsContainer else { return }
        amount = min(amount, gc.goodsCount(type))
    }

    // MARK: Locatable

    @discardableResult
    public func setLocation(_ newLocation: (any Location)?) -> Bool {
        location = newLocation
        return true
    }

    public var isInEurope: Bool {
        location is Europe || ((location as? Unit)?.isInEurope ?? false)
    }

    public var tile: Tile? {
        location?.tile
    }

    public var spaceTaken: Int {
        1
    }

    // MARK: Ownable

    public var owner: Player? {
        (location as? Ownable)?.owner
    }

    // MARK: FreeColObject

    public override var specification: Specification? {
        gameReference?.specification
    }

    public override var game: Game? {
        gameReference
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        guard let game, let spec = specification,
              let type = try xr.getType(spec, "type", GoodsType.self) else {
            throw FreeColXMLError("Null goods type: \(self)")
        }
        self.type = type
        id = type.id
        amount = xr.attribute("amount", default: 0)
        location = try xr.getLocationAttribute(game, "location", make: true) as? any Location
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("type", type)
        xw.writeAttribute("amount", amount)
        xw.writeLocationAttribute("location", location)
    }

    /// The same goods at the same location.
    public override func isEqual(to other: FreeColObject) -> Bool {
        guard let other = other as? Goods else { return false }
        return location === other.location && super.isEqual(to: other)
    }

    public override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(location.map(ObjectIdentifier.init))
    }
}

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

/// A place a trade route can stop to load and unload goods: a colony,
/// a native settlement or Europe (common/model/TradeLocation).
public protocol TradeLocation: AnyObject {
    /// The goods of a type available here now.
    func availableGoodsCount(_ goodsType: GoodsType) -> Int
    /// The goods of a type that could be taken away in some turns.
    func exportAmount(_ goodsType: GoodsType, _ turns: Int) -> Int
    /// The goods of a type that could be brought in some turns.
    func importAmount(_ goodsType: GoodsType, _ turns: Int) -> Int
    /// The name of a trade location of the same kind (Java's casts make
    /// it that).
    func locationName(_ tradeLocation: TradeLocation) -> String?
    /// Whether goods can be loaded here.
    var canBeInput: Bool { get }
}

extension Colony: TradeLocation {
    public func locationName(_ tradeLocation: TradeLocation) -> String? {
        (tradeLocation as! Colony).name
    }

    public var canBeInput: Bool { true }
}

extension IndianSettlement: TradeLocation {
    public func locationName(_ tradeLocation: TradeLocation) -> String? {
        (tradeLocation as! IndianSettlement).name
    }

    public var canBeInput: Bool { false }
}

/// A player's trade route: stops where units load and unload goods
/// (common/model/TradeRoute).
///
/// The player holds its trade routes, and a route its stops; the owner
/// is weak.  The verification templates are in Labels.swift.  Not yet
/// ported: copyIn.
public final class TradeRoute: FreeColGameObject, GameObjectReadable, Ownable {

    public static let tag = "tradeRoute"

    public var name: String?
    public weak var owner: Player?
    private var stops: [TradeRouteStop] = []
    public var isSilent = false

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    public init(game: Game, name: String?, owner: Player?) {
        self.name = name
        self.owner = owner
        super.init(game: game)
    }

    /// A route with a known identifier.
    public init(game: Game, id: String, name: String?, owner: Player?) {
        self.name = name
        self.owner = owner
        super.init(game: game, id: id)
    }

    public override var xmlTagName: String {
        TradeRoute.tag
    }

    public var stopCount: Int {
        stops.count
    }

    /// The stop at an index, or nil.
    public func stop(_ index: Int) -> TradeRouteStop? {
        index >= 0 && index < stops.count ? stops[index] : nil
    }

    public var stopList: [TradeRouteStop] {
        stops
    }

    /// The stops from one up to (but not including) another, wrapping
    /// round, or nil if either is not a stop.
    public func stopSublist(_ start: TradeRouteStop, _ end: TradeRouteStop) -> [TradeRouteStop]? {
        var i0 = index(of: start)
        let iN = index(of: end)
        guard i0 >= 0, iN >= 0 else { return nil }
        var result: [TradeRouteStop] = []
        while i0 != iN {
            result.append(stops[i0])
            i0 += 1
            if i0 >= stops.count { i0 = 0 }
        }
        return result
    }

    public func addStop(_ stop: TradeRouteStop) {
        stops.append(stop)
    }

    public func removeStop(_ stop: TradeRouteStop) {
        if let i = stops.firstIndex(where: { $0 === stop }) { stops.remove(at: i) }
    }

    /// Remove the stops at a location.
    ///
    /// - Returns: Whether any were removed.
    @discardableResult
    public func removeMatchingStops(_ loc: (any Location)?) -> Bool {
        let before = stops.count
        stops.removeAll { Map.isSameLocation($0.location, loc) }
        return stops.count != before
    }

    /// The index of a stop, or -1.
    public func index(of stop: TradeRouteStop) -> Int {
        stops.firstIndex { $0 === stop } ?? -1
    }

    public func clearStops() {
        stops = []
    }

    /// The owner's units following this route.
    public var assignedUnits: [Unit] {
        owner?.units.filter { $0.tradeRoute === self } ?? []
    }

    public static func isStopValid(_ unit: Unit, _ stop: TradeRouteStop?) -> Bool {
        isStopValid(unit.owner, stop)
    }

    public static func isStopValid(_ player: Player?, _ stop: TradeRouteStop?) -> Bool {
        guard let stop, let player else { return false }
        return stop.isValid(player)
    }

    /// Why the route is unusable, as Java's message key, or nil if it
    /// is fine (verify gives the template).
    public var verifyKey: String? {
        guard name != nil else { return "model.tradeRoute.nullName" }
        guard let owner else { return "model.tradeRoute.nullOwner" }
        // At least two stops.
        if stopCount < 2 { return "model.tradeRoute.notEnoughStops" }
        // All stops valid, at least one not empty, and no goods present
        // unmaintained at all stops.
        var always = stops[0].cargo
        var empty = true
        for stop in stops {
            if !TradeRoute.isStopValid(owner, stop) { return "model.tradeRoute.invalidStop" }
            if !stop.cargo.isEmpty { empty = false }
            always.removeAll { gt in !stop.cargo.contains { $0 === gt } }
        }
        let enhanced = specification?.getBoolean(GameOptions.enhancedTradeRoutes) ?? false
        return empty ? "model.tradeRoute.allEmpty"
            : !enhanced && !always.isEmpty ? "model.tradeRoute.alwaysPresent"
            : nil
    }

    /// Why the name clashes with another of the owner's routes, as
    /// Java's message key, or nil.
    public var verifyUniqueNameKey: String? {
        owner?.tradeRoute(byName: name, excluding: self) != nil ? "model.tradeRoute.duplicateName" : nil
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        name = xr.attribute("name", default: nil as String?)
        owner = try xr.findFreeColGameObject(game!, "owner", Player.self, required: true)
        isSilent = xr.attribute("silent", default: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("name", id: name)
        xw.writeAttribute("owner", owner)
        xw.writeAttribute("silent", isSilent)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for stop in stops { stop.toXML(xw) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        clearStops()
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == TradeRouteStop.tag {
            addStop(try TradeRouteStop(game: game!, xr))
        } else {
            try super.readChild(xr)
        }
    }

    public override var description: String {
        var s = "[\(id ?? "null") \"\(name ?? "null")\""
        if let owner { s += " owner=\(owner.id ?? "null")" }
        s += " silent=\(isSilent)"
        return s + stops.map { " \($0)" }.joined() + "]"
    }
}

/// A stop on a trade route: a location and the goods to load there
/// (common/model/TradeRouteStop).  Stops are not registered with the
/// game.  The location is weak.
public final class TradeRouteStop: FreeColGameObject {

    public static let tag = "tradeRouteStop"

    public private(set) weak var location: (any Location)?
    /// The goods to load, a type once for each full hold.
    public var cargo: [GoodsType] = []

    public init(game: Game, location: (any Location)?) {
        self.location = location
        super.init(game: game, id: "") // Identifier not required
    }

    public convenience init(copying other: TradeRouteStop) {
        self.init(game: other.game!, location: other.location)
        cargo = other.cargo
    }

    /// Read a stop from the element the reader is on.
    public convenience init(game: Game, _ xr: FreeColXMLReader) throws {
        self.init(game: game, location: nil)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        TradeRouteStop.tag
    }

    public override var isInternable: Bool {
        false
    }

    public var tradeLocation: TradeLocation? {
        location as? TradeLocation
    }

    /// Whether the stop is a trade location the player owns that is
    /// still in the game.
    public func isValid(_ player: Player) -> Bool {
        guard let location, location is TradeLocation, let fcgo = location as? FreeColGameObject
        else { return false }
        return !fcgo.isDisposed && fcgo.isInitialized && player.owns(location as? Ownable)
    }

    public func addCargo(_ goodsType: GoodsType) {
        cargo.append(goodsType)
    }

    /// The cargo as goods, a full hold for each entry.
    public var compactCargo: [AbstractGoods] {
        var result: [AbstractGoods] = []
        for type in cargo {
            if let ag = result.first(where: { $0.type === type }) {
                ag.amount += GoodsContainer.cargoSize
            } else {
                result.append(AbstractGoods(type, GoodsContainer.cargoSize))
            }
        }
        return result
    }

    /// Whether a unit has goods to load or unload here.
    public func hasWork(_ unit: Unit, _ turns: Int) -> Bool {
        let stopGoods = compactCargo
        // Goods to load: space for more of a type there is some of here.
        if stopGoods.contains(where: { ag in
            unit.goodsCount(ag.type) < ag.amount && exportAmount(ag.type!, turns) > 0
        }) { return true }
        // Goods to unload: carried goods not loaded here, wanted here.
        return unit.compactGoodsList.contains { g in
            !stopGoods.contains { $0.type === g.type } && importAmount(g.type!, turns) > 0
        }
    }

    public func availableGoodsCount(_ goodsType: GoodsType) -> Int {
        tradeLocation?.availableGoodsCount(goodsType) ?? 0
    }

    public func exportAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        tradeLocation?.exportAmount(goodsType, turns) ?? 0
    }

    public func importAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        tradeLocation?.importAmount(goodsType, turns) ?? 0
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        // Java does not read the identifier here.
        location = try xr.getLocationAttribute(game!, "location", make: true) as? any Location
    }

    /// Java writes no identifier here.
    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        xw.writeLocationAttribute("location", location)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        for cargoType in cargo { xw.writeIdElement("cargo", cargoType.id) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        cargo = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "cargo" {
            if let gt = try specification.flatMap({ try xr.getType($0, FreeColObject.idTag, GoodsType.self) }) {
                cargo.append(gt)
            }
            try xr.closeTag("cargo")
        } else {
            try super.readChild(xr)
        }
    }

    public override var description: String {
        "[\(id ?? "null") \(location?.id ?? "null")" + cargo.map { " \($0)" }.joined() + "]"
    }
}

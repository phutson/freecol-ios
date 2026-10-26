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

/// How a road or river connects to its neighbours
/// (common/model/TileImprovementStyle).
///
/// The style is one digit per connection direction: 8 for roads (all
/// directions), 4 for rivers (the long sides), each 0 for no
/// connection or the magnitude of the connection.  Java shares one
/// object per style string; here styles are values.
public struct TileImprovementStyle: Hashable, Sendable, CustomStringConvertible {

    /// The style string.
    public let string: String
    /// The style with every connection as 1.
    public let mask: String

    /// The style for a string of 4 or 8 characters, or nil.
    public init?(_ key: String?) {
        guard let key, key.utf16.count == 4 || key.utf16.count == 8 else { return nil }
        string = key
        var mask = ""
        for c in key {
            // Character.digit(c, Character.MAX_RADIX) < 0
            guard c.isASCII, c.isLetter || c.isNumber else { break }
            mask.append(c == "0" ? "0" : "1")
        }
        self.mask = mask
    }

    public var description: String {
        string
    }
}

/// An improvement on a tile: a road, a river, plowing, clearing a
/// forest (common/model/TileImprovement).
///
/// Not yet ported: checkIntegrity.
public final class TileImprovement: TileItem, GameObjectReadable {

    public static let tag = "tileImprovement"
    // @compat 0.11.3
    public static let oldTag = "tileimprovement"

    public static let emptyRiverStyle = "0000"
    public static let emptyRoadStyle = "00000000"

    public static let noRiver = 0
    public static let smallRiver = 1
    public static let largeRiver = 2
    public static let fjordRiver = 3

    public private(set) var type: TileImprovementType?
    /// Turns of work left, 0 when finished.
    public var turnsToComplete = 0
    public var magnitude = 0
    public var style: TileImprovementStyle?
    /// Whether this improvement is only there because of something else,
    /// such as the road in a colony.
    public var isVirtual = false

    /// A new improvement with a fresh identifier.  One that is not
    /// natural needs the tile type's work turns plus its own.
    public init(game: Game, tile: Tile, type: TileImprovementType, style: TileImprovementStyle?) {
        self.type = type
        if !type.isNatural {
            turnsToComplete = (tile.type?.basicWorkTurns ?? 0) + type.addWorkTurns
        }
        magnitude = type.magnitude
        self.style = style
        super.init(game: game, tile: tile)
    }

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    public override var xmlTagName: String {
        TileImprovement.tag
    }

    public var isRiver: Bool {
        type?.id == "model.improvement.river"
    }

    public var isRoad: Bool {
        type?.id == "model.improvement.road"
    }

    /// The directions this improvement can connect in, or nil if it
    /// does not connect.
    public var connectionDirections: [Direction]? {
        isRoad ? Direction.allDirections : isRiver ? Direction.longSides : nil
    }

    private func styleCharacter(_ index: Int) -> Character? {
        guard let s = style?.string, index < s.count else { return nil }
        return s[s.index(s.startIndex, offsetBy: index)]
    }

    /// The magnitude of a river's connection in a direction, or 0.
    public func riverConnection(_ direction: Direction) -> Int {
        guard let index = Direction.longSides.firstIndex(of: direction),
              let c = styleCharacter(index) else { return 0 }
        return c.wholeNumberValue ?? 0
    }

    /// Whether this improvement connects in a direction.
    public func isConnected(to direction: Direction) -> Bool {
        let index = isRoad ? direction.ordinal
            : isRiver ? Direction.longSides.firstIndex(of: direction) : nil
        guard let index, let c = styleCharacter(index) else { return false }
        return c != "0"
    }

    private func setConnected(_ direction: Direction, _ value: Bool) {
        if style == nil || isConnected(to: direction) != value {
            setConnected(direction, value, String(magnitude))
        }
    }

    private func setConnected(_ direction: Direction, _ value: Bool, _ magnitude: String) {
        // Java starts a missing style as a road style, for rivers too.
        let old = Array((style ?? TileImprovementStyle(TileImprovement.emptyRoadStyle)!).string)
        var updated = ""
        for (index, d) in (connectionDirections ?? []).enumerated() {
            updated += d == direction ? (value ? magnitude : "0") : String(old[index])
        }
        style = TileImprovementStyle(updated)
    }

    /// The magnitude of each connection, by direction.
    public var connections: [Direction: Int] {
        var ret: [Direction: Int] = [:]
        for d in connectionDirections ?? [] where isConnected(to: d) {
            ret[d] = magnitude
        }
        return ret
    }

    /// This improvement's production modifier, scaled by its magnitude.
    private func productionModifier(_ goodsType: GoodsType) -> Modifier? {
        guard isComplete, let modifier = type?.productionModifier(goodsType) else { return nil }
        if modifier.value == 0 || magnitude <= 0 { return modifier }
        let scaled = Modifier(copying: modifier)
        scaled.value = modifier.value * Float(magnitude)
        return scaled
    }

    /// The cost of a move across this improvement in a direction.
    public func moveCost(_ direction: Direction, _ moveCost: Int) -> Int {
        isComplete && isConnected(to: direction) ? (type?.moveCost(moveCost) ?? moveCost) : moveCost
    }

    /// The tile type this finished improvement changes a type into.
    public func change(_ tileType: TileType?) -> TileType? {
        isComplete ? type?.change(tileType) : nil
    }

    /// The connections as a bit set, one bit per direction ordinal.
    public var connectionsFromStyle: Int64 {
        guard let style, let directions = connectionDirections else { return 0 }
        var conn: Int64 = 0
        for (i, c) in style.mask.enumerated() where i < directions.count && c != "0" {
            conn |= 1 << Int64(directions[i].ordinal)
        }
        return conn
    }

    /// Set a river's connections from a style, adding small rivers to
    /// neighbouring land where it flows, and the magnitude from the
    /// larger connections.
    public func setRiverStyle(_ conns: String?) {
        guard isRiver, let tile else { return }
        var counts = [0, 0]
        for (i, d) in Direction.longSides.enumerated() {
            let reverse = d.reverseDirection
            let t = tile.neighbour(d)
            let river = t?.river
            let c = conns.map { JavaString.substring($0, i, i + 1) } ?? "0"
            if c == "0" {
                river?.setConnected(reverse, false)
                setConnected(d, false)
            } else {
                let mag = Int(c) ?? 0
                if let river {
                    river.setConnected(reverse, true)
                    setConnected(d, true, c)
                    counts[mag - 1] += 1
                } else if let t {
                    if !(t.type?.isWater ?? false) {
                        t.addRiver(mag, TileImprovement.emptyRiverStyle)
                        t.river?.setConnected(reverse, true)
                    }
                    setConnected(d, true, c)
                    counts[mag - 1] += 1
                }
            }
        }
        magnitude = counts[1] >= counts[0] ? 2 : 1
    }

    /// Connect a river to the neighbouring rivers and water a style
    /// asks for, disconnecting the rest.
    ///
    /// - Returns: The new style string.
    @discardableResult
    public func updateRiverConnections(_ conns: String?) -> String? {
        guard isRiver, let tile else { return nil }
        for (i, d) in Direction.longSides.enumerated() {
            let reverse = d.reverseDirection
            let t = tile.neighbour(d)
            let river = t?.river
            let c = conns.map { JavaString.substring($0, i, i + 1) } ?? "0"
            if c == "0" {
                river?.setConnected(reverse, false)
                setConnected(d, false)
            } else if let river {
                river.setConnected(reverse, true)
                setConnected(d, true)
            } else if let t, t.type?.isWater ?? false {
                setConnected(d, true)
            }
        }
        return style?.string
    }

    /// Connect (or disconnect) a finished road to the neighbouring
    /// finished roads.
    ///
    /// - Returns: The new style string.
    @discardableResult
    public func updateRoadConnections(_ connect: Bool) -> String? {
        guard isRoad, isComplete, let tile else { return nil }
        for d in Direction.allDirections {
            if let road = tile.neighbour(d)?.road, road.isComplete {
                road.setConnected(d.reverseDirection, connect)
                setConnected(d, connect)
            } else {
                setConnected(d, false)
            }
        }
        return style?.string
    }

    /// The possible disasters, with their weights.
    public var disasters: [RandomChoice<Disaster>] {
        type?.disasters ?? []
    }

    // MARK: TileItem

    public override var zIndex: Int {
        type?.zIndex ?? 0
    }

    public override func isTileTypeAllowed(_ tileType: TileType) -> Bool {
        type?.isTileTypeAllowed(tileType) ?? false
    }

    /// The bonuses apply to the unit type's potential, only where the
    /// tile already produces something and only once finished.
    public override func applyBonus(_ goodsType: GoodsType, _ unitType: UnitType?,
                                    _ potential: Int) -> Int {
        guard potential > 0, isComplete else { return potential }
        return potential + (productionModifier(goodsType).map { Int(JavaMath.toInt($0.value)) } ?? 0)
    }

    /// Improvements raise production but never make it possible.
    public override func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        false
    }

    public override func productionModifiers(_ goodsType: GoodsType?,
                                             _ unitType: UnitType?) -> [Modifier] {
        guard let goodsType, isComplete else { return [] }
        if unitType == nil && isNatural && goodsType.isFoodType { return [] }
        if unitType == nil && !isNatural && !goodsType.isFoodType
            && (specification?.getBoolean(GameOptions.onlyNaturalImprovements) ?? false) {
            return []
        }
        guard var m = productionModifier(goodsType) else { return [] }
        if let unitType, let expert = unitType.expertProduction, expert === goodsType {
            let multiplicative = unitType.modifiers(goodsType.id, for: tile?.type)
                .filter { $0.type == .multiplicative }
            let expertBonus = FeatureContainer.applyModifiers(m.value, turn: nil, multiplicative)
            m = Modifier(copying: m)
            m.value = expertBonus
        }
        return [m]
    }

    public override var isNatural: Bool {
        type?.isNatural ?? false
    }

    /// Whether a unit may work on this unfinished improvement.
    public func isWorkerAllowed(_ unit: Unit?) -> Bool {
        guard let unit, !isComplete else { return false }
        return type?.isWorkerAllowed(unit) ?? false
    }

    public override var isComplete: Bool {
        turnsToComplete <= 0
    }

    public override var layer: Map.Layer { .rivers }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        tile = try xr.makeFreeColObject(game!, "tile", Tile.self, required: true)
        type = try specification.flatMap { try xr.getType($0, "type", TileImprovementType.self) }
        turnsToComplete = xr.attribute("turns", default: 0)
        magnitude = xr.attribute("magnitude", default: 0)
        isVirtual = xr.attribute("virtual", default: false)
        style = nil
        let str = xr.attribute("style", default: nil as String?)
        if let directions = connectionDirections {
            if let str {
                if str.utf16.count != directions.count {
                    xr.warn("At \(tile.map { "\($0)" } ?? "null") ignored bogus style for"
                        + " \(type?.id ?? "null"): \(str)")
                } else {
                    style = TileImprovementStyle(str)
                }
            }
            // A missing style is fine for unfinished roads, and old saves
            // have some missing on others; checkIntegrity fixes those.
        } else if let str, !str.isEmpty {
            xr.warn("At \(tile.map { "\($0)" } ?? "null") ignored nonempty style for"
                + " \(type?.id ?? "null"): \(str)")
        }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("tile", tile)
        xw.writeAttribute("type", type)
        xw.writeAttribute("turns", turnsToComplete)
        xw.writeAttribute("magnitude", magnitude)
        if let style { xw.writeAttribute("style", style.string) }
        if isVirtual { xw.writeAttribute("virtual", isVirtual) }
    }

    public override var description: String {
        var s = "[" + (type?.id ?? "NOTYPE")
        if turnsToComplete > 0 { s += " (\(turnsToComplete) turns left)" }
        if let style { s += " " + style.string }
        return s + "]"
    }
}

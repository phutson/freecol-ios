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

import Foundation
import FreeColUtil
import FreeColXML

/// A rectangular isometric map of tiles (common/model/Map).
///
/// Rows are staggered: odd rows are shifted half a tile right, and the
/// neighbours of (x, y) depend on whether y is odd (see Direction).
///
/// The map holds its tiles and regions.
///
/// Not yet ported:
/// Path finding is in MapSearch.swift.
///
/// - scale, which creates tiles and so needs a server game;
/// - copyIn and checkIntegrity.
public final class Map: FreeColGameObject, GameObjectReadable, Location {

    public static let tag = "map"

    /// The number of rows at the top and bottom that are polar.
    public static let polarHeight = 2

    /// How much of the map is filled in.  RIVERS includes every natural
    /// improvement that is not a resource.
    public enum Layer: JavaEnum, Comparable, CustomStringConvertible {
        case none, land, terrain, regions, rivers, resources, rumours, natives, all

        public var javaName: String {
            switch self {
            case .none: "NONE"
            case .land: "LAND"
            case .terrain: "TERRAIN"
            case .regions: "REGIONS"
            case .rivers: "RIVERS"
            case .resources: "RESOURCES"
            case .rumours: "RUMOURS"
            case .natives: "NATIVES"
            case .all: "ALL"
            }
        }

        public static func < (a: Layer, b: Layer) -> Bool {
            a.ordinal < b.ordinal
        }

        public var description: String {
            javaName
        }
    }

    /// A position on the map (Map.Position).
    public struct Position: Hashable, Sendable, CustomStringConvertible {
        public let x: Int
        public let y: Int

        public init(_ x: Int, _ y: Int) {
            self.x = x
            self.y = y
        }

        public init(_ tile: Tile) {
            self.init(tile.x, tile.y)
        }

        /// The position one step in a direction from another, or the
        /// same position for no direction.
        public init(_ start: Position, _ direction: Direction?) {
            self = direction.map { $0.step(start.x, start.y) } ?? start
        }

        public func isValid(_ width: Int, _ height: Int) -> Bool {
            Map.inBox(x, y, width, height)
        }

        /// The distance in tiles between two positions.  Java's comment:
        /// the formula "has been developed largely through trial and
        /// error".
        public static func xyDistance(_ ax: Int, _ ay: Int, _ bx: Int, _ by: Int) -> Int {
            // Java's / and % truncate towards zero, as Swift's do.
            var r = (bx - ax) - (ay - by) / 2
            if by > ay && ay % 2 == 0 && by % 2 != 0 {
                r += 1
            } else if by < ay && ay % 2 != 0 && by % 2 == 0 {
                r -= 1
            }
            return max(abs(ay - by + r), abs(r))
        }

        public func distance(to position: Position) -> Int {
            Position.xyDistance(x, y, position.x, position.y)
        }

        /// The direction to an adjacent position, or nil.
        public func direction(to other: Position) -> Direction? {
            Direction.allDirections.first { Position(self, $0) == other }
        }

        public var description: String {
            "(\(x), \(y))"
        }
    }

    public private(set) var width = -1
    public private(set) var height = -1
    /// The tiles by column, then row.
    private var tileArray: [Tile?] = []
    /// The tiles in the order they were added.
    private var tileList: [Tile] = []
    public var layer: Layer = .resources
    /// The latitude of the top row; negative is north.
    public var minimumLatitude = -90 {
        didSet { calculateLatitudePerRow() }
    }
    /// The latitude of the bottom row.
    public var maximumLatitude = 90 {
        didSet { calculateLatitudePerRow() }
    }
    public private(set) var latitudePerRow: Float = 0
    private var regionList: [Region] = []

    /// A new empty map with a fresh identifier.
    public init(game: Game, width: Int, height: Int) {
        super.init(game: game)
        _ = setTiles(width, height)
        calculateLatitudePerRow()
    }

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    public override var xmlTagName: String {
        Map.tag
    }

    // MARK: Tiles

    public static func inBox(_ x: Int, _ y: Int, _ width: Int, _ height: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
    }

    public func isValid(_ x: Int, _ y: Int) -> Bool {
        Map.inBox(x, y, width, height)
    }

    public func isValid(_ position: Position) -> Bool {
        isValid(position.x, position.y)
    }

    /// Set the size, once.
    ///
    /// - Returns: An error, or nil.
    private func setTiles(_ width: Int, _ height: Int) -> String? {
        if width <= 0 || height <= 0 {
            return "Bad map tile array size: (\(width),\(height))"
        }
        self.width = width
        self.height = height
        tileArray = Array(repeating: nil, count: width * height)
        tileList = []
        return nil
    }

    /// Set the size the first time, and otherwise check it is unchanged.
    private func updateTiles(_ width: Int, _ height: Int) -> String? {
        if self.width < 0 && self.height < 0 { return setTiles(width, height) }
        if self.width != width || self.height != height {
            return "Attempted map resize (\(self.width),\(self.height) -> \(width),\(height))"
        }
        return nil
    }

    /// The tile at a position, or nil off the map.
    public func tile(_ x: Int, _ y: Int) -> Tile? {
        isValid(x, y) ? tileArray[x * height + y] : nil
    }

    public func tile(_ position: Position) -> Tile? {
        tile(position.x, position.y)
    }

    @discardableResult
    private func setTile(_ tile: Tile?, _ x: Int, _ y: Int) -> Bool {
        guard let tile else { return false }
        tileArray[x * height + y] = tile
        tileList.append(tile)
        return true
    }

    /// Add a tile read from a saved game.  Java copies a tile read
    /// again into the existing one; Swift reads into the same object,
    /// so only new tiles need adding.
    private func updateTile(_ tile: Tile?) -> Bool {
        guard let tile, isValid(tile.x, tile.y) else { return false }
        guard let old = tileArray[tile.x * height + tile.y] else {
            return setTile(tile, tile.x, tile.y)
        }
        return old === tile
    }

    /// Fill the map with tiles, row by row.
    ///
    /// - Returns: false if a tile could not be made.
    @discardableResult
    public func populateTiles(_ make: (Int, Int) -> Tile?) -> Bool {
        for y in 0..<height {
            for x in 0..<width {
                if !setTile(make(x, y), x, y) { return false }
            }
        }
        return true
    }

    /// All the tiles, in the order they were added (row by row).
    public var tiles: [Tile] {
        tileList
    }

    public func tileList(_ predicate: (Tile) -> Bool) -> [Tile] {
        tileList.filter(predicate)
    }

    public func tileSet(_ predicate: (Tile) -> Bool) -> Set<Tile> {
        Set(tileList.filter(predicate))
    }

    public func forEachTile(_ body: (Tile) -> Void) {
        tileList.forEach(body)
    }

    public func forEachTile(where predicate: (Tile) -> Bool, _ body: (Tile) -> Void) {
        for t in tileList where predicate(t) { body(t) }
    }

    /// The tiles in a rectangle, clipped to the map, row by row.
    public func subMap(_ x: Int, _ y: Int, _ w: Int, _ h: Int) -> [Tile] {
        var x = x, y = y, w = w, h = h
        if x < 0 {
            w += x
            x = 0
        }
        if y < 0 {
            h += y
            y = 0
        }
        if w <= 0 || h <= 0 || x > width || y > height { return [] }
        if x + w > width { w = width - x }
        if y + h > height { h = height - y }
        var ret: [Tile] = []
        for yi in y..<(y + h) {
            for xi in x..<(x + w) {
                if let t = tile(xi, yi) { ret.append(t) }
            }
        }
        return ret
    }

    /// All the tiles in random order.
    public func shuffledTiles(_ random: JavaRandom) -> [Tile] {
        var ret = tileList
        RandomUtils.randomShuffle("All tile shuffle", &ret, random)
        return ret
    }

    // MARK: Latitude

    private func calculateLatitudePerRow() {
        latitudePerRow = Float(maximumLatitude - minimumLatitude) / Float(height - 1)
    }

    /// The latitude of a row.
    public func latitude(_ row: Int) -> Int {
        minimumLatitude + Int(JavaMath.toInt(Float(row) * latitudePerRow))
    }

    /// The row nearest a latitude.
    public func row(_ latitude: Int) -> Int {
        Int(JavaMath.toInt(Float(latitude - minimumLatitude) / latitudePerRow))
    }

    // MARK: Regions

    public var regions: [Region] {
        regionList
    }

    public func addRegion(_ region: Region) {
        regionList.append(region)
    }

    public func removeRegion(_ region: Region) {
        if let i = regionList.firstIndex(where: { $0 === region }) { regionList.remove(at: i) }
    }

    public func clearRegions() {
        regionList = []
    }

    /// The predefined regions, by key.
    public var fixedRegions: [String: Region] {
        var ret: [String: Region] = [:]
        for r in regionList {
            if let key = r.key { ret[key] = r }
        }
        return ret
    }

    public func region(byKey key: String?) -> Region? {
        guard let key else { return nil }
        return regionList.first { $0.key == key }
    }

    public func removeRegions(byKey key: String) {
        regionList.removeAll { $0.key == key }
    }

    public func region(byName name: String?) -> Region? {
        guard let name else { return nil }
        return regionList.first { $0.name == name }
    }

    // MARK: Geometry

    /// Whether two tiles are in the same land or water mass.
    public static func isSameContiguity(_ t1: Tile?, _ t2: Tile?) -> Bool {
        guard let t1, let t2 else { return false }
        return t1 === t2 || t1.isConnected(to: t2)
    }

    public func isPolar(_ tile: Tile) -> Bool {
        tile.y <= Map.polarHeight || tile.y >= height - Map.polarHeight - 1
    }

    /// The direction from one tile to an adjacent one, or nil.
    public func direction(_ t1: Tile?, _ t2: Tile?) -> Direction? {
        guard let t1, let t2 else { return nil }
        return Position(t1).direction(to: Position(t2))
    }

    /// The rough direction from one tile to another, or nil if they are
    /// the same.
    public static func roughDirection(_ src: Tile, _ dst: Tile) -> Direction? {
        let x = dst.x - src.x
        let y = dst.y - src.y
        if x == 0 && y == 0 { return nil }
        var theta = atan2(Double(y), Double(x)) + Double.pi / 2 + Double.pi / 8
        if theta < 0 { theta += 2 * Double.pi }
        return Direction.angleToDirection(theta)
    }

    public func adjacentTile(_ x: Int, _ y: Int, _ direction: Direction) -> Tile? {
        tile(direction.step(x, y))
    }

    public func adjacentTile(_ tile: Tile, _ direction: Direction) -> Tile? {
        adjacentTile(tile.x, tile.y, direction)
    }

    public func distance(_ t1: Tile, _ t2: Tile) -> Int {
        Position.xyDistance(t1.x, t1.y, t2.x, t2.y)
    }

    /// The closest of some tiles to a tile; the first on ties.
    public func closestTile<S: Sequence>(_ tile: Tile, _ tiles: S) -> Tile? where S.Element == Tile {
        var best: Tile?
        var bestDistance = 0
        for t in tiles {
            let d = distance(t, tile)
            if best == nil || d < bestDistance {
                best = t
                bestDistance = d
            }
        }
        return best
    }

    /// A random land tile: the first land found spiralling out from a
    /// random position away from the edges.
    public func randomLandTile(_ random: JavaRandom) -> Tile? {
        let slosh = 10
        var x = 0, y = 0, w = width, h = height
        if w >= slosh {
            w -= slosh
            x += slosh / 2
        }
        if h >= slosh {
            h -= slosh
            y += slosh / 2
        }
        x += Int(RandomUtils.randomInt("W", random, Int32(w)))
        y += Int(RandomUtils.randomInt("H", random, Int32(h)))
        guard let center = tile(x, y) else { return nil }
        return circleTiles(center, filled: true, radius: Constants.infinity).first(where: \.isLand)
    }

    /// The first land tile within a distance of a position, nearest
    /// first.
    public func landWithinDistance(_ x: Int, _ y: Int, _ distance: Int) -> Tile? {
        guard let center = tile(x, y) else { return nil }
        return circleTiles(center, filled: true, radius: distance).first(where: \.isLand)
    }

    // MARK: Circles

    /// The tiles in a circle round a center, nearest first and clockwise
    /// from NE in each ring, without the center (Map.CircleIterator).
    public struct CircleTiles: Sequence {
        let map: Map
        let center: Tile
        let filled: Bool
        let radius: Int

        public func makeIterator() -> CircleIterator {
            CircleIterator(map, center, filled, radius)
        }
    }

    /// The iterator for CircleTiles.
    public struct CircleIterator: IteratorProtocol {
        private let map: Map
        private let radius: Int
        private var currentRadius = 0
        private var n = 0
        private var x = 0
        private var y = 0

        init(_ map: Map, _ center: Tile, _ filled: Bool, _ radius: Int) {
            self.map = map
            self.radius = radius
            if radius <= 0 {
                x = Constants.undefined
                y = Constants.undefined
            } else if filled || radius == 1 {
                let step = Direction.ne.step(center.x, center.y)
                x = step.x
                y = step.y
                currentRadius = 1
            } else {
                currentRadius = radius
                x = center.x
                y = center.y
                for _ in 1..<radius {
                    let step = Direction.n.step(x, y)
                    x = step.x
                    y = step.y
                }
                let step = Direction.ne.step(x, y)
                x = step.x
                y = step.y
            }
            if !map.isValid(x, y) { nextTile() }
        }

        /// Move to the next valid position.
        private mutating func nextTile() {
            var started = n != 0
            repeat {
                n += 1
                let width = currentRadius * 2
                if n >= width * 4 {
                    currentRadius += 1
                    if currentRadius > radius || !started {
                        x = Constants.undefined
                        y = Constants.undefined
                        break
                    }
                    n = 0
                    started = false
                    let step = Direction.ne.step(x, y)
                    x = step.x
                    y = step.y
                } else {
                    let direction: Direction
                    switch n / width {
                    case 0: direction = .se
                    case 1: direction = .sw
                    case 2: direction = .nw
                    default: direction = .ne
                    }
                    let step = direction.step(x, y)
                    x = step.x
                    y = step.y
                }
            } while !map.isValid(x, y)
        }

        public mutating func next() -> Tile? {
            guard x != Constants.undefined && y != Constants.undefined else { return nil }
            let result = map.tile(x, y)
            nextTile()
            return result
        }
    }

    /// The tiles in a circle round a center, nearest first, without the
    /// center; for an unfilled circle, only the ring at the radius.
    public func circleTiles(_ center: Tile, filled: Bool, radius: Int) -> CircleTiles {
        CircleTiles(map: self, center: center, filled: filled, radius: radius)
    }

    // MARK: Contiguity and high seas

    /// Flood fill from a position over the true cells of a grid
    /// (indexed [x][y]), stopping after a number of positions.
    ///
    /// - Returns: The cells reached.
    public static func floodFillBool(_ boolmap: [[Bool]], _ x: Int, _ y: Int,
                                     limit: Int = Int(Int32.max)) -> [[Bool]] {
        let xmax = boolmap.count, ymax = boolmap[0].count
        var visited = Array(repeating: Array(repeating: false, count: ymax), count: xmax)
        var queue: [Position] = []
        var head = 0
        var limit = limit
        visited[x][y] = true
        var p: Position? = Position(x, y)
        while let current = p {
            limit -= 1
            if limit <= 0 { break }
            for d in Direction.allDirections {
                let np = Position(current, d)
                guard np.isValid(xmax, ymax) else { continue }
                if boolmap[np.x][np.y] && !visited[np.x][np.y] {
                    visited[np.x][np.y] = true
                    queue.append(np)
                }
            }
            p = head < queue.count ? queue[head] : nil
            head += 1
        }
        return visited
    }

    /// Number the land and water masses: water first, then land, each
    /// in the order their top-left tiles appear row by row.
    public func resetContiguity() {
        var waterMap = Array(repeating: Array(repeating: false, count: height), count: width)
        for y in 0..<height {
            for x in 0..<width {
                guard let t = tile(x, y) else { continue }
                waterMap[x][y] = !t.isLand
                t.contiguity = -1
            }
        }
        // Java passes the starting number by value, so land numbering
        // starts from 0 again, the same as water's.
        floodFill(0, waterMap)
        for y in 0..<height {
            for x in 0..<width where isValid(x, y) {
                waterMap[x][y] = !waterMap[x][y]
            }
        }
        floodFill(0, waterMap)
    }

    private func floodFill(_ contig: Int, _ waterMap: [[Bool]]) {
        var contig = contig
        for y in 0..<height {
            for x in 0..<width where waterMap[x][y] {
                guard let t = tile(x, y), t.contiguity < 0 else { continue }
                let found = Map.floodFillBool(waterMap, x, y)
                for yy in 0..<height {
                    for xx in 0..<width where found[xx][yy] {
                        if let t = tile(xx, yy), t.contiguity < 0 { t.contiguity = contig }
                    }
                }
                contig += 1
            }
        }
    }

    /// The innermost tiles directly connected to the high seas on each
    /// row's east and west sides, where European units can start.
    public func collectStartingTiles() -> (east: [Tile], west: [Tile]) {
        let west = 0, east = width - 1
        var eastTiles: [Tile] = [], westTiles: [Tile] = []
        for y in 0..<height {
            if var ok = tile(east, y), ok.isDirectlyHighSeasConnected {
                var x = east
                while x > west {
                    guard let t = tile(x, y), t.isDirectlyHighSeasConnected else { break }
                    ok = t
                    x -= 1
                }
                eastTiles.append(ok)
            }
            if var ok = tile(west, y), ok.isDirectlyHighSeasConnected {
                var x = west
                while x < east {
                    guard let t = tile(x, y), t.isDirectlyHighSeasConnected else { break }
                    ok = t
                    x += 1
                }
                westTiles.append(ok)
            }
        }
        return (eastTiles, westTiles)
    }

    /// Place the high seas along the east and west edges: ocean tiles
    /// near an edge and far enough from land.  Other high seas become
    /// ocean.
    ///
    /// - Parameters:
    ///   - distToLandFromHighSeas: The least distance from high seas to
    ///     land.
    ///   - maxDistanceToEdge: The greatest distance from high seas to
    ///     the map edge.
    public func resetHighSeas(_ distToLandFromHighSeas: Int, _ maxDistanceToEdge: Int) {
        guard let spec = specification,
              let ocean = spec.getTileType("model.tile.ocean"),
              let highSeas = spec.getTileType("model.tile.highSeas") else {
            preconditionFailure("HighSeas and Ocean TileTypes must exist")
        }
        precondition(distToLandFromHighSeas >= 0 && maxDistanceToEdge >= 0)
        forEachTile(where: { $0.type === highSeas }) { $0.type = ocean }

        var seaL: Tile?, seaR: Tile?
        var totalL = 0, totalR = 0, distanceL = -1, distanceR = -1
        for y in 0..<height {
            var x = 0
            while x < maxDistanceToEdge && x < width, let t = tile(x, y), t.type === ocean {
                if let other = landWithinDistance(x, y, distToLandFromHighSeas) {
                    let distance = t.distance(to: other)
                    if distanceL < distance {
                        distanceL = distance
                        seaL = t
                    }
                } else {
                    t.type = highSeas
                    totalL += 1
                }
                x += 1
            }
            x = 0
            while x < maxDistanceToEdge && x < width, let t = tile(width - 1 - x, y), t.type === ocean {
                if let other = landWithinDistance(width - 1 - x, y, distToLandFromHighSeas) {
                    let distance = t.distance(to: other)
                    if distanceR < distance {
                        distanceR = distance
                        seaR = t
                    }
                } else {
                    t.type = highSeas
                    totalR += 1
                }
                x += 1
            }
        }
        if totalL <= 0, let seaL {
            seaL.type = highSeas
            totalL += 1
        }
        if totalR <= 0, let seaR {
            seaR.type = highSeas
            totalR += 1
        }
        // Java warns when a side has no high seas, which breaks small
        // test maps.
    }

    /// Count the tiles from each tile to the high seas, stopping at
    /// land, so only coastal land gets a count.  Ocean on the left and
    /// right edges that could reach the high seas, and has no explicit
    /// setting, is marked as moving to Europe.
    public func resetHighSeasCount() {
        var curr: [Tile] = []
        var next: [Tile] = []
        var hsc = 0
        for t in tileList {
            t.highSeasCount = -1
            guard !t.isLand else { continue }
            if (t.x == 0 || t.x == width - 1), let type = t.type,
               type.isHighSeasConnected, !type.isDirectlyHighSeasConnected,
               t.moveToEurope == nil {
                t.moveToEurope = true
            }
            if t.isDirectlyHighSeasConnected {
                t.highSeasCount = 0
                next.append(t)
            }
        }
        while !next.isEmpty {
            hsc += 1
            curr += next
            next = []
            // Java removes from the front of a list.
            for tile in curr {
                let position = Position(tile)
                for d in Direction.allDirections {
                    let p = Position(position, d)
                    guard let t = self.tile(p), t.highSeasCount < 0 else { continue }
                    t.highSeasCount = hsc
                    if !t.isLand { next.append(t) }
                }
            }
            curr = []
        }
    }

    /// Set the layer from what the map actually has.
    public func resetLayers() {
        var regions = false, rivers = false, lostCityRumours = false
        var resources = false, nativeSettlements = false
        for y in 0..<height {
            for x in 0..<width {
                guard let t = tile(x, y) else { continue }
                regions = regions || t.region != nil
                rivers = rivers || t.hasRiver
                lostCityRumours = lostCityRumours || t.hasLostCityRumour
                resources = resources || t.hasResource
                nativeSettlements = nativeSettlements || t.settlement is IndianSettlement
            }
        }
        layer = (rivers && lostCityRumours && resources && nativeSettlements) ? .all
            : nativeSettlements ? .natives
            : lostCityRumours ? .rumours
            : resources ? .resources
            : rivers ? .rivers
            : regions ? .regions
            : .terrain
    }

    /// Fix the region parents and children: mountain and river regions
    /// used to be children of the discoverable land region they were
    /// made in, rather than of its geographic parent.
    public func fixupRegions() {
        for r in regionList where !r.isPacific {
            var p = r.parent
            if let parent = p, parent.discoverable && r.discoverable {
                p = parent.parent
                r.parent = p
            }
            if let p, !(p.children ?? []).contains(where: { $0 === r }) { p.addChild(r) }
        }
    }

    /// A copy of a tile, perhaps from another game, at a position, with
    /// the items up to a layer.  Regions are not copied (a FIXME in
    /// Java).
    public func importTile(_ other: Tile, _ x: Int, _ y: Int, _ layer: Layer) -> Tile {
        let t = Tile(game: game!, type: other.type, x: x, y: y)
        if let moveToEurope = other.moveToEurope { t.moveToEurope = moveToEurope }
        if let otherContainer = other.tileItemContainer {
            let container = TileItemContainer(game: game!, tile: t)
            container.copyFrom(otherContainer, layer: layer)
            t.tileItemContainer = container
        }
        return t
    }

    // MARK: Location
    //
    // The map is where units arrive from the high seas; units on it are
    // on its tiles.

    public var tile: Tile? {
        nil
    }

    /// Units are added to their entry tiles, not the map.
    @discardableResult
    public func add(_ locatable: any Locatable) -> Bool {
        precondition(!(locatable is Unit), "Disabled Map.add(Unit): \(locatable)")
        return false
    }

    @discardableResult
    public func remove(_ locatable: any Locatable) -> Bool {
        guard locatable is Unit, let tile = locatable.tile else { return false }
        return tile.remove(locatable)
    }

    public func contains(_ locatable: any Locatable) -> Bool {
        locatable is Unit && locatable.location?.tile != nil
    }

    public func canAdd(_ locatable: any Locatable) -> Bool {
        locatable is Unit
    }

    public var unitCount: Int {
        -1
    }

    public var unitList: [Unit] {
        []
    }

    public var goodsContainer: GoodsContainer? {
        nil
    }

    public var settlement: Settlement? {
        nil
    }

    public var colony: Colony? {
        nil
    }

    public var indianSettlement: IndianSettlement? {
        nil
    }

    public func up() -> any Location {
        self
    }

    public var rank: Int {
        LocationRank.nowhere
    }

    public var shortDescription: String {
        "Map"
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        if let err = updateTiles(xr.attribute("width", default: -1), xr.attribute("height", default: -1)) {
            throw FreeColXMLError("Map.readAttributes failure, " + err)
        }
        layer = xr.attribute("layer", Layer.self, default: .all) ?? .all
        minimumLatitude = xr.attribute("minimumLatitude", default: -90)
        maximumLatitude = xr.attribute("maximumLatitude", default: 90)
        calculateLatitudePerRow()
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("width", width)
        xw.writeAttribute("height", height)
        xw.writeAttribute("layer", layer)
        xw.writeAttribute("minimumLatitude", minimumLatitude)
        xw.writeAttribute("maximumLatitude", maximumLatitude)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for region in sortedById(regions) { region.toXML(xw) }
        for y in 0..<max(height, 0) {
            for x in 0..<max(width, 0) { tile(x, y)?.toXML(xw) }
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        // The tiles are not cleared, unlike most containers: they are
        // read into the same objects.
        try super.readChildren(xr)
        // Settlements learn their tiles here, once all are read, rather
        // than as each tile is read.
        for t in tileList { t.owningSettlement?.addTile(t) }
        // @compat 0.11.3: maps with broken parent and child chains.
        fixupRegions()
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let game = game!
        switch xr.localName {
        case Region.tag:
            if let region = try xr.readFreeColObject(game, Region.self) { addRegion(region) }
        case Tile.tag:
            let t = try xr.readFreeColObject(game, Tile.self)
            if !updateTile(t) {
                xr.warn("Tile update failure for: \(t.map { "\($0)" } ?? "null")")
            }
        default:
            try super.readChild(xr)
        }
    }
}

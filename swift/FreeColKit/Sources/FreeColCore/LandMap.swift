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

/// Where the land is, before there are tiles (common/model/LandMap): made
/// by one of four generators from the map generator options, or taken
/// from a map.
public final class LandMap {

    /// The land generators (MapGeneratorOptions.LAND_GENERATOR_*).
    public static let landGeneratorClassic = 0
    public static let landGeneratorContinent = 1
    public static let landGeneratorArchipelago = 2
    public static let landGeneratorIslands = 3

    public let width: Int
    public let height: Int
    private let cache: RandomUtils.RandomIntCache
    private var map: [[Bool]]
    public private(set) var numberOfLandTiles = 0

    /// An empty land map.
    public init(width: Int, height: Int, cache: RandomUtils.RandomIntCache) {
        self.width = width
        self.height = height
        self.cache = cache
        map = Array(repeating: Array(repeating: false, count: height), count: width)
    }

    /// The land of an existing map.
    public convenience init(map other: Map, cache: RandomUtils.RandomIntCache) {
        self.init(width: other.width, height: other.height, cache: cache)
        for y in 0..<height {
            for x in 0..<width {
                map[x][y] = other.tile(x, y)?.isLand ?? false
                if map[x][y] { numberOfLandTiles += 1 }
            }
        }
    }

    /// Land made as the map generator options say.
    public convenience init(options spec: Specification, cache: RandomUtils.RandomIntCache) {
        self.init(width: spec.getInteger(MapGeneratorOptions.mapWidth) ?? 40,
                  height: spec.getInteger(MapGeneratorOptions.mapHeight) ?? 100, cache: cache)
        let distanceToEdge = spec.getInteger(MapGeneratorOptions.preferredDistanceToEdge) ?? 0
        let minNumberOfTiles = (spec.getInteger(MapGeneratorOptions.landMass) ?? 0) * width * height / 100
        let gen = spec.getSelection(MapGeneratorOptions.landGeneratorType) ?? LandMap.landGeneratorClassic
        generate(gen, distanceToEdge, minNumberOfTiles)
    }

    public func isValid(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height
    }

    public func isLand(_ x: Int, _ y: Int) -> Bool {
        isValid(x, y) ? map[x][y] : false
    }

    public var hasLand: Bool {
        map.contains { $0.contains(true) }
    }

    @discardableResult
    private func setLand(_ x: Int, _ y: Int) -> Bool {
        if isLand(x, y) { return false }
        map[x][y] = true
        numberOfLandTiles += 1
        return true
    }

    /// Make land, and perhaps grow it to the sides.
    private func setLand(_ x: Int, _ y: Int, _ distanceToEdge: Int) {
        if !setLand(x, y) { return }
        let p = Map.Position(x, y)
        for direction in Direction.longSides {
            let n = Map.Position(p, direction)
            if n.isValid(width, height) { growLand(n.x, n.y, distanceToEdge) }
        }
    }

    private func generate(_ type: Int, _ distanceToEdge: Int, _ minNumberOfTiles: Int) {
        switch type {
        case LandMap.landGeneratorClassic:
            createClassicLandMap(distanceToEdge, minNumberOfTiles)
        case LandMap.landGeneratorContinent:
            addPolarRegions()
            // Create one landmass of 75%, the rest in small islands.
            let contsize = (minNumberOfTiles * 75) / 100
            let h = height / 4 + cache.nextInt(height / 2)
            addLandMass(contsize, contsize, width / 2, h, distanceToEdge)
            while numberOfLandTiles < minNumberOfTiles {
                addLandMass(15, 25, -1, -1, distanceToEdge)
            }
        case LandMap.landGeneratorArchipelago:
            addPolarRegions()
            // Five large islands, then fall through to the islands.
            let archsize = (minNumberOfTiles * 10) / 100
            for _ in 0..<5 {
                addLandMass(archsize - 5, archsize + 5, -1, -1, distanceToEdge)
            }
            addIslands(distanceToEdge, minNumberOfTiles)
        case LandMap.landGeneratorIslands:
            addIslands(distanceToEdge, minNumberOfTiles)
        default:
            break
        }
        cleanMap()
    }

    private func addIslands(_ distanceToEdge: Int, _ minNumberOfTiles: Int) {
        addPolarRegions()
        while numberOfLandTiles < minNumberOfTiles {
            addLandMass(25, 25 + cache.nextInt(50), -1, -1, distanceToEdge)
        }
    }

    private func createClassicLandMap(_ distanceToEdge: Int, _ minNumberOfTiles: Int) {
        var minNumberOfTiles = minNumberOfTiles
        let edg = distanceToEdge * 2
        let wid = width - edg * 2
        let hgt = height - edg * 2
        var x = 0, y = 0
        while numberOfLandTiles < minNumberOfTiles {
            var failCounter = 0
            repeat {
                x = edg + cache.nextInt(wid)
                y = edg + cache.nextInt(hgt)
                failCounter += 1
                // If landmass% is set too high, this loop may fail
                // to find a free tile.  Decrease necessary minimum
                // over time, so that this process will eventually end.
                if failCounter > 100 {
                    failCounter = 0
                    minNumberOfTiles -= 1
                    break
                }
            } while isLand(x, y)
            setLand(x, y, distanceToEdge)
        }
        addPolarRegions()
    }

    private func addPolarRegions() {
        for x in 0..<width {
            for y in 0..<Map.polarHeight { setLand(x, y) }
            let limit = height - 1 - Map.polarHeight
            for y in limit..<height { setLand(x, y) }
        }
    }

    /// Remove land with no land beside it.
    private func cleanMap() {
        for y in 0..<height {
            for x in 0..<width where !hasAdjacentLand(x, y) {
                map[x][y] = false
            }
        }
    }

    private func hasAdjacentLand(_ x: Int, _ y: Int) -> Bool {
        let p = Map.Position(x, y)
        return Direction.allDirections.contains { d in
            let n = Map.Position(p, d)
            return isLand(n.x, n.y)
        }
    }

    /// The positions to the sides with no land beside them, away from
    /// the edges.
    private func newPositions(_ position: Map.Position, _ distanceToEdge: Int) -> [Map.Position] {
        Direction.longSides.map { Map.Position(position, $0) }.filter { p in
            p.isValid(width, height) && !hasAdjacentLand(p.x, p.y)
                && p.x > distanceToEdge && p.x < width - distanceToEdge
        }
    }

    /// Make land if enough land is around, less likely near the edges.
    private func growLand(_ x: Int, _ y: Int, _ distanceToEdge: Int) {
        if isLand(x, y) { return }
        let edgeX: Int = distanceToEdge - min(x, width - x)
        let edgeY: Int = 2 * distanceToEdge - min(y, height - y)
        let r: Int = cache.nextInt(8) + max(-1, 1 + max(edgeX, edgeY))
        let p = Map.Position(x, y)
        let count = Direction.allDirections.filter { d in
            let n = Map.Position(p, d)
            return isLand(n.x, n.y)
        }.count
        if count > r { setLand(x, y, distanceToEdge) }
    }

    /// Grow a landmass from a point, at random if none is given, and add
    /// it if it reached the minimum size.
    ///
    /// - Returns: Its size, or 0 if it was too small.
    @discardableResult
    private func addLandMass(_ minSize: Int, _ maxSize: Int, _ x: Int, _ y: Int, _ distanceToEdge: Int) -> Int {
        var size = 0
        var x = x, y = y
        var newLand = Array(repeating: Array(repeating: false, count: height), count: width)
        if x < 0 || y < 0 {
            let wid = width - distanceToEdge * 2
            let hgt = height - distanceToEdge * 2
            repeat {
                x = distanceToEdge + cache.nextInt(wid)
                y = distanceToEdge + cache.nextInt(hgt)
            } while isLand(x, y) || hasAdjacentLand(x, y)
        }
        newLand[x][y] = true
        size += 1
        var p = Map.Position(x, y)
        var l = newPositions(p, distanceToEdge)
        let enough = minSize + cache.nextInt(maxSize - minSize + 1)
        while size < enough && !l.isEmpty {
            let i = cache.nextInt(l.count)
            p = l.remove(at: i)
            if !newLand[p.x][p.y] {
                newLand[p.x][p.y] = true
                size += 1
                l.append(contentsOf: newPositions(p, distanceToEdge))
            }
        }
        if size >= minSize {
            for xx in 0..<width {
                for yy in 0..<height where newLand[xx][yy] { setLand(xx, yy) }
            }
        }
        return size >= minSize ? size : 0
    }
}

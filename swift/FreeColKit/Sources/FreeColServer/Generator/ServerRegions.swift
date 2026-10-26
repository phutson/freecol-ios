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

import FreeColCore
import FreeColUtil

/// The predefined regions every map has (ServerRegion's static part).
enum ServerRegions {

    static let pacificScoreValue = 100

    /// A predefined region, added to the map
    /// (ServerRegion(Map, String, RegionType, Region)).
    private static func make(_ map: Map, _ key: String, _ type: Region.RegionType, _ parent: Region?) -> Region {
        let r = Region(game: map.game!, key: key, type: type, parent: parent)
        map.addRegion(r)
        return r
    }

    /// The rows splitting the non-polar land into thirds.
    private static func yForThirdsOfLand(_ map: Map) -> [Int] {
        var landTiles = Array(repeating: 0, count: map.height - 1)
        var sum = 0
        for t in map.tiles where t.isLand && !t.isPolar {
            landTiles[t.y] += 1
            sum += 1
        }
        return thirdsOfValues(landTiles, sum)
    }

    /// The columns splitting the land between two rows into thirds.
    private static func xForThirdsOfLand(_ map: Map, _ startY: Int, _ endY: Int) -> [Int] {
        var landTiles = Array(repeating: 0, count: map.width - 1)
        var sum = 0
        for t in map.subMap(0, startY, map.width - 1, endY - startY + 1) where t.isLand && !t.isPolar {
            landTiles[t.x] += 1
            sum += 1
        }
        return thirdsOfValues(landTiles, sum)
    }

    private static func thirdsOfValues(_ timesTheValue: [Int], _ sum: Int) -> [Int] {
        var result = [0, 0]
        var accumulatedSum = 0
        var needFirst = true
        for i in timesTheValue.indices {
            accumulatedSum += timesTheValue[i]
            if needFirst && accumulatedSum >= sum / 3 {
                result[0] = i
                needFirst = false
            }
            if accumulatedSum >= (2 * sum) / 3 {
                result[1] = i
                break
            }
        }
        return result
    }

    private static func ensureWithinMap(_ map: Map, _ x: Int, _ y: Int, _ width: Int, _ height: Int)
        -> JavaRectangle {
        let capX = max(0, x)
        let capY = max(0, y)
        let capWidth = min(map.width - 1, x + min(map.width - 1, width)) - capX
        let capHeight = min(map.height - 1, y + min(map.height - 1, height)) - capY
        return JavaRectangle(capX, capY, capWidth, capHeight)
    }

    /// A geographic land region over a part of the map, replacing any
    /// with its key.  Java adds it to the map twice.
    private static func geographic(_ map: Map, _ key: String, _ x: Int, _ y: Int, _ w: Int, _ h: Int) {
        map.removeRegions(byKey: key)
        let r = make(map, key, .land, nil)
        r.bounds.setBounds(ensureWithinMap(map, x, y, w, h))
        map.addRegion(r)
    }

    /// Make the predefined regions a map lacks: the polar regions, the
    /// nine geographic land regions (always remade), and the oceans,
    /// filled from the edges (requireFixedRegions).
    ///
    /// - Returns: The polar and ocean regions.
    static func requireFixedRegions(_ map: Map) -> [Region] {
        let fixed = map.fixedRegions
        var result: [Region] = []

        let arcticHeight = Map.polarHeight
        var arctic = fixed["model.region.arctic"]
        if arctic == nil {
            let r = make(map, "model.region.arctic", .land, nil)
            for x in 0..<map.width {
                for y in 0..<arcticHeight {
                    if let tile = map.tile(x, y), tile.isLand { r.addTile(tile) }
                }
            }
            arctic = r
        }
        result.append(arctic!)

        let antarcticHeight = map.height - Map.polarHeight - 1
        var antarctic = fixed["model.region.antarctic"]
        if antarctic == nil {
            let r = make(map, "model.region.antarctic", .land, nil)
            for x in 0..<map.width {
                for y in antarcticHeight..<map.height {
                    if let tile = map.tile(x, y), tile.isLand { r.addTile(tile) }
                }
            }
            antarctic = r
        }
        result.append(antarctic!)

        // The land regions, in thirds of the land each way.
        let maxInt = Int(Int32.max)
        let yThirds = yForThirdsOfLand(map)
        var xThirds = xForThirdsOfLand(map, 0, yThirds[0])
        geographic(map, "model.region.northWest", 0, 0, xThirds[0], yThirds[0])
        geographic(map, "model.region.north", xThirds[0], 0, xThirds[1] - xThirds[0], yThirds[0])
        geographic(map, "model.region.northEast", xThirds[1], 0, maxInt, yThirds[0])
        xThirds = xForThirdsOfLand(map, yThirds[0], yThirds[1])
        geographic(map, "model.region.west", 0, yThirds[0], xThirds[0], yThirds[1] - yThirds[0])
        geographic(map, "model.region.center", xThirds[0], yThirds[0], xThirds[1] - xThirds[0],
                   yThirds[1] - yThirds[0])
        geographic(map, "model.region.east", xThirds[1], yThirds[0], maxInt, yThirds[1] - yThirds[0])
        xThirds = xForThirdsOfLand(map, yThirds[1], map.height - 1)
        geographic(map, "model.region.southWest", 0, yThirds[1], xThirds[0], maxInt)
        geographic(map, "model.region.south", xThirds[0], yThirds[1], xThirds[1] - xThirds[0], maxInt)
        geographic(map, "model.region.southEast", xThirds[1], yThirds[1], maxInt, maxInt)

        var allOceans = true
        func ocean(_ key: String, _ parent: Region?, _ discoverable: Bool, _ score: Int = 0) -> Region {
            if let r = fixed[key] { return r }
            let r = make(map, key, .ocean, parent)
            r.discoverable = discoverable
            if score != 0 { r.scoreValue = score }
            allOceans = false
            return r
        }
        let pacific = ocean("model.region.pacific", nil, true, pacificScoreValue)
        result.append(pacific)
        let northPacific = ocean("model.region.northPacific", pacific, false)
        result.append(northPacific)
        let southPacific = ocean("model.region.southPacific", pacific, false)
        result.append(southPacific)
        let atlantic = ocean("model.region.atlantic", nil, false)
        result.append(atlantic)
        let northAtlantic = ocean("model.region.northAtlantic", atlantic, false)
        result.append(northAtlantic)
        let southAtlantic = ocean("model.region.southAtlantic", atlantic, false)
        result.append(southAtlantic)

        if !allOceans {
            // Fill the oceans from the first water up and down each side
            // of the middle, in a quarter, then a half, then the map.
            let maxx = map.width, midx = maxx / 2
            let maxy = map.height, midy = maxy / 2
            var tNP: Tile?, tSP: Tile?, tNA: Tile?, tSA: Tile?
            for y in stride(from: midy - 1, through: 0, by: -1) {
                if tNP == nil, let t = map.tile(0, y), !t.isLand { tNP = t }
                if tNA == nil, let t = map.tile(maxx - 1, y), !t.isLand { tNA = t }
                if tNP != nil && tNA != nil { break }
            }
            for y in midy..<maxy {
                if tSP == nil, let t = map.tile(0, y), !t.isLand { tSP = t }
                if tSA == nil, let t = map.tile(maxx - 1, y), !t.isLand { tSA = t }
                if tSP != nil && tSA != nil { break }
            }
            let rNP = JavaRectangle(0, 0, midx, midy)
            let rSP = JavaRectangle(0, midy, midx, maxy - midy)
            let rNA = JavaRectangle(midx, 0, maxx - midx, midy)
            let rSA = JavaRectangle(midx, midy, maxx - midx, maxy - midy)
            let rN = JavaRectangle(0, 0, maxx, midy)
            let rS = JavaRectangle(0, midy, maxx, maxy - midy)
            let rAll = JavaRectangle(0, 0, maxx, maxy)
            for (np, sp, na, sa) in [(rNP, rSP, rNA, rSA), (rN, rS, rN, rS), (rAll, rAll, rAll, rAll)] {
                if let tNP { fillOcean(map, tNP, northPacific, np) }
                if let tSP { fillOcean(map, tSP, southPacific, sp) }
                if let tNA { fillOcean(map, tNA, northAtlantic, na) }
                if let tSA { fillOcean(map, tSA, southAtlantic, sa) }
            }
        }
        return result
    }

    /// Flood an ocean region from a tile, within bounds, over water in
    /// no other region.
    @discardableResult
    private static func fillOcean(_ map: Map, _ tile: Tile, _ region: Region, _ bounds: JavaRectangle) -> Int {
        var queue: [Tile] = [tile]
        var head = 0
        var n = 0
        var visited = Array(repeating: Array(repeating: false, count: map.height), count: map.width)
        visited[tile.x][tile.y] = true
        while head < queue.count {
            let tile = queue[head]
            head += 1
            region.addTile(tile)
            n += 1
            for direction in Direction.allDirections {
                guard let t = map.adjacentTile(tile, direction), !visited[t.x][t.y],
                      bounds.contains(t.x, t.y) else { continue }
                visited[t.x][t.y] = true
                if (t.region == nil || t.region === region) && !t.isLand { queue.append(t) }
            }
        }
        return n
    }
}

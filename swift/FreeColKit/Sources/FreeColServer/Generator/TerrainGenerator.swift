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

/// Makes a map's terrain from a land map (server/generator/TerrainGenerator):
/// tile types by latitude, temperature and humidity, the predefined
/// regions, mountains and hills, rivers, lakes, land regions, and
/// bonuses.  Importing a map is not ported.
public final class TerrainGenerator {

    static let landRegionsScoreValue = 1000
    static let landRegionMinScore = 5
    static let landRegionMaxSize = 75

    /// The temperature settings (MapGeneratorOptions.TEMPERATURE_*).
    static let temperatureCold = 0, temperatureChilly = 1, temperatureTemperate = 2
    static let temperatureWarm = 3, temperatureHot = 4

    private let random: JavaRandom
    private let cache: RandomUtils.RandomIntCache
    private var landTileTypes: [TileType]?
    private var oceanTileTypes: [TileType]?

    public init(_ random: JavaRandom) {
        self.random = random
        cache = RandomUtils.RandomIntCache("terrain", random, range: 1 << 16, size: 512)
    }

    private func limitToRange(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        max(lower, min(value, upper))
    }

    private func approximateLandCount(_ spec: Specification) -> Int {
        (spec.getInteger(MapGeneratorOptions.mapWidth) ?? 0) * (spec.getInteger(MapGeneratorOptions.mapHeight) ?? 0)
            * (spec.getInteger(MapGeneratorOptions.landMass) ?? 0) / 100
    }

    private func randomLandTileType(_ spec: Specification, _ latitude: Int) -> TileType? {
        if landTileTypes == nil {
            // Not hills, mountains or water, which come elsewhere.
            landTileTypes = spec.tileTypeList.filter { !$0.isElevation && !$0.isWater }
        }
        return randomTileType(spec, landTileTypes!, latitude)
    }

    private func randomOceanTileType(_ spec: Specification, _ latitude: Int) -> TileType? {
        if oceanTileTypes == nil {
            oceanTileTypes = spec.tileTypeList.filter {
                $0.isWater && $0.isHighSeasConnected && !$0.isDirectlyHighSeasConnected
            }
        }
        return randomTileType(spec, oceanTileTypes!, latitude)
    }

    /// A tile type for a latitude, narrowed by temperature, humidity and
    /// forest, each with some randomness.
    private func randomTileType(_ spec: Specification, _ candidates: [TileType], _ latitude: Int) -> TileType? {
        let forestChance = spec.getRange(MapGeneratorOptions.forestNumber) ?? 0
        let temperaturePreference = spec.getRange(MapGeneratorOptions.temperature) ?? 0
        var poleTemperature = -20, equatorTemperature = 40
        switch temperaturePreference {
        case TerrainGenerator.temperatureCold: (poleTemperature, equatorTemperature) = (-20, 25)
        case TerrainGenerator.temperatureChilly: (poleTemperature, equatorTemperature) = (-20, 30)
        case TerrainGenerator.temperatureTemperate: (poleTemperature, equatorTemperature) = (-10, 35)
        case TerrainGenerator.temperatureWarm: (poleTemperature, equatorTemperature) = (-5, 40)
        case TerrainGenerator.temperatureHot: (poleTemperature, equatorTemperature) = (0, 40)
        default: break
        }
        let temperatureRange = equatorTemperature - poleTemperature
        var localeTemperature = poleTemperature + (90 - abs(latitude)) * temperatureRange / 90
        let temperatureDeviation = 7 // +/- 7 degrees randomization
        localeTemperature += cache.nextInt(temperatureDeviation * 2) - temperatureDeviation
        localeTemperature = limitToRange(localeTemperature, -20, 40)

        var localeHumidity = spec.getRange(MapGeneratorOptions.humidity) ?? 0
        let humidityDeviation = 20 // +/- 20% randomization
        localeHumidity += cache.nextInt(humidityDeviation * 2) - humidityDeviation
        localeHumidity = limitToRange(localeHumidity, 0, 100)

        var candidateTileTypes = candidates.filter { $0.withinRange(.temperature, localeTemperature) }
        switch candidateTileTypes.count {
        case 0: preconditionFailure("No TileType for temperature==\(localeTemperature)")
        case 1: return candidateTileTypes[0]
        default: break
        }
        candidateTileTypes = candidateTileTypes.filter { $0.withinRange(.humidity, localeHumidity) }
        switch candidateTileTypes.count {
        case 0: preconditionFailure("No TileType for humidity==\(localeHumidity)")
        case 1: return candidateTileTypes[0]
        default: break
        }
        let forested = cache.nextInt(100) < forestChance && candidateTileTypes.contains { $0.isForested }
        candidateTileTypes = candidateTileTypes.filter { $0.isForested == forested }
        switch candidateTileTypes.count {
        case 0: preconditionFailure("No TileType for forested==\(forested)")
        case 1: return candidateTileTypes[0]
        default: return candidateTileTypes[cache.nextInt(candidateTileTypes.count)]
        }
    }

    // MARK: Regions

    /// Land regions: each landmass not in a region, split into parts of
    /// at most 75 tiles, scored by size.
    private func createLandRegions(_ map: Map) -> [Region] {
        let game = map.game!
        let w = map.width, h = map.height
        var continents = 0
        var landmap = Array(repeating: Array(repeating: false, count: h), count: w)
        var continentmap = Array(repeating: Array(repeating: 0, count: h), count: w)
        var landsize = 0
        for x in 0..<w {
            for y in 0..<h {
                if let tile = map.tile(x, y) {
                    // Not the regions already made (polar, mountains,
                    // rivers).
                    landmap[x][y] = tile.isLand && tile.region == nil
                    if tile.isLand { landsize += 1 }
                }
            }
        }
        // Number the landmasses.
        for y in 0..<h {
            for x in 0..<w where landmap[x][y] {
                continents += 1
                let continent = Map.floodFillBool(landmap, x, y)
                for yy in 0..<h {
                    for xx in 0..<w where continent[xx][yy] {
                        continentmap[xx][yy] = continents
                        landmap[xx][yy] = false
                    }
                }
            }
        }
        var continentsize = Array(repeating: 0, count: continents + 1)
        for y in 0..<h {
            for x in 0..<w { continentsize[continentmap[x][y]] += 1 }
        }
        // Split those too big.
        let oldcontinents = continents
        if oldcontinents >= 1 {
            for c in 1...oldcontinents where continentsize[c] > TerrainGenerator.landRegionMaxSize {
                var splitcontinent = Array(repeating: Array(repeating: false, count: h), count: w)
                var splitX = 0, splitY = 0
                for x in 0..<w {
                    for y in 0..<h {
                        if continentmap[x][y] == c {
                            splitcontinent[x][y] = true
                            splitX = x
                            splitY = y
                        }
                    }
                }
                while continentsize[c] > TerrainGenerator.landRegionMaxSize {
                    var targetsize = TerrainGenerator.landRegionMaxSize
                    if continentsize[c] < 2 * TerrainGenerator.landRegionMaxSize {
                        targetsize = continentsize[c] / 2
                    }
                    continents += 1
                    let newregion = Map.floodFillBool(splitcontinent, splitX, splitY, limit: targetsize)
                    for x in 0..<w {
                        for y in 0..<h {
                            if newregion[x][y] {
                                continentmap[x][y] = continents
                                splitcontinent[x][y] = false
                                continentsize[c] -= 1
                            }
                            if splitcontinent[x][y] {
                                splitX = x
                                splitY = y
                            }
                        }
                    }
                }
            }
        }
        var landregions: [Region] = []
        if continents >= 1 {
            for _ in 1...continents { landregions.append(Region(game: game, type: .land)) }
        }
        for y in 0..<h {
            for x in 0..<w where continentmap[x][y] > 0 {
                if let tile = map.tile(x, y) { landregions[continentmap[x][y] - 1].addTile(tile) }
            }
        }
        for sr in landregions {
            // Exploration points by size.
            let share = Int(JavaMath.toInt(Float(sr.size) / Float(landsize)
                                           * Float(TerrainGenerator.landRegionsScoreValue)))
            sr.scoreValue = max(share, TerrainGenerator.landRegionMinScore)
        }
        return landregions
    }

    /// Mountain ranges, with hills round them, and random hills.
    private func createMountains(_ map: Map) -> [Region] {
        let game = map.game!
        let spec = game.specification!
        let randomHillsRatio: Float = 0.5
        // Half for mountain ranges, half for random hills.
        let maximumLength = max(spec.getInteger(MapGeneratorOptions.mapWidth) ?? 0,
                                spec.getInteger(MapGeneratorOptions.mapHeight) ?? 0) / 10
        let mountainNumber = spec.getRange(MapGeneratorOptions.mountainNumber) ?? 1
        var number = Int(JavaMath.round((1.0 - randomHillsRatio)
                                        * (Float(approximateLandCount(spec)) / Float(mountainNumber))))
        var result: [Region] = []

        var tiles = map.tiles.filter(\.isGoodMountainTile)
        RandomUtils.randomShuffle("Randomize mountain tiles", &tiles, random)
        var counter = 0
        for startTile in tiles {
            // Adding mountains changes which tiles are good.
            if !startTile.isGoodMountainTile { continue }
            let mountainRegion = Region(game: game, type: .mountain)
            let direction = Direction.randomDirection("getLand", random)
            let length = maximumLength - cache.nextInt(maximumLength / 2)
            var tile: Tile? = startTile
            for _ in 0..<length {
                guard let current = tile else { break }
                if !(current.type?.isMountains ?? false) {
                    guard let mountains = randomTileType(spec, spec.mountainsTileTypeList,
                                                         map.latitude(current.y)) else { continue }
                    current.type = mountains
                    mountainRegion.addTile(current)
                    counter += 1
                }
                // Nothing (1/8), mountains (2/8) or hills (5/8) round it.
                for t in current.surroundingTiles(1) {
                    if !t.isGoodHillTile || (t.type?.isMountains ?? false) { continue }
                    let r = cache.nextInt(8)
                    if r < 2 {
                        guard let mountains = randomTileType(spec, spec.mountainsTileTypeList,
                                                             map.latitude(t.y)) else { continue }
                        t.type = mountains
                        mountainRegion.addTile(t)
                        counter += 1
                    } else if r < 7 {
                        guard let hills = randomTileType(spec, spec.hillsTileTypeList,
                                                         map.latitude(t.y)) else { continue }
                        t.type = hills
                        mountainRegion.addTile(t)
                    }
                }
                tile = current.neighbour(direction)
                if !(tile?.isLand ?? false) { break }
            }
            mountainRegion.scoreValue = 2 * mountainRegion.size
            result.append(mountainRegion)
            if counter >= number { break }
        }

        tiles = map.tiles.filter(\.isGoodHillTile)
        RandomUtils.randomShuffle("Randomize hill tiles", &tiles, random)
        number = Int(JavaMath.toInt(Float(approximateLandCount(spec)) * randomHillsRatio)) / mountainNumber
        counter = 0
        for t in tiles {
            guard let mountains = randomTileType(spec, spec.mountainsTileTypeList, map.latitude(t.y)),
                  let hills = randomTileType(spec, spec.hillsTileTypeList, map.latitude(t.y)) else { continue }
            let m = cache.nextInt(4) == 0
            t.type = m ? mountains : hills
            counter += 1
            if counter >= number { break }
        }
        return result
    }

    /// Rivers from random sources, until enough tiles have one.
    private func createRivers(_ map: Map) -> [Region] {
        let game = map.game!
        let spec = game.specification!
        var result: [Region] = []
        let riverType = spec.getTileImprovementType("model.improvement.river")!
        let riverMap = River.RiverMap()
        var rivers: [River] = []
        var tiles = map.tiles.filter { $0.isGoodRiverTile(riverType) }
        RandomUtils.randomShuffle("Randomize river tiles", &tiles, random)
        let absoluteMaximumRiverTiles = map.tiles.filter { $0.type.map(riverType.isTileTypeAllowed) ?? false }.count
        let softMaximumRiverTiles = absoluteMaximumRiverTiles
            * (spec.getRange(MapGeneratorOptions.riverNumber) ?? 0) / 100
        for tile in tiles {
            if riverMap[tile] != nil { continue }
            if riverMap.count > softMaximumRiverTiles { break }
            let riverRegion = Region(game: game, type: .river)
            let river = River(map, riverMap, riverRegion, random)
            if river.flowFromSource(tile) {
                result.append(riverRegion)
                rivers.append(river)
            }
        }
        for river in rivers {
            river.region.scoreValue = 2 * river.sections.reduce(0) { $0 + $1.size }
        }
        return result
    }

    /// Lakes: the water no ocean region reached.
    private func createLakeRegions(_ map: Map) -> [Region] {
        var lakes: [Tile] = []
        for y in 0..<map.height {
            for x in 0..<map.width {
                if let tile = map.tile(x, y), !tile.isLand, tile.region == nil { lakes.append(tile) }
            }
        }
        return makeLakes(map, lakes)
    }

    private func makeLakes(_ map: Map, _ lakes: [Tile]) -> [Region] {
        let game = map.game!
        let lakeType = map.specification?.getTileType("model.tile.lake")
        var lakes = lakes
        var result: [Region] = []
        while let tile = lakes.first {
            // Java would loop for ever here.
            precondition(tile.region == nil, "Lake tile already in a region: \(tile)")
            let lakeRegion = Region(game: game, type: .lake)
            var todo: [Tile] = [tile]
            while !todo.isEmpty {
                let t = todo.removeFirst()
                if let i = lakes.firstIndex(where: { $0 === t }) {
                    t.region = lakeRegion
                    t.type = lakeType
                    lakes.remove(at: i)
                    for d in Direction.allDirections {
                        if let t0 = map.adjacentTile(t, d) { todo.append(t0) }
                    }
                }
            }
            result.append(lakeRegion)
        }
        return result
    }

    // MARK: Bonuses

    /// Fish by land and river mouths, and resources at random.
    private func perhapsAddBonus(_ t: Tile, _ generateBonus: Bool) {
        let game = t.game!
        let spec = game.specification!
        let fishBonusLandType = spec.getTileImprovementType("model.improvement.fishBonusLand")!
        let fishBonusRiverType = spec.getTileImprovementType("model.improvement.fishBonusRiver")!
        let bonusNumber = spec.getRange(MapGeneratorOptions.bonusNumber) ?? 0
        if t.isLand {
            if generateBonus && cache.nextInt(100) < bonusNumber {
                if let r = createResource(t) { t.addResource(r) }
            }
        } else {
            var adjacentLand = 0
            var adjacentRiver = false
            for direction in Direction.allDirections {
                if let other = t.neighbour(direction), other.isLand {
                    adjacentLand += 1
                    if other.hasRiver { adjacentRiver = true }
                }
            }
            // Fish by land, and at river mouths.
            if adjacentLand > 2 {
                _ = t.add(TileImprovement(game: game, tile: t, type: fishBonusLandType, style: nil))
            }
            if adjacentRiver && !t.hasRiver {
                _ = t.add(TileImprovement(game: game, tile: t, type: fishBonusRiverType, style: nil))
            }
            if t.type?.isHighSeasConnected ?? false {
                if generateBonus && adjacentLand > 1 && cache.nextInt(10 - adjacentLand) == 0 {
                    if let r = createResource(t) { t.addResource(r) }
                }
            } else {
                if cache.nextInt(100) < bonusNumber {
                    if let r = createResource(t) { t.addResource(r) }
                }
            }
        }
    }

    private func createResource(_ tile: Tile) -> Resource? {
        guard let types = tile.type?.resourceTypes,
              let resourceType = RandomChoice.weightedRandom("", types, random) else { return nil }
        let minValue = resourceType.minValue, maxValue = resourceType.maxValue
        let quantity = minValue == maxValue ? maxValue : minValue + cache.nextInt(maxValue - minValue + 1)
        return Resource(game: tile.game!, tile: tile, type: resourceType, quantity: quantity)
    }

    /// The style of a water tile, from the land round it (encodeStyle).
    public static func encodeStyle(_ tile: Tile) {
        var connections: [Direction: Bool] = [:]
        for d in Direction.corners {
            connections[d] = tile.neighbour(d)?.isLand ?? false
        }
        for d in Direction.longSides {
            if tile.neighbour(d)?.isLand ?? false {
                connections[d] = true
                connections[d.nextDirection] = false
                connections[d.previousDirection] = false
            } else {
                connections[d] = false
            }
        }
        var result = 0
        var index = 0
        for d in Direction.corners + Direction.longSides {
            if connections[d] ?? false { result += 1 << index }
            index += 1
        }
        tile.style = result
    }

    // MARK: The map

    /// Make a game's map from a land map, and give it to the game
    /// (generateMap, without importing).
    @discardableResult
    public func generateMap(_ game: Game, _ landMap: LandMap) -> Map {
        let spec = game.specification!
        let width = landMap.width, height = landMap.height
        let map = Map(game: game, width: width, height: height)
        game.changeMap(map)
        let minimumLatitude = limitToRange(spec.getInteger(MapGeneratorOptions.minimumLatitude) ?? -90, -90, 90)
        let maximumLatitude = limitToRange(spec.getInteger(MapGeneratorOptions.maximumLatitude) ?? 90, -90, 90)
        map.minimumLatitude = min(minimumLatitude, maximumLatitude)
        map.maximumLatitude = max(minimumLatitude, maximumLatitude)

        map.populateTiles { x, y in
            let latitude = map.latitude(y)
            let tt = landMap.isLand(x, y) ? randomLandTileType(spec, latitude) : randomOceanTileType(spec, latitude)
            return Tile(game: game, type: tt, x: x, y: y)
        }

        let fixed = ServerRegions.requireFixedRegions(map)
        var newRegions: [Region] = []
        map.resetHighSeas(spec.getInteger(MapGeneratorOptions.distanceToHighSea) ?? 0,
                          spec.getInteger(MapGeneratorOptions.maximumDistanceToEdge) ?? 0)
        if landMap.hasLand {
            newRegions += createMountains(map)
            newRegions += createRivers(map)
            newRegions += createLakeRegions(map)
            newRegions += createLandRegions(map)
        }

        // The new regions go in the predefined land region they are
        // centred in.  Java only offers the polar regions here.
        let geographic = fixed.filter(\.isGeographic)
        for sr in newRegions {
            if let gr = geographic.first(where: { $0.containsCenter(sr) }) {
                sr.parent = gr
                gr.addChild(sr)
                gr.size += sr.size
            }
            map.addRegion(sr)
        }
        map.fixupRegions()
        game.generateDefaultAreas()

        map.forEachTile { t in
            perhapsAddBonus(t, true)
            if !t.isLand { TerrainGenerator.encodeStyle(t) }
        }
        map.resetContiguity()
        map.resetHighSeasCount()
        return map
    }
}

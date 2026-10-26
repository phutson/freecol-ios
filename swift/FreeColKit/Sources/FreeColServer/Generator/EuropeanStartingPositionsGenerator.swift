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

/// Where the Europeans start, and with what
/// (server/generator/EuropeanStartingPositionsGenerator).  The debug
/// mode's extra units are not ported.
final class EuropeanStartingPositionsGenerator {

    /// The starting positions settings (GameOptions.STARTING_POSITIONS_*).
    static let startingPositionsClassic = 0
    static let startingPositionsRandom = 1
    static let startingPositionsHistorical = 2

    private let random: JavaRandom

    init(_ random: JavaRandom) {
        self.random = random
    }

    /// A European's starting units, by what they do.
    private struct StartingUnits {
        var carriers: [Unit] = []
        var passengers: [Unit] = []
        var otherNaval: [Unit] = []

        init(_ player: Player, _ random: JavaRandom) {
            guard let game = player.game, let spec = player.specification,
                  let nationType = player.nationType as? EuropeanNationType else { return }
            for au in nationType.startingUnits {
                guard let type = au.type(spec) else { continue }
                let unit = Unit(game: game, location: nil, owner: player, type: type, role: au.role(spec))
                unit.name = player.nameForUnit(type, random)
                if unit.isNaval {
                    if unit.canCarryUnits {
                        unit.setState(.active)
                        carriers.append(unit)
                    } else {
                        otherNaval.append(unit)
                    }
                } else {
                    unit.setState(.sentry)
                    passengers.append(unit)
                }
            }
        }
    }

    /// Make and place the Europeans' starting units (createEuropeanUnits).
    func createEuropeanUnits(_ map: Map, _ players: [Player]) {
        var europeanPlayers = players.filter { $0.isEuropean && !$0.isREF }
        precondition(!europeanPlayers.isEmpty, "No players to generate units for!")
        random.shuffle(&europeanPlayers)
        var startingUnits: [ObjectIdentifier: StartingUnits] = [:]
        for player in europeanPlayers { startingUnits[ObjectIdentifier(player)] = StartingUnits(player, random) }
        let startingTiles = determineStartingTiles(map, europeanPlayers, startingUnits)
        for player in europeanPlayers {
            guard let start = startingTiles[ObjectIdentifier(player)],
                  let units = startingUnits[ObjectIdentifier(player)] else { continue }
            placeUnits(player, start, units)
        }
    }

    private func determineStartingTiles(_ map: Map, _ players: [Player],
                                        _ units: [ObjectIdentifier: StartingUnits]) -> [ObjectIdentifier: Tile] {
        guard let game = map.game else { return [:] }
        if !mapDefinedStartingPositionsAvailable(players, game) {
            return startingTilesWithoutPredeterminedPositions(map, players, units)
        }
        let positions = startingTilesUsingMapDefinedPositions(players, units, game)
        if positions.count < units.count {
            return startingTilesWithoutPredeterminedPositions(map, players, units)
        }
        return positions
    }

    private func startingTilesUsingMapDefinedPositions(_ players: [Player], _ units: [ObjectIdentifier: StartingUnits],
                                                       _ game: Game) -> [ObjectIdentifier: Tile] {
        switch game.specification?.getInteger(GameOptions.startingPositions) ?? 0 {
        case EuropeanStartingPositionsGenerator.startingPositionsClassic:
            return mapStartingAreaEnsuringDistance(players, units, game)
        case EuropeanStartingPositionsGenerator.startingPositionsRandom:
            return randomMapStartingArea(players, units, game)
        case EuropeanStartingPositionsGenerator.startingPositionsHistorical:
            return mapStartingArea(players, units, game)
        default:
            preconditionFailure("Unknown starting positions type")
        }
    }

    /// The nations' own areas, tried a few times for players at least ten
    /// tiles apart.
    private func mapStartingAreaEnsuringDistance(_ players: [Player], _ units: [ObjectIdentifier: StartingUnits],
                                                 _ game: Game) -> [ObjectIdentifier: Tile] {
        for _ in 0..<10 {
            let tiles = mapStartingArea(players, units, game)
            let all = Array(tiles.values)
            if !all.contains(where: { t in all.contains { $0 !== t && t.distance(to: $0) < 10 } }) { return tiles }
        }
        return mapStartingArea(players, units, game)
    }

    /// A random tile in each nation's area, at sea for a nation with a
    /// ship.
    private func mapStartingArea(_ players: [Player], _ units: [ObjectIdentifier: StartingUnits],
                                 _ game: Game) -> [ObjectIdentifier: Tile] {
        var startingTiles: [ObjectIdentifier: Tile] = [:]
        for player in players {
            guard let nation = player.nation, let area = game.nationStartingArea(nation) else { continue }
            let prefersLand = units[ObjectIdentifier(player)]?.carriers.isEmpty ?? true
            var possible = area.tiles.filter { $0.isLand == prefersLand }
            if possible.isEmpty { possible = area.tiles }
            while !possible.isEmpty {
                let index = Int(random.nextInt(Int32(possible.count)))
                let tile = possible[index]
                if !startingTiles.values.contains(where: { $0 === tile }) {
                    startingTiles[ObjectIdentifier(player)] = tile
                    break
                }
                possible.remove(at: index)
            }
        }
        return startingTiles
    }

    /// Random tiles from all the nations' areas.  Java gathers them in a
    /// HashSet of tiles.
    private func randomMapStartingArea(_ players: [Player], _ units: [ObjectIdentifier: StartingUnits],
                                       _ game: Game) -> [ObjectIdentifier: Tile] {
        var gathered: [Tile] = []
        for player in players {
            if let nation = player.nation, let area = game.nationStartingArea(nation) {
                for t in area.tiles where !gathered.contains(where: { $0 === t }) { gathered.append(t) }
            }
        }
        let toChooseFrom = JavaTileSet(gathered).tiles
        var land = toChooseFrom.filter(\.isLand)
        random.shuffle(&land)
        var ocean = toChooseFrom.filter { !$0.isLand }
        random.shuffle(&ocean)
        var indexLand = 0, indexOcean = 0
        var startingTiles: [ObjectIdentifier: Tile] = [:]
        for player in players {
            let prefersLand = units[ObjectIdentifier(player)]?.carriers.isEmpty ?? true
            let tile: Tile
            if prefersLand && indexLand < land.count {
                tile = land[indexLand]
                indexLand += 1
            } else if !prefersLand && indexOcean < ocean.count {
                tile = ocean[indexOcean]
                indexOcean += 1
            } else if indexLand < land.count {
                tile = land[indexLand]
                indexLand += 1
            } else {
                tile = ocean[indexOcean]
                indexOcean += 1
            }
            startingTiles[ObjectIdentifier(player)] = tile
        }
        return startingTiles
    }

    private func mapDefinedStartingPositionsAvailable(_ players: [Player], _ game: Game) -> Bool {
        guard let spec = game.specification else { return false }
        var defined = spec.getBoolean(GameOptions.mapDefinedStartingPositions) ?? false
        let positionType = spec.getInteger(GameOptions.startingPositions) ?? 0
        var numAreas = 0
        if defined {
            for player in players {
                let area = player.nation.flatMap { game.nationStartingArea($0) }
                if area == nil || area!.tiles.isEmpty {
                    if positionType == EuropeanStartingPositionsGenerator.startingPositionsClassic
                        || positionType == EuropeanStartingPositionsGenerator.startingPositionsHistorical {
                        break
                    }
                    continue
                }
                numAreas += 1
            }
        }
        if numAreas < players.count { defined = false }
        return defined
    }

    /// Tiles from the east and west edges: spread out, or by latitude.
    private func startingTilesWithoutPredeterminedPositions(_ map: Map, _ players: [Player],
                                                            _ units: [ObjectIdentifier: StartingUnits])
        -> [ObjectIdentifier: Tile] {
        let positionType = map.specification?.getInteger(GameOptions.startingPositions) ?? 0
        let number = players.count
        let (eastTiles, westTiles) = map.collectStartingTiles()
        var eastLand = eastTiles.filter(\.isLand), eastSea = eastTiles.filter { !$0.isLand }
        var westLand = westTiles.filter(\.isLand), westSea = westTiles.filter { !$0.isLand }
        switch positionType {
        case EuropeanStartingPositionsGenerator.startingPositionsClassic:
            sampleTiles(&eastLand, number)
            sampleTiles(&eastSea, number)
            sampleTiles(&westLand, number)
            sampleTiles(&westSea, number)
        case EuropeanStartingPositionsGenerator.startingPositionsRandom:
            eastLand += westLand
            eastSea += westSea
            sampleTiles(&eastLand, number)
            sampleTiles(&eastSea, number)
        default:
            break // Historical positions keep all the tiles.
        }
        var startingTiles: [ObjectIdentifier: Tile] = [:]
        for player in players {
            let startEast = player.nation?.startsOnEastCoast ?? true
            let startAtSea = !(units[ObjectIdentifier(player)]?.carriers.isEmpty ?? true)
            var start: Tile?
            switch positionType {
            case EuropeanStartingPositionsGenerator.startingPositionsClassic:
                if startAtSea {
                    start = startEast ? eastSea.removeFirst() : westSea.removeFirst()
                } else {
                    start = startEast ? eastLand.removeFirst() : westLand.removeFirst()
                }
            case EuropeanStartingPositionsGenerator.startingPositionsRandom:
                start = startAtSea ? eastSea.removeFirst() : eastLand.removeFirst()
            case EuropeanStartingPositionsGenerator.startingPositionsHistorical:
                start = startAtSea ? historicalStartingPosition(player, map, &eastSea, &westSea)
                    : historicalStartingPosition(player, map, &eastLand, &westLand)
            default:
                break
            }
            guard let start else {
                preconditionFailure("Failed to find start tile \(startAtSea ? "at sea" : "on land") for \(player)")
            }
            startingTiles[ObjectIdentifier(player)] = start
        }
        return startingTiles
    }

    /// Put the units on the start tile: all aboard at sea, landed on
    /// land, the rest in Europe.
    private func placeUnits(_ player: Player, _ start: Tile, _ units: StartingUnits) {
        player.entryTile = start
        let europe = player.europe
        if !start.isLand {
            for u in units.carriers {
                _ = u.setLocation(start)
                player.exploreForUnit(u)
            }
            passengers: for unit in units.passengers {
                for carrier in units.carriers where carrier.canAdd(unit) {
                    _ = unit.setLocation(carrier)
                    continue passengers
                }
                _ = unit.setLocation(europe)
            }
            for u in units.otherNaval {
                _ = u.setLocation(start)
                player.exploreForUnit(u)
            }
        } else {
            for u in units.passengers {
                _ = u.setLocation(start)
                player.exploreForUnit(u)
            }
            for u in units.otherNaval { _ = u.setLocation(europe) }
        }
        // The REF would get an entry tile here, but there is none yet.
    }

    /// The tile nearest the nation's preferred latitude on its coast.
    private func historicalStartingPosition(_ player: Player, _ map: Map, _ east: inout [Tile],
                                            _ west: inout [Tile]) -> Tile? {
        guard let nation = player.nation else { return nil }
        let latY = map.row(nation.preferredLatitude)
        func pick(_ tiles: inout [Tile]) -> Tile? {
            guard var best = tiles.first else { return nil }
            for t in tiles where abs(t.y - latY) < abs(best.y - latY) { best = t }
            tiles.removeAll { $0 === best }
            return best
        }
        return nation.startsOnEastCoast ? pick(&east) : pick(&west)
    }

    /// Spread a number of tiles out evenly, shuffled; or none if there
    /// are too few.
    @discardableResult
    private func sampleTiles(_ tiles: inout [Tile], _ number: Int) -> Bool {
        let n = tiles.count
        let step = n / number
        if step <= 1 {
            tiles = []
            return false
        }
        var samples: [Tile] = []
        var i = step / 2
        while i < n {
            samples.append(tiles[i])
            i += step
        }
        tiles = samples
        RandomUtils.randomShuffle("Starting tiles", &tiles, random)
        return true
    }
}

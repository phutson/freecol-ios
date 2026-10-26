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
import Testing

/// MapTest.java.
@Suite(.serialized)
struct MapTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    var lakeType: TileType { spec.getTileType("model.tile.lake")! }
    var oceanType: TileType { spec.getTileType("model.tile.ocean")! }
    var plainsType: TileType { spec.getTileType("model.tile.plains")! }
    var artilleryType: UnitType { spec.getUnitType("model.unit.artillery")! }
    var colonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }
    var galleonType: UnitType { spec.getUnitType("model.unit.galleon")! }
    var pioneerType: UnitType { spec.getUnitType("model.unit.hardyPioneer")! }

    func singleLandPathMap(_ game: Game) -> Map {
        let builder = MapBuilder(game).setBaseTileType(oceanType)
        // A stripe of land
        for (x, y) in [(1, 11), (2, 10), (2, 9), (3, 8), (3, 7)] { builder.setTileType(x, y, plainsType) }
        return builder.build()
    }

    // (1,5)*
    //          *
    //      *        *     * F(3,7)
    //                  * C(3,8)
    //      *        *
    //
    //      *   *
    //
    //      *S(1,11)
    //
    func shortLongPathMap(_ game: Game) -> Map {
        let builder = MapBuilder(game).setBaseTileType(oceanType)
        builder.setTileType(1, 11, plainsType) // Start
        builder.setTileType(2, 10, plainsType) // Short path
        builder.setTileType(2, 9, plainsType)
        for (x, y) in [(1, 9), (1, 7), (1, 5), (2, 6), (2, 7)] { builder.setTileType(x, y, plainsType) } // Longer
        builder.setTileType(3, 8, plainsType) // Common
        builder.setTileType(3, 7, plainsType) // Finish
        return builder.build()
    }

    @Test func mapGameInt() {
        let game = FreeColTestCase.standardGame(spec)
        let map = MapBuilder(game).setDimensions(20, 15).build()
        #expect(map.width == 20)
        #expect(map.height == 15)
    }

    @Test func getSurroundingTiles() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = MapBuilder(game).setDimensions(10, 15).build()
        game.changeMap(map)

        // In the middle
        var surroundingTiles = Array(map.tile(4, 8)!.surroundingTiles(1))
        #expect(surroundingTiles.count == 8)
        for (x, y) in [(4, 6), (4, 10), (3, 8), (5, 8), (3, 7), (4, 7), (3, 9), (4, 9)] {
            #expect(surroundingTiles.contains { $0 === map.tile(x, y) }, "\(x), \(y)")
        }

        // On the sides
        surroundingTiles = Array(map.tile(0, 0)!.surroundingTiles(1))
        #expect(surroundingTiles.count == 3)
        for (x, y) in [(0, 2), (1, 0), (0, 1)] {
            #expect(surroundingTiles.contains { $0 === map.tile(x, y) }, "\(x), \(y)")
        }

        // A larger range
        #expect(Array(map.tile(4, 8)!.surroundingTiles(2)).count == 25 - 1)
        // All the tiles
        #expect(Array(map.tile(4, 8)!.surroundingTiles(10)).count == 150 - 1)
    }

    @Test func getReverseDirection() {
        #expect(Direction.n.reverseDirection == .s)
        #expect(Direction.s.reverseDirection == .n)
        #expect(Direction.w.reverseDirection == .e)
        #expect(Direction.e.reverseDirection == .w)
        #expect(Direction.sw.reverseDirection == .ne)
        #expect(Direction.se.reverseDirection == .nw)
        #expect(Direction.ne.reverseDirection == .sw)
        #expect(Direction.nw.reverseDirection == .se)
    }

    @Test func getTiles() {
        let game = FreeColTestCase.standardGame(spec)
        let xmax = 5, ymax = 6
        var allTiles: [Tile] = []
        let map = Map(game: game, width: xmax, height: ymax)
        _ = map.populateTiles { x, y in
            let tile = Tile(game: game, type: plainsType, x: x, y: y)
            allTiles.append(tile)
            return tile
        }
        var i = 0
        for t in map.tileList({ _ in true }) {
            i += 1
            let index = allTiles.firstIndex { $0 === t }
            #expect(index != nil)
            if let index { allTiles.remove(at: index) }
        }
        #expect(allTiles.isEmpty)
        #expect(i == xmax * ymax)
    }

    @Test func randomDirection() {
        let game = FreeColTestCase.standardGame(spec)
        _ = MapBuilder(game).setDimensions(10, 15).build()
        let dirs = Direction.randomDirections("testRandomDirection", JavaRandom(seed: 1))
        #expect(dirs.count == Direction.allCases.count)
    }

    /// The only path is blocked by a native settlement.
    @Test func noPathAvailableDueToCampInTheWay() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = singleLandPathMap(game)
        game.changeMap(map)
        _ = IndianSettlementBuilder(game).settlementTile(map.tile(2, 10)!).build()

        let dutchPlayer = try #require(game.player(byNationId: "model.nation.dutch"))
        let destinationTile = try #require(map.tile(3, 7))
        let colonist = Unit(game: game, location: map.tile(1, 11), owner: dutchPlayer, type: colonistType)
        colonist.destination = destinationTile
        #expect(colonist.findPath(destinationTile) == nil, "No path should be available")
    }

    /// The only path is blocked by a foreign colony.
    @Test func noPathAvailableDueToColonyInTheWay() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = singleLandPathMap(game)
        game.changeMap(map)
        let frenchPlayer = try #require(game.player(byNationId: "model.nation.french"))
        let settlementTile = try #require(map.tile(2, 10))
        _ = ColonyBuilder(game).player(frenchPlayer).colonyTile(settlementTile).build()
        #expect(settlementTile.hasSettlement, "French colony was not set properly on the map")

        let dutchPlayer = try #require(game.player(byNationId: "model.nation.dutch"))
        let destinationTile = try #require(map.tile(3, 7))
        let colonist = Unit(game: game, location: map.tile(1, 11), owner: dutchPlayer, type: colonistType)
        colonist.destination = destinationTile
        #expect(colonist.findPath(destinationTile) == nil, "No path should be available")
    }

    @Test func moveThroughTileWithEnemyUnit() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)

        let enemyUnitTile = try #require(map.tile(2, 1))
        let frenchPlayer = try #require(game.player(byNationId: "model.nation.french"))
        _ = Unit(game: game, location: enemyUnitTile, owner: frenchPlayer, type: pioneerType)

        let unitTile = try #require(map.tile(1, 1))
        let otherTile = try #require(map.tile(1, 2))
        let dutchPlayer = try #require(game.player(byNationId: "model.nation.dutch"))
        let unit = Unit(game: game, location: unitTile, owner: dutchPlayer, type: pioneerType)
        // The unit is going somewhere else.
        unit.destination = map.tile(3, 1)

        let decider = CostDeciders.avoidSettlementsAndBlockingUnits()
        #expect(decider.cost(unit, unitTile, otherTile, 4) != CostDeciderConstants.illegalMove,
                "No blocking unit, should be legal")
        #expect(decider.cost(unit, unitTile, enemyUnitTile, 4) == CostDeciderConstants.illegalMove,
                "Blocking unit, should be illegal")
    }

    /// The only path is blocked by a unit.
    @Test func noPathAvailableDueToUnitInTheWay() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = singleLandPathMap(game)
        game.changeMap(map)
        let frenchPlayer = try #require(game.player(byNationId: "model.nation.french"))
        _ = Unit(game: game, location: map.tile(2, 10), owner: frenchPlayer, type: colonistType)

        let dutchPlayer = try #require(game.player(byNationId: "model.nation.dutch"))
        let destinationTile = try #require(map.tile(3, 7))
        let colonist = Unit(game: game, location: map.tile(1, 11), owner: dutchPlayer, type: colonistType)
        colonist.destination = destinationTile
        let path = colonist.findPath(colonist.tile!, destinationTile, nil,
                                     CostDeciders.avoidSettlementsAndBlockingUnits())
        #expect(path == nil, "No path should be available")
    }

    @Test func shortestPathObstructed() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = shortLongPathMap(game)
        game.changeMap(map)
        _ = IndianSettlementBuilder(game).settlementTile(map.tile(2, 10)!).build()

        let dutchPlayer = try #require(game.player(byNationId: "model.nation.dutch"))
        let colonist = Unit(game: game, location: map.tile(1, 11), owner: dutchPlayer, type: colonistType)
        let destinationTile = try #require(map.tile(3, 7))
        colonist.destination = destinationTile
        #expect(colonist.findPath(destinationTile) != nil, "A path should be available")
    }

    /// A goal decider with sub goals and a deliberately simple score.
    final class SettlementScoreGoalDecider: GoalDecider {
        private(set) var goal: PathNode?
        private var score = -1
        var hasSubGoals: Bool { true }
        func check(_ unit: Unit?, _ pathNode: PathNode) -> Bool {
            guard pathNode.location?.settlement != nil, let tile = pathNode.tile else { return false }
            let value = tile.x + tile.y
            guard value > score else { return false }
            score = value
            goal = pathNode
            return true
        }
    }

    @Test func searchForColony() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.coastTestMap(game, plainsType, explored: true)
        game.changeMap(map)

        let dutchPlayer = try #require(game.player(byNationId: "model.nation.dutch"))
        let frenchPlayer = try #require(game.player(byNationId: "model.nation.french"))
        let unitTile = try #require(map.tile(15, 5))
        let colonyTile = try #require(map.tile(9, 9)) // on the coast
        let galleon = Unit(game: game, location: unitTile, owner: dutchPlayer, type: galleonType)
        let artillery = Unit(game: game, location: galleon, owner: dutchPlayer, type: artilleryType)
        _ = ColonyBuilder(game).player(frenchPlayer).colonyTile(colonyTile).build()
        #expect(colonyTile.hasSettlement, "French colony not on the map")
        dutchPlayer.setStance(frenchPlayer, .war)
        frenchPlayer.setStance(dutchPlayer, .war)

        let gd = SettlementScoreGoalDecider()
        var path = map.search(artillery, unitTile, gd, CostDeciders.avoidIllegal(), Constants.infinity, galleon)
        // Java also checks the drop node is not null, which it never is.
        #expect(path != nil && path!.lastNode.tile === colonyTile,
                "Should find the French colony via a drop off")

        // Another colony, which scores less
        let colonyTile2 = try #require(map.tile(5, 5))
        _ = ColonyBuilder(game).player(frenchPlayer).colonyTile(colonyTile2).build()
        #expect(colonyTile2.hasSettlement, "French colony not on the map")
        path = map.search(artillery, unitTile, gd, CostDeciders.avoidIllegal(), Constants.infinity, galleon)
        #expect(path != nil && path!.lastNode.tile === colonyTile,
                "Should still find the first French colony via a drop off")
    }

    @Test func latitude() {
        let game = FreeColTestCase.standardGame(spec)
        var map = MapBuilder(game).setDimensions(1, 181).build()
        #expect(map.height == 181)
        #expect(map.latitudePerRow == 1)
        #expect(map.latitude(0) == -90)
        #expect(map.row(-90) == 0)
        #expect(map.latitude(90) == 0)
        #expect(map.row(0) == 90)
        #expect(map.latitude(180) == 90)
        #expect(map.row(90) == 180)

        map = MapBuilder(game).setDimensions(1, 91).build()
        #expect(map.height == 91)
        #expect(map.latitudePerRow == 2)
        #expect(map.latitude(0) == -90)
        #expect(map.row(-90) == 0)
        #expect(map.latitude(45) == 0)
        #expect(map.row(0) == 45)
        #expect(map.latitude(90) == 90)
        #expect(map.row(90) == 90)

        map = MapBuilder(game).setDimensions(1, 91).build()
        map.minimumLatitude = 0
        #expect(map.height == 91)
        #expect(map.latitudePerRow == 1)
        #expect(map.latitude(0) == 0)
        #expect(map.row(0) == 0)
        #expect(map.latitude(45) == 45)
        #expect(map.row(45) == 45)
        #expect(map.latitude(90) == 90)
        #expect(map.row(90) == 90)
    }

    @Test func circleIterator() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.coastTestMap(game, plainsType, explored: true)
        game.changeMap(map)
        let tile = try #require(map.tile(10, 10))

        #expect(Array(map.circleTiles(tile, filled: false, radius: -1)).isEmpty, "Radius -1 should produce 0 tiles")
        #expect(Array(map.circleTiles(tile, filled: false, radius: 0)).isEmpty, "Radius 0 should produce 0 tiles")
        #expect(Array(map.circleTiles(tile, filled: false, radius: 1)).count == 8, "Radius 1")
        #expect(Array(map.circleTiles(tile, filled: false, radius: 2)).count == 16, "Radius 2")

        let radius2Filled = Array(map.circleTiles(tile, filled: true, radius: 2))
        #expect(radius2Filled.count == 24, "Radius 2")
        let expected = [
            // Radius 1
            (10, 9), (11, 10), (10, 11), (10, 12), (9, 11), (9, 10), (9, 9), (10, 8),
            // Radius 2
            (10, 7), (11, 8), (11, 9), (12, 10), (11, 11), (11, 12), (10, 13), (10, 14),
            (9, 13), (9, 12), (8, 11), (8, 10), (8, 9), (9, 8), (9, 7), (10, 6),
        ].map { map.tile($0.0, $0.1)! }
        #expect(radius2Filled.elementsEqual(expected, by: ===),
                "The tiles should be returned in a certain order (spiraling clockwise outwards).")

        #expect(Array(map.circleTiles(map.tile(0, 1)!, filled: false, radius: 1)).count == 6,
                "Radius 1 in corner")
        #expect(Array(map.circleTiles(map.tile(map.width - 1, 1)!, filled: false, radius: 1)).count == 4,
                "Radius 1 in corner2")
    }

    @Test func findPath() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.coastTestMap(game, plainsType, explored: true)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let europe = try #require(dutch.europe)

        // The nearest port is Europe
        let seaTile = try #require(map.tile(13, 2))
        let galleon = Unit(game: game, location: seaTile, owner: dutch, type: galleonType)
        var path = try #require(galleon.findOurNearestPort(), "Nearest port should exist.")
        #expect(path.lastNode.location === europe, "Nearest port should be Europe.")

        let settlementTile = try #require(map.tile(9, 2))
        _ = ColonyBuilder(game).player(dutch).colonyTile(settlementTile).build()
        #expect(settlementTile.hasSettlement, "Dutch colony should be on the map.")
        #expect(settlementTile.isShore, "Dutch colony should be on the shore.")

        // Now the nearest port is the colony.
        path = try #require(galleon.findOurNearestPort(), "Nearest port should exist.")
        #expect(path.lastNode.tile === settlementTile, "Nearest port should be the colony.")

        // The colonist finds the trivial path
        let colonist = Unit(game: game, location: settlementTile, owner: dutch, type: colonistType)
        path = try #require(colonist.findPath(settlementTile, settlementTile), "Trivial path should exist.")
        #expect(path.next == nil, "Trivial path should be trivial.")
        #expect(path.tile === settlementTile, "Trivial path should start at settlement.")

        // The colonist can not find a path into the sea
        #expect(map.findPath(colonist, settlementTile, seaTile, nil, nil) == nil, "Sea path should be illegal.")

        // but a naval unit can.
        path = try #require(galleon.findPath(settlementTile, seaTile), "Sea path should be legal for naval unit.")
        #expect(path.tile === settlementTile, "Sea path should start at settlement.")
        #expect(path.lastNode.tile === seaTile, "Sea path should end at sea tile.")

        // A carrier makes the sea path work for the colonist.
        path = try #require(colonist.findPath(settlementTile, seaTile, galleon), "Sea path should now be legal.")
        #expect(path.tile === settlementTile, "Sea path should start at settlement.")
        #expect(path.lastNode.tile === seaTile, "Sea path should end at sea tile.")

        // and still does if the colonist walks to the carrier.
        let landTile = try #require(map.tile(2, 2))
        path = try #require(colonist.findPath(landTile, seaTile, galleon), "Sea path should still be legal.")
        #expect(path.tile === landTile, "Sea path should start at land tile.")
        #expect(path.lastNode.tile === seaTile, "Sea path should end at sea tile.")
        var p: PathNode? = path
        while let node = p, !node.isOnCarrier { p = node.next }
        #expect(p?.tile === settlementTile, "Sea path should include pickup at settlement.")

        // The colonist uses the carrier when it is quicker than walking
        let shoreTile = try #require(map.tile(9, 13))
        #expect(shoreTile.isShore, "Shore tile should be on the shore.")
        path = try #require(colonist.findPath(settlementTile, shoreTile, galleon), "Shore path should be legal.")
        #expect(path.usesCarrier, "Shore path should have carrier moves.")
        #expect(path.carrierMove != nil, "Shore path should have drop node.")

        // but not when it does not help.
        path = try #require(colonist.findPath(map.tile(2, 5)!, map.tile(9, 4)!, galleon),
                            "Middle path should be legal.")
        #expect(!path.usesCarrier, "Middle path should not not use carrier.")

        // To Europe
        path = try #require(colonist.findPath(settlementTile, europe, galleon), "To-Europe path should be valid.")
        #expect(path.lastNode.location === europe, "To-Europe path should end in Europe.")

        // From Europe
        path = try #require(colonist.findPath(europe, landTile, galleon), "From-Europe path should be valid.")
        #expect(path.location === europe, "From-Europe path should start in Europe.")

        // A settlement on a lake connected to the first: a ship there
        // finds a path to Europe.
        map.tile(8, 2)!.type = lakeType
        let anotherSettlementTile = try #require(map.tile(7, 2))
        _ = ColonyBuilder(game).player(dutch).colonyTile(anotherSettlementTile).build()
        path = try #require(galleon.findPath(anotherSettlementTile, europe),
                            "From-lake-settlement path should be valid.")
        #expect(path.lastNode.location === europe, "From-lake-settlement path should end in Europe.")

        // The colonist on the carrier, out to sea, finds a path inland.
        colonist.setLocation(galleon)
        galleon.setLocation(seaTile)
        path = try #require(colonist.findPath(galleon, landTile, galleon), "From-galleon path should be valid.")
        #expect(path.location === seaTile, "From-galleon path should start at sea.")
        #expect(path.isOnCarrier, "From-galleon path should start on carrier.")
        #expect(path.transportDropNode.tile != nil, "From-galleon path should have a drop node.")
    }

    @Test(.disabled("Map.copy is not ported yet (it copies by writing XML)"))
    func copy() {}
}

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
import Testing

/// MovementTest.java.
@Suite(.serialized)
struct MovementTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    var hills: TileType { spec.getTileType("model.tile.hills")! }
    var ocean: TileType { spec.getTileType("model.tile.ocean")! }
    var plains: TileType { spec.getTileType("model.tile.plains")! }
    func role(_ id: String) -> Role { spec.getRole("model.role." + id)! }
    var braveType: UnitType { spec.getUnitType("model.unit.brave")! }
    var colonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }

    /// A game with a map of a tile type, and two explored tiles for the
    /// Dutch at (5, 8) and (4, 8).
    func setUp(_ tileType: TileType) -> (Game, Map, Player, Tile, Tile) {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, tileType)
        game.changeMap(map)
        let dutch = game.player(byNationId: "model.nation.dutch")!
        let tile1 = map.tile(5, 8)!, tile2 = map.tile(4, 8)!
        return (game, map, dutch, tile1, tile2)
    }

    @Test func moveFromPlainsToPlains() throws {
        let (game, _, dutch, tile1, tile2) = setUp(plains)
        tile1.setExplored(dutch, true)
        tile2.setExplored(dutch, true)
        let colonist = Unit(game: game, location: tile1, owner: dutch, type: colonistType)

        let moveCost = plains.basicMoveCost
        #expect(colonist.moveCost(tile2) == moveCost)
        #expect(colonist.moveCost(tile2) == min(moveCost, colonistType.movement))

        // Plowing does not change the result
        #expect(tile2.tileImprovements.isEmpty, "No improvements")
        let ti = TileImprovement(game: game, tile: tile2,
                                 type: spec.getTileImprovementType("model.improvement.plow")!, style: nil)
        ti.turnsToComplete = 0
        tile2.add(ti)
        #expect(tile2.completeTileImprovements.count == 1, "Plowed")
        #expect(colonist.moveCost(tile2) == moveCost)
        #expect(colonist.moveCost(tile2) == min(moveCost, colonistType.movement))
    }

    @Test func moveFromPlainsToHills() {
        let (game, _, dutch, tile1, tile2) = setUp(plains)
        tile2.type = hills
        tile1.setExplored(dutch, true)
        tile2.setExplored(dutch, true)
        let colonist = Unit(game: game, location: tile1, owner: dutch, type: colonistType)

        let moveCost = hills.basicMoveCost
        #expect(moveCost > colonist.movesLeft)
        #expect(colonist.moveCost(tile2) == min(moveCost, colonistType.movement))
    }

    @Test func moveAlongRoad() throws {
        let (game, _, dutch, tile1, tile2) = setUp(plains)
        tile1.setExplored(dutch, true)
        tile2.setExplored(dutch, true)

        let road1 = try #require(tile1.addRoad())
        #expect(road1.isRoad)
        #expect(!road1.isComplete)
        road1.turnsToComplete = 0
        #expect(road1.isComplete)
        road1.updateRoadConnections(true)
        #expect(tile1.road === road1)

        let road2 = try #require(tile2.addRoad())
        road2.turnsToComplete = 0
        road2.updateRoadConnections(true)
        #expect(road2.isComplete)
        #expect(tile2.road === road2)

        #expect(road1.isConnected(to: tile1.direction(to: tile2)!))
        #expect(road2.isConnected(to: tile2.direction(to: tile1)!))

        let colonist = Unit(game: game, location: tile1, owner: dutch, type: colonistType)
        let moveCost = 1
        #expect(colonist.moveCost(tile2) == moveCost)
        #expect(colonist.moveCost(tile2) == min(moveCost, colonistType.movement))
    }

    @Test func moveAlongRiver() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, ocean)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let tile1 = try #require(map.tile(5, 8))
        let tile2 = try #require(tile1.neighbour(.ne))
        tile1.type = plains
        tile2.type = plains
        tile1.setExplored(dutch, true)
        tile2.setExplored(dutch, true)
        #expect(map.direction(tile1, tile2) == .ne)
        #expect(map.direction(tile2, tile1) == .sw)

        let river1 = try #require(tile1.addRiver(1, "0101"))
        #expect(river1.isRiver)
        #expect(river1.isComplete)
        #expect(tile1.hasRiver)
        let river2 = try #require(tile2.addRiver(1, "0101"))
        #expect(river2.isRiver)
        #expect(river2.isComplete)
        #expect(tile2.hasRiver)

        for river in [river1, river2] {
            #expect(!river.isConnected(to: .ne))
            #expect(river.isConnected(to: .se))
            #expect(!river.isConnected(to: .sw))
            #expect(river.isConnected(to: .nw))
        }

        let colonist = Unit(game: game, location: tile1, owner: dutch, type: colonistType)

        // The rivers start parallel: no cost reduction
        var moveCost = 3
        #expect(colonist.moveCost(tile2) == moveCost)
        #expect(colonist.moveCost(tile2) == min(moveCost, colonistType.movement))

        // The rivers are connected: the cost reduction applies
        river1.updateRiverConnections("1000")
        river2.updateRiverConnections("0010")
        #expect(river1.isConnected(to: .ne))
        #expect(!river1.isConnected(to: .se))
        #expect(!river1.isConnected(to: .sw))
        #expect(!river1.isConnected(to: .nw))
        #expect(!river2.isConnected(to: .ne))
        #expect(!river2.isConnected(to: .se))
        #expect(river2.isConnected(to: .sw))
        #expect(!river2.isConnected(to: .nw))

        moveCost = 1
        #expect(colonist.moveCost(tile2) == moveCost)
        #expect(colonist.moveCost(tile2) == min(moveCost, colonistType.movement))
    }

    @Test func scoutColony() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, explored: true)
        game.changeMap(map)
        let french = try #require(game.player(byNationId: "model.nation.french"))
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let iroquois = try #require(game.player(byNationId: "model.nation.iroquois"))

        let tile1 = map.tile(5, 8)!, tile2 = map.tile(4, 8)!, tile3 = map.tile(6, 8)!
        for player in [french, dutch] {
            for tile in [tile1, tile2, tile3] { tile.setExplored(player, true) }
        }

        let colony = FreeColTestCase.standardColony(game)
        #expect(tile1.colony === colony)

        let colonist = Unit(game: game, location: tile2, owner: french, type: colonistType)
        #expect(colonist.moveType(tile1) == .moveNoAccessSettlement)
        for (id, expected) in [("pioneer", Unit.MoveType.moveNoAccessSettlement),
                               ("missionary", .moveNoAccessSettlement),
                               ("scout", .enterForeignColonyWithScout),
                               ("soldier", .attackSettlement),
                               ("dragoon", .attackSettlement)] {
            colonist.setRole(role(id))
            #expect(colonist.moveType(tile1) == expected, "\(id)")
        }

        let brave = Unit(game: game, location: tile3, owner: iroquois, type: braveType)
        #expect(brave.moveType(tile1) == .attackSettlement)
        for id in ["mountedBrave", "armedBrave", "nativeDragoon"] {
            brave.setRole(role(id))
            #expect(brave.moveType(tile1) == .attackSettlement, "\(id)")
        }
    }

    @Test func scoutIndianSettlement() throws {
        let (game, _, _, tile1, tile2) = setUp(plains)
        let map = game.map!
        let french = try #require(game.player(byNationId: "model.nation.french"))
        let inca = try #require(game.player(byNationId: "model.nation.inca"))
        let iroquois = try #require(game.player(byNationId: "model.nation.iroquois"))
        let tile3 = map.tile(6, 8)!
        for tile in [tile1, tile2, tile3] { tile.setExplored(french, true) }

        // Build the settlement
        _ = IndianSettlementBuilder(game).player(inca).settlementTile(tile1).skillToTeach(nil).build()

        let colonist = Unit(game: game, location: tile2, owner: french, type: colonistType)
        #expect(colonist.moveType(tile1) == .moveNoAccessContact)
        Player.makeContact(french, inca)
        #expect(colonist.moveType(tile1) == .enterIndianSettlementWithFreeColonist)
        for (id, expected) in [("pioneer", Unit.MoveType.enterIndianSettlementWithFreeColonist),
                               ("missionary", .enterIndianSettlementWithMissionary),
                               ("scout", .enterIndianSettlementWithScout),
                               ("soldier", .attackSettlement),
                               ("dragoon", .attackSettlement)] {
            colonist.setRole(role(id))
            #expect(colonist.moveType(tile1) == expected, "\(id)")
        }

        let brave = Unit(game: game, location: tile3, owner: iroquois, type: braveType)
        #expect(brave.moveType(tile1) == .attackSettlement)
        for id in ["mountedBrave", "armedBrave", "nativeDragoon"] {
            brave.setRole(role(id))
            #expect(brave.moveType(tile1) == .attackSettlement, "\(id)")
        }
    }
}

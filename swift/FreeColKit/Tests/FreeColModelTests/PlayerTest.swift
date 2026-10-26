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

/// PlayerTest.java.
@Suite(.serialized)
struct PlayerTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    nonisolated(unsafe) static let classic = FreeColTestCase.loadSpecification("classic")
    var spec: Specification { Self.spec }
    var freeColonist: UnitType { spec.getUnitType("model.unit.freeColonist")! }

    @Test func units() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, spec.getTileType("model.tile.plains")!)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let french = try #require(game.player(byNationId: "model.nation.french"))
        for (x, y) in [(4, 7), (4, 8), (5, 7), (5, 8)] { map.tile(x, y)!.setExplored(dutch, true) }

        let unit1 = Unit(game: game, location: map.tile(4, 7), owner: dutch, type: freeColonist)
        let unit2 = Unit(game: game, location: map.tile(4, 8), owner: dutch, type: freeColonist)
        _ = Unit(game: game, location: map.tile(5, 7), owner: dutch, type: freeColonist)
        _ = Unit(game: game, location: map.tile(5, 8), owner: dutch, type: freeColonist)
        #expect(dutch.units.count == 4)

        unit1.dispose()
        #expect(!dutch.hasUnit(unit1))

        unit2.changeOwner(french)
        #expect(!dutch.hasUnit(unit2))
        #expect(french.hasUnit(unit2))
    }

    func checkEuropeanPlayer(_ player: Player?, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let player = try #require(player, sourceLocation: sourceLocation)
        #expect(player.canBuildColonies, sourceLocation: sourceLocation)
        #expect(player.canHaveFoundingFathers, sourceLocation: sourceLocation)
        #expect(player.canMoveToEurope, sourceLocation: sourceLocation)
        #expect(player.isColonial, sourceLocation: sourceLocation)
        #expect(!player.isDead, sourceLocation: sourceLocation)
        #expect(player.isEuropean, sourceLocation: sourceLocation)
        #expect(!player.isIndian, sourceLocation: sourceLocation)
        #expect(!player.isREF, sourceLocation: sourceLocation)
        #expect(player.maximumFoodConsumption == 2, sourceLocation: sourceLocation)
    }

    func checkIndianPlayer(_ player: Player?, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let player = try #require(player, sourceLocation: sourceLocation)
        #expect(!player.canBuildColonies, sourceLocation: sourceLocation)
        #expect(!player.canHaveFoundingFathers, sourceLocation: sourceLocation)
        #expect(!player.canMoveToEurope, sourceLocation: sourceLocation)
        #expect(!player.isColonial, sourceLocation: sourceLocation)
        #expect(!player.isDead, sourceLocation: sourceLocation)
        #expect(!player.isEuropean, sourceLocation: sourceLocation)
        #expect(player.isIndian, sourceLocation: sourceLocation)
        #expect(!player.isREF, sourceLocation: sourceLocation)
        #expect(player.maximumFoodConsumption == 2, sourceLocation: sourceLocation)
    }

    func checkRoyalPlayer(_ player: Player?, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let player = try #require(player, sourceLocation: sourceLocation)
        #expect(!player.canBuildColonies, sourceLocation: sourceLocation)
        #expect(!player.canHaveFoundingFathers, sourceLocation: sourceLocation)
        #expect(player.canMoveToEurope, sourceLocation: sourceLocation)
        #expect(!player.isColonial, sourceLocation: sourceLocation)
        #expect(player.playerType == .royal, sourceLocation: sourceLocation)
        #expect(!player.isDead, sourceLocation: sourceLocation)
        #expect(player.isEuropean, sourceLocation: sourceLocation)
        #expect(!player.isIndian, sourceLocation: sourceLocation)
        #expect(player.isREF, sourceLocation: sourceLocation)
        #expect(player.maximumFoodConsumption == 2, sourceLocation: sourceLocation)
    }

    static let natives = ["inca", "aztec", "arawak", "cherokee", "iroquois", "sioux", "apache", "tupi"]

    func checkPlayers(_ game: Game, _ europeans: [String]) throws {
        for id in europeans {
            let player = game.player(byNationId: "model.nation.\(id)")
            try checkEuropeanPlayer(player)
            let ref = game.player(byNationId: "model.nation.\(id)REF")
            try checkRoyalPlayer(ref)
            #expect(player?.refPlayer === ref, "\(id)")
        }
        for id in Self.natives {
            try checkIndianPlayer(game.player(byNationId: "model.nation.\(id)"))
        }
    }

    @Test func classicPlayers() throws {
        let game = FreeColTestCase.standardGame(Self.classic)
        try checkPlayers(game, ["dutch", "french", "english", "spanish"])
    }

    @Test func freecolPlayers() throws {
        // As the standard game, except that the players are added to
        // it again, with all European nations available.
        let game = FreeColTestCase.standardGame(spec)
        let nationOptions = NationOptions(specification: spec)
        for nation in spec.europeanNations { nationOptions.setNationState(nation, .available) }
        game.nationOptions = nationOptions
        spec.applyDifficultyLevel("model.difficulty.medium")
        for n in spec.nations where !n.isUnknownEnemy {
            let p = Player(game: game, nation: n)
            p.isAI = !(n.type?.isEuropean ?? false) || (n.type?.isREF ?? false)
            game.addPlayer(p)
        }
        try checkPlayers(game, ["dutch", "french", "english", "spanish", "portuguese", "swedish", "danish",
                                "russian"])
    }

    @Test func tension() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let french = try #require(game.player(byNationId: "model.nation.french"))
        let initialTension = 500
        let change = 250

        dutch.setTension(french, Tension(initialTension))
        french.setTension(dutch, Tension(initialTension))

        // Java's tensions are mutable objects; here they are values.
        var t = dutch.tension(french)
        t.modify(change)
        dutch.setTension(french, t)

        #expect(dutch.tension(french).value == initialTension + change,
                "Dutch tension value should have changed")
        #expect(french.tension(dutch).value == initialTension,
                "French tension value should have remained the same")
    }

    @Test func addAnotherPlayersUnit() async throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let french = try #require(game.player(byNationId: "model.nation.french"))
        #expect(dutch.unitCount == 0, "Wrong number of units for dutch player")
        #expect(french.unitCount == 0, "Wrong number of units for french player")

        let colonist = Unit(game: game, location: map.tile(6, 8), owner: dutch, type: freeColonist)
        #expect(colonist.owner === dutch, "Colonist should be dutch")
        #expect(dutch.unitCount == 1, "Wrong number of units for dutch player")

        // Java throws IllegalStateException; here it is a precondition.
        await #expect(processExitsWith: .failure) {
            let spec = FreeColTestCase.loadSpecification()
            let game = FreeColTestCase.standardGame(spec)
            let map = FreeColTestCase.testMap(game)
            game.changeMap(map)
            let colonist = Unit(game: game, location: map.tile(6, 8), owner: game.player(byNationId: "model.nation.dutch")!,
                                type: spec.getUnitType("model.unit.freeColonist")!)
            _ = game.player(byNationId: "model.nation.french")!.addUnit(colonist)
        }
        #expect(colonist.owner === dutch, "Colonist owner should not have been changed")
        #expect(dutch.unitCount == 1, "Wrong number of units for dutch player")
        #expect(french.unitCount == 0, "Wrong number of units for french player")
    }
}

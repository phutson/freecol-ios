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
import FreeColCore
import FreeColEngine
import FreeColIO
import FreeColServer
import FreeColTestSupport
import Testing

/// The engine actor, driven as the user interface will: a new game,
/// commands (carried out and refused), ending turns, saving and loading,
/// and snapshots handed between tasks.
struct GameEngineTests {

    static let data = FreeColDataDirectory(url: ReferenceDumps.repositoryRoot.appendingPathComponent("data"))

    static let english: MessageBundle = {
        let data = ReferenceDumps.repositoryRoot.appendingPathComponent("data")
        let strings = data.appendingPathComponent("strings")
        let numberRules = try! NumberRules(data: Data(contentsOf: strings.appendingPathComponent("plurals.xml")))
        return MessageBundle.load(directory: strings, languageId: "en_US", numberRules: numberRules,
                                  rulesDirectories: ["classic", "freecol"].map {
                                      data.appendingPathComponent("rules/" + $0)
                                  })
    }()

    static func newEngine(seed: Int64 = 11) throws -> GameEngine {
        try GameEngine(newGame: data, seed: seed, playerName: "Player", messages: english)
    }

    static let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// A new game: the human Dutch player's turn, its ships at sea with
    /// colonists aboard, the land round them explored, the others' at
    /// their own start, and the same game from the same seed.
    @Test func newGame() async throws {
        let engine = try Self.newEngine()
        let s = await engine.snapshot()
        #expect(s.turn == 1)
        #expect(s.isPlayersTurn)
        #expect(s.player?.nationId == "model.nation.dutch")
        #expect(s.player?.name == "Player")
        #expect(s.player?.gold != nil)
        #expect(s.players.count >= 12)
        #expect(s.map.width == 40 && s.map.height == 100)
        let explored = s.map.tiles.filter(\.isExplored)
        #expect(!explored.isEmpty && explored.count < s.map.tiles.count)
        let ships = s.ownUnits.filter { $0.isNaval }
        #expect(!ships.isEmpty)
        #expect(ships.contains { !$0.carriedUnitIds.isEmpty })
        for ship in ships {
            let position = try #require(ship.position)
            #expect(s.map.tile(position.x, position.y)?.unitIds.contains(ship.id) == true)
        }
        #expect(s.europe != nil && !(s.europe?.recruitableTypeIds.isEmpty ?? true))
        #expect(!s.market.isEmpty)
        // Others' units only where the player sees them.
        for u in s.units where u.ownerId != s.playerId {
            let p = try #require(u.position)
            #expect(s.map.tile(p.x, p.y)?.isVisible == true)
        }
        // No other player's gold is shown.
        #expect(s.players.filter { $0.id != s.playerId }.allSatisfy { $0.gold == nil })
        // The same seed, the same game.
        let again = await (try Self.newEngine()).snapshot()
        #expect(again == s)
    }

    /// A ship sails a tile: it moves, the player is shown it, and its
    /// moves are spent.  A command for a unit that is not there is
    /// refused and changes nothing.
    @Test func commands() async throws {
        let engine = try Self.newEngine()
        let before = await engine.snapshot()
        let ship = try #require(before.ownUnits.first { $0.isNaval && $0.position != nil })
        var moved: CommandResult?
        for d in Self.directions {
            let r = await engine.perform(.move(unit: ship.id, direction: d))
            if !r.wasRefused {
                moved = r
                break
            }
        }
        let result = try #require(moved)
        let after = try #require(result.snapshot.unit(ship.id))
        #expect(after.position != ship.position)
        #expect(after.movesLeft < ship.movesLeft)
        #expect(result.events.contains { if case .unitMoved(let id, _, _) = $0 { id == ship.id } else { false } })

        let refused = await engine.perform(.move(unit: "unit:999999", direction: "N"))
        #expect(refused.wasRefused)
        #expect(refused.snapshot == result.snapshot)
    }

    /// Ending the turn plays everyone else's and comes back to the
    /// player in the next turn, with its units' moves restored.
    @Test func endTurn() async throws {
        let engine = try Self.newEngine()
        let ship = try #require(await engine.snapshot().ownUnits.first { $0.isNaval && $0.position != nil })
        for d in Self.directions where !(await engine.perform(.move(unit: ship.id, direction: d))).wasRefused {
            break
        }
        let r1 = try await engine.endTurn()
        #expect(r1.snapshot.turn == 2)
        #expect(r1.snapshot.isPlayersTurn)
        #expect(r1.snapshot.unit(ship.id)?.movesLeft == ship.initialMoves)
        let r2 = try await engine.endTurn()
        #expect(r2.snapshot.turn == 3)
    }

    /// A saved game loads as the same game, which plays on the same.
    @Test func saveAndLoad() async throws {
        let engine = try Self.newEngine()
        _ = try await engine.endTurn()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("engine-\(UUID().uuidString).fsg")
        defer { try? FileManager.default.removeItem(at: url) }
        try await engine.save(to: url)
        let loaded = try GameEngine(loading: url, messages: Self.english)
        let s = await engine.snapshot()
        #expect(await loaded.snapshot() == s)
        #expect(await loaded.randomState == engine.randomState)
        // The saved generator plays on as the live one.
        let a = try await engine.endTurn().snapshot
        let b = try await loaded.endTurn().snapshot
        #expect(a == b)
    }

    /// One of Java's saved games, from the oracle.
    @Test func loadJavaGame() async throws {
        let url = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("games/freecol-commands-seed1.fsg")
        let engine = try GameEngine(loading: url, messages: Self.english)
        let s = await engine.snapshot()
        #expect(s.player?.nationId == "model.nation.dutch")
        #expect(!s.colonies.isEmpty)
        #expect(!s.settlements.isEmpty)
        #expect(s.colonies.allSatisfy { !$0.buildings.isEmpty && $0.unitCount > 0 })
        // Explored tiles out of sight, and no units shown on them.
        let unseen = s.map.tiles.filter { $0.isExplored && !$0.isVisible }
        #expect(!unseen.isEmpty)
        #expect(unseen.allSatisfy { $0.unitIds.isEmpty })
        for u in s.units where u.ownerId != s.playerId {
            let p = try #require(u.position)
            #expect(s.map.tile(p.x, p.y)?.isVisible == true)
        }
    }

    /// Snapshots go anywhere: made in the engine, read in another task.
    @Test func snapshotsCrossTasks() async throws {
        let engine = try Self.newEngine()
        let count = await Task.detached { await engine.snapshot().units.count }.value
        #expect(count > 0)
    }
}

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
@testable import FreeColEngine
import FreeColIO
import FreeColServer
import FreeColTestSupport
import Testing

/// The player's copy of the game, kept up to date from what the server
/// sends after each command as Java's client keeps its own, is the copy
/// read afresh after every command (apart from what Java's client also
/// has and a fresh copy lacks: the messages it was sent, market data
/// sent only on a price change, and a land name not yet answered).
@Suite struct ClientUpdateTests {

    static let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    /// Play some turns: every unit on the map makes a move of each kind
    /// it can, answering every question with its first choice, then the
    /// turn ends.
    static func play(_ engine: GameEngine, turns: Int) async throws {
        // Some test games were made with units on tiles the player had
        // not explored, which no game would have, and which the server
        // notices only later (TradePlayTests.firstContact).
        _ = try await engine.serverActs { _, _, human, _ in
            for u in human.units where u.tile != nil { _ = human.exploreForUnit(u) }
            return ChangeSet()
        }
        await engine.checkClientUpdates()
        _ = try await engine.play(.startTurn)
        for _ in 0..<turns {
            for u in await engine.snapshot().ownUnits where u.position != nil {
                guard let types = await engine.moveTypes(u.id) else { continue }
                var tried: Set<String> = []
                for (i, type) in types.enumerated() where !tried.contains(type) && type != "MOVE_NO_MOVES" {
                    tried.insert(type)
                    var asked: [String] = []
                    _ = try await PlayTests.playAccepting(engine, .move(unitId: u.id, direction: directions[i]),
                                                          asked: &asked)
                    if await engine.snapshot().unit(u.id)?.position == nil { break }
                }
            }
            var asked: [String] = []
            _ = try await PlayTests.playAccepting(engine, .endTurn, asked: &asked)
        }
    }

    @Test(arguments: ["natives", "commands", "europe", "moves", "combat", "colonypanel"])
    func savedGames(_ name: String) async throws {
        let engine = try GameEngine(loading: PlayerViewTests.oracle.appendingPathComponent(
            "games/freecol-\(name)-seed1.fsg"), messages: GameEngineTests.english)
        try await Self.play(engine, turns: 2)
        let (applied, mismatches) = await engine.clientUpdates
        #expect(applied > 5)
        #expect(mismatches.isEmpty, Comment(rawValue: mismatches.prefix(3).joined(separator: "\n\n")))
    }

    @Test func newGame() async throws {
        let engine = try GameEngineTests.newEngine()
        try await Self.play(engine, turns: 3)
        let (applied, mismatches) = await engine.clientUpdates
        #expect(applied > 3)
        #expect(mismatches.isEmpty, Comment(rawValue: mismatches.prefix(3).joined(separator: "\n\n")))
    }
}

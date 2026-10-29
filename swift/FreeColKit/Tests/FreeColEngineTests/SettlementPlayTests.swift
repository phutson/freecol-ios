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
import FreeColTestSupport
import Testing

/// Entering settlements through the engine, as the client does: a scout
/// speaking with a chief, a missionary founding a mission, and an
/// armed unit demanding tribute.
@Suite struct SettlementPlayTests {

    static let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    static func engine() async throws -> GameEngine {
        let url = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("games/freecol-natives-seed1.fsg")
        let engine = try GameEngine(loading: url, messages: GameEngineTests.english)
        _ = try await engine.play(.startTurn)
        return engine
    }

    /// A unit of the player's and a direction whose move is of a type.
    static func find(_ engine: GameEngine, _ moveType: String) async -> (String, String)? {
        for u in await engine.snapshot().ownUnits where u.position != nil {
            if let i = await engine.moveTypes(u.id)?.firstIndex(of: moveType) { return (u.id, directions[i]) }
        }
        return nil
    }

    /// Make a move, answering the questions as given (by their id's
    /// prefix), the rest with their first choice.
    static func play(_ engine: GameEngine, _ action: GameEngine.PlayAction, _ picks: [String: String])
        async throws -> (CommandResult, [String]) {
        var answers: [String: String] = [:], asked: [String] = []
        while true {
            let r = try await engine.play(action, answers: answers)
            guard let q = r.question, asked.count < 10 else { return (r, asked) }
            asked.append(q.id)
            let prefix = String(q.id.prefix { $0 != ":" })
            answers[q.id] = picks[prefix] ?? q.choices.first?.id ?? ""
        }
    }

    @Test func scoutSpeaks() async throws {
        let engine = try await Self.engine()
        let (scout, d) = try #require(await Self.find(engine, "ENTER_INDIAN_SETTLEMENT_WITH_SCOUT"))
        let (r, asked) = try await Self.play(engine, .move(unitId: scout, direction: d), ["scout": "speak"])
        #expect(asked == ["scout:\(scout)"])
        // The chief's answer is told (or the scout did not come back).
        let told = r.events.contains { if case .notice = $0 { true } else { false } }
        #expect(told || r.snapshot.unit(scout) == nil)
    }

    @Test func missionaryEstablishes() async throws {
        let engine = try await Self.engine()
        let (missionary, d) = try #require(await Self.find(engine, "ENTER_INDIAN_SETTLEMENT_WITH_MISSIONARY"))
        let before = await engine.snapshot()
        let at = try #require(before.unit(missionary)?.position)
        let (r, asked) = try await Self.play(engine, .move(unitId: missionary, direction: d), ["missionary": "establish"])
        #expect(asked == ["missionary:\(missionary)"])
        // In the mission, off the map.
        #expect(r.snapshot.unit(missionary)?.position != at || r.snapshot.unit(missionary)?.place != before.unit(missionary)?.place)
        #expect(r.refusal == nil)
    }

    @Test func tributeFromNatives() async throws {
        let engine = try await Self.engine()
        let (soldier, d) = try #require(await Self.find(engine, "ATTACK_SETTLEMENT"))
        let (_, asked) = try await Self.play(engine, .move(unitId: soldier, direction: d),
                                             ["settlement": "tribute", "tribute": "yes"])
        #expect(asked == ["settlement:\(soldier)", "tribute:\(soldier)"])
        // The demand spends the unit's moves.
        #expect(await engine.snapshot().unit(soldier)?.movesLeft == 0)
    }
}

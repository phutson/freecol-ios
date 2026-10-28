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
import FreeColServer
import Testing

/// Playing on the map through the engine, as the client does: the
/// first moves of a new game, from the ships to a colony.
@Suite struct PlayTests {

    /// Answer every question with its first choice (or the name
    /// offered), as the player who accepts would, and say what was
    /// asked.
    static func playAccepting(_ engine: GameEngine, _ action: GameEngine.PlayAction,
                              asked: inout [String]) async throws -> CommandResult {
        var answers: [String: String] = [:]
        while true {
            let r = try await engine.play(action, answers: answers)
            guard let q = r.question else { return r }
            asked.append(q.id)
            #expect(answers[q.id] == nil, "asked again: \(q.id)")
            answers[q.id] = q.choices.first?.id ?? q.suggestion ?? ""
            if asked.count > 20 { return r }
        }
    }

    @Test func firstMoves() async throws {
        let engine = try GameEngineTests.newEngine()
        var asked: [String] = []
        let start = try await engine.play(.startTurn)
        // The ships are offered first; the colonists aboard are waiting.
        let shipId = try #require(start.activeUnitId)
        #expect(start.snapshot.unit(shipId)?.isNaval == true)
        #expect(await engine.unitActions(shipId)?.unload == true)
        #expect(await engine.unitActions(shipId)?.buildColony == false)

        // Sail west, the way to the land, until land is in sight, then
        // the nearest sea beside it the ship can reach.
        var snapshot = start.snapshot
        var best: (MapPosition, UnitPath)?
        for _ in 0..<40 where best == nil {
            let map = snapshot.map
            let at = try #require(snapshot.unit(shipId)?.position)
            for t in map.tiles where t.isExplored && !t.isLand && t.unitIds.isEmpty {
                let nearLand = Direction.allDirections.contains { d in
                    let p = d.step(t.x, t.y)
                    return map.tile(p.x, p.y)?.isLand == true
                }
                guard nearLand, let path = await engine.gotoPath(shipId, to: MapPosition(x: t.x, y: t.y)) else {
                    continue
                }
                if best == nil || (path.destination?.turns ?? 99, path.steps.count)
                    < (best!.1.destination?.turns ?? 99, best!.1.steps.count) {
                    best = (MapPosition(x: t.x, y: t.y), path)
                }
            }
            if best != nil { break }
            if snapshot.unit(shipId)?.movesLeft ?? 0 > 0 {
                snapshot = try await Self.playAccepting(engine, .move(unitId: shipId, direction: "W"), asked: &asked).snapshot
                if snapshot.unit(shipId)?.position == at { break }
            } else {
                snapshot = try await Self.playAccepting(engine, .endTurn, asked: &asked).snapshot
            }
        }
        let shipAt = try #require(snapshot.unit(shipId)?.position)
        let (coast, path) = try #require(best)
        #expect(path.steps.first?.place == .tile(shipAt))
        #expect(path.destination?.place == .tile(coast))

        // Sail there, ending turns until it arrives.
        var r = try await Self.playAccepting(engine, .goTo(unitId: shipId, destination: .tile(coast)), asked: &asked)
        var turns = 0
        while r.snapshot.unit(shipId)?.position != coast && turns < 6 {
            r = try await Self.playAccepting(engine, .endTurn, asked: &asked)
            turns += 1
        }
        #expect(r.snapshot.unit(shipId)?.position == coast)
        #expect(r.snapshot.unit(shipId)?.destinationId == nil)

        // Onto the land beside it: all aboard disembark.
        let ashore = try #require(Direction.allDirections.first { d in
            let p = d.step(coast.x, coast.y)
            return r.snapshot.map.tile(p.x, p.y)?.isLand == true
        })
        let aboard = try #require(r.snapshot.unit(shipId)?.carriedUnitIds)
        #expect(!aboard.isEmpty)
        let landing = try await Self.playAccepting(engine, .move(unitId: shipId, direction: ashore.javaName),
                                                   asked: &asked)
        #expect(asked.contains("disembark:\(shipId)"))
        let landed = aboard.filter { landing.snapshot.unit($0)?.position != coast }
        #expect(!landed.isEmpty)
        // The first landing names the land.
        let named = landing.events.compactMap { e -> (String, String)? in
            if case .request(.newLandName(let unit, let name, _)) = e { return (unit, name) }
            return nil
        }
        let (namer, newLand) = try #require(named.first)
        #expect(!newLand.isEmpty)
        #expect(!(await engine.perform(.newLandName(unit: namer, name: newLand))).wasRefused)

        // Landing takes their moves.  Next turn, a colonist ashore
        // founds a colony, after the warnings and the name.
        _ = try await Self.playAccepting(engine, .endTurn, asked: &asked)
        var founder: String?
        for id in landed where await engine.unitActions(id)?.buildColony == true {
            founder = id
            break
        }
        let founderId = try #require(founder)
        let built = try await Self.playAccepting(engine, .buildColony(unitId: founderId), asked: &asked)
        #expect(asked.contains("colonyName:\(founderId)"))
        let colony = try #require(built.colonyToShow)
        #expect(built.snapshot.colony(colony) != nil)
        #expect(built.snapshot.colonies.count == 1)

        // Ending the turn asks first while units still wait, then plays
        // on to the next.
        let before = built.snapshot.turn
        asked = []
        let next = try await Self.playAccepting(engine, .endTurn, asked: &asked)
        if !(await engine.snapshot()).ownUnits.isEmpty { #expect(asked.contains("endTurn") || asked.isEmpty) }
        #expect(next.snapshot.turn == before + 1)
        #expect(next.snapshot.isPlayersTurn)
    }

    /// Fortifying, sentry and skipping change the unit's state; the
    /// unit's moves are then left, and the next is offered.
    @Test func unitActions() async throws {
        let engine = try GameEngineTests.newEngine()
        let start = try await engine.play(.startTurn)
        let first = try #require(start.activeUnitId)
        let sentry = try await engine.play(.changeState(unitId: first, state: "SENTRY"))
        #expect(sentry.snapshot.unit(first)?.state == "SENTRY")
        #expect(sentry.activeUnitId != first)
        let wait = try await engine.play(.wait)
        #expect(wait.activeUnitId != sentry.activeUnitId || sentry.activeUnitId == nil)
        if let other = wait.activeUnitId {
            let skipped = try await engine.play(.skip(unitId: other))
            #expect(skipped.snapshot.unit(other)?.state == "SKIPPED")
            #expect(skipped.activeUnitId != other)
        }
    }
}

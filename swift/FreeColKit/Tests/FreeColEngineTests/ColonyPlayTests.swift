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
import FreeColTestSupport
import Testing

/// Working a colony through the engine, as its panel does: moving
/// colonists between buildings and tiles and out of the colony,
/// changing their work, and setting the build queue.
@Suite struct ColonyPlayTests {

    static func engine() async throws -> GameEngine {
        let url = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("games/freecol-commands-seed1.fsg")
        let engine = try GameEngine(loading: url, messages: GameEngineTests.english)
        _ = try await engine.play(.startTurn)
        return engine
    }

    /// The colony with the most colonists.
    static func biggest(_ engine: GameEngine) async throws -> ColonyScreen {
        let s = await engine.snapshot()
        var best: ColonyScreen?
        for c in s.colonies {
            if let screen = await engine.colonyScreen(c.id), screen.unitCount > (best?.unitCount ?? -1) {
                best = screen
            }
        }
        return try #require(best)
    }

    @Test func workElsewhere() async throws {
        let engine = try await Self.engine()
        // A colonist and a free tile of its colony it could work.
        var found: (ColonyScreen, String, WorkPlace)?
        for c in await engine.snapshot().colonies where found == nil {
            guard let screen = await engine.colonyScreen(c.id) else { continue }
            let workers = screen.buildings.flatMap(\.unitIds) + screen.tiles.flatMap(\.unitIds)
            for w in workers where found == nil {
                if let p = screen.places(w).first(where: { p in
                    p.noAddReason == "NONE" && p.workTypeId != nil && screen.tiles.contains { $0.id == p.workLocationId }
                }) {
                    found = (screen, w, p)
                }
            }
        }
        let (before, worker, place) = try #require(found)
        let r = try await engine.play(.work(unitId: worker, workLocationId: place.workLocationId))
        #expect(r.refusal == nil)
        let after = try #require(await engine.colonyScreen(before.id))
        let tile = try #require(after.tiles.first { $0.id == place.workLocationId })
        #expect(tile.unitIds.contains(worker))
        #expect(!after.buildings.flatMap(\.unitIds).contains(worker))
        // At the work the tile suits best.
        let at = try #require(tile.unitIds.firstIndex(of: worker))
        #expect(tile.made[at]?.typeId == place.workTypeId)
        #expect(after.unitCount == before.unitCount)

        // Another work, then out of the colony.
        let other = try #require(after.places(worker).first { $0.workLocationId == place.workLocationId })
        _ = other
        let out = try await engine.play(.putOutsideColony(unitId: worker))
        let outside = try #require(await engine.colonyScreen(before.id))
        #expect(out.notices.isEmpty || outside.unitCount < before.unitCount)
        if outside.unitCount < before.unitCount {
            #expect(outside.outsideUnitIds.contains(worker))
            // And back in, to a building.
            let into = try #require(outside.places(worker).first { p in
                p.noAddReason == "NONE" && outside.buildings.contains { $0.id == p.workLocationId }
            })
            _ = try await engine.play(.work(unitId: worker, workLocationId: into.workLocationId))
            let back = try #require(await engine.colonyScreen(before.id))
            #expect(back.unitCount == before.unitCount)
            #expect(back.buildings.first { $0.id == into.workLocationId }?.unitIds.contains(worker) == true)
        }
    }

    @Test func buildQueue() async throws {
        let engine = try await Self.engine()
        let before = try await Self.biggest(engine)
        let open = before.buildingChoices.filter { $0.locked == nil }.map(\.typeId)
            + before.unitChoices.filter { $0.locked == nil }.map(\.typeId)
        #expect(open.count >= 2)
        let queue = Array(open.prefix(2))
        _ = try await engine.play(.setBuildQueue(colonyId: before.id, queue: queue))
        let after = try #require(await engine.colonyScreen(before.id))
        #expect(after.queue == queue)
        #expect(after.building == queue[0])
        // A queued building is no longer offered.
        if let b = queue.first(where: { id in before.buildingChoices.contains { $0.typeId == id } }) {
            #expect(!after.buildingChoices.contains { $0.typeId == b })
        }
    }

    @Test func changeWork() async throws {
        let engine = try await Self.engine()
        let before = try await Self.biggest(engine)
        // A tile worker set to another goods its tile makes.
        for t in before.tiles where !t.isCentre {
            for (i, id) in t.unitIds.enumerated() {
                guard let made = t.made[i] else { continue }
                let other = ["model.goods.grain", "model.goods.furs", "model.goods.lumber", "model.goods.ore"]
                    .first { $0 != made.typeId }!
                _ = try await engine.play(.changeWorkType(unitId: id, goodsTypeId: other))
                let after = try #require(await engine.colonyScreen(before.id))
                let tile = try #require(after.tiles.first { $0.id == t.id })
                let j = try #require(tile.unitIds.firstIndex(of: id))
                // Either it works the new goods, or, the tile making none
                // of it, the panel sets it back to what the tile suits.
                #expect(tile.made[j]?.typeId == other || tile.made[j]?.typeId == made.typeId)
                return
            }
        }
        Issue.record("No tile worker")
    }
}

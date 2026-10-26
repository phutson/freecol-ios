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

/// PathfindingTest.java, which Java's AllTests does not run.
@Suite(.serialized)
struct PathfindingTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    /// A goal decider that keeps the last node it accepts, as Java's
    /// anonymous ones in this test do.
    final class TestGoalDecider: GoalDecider {
        private(set) var goal: PathNode?
        let isGoal: (Tile) -> Bool
        init(_ isGoal: @escaping (Tile) -> Bool) { self.isGoal = isGoal }
        var hasSubGoals: Bool { true }
        func check(_ unit: Unit?, _ path: PathNode) -> Bool {
            guard let tile = path.tile, isGoal(tile) else { return false }
            goal = path
            return true
        }
    }

    @Test func composedGoalDeciders() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.coastTestMap(game, spec.getTileType("model.tile.plains")!, explored: true)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))

        let colonyTile = try #require(map.tile(9, 2))
        _ = ColonyBuilder(game).player(dutch).colonyTile(colonyTile).build()
        #expect(colonyTile.isShore)

        let unitTile = try #require(map.tile(9, 3))
        let unit = Unit(game: game, location: unitTile, owner: dutch,
                        type: spec.getUnitType("model.unit.freeColonist")!)

        let nativeTile = try #require(map.tile(9, 4))
        _ = IndianSettlementBuilder(game).settlementTile(nativeTile).build()
        #expect(nativeTile.isShore)

        let settlementGD = TestGoalDecider { $0.hasSettlement }
        let colonyGD = TestGoalDecider { $0.colony != nil }
        let nativeGD = TestGoalDecider { $0.indianSettlement != nil }
        let ownedGD = TestGoalDecider { $0.owner === dutch }

        var gd = GoalDeciders.composed(all: true, ownedGD, settlementGD)
        var path = try #require(unit.search(unitTile, gd, nil, 1, nil))
        #expect(path.lastNode.tile === colonyTile, "Composed-AND GoalDecider should find colony")
        gd = GoalDeciders.composed(all: true, settlementGD, ownedGD)
        path = try #require(unit.search(unitTile, gd, nil, 1, nil))
        #expect(path.lastNode.tile === colonyTile, "Composed-AND GoalDecider should still find colony")

        gd = GoalDeciders.composed(all: false, nativeGD, colonyGD)
        path = try #require(unit.search(unitTile, gd, nil, 1, nil))
        #expect(path.lastNode.tile === nativeTile, "Composed-OR GoalDecider should find natives")
        gd = GoalDeciders.composed(all: false, nativeGD, colonyGD)
        path = try #require(unit.search(unitTile, gd, nil, 1, nil))
        // The same search again finds the natives, in Java too: this
        // check fails there (on tile:564 rather than tile:524), and
        // Java's AllTests leaves PathfindingTest out.
        withKnownIssue("Fails in Java as well") {
            #expect(path.lastNode.tile === colonyTile, "Composed-OR GoalDecider should find colony")
        }
        #expect(path.lastNode.tile === nativeTile)
    }
}

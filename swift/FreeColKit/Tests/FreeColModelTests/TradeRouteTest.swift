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

/// TradeRouteTest.java.
@Suite(.serialized)
struct TradeRouteTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    @Test func tradeRoute() throws {
        let furs = spec.getGoodsType("model.goods.furs")!
        let mixedForestType = spec.getTileType("model.tile.mixedForest")!
        let wagonTrainType = spec.getUnitType("model.unit.wagonTrain")!

        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, mixedForestType, explored: true))

        // Set up three colonies
        let colony1 = FreeColTestCase.standardColony(game, 4, 1, 1)
        let colony2 = FreeColTestCase.standardColony(game, 4, 3, 1)
        let colony3 = FreeColTestCase.standardColony(game, 4, 5, 1)
        let tile1 = try #require(colony1.tile), tile2 = try #require(colony2.tile)
        let tile3 = try #require(colony3.tile)
        #expect(tile1.type === mixedForestType)
        #expect(tile2.type === mixedForestType)
        #expect(tile3.type === mixedForestType)
        let player = try #require(colony1.owner)

        // Create a wagon
        let wagon = Unit(game: game, location: tile1, owner: player, type: wagonTrainType)
        wagon.setLocation(tile1)
        #expect(wagon.turnsToReach(colony2) == 2)
        #expect(wagon.turnsToReach(colony3) == 4)
        wagon.setLocation(tile2)
        #expect(wagon.turnsToReach(colony1) == 2)
        #expect(wagon.turnsToReach(colony3) == 2)
        wagon.setLocation(tile3)
        #expect(wagon.turnsToReach(colony1) == 4)
        #expect(wagon.turnsToReach(colony2) == 2)
        wagon.setLocation(tile1)

        // Create a trade route and build towards validity
        let tr = TradeRoute(game: game, name: "TR", owner: player)
        #expect(tr.verify != nil) // Invalid, no stops
        #expect(tr.stopCount == 0)
        let trs1 = TradeRouteStop(game: game, location: colony1)
        #expect(trs1.isValid(player))
        tr.addStop(trs1)
        #expect(tr.verify != nil) // Invalid, one stop is not enough
        let trs2 = TradeRouteStop(game: game, location: colony2)
        #expect(trs2.isValid(player))
        tr.addStop(trs2)
        #expect(tr.verify != nil) // Invalid, all stops are empty
        trs1.addCargo(furs)
        #expect(tr.verify == nil) // Now finally valid
        trs2.addCargo(furs)
        #expect(tr.verify != nil) // Invalid again, furs always present
        let trs3 = TradeRouteStop(game: game, location: colony3)
        #expect(trs3.isValid(player))
        tr.addStop(trs3)
        #expect(tr.verify == nil) // Valid again, furs dumped at colony3

        // Assign the trade route
        wagon.tradeRoute = tr

        // Check the import and export amounts
        let ex = 50
        #expect(wagon.loadableAmount(furs) == GoodsContainer.cargoSize * 2)
        for colony in [colony1, colony2, colony3] {
            #expect(colony.goodsCount(furs) == 0)
            let data = colony.exportData(furs)
            data.exportLevel = ex
            data.exported = true
        }
        for colony in [colony1, colony2, colony3] {
            #expect(colony.exportAmount(furs, 0) == 0)
        }
        for trs in [trs1, trs2, trs3] {
            #expect(trs.exportAmount(furs, 0) == 0)
            #expect(trs.importAmount(furs, 0) == GoodsContainer.cargoSize)
        }

        // Which stops have work?  Initially nothing to collect, and
        // therefore nothing to deliver.
        #expect(!trs1.hasWork(wagon, 0))
        #expect(!trs2.hasWork(wagon, 0))
        #expect(!trs3.hasWork(wagon, 0))

        // Add some goods and delivery becomes valid
        wagon.addGoods(furs, 10)
        #expect(!trs1.hasWork(wagon, 0))
        #expect(!trs2.hasWork(wagon, 0))
        #expect(trs3.hasWork(wagon, 0))
        wagon.removeGoods(furs)

        // Now allow the production check.  There is still nothing to
        // collect because of the export level.
        #expect(!trs1.hasWork(wagon, 0))
        #expect(!trs2.hasWork(wagon, 2))
        #expect(!trs3.hasWork(wagon, 4))

        // Zero the export levels.  The first colony still does not
        // export, as it has not produced anything yet, but the second
        // (for which turnsToReach() > 0) has goods to export.  The third
        // shows no work unless there are goods on the wagon.
        for colony in [colony1, colony2, colony3] { colony.exportData(furs).exportLevel = 0 }
        #expect(!trs1.hasWork(wagon, 0))
        #expect(trs2.hasWork(wagon, 2))
        #expect(!trs3.hasWork(wagon, 4))
        wagon.addGoods(furs, 10)
        #expect(trs3.hasWork(wagon, 4))
        wagon.removeGoods(furs)
    }
}

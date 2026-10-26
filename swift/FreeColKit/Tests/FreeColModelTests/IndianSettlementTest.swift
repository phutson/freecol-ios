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

/// IndianSettlementTest.java.
@Suite(.serialized)
struct IndianSettlementTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }
    var horsesType: GoodsType { spec.getGoodsType("model.goods.horses")! }
    var musketsType: GoodsType { spec.getGoodsType("model.goods.muskets")! }

    @Test func automaticEquipBraves() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let camp = IndianSettlementBuilder(game).initialBravesInCamp(1).build()
        let indianBrave = try #require(camp.unitList.first)

        #expect(indianBrave.automaticRole == nil, "No auto-equip, no muskets")
        camp.addGoods(musketsType, 100)
        #expect(indianBrave.automaticRole === spec.getRole("model.role.armedBrave"),
                "Auto-equip to armed brave, muskets present")
        camp.addGoods(horsesType, 100)
        #expect(indianBrave.automaticRole === spec.getRole("model.role.nativeDragoon"),
                "Auto-equip to native dragoon, horses and muskets present")
    }

    /// Per Col1 rules, native settlements do not own water tiles.
    @Test func settlementDoesNotOwnWaterTiles() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.coastTestMap(game, spec.getTileType("model.tile.plains")!)
        game.changeMap(map)

        let campTile = try #require(map.tile(9, 9))
        let landTile = try #require(map.tile(8, 9))
        let waterTile = try #require(map.tile(10, 9))
        #expect(campTile.isLand, "Setup error, camp tile should be land")
        #expect(landTile.isLand, "Setup error, tile should be land")
        #expect(!waterTile.isLand, "Setup error, tile should be water")
        #expect(campTile.isAdjacent(waterTile), "Setup error, tiles should be adjacent")
        #expect(campTile.isAdjacent(landTile), "Setup error, tiles should be adjacent")

        let camp = IndianSettlementBuilder(game).settlementTile(campTile).build()
        let indianPlayer = camp.owner
        #expect(campTile.owner === indianPlayer, "Indian player should own camp tile")
        #expect(landTile.owner === indianPlayer, "Indian player should own land tile")
        #expect(waterTile.owner !== indianPlayer, "Indian player should not own water tile")
    }

    @Test func tradeGoodsWithSettlement() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)

        let builder = IndianSettlementBuilder(game)
        let camp1 = builder.build()
        let camp2 = IndianSettlementBuilder(game).settlementTile(map.tile(3, 3)!).build()
        let notEnoughToShare = 50
        let enoughToShare = 100

        camp1.addGoods(horsesType, notEnoughToShare)
        camp1.addGoods(musketsType, enoughToShare)
        #expect(camp1.goodsCount(musketsType) == enoughToShare, "Wrong quantity of muskets")
        #expect(camp1.goodsCount(horsesType) == notEnoughToShare, "Wrong quantity of horses")
        #expect(camp2.goodsCount(musketsType) == 0, "Wrong quantity of muskets")
        #expect(camp2.goodsCount(horsesType) == 0, "Wrong quantity of horses")

        camp1.tradeGoodsWithSettlement(camp2)

        #expect(camp1.goodsCount(musketsType) == enoughToShare / 2, "Wrong quantity of muskets")
        #expect(camp1.goodsCount(horsesType) == notEnoughToShare, "Wrong quantity of horses")
        #expect(camp2.goodsCount(musketsType) == enoughToShare / 2, "Wrong quantity of muskets")
        #expect(camp2.goodsCount(horsesType) == 0, "Wrong quantity of horses")
    }
}

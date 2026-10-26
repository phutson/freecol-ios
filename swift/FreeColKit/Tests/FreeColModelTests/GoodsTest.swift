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

/// GoodsTest.java.
@Suite(.serialized)
struct GoodsTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func goods(_ id: String) -> GoodsType { spec.getGoodsType("model.goods." + id)! }
    var bellsType: GoodsType { goods("bells") }
    var clothType: GoodsType { goods("cloth") }
    var cottonType: GoodsType { goods("cotton") }
    var crossesType: GoodsType { goods("crosses") }
    var fishType: GoodsType { goods("fish") }
    var foodType: GoodsType { spec.primaryFoodType! }
    var grainType: GoodsType { goods("grain") }
    var hammersType: GoodsType { goods("hammers") }
    var horsesType: GoodsType { goods("horses") }
    var lumberType: GoodsType { goods("lumber") }
    var musketsType: GoodsType { goods("muskets") }
    var oreType: GoodsType { goods("ore") }
    var toolsType: GoodsType { goods("tools") }
    var tradeGoodsType: GoodsType { goods("tradeGoods") }
    var plainsType: TileType { spec.getTileType("model.tile.plains")! }
    var wagonTrainType: UnitType { spec.getUnitType("model.unit.wagonTrain")! }

    /// A game, and a wagon train on a test map that is not the game's
    /// map, as in Java.
    func wagon(explored: Bool = false) -> (Game, Map, Unit) {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, plainsType, explored: explored)
        let wagon = Unit(game: game, location: map.tile(9, 10), owner: game.player(byNationId: "model.nation.dutch")!,
                         type: wagonTrainType)
        return (game, map, wagon)
    }

    @Test func goodsGameLocationIntInt() {
        let (game, _, wagon) = wagon()
        let g = Goods(game: game, location: wagon, type: cottonType, amount: 75)
        #expect(g.location === wagon)
        #expect(g.type === cottonType)
        #expect(g.amount == 75)
    }

    /// Java's setOwner throws; here goods have no owner of their own to
    /// set, only their location's.
    @Test func setOwner() {
        let (game, _, wagon) = wagon()
        let g = Goods(game: game, location: wagon, type: cottonType, amount: 75)
        #expect(g.owner === wagon.owner)
    }

    @Test func toStringTest() {
        let (game, _, wagon) = wagon()
        let g = Goods(game: game, location: wagon, type: cottonType, amount: 75)
        #expect(g.description == "75 cotton")
    }

    @Test func getName() {
        let game = FreeColTestCase.standardGame(spec)
        let g = Goods(game: game, location: nil, type: cottonType, amount: 75)
        #expect(Messages.message(g.label(sellable: true)) == "75 Cotton")
        #expect(Messages.message(g.label(sellable: false)) == "75 Cotton (boycotted)")
    }

    @Test func getInputType() {
        #expect(cottonType.inputType == nil)
        #expect(clothType.inputType === cottonType)
    }

    @Test func getOutputType() {
        #expect(clothType.outputType == nil)
        #expect(cottonType.outputType === clothType)
    }

    @Test func isFarmedGoods() {
        #expect(!bellsType.isFarmed)
        #expect(cottonType.isFarmed)
        #expect(!clothType.isFarmed)
    }

    @Test func militaryGoods() {
        #expect(!bellsType.isMilitary)
        #expect(!crossesType.isMilitary)
        #expect(!clothType.isMilitary)
        #expect(!cottonType.isMilitary)
        #expect(horsesType.isMilitary)
        #expect(musketsType.isMilitary)
    }

    @Test func buildingMaterials() {
        // for the dragoon role
        #expect(horsesType.isBuildingMaterial)
        #expect(musketsType.isBuildingMaterial)
        // for buildings and units
        #expect(hammersType.isBuildingMaterial)
        #expect(toolsType.isBuildingMaterial)

        // goods not involved in construction, or not directly
        for type in [bellsType, crossesType, clothType, cottonType, fishType, oreType, lumberType] {
            #expect(!type.isBuildingMaterial, "\(type)")
        }

        // raw materials
        #expect(oreType.isRawBuildingMaterial)
        #expect(lumberType.isRawBuildingMaterial)
        #expect(!toolsType.isRawBuildingMaterial)
        #expect(!foodType.isRawBuildingMaterial) // freecol rules!
        #expect(grainType.isRawBuildingMaterial) // freecol rules!
        for type in [fishType, horsesType, musketsType, hammersType, bellsType, crossesType, clothType,
                     cottonType] {
            #expect(!type.isRawBuildingMaterial, "\(type)")
        }
    }

    @Test func tradeGoods() {
        #expect(tradeGoodsType.isTradeGoods)
    }

    @Test func getTakeSpace() {
        let (game, _, wagon) = wagon(explored: true)
        #expect(Goods(game: game, location: wagon, type: cottonType, amount: 75).spaceTaken == 1)
    }

    @Test func setGetAmount() {
        let (game, _, wagon) = wagon(explored: true)
        let cotton = Goods(game: game, location: wagon, type: cottonType, amount: 75)
        #expect(cotton.amount == 75)
        cotton.amount = -10
        #expect(cotton.amount == -10)
        cotton.amount = 100000
        #expect(cotton.amount == 100000)
    }

    @Test func adjustAmount() {
        let (game, _, wagon) = wagon(explored: true)
        let cotton = Goods(game: game, location: wagon, type: cottonType, amount: 75)
        #expect(cotton.amount == 75)
        cotton.adjustAmount()
        cotton.amount = -10
        #expect(cotton.amount == -10)
        cotton.amount = 100000
        #expect(cotton.amount == 100000)
    }

    @Test func productionChain() {
        #expect(hammersType.productionChain.elementsEqual([lumberType, hammersType], by: ===))
        #expect(musketsType.productionChain.elementsEqual([oreType, toolsType, musketsType], by: ===))
    }
}

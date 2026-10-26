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

/// GoodsContainerTest.java.
@Suite(.serialized)
struct GoodsContainerTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()

    @Test func container() {
        let spec = Self.spec
        let sugar = spec.getGoodsType("model.goods.sugar")!
        let food = spec.primaryFoodType!
        let fish = spec.getGoodsType("model.goods.fish")!
        let lumber = spec.getGoodsType("model.goods.lumber")!

        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))
        let colony = FreeColTestCase.standardColony(game)
        let container = GoodsContainer(game: game, parent: colony)

        #expect(container.goodsCount(sugar) == 0)
        #expect(container.goodsCount(food) == 0)
        #expect(container.goodsCount(fish) == 0)
        #expect(container.goodsCount(lumber) == 0)

        container.addGoods(sugar, 36)
        #expect(container.goodsCount(sugar) == 36)
        container.addGoods(lumber, 37)
        #expect(container.goodsCount(lumber) == 37)
        container.addGoods(food, 38)
        #expect(container.goodsCount(food) == 38)
        container.addGoods(fish, 39)
        #expect(container.goodsCount(fish) == 39)

        func check(_ total: Int, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(container.goodsCount(sugar) == 36 + total, sourceLocation: sourceLocation)
            #expect(container.goodsCount(lumber) == 37 + total, sourceLocation: sourceLocation)
            #expect(container.goodsCount(food) == 38 + total, sourceLocation: sourceLocation)
            #expect(container.goodsCount(fish) == 39 + total, sourceLocation: sourceLocation)
        }

        var difference = 20
        var totalDifference = difference
        for type in [sugar, lumber, food, fish] { container.addGoods(type, difference) }
        check(totalDifference)

        difference = 10
        totalDifference -= difference
        for type in [sugar, lumber, food, fish] { container.removeGoods(type, difference) }
        check(totalDifference)

        difference = -20
        totalDifference += difference
        for type in [sugar, lumber, food, fish] { container.addGoods(type, difference) }
        check(totalDifference)

        container.removeAbove(10)
        #expect(container.goodsCount(sugar) == 10)
        #expect(container.goodsCount(lumber) == 10)
        // food and fish ignore the limit
        #expect(container.goodsCount(food) == 38 + totalDifference)
        #expect(container.goodsCount(fish) == 39 + totalDifference)

        difference = 20
        totalDifference -= difference
        container.removeGoods(sugar, difference)
        #expect(container.goodsCount(sugar) == 0)
        container.removeGoods(lumber, difference)
        #expect(container.goodsCount(lumber) == 0)
        container.removeGoods(food, difference)
        #expect(container.goodsCount(food) == 38 + totalDifference)
        container.removeGoods(fish, difference)
        #expect(container.goodsCount(fish) == 39 + totalDifference)
    }
}

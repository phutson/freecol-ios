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

/// SoLTest.java.
@Suite(.serialized)
struct SoLTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()

    @Test func soL() {
        let game = FreeColTestCase.standardGame(Self.spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))

        let bellsType = Self.spec.getGoodsType("model.goods.bells")!
        let colony = FreeColTestCase.standardColony(game, 7)
        for i in 1...100 {
            let requiredBells = (Colony.libertyPerRebel * (colony.sonsOfLiberty + 1) * colony.unitCount) / 100
            colony.addGoods(bellsType, requiredBells - colony.goodsCount(bellsType))
            #expect(colony.sonsOfLiberty == i)
            let rebelCount = Colony.calculateRebelCount(colony.unitCount, colony.sonsOfLiberty)
            #expect(rebelCount == Int((Float(i * 7) / 100).rounded(.down)))
        }
    }
}

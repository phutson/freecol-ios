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

/// ModelMessageTest.java.  Java's equals and hashCode are javaEquals
/// and javaHash here.
@Suite(.serialized)
struct ModelMessageTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()

    func colonyGame() -> (Game, Colony) {
        let game = FreeColTestCase.standardGame(Self.spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))
        return (game, FreeColTestCase.standardColony(game, 1))
    }

    @Test func hashCode() {
        let (_, colony) = colonyGame()
        let cotton = Self.spec.getGoodsType("model.goods.cotton")!
        let mm1 = ModelMessage(.missingGoods, "buildColony.landLocked", colony, cotton)
        let mm2 = ModelMessage(.missingGoods, "buildColony.landLocked", colony, cotton)
        #expect(mm1.javaEquals(mm2))
        #expect(mm1.javaHash == mm2.javaHash)

        let mm3 = ModelMessage(.missingGoods, "buildColony.landLocked", colony, cotton)
        let mm4 = ModelMessage(.missingGoods, "buildColony.landLocked", colony, cotton)
        #expect(mm3 !== mm4)
    }

    @Test func modelMapSet2() {
        let (_, colony) = colonyGame()
        let cotton = Self.spec.getGoodsType("model.goods.cotton")!
        func make() -> ModelMessage {
            ModelMessage(.warehouseCapacity, "model.building.warehouseSoonFull", colony, cotton)
                .addNamed("%goods%", cotton)
                .addName("%colony%", colony.name)
                .addAmount("%amount%", 10)
        }
        let mm1 = make(), mm2 = make()
        #expect(mm1.javaEquals(mm2))
        #expect(mm1.javaHash == mm2.javaHash)
    }

    @Test func defaultId() throws {
        let game = FreeColTestCase.standardGame(Self.spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))
        let player = try #require(game.player(byNationId: "model.nation.dutch"))
        let realMessageId = "player" // Must exist
        let fakeMessageId = "no.such.messageId" // Must not exist
        let mm1 = ModelMessage(.warehouseCapacity, fakeMessageId, realMessageId, player, nil)
        #expect(Messages.message(mm1) == Messages.message(realMessageId))
    }
}

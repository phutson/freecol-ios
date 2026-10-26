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

/// EuropeTest.java.
@Suite(.serialized)
struct EuropeTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()

    @Test func missionary() throws {
        let game = FreeColTestCase.standardGame(Self.spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let amsterdam = try #require(dutch.europe)
        let colonist = Unit(game: game, location: amsterdam, owner: dutch,
                            type: Self.spec.getUnitType("model.unit.freeColonist")!)
        #expect(amsterdam.hasAbility(Ability.dressMissionary))
        #expect(colonist.hasAbility(Ability.dressMissionary))
    }
}

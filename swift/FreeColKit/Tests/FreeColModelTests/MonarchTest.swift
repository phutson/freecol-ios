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
import FreeColUtil
import Testing

/// MonarchTest.java.
@Suite(.serialized)
struct MonarchTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()

    @Test(.disabled("Writing XML is not ported yet"))
    func serialize() {}

    func choicesContain(_ choices: [RandomChoice<Monarch.MonarchAction>], _ action: Monarch.MonarchAction) -> Bool {
        choices.contains { $0.object == action }
    }

    @Test func taxActionChoices() throws {
        let game = FreeColTestCase.standardGame(Self.spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let monarch = try #require(dutch.monarch)

        // The grace period has not yet expired.
        var choices = monarch.actionChoices()
        #expect(choices.isEmpty)

        FreeColTestCase.standardColony(game)
        game.turn = Turn(100)
        dutch.setTax(Monarch.minimumTaxRate / 2)
        choices = monarch.actionChoices()
        #expect(choicesContain(choices, .raiseTaxWar))
        #expect(choicesContain(choices, .raiseTaxAct))
        #expect(!choicesContain(choices, .lowerTaxWar))
        #expect(!choicesContain(choices, .lowerTaxOther))

        let maximumTax = Self.spec.getInteger(GameOptions.maximumTax)!
        dutch.setTax(maximumTax / 2)
        choices = monarch.actionChoices()
        #expect(choicesContain(choices, .raiseTaxWar))
        #expect(choicesContain(choices, .raiseTaxAct))
        #expect(choicesContain(choices, .lowerTaxWar))
        #expect(choicesContain(choices, .lowerTaxOther))

        dutch.setTax(maximumTax + 2)
        choices = monarch.actionChoices()
        #expect(!choicesContain(choices, .raiseTaxWar))
        #expect(!choicesContain(choices, .raiseTaxAct))
        #expect(choicesContain(choices, .lowerTaxWar))
        #expect(choicesContain(choices, .lowerTaxOther))

        dutch.changePlayerType(.rebel)
        choices = monarch.actionChoices()
        #expect(choices.isEmpty)
    }
}

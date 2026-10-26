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

/// FoundingFatherTest.java.
@Suite(.serialized)
struct FoundingFatherTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    @Test func features() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))

        let father1 = FoundingFather(id: "father1", specification: spec)
        father1.type = .trade
        let ability = Ability("some.new.ability")
        spec.addAbility(ability)
        father1.addAbility(ability)
        dutch.addFather(father1)
        #expect(dutch.hasAbility("some.new.ability"))

        let father2 = FoundingFather(id: "father2", specification: spec)
        father2.type = .trade
        let modifier = Modifier("some.new.modifier", 2, .additive, source: father2)
        father2.addModifier(modifier)
        spec.addModifier(modifier)
        dutch.addFather(father2)

        let modifiers = dutch.modifiers("some.new.modifier")
        #expect(modifiers.count == 1)
        #expect(modifiers.first?.value == 2)
        #expect(FeatureContainer.applyModifiers(2, turn: nil, modifiers) == 4)

        let father3 = FoundingFather(id: "father3", specification: spec)
        father3.type = .trade
        father3.addModifier(Modifier("some.new.modifier", 2, .additive, source: father3))
        dutch.addFather(father3)
        #expect(!dutch.modifiers("some.new.modifier").isEmpty)
        #expect(dutch.apply(2, turn: nil, "some.new.modifier") == 6)

        let father4 = FoundingFather(id: "father4", specification: spec)
        father4.type = .trade
        let ability2 = Ability("some.new.ability", value: false)
        #expect(ability != ability2)
        #expect(ability.hashValue != ability2.hashValue)
        father4.addAbility(ability2)
        dutch.addFather(father4)
        #expect(!dutch.hasAbility("some.new.ability"))
    }

    @Test func addAllFathers() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))
        let player = try #require(FreeColTestCase.standardColony(game, 4).owner)
        // All fathers can be added.
        for father in spec.foundingFathers {
            player.addFather(father)
        }
        #expect(player.fatherCount == spec.foundingFathers.count)
    }

    @Test func bellsRequired() throws {
        let expectedValues = [40, 161, 241, 321, 401]
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        #expect(spec.getInteger(GameOptions.foundingFatherFactor) == 40)
        for (index, expected) in expectedValues.enumerated() {
            #expect(dutch.fatherCount == index)
            #expect(dutch.totalFoundingFatherCost == expected)
            dutch.addFather(FoundingFather(id: "father\(index)", specification: spec))
        }
    }

    @Test func availableTo() throws {
        // This feature is not used at the moment.
        let game = FreeColTestCase.standardGame(spec)
        for father in spec.foundingFathers {
            for player in game.players {
                #expect(father.isAvailableTo(player) == player.isEuropean, "\(player.nationId ?? "")")
            }
        }

        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let french = try #require(game.player(byNationId: "model.nation.french"))
        let newFather = FoundingFather(id: "father", specification: spec)
        newFather.type = .trade

        let dutchScope = Scope()
        dutchScope.methodName = "getNationId"
        dutchScope.methodValue = "model.nation.dutch"
        #expect(dutchScope.appliesTo(dutch))

        let frenchScope = Scope()
        frenchScope.methodName = "getNationType"
        frenchScope.methodValue = "model.nationType.cooperation"
        #expect(frenchScope.appliesTo(french))

        newFather.copyScopes([dutchScope, frenchScope])
        for player in game.players {
            #expect(newFather.isAvailableTo(player) == (player === french || player === dutch),
                    "\(player.nationId ?? "")")
        }
    }
}

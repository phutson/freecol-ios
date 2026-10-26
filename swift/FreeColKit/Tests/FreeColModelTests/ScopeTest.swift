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

/// ScopeTest.java.
@Suite(.serialized)
struct ScopeTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }
    var carpenter: UnitType { spec.getUnitType("model.unit.masterCarpenter")! }
    var frigate: UnitType { spec.getUnitType("model.unit.frigate")! }

    @Test func emptyScope() {
        let testScope = Scope()
        // An empty scope applies to all
        #expect(testScope.appliesTo(carpenter))
        #expect(testScope.appliesTo(frigate))
        // unless negated
        testScope.matchNegated = true
        #expect(!testScope.appliesTo(carpenter))
        #expect(!testScope.appliesTo(frigate))
    }

    @Test func typeScope() {
        let testScope = Scope()
        testScope.type = "model.unit.frigate"
        #expect(testScope.appliesTo(frigate))
        #expect(!testScope.appliesTo(carpenter))
        testScope.matchNegated = true
        #expect(!testScope.appliesTo(frigate))
        #expect(testScope.appliesTo(carpenter))

        testScope.matchNegated = false
        testScope.type = "model.unit.masterCarpenter"
        #expect(!testScope.appliesTo(frigate))
        #expect(testScope.appliesTo(carpenter))
        testScope.matchNegated = true
        #expect(testScope.appliesTo(frigate))
        #expect(!testScope.appliesTo(carpenter))
    }

    @Test func abilityScope() {
        let testScope = Scope()
        testScope.abilityId = Ability.navalUnit
        #expect(testScope.appliesTo(frigate) == frigate.hasAbility(Ability.navalUnit))
        #expect(testScope.appliesTo(carpenter) == carpenter.hasAbility(Ability.navalUnit))
    }

    @Test func methodScope() {
        let testScope = Scope()
        testScope.methodName = "getLineOfSight"
        testScope.methodValue = "1"
        #expect(frigate.lineOfSight != 1)
        #expect(!testScope.appliesTo(frigate))
        #expect(carpenter.lineOfSight == 1)
        #expect(testScope.appliesTo(carpenter))
    }

    @Test func combinedScope() {
        let testScope = Scope()
        testScope.type = "model.unit.frigate"
        testScope.abilityId = Ability.navalUnit
        testScope.methodName = "getLineOfSight"
        testScope.methodValue = "2"
        #expect(testScope.appliesTo(frigate))

        testScope.methodValue = "1"
        #expect(!testScope.appliesTo(frigate))

        testScope.methodValue = "2"
        testScope.abilityId = Ability.foundColony
        #expect(!testScope.appliesTo(frigate))
    }

    @Test func matchesNull() {
        let testScope = Scope()
        testScope.type = "model.unit.frigate"
        #expect(testScope.appliesTo(frigate))
        #expect(testScope.appliesTo(nil))
        testScope.matchesNull = false
        #expect(testScope.appliesTo(frigate))
        #expect(!testScope.appliesTo(nil))
    }

    @Test func equality() {
        func make() -> Scope {
            let s = Scope()
            s.type = "model.unit.frigate"
            s.abilityId = Ability.navalUnit
            s.methodName = "getLineOfSight"
            s.methodValue = "2"
            s.matchesNull = true
            s.matchNegated = false
            return s
        }
        let testScope1 = make(), testScope2 = make()
        #expect(testScope1 == testScope1)
        #expect(testScope2 == testScope2)
        func same(_ expected: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect((testScope1 == testScope2) == expected, sourceLocation: sourceLocation)
            #expect((testScope2 == testScope1) == expected, sourceLocation: sourceLocation)
        }
        same(true)

        testScope1.type = "model.unit.carpenter"
        same(false)

        testScope1.type = "model.unit.frigate"
        testScope1.abilityId = Ability.foundColony
        same(false)

        testScope1.abilityId = Ability.navalUnit
        testScope1.abilityValue = false
        same(false)

        testScope1.abilityValue = true
        testScope1.methodName = "getOffence"
        same(false)

        testScope1.methodName = "getLineOfSight"
        testScope1.methodValue = "9"
        same(false)

        testScope1.methodValue = "2"
        same(true)

        testScope1.matchesNull = false
        same(false)

        testScope1.matchesNull = true
        same(true)

        testScope1.matchNegated = true
        same(false)

        testScope1.matchNegated = false
        same(true)
    }

    @Test func gameObjects() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let unit = Unit(game: game, location: map.tile(6, 8), owner: dutch,
                        type: spec.getUnitType("model.unit.freeColonist")!)

        let scope = Scope()
        scope.abilityId = Ability.foundColony
        #expect(scope.appliesTo(unit))
        scope.type = "model.unit.freeColonist"
        #expect(scope.appliesTo(unit))
        scope.type = "model.unit.hardyPioneer"
        #expect(!scope.appliesTo(unit))
    }
}

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

/// ModifierTest.java.
@Suite(.serialized)
struct ModifierTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    var carpenter: UnitType { spec.getUnitType("model.unit.masterCarpenter")! }
    var frigate: UnitType { spec.getUnitType("model.unit.frigate")! }

    @Test func additiveModifier() {
        let modifier = Modifier("test", 3, .additive)
        spec.addModifier(modifier)
        #expect(modifier.applyTo(1) == 4)
    }

    @Test func multiplicativeModifier() {
        let modifier = Modifier("test", 1.5, .multiplicative)
        spec.addModifier(modifier)
        #expect(modifier.applyTo(1) == 1 * 1.5)
        #expect(modifier.applyTo(3) == 3 * 1.5)
    }

    @Test func percentageModifier() {
        let modifier = Modifier("test", 50, .percentage)
        spec.addModifier(modifier)
        #expect(modifier.applyTo(100) == 150)
        #expect(modifier.applyTo(3) == 4.5)
    }

    @Test func combineAdditiveModifiers() {
        let modifiers: Set = [Modifier("test", 3, .additive), Modifier("test", 4, .additive)]
        #expect(FeatureContainer.applyModifiers(1, turn: nil, modifiers) == 1 + 3 + 4)
    }

    @Test func combineMultiplicativeModifiers() {
        let modifiers: Set = [Modifier("test", 3, .multiplicative), Modifier("test", 4, .multiplicative)]
        #expect(FeatureContainer.applyModifiers(2, turn: nil, modifiers) == 2 * 3 * 4)
    }

    @Test func combinePercentageModifiers() {
        let modifiers: Set = [Modifier("test", 3, .percentage), Modifier("test", 4, .percentage)]
        let expected: Float = 100 * (100 + 3) / 100 * (100 + 4) / 100
        #expect(FeatureContainer.applyModifiers(100, turn: nil, modifiers) == expected)
    }

    @Test func tiedModifierOrder() {
        // Same index, type, id and source: only the values differ.
        // Float rounding makes the result depend on the order, so the
        // order must not come from the input collection.
        let minus60 = Modifier("test", -60, .percentage)
        let plus25 = Modifier("test", 25, .percentage)

        var lowestFirst: Float = 2 + (2 * -60) / 100
        lowestFirst = lowestFirst + (lowestFirst * 25) / 100
        var highestFirst: Float = 2 + (2 * 25) / 100
        highestFirst = highestFirst + (highestFirst * -60) / 100
        #expect(Int(lowestFirst) != Int(highestFirst), "Test needs an order-sensitive case")

        #expect(FeatureContainer.applyModifiers(2, turn: nil, [minus60, plus25]) == lowestFirst)
        #expect(FeatureContainer.applyModifiers(2, turn: nil, [plus25, minus60]) == lowestFirst)
    }

    @Test func combinedModifier() {
        let modifier1 = Modifier("test", 3, .additive)
        let modifier2 = Modifier("test", 1.5, .multiplicative)
        let modifier3 = Modifier("test", 50, .percentage)

        var modifiers: Set = [modifier1, modifier2]
        #expect(FeatureContainer.applyModifiers(1, turn: nil, modifiers) == (1 + 3) * 1.5)

        modifiers.insert(modifier3)
        #expect(FeatureContainer.applyModifiers(1, turn: nil, modifiers) == ((1 + 3) * 1.5) * 1.5)

        modifiers.remove(modifier1)
        #expect(FeatureContainer.applyModifiers(10, turn: nil, modifiers) == 10 * 1.5 * 1.5)
    }

    @Test func scope() {
        let modifier1 = Modifier("test", 3, .additive)
        let modifier2 = Modifier("test", 1.5, .multiplicative)
        let modifier3 = Modifier("test", 30, .percentage)

        let featureContainer = FeatureContainer()
        featureContainer.addModifier(modifier1)
        featureContainer.addModifier(modifier2)
        featureContainer.addModifier(modifier3)

        // applies to frigate
        let scope1 = Scope()
        scope1.type = "model.unit.frigate"
        // applies to carpenter
        let scope2 = Scope()
        scope2.abilityId = Ability.navalUnit
        scope2.abilityValue = false
        // applies to frigate
        let scope3 = Scope()
        scope3.methodName = "getLineOfSight"
        scope3.methodValue = "2"

        modifier1.copyScopes([scope1])
        #expect(modifier1.appliesTo(frigate))
        #expect(!modifier1.appliesTo(carpenter))

        let frigateValue: Float = ((1 + 3) * 1.5) + ((1 + 3) * 1.5) * 30 / 100
        let carpenterValue: Float = 1.5 + (1.5 * 30) / 100
        var result = featureContainer.modifiers("test", for: frigate)
        #expect(result.count == 3)
        #expect(FeatureContainer.applyModifiers(1, turn: nil, result) == frigateValue)

        result = featureContainer.modifiers("test", for: carpenter)
        #expect(result.count == 2)
        #expect(FeatureContainer.applyModifiers(1, turn: nil, result) == carpenterValue)

        modifier2.copyScopes([scope2, scope3])
        #expect(modifier2.appliesTo(frigate))
        #expect(modifier2.appliesTo(carpenter))

        result = featureContainer.modifiers("test", for: frigate)
        #expect(result.count == 3)
        #expect(FeatureContainer.applyModifiers(1, turn: nil, result) == frigateValue)

        result = featureContainer.modifiers("test", for: carpenter)
        #expect(result.count == 2)
        #expect(FeatureContainer.applyModifiers(1, turn: nil, result) == carpenterValue)
    }

    @Test func timeLimits() {
        let modifier1 = Modifier("test", 1, .additive)
        let modifier2 = Modifier("test", 2, .additive)

        modifier1.firstTurn = Turn(10)
        modifier1.lastTurn = Turn(30)
        modifier2.firstTurn = Turn(20)
        modifier2.lastTurn = Turn(40)

        #expect(modifier1.hasTimeLimit)
        #expect(modifier2.hasTimeLimit)

        #expect(!modifier1.appliesTo(frigate, turn: Turn(5)))
        #expect(!modifier1.appliesTo(frigate, turn: Turn(35)))
        #expect(!modifier1.isOutOfDate(Turn(25)))
        #expect(modifier1.appliesTo(frigate, turn: Turn(25)))

        #expect(!modifier2.appliesTo(frigate, turn: Turn(5)))
        #expect(!modifier2.isOutOfDate(Turn(25)))
        #expect(modifier2.appliesTo(frigate, turn: Turn(25)))

        let featureContainer = FeatureContainer()
        featureContainer.addModifier(modifier1)
        featureContainer.addModifier(modifier2)
        var modifiers = featureContainer.modifiers("test", for: frigate, turn: Turn(15))
        #expect(modifiers.count == 1)
        #expect(modifiers.first === modifier1)
        modifiers = featureContainer.modifiers("test", for: frigate, turn: Turn(35))
        #expect(modifiers.count == 1)
        #expect(modifiers.first === modifier2)
    }

    @Test func increments() {
        let modifier1 = Modifier("test", 1, .additive)
        let modifier2 = Modifier("test", 2, .additive)

        modifier1.setIncrement(.additive, 1, firstTurn: Turn(10), lastTurn: Turn(15))
        #expect(!modifier1.appliesTo(frigate, turn: Turn(9)))
        #expect(modifier1.appliesTo(frigate, turn: Turn(10)))
        #expect(modifier1.hasIncrement)

        let featureContainer = FeatureContainer()
        featureContainer.addModifier(modifier1)
        featureContainer.addModifier(modifier2)

        func apply(_ turn: Int) -> Float {
            FeatureContainer.applyModifiers(1, turn: Turn(turn),
                                            featureContainer.modifiers("test", for: frigate, turn: Turn(turn)))
        }
        #expect(apply(9) == 3) // only modifier2
        #expect(apply(10) == 4) // both modifiers
        #expect(apply(11) == 5)
        #expect(apply(15) == 9)
        #expect(apply(16) == 3) // only modifier2
    }

    @Test func hashEquals() {
        let scope1 = Scope()
        scope1.type = "model.unit.frigate"
        scope1.abilityId = "whatever"

        let scope2 = Scope()
        scope2.type = "model.unit.frigate"
        scope2.abilityId = "whatever"

        let scope3 = Scope()
        scope3.type = "model.unit.frigate"
        scope3.abilityId = "whatever"
        scope3.abilityValue = false

        #expect(scope1 == scope1)
        #expect(scope1.hashValue == scope1.hashValue)
        #expect(scope1 == scope2)
        #expect(scope1.hashValue == scope2.hashValue)
        #expect(scope1 != scope3)
        #expect(scope1.hashValue != scope3.hashValue)

        let modifier1 = Modifier("test", 3, .additive)
        let modifier2 = Modifier("test", 3, .additive)
        let modifier3 = Modifier("test", 2, .additive)

        func same(_ a: Modifier, _ b: Modifier, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(a == b, sourceLocation: sourceLocation)
            #expect(a.hashValue == b.hashValue, sourceLocation: sourceLocation)
        }
        func different(_ a: Modifier, _ b: Modifier, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(a != b, sourceLocation: sourceLocation)
            #expect(a.hashValue != b.hashValue, sourceLocation: sourceLocation)
        }
        same(modifier1, modifier1)
        same(modifier1, modifier2)
        different(modifier1, modifier3)

        let scopeList1 = [scope1, scope3]
        let scopeList2 = [scope3, scope1]
        let scopeList3 = [scope1, scope2]

        modifier1.copyScopes(scopeList1)
        modifier2.copyScopes(scopeList1)
        same(modifier1, modifier1)
        same(modifier1, modifier2)
        different(modifier1, modifier3)

        modifier2.copyScopes(scopeList2)
        same(modifier2, modifier2)
        same(modifier1, modifier2)
        different(modifier2, modifier3)

        modifier2.copyScopes(scopeList3)
        same(modifier2, modifier2)
        different(modifier1, modifier2)
        different(modifier2, modifier3)
    }

    /// A single modifier with an unknown value makes the result unknown.
    @Test func modifierUnknown() {
        let featureContainer = FeatureContainer()
        featureContainer.addModifier(Modifier("test", 3, .additive))
        featureContainer.addModifier(Modifier("test", Modifier.unknown, .multiplicative))
        featureContainer.addModifier(Modifier("test", 30, .percentage))

        let turn = Turn(15)
        #expect(FeatureContainer.applyModifiers(1, turn: turn, featureContainer.modifiers("test", turn: turn))
                == Modifier.unknown)
    }
}

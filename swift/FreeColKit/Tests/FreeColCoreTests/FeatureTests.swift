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

import Testing
import FreeColUtil
import FreeColCore
import FreeColTestSupport

struct ModifierApplicationTests {

    @Test func oracleHasCases() {
        #expect(FeatureCases.list("applyModifiers").count == 400)
    }

    /// The result, each value and the description match Java for every
    /// case, whatever order the modifiers are given in.
    @Test func applyModifiersMatchesJava() throws {
        let shuffler = JavaRandom(seed: 11)
        for (n, c) in FeatureCases.list("applyModifiers").enumerated() {
            let b = FeatureBuilder()
            let json = try #require(c["modifiers"]?.arrayValue)
            let mods = json.map(b.modifier)
            let turn = c["turn"]?.intValue.map { Turn(Int($0)) }
            let base = float(c["baseBits"])
            let expected = c["resultBits"]!.intValue!

            for (m, j) in zip(mods, json) {
                #expect(m.description == j["string"]?.stringValue, "case \(n)")
            }
            let values = c["valueAtTurnBits"]!.arrayValue!.map { $0.intValue! }
            #expect(mods.map { bits($0.value(at: turn)) } == values, "case \(n)")

            for attempt in 0..<4 {
                var input = mods
                if attempt > 0 { shuffler.shuffle(&input) }
                let result = FeatureContainer.applyModifiers(base, turn: turn, input)
                #expect(bits(result) == expected, "case \(n), attempt \(attempt)")
            }
        }
    }

    /// Swift sorts into the same order as Java, up to modifiers that
    /// tie on every key (which apply the same operation).
    @Test func applicationOrderMatchesJava() throws {
        var ties = 0
        for (n, c) in FeatureCases.list("applyModifiers").enumerated() {
            let b = FeatureBuilder()
            let mods = try #require(c["modifiers"]?.arrayValue).map(b.modifier)
            let javaOrder = c["sortedOrder"]!.arrayValue!.map { mods[Int($0.intValue!)] }
            let swiftOrder = Modifier.sortedForApplication(mods.reversed())
            for (s, j) in zip(swiftOrder, javaOrder) {
                #expect(Modifier.compareForApplication(s, j) == 0, "case \(n)")
                if s !== j { ties += 1 }
            }
        }
        // Make sure the cases do exercise full ties.
        #expect(ties > 0)
    }

    @Test func unknownValueMakesTheResultUnknown() {
        let mods = [Modifier("x", 2, .additive), Modifier("x", Modifier.unknown, .additive, index: 5),
                    Modifier("x", 3, .additive, index: 10)]
        let result = FeatureContainer.applyModifiers(1, turn: nil, mods)
        #expect(result == Modifier.unknown)
        #expect(!mods[1].isKnown && mods[0].isKnown)
    }

    @Test func tiedPercentagesMatchTheJavaRegressionTest() {
        // ModifierTest.testTiedModifierOrder: -60% then +25% of 2 is
        // 0.99999994 whichever order the input has.
        let a = Modifier("test", -60, .percentage), b = Modifier("test", 25, .percentage)
        let lowestFirst: Float = {
            var x: Float = 2 + (2 * -60) / 100
            x = x + (x * 25) / 100
            return x
        }()
        #expect(FeatureContainer.applyModifiers(2, turn: nil, [a, b]) == lowestFirst)
        #expect(FeatureContainer.applyModifiers(2, turn: nil, [b, a]) == lowestFirst)
        #expect(JavaMath.toInt(lowestFirst) == 0)
    }
}

struct ScopeTests {

    @Test func appliesToMatchesJava() throws {
        let cases = FeatureCases.list("scopes")
        #expect(cases.count == 150)
        for (n, c) in cases.enumerated() {
            let b = FeatureBuilder()
            let scope = b.scope(c["scope"]!)
            #expect(scope.description == c["scope"]?["string"]?.stringValue, "case \(n)")
            for (target, expected) in try #require(c["appliesTo"]?.objectValue) {
                let object: FreeColObject? = target == "null" ? nil : b.type(target)
                #expect(.bool(scope.appliesTo(object)) == expected, "case \(n) \(target)")
            }
        }
    }

    /// Objects that are not rule types match type scopes through their
    /// scopeType, and method scopes through scopeMethodValue.
    @Test func gameObjectsAnswerThroughHooks() {
        final class Thing: FreeColObject {
            let kind: FreeColSpecObjectType?
            let water: Bool?
            init(kind: FreeColSpecObjectType?, water: Bool?) {
                self.kind = kind
                self.water = water
            }
            override var xmlTagName: String { "thing" }
            override var scopeType: FreeColSpecObjectType? { kind }
            override func scopeMethodValue(_ name: String) -> String? {
                name == "isWater" ? water.map(String.init) : nil
            }
        }
        let plains = TestType("model.tile.plains")
        let typeScope = Scope()
        typeScope.type = "model.tile.plains"
        #expect(typeScope.appliesTo(Thing(kind: plains, water: nil)))
        #expect(!typeScope.appliesTo(Thing(kind: TestType("model.tile.ocean"), water: nil)))
        #expect(!typeScope.appliesTo(Thing(kind: nil, water: nil)))

        let waterScope = Scope()
        waterScope.methodName = "isWater"
        waterScope.methodValue = "true"
        #expect(waterScope.appliesTo(Thing(kind: nil, water: true)))
        #expect(!waterScope.appliesTo(Thing(kind: nil, water: false)))
        // No such method: Java compares "null".
        waterScope.methodValue = "null"
        #expect(waterScope.appliesTo(Thing(kind: nil, water: nil)))
    }
}

struct FeatureContainerTests {

    @Test func lookupsMatchJava() throws {
        let cases = FeatureCases.list("containers")
        #expect(cases.count == 50)
        for (n, c) in cases.enumerated() {
            let b = FeatureBuilder()
            let holder = TestType("model.unit.holder\(n)")
            var added: [Ability] = []
            for a in c["abilities"]?.arrayValue ?? [] {
                let ability = b.ability(a)
                #expect(.bool(holder.addAbility(ability)) == a["added"], "case \(n)")
                #expect(ability.description == a["string"]?.stringValue)
                added.append(ability)
            }
            for m in c["modifiers"]?.arrayValue ?? [] {
                #expect(.bool(holder.addModifier(b.modifier(m))) == m["added"], "case \(n)")
            }
            for q in try #require(c["queries"]?.arrayValue) {
                let id = q["id"]?.stringValue
                let target = b.type(q["target"]?.stringValue)
                let turn = q["turn"]?.intValue.map { Turn(Int($0)) }
                let label = "case \(n) \(id ?? "nil") \(target?.id ?? "nil") \(turn?.number ?? -1)"
                #expect(.bool(holder.hasAbility(id, for: target, turn: turn)) == q["hasAbility"], "\(label)")
                #expect(Int64(holder.abilities(id, for: target, turn: turn).count)
                        == q["abilityCount"]?.intValue, "\(label)")
                #expect(.bool(holder.hasModifier(id, for: target, turn: turn)) == q["hasModifier"], "\(label)")
                #expect(Int64(holder.modifiers(id, for: target, turn: turn).count)
                        == q["modifierCount"]?.intValue, "\(label)")
                #expect(bits(holder.apply(7, turn: turn, id, for: target))
                        == q["applyBits"]?.intValue, "\(label)")
            }
            #expect(Int64(holder.allModifiers.count) == c["modifierTotal"]?.intValue, "case \(n)")
            #expect(Int64(holder.abilities().count) == c["abilityTotal"]?.intValue, "case \(n)")
            if let first = added.first {
                #expect(.bool(holder.removeAbility(first) != nil) == c["removeFirstAbility"], "case \(n)")
                #expect(Int64(holder.abilities().count) == c["abilityTotalAfterRemove"]?.intValue)
            }
        }
    }

    @Test func addAndRemoveFeaturesBySource() {
        let source = TestType("model.foundingFather.test")
        source.addModifier(Modifier("model.modifier.x", 2, .additive, source: source))
        source.addAbility(Ability("model.ability.a", source: source))
        let player = TestType("model.unit.player")
        player.addModifier(Modifier("model.modifier.x", 1, .additive))
        player.addFeatures(of: source)
        #expect(player.allModifiers.count == 2)
        #expect(player.hasAbility("model.ability.a"))
        player.removeFeatures(of: source)
        #expect(player.allModifiers.count == 1)
        #expect(!player.hasAbility("model.ability.a"))
    }

    @Test func replaceSourceCopiesFeatures() {
        let oldSource = TestType("model.source.old"), newSource = TestType("model.source.new")
        let fc = FeatureContainer()
        let original = Modifier("model.modifier.x", 2, .additive, source: oldSource)
        fc.addModifier(original)
        fc.addModifier(Modifier("model.modifier.y", 3, .additive, source: newSource))
        fc.replaceSource(oldSource, newSource)
        let mods = fc.modifierValues
        #expect(mods.count == 2)
        #expect(mods.allSatisfy { $0.source === newSource })
        #expect(original.source === oldSource) // A copy was changed.
    }

    @Test func noAbilitiesIsNotHavingTheAbility() {
        #expect(!FeatureContainer.allAbilities([Ability]()))
        #expect(!TestType("x").hasAbility("model.ability.any"))
        #expect(TestObject("plain").abilities().isEmpty)
        #expect(!TestObject("plain").addModifier(Modifier("m", 1, .additive)))
    }
}

struct FeatureEqualityTests {

    @Test func equalityMatchesJava() throws {
        let cases = FeatureCases.list("equality")
        #expect(cases.count == 151)
        for (n, c) in cases.enumerated() {
            let b = FeatureBuilder()
            let x = b.modifier(c["a"]!), y = b.modifier(c["b"]!)
            let equal = c["equal"] == .bool(true)
            #expect(x.isEqual(to: y) == equal, "case \(n): \(x) vs \(y)")
            #expect(y.isEqual(to: x) == equal, "case \(n) reversed")
            if equal { #expect(x.hashValue == y.hashValue, "case \(n) hash") }
        }
    }

    @Test func emptyAndMissingScopesDiffer() {
        // Java distinguishes a cleared scope container from none at all.
        let a = Modifier("m", 1, .additive), b = Modifier("m", 1, .additive)
        #expect(a == b)
        b.addScope(Scope())
        b.clearScopes()
        #expect(!b.hasScope)
        #expect(a != b)
    }

    @Test func copiesAreEqual() {
        let source = TestType("model.source.a")
        let m = Modifier("m", 1.5, .multiplicative, source: source, index: 30)
        m.addScope(Scope())
        m.setIncrement(.additive, -0.5, firstTurn: Turn(2), lastTurn: Turn(5))
        let copy = Modifier(copying: m)
        #expect(copy == m && copy !== m)
        let a = Ability("a", source: source, value: false)
        #expect(Ability(copying: a) == a)
    }
}

struct TimedModifierTests {

    @Test func makeTimedModifierMatchesJava() throws {
        let cases = FeatureCases.list("timedModifiers")
        #expect(cases.count == 5)
        for (n, c) in cases.enumerated() {
            let b = FeatureBuilder()
            let template = b.modifier(c["template"]!)
            let m = Modifier.makeTimedModifier("model.modifier.timed", template: template,
                                               start: Turn(4))
            let expected = c["result"]!
            #expect(m.description == expected["string"]?.stringValue, "case \(n)")
            #expect(m.firstTurn.map { Int64($0.number) } == expected["firstTurn"]?.intValue)
            #expect(m.lastTurn.map { Int64($0.number) } == expected["lastTurn"]?.intValue)
            #expect(m.temporary == (expected["temporary"] == .bool(true)))
            let values = c["valueBitsByTurn1to14"]!.arrayValue!.map { $0.intValue! }
            #expect((1...14).map { bits(m.value(at: Turn($0))) } == values, "case \(n)")
        }
    }
}

struct TurnTests {

    @Test func calendarMatchesJava() throws {
        let calendars = try #require(FeatureCases.features?["turns"]?["calendars"]?.arrayValue)
        #expect(calendars.count == 3)
        for c in calendars {
            let cal = TurnCalendar(startingYear: Int(c["startingYear"]!.intValue!),
                                   seasonYear: Int(c["seasonYear"]!.intValue!),
                                   seasonNumber: Int(c["seasonNumber"]!.intValue!))
            let years = c["yearByTurn1to300"]!.arrayValue!.map { Int($0.intValue!) }
            let seasons = c["seasonByTurn1to300"]!.arrayValue!.map { Int($0.intValue!) }
            #expect((1...300).map { cal.year(of: Turn($0)) } == years, "\(cal)")
            #expect((1...300).map { cal.season(of: Turn($0)) } == seasons, "\(cal)")
            for t in c["yearToTurn"]!.arrayValue! {
                let v = t.arrayValue!.map { Int($0.intValue!) }
                #expect(cal.turnNumber(year: v[0], season: v[1]) == v[2], "\(cal) \(v)")
            }
            let first = Int(c["firstSeasonTurn"]!.intValue!)
            #expect(cal.isFirstSeasonTurn(Turn(first)) && !cal.isFirstSeasonTurn(Turn(first + 1)))
        }
    }

    @Test func turnBasics() {
        #expect(Turn(1).isFirstTurn && !Turn(2).isFirstTurn)
        #expect(Turn(5).next() == Turn(6))
        #expect(Turn(7).description == "7")
        #expect(TurnCalendar.standard.year(of: Turn(1)) == 1492)
    }
}

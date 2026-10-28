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
import FreeColCore
import FreeColTestSupport

/// A minimal concrete object, like the anonymous subclass the Java
/// oracle uses.
final class TestObject: FreeColObject {
    init(_ id: String?) {
        super.init()
        self.id = id
    }

    override var xmlTagName: String { "test" }
}

/// A game that can issue identifiers, as Java's ServerGame does.
final class TestGame: Game {
    override func getNextId() -> Int {
        defer { nextId += 1 }
        return nextId
    }
}

/// A game object type for the registry tests.
final class TestUnit: FreeColGameObject {
    override var xmlTagName: String { "unit" }
}

struct FreeColObjectIdTests {

    @Test func identifierPartsMatchJava() throws {
        let cases = try #require(try JavaOracle.load()["ids"]?["properties"]?.arrayValue)
        #expect(cases.count == 18)
        for c in cases {
            let id = c["id"]!.stringValue!
            let o = TestObject(id)
            #expect(o.idType == c["idType"]?.stringValue, "idType of \(id)")
            #expect(Int64(o.idNumber) == c["idNumber"]?.intValue, "idNumber of \(id)")
            #expect(o.suffix == c["suffix"]?.stringValue, "suffix of \(id)")
            #expect(o.suffix(afterPrefix: "model.unit.") == c["suffixAfterModelUnit"]?.stringValue,
                    "suffix(afterPrefix:) of \(id)")
        }
    }

    @Test func compareIdsMatchesJava() throws {
        let cases = try #require(try JavaOracle.load()["ids"]?["compareIds"]?.arrayValue)
        #expect(cases.count == 18 * 18)
        for c in cases {
            let parts = c.arrayValue!
            let a = TestObject(parts[0].stringValue), b = TestObject(parts[1].stringValue)
            #expect(Int64(FreeColObject.compareIds(a, b)) == parts[2].intValue,
                    "compareIds(\(a.id!), \(b.id!))")
        }
    }

    @Test func missingObjectsAndIdsSortFirst() {
        let a = TestObject("unit:1"), none = TestObject(nil)
        #expect(FreeColObject.compareIds(nil, nil) == 0)
        #expect(FreeColObject.compareIds(nil, a) == -1)
        #expect(FreeColObject.compareIds(a, nil) == 1)
        #expect(FreeColObject.compareIds(none, a) == -1)
        #expect(FreeColObject.compareIds(none, TestObject(nil)) == 0)
        #expect(none.idType == nil && none.idNumber == -1 && none.suffix == nil)
    }

    @Test func numbersSortNumerically() {
        let ids = ["player:10", "player:2", "player:1", "colony:5"]
        let sorted = ids.map(TestObject.init).sorted(by: FreeColObject.idOrder).map(\.id!)
        #expect(sorted == ["colony:5", "player:1", "player:2", "player:10"])
    }

    @Test func equalityAndHashingFollowIdentifiers() {
        let a = TestObject("unit:1"), b = TestObject("unit:1"), c = TestObject("unit:2")
        #expect(a == b && a != c)
        #expect(Set([a, b, c]).count == 2)
        #expect(a.idEquals(b) && !a.idEquals(c) && !a.idEquals(nil))
        #expect(!TestObject(nil).idEquals(TestObject(nil)))
    }

    @Test func plainObjectsHaveNoGameOrSpecification() {
        let o = TestObject("x")
        #expect(o.game == nil && o.specification == nil)
        #expect(o.classIndex == FreeColObject.defaultClassIndex)
        #expect(FreeColObject.objectClassIndex("not a FreeColObject") == 1000)
        #expect(o.description == "TestObject:x")
    }
}

struct FreeColSpecObjectTests {

    final class Rule: FreeColSpecObject {
        override var xmlTagName: String { "rule" }
    }

    @Test func holdsItsSpecification() {
        let spec = Specification(id: "classic")
        let rule = Rule(specification: spec)
        #expect(rule.specification === spec)
        let other = Specification(id: "freecol")
        rule.setSpecification(other)
        #expect(rule.specification === other)
    }
}

struct GameRegistryTests {

    @Test func gameIsObjectZeroInItsOwnGame() {
        let game = TestGame(specification: Specification(id: "freecol"))
        #expect(game.id == "0")
        #expect(game.game === game)
        #expect(game.isInitialized)
        #expect(game.getFreeColGameObject("0") === game)
        #expect(game.specification?.id == "freecol")
        #expect(game.classIndex == FreeColGameObject.freeColGameObjectClassIndex)
    }

    @Test func newObjectsGetSequentialIdentifiers() {
        let game = TestGame()
        let u1 = TestUnit(game: game), u2 = TestUnit(game: game)
        #expect(u1.id == "unit:1" && u2.id == "unit:2")
        #expect(u1.isInitialized)
        #expect(game.getFreeColGameObject("unit:2") === u2)
        #expect(game.getFreeColGameObject("unit:2", as: TestUnit.self) === u2)
        #expect(game.getFreeColGameObject("unit:2", as: Game.self) == nil)
        #expect(u1.specification === game.specification)
    }

    @Test func objectsWithKnownIdentifiersAreNotInitialized() {
        let game = TestGame()
        let u = TestUnit(game: game, id: "unit:77")
        #expect(!u.isInitialized)
        #expect(game.getFreeColGameObject("unit:77") === u)
    }

    @Test func reinterningMovesTheRegistration() {
        let game = TestGame()
        let u = TestUnit(game: game, id: "unit:5")
        u.internId("unit:6")
        #expect(game.getFreeColGameObject("unit:5") == nil)
        #expect(game.getFreeColGameObject("unit:6") === u)
        u.intern() // Same identifier: re-registers without complaint.
        #expect(game.getFreeColGameObject("unit:6") === u)
    }

    @Test func registryHoldsObjectsWeakly() {
        let game = TestGame()
        var u: TestUnit? = TestUnit(game: game, id: "unit:9")
        #expect(game.getFreeColGameObject("unit:9") != nil)
        u = nil
        #expect(u == nil)
        #expect(game.getFreeColGameObject("unit:9") == nil)
        #expect(game.freeColGameObjects.map(\.id) == ["0"])
    }

    @Test func disposeUnregisters() {
        let game = TestGame()
        let u = TestUnit(game: game)
        u.dispose()
        #expect(u.isDisposed)
        #expect(game.getFreeColGameObject(u.id) == nil)
        u.dispose() // A second dispose does nothing.
    }

    @Test func listsLiveObjectsInIdentifierOrder() {
        let game = TestGame()
        let units = (0..<12).map { _ in TestUnit(game: game) }
        // Kept alive to the end, as the registry holds them weakly
        // (optimised builds would let them go at once).
        withExtendedLifetime(units) {
            #expect(game.freeColGameObjects.map(\.id!)
                    == ["0"] + (1...12).map { "unit:\($0)" })
        }
    }

    @Test func manyRemovalsCleanTheRegistry() {
        let game = TestGame()
        let keep = TestUnit(game: game)
        for _ in 0..<200 {
            TestUnit(game: game).dispose()
        }
        #expect(game.freeColGameObjects.count == 2)
        #expect(game.getFreeColGameObject(keep.id) === keep)
    }

    @Test func equalityNeedsTheSameGame() {
        let g1 = TestGame(), g2 = TestGame()
        let a = TestUnit(game: g1, id: "unit:1")
        let b = TestUnit(game: g2, id: "unit:1")
        let c = TestUnit(game: g1, id: "unit:2")
        #expect(a != b)
        #expect(a == a && a != c)
        c.internId("unit:3")
        #expect(Set<FreeColObject>([a, b, c]).count == 3)
    }

    @Test func gameReferenceIsWeak() {
        var game: TestGame? = TestGame()
        let u = TestUnit(game: game!, id: "unit:1")
        weak let weakGame = game
        game = nil
        #expect(weakGame == nil)
        #expect(u.game == nil && u.specification == nil)
    }
}

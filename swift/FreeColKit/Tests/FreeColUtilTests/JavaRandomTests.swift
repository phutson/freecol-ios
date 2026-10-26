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
import FreeColTestSupport

/// One seed's worth of expected values from the Java oracle.
struct OracleSeed: CustomTestStringConvertible, Sendable {
    let json: JSONValue
    var seed: Int64 { json["seed"]!.intValue! }
    var testDescription: String { "seed \(seed)" }

    static let all: [OracleSeed] = {
        (try? JavaOracle.load())?["random"]?.arrayValue?.map(OracleSeed.init) ?? []
    }()
}

private func int32s(_ value: JSONValue?) -> [Int32] {
    value?.arrayValue?.compactMap { $0.intValue }.map { Int32($0) } ?? []
}

struct JavaRandomTests {

    @Test func oracleIsPresent() throws {
        let oracle = try JavaOracle.load()
        #expect(oracle["kind"] == .string("javaCompat"))
        #expect(OracleSeed.all.count == 7)
    }

    @Test(arguments: OracleSeed.all)
    func nextInt(_ s: OracleSeed) {
        let r = JavaRandom(seed: s.seed)
        let expected = int32s(s.json["nextInt"])
        #expect((0..<expected.count).map { _ in r.nextInt() } == expected)
    }

    @Test(arguments: OracleSeed.all)
    func nextIntBound(_ s: OracleSeed) throws {
        let bounds = try #require(s.json["nextIntBound"]?.objectValue)
        #expect(bounds.count == 13)
        for (bound, values) in bounds {
            let r = JavaRandom(seed: s.seed)
            let expected = int32s(values)
            let actual = (0..<expected.count).map { _ in r.nextInt(Int32(bound)!) }
            #expect(actual == expected, "bound \(bound)")
        }
    }

    @Test(arguments: OracleSeed.all)
    func nextFloatAndDouble(_ s: OracleSeed) {
        var r = JavaRandom(seed: s.seed)
        let floats = s.json["nextFloatBits"]!.arrayValue!.map { UInt32(truncatingIfNeeded: $0.intValue!) }
        #expect(floats.map { _ in r.nextFloat().bitPattern } == floats)
        r = JavaRandom(seed: s.seed)
        let doubles = s.json["nextDoubleBits"]!.arrayValue!.map { UInt64(bitPattern: $0.intValue!) }
        #expect(doubles.map { _ in r.nextDouble().bitPattern } == doubles)
    }

    @Test(arguments: OracleSeed.all)
    func intsStream(_ s: OracleSeed) throws {
        let ranges = try #require(s.json["intsStream"]?.objectValue)
        for (range, values) in ranges {
            let expected = int32s(values)
            let actual = JavaRandom(seed: s.seed)
                .ints(expected.count, origin: 0, bound: Int32(range)!)
            #expect(actual == expected, "range \(range)")
        }
    }

    @Test(arguments: OracleSeed.all)
    func shuffle(_ s: OracleSeed) throws {
        let shuffles = try #require(s.json["shuffle"]?.objectValue)
        for (size, values) in shuffles {
            var list = Array(0..<Int32(size)!)
            JavaRandom(seed: s.seed).shuffle(&list)
            #expect(list == int32s(values), "size \(size)")
        }
    }

    @Test(arguments: OracleSeed.all)
    func mixedCalls(_ s: OracleSeed) {
        let r = JavaRandom(seed: s.seed)
        let expected = s.json["mixed"]!.arrayValue!.map { $0.intValue! }
        let actual: [Int64] = (0..<expected.count).map { i in
            switch i % 4 {
            case 0: Int64(r.nextInt(13))
            case 1: Int64(Int32(bitPattern: r.nextFloat().bitPattern))
            case 2: Int64(bitPattern: r.nextDouble().bitPattern)
            default: Int64(r.nextInt())
            }
        }
        #expect(actual == expected)
    }

    @Test(arguments: OracleSeed.all)
    func savedState(_ s: OracleSeed) throws {
        let r = JavaRandom(seed: s.seed)
        #expect(r.serializedState == s.json["initialState"]?.stringValue)
        for _ in 0..<7 { _ = r.nextInt(100) }
        let saved = try #require(s.json["stateAfter7"]?.stringValue)
        #expect(r.serializedState == saved)

        // Restore Java's saved state and continue the sequence.
        let restored = try #require(JavaRandom(serializedState: saved))
        let expected = int32s(s.json["afterRestore"])
        #expect((0..<expected.count).map { _ in restored.nextInt(1000) } == expected)
        #expect(JavaRandom(serializedState: saved.lowercased())?.serializedState == saved)
    }

    @Test func rejectsOtherSerializedData() {
        #expect(JavaRandom(serializedState: "") == nil)
        #expect(JavaRandom(serializedState: "ACED0005") == nil)
        let good = JavaRandom(seed: 1).serializedState
        #expect(JavaRandom(serializedState: String(good.dropLast(2)) + "79") == nil)
        #expect(JavaRandom(serializedState: "X" + good.dropFirst()) == nil)
    }

    @Test func setSeedRestartsTheSequence() {
        let r = JavaRandom(seed: 99)
        let first = (0..<5).map { _ in r.nextInt() }
        r.setSeed(99)
        #expect((0..<5).map { _ in r.nextInt() } == first)
    }
}

struct RandomUtilsTests {

    @Test func traceMatchesJavaLogText() {
        let r = JavaRandom(seed: 42)
        var lines: [String] = []
        r.trace = { lines.append($0) }
        _ = RandomUtils.randomInt("pick", r, 10)
        _ = RandomUtils.randomInts("batch", r, 6, 3)
        _ = RandomUtils.randomFloat("f", r)
        _ = RandomUtils.randomDouble("d", r)
        var list = [1, 2, 3]
        RandomUtils.randomShuffle("s", &list, r)
        #expect(lines.count == 5)
        #expect(lines[0] == "pick random(10) = 0")
        #expect(lines[1].hasPrefix("batch random = [ ") && lines[1].hasSuffix(" ]"))
        #expect(lines[2].hasPrefix("f random(1.0f) = 0."))
        #expect(lines[3].hasPrefix("d random(1.0) = 0."))
        #expect(lines[4] == "s shuffle.")
    }

    @Test func smallListsDoNotUseTheGenerator() {
        let r = JavaRandom(seed: 5)
        let before = r.serializedState
        #expect(RandomUtils.randomMember("m", [7], r) == 7)
        #expect(RandomUtils.randomMember("m", [Int](), r) == nil)
        var one = [1]
        RandomUtils.randomShuffle("s", &one, r)
        #expect(r.serializedState == before)
    }

    @Test func intCacheRefillsInBatches() {
        let cache = RandomUtils.RandomIntCache("c", JavaRandom(seed: 3), range: 100, size: 4)
        let direct = JavaRandom(seed: 3)
        let expected = direct.ints(4, origin: 0, bound: 100) + direct.ints(4, origin: 0, bound: 100)
        #expect((0..<8).map { _ in cache.nextInt() } == expected)
    }
}

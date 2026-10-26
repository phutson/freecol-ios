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

struct JavaMathTests {

    @Test func floatConversionsMatchJava() throws {
        let cases = try #require(try JavaOracle.load()["math"]?["float"]?.arrayValue)
        #expect(cases.count > 200)
        for c in cases {
            let f = Float(bitPattern: UInt32(truncatingIfNeeded: c["bits"]!.intValue!))
            #expect(Int64(JavaMath.round(f)) == c["round"]!.intValue!, "round(\(f))")
            #expect(Int64(JavaMath.toInt(f)) == c["toInt"]!.intValue!, "(int) \(f)")
            #expect(JavaMath.toLong(f) == c["toLong"]!.intValue!, "(long) \(f)")
            let floor = Float(bitPattern: UInt32(truncatingIfNeeded: c["floor"]!.intValue!))
            #expect(f.rounded(.down).bitPattern == floor.bitPattern || f.isNaN, "floor(\(f))")
        }
    }

    @Test func doubleConversionsMatchJava() throws {
        let cases = try #require(try JavaOracle.load()["math"]?["double"]?.arrayValue)
        #expect(cases.count > 200)
        for c in cases {
            let d = Double(bitPattern: UInt64(bitPattern: c["bits"]!.intValue!))
            #expect(JavaMath.round(d) == c["round"]!.intValue!, "round(\(d))")
            #expect(Int64(JavaMath.toInt(d)) == c["toInt"]!.intValue!, "(int) \(d)")
            #expect(JavaMath.toLong(d) == c["toLong"]!.intValue!, "(long) \(d)")
        }
    }

    @Test func roundingDiffersFromSwiftForNegativeHalves() {
        #expect(JavaMath.round(Float(-2.5)) == -2)
        #expect(Float(-2.5).rounded() == -3)
        #expect(JavaMath.round(Float(0.49999997)) == 0)
    }
}

struct JavaStringTests {

    private static func strings() throws -> JSONValue {
        try #require(try JavaOracle.load()["strings"])
    }

    @Test func hashCodeMatchesJava() throws {
        for pair in try #require(try Self.strings()["hashCode"]?.arrayValue) {
            let s = pair.arrayValue![0].stringValue!
            #expect(Int64(JavaString.hashCode(s)) == pair.arrayValue![1].intValue!, "\"\(s)\"")
        }
    }

    @Test func compareMatchesJava() throws {
        let cases = try #require(try Self.strings()["compare"]?.arrayValue)
        #expect(cases.count == 15 * 15)
        for c in cases {
            let parts = c.arrayValue!
            let a = parts[0].stringValue!, b = parts[1].stringValue!
            #expect(Int64(JavaString.compare(a, b).signum()) == parts[2].intValue!,
                    "compare(\"\(a)\", \"\(b)\")")
        }
    }

    @Test func parseIntMatchesJava() throws {
        for c in try #require(try Self.strings()["parseInt"]?.arrayValue) {
            let parts = c.arrayValue!
            let s = parts[0].stringValue!
            let expected = parts[1].intValue.map { Int32($0) }
            #expect(JavaString.parseInt(s) == expected, "parseInt(\"\(s)\")")
        }
    }

    @Test func lastPartMatchesJava() throws {
        for c in try #require(try Self.strings()["lastPart"]?.arrayValue) {
            let parts = c.arrayValue!
            #expect(JavaString.lastPart(parts[0].stringValue!, ".") == parts[1].stringValue!)
        }
    }

    @Test func utf16Offsets() {
        #expect(JavaString.lastIndexOf("unit:am:7", ":") == 7)
        #expect(JavaString.lastIndexOf("abc", ":") == nil)
        #expect(JavaString.substring("unit:123", 5) == "123")
        #expect(JavaString.substring("unit:123", 0, 4) == "unit")
    }
}

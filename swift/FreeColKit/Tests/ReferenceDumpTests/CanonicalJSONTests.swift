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

struct JavaNumberFormatTests {

    // Expected strings were printed by Double.toString and
    // Float.toString on JDK 18.
    @Test(arguments: [
        (0.0, "0.0"), (-0.0, "-0.0"), (1.0, "1.0"), (-1.5, "-1.5"),
        (0.1, "0.1"), (0.001, "0.001"), (0.00099, "9.9E-4"),
        (1234567.0, "1234567.0"), (9999999.0, "9999999.0"),
        (1.0e7, "1.0E7"), (12345678.9, "1.23456789E7"), (1.0e-4, "1.0E-4"),
        (3.14159, "3.14159"), (100.0, "100.0"), (2.5e-10, "2.5E-10"),
        (1.7976931348623157e308, "1.7976931348623157E308"),
        (1.0e22, "1.0E22"), (123.456, "123.456"),
        (0.3333333333333333, "0.3333333333333333"),
    ] as [(Double, String)])
    func double(value: Double, java: String) {
        #expect(JavaNumberFormat.string(value) == java)
    }

    @Test(arguments: [
        (0.1, "0.1"), (0.99999994, "0.99999994"), (1.5, "1.5"),
        (-12.5, "-12.5"), (33.3, "33.3"), (1.0e7, "1.0E7"),
        (1.0e-4, "1.0E-4"), (3.4028235e38, "3.4028235E38"),
        (0.001, "0.001"), (1234567.0, "1234567.0"), (16777216, "1.6777216E7"),
    ] as [(Float, String)])
    func float(value: Float, java: String) {
        #expect(JavaNumberFormat.string(value) == java)
    }

    /// Java always prints at least two digits and picks the closest
    /// two-digit decimal, which only differs from the shortest digits
    /// for the smallest subnormals.  Float.MIN_VALUE is FreeCol's
    /// unknown modifier value, so it appears in modifier descriptions.
    @Test func smallestSubnormals() {
        #expect(JavaNumberFormat.string(Double.leastNonzeroMagnitude) == "4.9E-324")
        #expect(JavaNumberFormat.string(-Double.leastNonzeroMagnitude) == "-4.9E-324")
        #expect(JavaNumberFormat.string(Float.leastNonzeroMagnitude) == "1.4E-45")
        #expect(JavaNumberFormat.string(Float.leastNonzeroMagnitude * 2) == "2.8E-45")
        #expect(JavaNumberFormat.string(Float(0.1)) == "0.1")
        #expect(JavaNumberFormat.string(Float(1.0e7)) == "1.0E7")
    }
}

struct CanonicalJSONTests {

    @Test func layout() throws {
        let value = JSONValue.object([
            "b": .array([.integer(1), .decimal(2.0), .string("x\"y\n")]),
            "a": .object([:]),
            "c": .array([]),
            "d": .null,
            "e": .bool(true),
        ])
        let expected = """
        {
          "a": {},
          "b": [
            1,
            2.0,
            "x\\"y\\n"
          ],
          "c": [],
          "d": null,
          "e": true
        }

        """
        #expect(CanonicalJSON.document(value) == expected)
    }

    @Test func keysSortLikeJavaStrings() {
        // Java's String.compareTo orders by UTF-16 code units, so
        // uppercase sorts before lowercase and "a" before "a.b".
        let value = JSONValue.object(["b": .null, "B": .null, "a.b": .null, "a": .null])
        let keys = CanonicalJSON.document(value)
            .split(separator: "\n").dropFirst().dropLast()
            .map { $0.trimmingPrefix("  \"").prefix { $0 != "\"" } }
        #expect(keys == ["B", "a", "a.b", "b"])
    }

    @Test func parseKeepsIntegersAndDecimalsApart() throws {
        let value = try JSONValue.parse(Array("[2, 2.0, -3, 1.0E-4]".utf8))
        #expect(value == .array([.integer(2), .decimal(2.0), .integer(-3), .decimal(1.0e-4)]))
    }
}

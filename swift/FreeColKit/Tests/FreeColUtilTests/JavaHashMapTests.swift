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

struct JavaHashMapTests {

    /// Replays Java's puts and removes and checks the iteration order,
    /// for the map and for a copy (which Java presizes).
    @Test func iterationOrderMatchesJava() throws {
        let cases = try #require(try JavaOracle.load()["hashMaps"]?.arrayValue)
        #expect(cases.count == 60)
        for (n, c) in cases.enumerated() {
            let capacity = Int(c["initialCapacity"]!.intValue!)
            var m = capacity > 0
                ? JavaHashMap<String, Int>(initialCapacity: capacity, javaHash: JavaString.hashCode)
                : JavaHashMap<String, Int>(javaHash: JavaString.hashCode)
            for op in c["ops"]!.arrayValue! {
                let parts = op.arrayValue!
                let key = parts[1].stringValue!
                if parts[0] == .string("put") {
                    m.put(key, Int(parts[2].intValue!))
                } else {
                    m.removeValue(forKey: key)
                }
            }
            let keys = c["keys"]!.arrayValue!.map { $0.stringValue! }
            #expect(m.keys == keys, "case \(n)")
            #expect(m.count == keys.count)
            let copy = JavaHashMap(copying: m)
            #expect(copy.keys == c["copyKeys"]!.arrayValue!.map { $0.stringValue! }, "copy, case \(n)")
            for k in keys { #expect(copy[k] == m[k]) }
        }
    }

    @Test func basicOperations() {
        var m = JavaHashMap<String, Int>(javaHash: JavaString.hashCode)
        #expect(m.isEmpty && m["a"] == nil)
        #expect(m.put("a", 1) == nil)
        #expect(m.put("a", 2) == 1)
        m["b"] = 3
        #expect(m.count == 2 && m["a"] == 2)
        m["a"] = nil
        #expect(m.keys == ["b"])
        m.removeAll()
        #expect(m.isEmpty)
    }
}

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

import Foundation
import FreeColCore
import FreeColTestSupport
import FreeColXML
import Testing

/// The specifications written as Java writes them into saved games:
/// compared, as trees, with the XML Java wrote for the same rules
/// (spec-*.xml, from SpecDump).
@Suite(.serialized)
struct SpecificationWritingTests {

    static func javaTree(_ dump: String) throws -> JSONValue {
        let url = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("spec-\(dump).xml")
        return try XmlTree.parse(String(decoding: Data(contentsOf: url), as: UTF8.self))
    }

    static func swiftTree(_ spec: Specification) throws -> JSONValue {
        let xw = FreeColXMLWriter(scope: .toSave())
        spec.toXML(xw)
        return try XmlTree.parse(xw.xml)
    }

    static func check(_ spec: Specification, _ dump: String) throws {
        let diffs = XmlTree.differences(try swiftTree(spec), try javaTree(dump), "", limit: 40)
        if !diffs.isEmpty {
            Issue.record(Comment(rawValue: "spec-\(dump):\n" + diffs.joined(separator: "\n")))
        }
    }

    /// The rules loaded from data/rules write what Java writes for them.
    /// (Rules read back from that XML can write the European starting
    /// units in another order, in Java as here: the copied maps of
    /// types that extend others are smaller HashMaps than fresh ones.
    /// The saved games' specifications check that case; see
    /// XMLWritingTests.)
    @Test(arguments: [("classic", "model.difficulty.medium", "classic"),
                      ("freecol", "model.difficulty.medium", "freecol"),
                      ("freecol", "model.difficulty.veryHard", "freecol-veryHard")])
    func rawRulesWriteAsJava(rules: String, difficulty: String, dump: String) throws {
        try Self.check(try SpecificationTests.data.loadSpecification(rules, difficulty: difficulty), dump)
    }
}

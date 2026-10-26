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
import Testing
import FreeColTestSupport

/// Checks that Swift reads and rewrites every Java reference dump
/// byte for byte.  Later port steps compare their own dumps with these
/// files, so the writer has to reproduce Java's format exactly first.
///
/// Disabled when no dumps exist; make them with
/// swift/scripts/make-reference-dumps.sh.
@Suite(.enabled(if: ReferenceDumps.available,
                "No reference dumps; run swift/scripts/make-reference-dumps.sh"))
struct ReferenceDumpRoundTripTests {

    @Test(arguments: ReferenceDumps.jsonFiles())
    func roundTrip(file: URL) throws {
        let original = try Data(contentsOf: file)
        let value = try JSONValue.parse(original)
        let rewritten = Data(CanonicalJSON.document(value).utf8)
        #expect(rewritten == original,
                "\(file.lastPathComponent) differs after a Swift round trip")
    }

    @Test func specDumpsHaveExpectedShape() throws {
        let specs = ReferenceDumps.jsonFiles(in: "spec")
        try #require(!specs.isEmpty)
        for file in specs {
            let doc = try ReferenceDumps.load(file)
            #expect(doc["kind"] == .string("specification"))
            #expect(doc["format"] == .integer(1))
            #expect(doc["xml"]?["tag"] == .string("freecol-specification"))
            let unitTypes = try #require(doc["derived"]?["unitTypes"]?.objectValue)
            #expect(unitTypes["model.unit.freeColonist"] != nil)
        }
    }
}

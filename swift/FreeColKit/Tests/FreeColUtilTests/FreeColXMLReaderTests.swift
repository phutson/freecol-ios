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
import FreeColXML
import FreeColTestSupport

struct JavaParsingTests {

    @Test func decodeMatchesJava() throws {
        let cases = try #require(try JavaOracle.load()["strings"]?["decode"]?.arrayValue)
        #expect(cases.count > 25)
        for c in cases {
            let p = c.arrayValue!
            let s = p[0].stringValue!
            #expect(JavaString.decodeIntOrNil(s).map(Int64.init) == p[1].intValue, "Integer.decode(\"\(s)\")")
            #expect(JavaString.decodeLongOrNil(s) == p[2].intValue, "Long.decode(\"\(s)\")")
        }
    }

    @Test func parseFloatMatchesJava() throws {
        let cases = try #require(try JavaOracle.load()["strings"]?["parseFloat"]?.arrayValue)
        #expect(cases.count == 30)
        for c in cases {
            let p = c.arrayValue!
            let s = p[0].stringValue!
            let expected = p[1].intValue.map { UInt32(truncatingIfNeeded: $0) }
            let actual = JavaString.parseFloat(s).map { $0.isNaN ? 0x7FC0_0000 : $0.bitPattern }
            #expect(actual == expected, "Float.parseFloat(\"\(s)\")")
        }
    }

    @Test func parseBoolean() {
        #expect(JavaString.parseBoolean("true") && JavaString.parseBoolean("TRUE"))
        #expect(!JavaString.parseBoolean("yes") && !JavaString.parseBoolean(nil))
    }
}

struct FreeColXMLReaderTests {

    enum Colour: JavaEnum {
        case red, darkBlue
        var javaName: String { self == .red ? "RED" : "DARK_BLUE" }
    }

    static let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- comment -->
        <root id="r" n="010" f="1.5" b="TRUE" bad="x" c="dark_blue">
          text is skipped
          <child id="c1"/>
          <child id="c2"><grandchild/></child>
          <other/>
        </root>
        """

    @Test func stepsThroughTagsLikeStAX() throws {
        let xr = try FreeColXMLReader(string: Self.document)
        #expect(try xr.nextTag() == .start)
        #expect(xr.localName == "root")
        #expect(xr.readId() == "r")
        #expect(xr.attribute("n", default: 0) == 8) // Integer.decode reads octal.
        #expect(xr.attribute("f", default: Float(0)) == 1.5)
        #expect(xr.attribute("b", default: false))
        #expect(xr.attribute("missing", default: 42) == 42)
        #expect(xr.attribute("bad", default: 3) == 3)
        #expect(xr.warnings == ["bad is not an integer: x"])
        #expect(xr.attribute("c", Colour.self, default: nil) == .darkBlue)

        var ids: [String] = []
        while try xr.moreTags() {
            if xr.atTag("child") {
                ids.append(xr.readId()!)
                if ids.count == 1 { try xr.closeTag("child") } else { try xr.swallowTag("child") }
            } else {
                try xr.closeTag("other")
            }
        }
        try xr.expectTag("root")
        #expect(ids == ["c1", "c2"])
    }

    @Test func closeTagRejectsChildren() throws {
        let xr = try FreeColXMLReader(string: "<a><b/></a>")
        try xr.nextTag()
        #expect(throws: FreeColXMLError.self) { try xr.closeTag("a") }
    }

    @Test func oldIdentifiersAreUpgraded() throws {
        let xr = try FreeColXMLReader(string: #"<t id="tileimprovement:12"/>"#)
        try xr.nextTag()
        #expect(xr.readId() == "tileImprovement:12")
    }

    @Test func malformedXMLThrows() {
        #expect(throws: FreeColXMLError.self) { try FreeColXMLReader(string: "<a><b></a>") }
    }
}

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

/// SerializationTest.java.  Java writes games, templates and
/// specifications as XML and checks them against the XML Schemas in
/// schema/.  Writing XML is not ported yet, and Foundation has no XML
/// Schema validator on iOS, so these wait.  Reading the standard maps
/// is covered by MapTests.
struct SerializationTest {

    @Test(.disabled("Needs the server (ServerTestHelper.newTurn) and writing XML"))
    func validation() {}

    @Test(.disabled("Needs an XML Schema validator"))
    func standardMaps() {}

    @Test(.disabled("Writing XML is not ported yet"))
    func stringTemplate() {}

    @Test(.disabled("Writing XML is not ported yet"))
    func specification() {}

    @Test(.disabled("Writing XML is not ported yet"))
    func difficulty() {}

    @Test(.disabled("Writing XML is not ported yet"))
    func generatedLists() {}
}

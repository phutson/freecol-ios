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

/// Streaming XML reading and writing.
///
/// Ported from:
///   - `net.sf.freecol.common.io (FreeColXMLReader, FreeColXMLWriter)`
///
/// So far: FreeColXMLReader, a pull-style reader with Java's cursor
/// API over a document parsed by Foundation's XMLParser.  The writer
/// follows when saved games are ported.
public enum FreeColXML {
    /// The Java packages this module is ported from.
    public static let javaPackages: [String] = [
        "net.sf.freecol.common.io",
    ]
}

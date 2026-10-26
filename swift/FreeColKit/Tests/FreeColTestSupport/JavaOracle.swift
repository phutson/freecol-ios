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

/// What Java itself computes for the library behavior the game depends
/// on, written by net.sf.freecol.tools.dump.JavaCompatOracle into
/// Tests/JavaOracle/java-compat.json.
///
/// Unlike the reference dumps this file is small and kept with the
/// tests, so these tests always run.  Regenerate it with
/// swift/scripts/make-reference-dumps.sh.
public enum JavaOracle {

    /// The oracle file.
    public static let url: URL = {
        // This file is Tests/FreeColTestSupport/JavaOracle.swift.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("JavaOracle/java-compat.json")
    }()

    /// Load and parse the oracle file.
    public static func load() throws -> JSONValue {
        try JSONValue.parse(try Data(contentsOf: url))
    }
}

extension JSONValue {

    /// The integer value, or nil if this is not an integer.
    public var intValue: Int64? {
        if case .integer(let i) = self { return i }
        return nil
    }

    /// Whether this is null.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

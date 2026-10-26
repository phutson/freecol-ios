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

/// A Swift enum standing in for a Java enum.
///
/// Java writes enum values by constant name ("ADDITIVE") and reads them
/// back case-insensitively (Enum.valueOf after upper-casing); toString
/// gives the name too.  The cases must be declared in Java's order,
/// since Java compares enums by ordinal.
public protocol JavaEnum: CaseIterable, Hashable, Sendable {
    /// The Java constant name.
    var javaName: String { get }
}

extension JavaEnum {

    /// The case with a Java constant name, matched as Java's XML reader
    /// does (upper-cased in the US locale).
    public init?(javaName: String) {
        let upper = javaName.uppercased()
        guard let match = Self.allCases.first(where: { $0.javaName == upper }) else { return nil }
        self = match
    }

    /// Java's ordinal: the position in declaration order.
    public var ordinal: Int {
        Self.allCases.firstIndex(of: self).map { Self.allCases.distance(from: Self.allCases.startIndex, to: $0) } ?? 0
    }
}

extension String {
    /// nil if empty, otherwise the string.
    public var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

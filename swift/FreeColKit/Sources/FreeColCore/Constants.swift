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

/// Shared constants (common/model/Constants).
public enum Constants {
    /// "Unlimited" (Java's Integer.MAX_VALUE).  Kept at the Java int
    /// value, since it is written to and read from saved games.
    public static let infinity = Int(Int32.max)

    /// "Not set" (Java's Integer.MIN_VALUE).
    public static let undefined = Int(Int32.min)
}

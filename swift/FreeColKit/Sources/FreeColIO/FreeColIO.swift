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

/// Rules files, mods and saved games.
///
/// Ported from:
///   - `net.sf.freecol.common.io`
///
/// Saved games (.fsg) are zip archives holding savegame.xml.
///
/// FreeColDataDirectory finds rule sets, mods and compatibility files
/// and loads specifications from them; FreeColSavegameFile reads saved
/// games; FreeColDataFile reads a data directory's files for the
/// resource mappings (FreeColResources).
public enum FreeColIO {
    /// The Java packages this module is ported from.
    public static let javaPackages: [String] = [
        "net.sf.freecol.common.io",
    ]
}

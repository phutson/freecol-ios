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

/// The images, sounds, fonts and other resources the data files map
/// keys to, layered from data/base, the total conversion, mods and the
/// saved game.
///
/// Ported from:
///   - `net.sf.freecol.common.resources`
///   - `net.sf.freecol.common.io.sza`
///
/// Resources describe and parse; decoding images and sounds, scaling
/// and drawing are left to the user interface (Phase 5).
public enum FreeColResources {
    /// The Java packages this module is ported from.
    public static let javaPackages: [String] = [
        "net.sf.freecol.common.resources",
        "net.sf.freecol.common.io.sza",
    ]
}

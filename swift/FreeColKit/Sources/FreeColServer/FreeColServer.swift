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

/// The game engine: what Java's server does, without the network.
///
/// Java's server sends each player messages built from a change set;
/// here a change set gives each player the list of what it is told,
/// which the user interface observes.  Each of those can still be
/// written as Java's message XML, which is how it is checked.
///
/// Ported from:
///   - `net.sf.freecol.common.networking.ChangeSet` and the messages
///     it makes
///   - `net.sf.freecol.server.model` and `net.sf.freecol.server.control`
///     (Phase 3, in progress)
public enum FreeColServer {
    /// The Java packages this module is ported from.
    public static let javaPackages: [String] = [
        "net.sf.freecol.common.networking",
        "net.sf.freecol.server.model",
        "net.sf.freecol.server.control",
    ]
}

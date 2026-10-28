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

import FreeColResources

/// The map's images from the resource manager: an image for a key
/// exists if the manager has one, and its variations are chosen as
/// Java's ImageResource chooses them.
public struct ResourceMapImages: MapImages {
    public let manager: ResourceManager

    public init(_ manager: ResourceManager) {
        self.manager = manager
    }

    public func hasImage(_ key: String) -> Bool {
        manager.imageResource(key) != nil
    }

    public func variation(_ key: String, seed: Int32) -> Int {
        manager.imageResource(key)?.variationNumber(seed: seed) ?? 0
    }
}

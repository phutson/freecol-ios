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

/// An object that belongs to a specification rather than a game, such
/// as a unit type or a modifier (common/model/FreeColSpecObject).
///
/// The specification is held strongly: rule objects are owned by the
/// specification's lists, and a specification never points back at
/// them through this property, so there is no cycle.
open class FreeColSpecObject: FreeColObject {

    private var storedSpecification: Specification?

    public init(specification: Specification?) {
        storedSpecification = specification
        super.init()
    }

    open override var specification: Specification? {
        storedSpecification
    }

    open override func setSpecification(_ specification: Specification?) {
        storedSpecification = specification
    }
}

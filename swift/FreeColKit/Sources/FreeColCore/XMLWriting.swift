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

import FreeColXML

/// The parts of FreeColXMLWriter that know model classes.
extension FreeColXMLWriter {

    /// The client player of a client scope.
    public var clientPlayerObject: Player? {
        clientPlayer as? Player
    }

    /// An object by identifier: nothing for nil, or an object without
    /// one (Java's writeAttribute(String, FreeColObject)).
    public func writeAttribute(_ name: String, _ value: FreeColObject?) {
        writeAttribute(name, id: value?.id)
    }

    /// A location by identifier (writeLocationAttribute).
    public func writeLocationAttribute(_ name: String, _ value: (any Location)?) {
        writeAttribute(name, id: value?.id)
    }

    /// A list of objects as Java's writeToListElement.
    public func writeToListElement(_ tag: String, _ members: [FreeColObject]) {
        writeToListElement(tag, members.map(\.id))
    }

    /// An element with just an identifier attribute.
    public func writeIdElement(_ tag: String, _ id: String?) {
        writeStartElement(tag)
        writeAttribute(FreeColObject.idTag, id: id)
        writeEndElement()
    }
}

/// Sorted by identifier, keeping the order of equal ones, as Java's
/// sort of FreeCol objects.
func sortedById<T: FreeColObject>(_ objects: some Sequence<T>) -> [T] {
    objects.stableSorted { FreeColObject.compareIds($0, $1) < 0 }
}

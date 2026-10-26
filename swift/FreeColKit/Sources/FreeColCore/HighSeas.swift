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

import FreeColUtil
import FreeColXML

/// The high seas: where a player's ships sail between Europe and the
/// map (common/model/HighSeas).  Only naval units can be here.
///
/// The player holds its high seas, and the high seas hold the ships on
/// them.  The destinations (Europe, the map) are weak references.
///
/// Not yet ported: getLinkTarget and copyIn.
public final class HighSeas: UnitLocation, GameObjectReadable {

    public static let tag = "highSeas"

    private final class WeakLocation {
        weak var location: (any Location)?
        init(_ location: any Location) { self.location = location }
    }

    private var destinationList: [WeakLocation] = []

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// New high seas with a fresh identifier.
    public override init(game: Game) {
        super.init(game: game)
    }

    public override var xmlTagName: String {
        HighSeas.tag
    }

    /// Where ships can sail to from here.
    public var destinations: [any Location] {
        destinationList.compactMap(\.location)
    }

    /// The destination identifiers, joined by commas.
    public var destinationsDescription: String {
        destinations.map { $0.id ?? "null" }.joined(separator: ",")
    }

    public func addDestination(_ destination: (any Location)?) {
        guard let destination else { return } // Java logs a warning
        if !destinations.contains(where: { $0 === destination }) {
            destinationList.append(WeakLocation(destination))
        }
    }

    public func removeDestination(_ destination: any Location) {
        destinationList.removeAll { $0.location === destination }
    }

    // MARK: Location

    public override func up() -> any Location {
        self
    }

    public override var rank: Int {
        LocationRank.highSeas
    }

    public override var shortDescription: String {
        "HighSeas"
    }

    public override func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        ((locatable as? Unit)?.isNaval ?? false) ? .none : .wrongType
    }

    // MARK: Reading XML

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for loc in destinations {
            xw.writeStartElement("destination")
            xw.writeLocationAttribute(FreeColObject.idTag, loc)
            xw.writeEndElement()
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        destinationList = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "destination" {
            addDestination(try xr.getLocationAttribute(game!, FreeColObject.idTag, make: true)
                as? any Location)
            try xr.closeTag("destination")
        } else {
            try super.readChild(xr)
        }
    }

    public override var description: String {
        id ?? "null"
    }
}

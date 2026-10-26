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

/// Something an object can or cannot do, such as found a colony
/// (common/model/Ability).  The ability id constants are in
/// AbilityIds.swift.
public final class Ability: Feature {

    public static let tag = "ability"

    /// Whether the ability is present (true) or explicitly denied.
    public var value: Bool

    /// Create an ability.  Its specification is the source's, as in Java.
    public init(_ id: String?, source: FreeColSpecObjectType? = nil, value: Bool = true) {
        self.value = value
        super.init(specification: source?.specification)
        self.id = id
        self.source = source
    }

    /// A copy of an ability (Java's copy constructor).
    public convenience init(copying other: Ability) {
        self.init(other.id, value: other.value)
        copyFeature(from: other)
    }

    public override var xmlTagName: String {
        Ability.tag
    }

    /// Read an ability from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader, specification: Specification?) throws {
        self.init(nil)
        setSpecification(specification)
        try readFromXML(xr)
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        value = xr.attribute("value", default: true)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", value)
    }

    // MARK: FreeColObject

    public override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? Ability else { return false }
        return value == other.value && super.isEqual(to: other)
    }

    public override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(value)
    }

    /// Java's toString, which the reference dumps record.
    public override var description: String {
        var s = "[ \(id ?? "null")"
        if let source { s += " (\(source.id ?? "null"))" }
        return s + " = \(value) ]"
    }
}

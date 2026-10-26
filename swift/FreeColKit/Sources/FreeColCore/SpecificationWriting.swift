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

extension Specification {

    /// The option groups written, in order (Java's coreOptionGroups).
    static let coreOptionGroups = ["gameOptions", "mapGeneratorOptions", "difficultyLevels"]

    /// Write the specification, its sections in the order of
    /// specification.xml (Specification.toXML).
    public func toXML(_ xw: FreeColXMLWriter) {
        xw.writeStartElement(Specification.tag)
        xw.writeAttribute(FreeColObject.idTag, id: id)
        xw.writeAttribute("difficulty-level", id: difficultyLevel)
        xw.writeAttribute("version", id: version)
        writeSection(xw, "abilities", gameAbilities)
        writeSection(xw, "modifiers", specialModifiers)
        writeSection(xw, "events", events)
        writeSection(xw, "disasters", disasters)
        writeSection(xw, "goods-types", goodsTypeList)
        writeSection(xw, "resource-types", resourceTypeList)
        writeSection(xw, "tile-types", tileTypeList)
        writeSection(xw, "roles", rolesList)
        writeSection(xw, "tile-improvement-types", tileImprovementTypeList)
        writeSection(xw, "unit-change-types", unitChangeTypeList)
        writeSection(xw, "unit-types", unitTypeList)
        writeSection(xw, "building-types", buildingTypeList)
        writeSection(xw, "founding-fathers", foundingFathers)
        writeSection(xw, "european-nation-types", europeanNationTypes)
        writeSection(xw, "european-nation-types", refNationTypes)
        writeSection(xw, "indian-nation-types", indianNationTypes)
        writeSection(xw, "nations", nations)
        xw.writeStartElement("options")
        for id in Specification.coreOptionGroups {
            allOptionGroups[id]?.toXML(xw)
        }
        xw.writeEndElement()
        xw.writeEndElement()
    }

    private func writeSection(_ xw: FreeColXMLWriter, _ section: String, _ items: [FreeColObject]) {
        xw.writeStartElement(section)
        for item in items { item.toXML(xw) }
        xw.writeEndElement()
    }
}

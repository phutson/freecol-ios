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

/// Which nations a game offers and how national advantages are
/// chosen (common/model/NationOptions).
///
/// Not yet ported: copyIn.
public final class NationOptions: FreeColSpecObject {

    public static let tag = "nationOptions"

    /// How national advantages are given (NationOptions.Advantages).
    public enum Advantages: JavaEnum, CustomStringConvertible {
        case none, fixed, selectable

        public var javaName: String {
            switch self {
            case .none: "NONE"
            case .fixed: "FIXED"
            case .selectable: "SELECTABLE"
            }
        }

        public var description: String {
            javaName
        }
    }

    /// Who may play a nation (NationOptions.NationState).
    public enum NationState: JavaEnum, CustomStringConvertible {
        case available, aiOnly, notAvailable

        public var javaName: String {
            switch self {
            case .available: "AVAILABLE"
            case .aiOnly: "AI_ONLY"
            case .notAvailable: "NOT_AVAILABLE"
            }
        }

        public var description: String {
            javaName
        }
    }

    /// FreeCol's command line defaults (FreeCol.getAdvantages and
    /// getEuropeanCount).
    public static let defaultAdvantages = Advantages.selectable
    public static let defaultEuropeanCount = 4

    public private(set) var nationalAdvantages = NationOptions.defaultAdvantages
    /// The state of each nation, in Java's HashMap order.
    private var nations = JavaHashMap<Nation, NationState>(javaHash: { $0.javaHashCode })

    /// The default options: the first selectable European nations
    /// available, the rest AI only.
    public override init(specification: Specification?) {
        super.init(specification: specification)
        guard let specification else { return }
        var counter = 0
        for nation in specification.nations where !nation.isUnknownEnemy && !(nation.type?.isREF ?? false) {
            if (nation.type?.isEuropean ?? false) && nation.isSelectable {
                if counter < NationOptions.defaultEuropeanCount {
                    _ = nations.put(nation, .available)
                    counter += 1
                } else {
                    _ = nations.put(nation, .notAvailable)
                }
            } else {
                _ = nations.put(nation, .aiOnly)
            }
        }
    }

    /// Read the options from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader, specification: Specification?) throws {
        self.init(specification: specification)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        NationOptions.tag
    }

    /// The nations and their states, in Java's order.
    public var nationStates: [(nation: Nation, state: NationState)] {
        nations.entries.map { ($0.key, $0.value) }
    }

    public func nationState(_ nation: Nation) -> NationState? {
        nations[nation]
    }

    public func setNationState(_ nation: Nation, _ state: NationState) {
        _ = nations.put(nation, state)
    }

    // MARK: Writing XML

    /// The nation options write no identifier.
    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        xw.writeAttribute("nationalAdvantages", nationalAdvantages)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for nation in sortedById(nations.keys) {
            xw.writeStartElement("nationOption")
            xw.writeAttribute(FreeColObject.idTag, nation)
            xw.writeAttribute("state", nations[nation]!)
            xw.writeEndElement()
        }
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        // The nation options do not read the FreeColObject attributes.
        nationalAdvantages = xr.attribute("nationalAdvantages", Advantages.self, default: .selectable)
            ?? .selectable
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        nations.removeAll()
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "nationOption":
            readNationState(xr)
            try xr.closeTag("nationOption")
        case "Nations":
            // @compat 0.11.3
            while try xr.moreTags() {
                guard xr.localName == "Nation" else {
                    throw FreeColXMLError("Bogus Nation tag: \(xr.localName)")
                }
                readNationState(xr)
                try xr.closeTag("Nation")
            }
        default:
            try super.readChild(xr)
        }
    }

    private func readNationState(_ xr: FreeColXMLReader) {
        if let nation = try? specification.flatMap({ try xr.getType($0, FreeColObject.idTag, Nation.self) }),
           let state = xr.attribute("state", NationState.self, default: nil) {
            _ = nations.put(nation, state)
        }
    }
}

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

/// A named group of tiles, such as a nation's starting area drawn in
/// the map editor (common/model/Area).
///
/// The game holds its areas, and an area its tile references (the map
/// owns the tiles).  Not yet ported: copyIn.
public final class Area: FreeColGameObject, GameObjectReadable {

    public static let tag = "area"

    /// The identifier prefix of a nation's starting area.
    public static let prefixPlayerStartingPosition = "model.area.starting."

    public private(set) var nameKey: String?
    public private(set) var name: String?
    public private(set) var tiles: [Tile] = []

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    public init(game: Game, id: String, nameKey: String?) {
        self.nameKey = nameKey
        super.init(game: game, id: id)
    }

    public override var xmlTagName: String {
        Area.tag
    }

    public func addTile(_ tile: Tile) {
        tiles.append(tile)
    }

    public func containsTile(_ tile: Tile) -> Bool {
        tiles.contains { $0 === tile }
    }

    public func removeTile(_ tile: Tile) {
        if let i = tiles.firstIndex(where: { $0 === tile }) { tiles.remove(at: i) }
    }

    /// Rename an area; areas with a fixed name key can not be renamed.
    public func setName(_ name: String?) {
        precondition(nameKey == nil, "Cannot change the name of areas with a fixed nameKey.")
        self.name = name
    }

    public var isEmpty: Bool {
        tiles.isEmpty
    }

    /// The colour to draw the area: a starting area's nation colour, or
    /// one made from the identifier's hash.
    public var rgb: Int32? {
        let id = self.id ?? ""
        if JavaString.startsWith(id, Area.prefixPlayerStartingPosition) {
            let nationId = String(id.dropFirst(Area.prefixPlayerStartingPosition.count))
            if let nation = game?.specification?.getAlreadyInitializedType(nationId, Nation.self) {
                return nation.rgb
            }
        }
        let hashCode = JavaString.hashCode(id)
        let r = hashCode % 256, g = (hashCode / 256) % 256, b = (hashCode / (256 * 256)) % 256
        // Java's java.awt.Color range check.
        precondition(r >= 0 && g >= 0 && b >= 0, "Color parameter outside of expected range: \(r),\(g),\(b)")
        return Nation.opaque | (r << 16) | (g << 8) | b
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        nameKey = xr.attribute("nameKey", default: nil as String?)
        name = xr.attribute("name", default: nil as String?)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("nameKey", id: nameKey)
        xw.writeAttribute("name", id: name)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for tile in tiles { xw.writeIdElement("tileReference", tile.id) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        tiles = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "tileReference" {
            if let tile = try xr.makeFreeColObject(game!, FreeColObject.idTag, Tile.self, required: true) {
                tiles.append(tile)
            }
            try xr.closeTag("tileReference")
        } else {
            try super.readChild(xr)
        }
    }

    public override var description: String {
        "[\(id ?? "null")]"
    }
}

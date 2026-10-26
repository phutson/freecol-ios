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

/// A named part of the map, such as an ocean or a mountain range
/// (common/model/Region).
///
/// The map holds its regions.  A region holds its children; the parent
/// and the discovering player are weak references.
///
/// The label is in Labels.swift.
public final class Region: FreeColGameObject, GameObjectReadable {

    public static let tag = "region"

    /// The keys of the regions every map has.
    public static let predefinedRegionKeys = [
        "model.region.arctic", "model.region.antarctic",
        "model.region.northWest", "model.region.north", "model.region.northEast",
        "model.region.west", "model.region.center", "model.region.east",
        "model.region.southWest", "model.region.south", "model.region.southEast",
        "model.region.atlantic", "model.region.northAtlantic", "model.region.southAtlantic",
        "model.region.pacific", "model.region.northPacific", "model.region.southPacific",
    ]

    public static let pacificKey = "model.region.pacific"

    /// The kinds of region.  Land kinds can be claimed.
    public enum RegionType: JavaEnum, CustomStringConvertible, Named {
        case ocean, coast, lake, river, land, mountain, desert

        public var javaName: String {
            switch self {
            case .ocean: "OCEAN"
            case .coast: "COAST"
            case .lake: "LAKE"
            case .river: "RIVER"
            case .land: "LAND"
            case .mountain: "MOUNTAIN"
            case .desert: "DESERT"
            }
        }

        public var claimable: Bool {
            switch self {
            case .ocean, .coast, .lake: false
            case .river, .land, .mountain, .desert: true
            }
        }

        public var key: String {
            "regionType." + javaName.lowercased()
        }

        public var unknownKey: String {
            "model." + key + ".unknown"
        }

        public var nameKey: String {
            Messages.nameKey("model." + key)
        }

        public var description: String {
            javaName
        }
    }

    /// The name given by the player who discovered it.
    public var name: String?
    /// The message key of a predefined region's name.
    public private(set) var key: String?
    public private(set) var type: RegionType?
    public weak var parent: Region?
    public var children: [Region]?
    public var claimable = false
    public var discoverable = false
    public var discoveredIn: Turn?
    public weak var discoveredBy: Player?
    /// The identifier of the unit discovering this region.
    public private(set) var discoverer: String?
    public var scoreValue = 0

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    /// A new region with a fresh identifier.
    public override init(game: Game) {
        super.init(game: game)
    }

    /// A new region, as the map generator makes them
    /// (ServerRegion(Game, String, RegionType, Region)): a predefined
    /// one has a key, and a parent takes it as a child.
    public init(game: Game, key: String?, type: RegionType, parent: Region?) {
        super.init(game: game)
        self.key = key
        name = nil
        self.type = type
        self.parent = parent
        parent?.addChild(self)
    }

    /// A new region of a type, which can be discovered
    /// (ServerRegion(Game, RegionType)).
    public convenience init(game: Game, type: RegionType) {
        self.init(game: game, key: nil, type: type, parent: nil)
        claimable = type.claimable
        discoverable = true
    }

    // MARK: The server's region (ServerRegion)

    /// The number of tiles added, or a total for a region with children.
    /// Not saved.
    public var size = 0
    /// The bounds of the tiles added.  Not saved.
    public var bounds = JavaRectangle()

    /// Whether this is one of the predefined land regions.
    public var isGeographic: Bool {
        key != nil && type == .land
    }

    public var center: (x: Int, y: Int) {
        (Int(bounds.x + bounds.width / 2), Int(bounds.y + bounds.height / 2))
    }

    public func containsCenter(_ other: Region) -> Bool {
        let c = other.center
        return bounds.contains(c.x, c.y)
    }

    /// Put a tile in this region (ServerRegion.addTile).
    public func addTile(_ tile: Tile) {
        tile.region = self
        size += 1
        if bounds.x == 0 && bounds.width == 0 || bounds.y == 0 && bounds.height == 0 {
            bounds.setBounds(Int32(tile.x), Int32(tile.y), 0, 0)
        } else {
            bounds.add(tile.x, tile.y)
        }
    }

    public override var xmlTagName: String {
        Region.tag
    }

    /// Whether this region has a name or key.
    public var hasName: Bool {
        name != nil || key != nil
    }

    /// Whether this is the Pacific or part of it.
    public var isPacific: Bool {
        key == Region.pacificKey || (parent?.isPacific ?? false)
    }

    public func addChild(_ child: Region) {
        if children == nil { children = [] }
        children!.append(child)
    }

    public var isLeaf: Bool {
        children?.isEmpty ?? true
    }

    /// Whether a unit moving in discovers this region, reserving it for
    /// that unit (checkDiscover).
    public func checkDiscover(_ unit: Unit) -> Bool {
        guard discoverable else { return false }
        if discoverer == nil {
            discoverer = unit.id
            return true
        }
        return discoverer == unit.id
    }

    /// The unit that checked first discovers this region and its
    /// discoverable children (discover).
    ///
    /// - Returns: The regions discovered.
    public func discover(_ player: Player, _ unit: Unit?, _ turn: Turn) -> [Region] {
        guard let unit, let discoverer, discoverer == unit.id else { return [] }
        discoveredBy = player
        discoveredIn = turn
        discoverable = false
        let discovered = (children ?? []).filter(\.discoverable)
        for r in discovered {
            r.discoveredBy = player
            r.discoverer = unit.id
            r.discoveredIn = turn
            r.discoverable = false
        }
        return [self] + discovered
    }

    /// This region if it can be discovered, or the nearest such parent.
    public var discoverableRegion: Region? {
        discoverable ? self : parent?.discoverableRegion
    }

    // @compat 0.11.3
    private func fixRegionKey(_ key: String?) -> String? {
        guard let key else { return nil }
        for r in Region.predefinedRegionKeys {
            if key == r { return r }
            if key == r + ".name" { return JavaString.lastPart(key, ".") }
        }
        return nil
    }
    // end @compat 0.11.3

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let game = game!
        name = xr.attribute("name", default: nil as String?)
        // @compat 0.11.3
        if xr.hasAttribute("nameKey") {
            key = fixRegionKey(xr.attribute("nameKey", default: nil as String?))
        } else {
            key = xr.attribute("key", default: nil as String?)
        }
        type = xr.attribute("type", RegionType.self, default: nil)
        claimable = xr.attribute("claimable", default: false)
        discoverable = xr.attribute("discoverable", default: false)
        scoreValue = xr.attribute("scoreValue", default: 0)
        let turn = xr.attribute("discoveredIn", default: Constants.undefined)
        discoveredIn = turn == Constants.undefined ? nil : Turn(turn)
        discoveredBy = try xr.findFreeColGameObject(game, "discoveredBy", Player.self, required: false)
        parent = try xr.makeFreeColObject(game, "parent", Region.self, required: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("name", id: name)
        xw.writeAttribute("key", id: key)
        if let type { xw.writeAttribute("type", type) }
        xw.writeAttribute("claimable", claimable)
        xw.writeAttribute("discoverable", discoverable)
        xw.writeAttribute("parent", parent)
        if let discoveredIn { xw.writeAttribute("discoveredIn", discoveredIn.number) }
        xw.writeAttribute("discoveredBy", discoveredBy)
        if scoreValue > 0 { xw.writeAttribute("scoreValue", scoreValue) }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for child in children ?? [] { xw.writeIdElement("child", child.id) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        children = nil
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "child" {
            if let child = try xr.makeFreeColObject(game!, FreeColObject.idTag, Region.self,
                                                    required: true) {
                addChild(child)
            }
            try xr.closeTag("child")
        } else {
            try super.readChild(xr)
        }
    }

    public override var description: String {
        var s = "[\(id ?? "null") \(key ?? name ?? "<unnamed>") \(type.map { "\($0)" } ?? "null")"
        s += discoverable ? "!" : "discoverer=\(discoverer ?? "null")"
        return s + "]"
    }
}

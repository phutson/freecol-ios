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

import FreeColEngine

/// What the map's images are, found by key (the resource manager), and
/// which variation of one a tile uses.
public protocol MapImages {
    /// Whether there is an image for a key.
    func hasImage(_ key: String) -> Bool
    /// The variation of a key's image picked by a seed, 0 if it has
    /// only one (ImageResource.getVariation).
    func variation(_ key: String, seed: Int32) -> Int
}

/// One image: its key, and which variation.
public struct MapImage: Hashable, Sendable {
    public let key: String
    public let variation: Int

    public init(_ key: String, variation: Int = 0) {
        self.key = key
        self.variation = variation
    }
}

/// Where an image goes on its tile, as Java's TileViewer and MapViewer
/// place them, in tile pixels at scale 1 (a tile is 128 by 64).
public enum MapPlacement: Sendable, Equatable {
    /// At the tile's corner (base terrain, borders, rivers, plowing).
    case corner
    /// Centred on the tile (resources, rumours, clouds).
    case centered
    /// Centred across, and, if taller than the tile, not reaching below
    /// it (settlements; displayLargeCenteredImage).
    case largeCentered
    /// Across the tile, its foot on the tile's foot (hills, mountains,
    /// forests).
    case bottom
    /// Centred, raised a little (units; calculateUnitImagePositionInTile).
    case unit

    /// The top left corner of an image of a size on a tile, from the
    /// tile's top left.
    public func origin(width: Int, height: Int) -> (x: Int, y: Int) {
        let tw = MapScene.tileWidth, th = MapScene.tileHeight
        switch self {
        case .corner: return (0, 0)
        case .centered: return ((tw - width) / 2, (th - height) / 2)
        case .largeCentered:
            var y = th - height
            if y > 0 { y /= 2 }
            return ((tw - width) / 2, y)
        case .bottom: return (0, th - height)
        case .unit: return ((tw - width) / 2, (th - height) / 2 - MapScene.unitOffset)
        }
    }
}

/// One thing to draw on a tile.
public enum MapDrawing: Sendable, Equatable {
    /// An image; dimmed for fog of war (Java's 0.8 rescale), or grey
    /// (a sentry, or a unit out of sight).
    case image(MapImage, MapPlacement, dimmed: Bool, grey: Bool)
    /// The fog of war over a tile seen before but not now (black at a
    /// fifth).
    case fog
}

/// Something to draw, on which tile.
public struct MapDraw: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let drawing: MapDrawing
}

/// What to draw for a player's view of the map, and in what order, as
/// Java's MapViewer (displayNonAnimationImages) and TileViewer draw it,
/// pass by pass over the tiles.  Images are named by key, so drawing
/// them is left to the screen.
///
/// Not yet: the transitions between terrain types, beaches, river
/// mouths and animated water, forest corners, roads, borders, the
/// chips on settlements and units, and labels (Phase 5 step 2).  Water
/// is drawn with its plain image.
public enum MapScene {

    public static let tileWidth = 128
    public static let tileHeight = 64
    /// How far units are raised on their tiles (TileBounds.UNIT_OFFSET).
    public static let unitOffset = 20

    /// The z-indexes Java layers tile items by (Tile.OVERLAY_ZINDEX and
    /// FOREST_ZINDEX).
    static let overlayZIndex = 100
    static let forestZIndex = 200

    /// The top left of a tile on the whole map, in pixels at scale 1:
    /// odd rows are half a tile across (paintEachTile).
    public static func origin(_ x: Int, _ y: Int) -> (x: Int, y: Int) {
        (x * tileWidth + (y & 1) * (tileWidth / 2), y * (tileHeight / 2))
    }

    /// The whole map's size in pixels at scale 1.
    public static func size(_ map: MapSnapshot) -> (width: Int, height: Int) {
        (map.width * tileWidth + tileWidth / 2, (map.height + 1) * (tileHeight / 2))
    }

    /// The seed that picks a tile's image variations
    /// (ImageLibrary.variationSeedUsing).
    public static func variationSeed(_ x: Int, _ y: Int) -> Int32 {
        Int32(truncatingIfNeeded: x &* 6841 &+ y &* 7919)
    }

    // MARK: Keys (ImageLibrary)

    /// The base image of a tile type, or of unexplored land
    /// (getTerrainImageKey).
    public static func terrainKey(_ typeId: String?) -> String {
        "image.tile." + (typeId ?? "model.tile.unexplored") + ".center"
    }

    /// The edge of unexplored land towards a side (getBorderImage).
    public static func unexploredBorderKey(_ direction: String) -> String {
        "image.tile.model.tile.unexplored.border." + direction
    }

    static func overlayKey(_ typeId: String) -> String { "image.tileoverlay." + typeId }

    static func aboveTileKey(_ typeId: String) -> String { "image.abovetile." + typeId }

    static func riverKey(_ style: String) -> String { "image.tile.model.improvement.river.s" + style }

    static func improvementKey(_ typeId: String) -> String { "image.tile." + typeId }

    static func resourceKey(_ typeId: String) -> String { "image.tileitem." + typeId }

    static let lostCityRumourKey = "image.tileitem.lostCityRumour"

    /// The forest of a tile type, cut for its river if it has one
    /// (getForestImageInternal).
    static func forestKey(_ typeId: String, riverStyle: String?, _ images: MapImages) -> String {
        if let riverStyle {
            let mask = String(riverStyle.map { $0 == "0" ? "0" : "1" })
            // An unconnected river still shows.
            let key = "image.tileforest." + typeId + ".s" + (mask == "0000" ? "0100" : mask)
            if images.hasImage(key) { return key }
        }
        return "image.tileforest." + typeId
    }

    /// A settlement's image: its type's, by size and stockade for a
    /// colony, or with a mission for natives, and national if there is
    /// a national one (getSettlementKey).
    public static func settlementKey(_ s: TileSettlementSnapshot, _ images: MapImages) -> String {
        var key = "image.tileitem." + s.typeId
        if s.isColony {
            if s.isUndead {
                key += ".undead"
            } else {
                let count = s.apparentUnitCount
                key += count <= 3 ? ".small" : count <= 7 ? ".medium" : ".large"
                if let stockade = s.stockadeKey { key += "." + stockade }
            }
            if let nation = s.ownerNationResourceKey, images.hasImage(key + "." + nation) {
                key += "." + nation
            }
        } else if s.hasMissionary {
            key += ".mission"
        }
        return key
    }

    /// A unit's image: its type's, by role, native if a former native
    /// with an image of its own, and national if there is a national
    /// one (getUnitTypeImageKey).
    public static func unitKey(_ unit: UnitSnapshot, ownerNation: String?, _ images: MapImages) -> String {
        let nativeEthnicity = unit.hasNativeEthnicity && !unit.isNativeBorn
        let role = unit.roleId.flatMap { $0 == "model.role.default" ? nil : $0 }
        let roleQual = role.map { "." + ($0.split(separator: ".").last.map(String.init) ?? $0) } ?? ""
        var key = "image.unit." + unit.typeId + roleQual + (nativeEthnicity ? ".native" : "")
        if nativeEthnicity && !images.hasImage(key) {
            key = "image.unit." + unit.typeId + roleQual
        }
        if let ownerNation, images.hasImage(key + "." + ownerNation) {
            key += "." + ownerNation
        }
        return key
    }

    /// The unit drawn in front on a tile, with no unit selected: none
    /// on a settlement, otherwise the one with the most moves left,
    /// active ones first (MapViewerState.findUnitInFront).
    public static func unitInFront(_ tile: TileSnapshot, _ units: [String: UnitSnapshot]) -> UnitSnapshot? {
        if tile.unitIds.isEmpty || tile.settlementId != nil { return nil }
        var result: UnitSnapshot?
        var bestScore = -1
        for id in tile.unitIds {
            guard let u = units[id] else { continue }
            let score = u.movesLeft + (u.state == "ACTIVE" ? 10000 : 0)
            if bestScore < score {
                bestScore = score
                result = u
            }
        }
        return result
    }

    // MARK: Planning

    /// What to draw for the tiles in some columns and rows, in Java's
    /// order: the base terrain, fog, unexplored borders, the tile items
    /// and settlements, the units, and what is drawn above tiles.
    public static func plan(_ snapshot: GameSnapshot, _ images: MapImages,
                            columns: Range<Int>, rows: Range<Int>) -> [MapDraw] {
        let map = snapshot.map
        let cols = columns.clamped(to: 0..<map.width), rws = rows.clamped(to: 0..<map.height)
        var tiles: [TileSnapshot] = []
        for y in rws { for x in cols { if let t = map.tile(x, y) { tiles.append(t) } } }
        var draws: [MapDraw] = []
        func add(_ t: TileSnapshot, _ d: MapDrawing) { draws.append(MapDraw(x: t.x, y: t.y, drawing: d)) }
        // Java's sized images take a variation by seed: the tile's, or
        // 0 where none is given (ImageCache.getSizedImage); its scaled
        // images are always the first (getScaledImage).
        func image(_ key: String, _ t: TileSnapshot, seeded: Bool) -> MapImage {
            MapImage(key, variation: images.variation(key, seed: seeded ? variationSeed(t.x, t.y) : 0))
        }

        // The base terrain (displayTileWithBeach), unexplored included.
        for t in tiles {
            let key = terrainKey(t.isExplored ? t.typeId : nil)
            add(t, .image(image(key, t, seeded: true), .corner, dimmed: false, grey: false))
        }

        // Fog over what is not seen now.
        for t in tiles where t.isExplored && !t.isVisible { add(t, .fog) }

        // The edges of unexplored land (displayUnknownTileBorder).
        for t in tiles where t.isExplored {
            for d in ["N", "NE", "E", "SE", "S", "SW", "W", "NW"] {
                guard let n = neighbour(map, t, d), !n.isExplored else { continue }
                let key = unexploredBorderKey(d)
                add(t, .image(image(key, t, seeded: true), .corner, dimmed: false, grey: false))
            }
        }

        // The tile items and settlements (displayTileItems,
        // displaySettlementWithChipsOrPopulationNumber).
        for t in tiles where t.isExplored {
            let dim = !t.isVisible
            let items = t.items.enumerated().sorted {
                $0.element.zIndex != $1.element.zIndex ? $0.element.zIndex < $1.element.zIndex
                    : $0.offset < $1.offset
            }.map(\.element)
            func item(_ it: TileItemSnapshot) {
                switch it.kind {
                case .improvement:
                    guard let typeId = it.typeId else { return }
                    if typeId == "model.improvement.road" {
                        return // Roads are painted (RoadPainter), in step 2.
                    } else if typeId == "model.improvement.river" {
                        if let style = it.style, images.hasImage(riverKey(style)) {
                            add(t, .image(image(riverKey(style), t, seeded: false), .corner, dimmed: dim, grey: false))
                        }
                    } else if images.hasImage(improvementKey(typeId)) {
                        add(t, .image(image(improvementKey(typeId), t, seeded: false), .corner, dimmed: dim,
                                      grey: false))
                    }
                case .resource:
                    if let typeId = it.typeId {
                        add(t, .image(MapImage(resourceKey(typeId)), .centered, dimmed: dim, grey: false))
                    }
                case .lostCityRumour:
                    add(t, .image(MapImage(lostCityRumourKey), .centered, dimmed: dim, grey: false))
                }
            }
            var rest = items[...]
            while let it = rest.first, it.zIndex < overlayZIndex { item(it); rest = rest.dropFirst() }
            if let typeId = t.typeId, images.hasImage(overlayKey(typeId)) {
                add(t, .image(image(overlayKey(typeId), t, seeded: true), .bottom, dimmed: dim, grey: false))
            }
            while let it = rest.first, it.zIndex < forestZIndex { item(it); rest = rest.dropFirst() }
            if t.isForested, let typeId = t.typeId {
                let river = t.items.first { $0.typeId == "model.improvement.river" }?.style
                add(t, .image(image(forestKey(typeId, riverStyle: river, images), t, seeded: false), .bottom,
                              dimmed: dim, grey: false))
            }
            for it in rest { item(it) }
            if let s = t.settlement {
                add(t, .image(MapImage(settlementKey(s, images)), .largeCentered, dimmed: dim, grey: false))
            }
        }

        // The unit in front on each tile seen now (displayUnit).
        let units = Dictionary(snapshot.units.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let nations = Dictionary(snapshot.players.map { ($0.id, $0.nationResourceKey) },
                                 uniquingKeysWith: { a, _ in a })
        for t in tiles where t.isVisible {
            guard let u = unitInFront(t, units) else { continue }
            let key = unitKey(u, ownerNation: u.ownerId.flatMap { nations[$0] }, images)
            add(t, .image(MapImage(key), .unit, dimmed: false, grey: u.state == "SENTRY"))
        }

        // What shows above tiles, such as clouds over the high seas.
        for t in tiles where t.isExplored {
            guard let typeId = t.typeId, images.hasImage(aboveTileKey(typeId)) else { continue }
            add(t, .image(image(aboveTileKey(typeId), t, seeded: true), .centered, dimmed: false, grey: false))
        }
        return draws
    }

    /// The tile next to one, on Java's staggered rows (Direction.step).
    static func neighbour(_ map: MapSnapshot, _ t: TileSnapshot, _ direction: String) -> TileSnapshot? {
        let odd = (t.y & 1) != 0
        let d: (Int, Int)
        switch direction {
        case "N": d = (0, -2)
        case "NE": d = odd ? (1, -1) : (0, -1)
        case "E": d = (1, 0)
        case "SE": d = odd ? (1, 1) : (0, 1)
        case "S": d = (0, 2)
        case "SW": d = odd ? (0, 1) : (-1, 1)
        case "W": d = (-1, 0)
        default: d = odd ? (0, -1) : (-1, -1)
        }
        return map.tile(t.x + d.0, t.y + d.1)
    }
}

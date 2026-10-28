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

import FreeColCore
import FreeColEngine

/// What the map's images are, found by key (the resource manager), and
/// which variation of one a tile uses.
public protocol MapImages {
    /// Whether there is an image for a key.
    func hasImage(_ key: String) -> Bool
    /// The variation of a key's image picked by a seed
    /// (ImageResource.getVariationNumberForSeed).
    func variation(_ key: String, seed: Int32) -> Int
    /// The variation of a key's image for an animation tick
    /// (getVariationNumberForTick).
    func variation(_ key: String, ticks: Int64) -> Int
    /// How many pictures a key's image has: its variations and itself.
    func numberOfVariations(_ key: String) -> Int
    /// The key Java caches a key's image under (getCachingKey).
    func cachingKey(_ key: String) -> String?
    /// A colour resource, as ARGB (ImageLibrary.getColor).
    func color(_ key: String) -> Int32
    /// A string resource (ResourceManager.getString).
    func string(_ key: String) -> String
}

/// One image: its key, and which variation.  Variations are numbered
/// from 0, and one past them is the image itself.
public struct MapImage: Hashable, Sendable {
    public let key: String
    public let variation: Int

    public init(_ key: String, variation: Int = 0) {
        self.key = key
        self.variation = variation
    }
}

/// The client's options that change what the map shows, with Java's
/// defaults (data/base/client-options.xml).
public struct MapOptions: Sendable, Equatable {
    /// 0 lowest, 10 low, 20 normal, 30 high, 40 highest.
    public var graphicsQuality = 20
    public var useTerrainAnimations = true
    public var displayFogOfWar = false
    /// Borders round each player's land.
    public var displayBorders = false
    /// The tile text: 0 none, 1 names, 2 owners, 3 regions (which also
    /// draws region borders).
    public var displayTileText = 0
    /// Settlement labels: 0 none, 1 classic (names under settlements,
    /// chips on native ones and the number of colonists on colonies).
    /// Java's 2, modern, is not drawn yet.
    public var displayColonyLabels = 1
    /// The animation tick: milliseconds / 125, or 0 to freeze.
    public var ticks: Int64 = 0

    public init() {}

    /// isTerrainAnimationsEnabled and isRiverAnimationEnabled.
    var terrainAnimations: Bool { useTerrainAnimations && graphicsQuality >= 10 }
    var riverAnimation: Bool { terrainAnimations && graphicsQuality >= 20 }
}

/// Where an image goes on its tile, as Java's TileViewer and MapViewer
/// place them, in tile pixels at scale 1 (a tile is 128 by 64).
public enum MapPlacement: Sendable, Equatable {
    /// At the tile's corner (base terrain, borders, composites).
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
    /// Centred across, a pixel right, below the tile (settlement names).
    case label

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
        case .label: return ((tw - width) / 2 + 1, th)
        }
    }
}

/// The size Java draws an image at: resized to a tile, or to the
/// taller tile of hills and forests (ImageLibrary's sized images), or
/// as it is (its scaled images, at scale 1).
public enum MapSize: Sendable, Equatable {
    case natural
    /// 128 by 64 (TILE_SIZE).
    case tile
    /// 128 by 96 (TILE_OVERLAY_SIZE): hills, mountains, clouds.
    case overlay
    /// 128 by 84 (TILE_FOREST_SIZE).
    case forest

    /// The size, or nil for an image's own.
    public var dimensions: (width: Int, height: Int)? {
        switch self {
        case .natural: nil
        case .tile: (128, 64)
        case .overlay: (128, 96)
        case .forest: (128, 84)
        }
    }
}

/// One thing to draw on a tile.
public enum MapDrawing: Sendable, Equatable {
    /// An image at a size; dimmed for fog of war (Java's 0.8 rescale),
    /// or grey (a sentry).
    case image(MapImage, MapPlacement, size: MapSize, dimmed: Bool, grey: Bool)
    /// An image Java makes from others (a transition, beach, river or
    /// river mouth), at the tile's corner.
    case composite(MapComposite, dimmed: Bool)
    /// A line drawn on the tile, in an ARGB colour at a width (roads).
    case path([MapPathSegment], color: Int32, width: Float)
    /// The fog of war over a tile seen before but not now (black at a
    /// fifth).
    case fog
    /// A row of chips from a point on the tile.  Java steps along by
    /// the first chip's width and 2 more, so each after the first is
    /// that far from the one before, whatever its own width.
    case chips([MapChip], x: Int, y: Int, dimmed: Bool)
    /// Text, placed by its size.
    case text(MapText, MapPlacement, dimmed: Bool)
    /// A line one pixel wide, its ends included (Graphics.drawLine).
    case line(x1: Int, y1: Int, x2: Int, y2: Int, color: Int32)
    /// A rectangle, filled (fillRect), or outlined one pixel wide, a
    /// pixel larger each way (drawRect).
    case rectangle(x: Int, y: Int, width: Int, height: Int, color: Int32, filled: Bool)
}

/// A chip: a small box of a colour edged in black, with a letter or two
/// on it (ImageLibrary.createChip, in the font simple-bold-tiny).
public struct MapChip: Sendable, Equatable {
    public let text: String
    public let background: Int32
    public let foreground: Int32

    public static let font = "simple-bold-tiny"
}

/// Text in a colour, its letters edged a pixel round in black, or
/// white if the text is nearly black (ImageLibrary.getStringImage).
public struct MapText: Sendable, Equatable {
    public let text: String
    public let color: Int32
    /// Java's font name: face, style and size ("simple-bold-tiny").
    public let font: String

    /// makeStringBorderColor.
    public var borderColor: Int32 { MapScene.luminance(color) < 10 ? MapScene.white : MapScene.black }
}

/// A step of a path on a tile, in tile pixels (Java's GeneralPath).
public enum MapPathSegment: Sendable, Equatable {
    case move(Float, Float)
    case line(Float, Float)
    /// A quadratic curve through a control point.
    case quad(Float, Float, Float, Float)
}

/// The passes over the map, in the order Java's MapViewer paints them.
public enum MapPass: String, Sendable, Equatable {
    /// Water, beaches, river mouths and rivers (displayAnimatedBaseTiles).
    case animated
    /// The other base tiles (displayTileWithBeach).
    case base
    /// The transitions between terrains (drawBaseTileTransitions).
    case transitions
    /// Region and country borders under the items, opaque.
    case territory
    case fog
    /// The edges of unexplored land (displayUnknownTileBorder).
    case borders
    /// Tile items and settlements (displayTileItems).
    case items
    /// Region and country borders over the items, translucent.
    case territoryOver
    /// Units, with their chips, the lines for the units with them, and
    /// their hitpoints.
    case units
    /// What shows above tiles.
    case above
    /// Settlement names (displaySettlementLabels).
    case labels
}

/// Something to draw, on which tile, in which pass.
public struct MapDraw: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let pass: MapPass
    public let drawing: MapDrawing
}

/// What to draw for a player's view of the map, and in what order, as
/// Java's MapViewer (displayNonAnimationImages) and TileViewer draw it,
/// pass by pass over the tiles.  Images are named by key, so drawing
/// them is left to the screen.
public enum MapScene {

    public static let tileWidth = 128
    public static let tileHeight = 64
    /// How far units are raised on their tiles (TileBounds.UNIT_OFFSET).
    public static let unitOffset = 20
    /// Where chips go on a tile (TileViewer.STATE_OFFSET_X and _Y).
    static let stateOffsetX = 25, stateOffsetY = 10

    static let black = Int32(bitPattern: 0xFF00_0000)
    static let white: Int32 = -1
    static let gray = Int32(bitPattern: 0xFF80_8080)
    static let green = Int32(bitPattern: 0xFF00_FF00)

    /// The brightness Java's colour rules weigh (0 to 255).
    static func luminance(_ argb: Int32) -> Double {
        let r = Double((argb >> 16) & 0xFF), g = Double((argb >> 8) & 0xFF), b = Double(argb & 0xFF)
        return r * 0.3 + g * 0.59 + b * 0.11
    }

    /// Black text on light colours, white on dark
    /// (ImageLibrary.makeForegroundColor).
    static func foreground(_ background: Int32?) -> Int32 {
        guard let background else { return black }
        return luminance(background) >= 126 ? black : white
    }

    /// The z-indexes Java layers tile items by (Tile.OVERLAY_ZINDEX and
    /// FOREST_ZINDEX).
    static let overlayZIndex = 100
    static let forestZIndex = 200

    static let riverId = "model.improvement.river"
    static let roadId = "model.improvement.road"

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
    public static func unexploredBorderKey(_ direction: Direction) -> String {
        "image.tile.model.tile.unexplored.border." + direction.javaName
    }

    static func overlayKey(_ typeId: String) -> String { "image.tileoverlay." + typeId }

    static func aboveTileKey(_ typeId: String) -> String { "image.abovetile." + typeId }

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
    /// order: the animated base tiles (water, beaches, river mouths and
    /// rivers), the other base tiles, the transitions between terrains,
    /// fog, the edges of unexplored land, the tile items and
    /// settlements, the units, and what is drawn above tiles.
    ///
    /// Not yet: the grid, chips and labels.
    public static func plan(_ snapshot: GameSnapshot, _ images: MapImages, _ options: MapOptions = MapOptions(),
                            columns: Range<Int>, rows: Range<Int>) -> [MapDraw] {
        let view = MapView(snapshot.map, images, options)
        let map = snapshot.map
        let cols = columns.clamped(to: 0..<map.width), rws = rows.clamped(to: 0..<map.height)
        var tiles: [TileSnapshot] = []
        for y in rws { for x in cols { if let t = map.tile(x, y) { tiles.append(t) } } }
        var draws: [MapDraw] = []
        var pass = MapPass.animated
        func add(_ t: TileSnapshot, _ d: MapDrawing) { draws.append(MapDraw(x: t.x, y: t.y, pass: pass, drawing: d)) }
        func seeded(_ key: String, _ t: TileSnapshot) -> MapImage {
            MapImage(key, variation: images.variation(key, seed: variationSeed(t.x, t.y)))
        }
        func composite(_ t: TileSnapshot, _ c: MapComposite?, dimmed: Bool = false) {
            if let c { add(t, .composite(c, dimmed: dimmed)) }
        }
        func transitions(_ t: TileSnapshot) {
            if options.graphicsQuality == 0 { return }
            let nice = options.graphicsQuality >= 20, variations = options.graphicsQuality >= 30
            for d in [Direction.ne, .sw, .nw, .se] {
                composite(t, view.transition(t, d, nice: nice, variations: variations))
            }
        }

        // The animated base tiles (displayAnimatedBaseTiles): water with
        // its beaches and river mouths, and land with a river.
        let ticks = options.terrainAnimations ? options.ticks : 0
        for t in tiles {
            guard let typeId = t.typeId, t.isExplored else { continue }
            if !t.isLand {
                if view.directionsWithLand(t).isEmpty {
                    let key = terrainKey(typeId)
                    add(t, .image(MapImage(key, variation: images.variation(key, ticks: ticks)), .corner,
                                  size: .tile, dimmed: false, grey: false))
                } else {
                    composite(t, view.beach(t, ticks))
                }
                if options.riverAnimation && view.hasRiverDelta(t) {
                    transitions(t)
                    for c in view.riverMouths(t, ticks) { composite(t, c) }
                }
            } else if options.riverAnimation && view.river(t) != nil {
                add(t, .image(seeded(terrainKey(typeId), t), .corner, size: .tile, dimmed: false, grey: false))
                transitions(t)
                composite(t, view.riverImage(t, ticks))
            }
        }

        // The other base tiles (displayTileWithBeach), unexplored ones
        // included.
        pass = .base
        for t in tiles {
            let animated = t.isExplored && (!t.isLand || options.riverAnimation && view.river(t) != nil)
            if animated { continue }
            add(t, .image(seeded(terrainKey(t.isExplored ? t.typeId : nil), t), .corner, size: .tile, dimmed: false, grey: false))
        }

        // The transitions, where not drawn with the animated tiles.
        pass = .transitions
        for t in tiles {
            if options.riverAnimation && (view.river(t) != nil || view.hasRiverDelta(t)) { continue }
            transitions(t)
            if !options.riverAnimation {
                for c in view.riverMouths(t, 0) { composite(t, c) }
            }
        }

        // Region and country borders, opaque (displayTerritorialBorders).
        func territory(_ opaque: Bool) {
            let alpha: Int32 = opaque ? 255 : 100
            // Java's regions first, then countries, each over all tiles.
            for region in [true, false] {
                if region ? options.displayTileText != 3 : !options.displayBorders { continue }
                for t in tiles {
                    guard let path = view.territoryPath(t, region: region) else { continue }
                    let rgb = region ? nil : t.ownerId.flatMap { nationColors[$0] } ?? nil
                    let color = ((rgb ?? -1) & 0x00FF_FFFF) | (alpha << 24)
                    add(t, .path(path, color: color, width: Float(MapScene.tileHeight / 16)))
                }
            }
        }
        let nationColors = Dictionary(snapshot.players.map { ($0.id, $0.nationColor) }, uniquingKeysWith: { a, _ in a })
        pass = .territory
        territory(true)

        // Fog over what is not seen now, if the game and the player want
        // it (shouldFogOfWarBeDisplayed).
        let fog = snapshot.fogOfWar && options.displayFogOfWar
        pass = .fog
        if fog {
            for t in tiles where t.isExplored && !t.isVisible { add(t, .fog) }
        }

        // The edges of unexplored land (displayUnknownTileBorder).
        pass = .borders
        for t in tiles where t.isExplored {
            for d in Direction.allDirections {
                guard let n = view.neighbour(t, d), !n.isExplored else { continue }
                add(t, .image(seeded(unexploredBorderKey(d), t), .corner, size: .tile, dimmed: false, grey: false))
            }
        }

        // The tile items and settlements (displayTileItems,
        // displaySettlementWithChipsOrPopulationNumber).
        pass = .items
        for t in tiles where t.isExplored {
            let dim = fog && !t.isVisible
            let items = t.items.enumerated().sorted {
                $0.element.zIndex != $1.element.zIndex ? $0.element.zIndex < $1.element.zIndex
                    : $0.offset < $1.offset
            }.map(\.element)
            func item(_ it: TileItemSnapshot) {
                switch it.kind {
                case .improvement:
                    guard let typeId = it.typeId else { return }
                    if typeId == roadId {
                        add(t, .path(view.roadPath(t), color: images.color("color.map.road"), width: 2))
                    } else if typeId == riverId {
                        // Drawn with the animated tiles, if animated.
                        if !options.riverAnimation { composite(t, view.riverImage(t, 0), dimmed: dim) }
                    } else if images.hasImage(improvementKey(typeId)) {
                        let key = improvementKey(typeId)
                        add(t, .image(MapImage(key, variation: images.variation(key, seed: 0)), .corner,
                                      size: .tile, dimmed: dim, grey: false))
                    }
                case .resource:
                    if let typeId = it.typeId {
                        add(t, .image(MapImage(resourceKey(typeId)), .centered, size: .natural, dimmed: dim, grey: false))
                    }
                case .lostCityRumour:
                    add(t, .image(MapImage(lostCityRumourKey), .centered, size: .natural, dimmed: dim, grey: false))
                }
            }
            var rest = items[...]
            while let it = rest.first, it.zIndex < overlayZIndex { item(it); rest = rest.dropFirst() }
            if let typeId = t.typeId, images.hasImage(overlayKey(typeId)) {
                add(t, .image(seeded(overlayKey(typeId), t), .bottom, size: .overlay, dimmed: dim, grey: false))
            }
            while let it = rest.first, it.zIndex < forestZIndex { item(it); rest = rest.dropFirst() }
            if t.isForested, let typeId = t.typeId {
                let key = forestKey(typeId, riverStyle: view.river(t)?.style, images)
                add(t, .image(MapImage(key, variation: images.variation(key, seed: 0)), .bottom, size: .forest, dimmed: dim,
                              grey: false))
            } else if options.graphicsQuality >= 30 {
                for (key, _) in view.forestCorners(t) {
                    add(t, .image(MapImage(key, variation: images.variation(key, seed: 0)), .bottom, size: .forest, dimmed: false,
                                  grey: false))
                }
            }
            for it in rest { item(it) }
            if let s = t.settlement {
                add(t, .image(MapImage(settlementKey(s, images)), .largeCentered, size: .natural, dimmed: dim, grey: false))
                settlementChips(t, s, dim)
            }
        }

        // A colony's number of colonists, or a native settlement's
        // chips (displaySettlementWithChipsOrPopulationNumber).
        func settlementChips(_ t: TileSnapshot, _ s: TileSettlementSnapshot, _ dim: Bool) {
            let classic = options.displayColonyLabels == 1
            if s.isColony {
                guard classic else { return }
                let text = MapText(text: String(s.apparentUnitCount),
                                   color: images.color("color.map.productionBonus.\(s.productionBonus)"),
                                   font: s.wantsMoreUnits ? "simple-bold+italic-smaller" : MapChip.font)
                add(t, .text(text, .centered, dimmed: dim))
                return
            }
            var chips: [MapChip] = []
            let background = s.ownerColor ?? white
            if classic {
                chips.append(MapChip(text: images.string("indianSettlementChip." + (s.isCapital ? "capital" : "normal")),
                                     background: background, foreground: foreground(background)))
                if let missionary = s.missionaryColor {
                    let key = "color.foreground.mission." + (s.missionaryIsExpert ? "expert" : "normal")
                    chips.append(MapChip(text: images.string("cross"), background: missionary,
                                         foreground: images.color(key)))
                }
            }
            if let alarm = s.alarm {
                let key = alarm.isWorthScouting ? "indianAlarmChip.contacted" : "indianAlarmChip.scouted"
                chips.append(MapChip(text: images.string(key), background: background,
                                     foreground: foreground(alarm.mostHatedColor)))
            }
            if !chips.isEmpty { add(t, .chips(chips, x: stateOffsetX, y: stateOffsetY, dimmed: dim)) }
        }

        // The borders again, translucent over the items.
        pass = .territoryOver
        territory(false)

        // The unit in front on each tile seen now (displayUnit).
        pass = .units
        let units = Dictionary(snapshot.units.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let nations = Dictionary(snapshot.players.map { ($0.id, $0.nationResourceKey) },
                                 uniquingKeysWith: { a, _ in a })
        for t in tiles where t.isVisible {
            guard let u = unitInFront(t, units) else { continue }
            let key = unitKey(u, ownerNation: u.ownerId.flatMap { nations[$0] }, images)
            add(t, .image(MapImage(key), .unit, size: .natural, dimmed: false, grey: u.state == "SENTRY"))
            // Its occupation, on its owner's colour.
            let background = u.ownerId.flatMap { nationColors[$0] } ?? nil
            add(t, .chips([MapChip(text: u.occupation, background: background ?? white,
                                   foreground: u.state == "FORTIFIED" ? gray : foreground(background))],
                          x: stateOffsetX, y: 0, dimmed: false))
            // A line for each unit here, if more than one.
            if t.totalUnitCount > 1 {
                for i in 0..<min(t.totalUnitCount, 10) {
                    add(t, .line(x1: stateOffsetX - 5, y1: 1 + 2 * i, x2: stateOffsetX - 2, y2: 1 + 2 * i, color: white))
                }
            }
            // Its hitpoints, if hurt.
            if u.hitPoints >= 0 && u.hitPoints < u.maximumHitPoints {
                let full = tileHeight - 10
                let filled = Int(Float(full) * (Float(u.hitPoints) / Float(u.maximumHitPoints)))
                add(t, .rectangle(x: 18, y: 5 - unitOffset + full - filled, width: 5, height: filled, color: green,
                                  filled: true))
                add(t, .rectangle(x: 18, y: 5 - unitOffset, width: 5, height: full, color: black, filled: false))
            }
        }

        // What shows above tiles, such as clouds over the high seas.
        pass = .above
        for t in tiles where t.isExplored {
            guard let typeId = t.typeId, images.hasImage(aboveTileKey(typeId)) else { continue }
            add(t, .image(seeded(aboveTileKey(typeId), t), .centered, size: .overlay, dimmed: false, grey: false))
        }

        // Settlement names, in their owners' colours.
        pass = .labels
        if options.displayColonyLabels != 0 {
            for t in tiles where t.isExplored {
                guard let s = t.settlement, let name = s.name else { continue }
                add(t, .text(MapText(text: name, color: s.ownerColor ?? white, font: "normal-bold-smaller"), .label,
                             dimmed: fog && !t.isVisible))
            }
        }
        return draws
    }
}

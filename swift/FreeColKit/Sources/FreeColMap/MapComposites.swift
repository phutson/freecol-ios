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
import FreeColUtil

/// How to make a tile-sized picture from images, as Java's image
/// creators make them.
public indirect enum MapPicture: Hashable, Sendable {
    /// An image.
    case image(MapImage)
    /// A picture keeping only where a mask is opaque
    /// (ImageUtils.imageWithAlphaFromMask: AlphaComposite.DST_IN).
    case masked(MapPicture, mask: MapPicture)
    /// Pictures drawn over each other, each at an opacity.
    case layers([MapLayer])
    /// A mask under itself scaled up by a quarter about its centre,
    /// which softens its edge (toLargerMaskWithLessTransparency).
    case enlarged(MapPicture)
}

/// A picture in a stack, at an opacity.
public struct MapLayer: Hashable, Sendable {
    public let picture: MapPicture
    public let opacity: Float

    public init(_ picture: MapPicture, _ opacity: Float = 1) {
        self.picture = picture
        self.opacity = opacity
    }
}

/// A picture Java makes, with the key and variation Java caches it
/// under (getCachedImageOrGenerate), which names what it is made of.
/// Java makes a picture once per key and variation, and so may the
/// screen.
public struct MapComposite: Hashable, Sendable {
    public let key: String
    public let variation: Int
    public let picture: MapPicture
}

/// A player's view of the map, for planning: its tiles, their
/// neighbours, and the pictures made from them (Java's
/// BaseTileTransitionImageCreator, BeachTileAnimationImageCreator,
/// RiverAnimationImageCreator and DeltaAnimationImageCreator).
struct MapView {
    let map: MapSnapshot
    let images: MapImages
    let options: MapOptions

    init(_ map: MapSnapshot, _ images: MapImages, _ options: MapOptions) {
        self.map = map
        self.images = images
        self.options = options
    }

    static let beachKey = "image.tile.model.tile.beach"
    static let riverWaterKey = "image.tile.river.water"
    static let riverPebblesKey = "image.tile.river.pebbles"
    /// The mask of a whole tile (getTerrainMask(null)).
    static let tileMaskKey = "image.mask"

    func neighbour(_ t: TileSnapshot, _ d: Direction) -> TileSnapshot? {
        let p = d.step(t.x, t.y)
        return map.tile(p.x, p.y)
    }

    func river(_ t: TileSnapshot) -> TileItemSnapshot? {
        t.items.first { $0.typeId == MapScene.riverId }
    }

    /// A sized image with no seed given, which Java takes by seed 0
    /// (getSizedImage).
    func sized(_ key: String) -> MapPicture {
        .image(MapImage(key, variation: images.variation(key, seed: 0)))
    }

    /// An image resource's own picture, not a variation (getImage).
    func itself(_ key: String) -> MapPicture {
        .image(MapImage(key, variation: images.numberOfVariations(key) - 1))
    }

    // MARK: Transitions

    /// The neighbours on land, in Java's order of directions.
    func directionsWithLand(_ t: TileSnapshot) -> [Direction] {
        Direction.allDirections.filter { neighbour(t, $0)?.isLand ?? false }
    }

    /// The fading edge of a neighbouring terrain, or of a beach, over a
    /// tile's side, made by a mask; the corners at NW and SE also blend
    /// the neighbour's own edges (getBaseTileTransitionImage).
    func transition(_ tile: TileSnapshot, _ direction: Direction, nice: Bool,
                    variations: Bool) -> MapComposite? {
        guard let bordering = neighbour(tile, direction), bordering.isExplored, tile.isExplored else { return nil }
        let special = nice && (direction == .nw || direction == .se)
        if tile.typeId == bordering.typeId && !special { return nil }
        // The neighbour's terrain, or a beach where water meets land.
        let notBeach = bordering.isLand || (!bordering.isLand && !tile.isLand)
        let terrainKey = notBeach ? MapScene.terrainKey(bordering.typeId) : MapView.beachKey
        guard let terrainCaching = images.cachingKey(terrainKey),
              let tileCaching = images.cachingKey(MapScene.terrainKey(tile.typeId)) else { return nil }
        if terrainCaching == tileCaching && !special { return nil }

        let beachNE = special && beachCorner(tile, bordering, .ne)
        let beachSW = special && beachCorner(tile, bordering, .sw)
        let maskKey = "image.mask." + direction.javaName.lowercased()
        let maskCount = images.numberOfVariations(maskKey)
        let maskVariation: Int
        if variations && maskCount > 1 {
            // The same either side; never the last, a straight edge.
            let seedTile = direction == .nw || direction == .ne ? tile : bordering
            let random = JavaRandom(seed: Int64(MapScene.variationSeed(seedTile.x, seedTile.y)))
            maskVariation = Int(random.nextInt(Int32(maskCount - 1)))
        } else {
            maskVariation = maskCount - 1
        }

        let key: String
        if special {
            let ne = neighbour(bordering, .ne)?.typeId ?? "null"
            let sw = neighbour(bordering, .sw)?.typeId ?? "null"
            key = terrainCaching + "," + ne + "," + sw + "," + String(maskVariation) + ","
                + String(beachNE) + String(beachSW) + "$baseTransition$gen"
        } else {
            key = terrainCaching + "," + String(maskVariation) + "$baseTransition$gen"
        }

        let terrain = MapPicture.image(MapImage(terrainKey, variation: 0))
        let content: MapPicture
        if !special {
            content = terrain
        } else {
            // The corners: the neighbour's terrain blended with its own
            // edges towards NE and SW, and a beach where water corners
            // touch land.
            var layers: [MapLayer] = []
            if tile.isLand || bordering.isLand {
                layers.append(MapLayer(terrain))
            } else {
                if beachNE { layers.append(MapLayer(specialBeach(.ne))) }
                if beachSW { layers.append(MapLayer(specialBeach(.sw))) }
            }
            for d in [Direction.ne, .sw] {
                if let t = transition(bordering, d, nice: false, variations: false) {
                    layers.append(MapLayer(t.picture))
                }
            }
            content = .layers(layers)
        }
        // Java caches the transition by its key and its direction.
        return MapComposite(key: key, variation: direction.javaOrdinal,
                            picture: .masked(content, mask: .image(MapImage(maskKey, variation: maskVariation))))
    }

    /// Whether a water corner touches land (shouldIncludeSpecialBeachTransitionInDirection).
    private func beachCorner(_ tile: TileSnapshot, _ bordering: TileSnapshot, _ d: Direction) -> Bool {
        if tile.isLand || bordering.isLand { return false }
        return (neighbour(tile, d)?.isLand ?? false) || (neighbour(bordering, d)?.isLand ?? false)
    }

    private func specialBeach(_ d: Direction) -> MapPicture {
        .masked(.image(MapImage(MapView.beachKey, variation: 0)),
                mask: sized("image.mask.special.beach." + d.javaName.lowercased()))
    }

    // MARK: Water

    /// Water with beaches along the land beside it, a little more water
    /// in some frames (getAnimatedScaledWaterAndBeachTerrainImage).
    func beach(_ tile: TileSnapshot, _ ticks: Int64) -> MapComposite? {
        guard let typeId = tile.typeId, images.hasImage(MapView.beachKey) else { return nil }
        let combination = beachCombination(directionsWithLand(tile))
        let oceanKey = MapScene.terrainKey(typeId)
        guard let oceanCaching = images.cachingKey(oceanKey) else { return nil }
        let oceanVariation = images.variation(oceanKey, ticks: ticks)
        let masked = MapPicture.masked(.image(MapImage(oceanKey, variation: oceanVariation)),
                                       mask: sized("image.mask.beach." + combination))
        let extraOcean: Float = 0.05
        let alpha = oceanVariation <= 10 ? extraOcean * Float(oceanVariation)
            : extraOcean * 10 - extraOcean * Float(oceanVariation - 10)
        let picture = MapPicture.masked(.layers([MapLayer(itself(MapView.beachKey)), MapLayer(masked),
                                                 MapLayer(masked, alpha)]),
                                        mask: sized(MapView.tileMaskKey))
        return MapComposite(key: oceanCaching + ".beach." + combination + "$gen", variation: oceanVariation,
                            picture: picture)
    }

    /// The beach mask's name: the sides with land, and the corners not
    /// part of them (determineDirectionCombinationKey).
    private func beachCombination(_ directions: [Direction]) -> String {
        let sides = directions.filter { Direction.longSides.contains($0) }
            .map { $0.javaName.lowercased() }.sorted()
        let pre = sides.isEmpty ? nil : sides.joined(separator: "_")
        return directions.filter {
            Direction.longSides.contains($0) || pre == nil || !pre!.contains($0.javaName.lowercased())
        }.map { $0.javaName.lowercased() }.sorted().joined(separator: "_")
    }

    // MARK: Rivers

    private func directionNames(_ directions: [Direction]) -> String {
        directions.map { $0.javaName.lowercased() }.sorted().joined(separator: "_")
    }

    /// How strong a river's connection is towards a side
    /// (getRiverConnection).
    private func riverConnection(_ river: TileItemSnapshot, _ d: Direction) -> Int {
        guard let i = Direction.longSides.firstIndex(of: d), let style = river.style,
              i < style.count else { return 0 }
        return style[style.index(style.startIndex, offsetBy: i)].wholeNumberValue ?? 0
    }

    /// Whether a river on a neighbouring land flows into this water
    /// (hasRiverDelta).
    func hasRiverDelta(_ t: TileSnapshot) -> Bool {
        !riverMouthDirections(t).isEmpty
    }

    private func riverMouthDirections(_ t: TileSnapshot) -> [Direction] {
        Direction.longSides.filter { d in
            guard let bordering = neighbour(t, d), !t.isLand, bordering.isLand, t.isExplored,
                  let river = river(bordering) else { return false }
            return riverConnection(river, d.reverseDirection) > 0
        }
    }

    /// The mouths of rivers flowing into this water
    /// (drawRiverMouth, getAnimatedScaledRiverDeltaTerrainImage).
    func riverMouths(_ t: TileSnapshot, _ ticks: Int64) -> [MapComposite] {
        guard images.hasImage(MapView.riverPebblesKey),
              let waterCaching = images.cachingKey(MapView.riverWaterKey) else { return [] }
        let variation = images.variation(MapView.riverWaterKey, ticks: ticks)
        return riverMouthDirections(t).map { d in
            let name = d.javaName.lowercased()
            let picture = MapPicture.masked(
                .layers([MapLayer(.masked(itself(MapView.riverPebblesKey),
                                          mask: sized("image.mask.river.delta.pebbles." + name))),
                         MapLayer(.masked(.image(MapImage(MapView.riverWaterKey, variation: variation)),
                                          mask: sized("image.mask.river.delta." + name)), 0.9)]),
                mask: sized(MapView.tileMaskKey))
            return MapComposite(key: waterCaching + ".riverDelta." + d.javaName + "." + String(variation) + "$gen",
                                variation: variation, picture: picture)
        }
    }

    /// A river's water over pebbles, shaped by its connections, a minor
    /// one widening where it meets a major river or the sea
    /// (getAnimatedScaledRiverTerrainImage).
    func riverImage(_ t: TileSnapshot, _ ticks: Int64) -> MapComposite? {
        guard let river = river(t), images.hasImage(MapView.riverPebblesKey),
              let waterCaching = images.cachingKey(MapView.riverWaterKey) else { return nil }
        let connections = Direction.longSides.filter { riverConnection(river, $0) > 0 }
        let variationKey = directionNames(connections)
        let variation = images.variation(MapView.riverWaterKey, ticks: ticks)
        let minor = river.magnitude <= 1 ? ".minor" : ""
        let toMajor = river.magnitude > 1 ? [] : connections.filter { d in
            guard let n = neighbour(t, d) else { return false }
            return (self.river(n).map { $0.magnitude > 1 } ?? false) || (t.isLand && !n.isLand)
        }
        let baseMask = sized("image.mask.river" + minor + (variationKey.isEmpty ? "" : "." + variationKey))
        let riverMask = toMajor.isEmpty ? baseMask
            : .layers([MapLayer(baseMask)] + toMajor.map {
                MapLayer(sized("image.mask.river.to_major." + $0.javaName.lowercased()))
            })
        let water = MapPicture.masked(.image(MapImage(MapView.riverWaterKey, variation: variation)), mask: riverMask)
        let picture = MapPicture.masked(
            .masked(.layers([MapLayer(itself(MapView.riverPebblesKey)), MapLayer(water, 0.9)]),
                    mask: .enlarged(riverMask)),
            mask: sized(MapView.tileMaskKey))
        return MapComposite(key: waterCaching + ".river." + minor + directionNames(toMajor) + "." + variationKey + "$gen",
                            variation: variation, picture: picture)
    }

    // MARK: Roads

    /// Where a road leaves a tile towards each side (RoadPainter's
    /// corners).
    private static let roadCorners: [Direction: (Float, Float)] = [
        .n: (64, 0), .ne: (96, 16), .e: (128, 32), .se: (96, 48),
        .s: (64, 64), .sw: (32, 48), .w: (0, 32), .nw: (32, 16),
    ]

    /// Pairs of exits not joined on a tile with three or four, so the
    /// roads do not cut corners.
    private static let prohibitedRoads: [Direction: [Direction]] = [
        .n: [.nw, .ne], .ne: [.n, .e], .e: [.ne, .se], .se: [.e, .s],
        .s: [.se, .sw], .sw: [.s, .w], .w: [.sw, .nw], .nw: [.w, .n],
    ]

    /// A road's lines: a cross alone, towards the one neighbour with a
    /// road, curving between two or round three or four, and straight
    /// from the centre to more (RoadPainter.displayRoad).
    func roadPath(_ t: TileSnapshot) -> [MapPathSegment] {
        let w = Float(MapScene.tileWidth), h = Float(MapScene.tileHeight)
        let hw = Float(MapScene.tileWidth / 2), hh = Float(MapScene.tileHeight / 2)
        let directions = Direction.allDirections.filter { d in
            neighbour(t, d)?.items.contains { $0.typeId == MapScene.roadId } ?? false
        }
        let points = directions.map { MapView.roadCorners[$0]! }
        switch points.count {
        case 0:
            return [.move(0.35 * w, 0.35 * h), .line(0.65 * w, 0.65 * h),
                    .move(0.35 * w, 0.65 * h), .line(0.65 * w, 0.35 * h)]
        case 1:
            return [.move(hw, hh), .line(points[0].0, points[0].1)]
        case 2:
            return [.move(points[0].0, points[0].1), .quad(hw, hh, points[1].0, points[1].1)]
        case 3, 4:
            var pen = directions[directions.count - 1]
            let start = MapView.roadCorners[pen]!
            var ret: [MapPathSegment] = [.move(start.0, start.1)]
            for d in directions {
                let pt = MapView.roadCorners[d]!
                if MapView.prohibitedRoads[pen]!.contains(d) {
                    ret.moveTo(pt.0, pt.1)
                } else {
                    ret.append(.quad(hw, hh, pt.0, pt.1))
                }
                pen = d
            }
            return ret
        default:
            return points.flatMap { [MapPathSegment.move(hw, hh), .line($0.0, $0.1)] }
        }
    }

    // MARK: Borders

    /// Where borders run on a tile, inset from its edges, and where they
    /// bend (MapViewerScaledUtils's border and control points).
    private static let borderPoints: [Direction: (Float, Float)] = [
        .nw: (20, 26), .n: (52, 10), .ne: (76, 10), .e: (108, 26),
        .se: (108, 38), .s: (76, 54), .sw: (52, 54), .w: (20, 38),
    ]
    private static let controlPoints: [Direction: (Float, Float)] = [
        .n: (64, 4), .e: (120, 32), .s: (64, 60), .w: (8, 32),
        .se: (64, 64), .ne: (128, 32), .sw: (0, 32), .nw: (64, 0),
    ]

    /// The border inside a tile along the sides where its owner's land,
    /// or its region, ends: straight, round small and big corners
    /// (MapViewer.displayTerritorialBorders).  Nil if the tile has no
    /// owner (or region).
    func territoryPath(_ tile: TileSnapshot, region: Bool) -> [MapPathSegment]? {
        let key = region ? tile.regionId : tile.ownerId
        guard key != nil else { return nil }
        func same(_ t: TileSnapshot?) -> Bool {
            guard let t else { return false }
            return (region ? t.regionId : t.ownerId) == key
        }
        let bp = MapView.borderPoints, cp = MapView.controlPoints
        let hw = Float(MapScene.tileWidth / 2), hh = Float(MapScene.tileHeight / 2)
        let w = Float(MapScene.tileWidth), h = Float(MapScene.tileHeight)
        var path: [MapPathSegment] = [.move(bp[.ne]!.0, bp[.ne]!.1)]
        for d in Direction.longSides {
            let next = d.nextDirection, next2 = next.nextDirection
            if same(neighbour(tile, d)) {
                path.moveTo(bp[next2]!.0, bp[next2]!.1)
                continue
            }
            let tile1 = neighbour(tile, next), tile2 = neighbour(tile, next2)
            if !same(tile2) {
                // A small corner.
                path.append(.line(bp[next]!.0, bp[next]!.1))
                path.append(.quad(cp[next]!.0, cp[next]!.1, bp[next2]!.0, bp[next2]!.1))
                continue
            }
            let (dx, dy): (Float, Float)
            switch d {
            case .nw: (dx, dy) = (hw, -hh)
            case .ne: (dx, dy) = (hw, hh)
            case .se: (dx, dy) = (-hw, hh)
            default: (dx, dy) = (-hw, -hh)
            }
            if same(tile1) {
                // A short straight line, and a big corner.
                path.append(.line(bp[next]!.0, bp[next]!.1))
                let previous = d.previousDirection, previous2 = previous.previousDirection
                let (ddx, ddy): (Float, Float)
                switch d {
                case .nw: (ddx, ddy) = (0, -h)
                case .ne: (ddx, ddy) = (w, 0)
                case .se: (ddx, ddy) = (0, h)
                default: (ddx, ddy) = (-w, 0)
                }
                path.append(.quad(cp[previous]!.0 + dx, cp[previous]!.1 + dy,
                                  bp[previous2]!.0 + ddx, bp[previous2]!.1 + ddy))
            } else {
                // A straight line.
                path.append(.line(bp[d]!.0 + dx, bp[d]!.1 + dy))
            }
        }
        return path
    }

    // MARK: Forests

    /// The corners of forests on neighbouring tiles that reach over a
    /// tile without a forest or river (drawForestCornerImages), by key.
    func forestCorners(_ t: TileSnapshot) -> [(key: String, corner: Direction)] {
        if river(t) != nil { return [] }
        var ret: [(key: String, corner: Direction)] = []
        for (d1, d2, d3) in [(Direction.nw, Direction.ne, Direction.n), (.sw, .se, .s), (.ne, .se, .e), (.nw, .sw, .w)] {
            guard let t1 = neighbour(t, d1), t1.isForested, let t2 = neighbour(t, d2), t2.isForested,
                  t1.typeId == t2.typeId, let typeId = t1.typeId else { continue }
            let key = "image.tileforest." + typeId + "." + d3.javaName.lowercased()
            if images.hasImage(key) { ret.append((key, d3)) }
        }
        return ret
    }
}

extension Array where Element == MapPathSegment {
    /// A move, which replaces a move just before it, as Java's
    /// Path2D.moveTo does.
    mutating func moveTo(_ x: Float, _ y: Float) {
        if case .move = last { removeLast() }
        append(.move(x, y))
    }
}

extension Direction {
    /// Java's ordinal: N, NE, E, SE, S, SW, W, NW.
    var javaOrdinal: Int { Direction.allDirections.firstIndex(of: self) ?? 0 }
}

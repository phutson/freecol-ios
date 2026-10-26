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
import FreeColUtil

/// One tile of a river, with the branches it connects to
/// (server/generator/RiverSection).
final class RiverSection {

    private var branches: [Direction: Int] = [:]
    private(set) var size = TileImprovement.smallRiver
    var direction: Direction
    let tile: Tile

    init(_ tile: Tile, _ direction: Direction) {
        self.tile = tile
        self.direction = direction
        setBranch(direction, TileImprovement.smallRiver)
    }

    /// Set a branch; anything but small is large.
    func setBranch(_ direction: Direction, _ size: Int) {
        branches[direction] = size != TileImprovement.smallRiver ? TileImprovement.largeRiver : size
    }

    private func branch(_ direction: Direction) -> Int {
        branches[direction] ?? TileImprovement.noRiver
    }

    /// The river grows downstream of a joining one.
    func grow() {
        size += 1
        setBranch(direction, TileImprovement.largeRiver)
    }

    /// The river's style: a digit per long side.
    func encodeStyle() -> String {
        Direction.longSides.map { String(branch($0), radix: 36) }.joined()
    }
}

/// A river, flowing from a source to the sea or another river
/// (server/generator/River).
final class River {

    /// Which way the river turns (River.DirectionChange).
    private enum DirectionChange: CaseIterable {
        case straightAhead, rightTurn, leftTurn

        func newDirection(_ old: Direction) -> Direction {
            switch self {
            case .straightAhead:
                return old
            case .rightTurn:
                switch old {
                case .ne: return .se
                case .se: return .sw
                case .sw: return .nw
                case .nw: return .ne
                default: return old
                }
            case .leftTurn:
                switch old {
                case .ne: return .nw
                case .se: return .ne
                case .sw: return .se
                case .nw: return .sw
                default: return old
                }
            }
        }
    }

    private let riverType: TileImprovementType
    private var direction: Direction
    private let map: Map
    private(set) var sections: [RiverSection] = []
    private var nextRiver: River?
    private(set) var region: Region
    private let random: JavaRandom
    /// Which river each tile is in, shared by the rivers of a map.
    private let riverMap: RiverMap
    private var connected = false

    /// The rivers by tile (Java's HashMap<Tile, River>).
    final class RiverMap {
        private var rivers: [ObjectIdentifier: River] = [:]
        var count: Int { rivers.count }
        subscript(tile: Tile) -> River? {
            get { rivers[ObjectIdentifier(tile)] }
            set { rivers[ObjectIdentifier(tile)] = newValue }
        }
    }

    init(_ map: Map, _ riverMap: RiverMap, _ region: Region, _ random: JavaRandom) {
        self.map = map
        self.riverMap = riverMap
        self.region = region
        self.random = random
        riverType = map.specification!.getTileImprovementType("model.improvement.river")!
        direction = RandomUtils.randomMember("River", Direction.longSides, random)!
    }

    var length: Int { sections.count }

    var lastSection: RiverSection { sections[sections.count - 1] }

    /// A river joins this one at a tile: it grows from there down.
    private func grow(_ lastSection: RiverSection, _ tile: Tile?) {
        var found = false
        for section in sections {
            if found {
                section.grow()
            } else if section.tile === tile {
                section.setBranch(lastSection.direction.reverseDirection, lastSection.size)
                section.grow()
                found = true
            }
        }
        drawToMap(sections)
        if let nextRiver {
            let section = sections[sections.count - 1]
            nextRiver.grow(section, section.tile.neighbour(section.direction))
        }
    }

    private func isNextToSelf(_ tile: Tile) -> Bool {
        Direction.longSides.contains { contains(tile.neighbour($0)) }
    }

    private func isNextToWater(_ tile: Tile) -> Bool {
        Direction.longSides.contains { d in
            guard let t = tile.neighbour(d) else { return false }
            return !t.isLand || t.hasRiver
        }
    }

    private func contains(_ tile: Tile?) -> Bool {
        sections.contains { $0.tile === tile }
    }

    /// Start a river at a tile, which must allow one and not be beside
    /// water.
    ///
    /// - Returns: Whether a river was made.
    func flowFromSource(_ tile: Tile) -> Bool {
        guard let type = tile.type, riverType.isTileTypeAllowed(type) else { return false }
        if isNextToWater(tile) { return false }
        return flow(tile)
    }

    /// Flow from a tile until the sea or another river.
    private func flow(_ start: Tile) -> Bool {
        var source = start
        flowing: while true {
            if sections.count % 2 == 0 {
                // Turn, perhaps, every second tile.
                let index = Int(RandomUtils.randomInt("Flow", random, Int32(DirectionChange.allCases.count)))
                direction = DirectionChange.allCases[index].newDirection(direction)
            }
            for change in DirectionChange.allCases {
                let dir = change.newDirection(direction)
                guard let nextTile = source.neighbour(dir), let nextType = nextTile.type else { continue }
                // Allowed, not going back, not beside itself.
                if !riverType.isTileTypeAllowed(nextType) || contains(nextTile) || isNextToSelf(nextTile) {
                    continue
                }
                // Is the tile after that water or a river?
                for change2 in DirectionChange.allCases {
                    let lastDir = change2.newDirection(dir)
                    guard let t = nextTile.neighbour(lastDir) else { continue }
                    if t.isLand && !t.hasRiver { continue }
                    sections.append(RiverSection(source, dir))
                    let lastSection = RiverSection(nextTile, lastDir)
                    sections.append(lastSection)
                    if t.hasRiver && t.isLand {
                        // It joins another river.
                        nextRiver = riverMap[t]
                        nextRiver!.grow(lastSection, t)
                        connected = connected || nextRiver!.connected
                        if length < 10 { region = nextRiver!.region }
                        drawToMap(sections)
                    } else {
                        // It reaches water.
                        if let someRiver = riverMap[t] {
                            someRiver.lastSection.setBranch(lastDir.reverseDirection, TileImprovement.smallRiver)
                        } else {
                            sections.append(RiverSection(t, lastDir.reverseDirection))
                            if lastSection.size < TileImprovement.fjordRiver {
                                createDelta(nextTile, lastDir, lastSection)
                            }
                        }
                        connected = connected || t.isHighSeasConnected
                        drawToMap(sections)
                    }
                    return true
                }
                // Keep going.
                sections.append(RiverSection(source, dir))
                source = nextTile
                continue flowing
            }
            // Nowhere to go.
            sections = []
            return false
        }
    }

    private func createDelta(_ tile: Tile, _ direction: Direction, _ section: RiverSection) {
        delta(tile, direction, section, DirectionChange.leftTurn.newDirection(direction))
        delta(tile, direction, section, DirectionChange.rightTurn.newDirection(direction))
    }

    private func delta(_ tile: Tile, _ direction: Direction, _ section: RiverSection, _ d: Direction) {
        guard let t = tile.neighbour(d) else { return }
        if !t.isLand {
            section.setBranch(d, TileImprovement.smallRiver)
            drawToMap([RiverSection(tile, d.reverseDirection)])
        } else if let tt = t.type, riverType.isTileTypeAllowed(tt) {
            guard let t2 = t.neighbour(direction) else { return }
            if !t2.isLand && RandomUtils.randomInt("Delta", random, 2) == 0 {
                section.setBranch(d, TileImprovement.smallRiver)
                let rs = RiverSection(t, direction)
                rs.setBranch(d.reverseDirection, TileImprovement.smallRiver)
                drawToMap([rs, RiverSection(t2, direction.reverseDirection)])
            }
        }
    }

    /// Put the sections on the map, as rivers (or great rivers).
    private func drawToMap(_ sections: [RiverSection]) {
        var oldSection: RiverSection?
        let enableGreatRivers = map.specification?.getBoolean(MapGeneratorOptions.enableGreatRivers) ?? false
        for section in sections {
            riverMap[section.tile] = self
            if let oldSection {
                section.setBranch(oldSection.direction.reverseDirection, oldSection.size)
            }
            let tile = section.tile
            if tile.isLand {
                if enableGreatRivers && section.size >= TileImprovement.fjordRiver {
                    tile.changeType(map.specification?.getTileType("model.tile.greatRiver"))
                } else if section.size > TileImprovement.noRiver {
                    tile.addRiver(min(section.size, TileImprovement.largeRiver), section.encodeStyle())
                }
                region.addTile(tile)
                oldSection = section
            }
        }
    }
}

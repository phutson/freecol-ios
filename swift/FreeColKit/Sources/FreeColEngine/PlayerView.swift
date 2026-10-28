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
import FreeColXML

// What Java's client decides as a player plays on the map, made on the
// player's copy of the game, as the server would send it: which unit
// to offer next, what a move would do, the paths a goto would take, and
// which unit actions are open.

/// Where a step of a path is.
public enum PathPlace: Sendable, Equatable, Hashable {
    case tile(MapPosition)
    case europe
    /// Aboard the carrier with this identifier, on a tile or not.
    case carrier(String, MapPosition?)
}

/// A step of a path: where, and the turns taken and moves left on
/// reaching it (PathNode).
public struct PathStep: Sendable, Equatable, Hashable {
    public let place: PathPlace
    public let turns: Int
    public let movesLeft: Int
    /// The direction moved in to get here (N, NE...), if by a move on
    /// the map.
    public let direction: String?

    /// The tile it is on, if any (for a carrier, the carrier's).
    public var tile: MapPosition? {
        switch place {
        case .tile(let p): p
        case .carrier(_, let p): p
        case .europe: nil
        }
    }
}

/// A unit's path, from where it is.
public struct UnitPath: Sendable, Equatable {
    public let steps: [PathStep]

    public var destination: PathStep? { steps.last }
}

/// Which of the map controls' unit actions are open to a unit
/// (ActionManager.makeUnitActionButtons, and loading, unloading and
/// going to a tile), as their shouldBeEnabled decide on the player's
/// turn.  Waiting, skipping, sentry and disbanding are always open to
/// a unit of the player's.
public struct UnitActions: Sendable, Equatable {
    public var attackRanged = false
    public var fortify = false
    /// By the improvement type's suffix ("plow", "road",
    /// "clearForest"), for the types that are not natural.
    public var improvements: [String: Bool] = [:]
    /// Found a colony, or join the one here.
    public var buildColony = false
    public var load = false
    public var unload = false
    public var gotoTile = false

    public init() {}
}

/// The game as a player's client holds it.
final class PlayerView {
    let game: Game
    let player: Player

    /// Read the player's copy of a game, as the server sends it.
    init(of serverGame: Game, for serverPlayer: Player) throws {
        let xr = try FreeColXMLReader(string: serverGame.serialize(.toClient(serverPlayer)))
        try xr.nextTag()
        let game = Game(specification: nil)
        game.isClientCopy = true
        try game.readFromXML(xr)
        guard let id = serverPlayer.id, let player = game.getFreeColGameObject(id, as: Player.self) else {
            throw FreeColXMLError("No player \(serverPlayer.id ?? "") in its copy of the game")
        }
        self.game = game
        self.player = player
    }

    func unit(_ id: String) -> Unit? {
        guard let unit = game.getFreeColGameObject(id, as: Unit.self), player.owns(unit) else { return nil }
        return unit
    }

    func tile(_ p: MapPosition) -> Tile? {
        game.map?.tile(p.x, p.y)
    }

    /// What a move in each direction would do (Unit.getMoveType), by
    /// Java's names, north first and clockwise.
    func moveTypes(_ unit: Unit) -> [Unit.MoveType] {
        Direction.allDirections.map { unit.moveType($0) }
    }

    /// The path the goto cursor shows to a tile (SwingGUI.updateGotoTile):
    /// none to the unit's own tile, an unexplored one, or one the unit
    /// could not legally move to directly.
    func gotoPath(_ unit: Unit, to tile: Tile) -> UnitPath? {
        guard unit.tile !== tile, tile.isExplored, unit.simpleMoveType(tile).isLegal else { return nil }
        return Self.path(unit.findPath(tile))
    }

    /// The path to the unit's destination, if it has one it is not at
    /// (SwingGUI.updateUnitPath).
    func destinationPath(_ unit: Unit) -> UnitPath? {
        guard let destination = unit.destination, !unit.isAtLocation(destination) else { return nil }
        return Self.path(unit.findPath(destination))
    }

    /// The path to Europe.
    func europePath(_ unit: Unit) -> UnitPath? {
        guard let europe = player.europe else { return nil }
        return Self.path(unit.findPath(europe))
    }

    /// The unit actions open to a unit of the player's.
    func actions(_ unit: Unit) -> UnitActions {
        var a = UnitActions()
        a.attackRanged = (unit.type?.attackRange ?? 0) > 0 && unit.movesLeft > 0 && unit.isOffensiveUnit
        a.fortify = unit.checkSetState(.fortifying)
        let tile = unit.tile
        for type in game.specification?.tileImprovementTypeList ?? [] where !type.isNatural {
            a.improvements[type.suffix ?? ""] = tile?.isImprovementTypeAllowed(type) == true
                && type.isWorkerAllowed(unit) && unit.checkSetState(.improving)
        }
        a.buildColony = unit.hasTile && (unit.canBuildColony || (tile?.colony != nil && unit.type?.hasSkill == true))
        a.load = unit.isCarrier && unit.hasSpaceLeft
        a.unload = unit.isCarrier && unit.cargoSpaceTaken > 0
        a.gotoTile = unit.hasTile
        return a
    }

    /// What may be wrong with founding a colony here
    /// (Tile.getBuildColonyWarnings): landlocked, too little food or
    /// building materials, land already used or claimed.
    static func buildColonyWarnings(_ tile: Tile, _ unit: Unit) -> [StringTemplate] {
        guard let spec = tile.specification, let tileType = tile.type else { return [] }
        let owner = unit.owner
        var landLocked = true
        var ownedByEuropeans = false, ownedBySelf = false, ownedByIndians = false
        // The building and food goods, with what could be made of them,
        // in Java's hash order.
        var goods = JavaHashMap<GoodsType, Int>(javaHash: { JavaString.hashCode($0.id ?? "") })
        for var goodsType in spec.goodsTypeList {
            if goodsType.isBuildingMaterial {
                while goodsType.isRefined, let input = goodsType.inputType { goodsType = input }
            } else if !goodsType.isFoodType {
                continue
            }
            _ = goods.put(goodsType, 0)
        }
        // The best this tile makes unattended.
        for productionType in tileType.availableProductionTypes(unattended: true) {
            for ag in productionType.outputs {
                guard let goodsType = ag.type, let old = goods[goodsType] else { continue }
                let potential = tile.potentialProduction(goodsType, nil)
                if potential > old { _ = goods.put(goodsType, potential) }
            }
        }
        // And what the tiles round it would make worked.
        let worker = spec.defaultUnitType(owner?.nationType)
        for t in tile.surroundingTiles(1, 1) {
            if !t.isLand { landLocked = false }
            for (goodsType, amount) in goods.entries {
                _ = goods.put(goodsType, amount + t.potentialProduction(goodsType, worker))
            }
            let tileOwner = t.owner
            if owner === tileOwner {
                if t.owningSettlement != nil {
                    ownedBySelf = true
                } else if t.surroundingTiles(1, 1).contains(where: { $0.colony != nil && $0.colony?.owner === owner }) {
                    ownedBySelf = true
                }
            } else if let tileOwner, tileOwner.isEuropean {
                ownedByEuropeans = true
            } else if tileOwner != nil {
                ownedByIndians = true
            }
        }
        var ret: [StringTemplate] = []
        if landLocked { ret.append(.key("warning.landLocked")) }
        if goods.entries.filter({ $0.key.isFoodType }).reduce(0, { $0 + $1.value }) < 8 {
            ret.append(.key("warning.noFood"))
        }
        for (goodsType, amount) in goods.entries where !goodsType.isFoodType && amount < 4 {
            ret.append(StringTemplate.template("warning.noBuildingMaterials").addNamed("%goods%", goodsType))
        }
        if ownedBySelf { ret.append(.key("warning.ownLand")) }
        if ownedByEuropeans { ret.append(.key("warning.europeanLand")) }
        if ownedByIndians { ret.append(.key("warning.nativeLand")) }
        return ret
    }

    static func path(_ node: PathNode?) -> UnitPath? {
        guard let node else { return nil }
        var steps: [PathStep] = []
        var p: PathNode? = node
        while let n = p {
            let place: PathPlace
            if let t = n.location as? Tile {
                place = .tile(MapPosition(x: t.x, y: t.y))
            } else if n.location is Europe {
                place = .europe
            } else {
                place = .carrier(n.location?.id ?? "", n.tile.map { MapPosition(x: $0.x, y: $0.y) })
            }
            steps.append(PathStep(place: place, turns: n.turns, movesLeft: n.movesLeft,
                                  direction: n.direction?.javaName))
            p = n.next
        }
        return UnitPath(steps: steps)
    }
}

/// The order the client offers the player's units to move in
/// (Player.getNextActiveUnit, a UnitIterator): round the units still
/// to move, by where they are, and round again once all have been
/// offered.  Kept by identifier, so it lasts while the player's copy
/// of the game is read afresh.
struct ActiveUnitCycle {
    private var waiting: [String] = []

    /// Start again (Player.resetIterators).
    mutating func reset() {
        waiting = []
    }

    /// The next unit to offer, if any can move.
    mutating func next(_ view: PlayerView) -> Unit? {
        if let u = first(view) { return u }
        waiting = view.player.units.filter { $0.isCandidateForNextActiveUnit }
            .stableSorted { $0.rank < $1.rank }.compactMap(\.id)
        return first(view)
    }

    private mutating func first(_ view: PlayerView) -> Unit? {
        while !waiting.isEmpty {
            let id = waiting.removeFirst()
            if let u = view.unit(id), u.isCandidateForNextActiveUnit { return u }
        }
        return nil
    }
}

extension Sequence {
    /// The elements sorted, keeping the order of equal elements (as
    /// Java's sorts do).
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            areInIncreasingOrder(a.element, b.element)
                || (!areInIncreasingOrder(b.element, a.element) && a.offset < b.offset)
        }.map(\.element)
    }
}

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

/// Path finding on the map: the A* search and the path and goal
/// searches built on it (the search part of common/model/Map).
///
/// Not yet ported: search tracing (LogBuilder output).
extension Map {

    /// A heuristic for the A* search: an estimate of the cost to the
    /// goal from a tile (zero gives Dijkstra's algorithm).
    typealias SearchHeuristic = (Tile) -> Int

    /// The destination a path really ends at: Europe, or a tile.
    private func findRealEnd(_ unit: Unit?, _ end: (any Location)?) -> (any Location)? {
        var end = end
        while true {
            guard let e = end else { preconditionFailure("Null end for: \(String(describing: unit))") }
            if e is Europe { return e }
            if e is Map {
                end = unit?.fullEntryLocation
            } else if let tile = e.tile {
                return tile
            } else if let unit {
                return unit.resolveDestination()
            } else {
                preconditionFailure("Invalid end: \(e)")
            }
        }
    }

    /// A path to the best place for a unit to arrive on the map from
    /// Europe, to reach a tile.
    private func bestEntryPath(_ unit: Unit?, _ tile: Tile, _ carrier: Unit?,
                               _ costDecider: CostDecider?) -> PathNode? {
        searchMap(unit, tile, GoalDeciders.highSeas(),
                  costDecider ?? CostDeciders.avoidSettlementsAndBlockingUnits(),
                  Constants.infinity, carrier, nil)
    }

    /// The best tile for a unit to arrive on the map at from Europe, to
    /// reach a tile.
    public func bestEntryTile(_ unit: Unit?, _ tile: Tile, _ carrier: Unit?,
                              _ costDecider: CostDecider?) -> Tile? {
        bestEntryPath(unit, tile, carrier, costDecider)?.lastNode.tile
    }

    /// The quickest path between two tiles, with a carrier if given.
    private func findMapPath(_ unit: Unit?, _ start: Tile, _ end: Tile, _ carrier: Unit?,
                             _ costDecider: CostDecider?) -> PathNode? {
        let offMapUnit = carrier ?? ((unit?.isNaval ?? false) ? unit : nil)
        let gd = GoalDeciders.location(end)
        let sh: SearchHeuristic = { $0.distance(to: end) }

        if start.contiguity == end.contiguity {
            // Could get there without a carrier: try both ways, as
            // carrying is sometimes faster (mounted units, roads).
            var path = searchMap(unit, start, gd, costDecider, Constants.infinity, nil, sh)
            let carrierPath = carrier == nil ? nil
                : searchMap(unit, start, gd, costDecider, Constants.infinity, carrier, sh)
            if let carrierPath, path == nil || path!.lastNode.cost > carrierPath.lastNode.cost {
                path = carrierPath
            }
            return path
        }
        if offMapUnit != nil {
            // With an off map unit, paths through settlements and lakes
            // are possible that contiguity does not show, so search.
            return searchMap(unit, start, gd, costDecider, Constants.infinity, carrier, sh)
        }
        if let unit, unit.isOnCarrier, !start.isLand, end.isLand,
           !start.contiguityAdjacent(end.contiguity).isEmpty {
            // A land unit moving off a ship to adjacent land.
            return searchMap(unit, start, gd, costDecider, Constants.infinity, carrier, sh)
        }
        if let unit, start.isLand, !end.isLand, let endUnit = end.firstUnit,
           unit.owner?.owns(endUnit) ?? false,
           !end.contiguityAdjacent(start.contiguity).isEmpty,
           let embarkTo = end.carrier(for: unit) {
            // A land unit moving from land to an adjacent ship.
            let path = searchMap(unit, start, GoalDeciders.adjacentLocation(end)!, costDecider,
                                 Constants.infinity, nil, nil)
            if let path {
                let last = path.lastNode
                last.next = PathNode(embarkTo, 0, last.turns + 1, true, last, nil)
            }
            return path
        }
        // Otherwise there is no connection.
        return nil
    }

    /// Add the turns left on the high seas.
    private func finishPath(_ path: PathNode?, _ unit: Unit?) {
        guard let path, let unit, unit.isAtSea else { return }
        let initialTurns = (unit.isOnCarrier ? unit.carrier! : unit).workLeft
        if initialTurns != 0 { path.addTurns(initialTurns) }
    }

    /// The quickest path for a unit (with an optional carrier) from one
    /// location to another.
    ///
    /// - Parameter costDecider: The costs, or the unit's defaults.
    /// - Returns: A path from the start to the end, or nil.
    public func findPath(_ unit: Unit?, _ start: any Location, _ end: (any Location)?,
                         _ carrier: Unit?, _ costDecider: CostDecider?) -> PathNode? {
        // Reduce the end to Europe or a tile.
        let realEnd = findRealEnd(unit, end)
        // The unit for off map travel.
        let offMapUnit = carrier ?? unit
        var path: PathNode?

        if let endTile = realEnd as? Tile, !endTile.isExplored {
            // No path into unexplored territory, whose costs are
            // unknown, unless it borders explored land of the start's
            // contiguity.
            let closest = (start as? Tile).flatMap { st in
                closestTile(st, endTile.surroundingTiles(1, 1).filter {
                    $0.isExplored && Map.isSameContiguity($0, st)
                })
            }
            path = closest.flatMap { findPath(unit, start, $0, carrier, costDecider) }
            if let path {
                let last = path.lastNode
                last.next = PathNode(endTile, 0, last.turns + 1, last.isOnCarrier, last, nil)
            }
        } else if start is Europe && realEnd is Europe {
            // Europe to Europe: a trivial path.
            path = PathNode(start, unit?.movesLeft ?? 0, 0, false, nil, nil)
        } else if start is Europe, let endTile = realEnd as? Tile {
            // Europe to a tile: find where to enter the map, then search
            // on from there (costs are not symmetric).
            if let offMapUnit, offMapUnit.type?.canMoveToHighSeas ?? false,
               let p = bestEntryPath(unit, endTile, carrier, costDecider),
               let entry = p.lastNode.tile,
               let found = findMapPath(unit, entry, endTile, carrier, costDecider) {
                // Start with a node in Europe, after the sailing time.
                found.addTurns(offMapUnit.sailTurns)
                var head = PathNode(start, unit?.movesLeft ?? 0, 0, carrier != nil, nil, found)
                found.previous = head
                if let carrier, unit?.location !== carrier {
                    let before = PathNode(start, unit?.movesLeft ?? 0, 0, false, nil, head)
                    head.previous = before
                    head = before
                }
                path = head
            }
        } else if let startTile = start as? Tile, realEnd is Europe {
            // A tile to Europe: search for the high seas.
            if let offMapUnit, offMapUnit.type?.canMoveToHighSeas ?? false,
               let p = searchMap(unit, startTile, GoalDeciders.highSeas(), costDecider,
                                 Constants.infinity, carrier, nil) {
                let last = p.lastNode
                last.next = PathNode(realEnd, unit?.initialMovesLeft ?? 0, last.turns + offMapUnit.sailTurns,
                                     last.isOnCarrier, last, nil)
                path = p
            }
        } else if let startTile = start as? Tile, let endTile = realEnd as? Tile {
            // Tile to tile, short circuiting a blocked neighbour.
            if let unit, let d = startTile.direction(to: endTile), case let mt = unit.moveType(d),
               mt.isLegal, !mt.isProgress {
                let head = PathNode(start, unit.movesLeft, 0, carrier != nil, nil, nil)
                let cost = unit.moveCost(startTile, endTile, unit.movesLeft)
                head.next = PathNode(realEnd, unit.movesLeft - cost, 0, false, head, nil)
                path = head
            } else {
                path = findMapPath(unit, startTile, endTile, carrier, costDecider)
            }
        } else {
            preconditionFailure("Can not happen: \(start), \(String(describing: realEnd))")
        }
        finishPath(path, unit)
        return path
    }

    /// Search for a goal.  Units in Europe start from their entry
    /// location.
    ///
    /// - Returns: The path to a goal, or nil.
    public func search(_ unit: Unit?, _ start: any Location, _ goalDecider: GoalDecider,
                       _ costDecider: CostDecider?, _ maxTurns: Int, _ carrier: Unit?) -> PathNode? {
        let offMapUnit = carrier ?? unit
        var path: PathNode?
        if start is Europe {
            // Not optimal: start from the standard entry location, then
            // find the best path to where that search ended.
            if let offMapUnit, offMapUnit.type?.canMoveToHighSeas ?? false,
               let entry = offMapUnit.fullEntryLocation,
               let p = searchMap(unit, entry, goalDecider, costDecider, maxTurns, carrier, nil) {
                path = findPath(unit, start, p.lastNode.tile, carrier, costDecider)
            }
        } else if let tile = start.tile {
            path = searchMap(unit, tile, goalDecider, costDecider, maxTurns, carrier, nil)
        }
        finishPath(path, unit)
        return path
    }

    /// Whether a carrier was used earlier on a partly built path.
    private func usedCarrier(_ path: PathNode?) -> Bool {
        var p = path
        while let n = p {
            if n.isOnCarrier { return true }
            p = n.previous
        }
        return false
    }

    /// A candidate move in the search, costed by a cost decider.
    private final class MoveCandidate {
        let current: PathNode
        let dst: any Location
        var movesLeft: Int
        var turns: Int
        let onCarrier: Bool
        var cost: Int

        init(_ unit: Unit?, _ current: PathNode, _ dst: any Location, _ movesLeft: Int, _ turns: Int,
             _ onCarrier: Bool, _ decider: CostDecider?) {
            self.current = current
            self.dst = dst
            self.movesLeft = movesLeft
            self.turns = turns
            self.onCarrier = onCarrier
            let cd = decider ?? CostDeciders.defaultCostDecider(for: unit)
            cost = cd.cost(unit, current.location, dst, movesLeft)
            if cost == CostDeciderConstants.illegalMove {
                // Routing through short stretches of unexplored tiles is
                // allowed, but costed conservatively (BR#3153): all the
                // moves and two more turns.
                if let tile = dst.tile, !tile.isExplored {
                    self.turns += 2
                    self.movesLeft = 0
                    cost = PathNode.nodeCost(self.turns, self.movesLeft)
                } else {
                    self.turns = Constants.infinity
                    self.movesLeft = 0
                    cost = Constants.infinity
                }
            } else {
                self.turns += cd.newTurns
                self.movesLeft = cd.movesLeft
                cost = PathNode.nodeCost(self.turns, self.movesLeft)
            }
        }

        /// Boarding a carrier: its moves, and another turn.
        func embarkUnit(_ unit: Unit) {
            movesLeft = unit.initialMovesLeft
            turns += 1
            cost = PathNode.nodeCost(turns, movesLeft)
        }

        func canImprove(_ best: PathNode?) -> Bool {
            best == nil || cost < best!.cost
        }
    }

    private enum MoveStep {
        case byLand, byWater, embark, disembark, fail
    }

    /// The A* search for a goal from a start tile, with a heuristic (or
    /// Dijkstra's algorithm without one).
    ///
    /// The open nodes are in a map by location for membership and in
    /// Java's priority queue by cost plus heuristic, so ties are broken
    /// as Java breaks them.
    func searchMap(_ unit: Unit?, _ start: Tile, _ goalDecider: GoalDecider, _ costDecider: CostDecider?,
                   _ maxTurns: Int, _ carrier: Unit?, _ searchHeuristic: SearchHeuristic?) -> PathNode? {
        // Values that do not change during the search are cached (and
        // nested searches, from goal deciders, share the cache).
        let outerCache = SearchCache.current
        if outerCache == nil { SearchCache.current = SearchCache() }
        defer { if outerCache == nil { SearchCache.current = nil } }
        // Keyed by location, as Java keys them by location id.
        var openMap: [ObjectIdentifier: PathNode] = [:]
        var closedMap: [ObjectIdentifier: PathNode] = [:]
        var f: [ObjectIdentifier: Int] = [:]
        // Every node made, kept until the search ends: PathNode's link
        // back is weak, and a node replaced by a better one may still be
        // the previous node of others, as in Java.
        var allNodes: [PathNode] = []
        var openMapQueue = JavaPriorityQueue<PathNode> { a, b in
            let fa = f[ObjectIdentifier(a.location!)] ?? 0, fb = f[ObjectIdentifier(b.location!)] ?? 0
            return fa < fb ? -1 : fa > fb ? 1 : 0
        }
        let sh: SearchHeuristic = searchHeuristic ?? { _ in 0 }
        let offMapUnit = carrier ?? unit
        var currentUnit: Unit? = start.isLand
            ? ((unit != nil && unit!.location === carrier && start.hasSettlement
                && (start.settlement?.isConnectedPort ?? false)) ? carrier : unit)
            : offMapUnit

        // The start node.
        let firstNode = PathNode(start, currentUnit?.movesLeft ?? -1, 0,
                                 carrier != nil && currentUnit === carrier, nil, nil)
        allNodes.append(firstNode)
        let startId = ObjectIdentifier(start)
        f[startId] = sh(start)
        openMap[startId] = firstNode
        openMapQueue.offer(firstNode)

        // Add a candidate to the open map and queue, replacing any open
        // node for its location.
        func improve(_ move: MoveCandidate) {
            let id = ObjectIdentifier(move.dst)
            if let best = openMap[id] {
                openMap[id] = nil
                openMapQueue.remove(best)
            }
            var fcost = move.cost
            if let tile = move.dst.tile { fcost += sh(tile) }
            f[id] = fcost
            let path = PathNode(move.dst, move.movesLeft, move.turns, move.onCarrier, move.current, nil)
            allNodes.append(path)
            openMap[id] = path
            openMapQueue.offer(path)
        }

        var bestScore = Constants.infinity
        search: while !openMap.isEmpty {
            // The node with the lowest f.
            let currentNode = openMapQueue.poll()!
            let currentId = ObjectIdentifier(currentNode.location!)
            openMap[currentId] = nil

            // The unit for this node.
            currentUnit = currentNode.isOnCarrier ? carrier : unit

            // Success?
            if goalDecider.check(currentUnit, currentNode) {
                guard let best = goalDecider.goal, goalDecider.hasSubGoals else { break search }
                bestScore = best.cost
                continue
            }

            closedMap[currentId] = currentNode

            // Skip nodes that can not beat the best path, or are over
            // the turn limit.
            if bestScore < currentNode.cost { continue }
            if currentNode.turns > maxTurns { continue }

            let currentMovesLeft = currentNode.movesLeft
            let currentTurns = currentNode.turns
            let currentOnCarrier = currentNode.isOnCarrier
            // Without a tile, the node is in Europe: tiles "next to"
            // Europe are not considered yet.
            guard let currentTile = currentNode.tile else { continue }

            for moveTile in currentTile.surroundingTiles(1) {
                // Skip the tile just visited.
                if let prev = currentNode.previous, prev.tile === moveTile { continue }
                // Skip neighbours already cheaper.
                let closed = closedMap[ObjectIdentifier(moveTile)]
                if let closed, closed.cost <= currentNode.cost { continue }

                let umt = unit!.simpleMoveType(currentTile, moveTile)
                var unitMove = umt.isProgress
                let carrierMove = carrier.map { $0.simpleMoveType($0.tile, moveTile).isProgress } ?? false
                var move: MoveCandidate

                // A move to the goal?  The fake high cost keeps the goal
                // decider from caching this as the best path.
                let probe = PathNode(moveTile, 0, Constants.infinity / 2, false, currentNode, nil)
                allNodes.append(probe)
                let isGoal = goalDecider.check(unit, probe)
                if isGoal {
                    if unitMove {
                        if moveTile.hasSettlement && currentOnCarrier && carrierMove {
                            // A goal settlement reached by carrier: dock.
                            move = MoveCandidate(carrier, currentNode, moveTile, currentMovesLeft,
                                                 currentTurns, true, CostDeciders.tileCost())
                        } else {
                            // Otherwise the unit completes the path.
                            let left = currentOnCarrier
                                ? (currentNode.embarkedThisTurn(currentTurns) ? 0 : unit!.initialMovesLeft)
                                : currentMovesLeft
                            move = MoveCandidate(unit, currentNode, moveTile, left, currentTurns, false,
                                                 CostDeciders.tileCost())
                        }
                    } else {
                        // Moves that do not progress but still do useful
                        // work.
                        switch umt {
                        case .attackUnit, .attackSettlement, .enterForeignColonyWithScout,
                             .enterIndianSettlementWithScout, .enterIndianSettlementWithFreeColonist,
                             .enterIndianSettlementWithMissionary, .enterSettlementWithCarrierAndGoods:
                            // An interaction with the unit or settlement.
                            move = MoveCandidate(unit, currentNode, moveTile, currentMovesLeft, currentTurns,
                                                 false, CostDeciders.tileCost())
                            unitMove = true
                        case .embark:
                            move = MoveCandidate(unit, currentNode, moveTile, currentMovesLeft, currentTurns,
                                                 true, CostDeciders.tileCost())
                            unitMove = true
                        case .moveNoAttackCivilian:
                            // A settlement in the way: this path can
                            // never succeed.
                            if moveTile.hasSettlement {
                                if !goalDecider.hasSubGoals { break search }
                                continue
                            }
                            // A unit in the way: transient, unless it
                            // can be reached this turn or the tile is
                            // hemmed in (a small island or river).
                            if currentNode.turns <= 0 || moveTile.availableAdjacentCount < 3 {
                                if !goalDecider.hasSubGoals { break search }
                                continue
                            }
                            unitMove = true
                            move = MoveCandidate(unit, currentNode, moveTile, currentMovesLeft, currentTurns,
                                                 false, CostDeciders.tileCost())
                        default:
                            // Land units that need a ship, landing that
                            // must disembark first, and so on: try the
                            // other tiles.
                            continue
                        }
                    }
                } else {
                    // An ordinary move, perhaps changing carrier.  Units
                    // do not re-embark, and the carrier is preferred
                    // when both can move (only into a settlement).
                    let step: MoveStep = currentOnCarrier
                        ? (carrierMove ? .byWater : unitMove ? .disembark : .fail)
                        : (carrierMove && !usedCarrier(currentNode)) ? .embark
                        : unitMove ? (unit!.isNaval ? .byWater : .byLand)
                        : .fail
                    switch step {
                    case .byLand:
                        move = MoveCandidate(unit, currentNode, moveTile, currentMovesLeft, currentTurns,
                                             false, costDecider)
                    case .byWater:
                        move = MoveCandidate(offMapUnit, currentNode, moveTile, currentMovesLeft, currentTurns,
                                             currentOnCarrier, costDecider)
                    case .embark:
                        move = MoveCandidate(offMapUnit, currentNode, moveTile, currentMovesLeft, currentTurns,
                                             true, costDecider)
                        move.embarkUnit(carrier!)
                    case .disembark:
                        move = MoveCandidate(unit, currentNode, moveTile, 0, currentTurns, false, costDecider)
                    case .fail:
                        continue
                    }
                }
                if move.cost >= Constants.infinity { continue }
                // Tighten a previously seen case if possible.
                if let closed {
                    if move.canImprove(closed) {
                        closedMap[ObjectIdentifier(moveTile)] = nil
                        improve(move)
                    }
                } else if move.canImprove(openMap[ObjectIdentifier(moveTile)]) {
                    improve(move)
                }
            }
        }

        // Link the path forwards, which was left out while building it.
        guard var best = goalDecider.goal else { return nil }
        while let prev = best.previous {
            prev.next = best
            best = prev
        }
        withExtendedLifetime(allNodes) {}
        return best
    }

    /// Search the tiles within a radius of a start for a goal, without
    /// a unit (so moves are not checked).
    ///
    /// - Returns: The goal's tile, or nil.
    public func searchCircle(_ start: Tile?, _ goalDecider: GoalDecider?, _ radius: Int) -> Tile? {
        guard let start, let goalDecider, radius > 0 else { return nil }
        for t in circleTiles(start, filled: true, radius: radius) {
            let path = PathNode(t, 0, start.distance(to: t), false, nil, nil)
            if goalDecider.check(nil, path) && !goalDecider.hasSubGoals { break }
        }
        return goalDecider.goal?.tile
    }
}

/// Values cached for the length of a path search, which changes nothing
/// they depend on.
final class SearchCache {
    /// The search in progress, if any.  The engine runs in one actor.
    nonisolated(unsafe) static var current: SearchCache?

    var initialMoves: [ObjectIdentifier: Int] = [:]
}

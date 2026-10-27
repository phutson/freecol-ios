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

/// A step on a path: a location, with the moves and turns used to get
/// there and whether the unit is on its carrier (common/model/PathNode).
///
/// A path is held by its first node: each node holds the next one, and
/// the link back to the previous node is weak, as two strong links
/// would never be freed.  Holding only a later node keeps the rest of
/// the path from it, not the earlier nodes.
public final class PathNode: CustomStringConvertible {

    private static let turnFactor = 100

    public let location: (any Location)?
    public var movesLeft: Int
    public var turns: Int
    public var isOnCarrier: Bool
    public var next: PathNode?
    /// Weak, so the nodes are not a cycle.  A node held without the
    /// head of its path can lose it, so the previous node's tile, which
    /// the map holds, is kept for the direction.
    public weak var previous: PathNode? {
        didSet { previousTile = previous?.tile }
    }
    private weak var previousTile: Tile?

    public init(_ location: (any Location)?, _ movesLeft: Int, _ turns: Int, _ onCarrier: Bool,
                _ previous: PathNode?, _ next: PathNode?) {
        self.location = location
        self.movesLeft = movesLeft
        self.turns = turns
        self.isOnCarrier = onCarrier
        self.previous = previous
        previousTile = previous?.tile
        self.next = next
    }

    public var tile: Tile? {
        location?.tile
    }

    /// Add turns to this node and the rest of the path.
    public func addTurns(_ turns: Int) {
        var p: PathNode? = self
        while let n = p {
            n.turns += turns
            p = n.next
        }
    }

    /// The nodes from here to the end.
    public var length: Int {
        var n = 0
        var p: PathNode? = self
        while let node = p {
            n += 1
            p = node.next
        }
        return n
    }

    /// The direction from the previous node's tile to this one's.
    public var direction: Direction? {
        guard let prev = previousTile, let tile else { return nil }
        return prev.map?.direction(prev, tile)
    }

    /// The node where the unit leaves its carrier.
    public var transportDropNode: PathNode {
        var p = self
        while let n = p.next, p.isOnCarrier { p = n }
        return p
    }

    public var firstNode: PathNode {
        var p = self
        while let prev = p.previous { p = prev }
        return p
    }

    public var lastNode: PathNode {
        var p = self
        while let n = p.next { p = n }
        return p
    }

    /// The turns to the end, counting a last node without moves left as
    /// a further turn.
    public var totalTurns: Int {
        let path = lastNode
        return path.movesLeft == 0 ? path.turns + 1 : path.turns
    }

    public var transportDropTurns: Int {
        transportDropNode.turns
    }

    /// The cost of reaching a node: whole turns first, then moves used.
    public static func nodeCost(_ turns: Int, _ movesLeft: Int) -> Int {
        turns >= Constants.infinity / (turnFactor + 1) ? Constants.infinity
            : turnFactor * turns + (turnFactor - movesLeft)
    }

    public var cost: Int {
        PathNode.nodeCost(turns, movesLeft)
    }

    /// The first node from here on a carrier, or nil.
    public var carrierMove: PathNode? {
        var p: PathNode? = self
        while let n = p {
            if n.isOnCarrier { return n }
            p = n.next
        }
        return nil
    }

    public var usesCarrier: Bool {
        firstNode.carrierMove != nil
    }

    /// Whether the unit boarded its carrier this turn.
    public func embarkedThisTurn(_ turns: Int) -> Bool {
        var p: PathNode? = self
        while let n = p {
            if n.turns < turns { return false }
            if !n.isOnCarrier { return true }
            p = n.previous
        }
        return false
    }

    /// Mark the whole path as carried, ending with a disembark.
    public func convertToGoodsDeliveryPath() {
        var p = self
        while let n = p.next {
            p.isOnCarrier = true
            p = n
        }
        p.isOnCarrier = true
        ensureDisembark()
    }

    /// End the path off the carrier.
    public func ensureDisembark() {
        let p = lastNode
        if p.isOnCarrier {
            p.next = PathNode(p.location, p.movesLeft, p.turns, false, p, nil)
        }
    }

    /// Java's toString.
    public var description: String {
        "PathNode loc=\(location?.id ?? "null") movesLeft=\(movesLeft) turns=\(turns)"
            + " onCarrier=\(isOnCarrier) direction=\(direction.map { "\($0)" } ?? "null") cost=\(cost)"
    }

    public var fullPathToString: String {
        var s = ""
        var p: PathNode? = self
        while let n = p {
            s += "\(n)\n"
            p = n.next
        }
        return s
    }
}

// MARK: Cost deciders

/// Decides the cost of a move along a path
/// (common/model/pathfinding/CostDecider).
public protocol CostDecider: AnyObject {
    /// The cost of a move, or illegalMove.  Afterwards movesLeft and
    /// newTurns describe the unit after the move.
    func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
              _ movesLeftBefore: Int) -> Int
    var movesLeft: Int { get }
    var newTurns: Int { get }
}

public enum CostDeciderConstants {
    public static let illegalMove = -1
}

/// The basic cost of moving: illegal moves are refused, special moves
/// and leaving a carrier take the rest of the turn, and a move that
/// costs more than is left takes another turn
/// (common/model/pathfinding/BaseCostDecider).
open class BaseCostDecider: CostDecider {

    public internal(set) var movesLeft = 0
    public internal(set) var newTurns = 0

    public init() {}

    open func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                   _ movesLeftBefore: Int) -> Int {
        let illegal = CostDeciderConstants.illegalMove
        guard let unit, let oldLocation, let newLocation else { return illegal }
        var cost = 0
        newTurns = 0
        let oldTile = oldLocation.tile, newTile = newLocation.tile
        if oldLocation is Europe { // Coming from Europe
            guard !(newLocation is Europe), let newTile, newTile.isDirectlyHighSeasConnected,
                  unit.type?.canMoveToHighSeas ?? false else { return illegal }
            newTurns = unit.sailTurns
            movesLeft = unit.initialMovesLeft
            cost = newTurns * unit.initialMovesLeft
        } else if oldTile == nil {
            return illegal
        } else if newLocation is Europe { // Going to Europe
            guard unit.type?.canMoveToHighSeas ?? false else { return illegal }
            newTurns = unit.sailTurns
            movesLeft = unit.initialMovesLeft
            cost = newTurns * unit.initialMovesLeft
        } else if newTile == nil || !newTile!.isExplored {
            return illegal
        } else { // Moving between tiles
            // Special moves and moving off a carrier take the rest of
            // the turn.
            var consumeMove = false
            switch unit.simpleMoveType(oldTile, newTile) {
            case .moveHighSeas:
                break
            case .attackUnit, .move:
                // Hostile units are ignored here, attacks treated as
                // moves; leaving a carrier takes the turn.
                if unit.isOnCarrier { consumeMove = true }
            case .attackSettlement, .exploreLostCityRumour, .embark,
                 .enterIndianSettlementWithFreeColonist, .enterIndianSettlementWithScout,
                 .enterIndianSettlementWithMissionary, .enterForeignColonyWithScout,
                 .enterSettlementWithCarrierAndGoods:
                consumeMove = true
            default:
                return illegal
            }
            cost = adjust(unit, oldTile!, newTile!, movesLeftBefore)
            if consumeMove {
                cost += movesLeft
                movesLeft = 0
            }
        }
        return cost
    }

    /// The cost of a tile move, taking another turn if needed.
    func adjust(_ unit: Unit, _ oldTile: Tile, _ newTile: Tile, _ movesLeftBefore: Int) -> Int {
        var cost = unit.moveCost(oldTile, newTile, movesLeftBefore)
        if cost <= movesLeftBefore {
            movesLeft = movesLeftBefore - cost
            newTurns = 0
        } else { // This move takes an extra turn to complete
            let initialMoves = unit.initialMovesLeft
            let moveCostNextTurn = unit.moveCost(oldTile, newTile, initialMoves)
            cost = movesLeftBefore + moveCostNextTurn
            movesLeft = initialMoves - moveCostNextTurn
            newTurns = 1
        }
        return cost
    }
}

/// The cost deciders (common/model/pathfinding/CostDeciders).
///
/// Java shares one instance of most deciders, whose moves and turns
/// last only from one cost to the next; here each call makes a new
/// one, which behaves the same.  Not yet ported: serverAvoidIllegal,
/// which needs the players' cached tiles (Phase 3).
public enum CostDeciders {

    /// Every tile costs one.
    final class Trivial: CostDecider {
        var movesLeft: Int { 0 }
        var newTurns: Int { 0 }
        func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                  _ movesLeft: Int) -> Int {
            guard let newLocation else { return CostDeciderConstants.illegalMove }
            if newLocation is Europe { return 1 }
            return newLocation.tile == nil ? CostDeciderConstants.illegalMove : 1
        }
    }

    /// The tile move cost, legal or not.
    final class TileCost: BaseCostDecider {
        override func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                           _ movesLeft: Int) -> Int {
            guard let unit, let oldLocation, let newLocation else { return CostDeciderConstants.illegalMove }
            if newLocation is Europe || oldLocation is Europe { return 1 }
            guard let newTile = newLocation.tile, let oldTile = oldLocation.tile else {
                return CostDeciderConstants.illegalMove
            }
            return adjust(unit, oldTile, newTile, movesLeft)
        }
    }

    /// One for each tile the unit could enter.
    final class LegalTileCount: CostDecider {
        var movesLeft: Int { 0 }
        var newTurns: Int { 1 }
        func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                  _ movesLeft: Int) -> Int {
            guard let newLocation else { return CostDeciderConstants.illegalMove }
            if newLocation is Europe { return 1 }
            guard let tile = newLocation.tile, let unit else { return CostDeciderConstants.illegalMove }
            return unit.isTileAccessible(tile) ? 1 : CostDeciderConstants.illegalMove
        }
    }

    /// The base cost, refusing other players' settlements.
    class AvoidSettlements: BaseCostDecider {
        override func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                           _ movesLeft: Int) -> Int {
            let cost = super.cost(unit, oldLocation, newLocation, movesLeft)
            if cost != CostDeciderConstants.illegalMove && cost != Constants.infinity,
               let settlement = newLocation?.settlement, settlement.owner !== unit?.owner {
                return CostDeciderConstants.illegalMove
            }
            return cost
        }
    }

    /// Also refusing tiles with other players' units, and rumours for
    /// units on trade routes.
    class AvoidSettlementsAndBlockingUnits: AvoidSettlements {
        override func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                           _ movesLeft: Int) -> Int {
            let cost = super.cost(unit, oldLocation, newLocation, movesLeft)
            if cost != CostDeciderConstants.illegalMove && cost != Constants.infinity,
               let tile = newLocation?.tile {
                if let defender = tile.firstUnit, defender.owner !== unit?.owner {
                    return CostDeciderConstants.illegalMove
                } else if unit?.tradeRoute != nil && tile.hasLostCityRumour {
                    return CostDeciderConstants.illegalMove
                }
            }
            return cost
        }
    }

    /// Also ending the move next to a naval threat, and doubling the
    /// cost of tiles a fort can bombard.
    final class AvoidNavalDanger: AvoidSettlementsAndBlockingUnits {
        private static let dangerFactor = 2

        override func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                           _ movesLeft: Int) -> Int {
            var cost = super.cost(unit, oldLocation, newLocation, movesLeft)
            if cost != CostDeciderConstants.illegalMove && cost != Constants.infinity,
               let tile = newLocation?.tile, let unit, let owner = unit.owner {
                let threat = tile.surroundingTiles(1, 1).contains { t in
                    t.unitList.contains { u in
                        !owner.owns(u) && u.isNaval
                            && (u.hasAbility(Ability.piracy)
                                || ((u.owner?.atWar(with: owner) ?? false) && u.isOffensiveUnit))
                    }
                }
                if threat {
                    cost += self.movesLeft
                    self.movesLeft = 0
                    self.newTurns += 1
                }
                if tile.isDangerousToShip(unit) { cost *= AvoidNavalDanger.dangerFactor }
            }
            return cost
        }
    }

    /// Several deciders together: illegal if any is, otherwise the
    /// highest cost so far (Java never resets it between moves, which is
    /// mirrored), with that decider's moves and turns.
    final class Composed: CostDecider {
        private let costDeciders: [CostDecider]
        private var ret = -1
        private var index = -1

        init(_ cds: [CostDecider]) {
            precondition(cds.count >= 2, "Short CostDecider list: \(cds.count)")
            costDeciders = cds
        }

        func cost(_ unit: Unit?, _ oldLocation: (any Location)?, _ newLocation: (any Location)?,
                  _ movesLeft: Int) -> Int {
            for (i, cd) in costDeciders.enumerated() {
                let cost = cd.cost(unit, oldLocation, newLocation, movesLeft)
                if cost == CostDeciderConstants.illegalMove || cost == Constants.infinity {
                    index = i
                    return CostDeciderConstants.illegalMove
                }
                if cost > ret {
                    index = i
                    ret = cost
                }
            }
            return ret
        }

        var movesLeft: Int { index < 0 ? 0 : costDeciders[index].movesLeft }
        var newTurns: Int { index < 0 ? 0 : costDeciders[index].newTurns }
    }

    public static func composed(_ cds: CostDecider...) -> CostDecider {
        Composed(cds)
    }

    /// The usual decider for a unit: ships that can not fight avoid
    /// danger, fighters avoid settlements, others avoid blocking units
    /// too.
    public static func defaultCostDecider(for unit: Unit?) -> CostDecider {
        guard let unit else { return avoidIllegal() }
        if unit.isNaval && !unit.isOffensiveUnit { return avoidNavalDanger() }
        return unit.isOffensiveUnit ? avoidSettlements() : avoidSettlementsAndBlockingUnits()
    }

    public static func numberOfTiles() -> CostDecider { Trivial() }
    public static func tileCost() -> CostDecider { TileCost() }
    public static func numberOfLegalTiles() -> CostDecider { LegalTileCount() }
    public static func avoidIllegal() -> CostDecider { BaseCostDecider() }
    public static func avoidSettlements() -> CostDecider { AvoidSettlements() }
    public static func avoidSettlementsAndBlockingUnits() -> CostDecider { AvoidSettlementsAndBlockingUnits() }
    public static func avoidNavalDanger() -> CostDecider { AvoidNavalDanger() }
}

// MARK: Goal deciders

/// Decides which path nodes are goals of a search
/// (common/model/pathfinding/GoalDecider).  A search stops at a goal
/// unless the decider has sub goals, in which case it goes on looking
/// for a better one.
public protocol GoalDecider: AnyObject {
    /// The best goal found.
    var goal: PathNode? { get }
    /// Whether to keep searching after a goal.
    var hasSubGoals: Bool { get }
    /// Whether a node is a goal (or sub goal).
    func check(_ unit: Unit?, _ pathNode: PathNode) -> Bool
}

/// A goal decider from closures.
final class ClosureGoalDecider: GoalDecider {
    var goal: PathNode?
    let hasSubGoals: Bool
    private let checker: (ClosureGoalDecider, Unit?, PathNode) -> Bool

    init(hasSubGoals: Bool, _ checker: @escaping (ClosureGoalDecider, Unit?, PathNode) -> Bool) {
        self.hasSubGoals = hasSubGoals
        self.checker = checker
    }

    func check(_ unit: Unit?, _ pathNode: PathNode) -> Bool {
        checker(self, unit, pathNode)
    }
}

/// The goal deciders (common/model/pathfinding/GoalDeciders).
public enum GoalDeciders {

    /// The last tile reached that an enemy can not see
    /// (getStealthyGoalDecider).
    public static func stealthy(_ enemy: Player) -> GoalDecider {
        ClosureGoalDecider(hasSubGoals: true) { gd, _, path in
            if enemy.canSee(path.tile) { return false }
            gd.goal = path
            return true
        }
    }

    /// Several deciders together: with `all`, a node must satisfy each;
    /// otherwise any one, and later deciders are not asked once an
    /// earlier one has succeeded.
    public static func composed(all: Bool, _ gds: GoalDecider...) -> GoalDecider {
        precondition(gds.count >= 2, "Short GoalDecider list: \(gds.count)")
        return ComposedGoalDecider(all, gds)
    }

    final class ComposedGoalDecider: GoalDecider {
        private let all: Bool
        private let gds: [GoalDecider]
        private var winner: Int
        private(set) var goal: PathNode?

        init(_ all: Bool, _ gds: [GoalDecider]) {
            self.all = all
            self.gds = gds
            winner = gds.count
        }

        var hasSubGoals: Bool {
            for (i, gd) in gds.enumerated() {
                if !all && i > winner { break }
                if gd.hasSubGoals {
                    if !all { return true }
                } else if all {
                    return false
                }
            }
            return !all
        }

        func check(_ unit: Unit?, _ path: PathNode) -> Bool {
            for (i, gd) in gds.enumerated() {
                if !all && i > winner { break }
                if gd.check(unit, path) {
                    if !all {
                        winner = i
                        goal = path
                        return true
                    }
                } else if all {
                    return false
                }
            }
            if all {
                winner = 0
                goal = path
                return true
            }
            return false
        }
    }

    /// Our settlement with the best value: ports count double, sooner
    /// is better.
    public static func ourClosestSettlement() -> GoalDecider {
        var bestValue: Float = 0
        return ClosureGoalDecider(hasSubGoals: true) { gd, u, path in
            guard let u, let settlement = path.lastNode.location?.settlement,
                  settlement.owner?.owns(u) ?? false else { return false }
            let value = (settlement.isConnectedPort ? 2.0 : 1.0) / Float(path.totalTurns + 1)
            if bestValue < value {
                bestValue = value
                gd.goal = path
                return true
            }
            return false
        }
    }

    /// The cheapest explored high seas tile, free of other players'
    /// units.
    public static func highSeas() -> GoalDecider {
        ClosureGoalDecider(hasSubGoals: false) { gd, u, path in
            guard let tile = path.tile, let u, tile.isExploredBy(u.owner),
                  tile.isDirectlyHighSeasConnected,
                  tile.firstUnit == nil || (u.owner?.owns(tile.firstUnit) ?? false) else { return false }
            if gd.goal == nil || path.cost < gd.goal!.cost {
                gd.goal = path
                return true
            }
            return false
        }
    }

    /// The first high seas tile.
    public static func simpleHighSeas() -> GoalDecider {
        ClosureGoalDecider(hasSubGoals: false) { gd, _, path in
            guard let tile = path.tile, tile.isDirectlyHighSeasConnected else { return false }
            gd.goal = path
            return true
        }
    }

    /// A location, keeping the cheapest way there.
    public static func location(_ target: (any Location)?) -> GoalDecider {
        var bestCost = Constants.infinity
        return ClosureGoalDecider(hasSubGoals: false) { gd, _, path in
            guard Map.isSameLocation(path.location, target) else { return false }
            let cost = path.cost
            if cost < bestCost {
                gd.goal = path
                bestCost = cost
            }
            return true
        }
    }

    /// A tile next to a location, or nil if it is not on the map.
    public static func adjacentLocation(_ target: any Location) -> GoalDecider? {
        guard let tile = target.tile else { return nil }
        return ClosureGoalDecider(hasSubGoals: false) { gd, _, path in
            guard let t = path.tile, t.isAdjacent(tile) else { return false }
            gd.goal = path
            return true
        }
    }

    /// A land settlement of one of some players.
    public static func enemySettlement(_ enemies: [Player]) -> GoalDecider {
        ClosureGoalDecider(hasSubGoals: false) { gd, _, path in
            guard let t = path.tile, t.isLand, let s = t.settlement,
                  enemies.contains(where: { $0 === s.owner }) else { return false }
            gd.goal = path
            return true
        }
    }

    /// The best empty land tile to disembark at near a target: next to
    /// free water leading to the high seas, defensible, close, and away
    /// from hostile forts.
    public static func disembark(_ target: Tile) -> GoalDecider {
        let noDangerBonus = 1000.0
        var bestScore = -1.0
        return ClosureGoalDecider(hasSubGoals: true) { gd, u, pathNode in
            guard let u, let tile = pathNode.tile, tile.isLand, tile.isEmpty, !tile.hasSettlement,
                  let owner = u.owner, let map = u.game?.map else { return false }
            func danger(_ t: Tile) -> Bool {
                guard let settlement = t.settlement else { return false }
                return !owner.owns(settlement) && settlement.hasAbility(Ability.bombardShips)
                    && (owner.atWar(with: settlement.owner) || u.hasAbility(Ability.piracy))
            }
            func score(_ t: Tile) -> Double {
                t.defenceValue / (1.0 + Double(map.distance(target, t)))
                    + (t.surroundingTiles(1, 1).contains(where: danger) ? 0.0 : noDangerBonus)
            }
            // Java's maximize: the first of the best.
            var best: Tile?
            var bestValue = 0.0
            for t in tile.surroundingTiles(1, 1) where t.isHighSeasConnected && !t.isLand {
                let v = score(t)
                if best == nil || v > bestValue {
                    best = t
                    bestValue = v
                }
            }
            if let best, score(best) > bestScore {
                bestScore = score(best)
                gd.goal = pathNode
                return true
            }
            return false
        }
    }

    /// Our settlements ever closer to the high seas.
    public static func reduceHighSeasCount(_ unit: Unit) -> GoalDecider {
        var score = unit.tile?.highSeasCount ?? 0
        return ClosureGoalDecider(hasSubGoals: true) { gd, _, pathNode in
            guard let tile = pathNode.tile, tile.highSeasCount < score,
                  unit.owner?.owns(tile.settlement) ?? false else { return false }
            gd.goal = pathNode
            score = tile.highSeasCount
            return true
        }
    }

    /// River corners ever closer to the high seas.
    public static func corner() -> GoalDecider {
        var score = Int(Int32.max)
        return ClosureGoalDecider(hasSubGoals: true) { gd, _, pathNode in
            guard let tile = pathNode.tile, tile.highSeasCount < score, tile.isRiverCorner else {
                return false
            }
            score = tile.highSeasCount
            gd.goal = pathNode
            return true
        }
    }

    /// Finds the cheapest paths next to each of some locations at once
    /// (GoalDeciders.MultipleAdjacentDecider).  The decider never
    /// succeeds; the paths are in the results.
    public final class MultipleAdjacentDecider {
        public private(set) var goalDecider: GoalDecider!
        /// The paths found, by location, in Java's HashMap order.
        public private(set) var results = JavaHashMap<ObjectIdentifier, (location: any Location, path: PathNode)>(
            javaHash: { _ in 0 })

        public init(_ locs: [any Location]) {
            var hashes: [ObjectIdentifier: Int32] = [:]
            for l in locs {
                hashes[ObjectIdentifier(l)] = (l as? FreeColGameObject)?.javaGameObjectHash ?? 0
            }
            results = JavaHashMap(javaHash: { hashes[$0] ?? 0 })
            goalDecider = ClosureGoalDecider(hasSubGoals: true) { [unowned self] _, _, path in
                guard let tile = path.tile else { return false }
                for loc in locs where tile.isAdjacent(loc.tile) {
                    let key = ObjectIdentifier(loc)
                    if let p = results[key]?.path, p.cost <= path.cost { continue }
                    _ = results.put(key, (loc, path))
                }
                return false
            }
        }
    }
}

// MARK: Java's PriorityQueue

/// java.util.PriorityQueue, for the A* search: a binary heap whose
/// order among equal elements (and so the paths found) is Java's.
/// Removal compares by identity, as PathNode does not define equals.
public struct JavaPriorityQueue<T: AnyObject> {
    private var queue: [T] = []
    private let comparator: (T, T) -> Int

    public init(_ comparator: @escaping (T, T) -> Int) {
        self.comparator = comparator
    }

    public var isEmpty: Bool { queue.isEmpty }
    public var count: Int { queue.count }

    public mutating func offer(_ e: T) {
        queue.append(e)
        siftUp(queue.count - 1, e)
    }

    public mutating func poll() -> T? {
        guard !queue.isEmpty else { return nil }
        let result = queue[0]
        let x = queue.removeLast()
        if !queue.isEmpty { siftDown(0, x) }
        return result
    }

    @discardableResult
    public mutating func remove(_ o: T) -> Bool {
        guard let i = queue.firstIndex(where: { $0 === o }) else { return false }
        removeAt(i)
        return true
    }

    private mutating func removeAt(_ i: Int) {
        let s = queue.count - 1
        if s == i {
            queue.removeLast()
        } else {
            let moved = queue.removeLast()
            siftDown(i, moved)
            if queue[i] === moved { siftUp(i, moved) }
        }
    }

    private mutating func siftUp(_ k0: Int, _ x: T) {
        var k = k0
        while k > 0 {
            let parent = (k - 1) >> 1
            let e = queue[parent]
            if comparator(x, e) >= 0 { break }
            queue[k] = e
            k = parent
        }
        queue[k] = x
    }

    private mutating func siftDown(_ k0: Int, _ x: T) {
        var k = k0
        let n = queue.count
        let half = n >> 1
        while k < half {
            var child = 2 * k + 1
            var c = queue[child]
            let right = child + 1
            if right < n && comparator(c, queue[right]) > 0 {
                child = right
                c = queue[child]
            }
            if comparator(x, c) <= 0 { break }
            queue[k] = c
            k = child
        }
        queue[k] = x
    }
}

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

/// A unit's paths and searches, and its part in combat (the path and
/// combat parts of common/model/Unit).
extension Unit {

    /// More turns than any path takes.
    public static let manyTurns = 10000

    /// Where ports are tried in findIntermediatePort (Unit.PortMode).
    private enum PortMode {
        case lake, noHighSeas, blocked, land
    }

    // MARK: Combat

    /// The unit's combat modifiers: its type's, its owner's and its
    /// role's (@compat 0.11.0).  As in Java, each modifier's index is
    /// changed to the combat index of where it came from, in place.
    public func combatModifiers(_ id: String, _ fcgot: FreeColSpecObjectType?, _ turn: Turn?) -> [Modifier] {
        var result = ModifierSet()
        // Unit type modifiers always apply
        for m in type?.modifiers(id, for: fcgot, turn: turn) ?? [] {
            m.modifierIndex = m.type == .additive ? Modifier.unitAdditiveCombatIndex
                : Modifier.unitNormalCombatIndex
            result.add(m)
        }
        // The owner's modifiers may not all apply
        for m in owner?.modifiers(id, for: fcgot, turn: turn) ?? [] {
            m.modifierIndex = Modifier.generalCombatIndex
            result.add(m)
        }
        // Role modifiers apply
        for m in role?.modifiers(id, for: fcgot, turn: turn) ?? [] {
            m.modifierIndex = Modifier.roleCombatIndex
            result.add(m)
        }
        return result.members
    }

    /// Whether the unit could fire on a tile from here: within range,
    /// at a foreign settlement or defender.
    public func canAttackRanged(_ tile: Tile) -> Bool {
        guard let here = self.tile, (type?.attackRange ?? 0) >= here.distance(to: tile) else { return false }
        if let settlement = tile.settlement, settlement.owner !== owner { return true }
        if let defender = tile.defendingUnit(self), defender.owner !== owner { return true }
        return false
    }

    /// The closest place a ship could be repaired, other than the
    /// colony it is in: a colony that repairs, or Europe.
    public var repairLocation: (any Location)? {
        guard let player = owner else { return nil }
        let notHere = tile?.colony
        let colonies = player.colonyList.filter { $0 !== notHere && $0.hasAbility(Ability.repairUnits) }
        if let colony = closestColony(colonies) { return colony }
        return player.europe
    }

    /// The colony this unit could reach soonest, if sooner than many
    /// turns (Java's minimize keeps the first of equals).
    public func closestColony(_ colonies: [Colony]) -> Colony? {
        var best: Colony?
        var bestTurns = Unit.manyTurns - 1
        for c in colonies {
            let turns = turnsToReach(c)
            if turns < bestTurns {
                best = c
                bestTurns = turns
            }
        }
        return best
    }

    // MARK: Destinations

    /// Where a unit at sea is heading: its stop or destination (Europe
    /// itself, or the best entry tile for it), or the entry location.
    public func resolveDestination() -> (any Location)? {
        precondition(isAtSea, "Not at sea: \(self)")
        let stop = self.stop
        let dst: (any Location)? = TradeRoute.isStopValid(self, stop) ? stop?.location : destination
        if let dst, dst is Europe { return dst }
        if let tile = dst?.tile { return bestEntryTile(tile) }
        return fullEntryLocation
    }

    public func bestEntryTile(_ tile: Tile) -> Tile? {
        game?.map?.bestEntryTile(self, tile, nil, nil)
    }

    /// Where a path for this unit should start: its tile, or for ships
    /// and carried units off the map where they are heading, or else a
    /// settlement near Europe.
    public var pathStartLocation: (any Location)? {
        var ret: (any Location)? = tile
        if isOnCarrier, let carrier {
            if ret != nil {
                // OK
            } else if carrier.destination == nil {
                ret = nil
            } else if carrier.destination is Map {
                ret = carrier.fullEntryLocation
            } else if carrier.destination is Settlement {
                ret = carrier.destination
            } else { // The destination must be Europe
                ret = nil
            }
        } else if isNaval {
            if ret != nil {
                // OK
            } else if destination == nil || destination is Map {
                ret = fullEntryLocation
            } else if destination is Settlement {
                ret = destination
            } else {
                ret = fullEntryLocation
            }
        }
        if let ret { return ret }
        // A land unit off the map: our settlement nearest Europe.
        guard let owner else { return nil }
        func startValue(_ s: Settlement?) -> Int {
            guard let s, let t = s.tile, t.isHighSeasConnected else { return Constants.infinity }
            return t.highSeasCount
        }
        func best(_ settlements: [Settlement]) -> Settlement? {
            var best: Settlement?
            for s in settlements where best == nil || startValue(s) < startValue(best) { best = s }
            return best
        }
        if let sett = best(owner.settlements) ?? owner.settlements.first { return sett }
        // No settlements: the REF starts from a rebel colony.
        if owner.isREF { return best(owner.rebels.flatMap(\.settlements)) }
        // Desperately find the land nearest the entry location.
        guard let entry = fullEntryLocation?.tile else { return nil }
        return entry.surroundingTiles(1, Constants.infinity).first { $0.isLand }
    }

    /// Whether the unit should be carried to a location: not a ship, not
    /// there yet, and with no path, or one using a carrier.
    public func shouldTakeTransport(to loc: (any Location)?) -> Bool {
        guard let loc, !isNaval, !isAtLocation(loc) else { return false }
        guard let start = location else { return true }
        let path = findPath(start, loc, carrier)
        return path == nil || path!.usesCarrier
    }

    /// A path to somewhere safe: our nearest settlement, or for ships
    /// the nearest port, or a river corner closer to the high seas.
    public var trivialPath: PathNode? {
        guard !isDisposed, let location else { return nil }
        if !isNaval { return findOurNearestSettlement() }
        var path = findOurNearestPort()
        if path == nil, let tile, tile.isOnRiver, tile.isHighSeasConnected {
            // A ship up a river behind a blockage goes where others can
            // pass with the best connection to the high seas.
            path = search(location, GoalDeciders.corner(), CostDeciders.avoidSettlementsAndBlockingUnits(),
                          Constants.infinity, nil)
            if path == nil && tile.isRiverCorner {
                return PathNode(tile, 0, 0, false, nil, nil)
            }
        }
        return path
    }

    // MARK: Paths

    public func findPath(_ end: (any Location)?) -> PathNode? {
        guard let location else { preconditionFailure("Null start: \(self)") }
        return findPath(location, end)
    }

    public func findPath(_ start: any Location, _ end: (any Location)?) -> PathNode? {
        findPath(start, end, nil)
    }

    public func findPath(_ start: any Location, _ end: (any Location)?, _ carrier: Unit?) -> PathNode? {
        findPath(start, end, carrier, nil)
    }

    /// The quickest path from one location to another, with an optional
    /// carrier and cost decider.
    public func findPath(_ start: any Location, _ end: (any Location)?, _ carrier: Unit?,
                         _ costDecider: CostDecider?) -> PathNode? {
        precondition(end != nil, "findPath to null for \(self) from \(start)")
        guard let map = game?.map, let realStart = realStart(start, carrier) else { return nil }
        return map.findPath(self, realStart, end, carrier, costDecider)
    }

    /// The start of a path from a location, which must make sense for
    /// the unit and carrier.
    private func realStart(_ start: any Location, _ carrier: Unit?) -> (any Location)? {
        if let carrier {
            precondition(carrier.canCarryUnits, "Non-carrier carrier: \(carrier)")
            precondition(carrier.couldCarry(self), "Carrier could not carry unit: \(carrier)/\(self)")
        }
        var entry: (any Location)?
        if let startUnit = start as? Unit {
            guard let unitLoc = startUnit.location else {
                preconditionFailure("Null on-carrier start: \(self)/\(start)")
            }
            if unitLoc is HighSeas {
                guard let carrier else { preconditionFailure("Null carrier when starting on high seas: \(self)") }
                precondition(carrier === startUnit, "Wrong carrier when starting on high seas: \(self)")
                entry = carrier.resolveDestination()
            } else {
                entry = unitLoc
            }
        } else if start is HighSeas {
            if isOnCarrier {
                entry = self.carrier!.resolveDestination()
            } else if isNaval {
                entry = resolveDestination()
            } else {
                preconditionFailure("No carrier when starting on high seas: \(self)")
            }
        } else if start is Europe || start.tile != nil {
            entry = start
        } else {
            preconditionFailure("Invalid start: \(start)")
        }
        // Reduce to a tile if possible.
        return entry?.tile ?? entry
    }

    /// Search for a goal from a location.
    public func search(_ start: (any Location)?, _ gd: GoalDecider, _ cd: CostDecider?, _ maxTurns: Int,
                       _ carrier: Unit?) -> PathNode? {
        guard let start, let map = game?.map, let realStart = realStart(start, carrier) else { return nil }
        return map.search(self, realStart, gd, cd, maxTurns, carrier)
    }

    /// A path to the tile next to a target that is quickest to reach,
    /// that the unit can enter and that no foreign unit holds.
    public func findPathToNeighbour(_ start: any Location, _ end: Tile, _ carrier: Unit?,
                                    _ costDecider: CostDecider?) -> PathNode? {
        var best: Tile?
        var bestTurns = 0
        for t in end.surroundingTiles(1, 1) where isTileAccessible(t)
            && (t.firstUnit == nil || (owner?.owns(t.firstUnit) ?? false)) {
            let turns = findPath(start, t, carrier, costDecider)?.totalTurns ?? Constants.infinity
            if best == nil || turns < bestTurns {
                best = t
                bestTurns = turns
            }
        }
        return best.flatMap { findPath(start, $0, carrier, costDecider) }
    }

    public func turnsToReach(_ end: any Location) -> Int {
        guard let location else { return Unit.manyTurns }
        return turnsToReach(location, end)
    }

    public func turnsToReach(_ start: any Location, _ end: any Location) -> Int {
        turnsToReach(start, end, carrier, CostDeciders.avoidSettlementsAndBlockingUnits())
    }

    /// The turns to reach a location, or many if there is no path.
    public func turnsToReach(_ start: any Location, _ end: any Location, _ carrier: Unit?,
                             _ costDecider: CostDecider?) -> Int {
        findPath(start, end, carrier, costDecider)?.totalTurns ?? Unit.manyTurns
    }

    /// The decider for our closest settlement (Unit.ClosestSettlementGoalDecider):
    /// the fewest turns, perhaps only ports, never an excluded tile.
    private static func closestSettlementGoalDecider(_ exclude: Tile?, _ coastal: Bool) -> GoalDecider {
        var bestValue = Int(Int32.max)
        return ClosureGoalDecider(hasSubGoals: true) { gd, u, path in
            guard let u, let t = path.tile, t !== exclude, let settlement = t.settlement,
                  u.owner?.owns(settlement) ?? false, !coastal || settlement.isConnectedPort else { return false }
            let value = path.totalTurns
            if value < bestValue {
                bestValue = value
                gd.goal = path
                return true
            }
            return false
        }
    }

    public func findOurNearestSettlement(_ excludeStart: Bool, _ range: Int, _ coastal: Bool) -> PathNode? {
        guard owner?.hasSettlements ?? false, hasTile else { return nil }
        return findOurNearestSettlement(tile, excludeStart, range, coastal)
    }

    /// A path to our nearest settlement from a tile.
    public func findOurNearestSettlement(_ startTile: Tile?, _ excludeStart: Bool, _ range: Int,
                                         _ coastal: Bool) -> PathNode? {
        guard let startTile, owner?.hasSettlements ?? false else { return nil }
        let gd = Unit.closestSettlementGoalDecider(excludeStart ? startTile : nil, coastal)
        return search(startTile, gd, CostDeciders.avoidIllegal(), range, nil)
    }

    public func findOurNearestSettlement() -> PathNode? {
        findOurNearestSettlement(false, Int(Int32.max), false)
    }

    public func findOurNearestOtherSettlement() -> PathNode? {
        findOurNearestSettlement(true, Int(Int32.max), false)
    }

    /// A path to our nearest port, or Europe if that is sooner.
    public func findOurNearestPort() -> PathNode? {
        var ePath: PathNode?
        var eTurns = -1
        if type?.canMoveToHighSeas ?? false, let europe = owner?.europe {
            ePath = findPath(europe)
            eTurns = ePath?.totalTurns ?? -1
        }
        let sPath = findOurNearestSettlement(false, Constants.infinity, true)
        let sTurns = sPath?.totalTurns ?? -1
        guard let ePath else { return sPath }
        guard let sPath else { return ePath }
        return sTurns <= eTurns ? sPath : ePath
    }

    /// A port to stop at on the way to a destination that can not be
    /// reached directly, or else our nearest settlement.
    public func findIntermediatePort(_ dst: any Location) -> PathNode? {
        let ignoreSrc = settlement
        let ignoreDst = dst.settlement
        let srcTile = tile
        let dstTile = dst.tile
        let dstCont = dstTile?.contiguity ?? -1
        func value(_ s: Settlement) -> Int {
            guard let p = findPath(s) else { return Constants.infinity }
            return p.totalTurns + (dstTile!.distance(to: s.tile!))
        }
        // Java's minimize: the first of the best.
        func best(_ settlements: [Settlement]) -> Settlement? {
            var best: Settlement?
            var bestValue = 0
            for s in settlements {
                let v = value(s)
                if best == nil || v < bestValue {
                    best = s
                    bestValue = v
                }
            }
            return best
        }
        let mode: PortMode
        if isNaval {
            if !(srcTile?.isHighSeasConnected ?? false) {
                mode = .lake // On a lake!  FIXME: do better
            } else if dstTile == nil {
                mode = .noHighSeas // The carrier must be blocked from the high seas
            } else if dstTile!.isHighSeasConnected {
                // The carrier or the destination is blocked.
                mode = (tile?.isOnRiver ?? false) ? .noHighSeas : .blocked
            } else {
                mode = .blocked // The destination must be blocked
            }
        } else if dstTile == nil || tile?.contiguity != dstCont {
            // Ocean travel is needed: improve the connection from a port,
            // or go to one.
            mode = (srcTile?.isHighSeasConnected ?? false) ? .noHighSeas : .blocked
        } else {
            mode = .land // Land travel: just find a nearer settlement
        }
        var path: PathNode?
        switch mode {
        case .lake:
            break // No progress possible
        case .noHighSeas:
            // Probably blocked on a river: the settlement that most
            // reduces the high seas count.
            path = search(location, GoalDeciders.reduceHighSeasCount(self), nil, Constants.infinity, nil)
        case .blocked:
            // The closest available connected port.
            let ports = (owner?.connectedPortList ?? []).filter { $0 !== ignoreSrc && $0 !== ignoreDst }
            path = best(ports).flatMap { findPath($0) }
        case .land:
            // A nearby settlement with the destination's contiguity.
            let near = (owner?.settlements ?? []).filter {
                $0 !== ignoreSrc && $0 !== ignoreDst && $0.tile?.contiguity == dstCont
            }
            path = best(near).flatMap { findPath($0) }
        }
        return path ?? findOurNearestSettlement(false, Constants.infinity, false)
    }

    /// A path to the first enemy unit within range that could attack
    /// this unit with at least some odds.
    public func searchForDanger(_ range: Int, _ threat: Float) -> PathNode? {
        guard let game, let spec = specification, let start = tile, let type else { return nil }
        let cm = game.combatModel
        let threatDecider = ClosureGoalDecider(hasSubGoals: false) { [unowned self] gd, unit, path in
            guard let tile = path.tile, let first = tile.firstUnit,
                  owner?.atWar(with: first.owner) ?? false, let unit else { return false }
            if tile.unitList.contains(where: { u in
                guard u.canAttack(unit), cm.calculateCombatOdds(u, unit).win >= Double(threat),
                      let p = u.findPath(start) else { return false }
                return p.totalTurns < range
            }) {
                gd.goal = path
                return true
            }
            return false
        }
        // The other unit may be faster: scale the range by the fastest
        // land or naval speed over ours.
        let fastest = (isNaval ? spec.fastestNavalUnitType : spec.fastestLandUnitType)?.movement ?? type.movement
        let reverseRange = range * fastest / type.movement
        return search(start, threatDecider, CostDeciders.avoidIllegal(), reverseRange, carrier)
    }
}

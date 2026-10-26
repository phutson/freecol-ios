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
import FreeColServer
import FreeColUtil

/// What an AI unit is doing (server/ai/mission/Mission): a target, why
/// it may no longer be valid, and a turn's work towards it.
///
/// Java's missions log what they do; the log is left out here, but the
/// effects of logging (a unit waiting has its moves spent) are kept.
open class Mission: AIObject {

    static let minimumTransportPriority = 60
    static let normalTransportPriority = 100

    static let aiUnitNull = "aiUnit-null"
    static let aiUnitDied = "aiUnit-died"
    static let targetNull = "target-null"
    static let targetInvalid = "target-invalid"
    static let targetOwnership = "target-ownership"
    static let targetNotFound = "target-not-found"
    static let unitNotAPerson = "unit-not-a-person"
    static let unitNotOffensive = "unit-not-offensive"
    static let unitNotOfRequiredType = "unit-not-required-type"
    static let unitNotOnMap = "unit-not-on-map"

    public unowned let aiUnit: AIUnit

    /// A mission, which the unit takes at once.
    init(_ aiMain: AIMain, _ aiUnit: AIUnit) {
        self.aiUnit = aiUnit
        super.init(aiMain)
        initialized = true
        if aiUnit.mission !== self { aiUnit.changeMission(self) }
    }

    public var unit: Unit { aiUnit.unit }
    var player: Player? { unit.owner }
    var aiPlayer: MissionAIPlayer? { aiMain.aiPlayer(unit.owner) as? MissionAIPlayer }
    var aiRandom: JavaRandom { aiUnit.aiRandom! }

    public var isValid: Bool { invalidReason() == nil }

    static func isTargetReason(_ reason: String?) -> Bool {
        reason?.hasPrefix("target-") ?? false
    }

    private static func invalidUnitReason(_ unit: Unit?) -> String? {
        guard let unit else { return "unit-null" }
        if unit.isDisposed { return "unit-disposed" }
        if unit.isDamagedAndUnderForcedRepair { return "unit-under-repair" }
        return nil
    }

    static func invalidAIUnitReason(_ aiUnit: AIUnit?) -> String? {
        guard let aiUnit else { return aiUnitNull }
        return invalidUnitReason(aiUnit.unit)
    }

    /// Why a unit can not take a new mission: it has a valid one.
    static func invalidNewMissionReason(_ aiUnit: AIUnit?) -> String? {
        guard let aiUnit else { return aiUnitNull }
        if let m = aiUnit.mission, !m.isOneTime, m.isValid { return "mission-exists" }
        return nil
    }

    static func invalidTargetReason(_ target: (any Location)?) -> String? {
        guard let target else { return targetNull }
        if (target as? FreeColGameObject)?.isDisposed ?? false { return "target-disposed" }
        return nil
    }

    static func invalidTargetReason(_ target: (any Location)?, _ owner: Player?) -> String? {
        if let reason = invalidTargetReason(target) { return reason }
        if let e = target as? Europe, !(owner?.owns(e) ?? false) { return targetOwnership }
        if let s = target as? Settlement, !(owner?.owns(s) ?? false) { return targetOwnership }
        return nil
    }

    static func invalidAttackReason(_ aiUnit: AIUnit, _ other: Player?) -> String? {
        let unit = aiUnit.unit
        guard let player = unit.owner, let other else { return targetOwnership }
        if player === other { return targetOwnership }
        if player.isIndian && player.tension(other).level.ordinal <= Tension.Level.content.ordinal {
            return "target-native-tension-too-low"
        }
        if player.isEuropean
            && !(player.stance(other) == .war
                 || (unit.hasAbility(Ability.piracy) && player.stance(other) != .alliance)) {
            return "target-european-war-absent"
        }
        return nil
    }

    class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidAIUnitReason(aiUnit)
    }

    // MARK: The log's effects

    func lbWait() -> Mission {
        unit.movesLeft = 0
        return self
    }

    func lbDone(_ cont: Bool) -> Mission? {
        cont ? aiUnit.mission : lbDrop()
    }

    @discardableResult
    func lbDrop() -> Mission? {
        aiUnit.changeMission(nil)
    }

    func lbFail(_ cont: Bool) -> Mission? {
        cont ? aiUnit.mission : lbDrop()
    }

    // MARK: Moving

    /// Something blocking the path to a target, to attack
    /// (resolveBlockage).
    static func resolveBlockage(_ aiUnit: AIUnit, _ target: (any Location)?) -> (any Location)? {
        let unit = aiUnit.unit
        guard let path = unit.findPath(target), let next = path.next, let tile = next.tile else { return nil }
        let blocker: (any Location)? = tile.settlement ?? tile.defendingUnit(unit)
        return UnitSeekAndDestroyMission.invalidMissionReason(aiUnit, blocker) == nil ? blocker : nil
    }

    /// Move one step at random, near a direction (moveRandomly).
    ///
    /// - Returns: The direction moved, or nil if stuck.
    @discardableResult
    func moveRandomly(_ logMe: String?, _ direction: Direction?) -> Direction? {
        if unit.movesLeft <= 0 || !unit.hasTile { return nil }
        let logMe = logMe ?? "moveRandomly"
        let direction = direction ?? Direction.randomDirection(logMe, aiRandom)
        for d in direction.closestDirections(logMe, aiRandom) {
            if unit.tile?.neighbour(d) != nil && unit.moveType(d) == .move && aiUnit.move(d) { return d }
        }
        return nil
    }

    /// Wander until out of moves (moveRandomlyTurn).
    func moveRandomlyTurn(_ logMe: String) {
        var direction: Direction?
        repeat {
            direction = moveRandomly(logMe, direction)
        } while direction != nil
        unit.movesLeft = 0
    }

    /// Go towards a target (travelToTarget).
    ///
    /// - Returns: How it went: MOVE on arrival, or why it stopped.
    func travelToTarget(_ target: (any Location)?, _ costDecider: CostDecider?) -> Unit.MoveType {
        guard var target else { return .moveIllegal }
        if !(target is Europe) && target.tile == nil {
            preconditionFailure("Target neither Europe nor Tile: \(target)")
        }
        var aiCarrier = aiUnit.transport
        var path: PathNode?
        var useTransport = false
        target = upLoc(target) ?? target
        guard let owner = unit.owner, let here = unit.location else { return .moveIllegal }

        if unit.isAtSea {
            return .moveHighSeas
        } else if unit.isOnCarrier {
            return .moveNoAccessEmbark
        } else if unit.isAtLocation(target) {
            return .move
        } else if unit.isInEurope {
            if !owner.canMoveToEurope { return .moveIllegal }
            if unit.type?.canMoveToHighSeas ?? false {
                unit.destination = target
                return aiUnit.aiOwner?.ask(.moveTo(unit: unit.id, destination: game.map?.id)) == true
                    ? .moveHighSeas : .moveIllegal
            }
            useTransport = true
        } else if !unit.hasTile {
            return .moveIllegal
        } else if target is Europe {
            if !owner.canMoveToEurope { return .moveIllegal }
            if !(unit.type?.canMoveToHighSeas ?? false) || aiCarrier != nil {
                useTransport = true
            } else {
                path = unit.findPath(here, target, nil, costDecider)
            }
        } else if aiCarrier != nil {
            useTransport = true
        } else if !(unit.type?.canMoveToHighSeas ?? false) && !Map.isSameContiguity(target.tile, here.tile) {
            useTransport = true
        } else {
            path = unit.findPath(here, target, nil, costDecider)
        }

        if useTransport {
            if let carrier = aiCarrier {
                var waiting = false
                if let tm = carrier.mission as? CarrierMission, let pick = tm.transportTarget(aiUnit) {
                    if Map.isSameLocation(pick, unit.location) {
                        waiting = true
                    } else if let p = unit.findPath(here, pick, nil, costDecider) {
                        path = p
                        let ownPath = unit.findPath(here, target, nil, costDecider)
                        if ownPath == nil || ownPath!.totalTurns > p.totalTurns {
                            let ret = followMapPath(p.next)
                            if ret != .move { return ret }
                            waiting = true // Arrived for collection.
                        } else {
                            aiUnit.dropTransport()
                            aiCarrier = nil
                            path = ownPath
                            useTransport = false
                        }
                    } else {
                        // No path to the carrier.
                        path = unit.findPath(here, target, nil, costDecider)
                        if path == nil { return .moveNoTile }
                        aiUnit.dropTransport()
                        aiCarrier = nil
                        useTransport = false
                    }
                } else {
                    // A bogus carrier.
                    aiUnit.dropTransport()
                    aiCarrier = nil
                }
                if waiting, let carrier = aiCarrier {
                    return carrier.unit.movesLeft > 0 ? .moveNoAccessEmbark : .moveNoMoves
                }
            }
            if useTransport && aiCarrier == nil { return .moveNoAccessEmbark }
        }
        guard let path else { return .moveNoTile }
        guard let next = path.next else {
            preconditionFailure("Trivial path found from \(here) to target \(target)")
        }
        return followMapPath(next)
    }

    /// Follow a path while there are moves (followMapPath).
    private func followMapPath(_ start: PathNode?) -> Unit.MoveType {
        var node = start
        while let path = node {
            if unit.isDisposed { return .moveNoRepair }
            if unit.movesLeft <= 0 { return .moveNoMoves }
            if path.location is Europe {
                return aiUnit.aiOwner?.ask(.moveTo(unit: unit.id, destination: (path.location as? Europe)?.id))
                    == true ? .moveHighSeas : .moveIllegal
            }
            guard let d = path.direction else { return .moveIllegal }
            let mt = unit.moveType(d)
            if mt == .moveNoMoves {
                unit.movesLeft = 0
                return .moveNoMoves
            }
            if !mt.isProgress { return mt }
            if !aiUnit.move(d) { return .moveIllegal }
            node = path.next
        }
        return .move
    }

    /// Find a new target, or drop the mission (retargetMission).
    func retargetMission(_ reason: String) -> Mission? {
        if let newTarget = findTarget() {
            target = newTarget
            return self
        }
        return lbDrop()
    }

    // MARK: For subclasses

    var baseTransportPriority: Int { 0 }

    /// Where a carrier should take the unit, if anywhere
    /// (getTransportDestination).
    var transportDestination: (any Location)? {
        guard isValid, let loc = target, unit.shouldTakeTransportTo(loc) else { return nil }
        return loc
    }

    open var target: (any Location)? {
        get { nil }
        set {}
    }

    open func findTarget() -> (any Location)? { nil }

    /// Whether the mission is redone each turn.
    open var isOneTime: Bool { false }

    open func invalidReason() -> String? { nil }

    /// A turn's work.
    ///
    /// - Returns: The unit's mission afterwards.
    @discardableResult
    open func doMission() -> Mission? { self }
}

extension CarrierMission {
    func transportTarget(_ t: TransportableAIObject) -> (any Location)? { nil }
}

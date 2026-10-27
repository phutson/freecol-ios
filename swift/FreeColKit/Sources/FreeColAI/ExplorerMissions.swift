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

/// Scout native settlements and rumours (server/ai/mission/ScoutingMission).
final class ScoutingMission: Mission {

    private var scoutTarget: (any Location)?
    /// A tile beside a settlement on another land mass, to be carried
    /// to first.
    private var precedingTile: (any Location)?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: (any Location)?) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    private static func canScoutNatives(_ aiUnit: AIUnit) -> Bool {
        aiUnit.unit.hasAbility(Ability.speakWithChief)
    }

    static func extractTarget(_ aiUnit: AIUnit, _ path: PathNode?) -> (any Location)? {
        guard let loc = path?.lastNode.location else { return nil }
        if invalidSettlementReason(aiUnit, loc.settlement) == nil { return loc.settlement }
        if invalidTileReason(aiUnit, loc.tile) == nil { return loc.tile }
        return nil
    }

    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode?) -> Int {
        guard let path, let loc = extractTarget(aiUnit, path) else { return Int(Int32.min) }
        if loc is Colony { return 12 / (path.totalTurns + 1) }
        if loc is IndianSettlement { return 2000 / (path.totalTurns + 1) }
        if let t = loc as? Tile, t.hasLostCityRumour { return 1000 / (path.totalTurns + 1) }
        return Int(Int32.min)
    }

    private static func goalDecider(_ aiUnit: AIUnit, _ deferOK: Bool) -> GoalDecider {
        deferring(ScoredPathDecider(Int(Int32.min)) { path in
            let loc = extractTarget(aiUnit, path)
            return loc is IndianSettlement || loc is Tile ? scorePath(aiUnit, path) : nil
        }, deferOK)
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        return unit.search(unit.pathStartLocation, goalDecider(aiUnit, deferOK), CostDeciders.avoidIllegal(),
                           range, unit.carrier)
    }

    static func findMissionTarget(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> (any Location)? {
        if let path = findTargetPath(aiUnit, range, deferOK) { return upLoc(extractTarget(aiUnit, path)) }
        return upLoc(findCircleTarget(aiUnit, goalDecider(aiUnit, deferOK), range * 3, deferOK))
    }

    /// Equip as a scout if need be (prepare).
    static func prepare(_ aiUnit: AIUnit) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if canScoutNatives(aiUnit) { return nil }
        if let role = aiUnit.unit.specification?.scoutRole, aiUnit.equipForRole(role) { return nil }
        if aiUnit.unit.hasAbility(Ability.expertScout) { return nil }
        return "unit-unprepared-to-SCOUT"
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        return canScoutNatives(aiUnit!) ? nil : "unit-not-a-SCOUT"
    }

    private static func invalidIndianSettlementReason(_ aiUnit: AIUnit, _ settlement: IndianSettlement) -> String? {
        if let reason = invalidTargetReason(settlement) { return reason }
        let owner = aiUnit.unit.owner
        if settlement.hasScouted(owner) { return "settlement-scouted" }
        if let tension = settlement.alarm(owner), tension.value >= Tension.Level.hateful.limit {
            return "settlement-hateful"
        }
        return nil
    }

    private static func invalidSettlementReason(_ aiUnit: AIUnit, _ settlement: Settlement?) -> String? {
        if let colony = settlement as? Colony { return invalidTargetReason(colony, aiUnit.unit.owner) }
        if let s = settlement as? IndianSettlement { return invalidIndianSettlementReason(aiUnit, s) }
        return targetInvalid
    }

    private static func invalidTileReason(_ aiUnit: AIUnit, _ tile: Tile?) -> String? {
        guard let tile else { return "tile-null" }
        if tile.hasLostCityRumour { return nil }
        if !tile.isExploredBy(aiUnit.unit.owner) { return nil }
        return "explored-tile-lacks-rumour"
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let s = loc as? Settlement { return invalidSettlementReason(aiUnit, s) }
        if let t = loc as? Tile { return invalidTileReason(aiUnit, t) }
        return targetInvalid
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority }

    override var target: (any Location)? {
        get { precedingTile ?? scoutTarget }
        set {
            if newValue == nil || newValue is Tile || newValue is Colony {
                scoutTarget = newValue
                precedingTile = nil
            } else if let settlement = newValue as? IndianSettlement, let t = settlement.tile {
                if !unit.hasTile || unit.tile?.contiguity != t.contiguity {
                    // It must be reached by carrier: land beside it first.
                    let tiles = t.contiguityAdjacentInJavaOrder(t.contiguity)
                    let coast = tiles.filter(\.isCoastland)
                    precedingTile = RandomUtils.randomMember("scout-tile", coast.isEmpty ? tiles : coast, aiRandom)
                } else {
                    precedingTile = nil
                }
                scoutTarget = settlement
            }
        }
    }

    override func findTarget() -> (any Location)? {
        ScoutingMission.findMissionTarget(aiUnit, 20, true)
    }

    override func invalidReason() -> String? {
        ScoutingMission.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        let reason = invalidReason()
        if Mission.isTargetReason(reason) { return retargetMission(reason!) }
        if reason != nil { return lbFail(false) }

        let mt = travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits())
        switch mt {
        case .move:
            if precedingTile != nil {
                // Beside the settlement: go there now.
                precedingTile = nil
                return doMission()
            }
        case .moveHighSeas, .moveNoMoves, .moveIllegal:
            return lbWait()
        case .moveNoRepair:
            return lbFail(false)
        case .moveNoAccessEmbark:
            target = scoutTarget
            return self
        case .moveNoTile:
            _ = moveRandomly("AI scout", nil)
            return lbDodge()
        case .attackUnit:
            // Probably blocked beside the target: move and retry.
            _ = moveRandomly("AI scout", target?.tile.flatMap { unit.tile?.direction(to: $0) })
            return lbDodge()
        case .enterIndianSettlementWithScout:
            if let settlement = target as? IndianSettlement {
                aiUnit.aiOwner?.ask(.scoutSpeakToChief(unit: unit.id, settlement: settlement.id))
            }
        case .exploreLostCityRumour:
            if let tt = target?.tile, let d = unit.tile?.direction(to: tt) {
                aiUnit.aiOwner?.ask(.move(unit: unit.id, direction: d.javaName))
            }
        default:
            return self
        }
        if unit.isDisposed { return self }

        // Retarget, but not from one colony to the same one: then drop
        // the scout's equipment and give up.
        let completed = target
        let newTarget = ScoutingMission.findMissionTarget(aiUnit, 20, false)
        if newTarget == nil || (completed is Colony && newTarget === completed) {
            if completed is Colony && ScoutingMission.canScoutNatives(aiUnit), let role = specification?.defaultRole {
                _ = aiUnit.equipForRole(role)
            }
            return lbFail(false)
        }
        target = newTarget
        return self
    }
}

/// Establish missions at native settlements
/// (server/ai/mission/MissionaryMission).
final class MissionaryMission: Mission {

    private var missionTarget: (any Location)?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: (any Location)?) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    private static func extractTarget(_ aiUnit: AIUnit, _ path: PathNode?) -> (any Location)? {
        let settlement = path?.lastNode.location?.settlement
        if let s = settlement as? IndianSettlement, invalidIndianSettlementReason(aiUnit, s) == nil { return s }
        if let c = settlement as? Colony, invalidTargetReason(c, aiUnit.unit.owner) == nil { return c }
        return nil
    }

    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode) -> Int {
        extractTarget(aiUnit, path) is IndianSettlement ? 1000 / (path.totalTurns + 1) : Int(Int32.min)
    }

    private static func goalDecider(_ aiUnit: AIUnit, _ deferOK: Bool) -> GoalDecider {
        deferring(ScoredPathDecider(Int(Int32.min)) { path in
            path.lastNode.location?.settlement is IndianSettlement ? scorePath(aiUnit, path) : nil
        }, deferOK)
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        return unit.search(unit.pathStartLocation, goalDecider(aiUnit, deferOK),
                           CostDeciders.avoidSettlementsAndBlockingUnits(), range, unit.carrier)
    }

    static func findMissionTarget(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> (any Location)? {
        findTargetPath(aiUnit, range, deferOK).flatMap { extractTarget(aiUnit, $0) }
    }

    /// Dress as a missionary where possible (prepare).
    static func prepare(_ aiUnit: AIUnit) -> String? {
        if let reason = invalidUnitReason(aiUnit) { return reason }
        let unit = aiUnit.unit
        if !unit.hasAbility(Ability.establishMission),
           (unit.location as? FreeColGameObject)?.hasAbility(Ability.dressMissionary) ?? false,
           let role = unit.specification?.missionaryRole {
            _ = aiUnit.equipForRole(role)
        }
        return unit.hasAbility(Ability.establishMission) ? nil : "unit-can-not-establish-mission"
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        if !unit.isPerson { return unitNotAPerson }
        if unit.skillLevel >= -1 && !unit.hasAbility(Ability.expertMissionary) {
            return "unit-is-not-subskilled-or-expertMissionary"
        }
        if unit.isInEurope || unit.isAtSea {
            return unit.owner?.hasSettlements ?? false ? nil : "unit-off-map-but-missing-initial-settlement"
        }
        if unit.isInMission { return "unit-is-already-at-mission" }
        return nil
    }

    private static func invalidIndianSettlementReason(_ aiUnit: AIUnit, _ settlement: IndianSettlement) -> String? {
        if let reason = invalidTargetReason(settlement) { return reason }
        guard let owner = aiUnit.unit.owner else { return targetOwnership }
        if !owner.hasContacted(settlement.owner) { return "target-is-uncontacted" }
        if settlement.owner?.atWar(with: owner) ?? false { return "target-at-war" }
        if settlement.hasMissionary(owner) { return "target-has-our-mission" }
        return nil
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let s = loc as? IndianSettlement { return invalidIndianSettlementReason(aiUnit, s) }
        if let c = loc as? Colony { return invalidTargetReason(c, aiUnit.unit.owner) }
        return targetInvalid
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority }

    override var target: (any Location)? {
        get { missionTarget }
        set { if newValue == nil || newValue is Settlement { missionTarget = newValue } }
    }

    override func findTarget() -> (any Location)? {
        MissionaryMission.findMissionTarget(aiUnit, 20, true)
    }

    override func invalidReason() -> String? {
        MissionaryMission.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        let reason = invalidReason()
        if Mission.isTargetReason(reason) { return retargetMission(reason!) }
        if reason != nil { return lbFail(false) }
        switch travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits()) {
        case .move:
            // At an intermediate colony: retarget, without fallbacks.
            let completed = target
            let newTarget = MissionaryMission.findMissionTarget(aiUnit, 20, false)
            if newTarget == nil || newTarget === completed { return lbFail(false) }
            target = newTarget
            return self
        case .moveHighSeas, .moveNoMoves, .moveIllegal:
            return lbWait()
        case .moveNoRepair:
            return lbFail(false)
        case .moveNoAccessEmbark, .moveNoTile:
            return self
        case .enterIndianSettlementWithMissionary:
            break
        default:
            return self
        }
        guard let settlement = target as? IndianSettlement, let st = settlement.tile,
              let d = unit.tile?.direction(to: st) else { return lbFail(false) }
        aiUnit.aiOwner?.ask(.missionary(unit: unit.id, direction: d.javaName,
                                        denounce: settlement.hasMissionary ? "true" : "false"))
        return settlement.hasMissionary(unit.owner) && unit.isInMission ? lbDone(false) : lbFail(false)
    }
}

/// Raid other players' ships (server/ai/mission/PrivateerMission).
final class PrivateerMission: Mission {

    private var privateerTarget: (any Location)?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: (any Location)?) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    private static func extractTarget(_ aiUnit: AIUnit, _ path: PathNode?) -> (any Location)? {
        guard let loc = path?.lastNode.location else { return nil }
        let unit = aiUnit.unit
        if loc is Europe { return loc }
        if let other = loc.tile?.defendingUnit(unit), invalidMissionReason(aiUnit, other) == nil { return other }
        if let settlement = loc.settlement, invalidTargetReason(settlement, unit.owner) == nil { return settlement }
        return nil
    }

    /// How tempting a ship is: its cargo, less the danger.
    static func scoreUnit(_ aiUnit: AIUnit, _ defender: Unit) -> Int {
        let attacker = aiUnit.unit
        var value = 100 + defender.visibleGoodsCount * 200
        if defender.isOffensiveUnit, let co = attacker.game?.combatModel.calculateCombatOdds(attacker, defender) {
            value += Int(JavaMath.toInt((co.win - 0.5) * 200))
        }
        return value
    }

    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode) -> Int {
        let loc = extractTarget(aiUnit, path)
        let totalTurns = path.totalTurns + 1
        if loc is Europe || loc is Colony { return 1000 / totalTurns }
        if let u = loc as? Unit { return scoreUnit(aiUnit, u) / totalTurns }
        if loc is Tile { return 50 / totalTurns }
        return Int(Int32.min)
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        return unit.search(unit.pathStartLocation, ScoredPathDecider(Int(Int32.min)) { scorePath(aiUnit, $0) },
                           CostDeciders.avoidIllegal(), range, nil)
    }

    static func findMissionTarget(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> (any Location)? {
        findTargetPath(aiUnit, range).flatMap { extractTarget(aiUnit, $0) }
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        if !unit.isCarrier { return "unit-not-a-carrier" }
        if !unit.isOffensiveUnit { return unitNotOffensive }
        if !unit.isEmpty || !unit.compactGoodsList.isEmpty { return "unit-has-cargo" }
        return nil
    }

    private static func invalidAttackReason(_ aiUnit: AIUnit, _ unit: Unit?) -> String? {
        guard let unit else { return targetInvalid }
        if !unit.isNaval { return "privateer-ignores-land-unit" }
        if aiUnit.unit.owner?.owns(unit) ?? false { return targetOwnership }
        if let reason = Mission.invalidAttackReason(aiUnit, unit.owner) { return reason }
        return scoreUnit(aiUnit, unit) <= 0 ? "privateer-avoids-trouble" : nil
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        let owner = aiUnit.unit.owner
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if aiUnit.unit.isInEurope { return nil }
        guard let loc else { return nil }
        if loc is Europe { return invalidTargetReason(loc, owner) }
        if let s = loc as? Settlement {
            return s is Colony ? invalidTargetReason(s, owner) : targetInvalid
        }
        if let u = loc as? Unit { return invalidAttackReason(aiUnit, u) }
        if let t = loc as? Tile { return t.isExploredBy(owner) ? "tile-is-explored" : nil }
        return targetInvalid
    }

    override var transportDestination: (any Location)? { nil }

    override var target: (any Location)? {
        get { privateerTarget }
        set {
            if newValue == nil || newValue is Colony || newValue is Europe || newValue is Unit {
                privateerTarget = newValue
            }
        }
    }

    override func findTarget() -> (any Location)? {
        PrivateerMission.findMissionTarget(aiUnit, 8, true)
    }

    override func invalidReason() -> String? {
        PrivateerMission.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        if aiUnit.hasCargo {
            // Deliver the goods.
            let m = europeanAIPlayer?.transportMission(aiUnit)
            return lbDone(m != nil)
        }
        let reason = invalidReason()
        if Mission.isTargetReason(reason) { return retargetMission(reason!) }
        if reason != nil { return lbFail(false) }

        if unit.isInEurope, let owner = unit.owner {
            let settlement = Mission.bestSettlement(owner)
            unit.destination = settlement?.tile ?? unit.fullEntryLocation
            aiUnit.moveToAmerica()
        }
        if unit.isAtSea { return self }
        guard let newTarget = PrivateerMission.findMissionTarget(aiUnit, 1, true) else {
            moveRandomlyTurn("AI privateer")
            return self
        }
        target = newTarget
        switch travelToTarget(newTarget, nil) {
        case .move:
            break
        case .moveHighSeas, .moveNoMoves, .moveIllegal:
            return lbWait()
        case .moveNoRepair:
            return lbFail(false)
        case .moveNoTile:
            _ = moveRandomly("AI privateer", nil)
            return lbDodge()
        case .attackUnit:
            if let tt = target?.tile, let direction = unit.tile?.direction(to: tt) {
                aiUnit.aiOwner?.ask(.attack(unit: unit.id, direction: direction.javaName))
            } else if let blocker = Mission.resolveBlockage(aiUnit, target) as? Unit,
                      PrivateerMission.scoreUnit(aiUnit, blocker) > 0,
                      let bt = blocker.tile, let d = unit.tile?.direction(to: bt) {
                aiUnit.aiOwner?.ask(.attack(unit: unit.id, direction: d.javaName))
            } else {
                moveRandomlyTurn("AI privateer")
            }
            return self
        default:
            return self
        }
        return self
    }
}

/// Escort another unit (server/ai/mission/EscortUnitMission).
final class EscortUnitMission: Mission {

    private var escortTarget: (any Location)?
    private var escortTransportTarget: (any Location)?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: Unit) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        return aiUnit!.unit.isOffensiveUnit ? nil : unitNotOffensive
    }

    private static func invalidTargetReason(_ aiUnit: AIUnit, _ unit: Unit?) -> String? {
        if let reason = invalidTargetReason(unit) { return reason }
        guard unit!.tile != nil else { return "target-not-on-map" }
        if aiUnit.unit.owner !== unit!.owner { return targetOwnership }
        if aiUnit.unit.isNaval != unit!.isNaval { return "target-incompatible" }
        return nil
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        return invalidTargetReason(aiUnit, loc as? Unit)
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority }

    override var transportDestination: (any Location)? {
        guard isValid, let loc = escortTransportTarget ?? escortTarget else { return nil }
        return unit.shouldTakeTransportTo(loc) ? loc : nil
    }

    override var target: (any Location)? {
        get { escortTarget }
        set { escortTarget = newValue } // Java insists on a unit.
    }

    override func findTarget() -> (any Location)? { nil }

    override func invalidReason() -> String? {
        EscortUnitMission.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        let reason = invalidReason()
        if Mission.isTargetReason(reason) { return lbDrop() }
        if reason != nil { return lbFail(false) }
        let currentTarget = target
        let mt = travelToTarget(currentTarget, CostDeciders.avoidSettlementsAndBlockingUnits())
        switch mt {
        case .moveHighSeas, .moveNoMoves, .moveIllegal:
            _ = lbWait()
        case .moveNoRepair:
            return lbFail(false)
        case .attackUnit, .attackSettlement:
            guard let ct = currentTarget?.tile, let d = unit.tile?.direction(to: ct) else { return lbWait() }
            aiUnit.aiOwner?.ask(.attack(unit: unit.id, direction: d.javaName))
            return self
        default:
            break
        }
        return self
    }
}

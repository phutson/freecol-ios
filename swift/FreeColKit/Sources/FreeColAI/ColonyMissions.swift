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
import FreeColXML

/// A goal decider keeping the best scoring path, as the missions'
/// anonymous ones do, with the first best value and a score that is nil
/// for a path that is not a candidate.
final class ScoredPathDecider<V: Comparable>: GoalDecider {
    private(set) var goal: PathNode?
    private var bestValue: V
    private let score: (PathNode) -> V?

    init(_ initial: V, _ score: @escaping (PathNode) -> V?) {
        bestValue = initial
        self.score = score
    }

    var hasSubGoals: Bool { true }

    func check(_ unit: Unit?, _ path: PathNode) -> Bool {
        guard let value = score(path), bestValue < value else { return false }
        bestValue = value
        goal = path
        return true
    }
}

extension Mission {
    /// A goal decider, or failing it, our closest settlement, if
    /// deferring is allowed.
    static func deferring(_ gd: GoalDecider, _ deferOK: Bool) -> GoalDecider {
        deferOK ? GoalDeciders.composed(all: false, gd, GoalDeciders.ourClosestSettlement()) : gd
    }

    var europeanAIPlayer: EuropeanAIPlayer? { aiPlayer as? EuropeanAIPlayer }
}

/// Build a colony (server/ai/mission/BuildColonyMission).
final class BuildColonyMission: Mission {

    // MARK: Saving

    override init(loading aiMain: AIMain, _ aiUnit: AIUnit, _ xr: FreeColXMLReader) throws {
        try super.init(loading: aiMain, aiUnit, xr)
    }

    override var xmlTag: String { "buildColonyMission" }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let buildTarget {
            xw.writeLocationAttribute("target", buildTarget)
            if colonyValue > 0 { xw.writeAttribute("value", colonyValue) }
        }
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        buildTarget = aiMain.location(xr, "target")
        colonyValue = xr.attribute("value", default: -1)
    }

    private var buildTarget: (any Location)?
    private var colonyValue = -1

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: (any Location)?) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    private func colonyValue(_ tile: Tile) -> Int {
        aiUnit.unit.owner?.colonyValue(tile) ?? 0
    }

    static func extractTarget(_ aiUnit: AIUnit, _ path: PathNode?) -> (any Location)? {
        guard let loc = path?.lastNode.location else { return nil }
        let tile = loc.tile, colony = loc.colony
        if invalidMissionReason(aiUnit, tile) == nil { return tile }
        if invalidMissionReason(aiUnit, colony) == nil { return colony }
        return nil
    }

    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode?) -> Float {
        guard let path, let tile = extractTarget(aiUnit, path) as? Tile,
              let player = aiUnit.unit.owner else { return Float(Int32.min) }
        let turns = Float(path.totalTurns) + 3
        return Float(3 * player.colonyValue(tile)) / turns
    }

    private static func goalDecider(_ aiUnit: AIUnit, _ deferOK: Bool) -> GoalDecider {
        deferring(ScoredPathDecider(Float(0)) { path in
            extractTarget(aiUnit, path) is Tile ? scorePath(aiUnit, path) : nil
        }, deferOK)
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        return unit.search(unit.pathStartLocation, goalDecider(aiUnit, deferOK),
                           CostDeciders.avoidSettlementsAndBlockingUnits(), range, unit.carrier)
    }

    static func findMissionTarget(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> (any Location)? {
        if let path = findTargetPath(aiUnit, range, deferOK) { return extractTarget(aiUnit, path) }
        return upLoc(findCircleTarget(aiUnit, goalDecider(aiUnit, deferOK), range * 3, deferOK))
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        if !(unit.owner?.canBuildColonies ?? false) { return "player-not-a-colony-founder" }
        if !(unit.type?.canBuildColony ?? false) { return "unit-not-a-colony-founder" }
        return nil
    }

    private static func invalidTileReason(_ aiUnit: AIUnit, _ tile: Tile) -> String? {
        guard let owner = aiUnit.unit.owner else { return targetOwnership }
        let reason = owner.canClaimToFoundSettlementReason(tile)
        switch reason {
        case .none, .natives: return nil
        default: return "target-\(reason)"
        }
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let colony = loc as? Colony { return invalidTargetReason(colony, aiUnit.unit.owner) }
        if let tile = loc as? Tile { return invalidTileReason(aiUnit, tile) }
        return targetInvalid
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority + 10 }

    override var target: (any Location)? {
        get { buildTarget }
        set {
            if newValue == nil || newValue is Colony || newValue is Tile {
                buildTarget = newValue
                colonyValue = (newValue as? Tile).map { colonyValue($0) } ?? -1
            }
        }
    }

    override func findTarget() -> (any Location)? {
        BuildColonyMission.findMissionTarget(aiUnit, 5, true)
    }

    override func invalidReason() -> String? {
        BuildColonyMission.invalidMissionReason(aiUnit, buildTarget)
    }

    override func doMission() -> Mission? {
        guard let player = unit.owner, let euaip = europeanAIPlayer else { return lbFail(false) }
        let reason = invalidReason()
        if Mission.isTargetReason(reason) {
            // Another builder took the tile: go on to the colony.
            if let t = buildTarget as? Tile, let c = t.colony, player.owns(c) {
                if euaip.pioneeringMission(aiUnit, c.tile) != nil { return lbDrop() }
                target = c
                return self
            }
        } else if reason != nil {
            return lbFail(false)
        } else if let t = buildTarget as? Tile, colonyValue(t) < colonyValue {
            return retargetMission("target tile value fell")
        }

        switch travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits()) {
        case .move: break
        case .moveHighSeas, .moveNoMoves, .moveIllegal: return lbWait()
        case .moveNoRepair: return lbFail(false)
        case .moveNoAccessEmbark, .moveNoTile: return self
        default: return self
        }

        if let colony = target as? Colony {
            // Improve the centre, join a small colony, or find a site.
            if euaip.pioneeringMission(aiUnit, colony.tile) != nil { return lbDrop() }
            if colony.unitCount <= 1 {
                target = colony
                return lbDrop()
            }
            if let newTarget = BuildColonyMission.findMissionTarget(aiUnit, 5, false) {
                target = newTarget
                return self
            }
            var best: Colony?
            var bestTurns = Int.max
            for c in player.colonyList where c !== colony && c.unitCount < colony.unitCount {
                let turns = unit.turnsToReach(c)
                if best == nil || turns < bestTurns {
                    best = c
                    bestTurns = turns
                }
            }
            if let best {
                target = best
                return self
            }
            return lbDrop()
        }
        guard let tile = target as? Tile else { return lbFail(false) }

        // Building needs moves.
        if unit.movesLeft <= 0 { return lbWait() }
        if tile.owner == nil {
            // All is well.
        } else if player.owns(tile) {
            if tile.owningSettlement is Colony { return lbFail(false) } // Java warns
        } else {
            // Claim it, buying or stealing.
            let price = player.landPrice(tile)
            var fail = price < 0
            if price > 0 && !player.checkGold(price) {
                if RandomUtils.randomInt("Land gold?", aiRandom, 4) == 0 { euaip.cheatGold(price) }
            }
            if price >= 0 {
                let pay = price == 0 ? 0 : player.checkGold(price) ? price : Constants.stealLand
                fail = !(aiUnit.aiOwner?.ask(.claimLand(tile: tile.id, claimant: unit.id, price: String(pay)))
                         ?? false)
                    || !player.owns(tile)
            }
            if fail { return retargetMission("tile-claim-at-\(tile.id ?? "")") }
        }

        if aiUnit.aiOwner?.ask(.buildColony(name: "", unit: unit.id)) == true,
           let colony = tile.colony, let aiColony = aiMain.aiColony(colony) {
            aiColony.requestRearrange()
            let m = euaip.workInsideColonyMission(aiUnit, aiColony)
            return lbDone(m != nil)
        }
        return lbFail(false)
    }
}

/// Improve tiles (server/ai/mission/PioneeringMission).
final class PioneeringMission: Mission {

    // MARK: Saving

    override init(loading aiMain: AIMain, _ aiUnit: AIUnit, _ xr: FreeColXMLReader) throws {
        try super.init(loading: aiMain, aiUnit, xr)
    }

    override var xmlTag: String { "pioneeringMission" }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let pioneerTarget {
            xw.writeLocationAttribute("target", pioneerTarget)
            if let tileImprovementPlan { xw.writeAttribute(TileImprovementPlan.tag, id: tileImprovementPlan.id) }
        }
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        pioneerTarget = aiMain.location(xr, "target")
        tileImprovementPlan = xr.hasAttribute(TileImprovementPlan.tag)
            ? aiMain.reference(xr.attribute(TileImprovementPlan.tag, default: nil as String?),
                               TileImprovementPlan.self) : nil
    }

    private(set) var tileImprovementPlan: TileImprovementPlan?
    private var pioneerTarget: (any Location)?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: (any Location)?) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    private static func bestMissionPlan(_ aiUnit: AIUnit, _ tile: Tile) -> TileImprovementPlan? {
        (aiUnit.aiOwner as? EuropeanAIPlayer)?.bestPlan(tile)
    }

    func setTileImprovementPlan(_ tip: TileImprovementPlan?) {
        let old = tileImprovementPlan
        tileImprovementPlan = tip
        if old !== tip {
            if let old, old.pioneer === aiUnit { old.pioneer = nil }
            if let tip {
                tip.pioneer = aiUnit
                europeanAIPlayer?.removeTileImprovementPlan(tip)
            }
        }
    }

    private func abandonTileImprovementPlan() {
        if let tip = tileImprovementPlan {
            if tip.pioneer === aiUnit { tip.pioneer = nil }
            setTileImprovementPlan(nil)
        }
    }

    override func dispose() {
        abandonTileImprovementPlan()
        super.dispose()
    }

    private static func hasMissionTools(_ aiUnit: AIUnit) -> Bool {
        aiUnit.unit.hasAbility(Ability.improveTerrain)
    }

    private var hasTools: Bool { PioneeringMission.hasMissionTools(aiUnit) }

    private static func extractTarget(_ aiUnit: AIUnit, _ path: PathNode?) -> (any Location)? {
        guard let loc = path?.lastNode.location else { return nil }
        if hasMissionTools(aiUnit) {
            return invalidTileReason(aiUnit, loc.tile) != nil ? nil : loc.tile
        }
        return invalidColonyReason(aiUnit, loc.colony) != nil ? nil : loc.colony
    }

    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode) -> Int {
        let loc = extractTarget(aiUnit, path)
        if hasMissionTools(aiUnit) {
            if let tile = loc as? Tile, let tip = bestMissionPlan(aiUnit, tile) {
                return 1000 * tip.value / (path.totalTurns + 1)
            }
        } else if loc is Colony {
            return 1000 / (path.totalTurns + 1)
        }
        return Int(Int32.min)
    }

    private static func goalDecider(_ aiUnit: AIUnit, _ deferOK: Bool) -> GoalDecider {
        deferring(ScoredPathDecider(Int(Int32.min)) { scorePath(aiUnit, $0) }, deferOK)
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        return unit.search(unit.pathStartLocation, goalDecider(aiUnit, deferOK),
                           CostDeciders.avoidSettlementsAndBlockingUnits(), range, unit.carrier)
    }

    /// The colony with the most tile improvement plans, or the nearest
    /// port to it (getBestPioneeringColony).
    private static func bestPioneeringColony(_ aiUnit: AIUnit) -> Colony? {
        guard let owner = aiUnit.aiOwner as? EuropeanAIPlayer else { return nil }
        var best: AIColony?
        for aic in owner.aiColonies()
        where best == nil || aic.currentTileImprovementPlans.count > best!.currentTileImprovementPlans.count {
            best = aic
        }
        guard let colony = best?.colony else { return nil }
        if colony.isConnectedPort { return colony }
        guard let path = aiUnit.unit.findOurNearestPort() else { return colony }
        return path.lastNode.location?.colony
    }

    static func findMissionTarget(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> (any Location)? {
        if let path = findTargetPath(aiUnit, range, false) { return extractTarget(aiUnit, path) }
        if deferOK { return bestPioneeringColony(aiUnit) }
        let loc = findCircleTarget(aiUnit, goalDecider(aiUnit, false), range * 3, false)
        return hasMissionTools(aiUnit) ? loc : upLoc(loc)
    }

    /// Equip with tools if needed (prepare).
    ///
    /// - Returns: Why the unit can not pioneer, or nil.
    static func prepare(_ aiUnit: AIUnit) -> String? {
        if let reason = invalidUnitReason(aiUnit) { return reason }
        let unit = aiUnit.unit
        if !hasMissionTools(aiUnit),
           !(unit.specification?.pioneerRole.map { aiUnit.equipForRole($0) } ?? false) {
            return "unit-could-not-equip"
        }
        return hasMissionTools(aiUnit) || unit.hasAbility(Ability.expertPioneer) ? nil : "unit-missing-tools"
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        return aiUnit!.unit.isPerson ? nil : unitNotAPerson
    }

    private static func invalidColonyReason(_ aiUnit: AIUnit, _ colony: Colony?) -> String? {
        if let reason = invalidTargetReason(colony, aiUnit.unit.owner) { return reason }
        let role = aiUnit.unit.specification?.getRole("model.role.pioneer")
        if !hasMissionTools(aiUnit), !colony!.canProvideGoods(role?.requiredGoods ?? []) {
            return "colony-can-not-provide-equipment"
        }
        return nil
    }

    private static func plan(_ aiUnit: AIUnit, _ tile: Tile) -> TileImprovementPlan? {
        guard let pm = aiUnit.mission as? PioneeringMission, let tip = pm.tileImprovementPlan,
              tip.target === tile else { return nil }
        return tip
    }

    private static func invalidTileReason(_ aiUnit: AIUnit, _ tile: Tile?) -> String? {
        guard let tile else { return targetInvalid }
        if !hasMissionTools(aiUnit) { return "unit-needs-tools" }
        if plan(aiUnit, tile) == nil && bestMissionPlan(aiUnit, tile) == nil { return "tile-has-no-plan" }
        if let s = tile.owningSettlement { return invalidTargetReason(s, aiUnit.unit.owner) }
        return nil
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let tile = loc as? Tile { return invalidTileReason(aiUnit, tile) }
        if let colony = loc as? Colony {
            return aiUnit.unit.isOnTile ? invalidColonyReason(aiUnit, colony)
                : invalidTargetReason(colony, aiUnit.unit.owner)
        }
        return targetInvalid
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority }

    override var target: (any Location)? {
        get { pioneerTarget }
        set {
            if newValue == nil || newValue is Colony || newValue is Tile {
                pioneerTarget = newValue
                setTileImprovementPlan((newValue as? Tile).flatMap { europeanAIPlayer?.bestPlan($0) })
            }
        }
    }

    override func findTarget() -> (any Location)? {
        PioneeringMission.findMissionTarget(aiUnit, 10, true)
    }

    override func invalidReason() -> String? {
        // Improvements just completing stay valid.
        if let tip = tileImprovementPlan {
            if tip.isDisposed { return "target-plan-disposed" }
            if tip.isComplete { return nil }
        }
        return PioneeringMission.invalidMissionReason(aiUnit, target)
    }

    /// Failing drops the tools in a colony, and always drops the
    /// mission (Java's lbFail override ignores its argument).
    override func lbFail(_ cont: Bool) -> Mission? {
        if hasTools && unit.colony != nil, let role = specification?.defaultRole { _ = aiUnit.equipForRole(role) }
        return super.lbFail(false)
    }

    override func doMission() -> Mission? {
        if let tip = tileImprovementPlan {
            if tip.isComplete {
                _ = lbDone(true)
                target = nil
            } else if !tip.validate() {
                _ = lbFail(true)
                target = nil
            }
        }
        let reason = invalidReason()
        if Mission.isTargetReason(reason) { return retargetMission(reason!) }
        if reason != nil { return lbFail(false) }

        guard let player = unit.owner, let aiPlayer = europeanAIPlayer else { return lbFail(false) }
        let costDecider = CostDeciders.avoidSettlementsAndBlockingUnits()

        if !hasTools {
            // Get tools first.
            switch travelToTarget(target, costDecider) {
            case .move: break
            case .moveHighSeas, .moveNoMoves, .moveIllegal: return lbWait()
            case .moveNoRepair: return lbFail(false)
            case .moveNoAccessEmbark, .moveNoTile: return self
            default: return self
            }
            let newTarget: (any Location)?
            if let role = specification?.pioneerRole, aiUnit.equipForRole(role), hasTools {
                newTarget = PioneeringMission.findMissionTarget(aiUnit, 10, false)
                if newTarget == nil { return lbFail(false) }
            } else {
                newTarget = PioneeringMission.findMissionTarget(aiUnit, 10, false)
                if newTarget == nil || Map.isSameLocation(newTarget, target) { return lbFail(false) }
            }
            target = newTarget
            return self
        }

        // Going to an intermediate colony?
        if target is Colony && Mission.invalidTargetReason(target, player) == nil {
            switch travelToTarget(target, costDecider) {
            case .move: break
            case .moveHighSeas: return lbWait()
            case .moveNoRepair: return lbFail(false)
            case .moveNoMoves, .moveNoTile, .moveIllegal: return self
            default: return self
            }
            guard let newTarget = PioneeringMission.findMissionTarget(aiUnit, 10, false) else {
                return lbFail(false)
            }
            target = newTarget
            return self
        }

        // Go to the tile.
        guard let tile = target?.tile else { return lbFail(false) }
        while true {
            let mt = travelToTarget(target, costDecider)
            switch mt {
            case .move: break
            case .moveHighSeas: return lbWait()
            case .moveNoRepair: return lbFail(false)
            case .moveNoMoves, .moveNoTile, .moveIllegal: return self
            case .moveNoAttackCivilian:
                // Perhaps blocked at the target for now: move and retry.
                if let d = unit.tile?.direction(to: tile) { _ = moveRandomly("AI pioneer", d) }
                continue
            default: return self
            }
            break
        }

        // Take the land first.
        if !player.owns(tile) {
            var fail: Bool
            var price = player.landPrice(tile)
            if price < 0 {
                fail = true
            } else {
                if price > 0 && !player.checkGold(price) { price = Constants.stealLand }
                fail = !(aiUnit.aiOwner?.ask(.claimLand(tile: tile.id, claimant: unit.id, price: String(price)))
                         ?? false)
                    || !player.owns(tile)
            }
            if fail {
                if let tip = tileImprovementPlan {
                    aiPlayer.removeTileImprovementPlan(tip)
                    tip.dispose()
                }
                guard let newTarget = PioneeringMission.findMissionTarget(aiUnit, 10, false) else {
                    return lbFail(false)
                }
                target = newTarget
                return self
            }
        }

        // Improve.
        if unit.state == .improving { return lbWait() }
        if unit.checkSetState(.improving) {
            guard let tip = tileImprovementPlan else { return lbFail(false) }
            aiPlayer.removeTileImprovementPlan(tip)
            if aiUnit.aiOwner?.ask(.changeWorkImprovementType(unit: unit.id, improvementType: tip.type?.id)) == true {
                return lbWait()
            }
            tip.dispose()
            return lbFail(false)
        }
        return lbWait() // Out of moves.
    }
}

/// Take a unit where a colony wishes for it
/// (server/ai/mission/WishRealizationMission).
final class WishRealizationMission: Mission {

    // MARK: Saving

    override init(loading aiMain: AIMain, _ aiUnit: AIUnit, _ xr: FreeColXMLReader) throws {
        try super.init(loading: aiMain, aiUnit, xr)
    }

    override var xmlTag: String { "wishRealizationMission" }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("wish", id: wish?.id)
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let wid = xr.attribute("wish", default: nil as String?)
        wish = wid.flatMap { aiMain.aiObject($0) as? Wish }
        if wish == nil, let wid {
            if wid.hasPrefix(GoodsWish.tag) {
                wish = aiMain.reference(wid, GoodsWish.self)
            } else if wid.hasPrefix(WorkerWish.tag) {
                wish = aiMain.reference(wid, WorkerWish.self)
            }
        }
    }

    private(set) var wish: Wish?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ wish: Wish) {
        super.init(aiMain, aiUnit)
        self.wish = wish
        wish.transportable = aiUnit
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        invalidAIUnitReason(aiUnit) ?? invalidTargetReason(loc, aiUnit.unit.owner)
    }

    override func dispose() {
        if let wish {
            wish.transportable = nil
            self.wish = nil
        }
        super.dispose()
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority }

    override var target: (any Location)? {
        get { wish?.destination }
        set {}
    }

    override func findTarget() -> (any Location)? { target }

    override func invalidReason() -> String? {
        wish == nil ? "wish-null" : WishRealizationMission.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        if invalidReason() != nil { return lbFail(false) }
        let target = self.target
        switch travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits()) {
        case .move: break
        case .moveHighSeas, .moveNoMoves, .moveIllegal: return lbWait()
        case .moveNoRepair: return lbFail(false)
        case .moveNoAccessEmbark, .moveNoTile: return self
        default: return self
        }
        if let colony = target as? Colony, let aiColony = aiMain.aiColony(colony), let owner = europeanAIPlayer {
            if let wish { aiColony.completeWish(wish) }
            // A defensive mission for a soldier, work for the rest.
            if unit.type?.isOffensive ?? false {
                _ = owner.defendSettlementMission(aiUnit, colony)
            } else {
                aiColony.requestRearrange()
                _ = owner.workInsideColonyMission(aiUnit, aiColony)
            }
        }
        wish = nil // completeWish disposes of it.
        // Java then drops the unit's mission, even the new one.
        return lbDrop()
    }
}

/// Take a treasure train to be cashed in
/// (server/ai/mission/CashInTreasureTrainMission).
final class CashInTreasureTrainMission: Mission {

    // MARK: Saving

    override init(loading aiMain: AIMain, _ aiUnit: AIUnit, _ xr: FreeColXMLReader) throws {
        try super.init(loading: aiMain, aiUnit, xr)
    }

    override var xmlTag: String { "cashInTreasureTrainMission" }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let cashInTarget { xw.writeLocationAttribute("target", cashInTarget) }
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        cashInTarget = aiMain.location(xr, "target")
    }

    private var cashInTarget: (any Location)?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: (any Location)?) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    /// Have the closest carrier collect the treasure (assignCarrier).
    private func assignCarrier() -> AIUnit? {
        guard let player = unit.owner, let here = unit.location else { return nil }
        let carriers = player.units.filter { $0.couldCarry(unit) }
        var closest: Unit?
        var closestTurns = Int.max
        for c in carriers {
            let turns = c.turnsToReach(here)
            if closest == nil || turns < closestTurns {
                closest = c
                closestTurns = turns
            }
        }
        if let closest, let aiCarrier = aiMain.aiUnit(closest), let tm = aiCarrier.mission as? TransportMission {
            target = player.europe
            _ = aiUnit.changeTransport(aiCarrier)
            if tm.forceCollection(aiUnit) { return aiCarrier }
        }
        return nil
    }

    static func extractTarget(_ aiUnit: AIUnit, _ path: PathNode?) -> (any Location)? {
        guard let loc = path?.lastNode.location else { return nil }
        if loc is Europe && invalidMissionReason(aiUnit, loc) == nil { return loc }
        if let colony = loc.colony, invalidMissionReason(aiUnit, colony) == nil { return colony }
        return nil
    }

    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode?) -> Int {
        guard let path, let loc = extractTarget(aiUnit, path) else { return Int(Int32.min) }
        if let c = loc as? Colony, invalidFullColonyReason(aiUnit, c) != nil { return Int(Int32.min) }
        return aiUnit.unit.treasureAmount / (path.totalTurns + 1)
    }

    private static func goalDecider(_ aiUnit: AIUnit, _ deferOK: Bool) -> GoalDecider {
        deferring(ScoredPathDecider(Int(Int32.min)) { path in
            let loc = extractTarget(aiUnit, path)
            if let c = loc as? Colony, invalidFullColonyReason(aiUnit, c) == nil { return scorePath(aiUnit, path) }
            if loc is Europe { return scorePath(aiUnit, path) }
            return nil
        }, deferOK)
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        guard let player = unit.owner else { return nil }
        let standardCd = CostDeciders.avoidSettlementsAndBlockingUnits()
        guard player.hasSettlements, let start = unit.pathStartLocation else {
            // Straight to Europe, if there is one.
            guard let europe = player.europe, let loc = unit.location else { return nil }
            return unit.findPath(loc, europe, unit.carrier, standardCd)
        }
        return unit.search(start, goalDecider(aiUnit, deferOK), standardCd, range, unit.carrier)
    }

    static func findMissionTarget(_ aiUnit: AIUnit, _ range: Int, _ deferOK: Bool) -> (any Location)? {
        if let path = findTargetPath(aiUnit, range, deferOK) { return extractTarget(aiUnit, path) }
        return upLoc(findCircleTarget(aiUnit, goalDecider(aiUnit, deferOK), range * 3, deferOK))
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        if !unit.canCarryTreasure { return "unit-cannot-carry-treasure" }
        if unit.treasureAmount <= 0 { return "unit-treasure-nonpositive" }
        return nil
    }

    private static func invalidFullColonyReason(_ aiUnit: AIUnit, _ colony: Colony) -> String? {
        if let reason = invalidTargetReason(colony, aiUnit.unit.owner) { return reason }
        return aiUnit.unit.canCashInTreasureTrain(colony.tile) ? nil : "cashin-impossible-at-location"
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if loc is Colony || loc is Europe { return invalidTargetReason(loc, aiUnit.unit.owner) }
        return targetInvalid
    }

    override var baseTransportPriority: Int { unit.treasureAmount }

    override var target: (any Location)? {
        get { cashInTarget }
        set { if newValue == nil || newValue is Europe || newValue is Colony { cashInTarget = newValue } }
    }

    override func findTarget() -> (any Location)? {
        CashInTreasureTrainMission.findMissionTarget(aiUnit, 20, true)
    }

    override func invalidReason() -> String? {
        CashInTreasureTrainMission.invalidMissionReason(aiUnit, cashInTarget)
    }

    override func doMission() -> Mission? {
        let reason = invalidReason()
        if Mission.isTargetReason(reason) { return retargetMission(reason!) }
        if reason != nil { return lbFail(false) }
        switch travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits()) {
        case .move: break
        case .moveHighSeas, .moveNoMoves, .moveIllegal: return lbWait()
        case .moveNoRepair: return lbFail(false)
        case .moveNoAccessEmbark, .moveNoTile: return self
        default: return self
        }
        // Cash in now in Europe, if there is no Europe, if transport is
        // free, or if no carrier can be had.
        if unit.canCashInTreasureTrain(unit.location) {
            var cashin = unit.owner?.europe == nil || unit.isInEurope || unit.transportFee == 0
            if !cashin && aiUnit.transport == nil { cashin = assignCarrier() == nil }
            if cashin {
                return aiUnit.aiOwner?.ask(.cashInTreasureTrain(unit: unit.id)) == true ? lbDone(false) : lbFail(false)
            }
        }
        return retargetMission("transport expected")
    }
}

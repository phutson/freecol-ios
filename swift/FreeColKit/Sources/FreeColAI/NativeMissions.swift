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

/// Wander at random (UnitWanderMission).
final class UnitWanderMission: Mission {
    private static let tag = "AI wanderer"

    override var isOneTime: Bool { true }

    override func invalidReason() -> String? {
        Mission.invalidAIUnitReason(aiUnit)
    }

    override func doMission() -> Mission? {
        if invalidReason() != nil { return lbFail(false) }
        moveRandomlyTurn(Self.tag)
        return self
    }
}

/// Wander at random, attacking what comes near (UnitWanderHostileMission).
final class UnitWanderHostileMission: Mission {
    private static let tag = "AI hostile-wanderer"

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        if !unit.isOffensiveUnit { return unitNotOffensive }
        if !unit.hasTile { return unitNotOnMap }
        return nil
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    override var isOneTime: Bool { true }

    override func invalidReason() -> String? {
        Self.invalidMissionReason(aiUnit)
    }

    override func doMission() -> Mission? {
        if invalidReason() != nil { return lbFail(false) }
        var check = 0
        let checkTurns = Int(RandomUtils.randomInt("Hostile", aiRandom, 4))
        var d: Direction? = Direction.randomDirection(Self.tag, aiRandom)
        while unit.movesLeft > 0 {
            if check == 0 {
                if aiPlayer?.seekAndDestroyMission(aiUnit, range: 1) != nil { return lbDone(true) }
                check = checkTurns
            } else {
                check -= 1
            }
            d = moveRandomly(Self.tag, d)
            if d == nil { break }
        }
        return self
    }
}

/// Stay in a settlement, or go to the nearest (IdleAtSettlementMission).
final class IdleAtSettlementMission: Mission {
    private static let tag = "AI idler"

    private var isSafe: Bool {
        unit.isInEurope || !unit.hasTile || (unit.tile?.hasSettlement ?? false)
    }

    override var baseTransportPriority: Int { Mission.minimumTransportPriority }

    override var target: (any Location)? {
        get { isSafe ? nil : findTarget() }
        set {}
    }

    override func findTarget() -> (any Location)? {
        if isSafe { return nil }
        return unit.findOurNearestOtherSettlement().flatMap { upLoc($0.lastNode.location) }
    }

    override var isOneTime: Bool { true }

    override func invalidReason() -> String? {
        Mission.invalidAIUnitReason(aiUnit)
    }

    override func doMission() -> Mission? {
        if invalidReason() != nil { return lbFail(false) }
        if isSafe { return self }
        guard let target else {
            moveRandomlyTurn(Self.tag)
            return lbWait()
        }
        switch travelToTarget(target, nil) {
        case .move: break
        case .moveHighSeas, .moveNoMoves, .moveIllegal: return lbWait()
        case .moveNoRepair: return lbFail(false)
        case .moveNoAccessEmbark, .moveNoTile: return self
        default: return self
        }
        return self
    }
}

/// Defend a settlement (DefendSettlementMission).
final class DefendSettlementMission: Mission {
    private static let tag = "AI defender"

    private weak var settlementTarget: Settlement?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ settlement: Settlement?) {
        super.init(aiMain, aiUnit)
        target = settlement
    }

    /// The settlement at the end of a path, if it can be defended
    /// (extractTarget).
    static func extractTarget(_ aiUnit: AIUnit, _ path: PathNode?) -> (any Location)? {
        guard let path, let loc = path.lastNode.location else { return nil }
        let settlement = loc.settlement
        return invalidSettlementReason(aiUnit, settlement) == nil ? settlement : nil
    }

    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode) -> Int {
        guard let s = extractTarget(aiUnit, path) as? Settlement,
              let owner = aiUnit.aiOwner as? MissionAIPlayer else { return Int(Int32.min) }
        return owner.adjustMission(aiUnit, path, DefendSettlementMission.self,
                                   Int(JavaMath.toInt(1000 * s.settlementDefenceRatio
                                                      / Double(path.totalTurns + 1))))
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        let gd = BestPathDecider { scorePath(aiUnit, $0) }
        return unit.search(unit.pathStartLocation, gd, CostDeciders.avoidSettlementsAndBlockingUnits(), range,
                           unit.carrier)
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        if (unit.game?.combatModel.defencePower(nil, unit) ?? 0) <= 0 { return "unit-not-defender" }
        return nil
    }

    private static func invalidSettlementReason(_ aiUnit: AIUnit, _ settlement: Settlement?) -> String? {
        invalidTargetReason(settlement, aiUnit.unit.owner)
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        guard let owner = unit.owner, owner.hasSettlements else { return targetNotFound }
        if owner.isIndian { return nil }
        if !unit.isDefensiveUnit || unit.hasAbility(Ability.speakWithChief) { return unitNotOfRequiredType }
        return nil
    }

    static func invalidMissionReason(_ aiUnit: AIUnit?, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let s = loc as? Settlement { return invalidSettlementReason(aiUnit!, s) }
        return targetInvalid
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority + 5 }

    override var target: (any Location)? {
        get { settlementTarget }
        set {
            if newValue == nil || newValue is Settlement { settlementTarget = newValue as? Settlement }
        }
    }

    override func findTarget() -> (any Location)? {
        Self.findTargetPath(aiUnit, 4).flatMap { Self.extractTarget(aiUnit, $0) }
    }

    override func invalidReason() -> String? {
        Self.invalidMissionReason(aiUnit, target)
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

        if let colony = target as? Colony, unit.isInColony || (unit.isPerson && colony.unitCount < 1) {
            let m = (aiUnit.aiOwner as? EuropeanAIPlayer)?.workInsideColonyMission(aiUnit, aiMain.aiColony(colony))
            return lbDone(m != nil)
        }
        switch unit.state {
        case .fortified, .fortifying: return lbWait()
        default: break
        }
        guard let settlement = target as? Settlement else { return lbWait() }
        var defenderCount = 0, fortifyCount = 0
        for u in settlement.allUnitsList {
            if Self.invalidMissionReason(aiMain.aiUnit(u)) == nil {
                defenderCount += 1
                switch u.state {
                case .fortified, .fortifying: fortifyCount += 1
                default: break
                }
            }
        }
        if defenderCount <= 2 || fortifyCount <= 1 {
            if !unit.checkSetState(.fortifying) { return lbWait() }
            if aiUnit.aiOwner?.ask(.changeState(unit: unit.id, state: Unit.UnitState.fortifying.javaName)) == true,
               unit.state == .fortifying {
                return lbWait()
            }
            return lbFail(false)
        }
        if !unit.isOffensiveUnit { return lbFail(false) }
        guard let cm = unit.game?.combatModel, let here = unit.tile else { return lbWait() }
        var bestTarget: Unit?
        var bestDifference = Double.leastNonzeroMagnitude
        var bestDirection: Direction?
        for d in Direction.randomDirections("defendSettlements", aiRandom) {
            guard let t = here.neighbour(d), let defender = t.firstUnit,
                  defender.owner?.atWar(with: unit.owner) ?? false, unit.moveType(d).isAttack,
                  let enemyUnit = t.defendingUnit(unit) else { continue }
            let enemyAttack = cm.offencePower(enemyUnit, unit)
            let weAttack = cm.offencePower(unit, enemyUnit)
            let enemyDefend = cm.defencePower(unit, enemyUnit)
            let weDefend = cm.defencePower(enemyUnit, unit)
            let difference = weAttack / (weAttack + enemyDefend) - enemyAttack / (enemyAttack + weDefend)
            if difference > bestDifference && (difference > 0 || weAttack > enemyDefend) {
                bestDifference = difference
                bestTarget = enemyUnit
                bestDirection = d
            }
        }
        if bestTarget != nil, let d = bestDirection {
            aiUnit.aiOwner?.ask(.attack(unit: unit.id, direction: d.javaName))
            return self
        }
        return lbWait()
    }
}

/// Take a gift from the home settlement to a colony
/// (IndianBringGiftMission).
final class IndianBringGiftMission: Mission {
    private static let tag = "AI native gifter"

    private(set) weak var colony: Colony?
    private var collected = false

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: Colony) {
        super.init(aiMain, aiUnit)
        self.target = target
        collected = hasGift
    }

    private var hasGift: Bool { unit.hasGoodsCargo }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        guard let home = aiUnit!.unit.homeIndianSettlement, !home.isDisposed else { return "home-destroyed" }
        return nil
    }

    private static func invalidColonyReason(_ aiUnit: AIUnit, _ colony: Colony) -> String? {
        if let reason = invalidTargetReason(colony) { return reason }
        let unit = aiUnit.unit
        guard let owner = unit.owner, let targetPlayer = colony.owner else { return targetInvalid }
        switch owner.stance(targetPlayer) {
        case .uncontacted, .war, .ceaseFire:
            return "bad-stance"
        case .peace, .alliance:
            if let tension = unit.homeIndianSettlement?.alarm(targetPlayer),
               tension.level.ordinal > Tension.Level.happy.ordinal {
                return "unhappy"
            }
        }
        return nil
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit?, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let c = loc as? Colony { return invalidColonyReason(aiUnit!, c) }
        if loc is IndianSettlement { return invalidTargetReason(loc, aiUnit!.unit.owner) }
        return targetInvalid
    }

    override var transportDestination: (any Location)? { nil }

    override var target: (any Location)? {
        get { collected ? colony : unit.homeIndianSettlement }
        set { if let c = newValue as? Colony { colony = c } }
    }

    override func findTarget() -> (any Location)? { target }

    override func invalidReason() -> String? {
        Self.invalidMissionReason(aiUnit, colony)
    }

    override func doMission() -> Mission? {
        if invalidReason() != nil { return lbFail(false) }
        guard let owner = aiUnit.aiOwner else { return self }
        let home = unit.homeIndianSettlement
        while !collected {
            switch travelToTarget(target, nil) {
            case .move:
                break
            case .moveHighSeas, .moveNoMoves, .moveIllegal:
                return lbWait()
            case .moveNoRepair:
                return lbFail(false)
            case .moveNoTile:
                return self
            case .attackSettlement, .attackUnit:
                if let blocker = Mission.resolveBlockage(aiUnit, target), let bt = blocker.tile,
                   let d = unit.tile?.direction(to: bt),
                   owner.ask(.attack(unit: unit.id, direction: d.javaName)) {
                    return self
                }
                moveRandomly(Self.tag, nil)
                continue
            default:
                return self
            }
            guard let is_ = home, let gift = is_.randomGift(aiRandom), let type = gift.type else {
                return lbFail(false)
            }
            if !owner.ask(.loadGoods(location: is_.id, type: type.id, amount: String(gift.amount),
                                     carrier: unit.id)) || !hasGift {
                return lbFail(false)
            }
            collected = true
            return self
        }
        while true {
            switch travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits()) {
            case .moveHighSeas, .moveNoMoves, .moveIllegal:
                return lbWait()
            case .moveNoRepair:
                return lbFail(false)
            case .moveNoTile:
                return self
            case .move, .attackSettlement:
                break
            case .attackUnit:
                if let blocker = Mission.resolveBlockage(aiUnit, target), let bt = blocker.tile,
                   let d = unit.tile?.direction(to: bt),
                   owner.ask(.attack(unit: unit.id, direction: d.javaName)) {
                    return self
                }
                moveRandomly(Self.tag, nil)
                continue
            default:
                return self
            }
            let result = owner.ask(.nativeGift(unit: unit.id, colony: colony?.id))
            return result ? lbDone(false) : lbFail(false)
        }
    }
}

/// Demand goods of a colony, and take them home (IndianDemandMission).
final class IndianDemandMission: Mission {
    private static let tag = "AI native demander"
    private static let goodsDemandMin = 30

    private(set) weak var colony: Colony?
    private var demanded = false
    private var succeeded = false

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: Colony) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    private var hasTribute: Bool { unit.hasGoodsCargo }

    func setSucceeded(_ result: Bool) {
        succeeded = result
    }

    /// What to demand: food if content, the most valuable non-military
    /// goods if displeased, else military, building, trade or refined
    /// goods first (selectGoods).
    private func selectGoods(_ target: Colony) -> Goods? {
        guard let spec = specification, let game = target.game, let owner = target.owner,
              let market = owner.market else { return nil }
        let goodsTypes = spec.goodsTypeList.filter { target.goodsCount($0) > 0 }
        let dx = (spec.getInteger(GameOptions.nativeDemands) ?? 0) + 1
        func marketPrice(_ g: Goods) -> Int { market.salePrice(g.type!, g.amount) }
        func best(_ goods: [Goods]) -> Goods? {
            var ret: Goods?
            for g in goods where ret == nil || marketPrice(g) > marketPrice(ret!) { ret = g }
            return ret
        }
        func make(_ g: Goods) -> Goods { Goods(game: game, location: target, type: g.type!, amount: capAmount(g.amount, dx)) }
        let tension = unit.owner?.tension(owner).level ?? .happy
        var goods: Goods?
        if let food = spec.primaryFoodType {
            let cutoff = capAmount(target.goodsCount(food), dx)
            if tension.ordinal <= Tension.Level.content.ordinal && target.goodsCount(food) >= cutoff {
                goods = Goods(game: game, location: target, type: food, amount: cutoff)
            }
        }
        if goods == nil && tension.ordinal <= Tension.Level.displeased.ordinal {
            goods = best(target.compactGoodsList.filter { !$0.isFoodType && !($0.type?.isMilitary ?? false) })
                .map(make)
        }
        if goods == nil {
            let preds: [(GoodsType) -> Bool] = [{ $0.isMilitary }, { $0.isBuildingMaterial }, { $0.isTradeGoods },
                                                { $0.isRefined }]
            if let goodsType = preds.lazy.compactMap({ p in goodsTypes.first(where: p) }).first {
                goods = Goods(game: game, location: target, type: goodsType,
                              amount: capAmount(target.goodsCount(goodsType), dx))
            }
        }
        if goods == nil { goods = best(target.compactGoodsList).map(make) }
        return goods
    }

    private func capAmount(_ amount: Int, _ difficulty: Int) -> Int {
        min(max(amount * difficulty / 6, Self.goodsDemandMin), GoodsContainer.cargoSize)
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        guard let home = aiUnit!.unit.homeIndianSettlement, !home.isDisposed else { return "home-destroyed" }
        return nil
    }

    private static func invalidColonyReason(_ aiUnit: AIUnit, _ colony: Colony) -> String? {
        if let reason = invalidTargetReason(colony) { return reason }
        let unit = aiUnit.unit
        guard let owner = unit.owner, let targetPlayer = colony.owner else { return targetInvalid }
        switch owner.stance(targetPlayer) {
        case .uncontacted, .peace, .alliance:
            return "bad-stance"
        case .war, .ceaseFire:
            if let tension = unit.homeIndianSettlement?.alarm(targetPlayer),
               tension.level.ordinal <= Tension.Level.content.ordinal {
                return "happy"
            }
        }
        return nil
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit?, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let c = loc as? Colony { return invalidColonyReason(aiUnit!, c) }
        if loc is IndianSettlement { return invalidTargetReason(loc, aiUnit!.unit.owner) }
        return targetInvalid
    }

    override var transportDestination: (any Location)? { nil }

    override var target: (any Location)? {
        get { (demanded && succeeded) ? unit.homeIndianSettlement : colony }
        set { if let c = newValue as? Colony { colony = c } }
    }

    override func findTarget() -> (any Location)? { target }

    override func invalidReason() -> String? {
        Self.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        if invalidReason() != nil { return lbFail(false) }
        guard let owner = aiUnit.aiOwner else { return self }
        let home = unit.homeIndianSettlement
        if !demanded {
            switch travelToTarget(target, nil) {
            case .moveHighSeas, .moveNoMoves, .moveIllegal:
                return lbWait()
            case .moveNoRepair:
                return lbFail(false)
            case .moveNoTile:
                return self
            case .attackSettlement where target?.tile.flatMap({ unit.tile?.direction(to: $0) }) != nil:
                break // Arrived at the target.
            case .attackSettlement, .attackUnit:
                // Something blocks the way.
                guard let blocker = Mission.resolveBlockage(aiUnit, target), let bt = blocker.tile,
                      let d = unit.tile?.direction(to: bt) else {
                    moveRandomly(Self.tag, nil)
                    return lbWait()
                }
                return owner.ask(.attack(unit: unit.id, direction: d.javaName)) ? self : lbWait()
            default:
                return self
            }
            guard let colony = target as? Colony, let enemy = colony.owner else { return self }
            let goods = selectGoods(colony)
            var amount = goods?.amount ?? 0
            if goods == nil {
                if !enemy.checkGold(1) { return lbDone(false) }
                amount = enemy.gold / 20
                if amount == 0 { amount = enemy.gold }
            }
            demanded = owner.ask(.indianDemand(unit: unit.id, colony: colony.id, type: goods?.type?.id,
                                               amount: String(amount), result: nil))
            return lbWait()
        } else if !succeeded {
            // Perhaps attack, if not content.
            guard let colony = target as? Colony, let enemy = colony.owner else { return lbDone(false) }
            let unitTension = home?.alarm(enemy)?.value ?? 0
            let tension = max(unitTension, unit.owner?.tension(enemy).value ?? 0)
            if let ct = colony.tile, let d = unit.tile?.direction(to: ct),
               tension >= Tension.Level.content.limit {
                owner.ask(.attack(unit: unit.id, direction: d.javaName))
            }
            return lbDone(false)
        } else if !hasTribute {
            return lbDone(true)
        } else {
            // Take the goods home.
            switch travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits()) {
            case .move:
                break
            case .moveHighSeas, .moveNoMoves, .moveIllegal:
                return lbWait()
            case .moveNoRepair:
                return lbFail(false)
            case .moveNoTile:
                return self
            default:
                return self
            }
            // Java puts the goods in the settlement itself, without the
            // server.
            if let container = unit.goodsContainer, let home {
                for goods in container.compactGoodsList {
                    if let type = goods.type, let tribute = container.removeGoods(type) {
                        _ = home.addGoods(tribute)
                    }
                }
            }
            return lbDone(false)
        }
    }
}

/// Attack a settlement or unit (UnitSeekAndDestroyMission).
final class UnitSeekAndDestroyMission: Mission {
    private static let tag = "AI seek+destroyer"

    private weak var targetObject: FreeColGameObject?
    private var transportTarget: (any Location)?

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ target: (any Location)?) {
        super.init(aiMain, aiUnit)
        self.target = target
    }

    /// What to attack at the end of a path: a settlement, or the unit
    /// defending the tile (extractTarget).
    static func extractTarget(_ aiUnit: AIUnit?, _ path: PathNode?) -> (any Location)? {
        guard let aiUnit, let loc = path?.lastNode.location else { return nil }
        if invalidSettlementReason(aiUnit, loc.settlement) == nil { return loc.settlement }
        if let t = loc.tile, let u = t.defendingUnit(aiUnit.unit), invalidTargetReason(aiUnit, u) == nil {
            return u
        }
        return nil
    }

    private static func scoreSettlementPath(_ aiUnit: AIUnit, _ path: PathNode, _ settlement: Settlement) -> Int {
        if invalidSettlementReason(aiUnit, settlement) != nil { return Int(Int32.min) }
        let unit = aiUnit.unit
        guard let cm = unit.game?.combatModel, let owner = aiUnit.aiOwner as? MissionAIPlayer else {
            return Int(Int32.min)
        }
        // In Java's int arithmetic, which wraps: a path the search has
        // not settled has 2^30 turns, and a hundred times that is nothing.
        var value = Int32(1020) &- Int32(truncatingIfNeeded: path.totalTurns) &* 100
        let off = cm.offencePower(unit, settlement)
        value = value &+ Int32(truncatingIfNeeded: JavaMath.round(off * 50))
        let settled = Int32(truncatingIfNeeded: settlement.settlementValue(Int(value), unit))
        return owner.adjustMission(aiUnit, path, UnitSeekAndDestroyMission.self, Int(settled))
    }

    /// The score of a path.  As in Java, a unit's score is worked out
    /// and dropped, so only settlements are ever chosen.
    static func scorePath(_ aiUnit: AIUnit, _ path: PathNode, _ onlySettlements: Bool,
                          _ noNativeSettlements: Bool) -> Int {
        let loc = extractTarget(aiUnit, path)
        if let s = loc as? Settlement {
            if noNativeSettlements && s is IndianSettlement { return Int(Int32.min) }
            return scoreSettlementPath(aiUnit, path, s)
        }
        return Int(Int32.min)
    }

    private static func findTargetPath(_ aiUnit: AIUnit, _ range: Int, _ onlySettlements: Bool,
                                       _ noNativeSettlements: Bool) -> PathNode? {
        if invalidAIUnitReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        let gd = BestPathDecider { scorePath(aiUnit, $0, onlySettlements, noNativeSettlements) }
        return unit.search(unit.pathStartLocation, gd, CostDeciders.avoidIllegal(), range, unit.carrier)
    }

    static func findMissionTarget(_ aiUnit: AIUnit, _ range: Int, _ onlySettlements: Bool,
                                  _ noNativeSettlements: Bool) -> (any Location)? {
        findTargetPath(aiUnit, range, onlySettlements, noNativeSettlements).flatMap { extractTarget(aiUnit, $0) }
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        let unit = aiUnit!.unit
        if !unit.isOffensiveUnit { return unitNotOffensive }
        if unit.hasAbility(Ability.speakWithChief) { return "scouts-should-not-seek-and-destroy" }
        return nil
    }

    private static func invalidSettlementReason(_ aiUnit: AIUnit, _ settlement: Settlement?) -> String? {
        if let reason = invalidTargetReason(settlement) { return reason }
        let unit = aiUnit.unit
        if unit.isNaval { return "unit-is-naval" }
        if settlement!.owner === unit.owner { return targetOwnership }
        return invalidAttackReason(aiUnit, settlement!.owner)
    }

    private static func invalidTargetReason(_ aiUnit: AIUnit, _ unit: Unit) -> String? {
        if let reason = invalidTargetReason(unit) { return reason }
        guard let tile = unit.tile else { return "target-not-on-map" }
        if aiUnit.unit.owner === unit.owner { return targetOwnership }
        if tile.hasSettlement { return "target-in-settlement" }
        if !aiUnit.unit.isTileAccessible(tile) { return "target-incompatible" }
        return invalidAttackReason(aiUnit, unit.owner)
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit?, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if let s = loc as? Settlement { return invalidSettlementReason(aiUnit!, s) }
        if let u = loc as? Unit { return invalidTargetReason(aiUnit!, u) }
        return targetInvalid
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority - 5 }

    override var transportDestination: (any Location)? {
        guard isValid else { return nil }
        let loc = transportTarget ?? target
        return unit.shouldTakeTransportTo(loc) ? loc : nil
    }

    override var target: (any Location)? {
        get { targetObject as? any Location }
        set {
            guard newValue == nil || newValue is Unit || newValue is Settlement else { return }
            targetObject = newValue as? FreeColGameObject
            transportTarget = nil
            if unit.shouldTakeTransportTo(newValue), let settlement = newValue as? Settlement,
               settlement.isConnectedPort, let owner = unit.owner {
                transportTarget = settlement.tile?.bestDisembarkTile(owner)
            }
        }
    }

    override func findTarget() -> (any Location)? {
        Self.findMissionTarget(aiUnit, 4, false, false)
    }

    override func invalidReason() -> String? {
        Self.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        let reason = invalidReason()
        if Mission.isTargetReason(reason) {
            if reason == Mission.targetOwnership, let colony = target as? Colony,
               player?.owns(colony) ?? false, aiPlayer?.defendSettlementMission(aiUnit, colony) != nil {
                return lbDone(true)
            }
            return retargetMission(reason!)
        } else if reason != nil {
            return lbFail(false)
        }
        // Natives always like attacking natives; the European AI decides.
        let noNativeSettlementsAttack = (aiPlayer as? EuropeanAIPlayer).map { !$0.likesAttackingNatives } ?? false
        var nearbyTarget = unit.isOnCarrier ? nil
            : Self.findMissionTarget(aiUnit, 1, false, noNativeSettlementsAttack)
        if let nearby = nearbyTarget {
            if target == nil {
                target = nearby
                return self
            }
            if nearby === target {
                nearbyTarget = nil
            } else if let now = unit.tile, let nearbyTile = nearby.tile, let targetTile = target?.tile,
                      now.distance(to: nearbyTile) >= now.distance(to: targetTile) {
                nearbyTarget = nil
            }
        }
        let currentTarget = nearbyTarget ?? target
        switch travelToTarget(currentTarget, CostDeciders.avoidSettlementsAndBlockingUnits()) {
        case .moveHighSeas, .moveNoMoves, .moveIllegal:
            return lbWait()
        case .moveNoRepair:
            return lbFail(false)
        case .moveNoAccessEmbark, .moveNoTile:
            return self
        case .attackUnit, .attackSettlement:
            guard let unitTile = unit.tile else { return lbWait() }
            if let settlement = unitTile.settlement, settlement.unitCount < 2 {
                let m = aiPlayer?.defendSettlementMission(aiUnit, settlement)
                return lbDone(m != nil)
            }
            guard let ct = currentTarget?.tile, let d = unitTile.direction(to: ct) else { return lbWait() }
            aiUnit.aiOwner?.ask(.attack(unit: unit.id, direction: d.javaName))
            return self
        default:
            return self
        }
    }
}

/// A goal decider keeping the best scoring path, as the missions'
/// anonymous ones do.
final class BestPathDecider: GoalDecider {
    private(set) var goal: PathNode?
    private var bestValue = Int(Int32.min)
    private let score: (PathNode) -> Int

    init(_ score: @escaping (PathNode) -> Int) {
        self.score = score
    }

    var hasSubGoals: Bool { true }

    func check(_ unit: Unit?, _ path: PathNode) -> Bool {
        let value = score(path)
        if bestValue < value {
            bestValue = value
            goal = path
            return true
        }
        return false
    }
}

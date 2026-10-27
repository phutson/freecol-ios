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

/// The natives' AI (server/ai/NativeAIPlayer): stances from tension,
/// settlements defended and their braves armed, gifts and demands, and
/// braves wandering, attacking what they hate.
final class NativeAIPlayer: MissionAIPlayer {

    static let maxDistanceToBringGifts = 5
    static let maxNumberOfGiftsBeingDelivered = 1
    static let maxDistanceToMakeDemands = 5
    static let maxNumberOfDemands = 1

    // MARK: The turn

    override func startWorking() {
        let turn = game.turn
        let nSettlements = player.settlementCount
        clearAIUnits()
        determineStances()
        var more: [AIUnit]
        if turn.isFirstTurn {
            initializeMissions()
            more = aiUnits()
        } else {
            abortInvalidMissions()
            if nSettlements > 0 {
                var randoms = RandomUtils.randomInts("Trades", aiRandom, Int32(nSettlements), nSettlements)
                secureSettlements(randoms.map(Int.init))
                randoms = RandomUtils.randomInts("Gifts", aiRandom, 100, nSettlements)
                bringGifts(randoms.map(Int.init))
                randoms = RandomUtils.randomInts("Tribute", aiRandom, 100, nSettlements)
                demandTribute(randoms.map(Int.init))
            }
            giveNormalMissions()
            more = doMissions(aiUnits())
        }
        if !more.isEmpty {
            abortInvalidMissions()
            giveNormalMissions()
            _ = doMissions(more)
        }
        clearAIUnits()
    }

    /// The first turn: the braves beyond those defending wander.
    private func initializeMissions() {
        for settlement in player.indianSettlementList {
            var units = settlement.allUnitsList
            while units.count > settlement.requiredDefenders {
                let u = units.removeFirst()
                if let aiu = aiUnit(u) { _ = wanderHostileMission(aiu) }
            }
            for u in units {
                if let aiu = aiUnit(u) { _ = defendSettlementMission(aiu, settlement) }
            }
        }
    }

    private func determineStances() {
        for p in game.livePlayers(excluding: player) {
            let newStance = determineStance(p)
            if newStance != player.stance(p) {
                do {
                    try aiMain.controller.changeStance(player, newStance, p, true)
                } catch {
                    aiMain.record(error, "changing stance")
                }
            }
        }
    }

    private func secureSettlements(_ randoms: [Int]) {
        let settlements = player.indianSettlementList
        for (i, settlement) in settlements.enumerated() {
            let other = settlements[randoms[i]]
            if other !== settlement { settlement.tradeGoodsWithSettlement(other) }
        }
        for settlement in settlements {
            equipBraves(settlement)
            secureIndianSettlement(settlement)
        }
    }

    /// Arm the braves that can be, the strongest last (equipBraves).
    func equipBraves(_ settlement: IndianSettlement) {
        guard let cm = game.combatModel as CombatModel? else { return }
        let units = settlement.allUnitsList.stableSorted { cm.compareMilitaryStrength($0, $1) < 0 }
        for u in units {
            if let r = settlement.canImproveUnitMilitaryRole(u) {
                _ = aiUnit(u)?.equipForRole(r)
            }
        }
    }

    /// Defend a settlement against the threats round it: call in or
    /// release defenders, and send braves at the threats
    /// (secureIndianSettlement).
    func secureIndianSettlement(_ settlement: IndianSettlement) {
        guard let isTile = settlement.tile, let minimumSize = settlement.type?.minimumSize else { return }
        let cm = game.combatModel
        let minimumDefence = minimumSize - 1
        var units = settlement.allUnitsList
        var defenders: [Unit] = []
        for u in settlement.ownedUnitList where !units.contains(where: { $0 === u }) { units.append(u) }
        for u in units {
            guard let aiu = aiMain.aiUnit(u) else {
                units.removeAll { $0 === u }
                continue
            }
            if let dm = aiu.mission as? DefendSettlementMission, dm.target === settlement {
                defenders.append(u)
                units.removeAll { $0 === u }
            } else if Mission.invalidNewMissionReason(aiu) != nil {
                units.removeAll { $0 === u }
            }
        }

        // Java keeps the threats in a HashMap by tile.
        var threats = JavaHashMap<Tile, Double>(javaHash: { $0.javaGameObjectHash })
        for t in isTile.surroundingTiles(settlement.radius + 1) {
            guard t.isLand, t.unitCount > 0, let first = t.firstUnit else { continue }
            let enemy = first.owner
            if enemy === player {
                for u in t.unitList {
                    guard !defenders.contains(where: { $0 === u }), !units.contains(where: { $0 === u }),
                          let aiu = aiMain.aiUnit(u) else { continue }
                    if let dm = aiu.mission as? DefendSettlementMission, dm.target === settlement {
                        defenders.append(u)
                    } else if Mission.invalidNewMissionReason(aiu) == nil {
                        units.append(u)
                    }
                }
            } else if let tension = settlement.alarm(enemy),
                      tension.level.ordinal > Tension.Level.content.ordinal {
                let threshold: Double, bonus: Double
                if tension.level.ordinal <= Tension.Level.displeased.ordinal {
                    threshold = 1.0
                    bonus = 0.0
                } else {
                    threshold = 0.0
                    bonus = Double(Float(tension.level.ordinal) - Float(Tension.Level.content.ordinal))
                }
                var value = 0.0
                for u in t.unitList where cm.offencePower(u, settlement) > threshold {
                    value += cm.offencePower(u, settlement) + bonus
                }
                if value > 0.0 { _ = threats.put(t, value) }
            }
        }

        let homeBonus = 3
        func isScore(_ u: Unit) -> Int {
            (u.tile?.distance(to: isTile) ?? 0) - (u.homeIndianSettlement === settlement ? homeBonus : 0)
        }
        let needed = minimumDefence + threats.count
        if defenders.count < needed {
            units = units.stableSorted { isScore($0) < isScore($1) }
            while !units.isEmpty {
                let u = units.removeFirst()
                if let aiu = aiMain.aiUnit(u), defendSettlementMission(aiu, settlement) != nil {
                    defenders.append(u)
                    if defenders.count >= needed { break }
                }
            }
        } else if defenders.count > needed {
            defenders = defenders.stableSorted { isScore($0) > isScore($1) }
            while defenders.count > needed { units.append(defenders.removeFirst()) }
        }

        var threatTiles = threats.keys.stableSorted { threats[$0]! < threats[$1]! }
        while !threatTiles.isEmpty && !units.isEmpty {
            let tile = threatTiles.removeFirst()
            var best: Unit?
            var bestScore = 0
            for u in units {
                guard let ut = u.tile else { continue }
                let score = ut.distance(to: tile)
                guard UnitSeekAndDestroyMission.invalidMissionReason(aiMain.aiUnit(u), tile.defendingUnit(u)) == nil,
                      score >= 0 else { continue }
                if best == nil || score < bestScore {
                    best = u
                    bestScore = score
                }
            }
            guard let unit = best else { continue }
            units.removeAll { $0 === unit }
            if let aiu = aiMain.aiUnit(unit) { _ = seekAndDestroyMission(aiu, tile.defendingUnit(unit)) }
        }
    }

    /// Missions for the units without a valid one: defend a settlement
    /// left with one unit, or one that can arm it; otherwise patrol
    /// (giveNormalMissions).
    private func giveNormalMissions() {
        var units = aiUnits()
        units.removeAll { aiu in
            let unit = aiu.unit
            if unit.isDisposed { return true }
            if let m = aiu.mission, m.isValid, !m.isOneTime { return true }
            return false
        }
        for aiu in units {
            let unit = aiu.unit
            var m = aiu.mission
            if let settlement = unit.settlement, settlement.unitCount + (settlement.tile?.unitCount ?? 0) <= 1 {
                if !(m is DefendSettlementMission) || m?.target !== settlement {
                    m = defendSettlementMission(aiu, settlement)
                }
            } else if let home = unit.homeIndianSettlement, home.canImproveUnitMilitaryRole(unit) != nil {
                if !(m is DefendSettlementMission) || m?.target !== home {
                    m = defendSettlementMission(aiu, home)
                }
            } else if !(m is UnitWanderHostileMission) {
                m = wanderHostileMission(aiu)
            }
        }
    }

    /// Settlements send gifts, at random, to colonies near (bringGifts).
    private func bringGifts(_ randoms: [Int]) {
        let cd = CostDeciders.numberOfLegalTiles()
        let giftPercent = specification?.getPercentage(GameOptions.giftProbability) ?? 0
        for (i, settlement) in player.indianSettlementList.enumerated() {
            if randoms[i] >= giftPercent { continue }
            guard settlement.randomGift(aiRandom) != nil else { continue }
            var availableUnits: [Unit] = []
            var alreadyAssigned = 0
            for ou in settlement.ownedUnitList {
                guard let aiu = aiUnit(ou) else { continue }
                if aiu.mission is IndianBringGiftMission {
                    alreadyAssigned += 1
                } else if Mission.invalidNewMissionReason(aiu) == nil {
                    availableUnits.append(ou)
                }
            }
            if alreadyAssigned > Self.maxNumberOfGiftsBeingDelivered || availableUnits.isEmpty { continue }
            guard let home = settlement.tile else { continue }
            var unit: Unit?
            var chosen: AIUnit?
            while unit == nil && !availableUnits.isEmpty {
                let u = availableUnits[Int(RandomUtils.randomInt("Gift unit", aiRandom, Int32(availableUnits.count)))]
                availableUnits.removeAll { $0 === u }
                chosen = aiUnit(u)
                if IndianBringGiftMission.invalidMissionReason(chosen) == nil, let ut = u.tile,
                   u.findPath(ut, home, nil, cd) != nil {
                    unit = u
                }
            }
            guard let unit, let aiu = chosen else { continue }
            var nearbyColonies: [RandomChoice<Colony>] = []
            for t in home.surroundingTiles(Self.maxDistanceToBringGifts) {
                guard let c = t.colony, settlement.hasContacted(c.owner),
                      IndianBringGiftMission.invalidMissionReason(aiu, c) == nil,
                      let ct = c.tile, let path = unit.findPath(home, ct, nil, cd) else { continue }
                let alarm = max(1, settlement.alarm(c.owner)?.value ?? 0)
                nearbyColonies.append(RandomChoice(c, 1000000 / alarm / (1 + path.totalTurns)))
            }
            if nearbyColonies.isEmpty { continue }
            guard let target = RandomChoice.weightedRandom("Choose gift colony", nearbyColonies, aiRandom) else {
                preconditionFailure("No gift target: \(self)")
            }
            _ = IndianBringGiftMission(aiMain, aiu, target)
        }
    }

    /// Settlements demand tribute, at random, of colonies near
    /// (demandTribute).
    private func demandTribute(_ randoms: [Int]) {
        let cd = CostDeciders.numberOfLegalTiles()
        let demandPercent = specification?.getPercentage(GameOptions.demandProbability) ?? 0
        for (i, settlement) in player.indianSettlementList.enumerated() {
            if randoms[i] >= demandPercent { continue }
            var availableUnits: [Unit] = []
            var alreadyAssigned = 0
            for ou in settlement.ownedUnitList {
                let aiu = aiUnit(ou)
                if Mission.invalidNewMissionReason(aiu) == nil {
                    if aiu?.mission is IndianDemandMission {
                        alreadyAssigned += 1
                    } else {
                        availableUnits.append(ou)
                    }
                }
            }
            if alreadyAssigned > Self.maxNumberOfDemands || availableUnits.isEmpty { continue }
            guard let home = settlement.tile else { continue }
            var unit: Unit?
            var chosen: AIUnit?
            while unit == nil && !availableUnits.isEmpty {
                let u = availableUnits[Int(RandomUtils.randomInt("Demand unit", aiRandom,
                                                                 Int32(availableUnits.count)))]
                availableUnits.removeAll { $0 === u }
                chosen = aiUnit(u)
                if IndianDemandMission.invalidMissionReason(chosen) == nil, let ut = u.tile,
                   u.findPath(ut, home, nil, cd) != nil {
                    unit = u
                }
            }
            guard let unit, let aiu = chosen else { continue }
            var nearbyColonies: [RandomChoice<Colony>] = []
            for t in home.surroundingTiles(Self.maxDistanceToMakeDemands) {
                guard let c = t.colony, settlement.hasContacted(c.owner),
                      IndianDemandMission.invalidMissionReason(aiu, c) == nil,
                      let ct = c.tile, let path = unit.findPath(home, ct, nil, cd) else { continue }
                let alarm = settlement.alarm(c.owner)?.value ?? 0
                let defence = c.unitCount + (c.stockade.map { $0.level * 10 } ?? 1)
                // Java's int arithmetic, which wraps.
                let weight = Int(Int32(1) &+ Int32(truncatingIfNeeded: alarm)
                                 &* Int32(truncatingIfNeeded: 1000000 / defence / (1 + path.totalTurns)))
                nearbyColonies.append(RandomChoice(c, weight))
            }
            if nearbyColonies.isEmpty { continue }
            guard let target = RandomChoice.weightedRandom("Choose demand colony", nearbyColonies, aiRandom)
            else { continue }
            _ = IndianDemandMission(aiMain, aiu, target)
        }
    }

    /// Drop the missions that are no longer valid.
    func abortInvalidMissions() {
        for au in aiUnits() {
            if let m = au.mission, m.invalidReason() != nil { au.changeMission(nil) }
        }
    }

    override func adjustMission(_ aiUnit: AIUnit, _ path: PathNode, _ type: Mission.Type, _ value: Int) -> Int {
        var value = value
        if type == DefendSettlementMission.self {
            if let settlement = DefendSettlementMission.extractTarget(aiUnit, path) as? Settlement {
                value -= 75 * settlementDefenders(settlement)
            }
        } else if type == UnitSeekAndDestroyMission.self {
            let target = UnitSeekAndDestroyMission.extractTarget(aiUnit, path)
            let targetPlayer = (target as? Ownable)?.owner
            if let targetPlayer, let home = aiUnit.unit.homeIndianSettlement, let alarm = home.alarm(targetPlayer) {
                value += alarm.value - Tension.Level.displeased.limit
            }
        }
        return value
    }

    // MARK: Answers

    /// A demand's answer: one of ours learns whether it succeeded
    /// (indianDemand).
    override func indianDemand(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int,
                               _ accept: IndianDemandAction?) -> IndianDemandAction {
        if unit.owner === player, let aiu = aiUnit(unit), let mission = aiu.mission as? IndianDemandMission,
           let accept, accept != .done {
            mission.setSucceeded(accept == .accept)
        }
        return .done
    }

    private func shipTradePenalties(_ sense: Bool) -> [Modifier] {
        guard let spec = specification else { return [] }
        let penalty = (sense ? 1 : -1) * (spec.getInteger(GameOptions.shipTradePenalty) ?? 0)
        return spec.modifiers(Modifier.shipTradePenalty).map {
            let m = Modifier(copying: $0)
            m.value = Float(penalty)
            return m
        }
    }

    /// Price the trade's goods, angrier the higher (updateTrade).
    private func updateTrade(_ nt: NativeTrade, _ anger: Int) {
        guard let spec = specification, let settlement = nt.indianSettlement, let unit = nt.unit else { return }
        let turn = game.turn
        var modifiers: [Modifier] = []
        let enhanced = spec.getBoolean(GameOptions.enhancedMissionaries) ?? false
        if settlement.hasMissionary(unit.owner) && enhanced, let u = settlement.missionary {
            modifiers += u.missionaryTradeModifiers(true)
        }
        if unit.isNaval { modifiers += shipTradePenalties(true) }
        for nti in nt.unitToSettlement {
            guard let g = nti.goods, let type = g.type else { continue }
            var price = Int(JavaMath.toInt(FeatureContainer.applyModifiers(
                1.0 / Float(anger) * Float(settlement.priceToBuy(type, g.amount)), turn: turn, modifiers)))
            for _ in stride(from: nti.haggleCount, through: 0, by: -1) { price = NativeTrade.haggleUp(price) }
            if price <= NativeTradeItem.priceUnset { price = NativeTradeItem.priceInvalid }
            nti.price = price
        }
        modifiers = []
        if settlement.hasMissionary(unit.owner) && enhanced, let u = settlement.missionary {
            modifiers += u.missionaryTradeModifiers(false)
        }
        if unit.isNaval { modifiers += shipTradePenalties(false) }
        for nti in nt.settlementToUnit {
            guard let g = nti.goods, let type = g.type else { continue }
            var price = Int(JavaMath.toInt(FeatureContainer.applyModifiers(
                Float(anger) * Float(settlement.priceToSell(type, g.amount)), turn: turn, modifiers)))
            for _ in stride(from: nti.haggleCount, through: 0, by: -1) { price = NativeTrade.haggleDown(price) }
            if price <= NativeTradeItem.priceUnset { price = NativeTradeItem.priceInvalid }
            nti.price = price
        }
    }

    /// The natives' side of a trade (handleTrade).
    override func handleTrade(_ action: NativeTrade.NativeTradeAction, _ nt: NativeTrade)
        -> NativeTrade.NativeTradeAction {
        let haggleNumber = 3
        guard let settlement = nt.indianSettlement, player.owns(settlement), let unit = nt.unit,
              let tension = settlement.alarm(unit.owner) else { return .nakInvalid }
        func anger(_ angry: Int) -> Int {
            switch tension.level {
            case .happy, .content: return 1
            case .displeased: return 2
            case .angry: return angry
            default: return -1
            }
        }
        switch action {
        case .open:
            let a = anger(-1)
            if a < 0 { return .nakHostile }
            updateTrade(nt, a)
            return nt.isDone ? .nakNosale : .ackOpen
        case .buy:
            let a = anger(-1)
            if a < 0 { return .nakHostile }
            updateTrade(nt, a)
            guard let item = nt.item, let ours = nt.settlementToUnit.first(where: { $0.goodsMatches(item) }) else {
                return .nakInvalid
            }
            if item.priceIsSet && item.price >= ours.price { return .ackBuy }
            let haggle = ours.haggleCount + 1
            if RandomUtils.randomInt("Haggle-buy", aiRandom, Int32(haggleNumber + haggle)) >= haggleNumber {
                return .nakHaggle
            }
            ours.haggleCount = haggle
            updateTrade(nt, a)
            nt.item = ours
            return .ackBuyHaggle
        case .sell:
            let military = nt.unitToSettlement.contains { $0.goods?.type?.isMilitary ?? false }
            let a = anger(military ? 3 : -1)
            if a < 0 { return .nakHostile }
            updateTrade(nt, a)
            guard let item = nt.item, let ours = nt.unitToSettlement.first(where: { $0.goodsMatches(item) }) else {
                return .nakInvalid
            }
            if item.priceIsSet && item.price <= ours.price { return .ackSell }
            let haggle = ours.haggleCount + 1
            if RandomUtils.randomInt("Haggle-sell", aiRandom, Int32(haggleNumber + haggle)) >= haggleNumber {
                return .nakHaggle
            }
            ours.haggleCount = haggle
            updateTrade(nt, a)
            nt.item = ours
            return .ackSellHaggle
        case .gift:
            guard let item = nt.item, nt.unitToSettlement.contains(where: { $0.goodsMatches(item) }),
                  let goods = item.goods else { return .nakInvalid }
            return settlement.canAdd(goods) ? .ackGift : .nakGoods
        default:
            return .nakInvalid
        }
    }
}

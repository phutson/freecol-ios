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

extension Wish {
    /// Java's Wish.hashCode: the identifier and value, the destination
    /// and the transportable.
    var javaWishHash: Int32 {
        var hash = id.map(JavaString.hashCode) ?? 31
        hash = 37 &* hash &+ Int32(truncatingIfNeeded: value)
        hash = 37 &* hash &+ ((destination as? FreeColGameObject)?.javaGameObjectHash ?? 31)
        let t: Int32
        if let aiu = transportable as? AIUnit {
            t = aiu.javaHash
        } else if transportable != nil {
            t = 31 // AIGoods are not carried for wishes in these games.
        } else {
            t = 31
        }
        return 37 &* hash &+ t
    }
}

extension WorkerWish {
    /// Java's WorkerWish.hashCode.
    var javaHash: Int32 {
        let hash = 37 &* javaWishHash &+ unitType.javaHashCode
        return 37 &* hash &+ (expertNeeded ? 1 : 0)
    }
}

/// The rest of a European computer player's turn: the first turn's
/// missions, Java's cheats, buying in Europe, giving units missions and
/// carrying them out (server/ai/EuropeanAIPlayer).
extension EuropeanAIPlayer {

    static let buildingRange = 5
    static let cashInRange = 20
    static let missionaryRange = 20
    static let pioneeringRange = 10
    static let privateerRange = 1
    static let scoutingRange = 20

    // MARK: The first turn

    /// Missions for the units on the first turn: colony builders aboard
    /// each ship, then the ship's transport, then the rest
    /// (initializeMissions).
    func initializeMissions() {
        let units = aiUnits()
        guard let map = game.map else { return }
        let maxRange = map.width + map.height
        for aiCarrier in units where !aiCarrier.hasMission {
            let carrier = aiCarrier.unit
            if !carrier.isNaval { continue }
            for u in carrier.unitList {
                guard let aiu = aiMain.aiUnit(u) else { continue }
                var target: (any Location)?
                var range = EuropeanAIPlayer.buildingRange
                while range < maxRange {
                    target = BuildColonyMission.findMissionTarget(aiu, range, false)
                    if target != nil { break }
                    range += EuropeanAIPlayer.buildingRange
                }
                guard let target else {
                    aiMain.record(JavaException("RuntimeException: Initial colony fail: \(u)"),
                                  player.nationId ?? "")
                    return
                }
                _ = buildColonyMission(aiu, target)
            }
            // The carrier's mission after the passengers', so that the
            // transport list and target work.
            if let tm = transportMission(aiCarrier) as? TransportMission {
                for u in carrier.unitList {
                    if let aiu = aiMain.aiUnit(u) { tm.queueTransportable(aiu, false) }
                }
            }
        }
        for aiu in units where !aiu.hasMission {
            _ = simpleMission(aiu)
        }
    }

    // MARK: Cheats

    /// Make sure the player has some gold (cheatGold).
    func cheatGold(_ amount: Int) {
        let gold = player.gold
        if gold < amount { _ = player.modifyGold(amount - gold) }
    }

    /// Java's cheats for its AI: lifting boycotts, equipping scouts and
    /// pioneers, units for wishes, mercenaries, and ships (cheat).
    func cheat() {
        guard aiMain.singlePlayer, player.playerType == .colonial, let spec = specification,
              let europe = player.europe else { return }
        let market = player.market
        let air = aiRandom
        let arrears = market.map { m in spec.goodsTypeList.filter { m.arrears($0) > 0 } } ?? []
        let randoms = RandomUtils.randomInts("cheats", air, 100, arrears.count + 6).map { Int($0) }
        var cheatIndex = 0
        func next() -> Int {
            defer { cheatIndex += 1 }
            return randoms[cheatIndex]
        }
        let percent = { (id: String) in spec.getInteger(id) ?? 0 }

        for goodsType in arrears where next() < percent(GameOptions.liftBoycottCheat) {
            market?.setArrears(goodsType, 0)
            // Remove one goods party modifier.
            func partyModifier(_ c: Colony) -> Modifier? {
                c.modifiers().first { $0.source?.id == Specification.SourceId.colonyGoodsParty }
            }
            let parties = player.colonyList.filter { partyModifier($0) != nil }
            if let party = RandomUtils.randomMember("end boycott", parties, air) {
                _ = party.removeModifier(partyModifier(party))
            }
        }

        let equipPred = { (u: Unit) in u.hasDefaultRole && u.hasAbility(Ability.canBeEquipped) }
        if !europe.isEmpty && scoutsNeeded > 0 && next() < percent(GameOptions.equipScoutCheat) {
            for u in europe.unitList where equipPred(u) {
                guard let role = spec.scoutRole,
                      let g = try? europe.priceGoods(u.goodsDifference(role, 1)) else { continue }
                cheatGold(g)
                if let scout = spec.roleWithAbility(Ability.speakWithChief),
                   aiUnit(u)?.equipForRole(scout) ?? false { break }
            }
        }
        if !europe.isEmpty && pioneersNeeded > 0 && next() < percent(GameOptions.equipPioneerCheat) {
            for u in europe.unitList where equipPred(u) {
                guard let role = spec.pioneerRole,
                      let g = try? europe.priceGoods(u.goodsDifference(role, 1)) else { continue }
                cheatGold(g)
                if let pioneer = spec.roleWithAbility(Ability.improveTerrain),
                   aiUnit(u)?.equipForRole(pioneer) ?? false { break }
            }
        }

        if next() < percent(GameOptions.landUnitCheat) {
            // The most valuable of the first wishes for each unit type
            // that can be had in Europe, in Java's HashSet order.
            var firsts: [WorkerWish] = []
            for (ut, wishes) in workerWishes.entries
            where ut.isAvailableTo(player) && europe.unitPrice(ut) != Constants.undefined && !wishes.isEmpty {
                firsts.append(wishes[0])
            }
            var bestWish: WorkerWish?
            for w in javaHashSetOrder(firsts, { $0.javaHash }) where bestWish == nil || w.value > bestWish!.value {
                bestWish = w
            }
            let cost = bestWish.map { europe.unitPrice($0.unitType) }
                ?? (player.immigration < player.immigrationRequired / 2 ? player.europeanRecruitPrice
                    : Constants.infinity)
            if cost != Constants.infinity {
                cheatGold(cost)
                if let bestWish {
                    if let aiu = trainAIUnitInEurope(bestWish.unitType) { _ = wishRealizationMission(aiu, bestWish) }
                } else {
                    _ = recruitAIUnitInEurope(-1) // giveNormalMissions finds its mission.
                }
            }
        }

        if game.turn.number > 300 && player.isAtWar && next() < percent(GameOptions.offensiveLandUnitCheat) {
            aiMain.record(NotYetPorted("the European AI's mercenary cheat"), player.nationId ?? "")
        }

        // Always a new armed ship if the navy is gone; otherwise a chance
        // in proportion to how far below average it is.
        let naval = navalStrengthRatio()
        let nNaval = player.unitCount(naval: true) == 0 ? 100
            : (0 < naval && naval < 0.5) ? Int(JavaMath.toInt(naval * Double(percent(GameOptions.offensiveNavalUnitCheat))))
            : -1
        let choice = { (ut: UnitType) in RandomChoice(ut, 100000 / europe.unitPrice(ut)) }
        if next() < nNaval {
            _ = cheatUnit(spec.unitTypeList.filter {
                $0.hasAbility(Ability.navalUnit) && $0.isAvailableTo(player) && $0.hasPrice && $0.isOffensive
            }.map(choice))
        }
        // Carriers only if there is work for them.
        let nCarrier = nNavalCarrier > 0 ? percent(GameOptions.transportNavalUnitCheat) : -1
        if next() < nCarrier {
            _ = cheatUnit(spec.unitTypeList.filter {
                $0.hasAbility(Ability.navalUnit) && $0.isAvailableTo(player) && $0.hasPrice && $0.space > 0
            }.map(choice))
        }
    }

    private func cheatUnit(_ rc: [RandomChoice<UnitType>]) -> AIUnit? {
        guard let unitType = RandomChoice.weightedRandom("Cheat which unit", rc, aiRandom) else { return nil }
        return cheatUnit(unitType)
    }

    private func cheatUnit(_ unitType: UnitType) -> AIUnit? {
        guard let europe = player.europe else { return nil }
        cheatGold(europe.unitPrice(unitType))
        return trainAIUnitInEurope(unitType)
    }

    // MARK: Europe

    /// Recruit in Europe (recruitAIUnitInEurope).
    func recruitAIUnitInEurope(_ requested: Int) -> AIUnit? {
        guard let europe = player.europe else { return nil }
        let n = europe.unitCount
        var slot = requested
        if !Europe.MigrationType.validMigrantSlot(slot) {
            slot = player.hasAbility(Ability.selectRecruit) ? Europe.MigrationType.defaultSlot
                : Europe.MigrationType.unspecificSlot
        }
        if ask(.emigrateUnit(slot: String(slot))) && europe.unitCount == n + 1,
           let aiu = aiUnit(europe.unitList[n]) {
            addAIUnit(aiu)
            return aiu
        }
        return nil
    }

    /// Train in Europe (trainAIUnitInEurope).
    func trainAIUnitInEurope(_ unitType: UnitType) -> AIUnit? {
        guard let europe = player.europe else { return nil }
        let n = europe.unitCount
        if ask(.trainUnitInEurope(unitType: unitType.id)) && europe.unitCount == n + 1,
           let aiu = aiUnit(europe.unitList[n]) {
            addAIUnit(aiu)
            return aiu
        }
        return nil
    }

    /// Buy ships, artillery, dragoons and wished-for workers in Europe
    /// (buyUnitsInEurope).
    func buyUnitsInEurope() {
        guard let europe = player.europe else { return }
        let numberOfUnitsInDock = europe.unitList.filter { !$0.isNaval }.count
        let numberOfShips = aiUnits().filter(\.unit.isNaval).count
        if numberOfUnitsInDock > 6 && numberOfShips < 15 {
            if !buyShip() { return }
        }
        if numberOfUnitsInDock > 30 { return }

        var militaryUnitBought = numberOfUnitsInDock >= 18
        if !militaryUnitBought {
            if reallyNeedsMoreArtillery || (likesAttackingNatives && needsMoreArtillery) {
                if buyArtillery() == nil { return }
                militaryUnitBought = true
            }
            if reallyNeedsMoreDragoons || (likesAttackingNatives && needsMoreDragoons) {
                if buyDragoon() == nil { return }
                militaryUnitBought = true
            }
        }

        for w in wishes() {
            guard let workerWish = w as? WorkerWish, w.transportable == nil else { continue }
            let unitType = workerWish.unitType
            if !unitType.isAvailableTo(player) { continue }
            let unitPrice = europe.unitPrice(unitType)
            if unitPrice <= 0 { continue }
            if unitPrice > player.gold { return }
            if let newUnit = trainAIUnitInEurope(unitType) { _ = wishRealizationMission(newUnit, workerWish) }
            if !militaryUnitBought {
                militaryUnitBought = true
                if buyDragoon() == nil { return }
            }
        }

        for _ in 0..<6 where buyDragoon() == nil { return }
    }

    /// Buy a carrier (buyShip).  Java shuffles the ship types with its
    /// own unseeded generator; the AI oracle's patch keeps the
    /// specification's order, as here.
    private func buyShip() -> Bool {
        guard let spec = specification else { return false }
        let unitTypes = spec.unitTypeList.filter {
            $0.hasAbility(Ability.navalUnit) && $0.isAvailableTo(player) && $0.hasPrice && $0.space > 0
        }
        guard let first = unitTypes.first, let role = spec.defaultRole?.id else { return false }
        let au = AbstractUnit(id: first.id, roleId: role, number: 1)
        let price = player.europeanPurchasePrice(au)
        if price <= 0 || price == Constants.infinity || price > player.gold { return false }
        _ = player.modifyGold(-price)
        _ = player.createUnits([au], player.europe, aiRandom)
        return true
    }

    private var armedMountedCount: Int {
        aiUnits().filter { $0.unit.isMounted && $0.unit.isArmed }.count
    }

    private var needsMoreDragoons: Bool { 2 * (aiColonies().count + 1) > armedMountedCount }

    private var reallyNeedsMoreDragoons: Bool { aiColonies().count + 1 > armedMountedCount }

    var reallyNeedsMoreArtillery: Bool {
        aiColonies().count / 2 + 1 > aiUnits().filter { $0.unit.hasAbility(Ability.bombard) }.count
    }

    /// Buy a dragoon: pay for the cheapest trained unit as a dragoon,
    /// but make a free colonist one (buyDragoon).
    private func buyDragoon() -> Unit? {
        guard let spec = specification,
              let dragoonRole = spec.militaryRolesList.first(where: {
                  $0.hasAbility(Ability.armed) && $0.hasAbility(Ability.mounted)
              }),
              let role = dragoonRole.id else { return nil }
        guard let cheapest = spec.unitTypesTrainedInEurope(player)
            .filter({ $0.price > 0 && $0.price != Constants.infinity })
            .stableSorted(by: { $0.price < $1.price }).first else { return nil }
        let price = player.europeanPurchasePrice(AbstractUnit(id: cheapest.id, roleId: role, number: 1))
        if price <= 0 || price == Constants.infinity || price > player.gold { return nil }
        _ = player.modifyGold(-price)
        guard let defaultType = spec.defaultUnitType else { return nil }
        return player.createUnits([AbstractUnit(id: defaultType.id, roleId: role, number: 1)], player.europe,
                                  aiRandom).first
    }

    /// Train the cheapest artillery (buyArtillery).
    private func buyArtillery() -> Unit? {
        guard let spec = specification, let europe = player.europe else { return nil }
        guard let cheapest = spec.unitTypesPurchasedInEurope(player)
            .filter({ $0.price > 0 && $0.price != Constants.infinity && $0.hasAbility(Ability.bombard)
                && $0.isAvailableTo(player) })
            .stableSorted(by: { $0.price < $1.price }).first else { return nil }
        if europe.unitPrice(cheapest) > player.gold { return nil }
        return trainAIUnitInEurope(cheapest)?.unit
    }

    // MARK: Nations

    /// A nation summary, asked for if not to hand (getNationSummary).
    func nationSummary(_ other: Player) -> NationSummary? {
        let id = other.id ?? ""
        if let ns = nationSummaries[id] { return ns }
        ask(.nationSummary(player: other.id))
        return nationSummaries[id]
    }

    /// The naval strength against the other colonial powers' average
    /// (getNavalStrengthRatio).  Java looks for this player among the
    /// others, so its own strength is always zero.
    private func navalStrengthRatio() -> Double {
        var navalAverage = 0.0
        let navalStrength = 0.0
        var nPlayers = 0
        for p in game.liveEuropeanPlayers(excluding: player) where !p.isREF {
            guard let ns = nationSummary(p) else { continue }
            let st = ns.navalStrength
            if st >= 0 { navalAverage += Double(st) }
            nPlayers += 1
        }
        if nPlayers <= 0 || navalStrength < 0 { return -1 }
        navalAverage /= Double(nPlayers)
        return navalAverage == 0 ? -1 : navalStrength / navalAverage
    }

    // MARK: Wishes and transport

    /// The transportables, the most valuable first (getTransportables).
    func transportables() -> [TransportableAIObject] {
        transportSupply.sortedByDescendingValue()
    }

    /// A transport mission takes on a transportable (claimTransportable).
    @discardableResult
    func claimTransportable(_ t: TransportableAIObject) -> Bool {
        guard let i = transportSupply.firstIndex(where: { $0 === t }) else { return false }
        transportSupply.remove(at: i)
        return true
    }

    /// The best worker wish for a unit to go to: the most valuable per
    /// turn of those in reach, else the most valuable (getBestWorkerWish).
    private func bestWorkerWish(_ aiUnit: AIUnit, _ unitType: UnitType?) -> WorkerWish? {
        guard let unitType, let wishes = workerWishes[unitType] else { return nil }
        let unit = aiUnit.unit
        var carried: WorkerWish?, other: WorkerWish?
        var bestCarriedValue = -1.0, bestOtherValue = -1.0
        for w in wishes {
            guard let dest = w.destination else { continue }
            let turns = unit.turnsToReach(dest)
            if turns < Unit.manyTurns {
                if bestCarriedValue < Double(w.value) / Double(turns) {
                    bestCarriedValue = Double(w.value) / Double(turns)
                    carried = w
                }
            } else if bestOtherValue < Double(w.value) {
                bestOtherValue = Double(w.value)
                other = w
            }
        }
        return carried ?? other
    }

    /// Take a worker wish for a unit (consumeWorkerWish).
    private func consumeWorkerWish(_ aiUnit: AIUnit, _ ww: WorkerWish) {
        if let type = aiUnit.unit.type, var list = workerWishes[type] {
            removeFirst(&list, ww)
            _ = workerWishes.put(type, list)
        }
        if let dest = ww.destination {
            let key = LocationKey(location: dest)
            if var list = transportDemand[key] {
                removeFirst(&list, ww)
                _ = transportDemand.put(key, list)
            }
        }
        ww.transportable = aiUnit
    }

    /// Take a goods wish for some goods (consumeGoodsWish).
    func consumeGoodsWish(_ aig: AIGoods, _ gw: GoodsWish) {
        if let type = aig.goodsType, var list = goodsWishes[type] {
            removeFirst(&list, gw)
            _ = goodsWishes.put(type, list)
        }
        if let dest = gw.destination {
            let key = LocationKey(location: dest)
            if var list = transportDemand[key] {
                removeFirst(&list, gw)
                _ = transportDemand.put(key, list)
            }
        }
        gw.transportable = aig
    }

    // MARK: Tile improvements

    /// Add a new colony's plans to the tile map (updateTipMap).
    func updateTipMap(_ aic: AIColony) {
        for tip in aic.currentTileImprovementPlans {
            if let t = tip.target { _ = tipMap.put(t, tip) }
        }
    }

    /// Forget a plan, here and in its colony (removeTileImprovementPlan).
    func removeTileImprovementPlan(_ plan: TileImprovementPlan) {
        if let t = plan.target { tipMap.removeValue(forKey: t) }
        for aic in aiColonies() where aic.removeTileImprovementPlan(plan) { break }
    }

    // MARK: Counts

    /// How many units should be building colonies (buildersNeeded).
    private func buildersNeeded() -> Int {
        if !player.canBuildColonies { return 0 }
        var nColonies = 0, nPorts = 0, nColonySize1 = 0
        for s in player.settlements {
            nColonies += 1
            if s.isConnectedPort { nPorts += 1 }
            if s.unitList.count == 1 { nColonySize1 += 1 }
        }
        if nPorts == 0 { return 2 }
        if nPorts == 1 { return 1 }
        if nColonies < 3 { return 1 }
        if nColonySize1 < 2 { return 1 }
        return 0
    }

    /// How many pioneers there should be (pioneersNeeded).
    var pioneersNeeded: Int { (tipMap.count + 1) / 2 }

    // MARK: Missions

    /// Give the units missions: builders, scouts and pioneers to their
    /// quotas, then simple missions, then the ships, then fallbacks
    /// (giveNormalMissions).  The units given missions are removed from
    /// the list, which Java's caller keeps for the next pass.
    func giveNormalMissions(_ aiUnits: inout [AIUnit]) {
        nBuilders = buildersNeeded()
        nPioneers = pioneersNeeded
        nScouts = scoutsNeeded
        var bcm: BuildColonyMission?
        var navalUnits: [AIUnit] = []
        var done: [AIUnit] = []
        var transportMissions: [TransportMission] = []

        func removeDone() {
            aiUnits.removeAll { u in done.contains { $0 === u } }
            done = []
        }

        // Which units need a mission, counting the valid ones.
        for aiUnit in aiUnits {
            let unit = aiUnit.unit
            var m = aiUnit.mission
            let oldTarget = m?.target
            if unit.isDisposed {
                // Invalid.
            } else if unit.isDamaged {
                if !(m is IdleAtSettlementMission) { _ = idleAtSettlementMission(aiUnit) }
            } else if unit.state == .inColony, let colony = unit.colony, colony.unitCount <= 1 {
                // Vital to the colony.
                if !(m is WorkInsideColonyMission),
                   workInsideColonyMission(aiUnit, aiMain.aiColony(colony)) != nil {
                    updateTransport(aiUnit, oldTarget)
                }
            } else if unit.isInMission {
                // At a mission.
            } else if let mm = m, mm.isValid, !mm.isOneTime {
                if let b = mm as? BuildColonyMission {
                    bcm = b
                    nBuilders -= 1
                } else if mm is PioneeringMission {
                    nPioneers -= 1
                } else if mm is ScoutingMission {
                    nScouts -= 1
                } else if let tm = mm as? TransportMission {
                    // Quiet offensive carriers might privateer.
                    if tm.isEmpty && unit.isNaval && unit.isOffensiveUnit {
                        navalUnits.append(aiUnit)
                        done.append(aiUnit)
                        continue
                    }
                    if tm.destinationCapacity() > 0 { transportMissions.append(tm) }
                } else if mm is PrivateerMission, !(mm.target is Unit) {
                    // Not chasing: might carry.
                    navalUnits.append(aiUnit)
                    done.append(aiUnit)
                    continue
                }
            } else if unit.isNaval {
                navalUnits.append(aiUnit)
            } else if unit.isAtSea {
                // Wait for it to emerge.
            } else {
                continue // Needs a mission.
            }
            m = nil
            done.append(aiUnit)
        }
        removeDone()

        // Builders pile onto a building mission while there are no
        // colonies.
        if let bcm, !player.hasSettlements {
            let bcmTarget = bcm.target
            for aiUnit in aiUnits.stableSorted(by: { $0.builderScore > $1.builderScore }) {
                let oldTarget = aiUnit.mission?.target
                if buildColonyMission(aiUnit, bcmTarget) == nil { continue }
                updateTransport(aiUnit, oldTarget)
                done.append(aiUnit)
                if requestsTransport(aiUnit) { transportSupply.append(aiUnit) }
            }
            removeDone()
        }
        if nBuilders > 0 {
            // Java gives up after 50 tries.
            var tries = 0
            for aiUnit in aiUnits.stableSorted(by: { $0.builderScore > $1.builderScore }) {
                if aiUnit.unit.isArmed && game.turn.number > 20 { continue }
                tries += 1
                if tries > 50 { break }
                let oldTarget = aiUnit.mission?.target
                if buildColonyMission(aiUnit, nil) == nil { continue }
                updateTransport(aiUnit, oldTarget)
                done.append(aiUnit)
                if requestsTransport(aiUnit) { transportSupply.append(aiUnit) }
                nBuilders -= 1
                if nBuilders <= 0 { break }
            }
            removeDone()
        }
        if nScouts > 0 {
            for aiUnit in aiUnits.stableSorted(by: { $0.scoutScore > $1.scoutScore }) {
                let oldTarget = aiUnit.mission?.target
                if scoutingMission(aiUnit) == nil { continue }
                updateTransport(aiUnit, oldTarget)
                done.append(aiUnit)
                if requestsTransport(aiUnit) { transportSupply.append(aiUnit) }
                nScouts -= 1
                if nScouts <= 0 { break }
            }
            removeDone()
        }
        if nPioneers > 0 {
            for aiUnit in aiUnits.stableSorted(by: { $0.pioneerScore > $1.pioneerScore }) {
                let oldTarget = aiUnit.mission?.target
                if pioneeringMission(aiUnit, nil) == nil { continue }
                updateTransport(aiUnit, oldTarget)
                done.append(aiUnit)
                if requestsTransport(aiUnit) { transportSupply.append(aiUnit) }
                nPioneers -= 1
                if nPioneers <= 0 { break }
            }
            removeDone()
        }

        // Simple missions for the other land units.
        for aiUnit in aiUnits {
            let oldTarget = aiUnit.mission?.target
            if simpleMission(aiUnit) == nil { continue }
            updateTransport(aiUnit, oldTarget)
            done.append(aiUnit)
            if requestsTransport(aiUnit) { transportSupply.append(aiUnit) }
        }
        removeDone()

        // The free ships, perhaps adding transport.
        var navalDone: [AIUnit] = []
        for aiUnit in navalUnits {
            guard let m = simpleMission(aiUnit) else { continue }
            navalDone.append(aiUnit)
            if let tm = m as? TransportMission {
                if tm.destinationCapacity() > 0 { transportMissions.append(tm) }
                // A new transport mission may have given its passengers
                // valid missions.
                for u in aiUnit.unit.unitList {
                    guard let aiu = aiMain.aiUnit(u), let um = aiu.mission, um.isValid,
                          aiUnits.contains(where: { $0 === aiu }) else { continue }
                    aiUnits.removeAll { $0 === aiu }
                }
            }
        }
        navalUnits.removeAll { u in navalDone.contains { $0 === u } }

        // Fallbacks for the rest: work in a port, or idle.
        aiUnits.append(contentsOf: navalUnits)
        var ports: [Colony]?
        let nPorts = player.numberOfPorts
        for aiUnit in aiUnits {
            let unit = aiUnit.unit
            let m = aiUnit.mission
            let oldTarget = m?.target
            if let m, m.isValid, !m.isOneTime { continue } // Java warns
            if nPorts > 0 && unit.isInEurope && unit.isPerson {
                if ports == nil { ports = player.connectedPortList }
                guard !(ports?.isEmpty ?? true) else { continue }
                let c = ports!.removeFirst()
                if workInsideColonyMission(aiUnit, aiMain.aiColony(c)) != nil { updateTransport(aiUnit, oldTarget) }
                ports!.append(c)
            } else if m is IdleAtSettlementMission {
                // Already idle.
            } else if idleAtSettlementMission(aiUnit) != nil {
                updateTransport(aiUnit, oldTarget)
            }
        }

        // Java's urgent transportables are always none, so there is
        // nothing to allocate.
        _ = transportMissions
    }

    /// The obvious mission for a unit (getSimpleMission).
    func simpleMission(_ aiUnit: AIUnit) -> Mission? {
        let unit = aiUnit.unit
        let old: Mission? = (aiUnit.mission?.isValid ?? false) ? aiUnit.mission : nil
        var m: Mission?
        if unit.isNaval {
            if old is PrivateerMission { return old }
            if !unit.isInEurope, let p = privateerMission(aiUnit, nil) { return p }
            if old is TransportMission { return old }
            if let t = transportMission(aiUnit) { return t }
            if let p = privateerMission(aiUnit, nil) { return p }
            if old is UnitSeekAndDestroyMission { return old }
            if let s = seekAndDestroyMission(aiUnit, range: 8) { return s }
            if old is UnitWanderHostileMission { return old }
            return wanderHostileMission(aiUnit)
        } else if unit.isCarrier {
            return transportMission(aiUnit)
        }
        // Cashing in is obvious.
        if old is CashInTreasureTrainMission { return old }
        if let c = cashInTreasureTrainMission(aiUnit) { return c }
        // So is working in a colony.
        if unit.isInColony && old is WorkInsideColonyMission { return old }
        if unit.isInColony, let w = workInsideColonyMission(aiUnit, nil) { return w }
        // Local defence.
        if let d = old as? DefendSettlementMission, let c = d.target as? Colony, !c.isVeryWellDefended { return old }
        if let d = defendCurrentSettlementMission(aiUnit) { return d }
        // The REF attacks.
        if unit.hasAbility(Ability.refUnit) {
            if old is UnitSeekAndDestroyMission { return old }
            if let s = seekAndDestroyMission(aiUnit, range: 12) { return s }
            return wanderHostileMission(aiUnit)
        }
        // Experts realize wishes.
        if unit.isColonist && unit.skillLevel > 0 && old is WishRealizationMission { return old }
        if unit.isColonist && unit.skillLevel > 0, let w = wishRealizationMission(aiUnit, nil) { return w }
        // Ordinary defence.
        if let d = defendSettlementMission(aiUnit, false, false) { return d }
        // Nearby offence.
        if old is UnitSeekAndDestroyMission { return old }
        if let s = seekAndDestroyMission(aiUnit, range: 8) { return s }
        // Missionaries.
        if old is MissionaryMission { return old }
        if let mm = missionaryMission(aiUnit) { return mm }
        // Other wishes, such as for people.
        if old is WishRealizationMission { return old }
        if let w = wishRealizationMission(aiUnit, nil) { return w }
        // Relaxed defence, longer range offence, any defence.
        if let d = defendSettlementMission(aiUnit, true, false) { return d }
        if let s = seekAndDestroyMission(aiUnit, range: 16) { return s }
        if let d = defendSettlementMission(aiUnit, true, true) { return d }
        // Wander, looking for trouble.
        if old is UnitWanderHostileMission { return old }
        m = wanderHostileMission(aiUnit)
        return m
    }

    /// A colony building mission (getBuildColonyMission).
    private func buildColonyMission(_ aiUnit: AIUnit, _ target: (any Location)?) -> Mission? {
        if BuildColonyMission.invalidMissionReason(aiUnit) != nil { return nil }
        guard let target = target ?? BuildColonyMission.findMissionTarget(aiUnit, EuropeanAIPlayer.buildingRange,
                                                                         aiUnit.unit.isInEurope) else { return nil }
        return BuildColonyMission(aiMain, aiUnit, target)
    }

    /// A treasure cashing mission (getCashInTreasureTrainMission).
    private func cashInTreasureTrainMission(_ aiUnit: AIUnit) -> Mission? {
        if CashInTreasureTrainMission.invalidMissionReason(aiUnit) != nil { return nil }
        guard let loc = CashInTreasureTrainMission.findMissionTarget(aiUnit, EuropeanAIPlayer.cashInRange,
                                                                    aiUnit.unit.isInEurope) else { return nil }
        return CashInTreasureTrainMission(aiMain, aiUnit, loc)
    }

    /// Defend the colony that most needs it, nearest first, if badly
    /// defended (or any if asked), by turns or tiles if relaxed
    /// (getDefendSettlementMission).
    func defendSettlementMission(_ aiUnit: AIUnit, _ relaxed: Bool, _ includeWellDefended: Bool) -> Mission? {
        if DefendSettlementMission.invalidMissionReason(aiUnit) != nil { return nil }
        let unit = aiUnit.unit
        guard let loc = unit.location else { return nil }
        var worstValue = Double.greatestFiniteMagnitude
        var worstColony: Colony?
        for aic in aiColonies() {
            let colony = aic.colony
            guard aic.isBadlyDefended || includeWellDefended, let tile = colony.tile else { continue }
            if unit.isAtLocation(tile) {
                worstColony = colony
                break
            }
            let ttr = 1 + unit.turnsToReach(loc, tile, unit.carrier, relaxed ? CostDeciders.numberOfTiles() : nil)
            if ttr >= Unit.manyTurns { continue }
            let value = colony.defenceRatio * 10 + Double(ttr)
            if value < worstValue {
                worstValue = value
                worstColony = colony
            }
        }
        return worstColony.flatMap { defendSettlementMission(aiUnit, $0) }
    }

    /// A privateering mission (getPrivateerMission).
    func privateerMission(_ aiUnit: AIUnit, _ target: (any Location)?) -> Mission? {
        if PrivateerMission.invalidMissionReason(aiUnit) != nil { return nil }
        guard let target = target ?? PrivateerMission.findMissionTarget(aiUnit, EuropeanAIPlayer.privateerRange,
                                                                       true) else { return nil }
        return PrivateerMission(aiMain, aiUnit, target)
    }

    /// A transport mission (getTransportMission).
    func transportMission(_ aiUnit: AIUnit) -> Mission? {
        if TransportMission.invalidMissionReason(aiUnit) != nil { return nil }
        return TransportMission(aiMain, aiUnit)
    }

    /// A mission to realize a worker wish (getWishRealizationMission).
    private func wishRealizationMission(_ aiUnit: AIUnit, _ requested: WorkerWish?) -> Mission? {
        if WishRealizationMission.invalidMissionReason(aiUnit) != nil { return nil }
        guard let wish = requested ?? bestWorkerWish(aiUnit, aiUnit.unit.type) else { return nil }
        consumeWorkerWish(aiUnit, wish)
        return WishRealizationMission(aiMain, aiUnit, wish)
    }

}

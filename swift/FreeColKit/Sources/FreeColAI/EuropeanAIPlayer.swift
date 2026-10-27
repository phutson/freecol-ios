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

import func Foundation.pow
import FreeColCore
import FreeColServer
import FreeColUtil
import FreeColXML

/// A location as a key, compared by identity and hashed as Java hashes
/// its game object.
struct LocationKey: Hashable {
    let location: any Location

    static func == (a: LocationKey, b: LocationKey) -> Bool { a.location === b.location }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(location)) }
    var javaHash: Int32 { (location as? FreeColGameObject)?.javaGameObjectHash ?? 0 }
}

/// A European computer player (server/ai/EuropeanAIPlayer).  Its
/// answers to the server are ported, and the colony part of its turn:
/// stances, its colonies' plans and wishes, and arranging their
/// workers.  The rest of its turn (its units' missions, buying, and
/// Java's cheats) comes in Phase 4's next step; until then it works
/// only with AIMain.Works.colonies, which the AI oracle's patched
/// EuropeanAIPlayer matches.
class EuropeanAIPlayer: MissionAIPlayer {

    /// The best plan for each tile.
    var tipMap = JavaHashMap<Tile, TileImprovementPlan>(javaHash: { $0.javaGameObjectHash })
    /// The wishes waiting for transport, by destination.
    var transportDemand = JavaHashMap<LocationKey, [Wish]>(javaHash: { $0.javaHash })
    /// What needs transport.
    var transportSupply: [TransportableAIObject] = []
    /// The goods wishes by goods type, and worker wishes by unit type.
    var goodsWishes = JavaHashMap<GoodsType, [GoodsWish]>(javaHash: { $0.javaHashCode })
    var workerWishes = JavaHashMap<UnitType, [WorkerWish]>(javaHash: { $0.javaHashCode })
    /// The wagons needed, by contiguity.
    var wagonsNeeded = JavaHashMap<Int, Int>(javaHash: { Int32(truncatingIfNeeded: $0) })
    /// The colonies badly defended at the start of the turn.
    private(set) var badlyDefended: [AIColony] = []
    var nBuilders = 0
    var nPioneers = 0
    var nScouts = 0
    var nNavalCarrier = 0

    /// Whether this nation likes attacking natives (the conquest
    /// nations).
    var likesAttackingNatives: Bool {
        player.nation?.type?.id == "model.nationType.conquest"
    }

    /// Whether the nation uses its army aggressively (the conquest and
    /// immigration nations).
    var isAggressive: Bool {
        let id = player.nation?.type?.id
        return id == "model.nationType.conquest" || id == "model.nationType.immigration"
    }

    var coloniesOnly: Bool { aiMain.works == .colonies }

    /// The player's turn (startWorking): stances, colonies, Java's
    /// cheats, buying in Europe, the military, and missions for the
    /// rest, three times over.
    override func startWorking() {
        let turn = game.turn
        clearAIUnits()
        nationSummaries.removeAll()
        badlyDefended.removeAll()
        // Java gathers the units now, before anything can make more.
        let colonyCount = aiColonies().count
        _ = aiUnits()
        if turn.isFirstTurn && !coloniesOnly { initializeMissions() }

        if likesAttackingNatives && turn.number > 100 {
            for p in game.livePlayers(excluding: player) where p.isIndian {
                player.setTension(p, Tension(Tension.tensionMax))
            }
        }
        determineStances()

        if colonyCount > 0 {
            for aic in aiColonies() where aic.isBadlyDefended { badlyDefended.append(aic) }
            for aic in aiColonies() { aic.update() }
            buildTipMap()
            buildWishMaps()
        }

        if coloniesOnly {
            // The colonies only, as the oracle's patch does.
            buildTransportMaps()
            do {
                for _ in 0..<3 { try rearrangeColonies() }
            } catch {
                aiMain.record(error, "\(player.nationId ?? "") rearranging colonies")
                return
            }
        } else {
            cheat()
            buyUnitsInEurope()
            var units = aiUnits()
            let militaryUnits = javaHashSetOrder(aiUnits().filter(MilitaryCoordinator.isUnitHandled)) {
                $0.javaHash
            }
            MilitaryCoordinator(self, militaryUnits).determineMissions()
            buildTransportMaps()
            var normalAIUnits = aiUnits().filter { !MilitaryCoordinator.isUnitHandled($0) }
            do {
                for _ in 0..<3 {
                    try rearrangeColonies()
                    try giveMissions(&normalAIUnits)
                    if units.isEmpty { break }
                    units = doMissions(units)
                }
            } catch {
                aiMain.record(error, "\(player.nationId ?? "") giving missions")
                return
            }
        }
        clearAIUnits()
        tipMap.removeAll()
        transportDemand.removeAll()
        transportSupply.removeAll()
        wagonsNeeded.removeAll()
        goodsWishes.removeAll()
        workerWishes.removeAll()
    }

    // MARK: Doing missions

    /// Carry out the missions (doMissions), updating transport, and a
    /// new colony at once so later units see its plans.
    ///
    /// - Returns: The units with moves left, to do again.
    override func doMissions(_ aiUnits: [AIUnit]) -> [AIUnit] {
        var result: [AIUnit] = []
        for aiu in aiUnits {
            let unit = aiu.unit
            if unit.isDisposed { continue }
            guard let oldMission = aiu.mission else {
                // Delivered, and its wish completed: back to
                // giveNormalMissions.
                result.append(aiu)
                continue
            }
            let oldTarget = oldMission.target
            let oldLocation = unit.location
            let oldColony = oldLocation?.colony
            aiu.doMission()
            if unit.isDisposed || unit.location == nil {
                aiu.dropTransport()
                continue
            }
            updateTransport(aiu, oldTarget)
            // A unit can disembark onto a fatal rumour.
            if unit.isDisposed || unit.location == nil { continue }
            if unit.movesLeft > 0 && (!unit.isOnCarrier || (unit.carrier?.movesLeft ?? 0) > 0) {
                result.append(aiu)
            }
            if oldColony == nil, let newColony = unit.location?.colony, Map.isSameLocation(oldLocation, newColony),
               let aiColony = aiMain.aiColony(newColony) {
                aiColony.update()
                updateTipMap(aiColony)
            }
        }
        return result
    }

    /// Fewer defenders where there are many, and fewer behind a stockade
    /// (adjustMission).
    override func adjustMission(_ aiUnit: AIUnit, _ path: PathNode, _ type: Mission.Type, _ value: Int) -> Int {
        guard value > 0, type == DefendSettlementMission.self else { return value }
        guard let colony = DefendSettlementMission.extractTarget(aiUnit, path) as? Colony else {
            aiMain.record(JavaException("IllegalStateException: European players defend colonies"),
                          player.nationId ?? "")
            return value
        }
        let defenders = settlementDefenders(colony)
        var v = value - 25 * defenders
        if colony.hasStockade, let level = colony.stockade?.level {
            v -= defenders > level + 1 ? 100 * level : 20 * level
        }
        return v
    }

    // MARK: Colonies

    /// The player's colonies' AI, in the order of its colonies
    /// (getAIColonies).
    func aiColonies() -> [AIColony] {
        player.colonyList.compactMap { aiMain.aiColony($0) }
    }

    private func rearrangeColonies() throws {
        for aic in aiColonies() { try aic.rearrangeColony() }
    }

    override func removeAIObject(_ ao: AIObject) {
        if let aic = ao as? AIColony {
            removeAIColony(aic)
        } else {
            super.removeAIObject(ao)
        }
    }

    /// Forget a colony's plans and transport (removeAIColony).  Missions
    /// that depend on it come with the European missions.
    private func removeAIColony(_ aic: AIColony) {
        let colony = aic.colony
        for t in colony.ownedTiles { tipMap.removeValue(forKey: t) }
        for aig in aic.currentExportGoods where Map.isSameLocation(aig.location, colony) {
            _ = aig.changeTransport(nil)
            aig.dispose()
        }
        transportDemand.removeValue(forKey: LocationKey(location: colony))
    }

    /// The best tile improvement plan for each tile, dropping plans
    /// done or broken (buildTipMap).
    func buildTipMap() {
        tipMap.removeAll()
        for aic in aiColonies() {
            for tip in aic.currentTileImprovementPlans {
                if tip.isComplete {
                    aic.removeTileImprovementPlan(tip)
                } else if tip.pioneer != nil {
                    // Removed when complete.
                } else if !tip.validate() {
                    aic.removeTileImprovementPlan(tip)
                    tip.dispose()
                } else if let target = tip.target {
                    if let other = tipMap[target], other.value >= tip.value { continue }
                    _ = tipMap.put(target, tip)
                }
            }
        }
    }

    /// The best plan for a tile.
    func bestPlan(_ tile: Tile) -> TileImprovementPlan? {
        tipMap[tile]
    }

    /// The wishes of all the colonies, the most valuable first
    /// (getWishes).
    func wishes() -> [Wish] {
        aiColonies().flatMap(\.currentWishes).sortedByDescendingValue()
    }

    /// The wishes by type, of those waiting for something
    /// (buildWishMaps).
    private func buildWishMaps() {
        guard let spec = specification else { return }
        for unitType in spec.unitTypeList { _ = workerWishes.put(unitType, []) }
        for goodsType in spec.storableGoodsTypeList { _ = goodsWishes.put(goodsType, []) }
        for w in wishes() {
            if let ww = w as? WorkerWish {
                if ww.transportable == nil { _ = workerWishes.put(ww.unitType, (workerWishes[ww.unitType] ?? []) + [ww]) }
            } else if let gw = w as? GoodsWish {
                if gw.destination is Colony {
                    _ = goodsWishes.put(gw.goodsType, (goodsWishes[gw.goodsType] ?? []) + [gw])
                }
            }
        }
    }

    /// Forget a completed wish (completeWish).
    func completeWish(_ w: Wish) {
        if let ww = w as? WorkerWish, var wl = workerWishes[ww.unitType] {
            removeFirst(&wl, ww)
            _ = workerWishes.put(ww.unitType, wl)
        } else if let gw = w as? GoodsWish, var gl = goodsWishes[gw.goodsType] {
            removeFirst(&gl, gw)
            _ = goodsWishes.put(gw.goodsType, gl)
        }
    }

    // MARK: Transport

    /// Count the wagons needed for a contiguity: zero primes a
    /// contiguity with a connected port (changeNeedWagon).
    private func changeNeedWagon(_ tile: Tile?, _ amount: Int) {
        guard let tile, tile.contiguity > 0 else { return }
        let contig = tile.contiguity
        if let i = wagonsNeeded[contig] {
            _ = wagonsNeeded.put(contig, i + amount)
        } else if amount == 0 {
            _ = wagonsNeeded.put(contig, 0)
        }
    }

    /// The wagons needed where a tile is (getNeededWagons).
    func neededWagons(_ tile: Tile?) -> Int {
        guard let tile, tile.contiguity > 0 else { return 0 }
        return wagonsNeeded[tile.contiguity] ?? 0
    }

    /// Whether more artillery is wanted: one for each colony, and one.
    var needsMoreArtillery: Bool {
        aiColonies().count + 1 > aiUnits().filter { $0.unit.hasAbility(Ability.bombard) }.count
    }

    /// The scouts wanted: three early on, then fewer.
    var scoutsNeeded: Int { 3 - game.turn.number / 100 }

    /// Whether something is queued on its carrier's transport mission,
    /// dropping the carrier if not (checkTransport).
    @discardableResult
    func checkTransport(_ t: TransportableAIObject) -> Bool {
        guard let aiCarrier = t.transport else { return false }
        if let tm = aiCarrier.mission as? TransportMission, tm.isTransporting(t) { return true }
        _ = t.changeTransport(nil)
        return false
    }

    func requestsTransport(_ t: TransportableAIObject) -> Bool {
        t.transport == nil && t.transportDestination != nil && t.transportSource != nil && !(t.location is Unit)
    }

    /// What needs carrying, and the carriers needed (buildTransportMaps).
    private func buildTransportMaps() {
        transportDemand.removeAll()
        transportSupply.removeAll()
        wagonsNeeded.removeAll()
        nNavalCarrier = 0
        for aic in aiColonies() where aic.colony.isConnectedPort { changeNeedWagon(aic.colony.tile, 0) }
        for aiu in aiUnits() {
            if let m = aiu.mission, !m.isValid { continue }
            let u = aiu.unit
            if u.isCarrier {
                if u.isNaval { nNavalCarrier -= 1 } else { changeNeedWagon(u.tile, -1) }
            } else {
                _ = checkTransport(aiu)
                if requestsTransport(aiu) {
                    transportSupply.append(aiu)
                    aiu.value += 1
                    nNavalCarrier += 1
                }
            }
        }
        for aic in aiColonies() {
            for aig in aic.currentExportGoods {
                _ = checkTransport(aig)
                if requestsTransport(aig) {
                    transportSupply.append(aig)
                    aig.value += 1
                    let src = aig.transportSource, dst = aig.transportDestination
                    let same = src != nil && dst != nil
                        && (src! === dst! || Map.isSameContiguity(src!.tile, dst!.tile))
                    if !same { nNavalCarrier += 1 }
                }
            }
            if !aic.colony.isConnectedPort { changeNeedWagon(aic.colony.tile, 1) }
        }
        for w in wishes() {
            guard let t = w.transportable, t.transport == nil, let d = t.transportDestination,
                  let loc = upLoc(d) else { continue }
            let key = LocationKey(location: loc)
            _ = transportDemand.put(key, (transportDemand[key] ?? []) + [w])
        }
    }

    /// Change a unit's transport after its target changed: drop a
    /// carrier not yet boarded, and dump or requeue on one boarded
    /// (updateTransport).
    func updateTransport(_ aiu: AIUnit, _ oldTarget: (any Location)?) {
        guard let aiCarrier = aiu.transport, let tm = aiCarrier.mission as? TransportMission else { return }
        let newTarget = aiu.mission?.target
        if Map.isSameLocation(oldTarget, newTarget) { return }
        if aiu.unit.location !== aiCarrier.unit {
            aiu.dropTransport()
        } else if newTarget == nil {
            tm.dumpTransportable(aiu)
        } else {
            tm.requeueTransportable(aiu)
        }
    }

    // MARK: Missions

    /// Work in a colony (getWorkInsideColonyMission).
    func workInsideColonyMission(_ aiUnit: AIUnit, _ aiColony: AIColony?) -> Mission? {
        let aic = aiColony ?? aiUnit.unit.colony.flatMap { aiMain.aiColony($0) }
        guard let aic, WorkInsideColonyMission.invalidMissionReason(aiUnit, aic.colony) == nil else { return nil }
        return WorkInsideColonyMission(aiMain, aiUnit, aic)
    }

    // With only the colonies working the getters below give no
    // missions, as in the oracle's patch.

    /// A pioneering mission, if there is work and the unit can be
    /// equipped (getPioneeringMission).
    func pioneeringMission(_ aiUnit: AIUnit, _ target: (any Location)?) -> Mission? {
        if coloniesOnly { return nil }
        if PioneeringMission.prepare(aiUnit) != nil { return nil }
        guard let target = target ?? PioneeringMission.findMissionTarget(aiUnit, EuropeanAIPlayer.pioneeringRange,
                                                                         true) else {
            if aiUnit.unit.isInEurope || aiUnit.unit.settlement != nil, let role = specification?.defaultRole {
                _ = aiUnit.equipForRole(role)
            }
            return nil
        }
        return PioneeringMission(aiMain, aiUnit, target)
    }

    /// A scouting mission, if there is somewhere to scout
    /// (getScoutingMission).
    func scoutingMission(_ aiUnit: AIUnit) -> Mission? {
        if coloniesOnly { return nil }
        if ScoutingMission.prepare(aiUnit) != nil { return nil }
        guard let loc = ScoutingMission.findMissionTarget(aiUnit, EuropeanAIPlayer.scoutingRange, true) else {
            if aiUnit.unit.isInEurope || aiUnit.unit.settlement != nil, let role = specification?.defaultRole {
                _ = aiUnit.equipForRole(role)
            }
            return nil
        }
        return ScoutingMission(aiMain, aiUnit, loc)
    }

    /// A missionary mission, if there is a settlement for it
    /// (getMissionaryMission).
    func missionaryMission(_ aiUnit: AIUnit) -> Mission? {
        if coloniesOnly { return nil }
        if MissionaryMission.prepare(aiUnit) != nil { return nil }
        guard let loc = MissionaryMission.findMissionTarget(aiUnit, EuropeanAIPlayer.missionaryRange, true) else {
            if let role = specification?.defaultRole { _ = aiUnit.equipForRole(role) }
            return nil
        }
        return MissionaryMission(aiMain, aiUnit, loc)
    }

    override func defendSettlementMission(_ aiUnit: AIUnit, _ target: Settlement) -> Mission? {
        coloniesOnly ? nil : super.defendSettlementMission(aiUnit, target)
    }

    // MARK: Stances

    /// The stance the tension calls for, and with the REFs: war with
    /// ours if rebels, and peace with others' while they have rebels
    /// (determineStance).
    override func determineStance(_ other: Player) -> Player.Stance {
        if other.isREF {
            if player.refPlayer === other { return player.isRebel ? .war : .peace }
            if !other.rebels.isEmpty { return .peace }
        }
        return super.determineStance(other)
    }

    /// Missions for the units without (giveNormalMissions), which the
    /// REF's AI does its own way first.
    func giveMissions(_ aiUnits: inout [AIUnit]) throws {
        giveNormalMissions(&aiUnits)
    }

    private func determineStances() {
        for p in game.livePlayers(excluding: player) {
            let newStance = determineStance(p)
            if newStance != player.stance(p) {
                if newStance == .war && peaceHolds(p) { continue } // The treaty holds for now.
                do {
                    try aiMain.controller.changeStance(player, newStance, p, true)
                } catch {
                    aiMain.record(error, "changing stance")
                }
            }
        }
    }

    /// Whether a recent peace treaty with a player still holds, by
    /// chance fading with the turns since (peaceHolds).
    private func peaceHolds(_ p: Player) -> Bool {
        let turn = game.turn
        let peaceProb = 0.01 * Double(specification?.getPercentage(GameOptions.peaceProbability) ?? 0)
        var peaceTurn = -1
        for h in player.history where h.playerId == p.id && (h.turn?.number ?? -1) > peaceTurn {
            switch h.eventType {
            case .makePeace, .formAlliance: peaceTurn = h.turn?.number ?? -1
            case .declareWar: peaceTurn = -1
            default: break
            }
        }
        if peaceTurn < 0 { return false }
        let n = turn.number - peaceTurn
        var prob = Float(pow(peaceProb, Double(n)))
        prob = p.apply(prob, turn: turn, Modifier.peaceTreaty)
        return prob > 0
            && Int(RandomUtils.randomInt("Peace holds?", aiRandom, 100)) < Int(JavaMath.toInt(100 * prob))
    }

    /// Accept a tax raise unless it costs too much (acceptTax).
    override func acceptTax(_ tax: Int) -> Bool {
        let toBeDestroyed = player.mostValuableGoods
        let goodsType = toBeDestroyed?.type
        let ret: Bool
        if tax <= 2 {
            ret = true
        } else if toBeDestroyed == nil {
            ret = false
        } else if goodsType!.isFoodType {
            ret = false
        } else if goodsType!.isBreedable {
            ret = player.settlements.filter { $0.goodsCount(goodsType!) > 0 }.count < 2
        } else if goodsType!.isMilitary || goodsType!.isTradeGoods || goodsType!.isBuildingMaterial {
            ret = game.turn.number < 300
        } else {
            let goodsTypes = specification?.storableGoodsTypeList ?? []
            let averageIncome = goodsTypes.reduce(0) { $0 + player.incomeAfterTaxes($1) } / goodsTypes.count
            let income = player.incomeAfterTaxes(goodsType!)
            ret = income <= 0 || income > averageIncome
        }
        if !ret, let goodsType { suppressEuropeanTrade(goodsType) }
        return ret
    }

    /// Stop trading goods that are to be boycotted: sell what is in
    /// Europe and on the way, drop it from the carriers' plans, and drop
    /// the wishes for it from Europe (suppressEuropeanTrade).
    private func suppressEuropeanTrade(_ type: GoodsType) {
        guard let europe = player.europe else { return }
        let units = europe.unitList + (player.highSeas?.unitList ?? [])
        for u in units {
            let amount = u.goodsCount(type)
            if u.isCarrier && amount > 0, aiUnit(u) != nil {
                ask(.unloadGoods(type: type.id, amount: String(amount), carrier: u.id))
            }
        }
        for aiu in aiUnits() {
            (aiu.mission as? TransportMission)?.suppressEuropeanTrade(type)
        }
        for gw in goodsWishes[type] ?? [] where gw.goodsType === type && gw.destination === europe {
            if let aig = gw.transportable as? AIGoods {
                consumeGoodsWish(aig, gw)
                aig.transportDestination = nil
            }
            gw.dispose()
        }
    }

    override func acceptMercenaries() -> Bool {
        player.isAtWar || aiAdvantage == "conquest"
    }

    /// The father with a custom house, or the heaviest for the age
    /// (selectFoundingFather).
    override func selectFoundingFather(_ ffs: [FoundingFather]) -> FoundingFather? {
        let age = game.age
        var bestFather: FoundingFather?
        var bestWeight = Int(Int32.min)
        for father in ffs {
            if father.hasAbility(Ability.buildCustomHouse) { return father }
            let weight = father.weight(age)
            if weight > bestWeight {
                bestWeight = weight
                bestFather = father
            }
        }
        return bestFather
    }

    override func indianDemand(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int,
                               _ accept: IndianDemandAction?) -> IndianDemandAction {
        aiAdvantage == "conquest" ? .accept : .reject
    }

    /// What a trade item is worth to the player (evaluateFor).  A stance
    /// is judged by strength, from the nation summary of the other side.
    private func evaluate(_ item: TradeItem) -> Int {
        if let stance = item.tradeStance {
            guard let other = item.other(player) else { return TradeItem.invalidTradeItem }
            let ratio: Double
            if let ns = nationSummaries[other.id ?? ""] {
                ratio = Player.strengthRatio(Double(player.calculateStrength(naval: false)),
                                             Double(ns.militaryStrength))
            } else {
                ratio = -1
            }
            var value = Int(JavaMath.round(100 * ratio))
            switch stance {
            case .war:
                if ratio < 0.33 { value = TradeItem.invalidTradeItem } else if ratio < 0.5 { value = -value }
            case .peace, .ceaseFire, .alliance:
                if ratio > 0.66 {
                    value = TradeItem.invalidTradeItem
                } else if ratio > 0.5 {
                    value = -value
                } else if ratio < 0.33 {
                    value = 1000
                }
            default:
                value = TradeItem.invalidTradeItem
            }
            return value
        }
        if item is GoldTradeItem { return item.evaluateFor(player) }
        aiMain.record(NotYetPorted("evaluating a \(type(of: item))"), player.nationId ?? "")
        return TradeItem.invalidTradeItem
    }

    /// Reject a trade, unless a Franklin or contact stance can be
    /// offered instead (rejectAgreement).
    private func rejectAgreement(_ stance: TradeItem?, _ agreement: DiplomaticTrade) -> DiplomaticTrade.TradeStatus {
        guard let stance else { return .rejectTrade }
        agreement.clear()
        agreement.add(stance)
        return .proposeTrade
    }

    /// Judge a trade: accept it if all is good, reject it if too much is
    /// bad or patience runs out, otherwise drop the worst items and
    /// propose the rest (acceptDiplomaticTrade).  Java keeps the scores
    /// in a HashMap, whose order for stances follows the enum's identity
    /// hash and so differs from run to run; the items' order is used here.
    override func acceptDiplomaticTrade(_ agreement: DiplomaticTrade) -> DiplomaticTrade.TradeStatus {
        guard let other = agreement.otherPlayer(player) else { return .rejectTrade }
        if agreement.version == 0 { return .proposeTrade } // A synthetic event.
        let franklin = other.hasAbility(Ability.alwaysOfferedPeace)
        var scores: [(item: TradeItem, score: Int)] = []
        var peace: TradeItem?
        var result: DiplomaticTrade.TradeStatus?
        var unacceptable = 0, value = 0, colonies = 0
        for item in agreement.items {
            if item is StanceTradeItem { _ = nationSummary(other) }
            var score = evaluate(item)
            if item is ColonyTradeItem {
                colonies += item.source === player ? 1 : -1
            } else if let stance = item.tradeStance {
                switch stance {
                case .alliance, .ceaseFire:
                    if franklin {
                        peace = item
                        score = 0
                    }
                case .uncontacted, .peace:
                    if agreement.context == .contact {
                        peace = item
                        score = 0
                    }
                default:
                    break
                }
            }
            if score == TradeItem.invalidTradeItem { unacceptable += 1 } else { value += score }
            scores.append((item, score))
        }

        if colonies > 0 && colonies > player.settlements.count - Colony.tradeMargin {
            result = rejectAgreement(peace, agreement)
        } else if unacceptable == 0 && value >= 0 {
            result = .acceptTrade
        } else {
            let ratio = Double(unacceptable) / Double(unacceptable + agreement.items.count)
            if ratio > 0.5 - 0.5 * Double(agreement.version) { result = rejectAgreement(peace, agreement) }
        }
        if result == nil {
            // Drop the unacceptable, sum the rest.
            value = 0
            for (item, score) in scores {
                if score == TradeItem.invalidTradeItem { agreement.remove(item) } else { value += score }
            }
            if agreement.isEmpty { result = rejectAgreement(peace, agreement) }
        }
        if RandomUtils.randomInt("Enough diplomacy?", aiRandom, Int32(1 + agreement.version)) > 5 {
            result = rejectAgreement(peace, agreement)
        }
        if result == nil {
            // Drop the worst until the sum is not negative, or offer
            // less gold.
            for (item, score) in scores.stableSorted(by: { $0.score < $1.score }) {
                if value >= 0 { break }
                value -= score
                if value >= 50, let gti = item as? GoldTradeItem {
                    gti.gold -= value / 2
                    value /= 2
                } else {
                    agreement.remove(item)
                }
            }
            result = value >= 0 && !agreement.isEmpty ? .proposeTrade : rejectAgreement(peace, agreement)
        }
        return result!
    }
}



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
    private var tipMap = JavaHashMap<Tile, TileImprovementPlan>(javaHash: { $0.javaGameObjectHash })
    /// The wishes waiting for transport, by destination.
    private var transportDemand = JavaHashMap<LocationKey, [Wish]>(javaHash: { $0.javaHash })
    /// What needs transport.
    private var transportSupply: [TransportableAIObject] = []
    /// The goods wishes by goods type, and worker wishes by unit type.
    private var goodsWishes = JavaHashMap<GoodsType, [GoodsWish]>(javaHash: { $0.javaHashCode })
    private var workerWishes = JavaHashMap<UnitType, [WorkerWish]>(javaHash: { $0.javaHashCode })
    /// The wagons needed, by contiguity.
    private var wagonsNeeded = JavaHashMap<Int, Int>(javaHash: { Int32(truncatingIfNeeded: $0) })
    /// The colonies badly defended at the start of the turn.
    private(set) var badlyDefended: [AIColony] = []
    private var nNavalCarrier = 0

    /// Whether this nation likes attacking natives (the conquest
    /// nations).
    var likesAttackingNatives: Bool {
        player.nation?.type?.id == "model.nationType.conquest"
    }

    private var coloniesOnly: Bool { aiMain.works == .colonies }

    /// The player's turn (startWorking), so far only with its colonies.
    override func startWorking() {
        guard coloniesOnly else {
            aiMain.record(NotYetPorted("the European AI's missions"), "\(player.nationId ?? "")")
            return
        }
        let turn = game.turn
        clearAIUnits()
        nationSummaries.removeAll()
        badlyDefended.removeAll()
        // Java gathers the units now, before anything can make more.
        let colonyCount = aiColonies().count
        _ = aiUnits()
        // Missions for the first turn come with the European missions.

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

        // The colonies only, as the oracle's patch does.
        buildTransportMaps()
        do {
            for _ in 0..<3 { try rearrangeColonies() }
        } catch {
            aiMain.record(error, "\(player.nationId ?? "") rearranging colonies")
            return
        }
        clearAIUnits()
        tipMap.removeAll()
        transportDemand.removeAll()
        transportSupply.removeAll()
        wagonsNeeded.removeAll()
        goodsWishes.removeAll()
        workerWishes.removeAll()
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

    /// Whether something has its carrier's transport mission
    /// (checkTransport).  Transport missions come with the European
    /// missions.
    private func checkTransport(_ t: TransportableAIObject) -> Bool {
        guard t.transport != nil else { return false }
        aiMain.record(NotYetPorted("transport missions"), "\(player.nationId ?? "")")
        return false
    }

    private func requestsTransport(_ t: TransportableAIObject) -> Bool {
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

    /// Change a unit's transport after its target changed
    /// (updateTransport).  Transport missions come with the European
    /// missions.
    func updateTransport(_ aiu: AIUnit, _ oldTarget: (any Location)?) {
        if aiu.transport != nil {
            aiMain.record(NotYetPorted("transport missions"), "\(player.nationId ?? "")")
        }
    }

    // MARK: Missions

    /// Work in a colony (getWorkInsideColonyMission).
    func workInsideColonyMission(_ aiUnit: AIUnit, _ aiColony: AIColony?) -> Mission? {
        let aic = aiColony ?? aiUnit.unit.colony.flatMap { aiMain.aiColony($0) }
        guard let aic, WorkInsideColonyMission.invalidMissionReason(aiUnit, aic.colony) == nil else { return nil }
        return WorkInsideColonyMission(aiMain, aiUnit, aic)
    }

    /// The missions below come with the European missions.  With only
    /// the colonies working there are none, as in the oracle's patch.
    func pioneeringMission(_ aiUnit: AIUnit, _ target: (any Location)?) -> Mission? {
        if !coloniesOnly { aiMain.record(NotYetPorted("PioneeringMission"), "\(player.nationId ?? "")") }
        return nil
    }

    func scoutingMission(_ aiUnit: AIUnit) -> Mission? {
        if !coloniesOnly { aiMain.record(NotYetPorted("ScoutingMission"), "\(player.nationId ?? "")") }
        return nil
    }

    func missionaryMission(_ aiUnit: AIUnit) -> Mission? {
        if !coloniesOnly { aiMain.record(NotYetPorted("MissionaryMission"), "\(player.nationId ?? "")") }
        return nil
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
    /// Europe and on the way (suppressEuropeanTrade).  Transport missions
    /// and goods wishes come with the European AI.
    private func suppressEuropeanTrade(_ type: GoodsType) {
        guard let europe = player.europe else { return }
        let units = europe.unitList + (player.highSeas?.unitList ?? [])
        for u in units {
            let amount = u.goodsCount(type)
            if u.isCarrier && amount > 0, aiUnit(u) != nil {
                ask(.unloadGoods(type: type.id, amount: String(amount), carrier: u.id))
            }
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

    override func acceptDiplomaticTrade(_ agreement: DiplomaticTrade) -> DiplomaticTrade.TradeStatus {
        aiMain.record(NotYetPorted("the European AI's diplomacy"), "\(player.nationId ?? "")")
        return .rejectTrade
    }
}

/// The REF's computer player (server/ai/REFAIPlayer), which comes with
/// Phase 4's last step.
final class REFAIPlayer: EuropeanAIPlayer {
    override func startWorking() {
        aiMain.record(NotYetPorted("the REF's AI"), "\(player.nationId ?? "")")
    }
}

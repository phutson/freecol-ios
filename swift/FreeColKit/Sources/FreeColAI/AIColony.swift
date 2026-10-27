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

/// The AI of a colony (server/ai/AIColony): what to export, the tiles
/// to improve, what the colony wishes for, and arranging its workers
/// by its ColonyPlan.
public final class AIColony: AIObject {

    /// Keep at least this many forested tiles.
    private static let forestMinimum = 1

    /// Do not ship out less than this.
    private static let exportMinimum = 10

    public unowned let colony: Colony
    private var colonyPlan: ColonyPlan?
    private var exportGoods: [AIGoods] = []
    private var wishes: [Wish] = []
    private var tileImprovementPlans: [TileImprovementPlan] = []
    /// When the workers are next rearranged.
    public private(set) var rearrangeTurn = 0

    /// The goods to export entirely, and to export only to keep the
    /// warehouse from filling.  Java's are shared by every AI colony,
    /// but each colony sets them afresh before using them.
    private var fullExport = Set<ObjectIdentifier>()
    private var partExport = Set<ObjectIdentifier>()

    init(_ aiMain: AIMain, _ colony: Colony) {
        self.colony = colony
        super.init(aiMain, colony.id)
        colony.rearrangeListener = { [weak self] goodsType in self?.propertyChange(goodsType) }
        initialized = true
    }

    private func aiUnit(_ unit: Unit) -> AIUnit? {
        aiMain.aiUnit(unit)
    }

    private var aiOwner: AIPlayer? {
        aiMain.aiPlayer(colony.owner)
    }

    var isBadlyDefended: Bool { colony.isBadlyDefended }

    /// Update what changes slowly: exports, tile improvements and
    /// wishes.
    func update() {
        resetExports()
        updateExportGoods()
        updateTileImprovementPlans()
        updateWishes()
    }

    /// Rearrange the workers by the colony plan, when due
    /// (rearrangeColony): claim free tiles, choose what to build, try
    /// the workers on a copy of the colony and apply the arrangement,
    /// then give the units missions.
    ///
    /// - Throws: JavaException where Java's would throw.
    func rearrangeColony() throws {
        // Is it collapsing?
        if colony.unitCount <= 0 && !avertAutoDestruction() { return }

        let turn = game.turn.number
        if rearrangeTurn > turn {
            // Java warns if it could be building, and goes on.
            guard colony.currentlyBuilding == nil, colonyPlan?.bestBuildableType != nil else { return }
        }

        guard let tile = colony.tile, let player = colony.owner, let spec = specification else { return }

        // Rearrange in 15 turns at most.
        var nextRearrange = 15

        // Explore rumours, take tiles, and claim free ones, before the
        // plan is made so that it can use them.
        exploreLCRs()
        stealTiles()
        for t in tile.surroundingTiles(1, 1) where !player.owns(t) && player.canClaimForSettlement(t) {
            aiOwner?.ask(.claimLand(tile: t.id, claimant: colony.id, price: "0"))
        }

        // Update the plan, choose what to build, and refine the plan.
        let plan = colonyPlan ?? ColonyPlan(aiMain, colony)
        colonyPlan = plan
        plan.update()
        let oldBuild = colony.currentlyBuilding
        var build = plan.bestBuildableType
        if build !== oldBuild {
            aiOwner?.ask(.setBuildQueue(colony: colony.id, queue: build.map { [$0.id ?? ""] } ?? []))
            build = colony.currentlyBuilding
        }
        try plan.refine(build)

        // The workers: the colony's, and those on its tile that are not
        // busy elsewhere.
        var workers = colony.unitList
        for u in tile.unitList
        where u.isPerson && !u.hasAbility(Ability.refUnit) && (aiUnit(u)?.isAvailableForWork(colony) ?? false) {
            workers.append(u)
        }

        // Try the plan's arrangement, and apply it.
        let preferScouts = (aiOwner as? EuropeanAIPlayer)?.scoutsNeeded ?? 0 > 0
        var trial = workers
        guard let scratch = try plan.assignWorkers(&trial, preferScouts) else {
            rearrangeTurn = turn + 1
            return
        }
        askRearrangeColony(workers, scratch)
        scratch.releaseCopy()

        // If the colony is empty after all, recover.
        if colony.unitCount <= 0 && !avertAutoDestruction() { return }

        // If the arrangement made the build impossible, choose again,
        // and rearrange again next turn.
        if let b = build, !colony.canBuild(b) {
            let newBuild = plan.bestBuildableType
            aiOwner?.ask(.setBuildQueue(colony: colony.id, queue: newBuild.map { [$0.id ?? ""] } ?? []))
            nextRearrange = 1
        }

        // Rearrange before the food or a warehouse runs out or fills.
        if let food = spec.primaryFoodType, colony.netProduction(of: food) < 0 {
            let net = colony.netProduction(of: food)
            let when = colony.goodsCount(food) / -net
            nextRearrange = max(0, min(nextRearrange, when - 1))
        }
        let warehouse = colony.warehouseCapacity
        for g in spec.storableGoodsTypeList where !g.isFoodType {
            let have = colony.goodsCount(g)
            let net = colony.adjustedNetProduction(of: g)
            if net >= 0 && (have >= warehouse || g.limitIgnored) { continue }
            let when = net < 0 ? have / -net - 1 : net > 0 ? (warehouse - have) / net - 1 : Int(Int32.max)
            nextRearrange = max(1, min(nextRearrange, when))
        }

        // The workers work in the colony.
        for u in colony.unitList {
            _ = aiUnit(u)?.tryWorkInsideColonyMission(self)
        }

        // Pioneers, if there is work for them.
        var tipSize = tileImprovementPlans.count
        if tipSize > 0 {
            let pioneers = tile.unitList.filter { $0.pioneerScore >= 0 }
                .stableSorted { $0.pioneerScore > $1.pioneerScore }
            for u in pioneers where aiUnit(u)?.tryPioneeringMission() ?? false {
                tipSize -= 1
                if tipSize <= 0 { break }
            }
        }

        for u in tile.unitList {
            _ = aiUnit(u)?.trySomeUsefulMission(colony)
        }

        rearrangeTurn = turn + nextRearrange
    }

    /// Ask the server to move the units that the trial moved
    /// (askRearrangeColony, RearrangeColonyMessage.getArrangements).
    private func askRearrangeColony(_ workers: [Unit], _ scratch: Colony) {
        var arrangements: [ColonyArrangement] = []
        for u in workers {
            guard let su = scratch.corresponding(u), let suLoc = su.location else { continue }
            if (u.location as? FreeColGameObject)?.id == (suLoc as? FreeColGameObject)?.id
                && u.workType === su.workType && u.role === su.role && u.roleCount == su.roleCount { continue }
            let loc = colony.corresponding(suLoc) as? FreeColGameObject
            arrangements.append(ColonyArrangement(unit: u.id, location: loc?.id, work: su.workType?.id,
                                                  role: su.role?.id, roleCount: String(su.roleCount)))
        }
        if !arrangements.isEmpty {
            aiOwner?.ask(.rearrangeColony(colony: colony.id, arrangements: arrangements))
        }
    }

    /// Set what to export (resetExports): luxuries, manufactured goods
    /// and raw materials not made here entirely, other raw materials and
    /// the goods needed to equip for roles only to keep the warehouse
    /// from filling.
    private func resetExports() {
        guard let spec = specification, let player = colony.owner else { return }
        fullExport.removeAll()
        partExport.removeAll()
        for g in spec.storableGoodsTypeList
        where !g.isFoodType && !g.isRawMaterialForUnstorableBuildingMaterial && !g.isBuildingMaterial
            && !g.isMilitary && !g.isTradeGoods {
            if g.isRawMaterial {
                partExport.insert(ObjectIdentifier(g))
            } else {
                fullExport.insert(ObjectIdentifier(g))
            }
        }
        let dUT = spec.defaultUnitType(player.nationType)
        for r in spec.rolesList where r.isAvailableTo([player, dUT]) {
            for ag in r.requiredGoods {
                guard let t = ag.type, fullExport.contains(ObjectIdentifier(t)) else { continue }
                fullExport.remove(ObjectIdentifier(t))
                partExport.insert(ObjectIdentifier(t))
            }
        }
        if player.market == nil {
            for g in spec.goodsTypeList { colony.exportData(g).exported = false }
        } else {
            let exportLevel = 4 * colony.warehouseCapacity / 5
            for g in spec.goodsTypeList {
                let data = colony.exportData(g)
                if fullExport.contains(ObjectIdentifier(g)) {
                    data.exportLevel = 0
                    data.exported = true
                } else if partExport.contains(ObjectIdentifier(g)) {
                    data.exportLevel = exportLevel
                    data.exported = true
                } else {
                    data.exported = false
                }
            }
        }
    }

    /// Explore neighbouring rumours with non-experts and scouts, the
    /// best scouts first.
    private func exploreLCRs() {
        guard let tile = colony.tile else { return }
        var scouts = tile.unitList.filter { u in
            u.isPerson && ((u.type?.skill ?? 0) <= 0 || u.hasAbility(Ability.expertScout))
        }.stableSorted { $0.scoutScore > $1.scoutScore }
        for t in tile.surroundingTiles(1, 1) where t.hasLostCityRumour {
            guard let direction = tile.direction(to: t) else { continue }
            while true {
                if scouts.isEmpty { return }
                let u = scouts.removeFirst()
                if !u.moveType(t).isProgress { continue }
                if aiUnit(u)?.move(direction) ?? false, !t.hasLostCityRumour {
                    u.destination = tile
                    break
                }
            }
        }
    }

    /// Take neighbouring native land, if the colony is defended: all of
    /// it from natives at war, otherwise the tile best for the building
    /// materials needed, and a little for food.
    private func stealTiles() {
        guard let spec = specification, let tile = colony.tile, let player = colony.owner else { return }
        let hasDefender = tile.unitList.contains { u in
            u.isDefensiveUnit && (aiUnit(u)?.hasDefendSettlementMission ?? false)
        }
        if !hasDefender { return }
        let needed = spec.rawBuildingGoodsTypeList.filter { colony.totalProduction(of: $0) <= 0 }
        let unitType = spec.defaultUnitType(player.nationType)
        var steal: Tile?
        var score = 1.0
        for t in tile.surroundingTiles(1) {
            guard let owner = t.owner, owner !== player, !owner.isEuropean,
                  player.canClaimForSettlement(t) else { continue }
            if owner.atWar(with: player) {
                aiOwner?.ask(.claimLand(tile: t.id, claimant: colony.id, price: String(Constants.stealLand)))
            } else {
                let s = needed.reduce(0.0) { $0 + Double(t.potentialProduction($1, unitType)) }
                    + spec.foodGoodsTypeList.reduce(0.0) { $0 + 0.1 * Double(t.potentialProduction($1, unitType)) }
                if s > score {
                    score = s
                    steal = t
                }
            }
        }
        if let steal {
            aiOwner?.ask(.claimLand(tile: steal.id, claimant: colony.id, price: String(Constants.stealLand)))
        }
    }

    /// No one is working in the colony: put someone from outside in
    /// the town hall, or similar.
    ///
    /// - Returns: Whether the colony has workers now.
    private func avertAutoDestruction() -> Bool {
        guard let spec = specification, let tile = colony.tile else { return colony.unitCount > 0 }
        out: for u in tile.unitList where u.isPerson {
            for wl in colony.availableWorkLocations where wl.canAdd(u) {
                for type in spec.libertyGoodsTypeList where wl.potentialProduction(type, u.type) > 0 {
                    guard let aiu = aiUnit(u), let ai = aiOwner else { continue }
                    if ai.ask(.work(unit: u.id, workLocation: wl.id)) && u.location === wl {
                        aiu.aiOwner?.ask(.changeWorkType(unit: u.id, workType: type.id))
                        break out
                    }
                }
            }
        }
        return colony.unitCount > 0
    }

    /// Stop using a work location that a colony is to be built on
    /// (stopUsing).
    func stopUsing(_ wl: WorkLocation) {
        for u in wl.unitList {
            aiOwner?.ask(.putOutsideColony(unit: u.id))
        }
        if colony.unitCount <= 0 { _ = avertAutoDestruction() }
        rearrangeTurn = game.turn.number
    }

    // MARK: Exports

    /// The goods to export, the most valuable first.
    var currentExportGoods: [AIGoods] { exportGoods }

    /// Forget export goods, without disposing of them.
    func removeExportGoods(_ ag: AIGoods) {
        exportGoods.removeAll { $0 === ag }
    }

    private func dropExportGoods(_ ag: AIGoods) {
        if let transport = ag.transport { transport.removeTransportable(ag) }
        removeExportGoods(ag)
        ag.dispose()
    }

    /// Choose the goods to ship out (updateExportGoods).
    private func updateExportGoods() {
        guard let spec = specification, let owner = colony.owner else { return }
        if colony.hasAbility(Ability.export) {
            for aig in exportGoods { dropExportGoods(aig) } // The custom house handles them.
            return
        }
        for aig in exportGoods {
            if !aig.isSafe {
                dropExportGoods(aig)
            } else if aig.goods?.location !== colony {
                // On its way: delivery will dispose of it.
                removeExportGoods(aig)
            } else if let t = aig.goodsType, colony.adjustedNetProduction(of: t) < 0 {
                dropExportGoods(aig)
            }
        }

        let europe = owner.europe
        let capacity = colony.warehouseCapacity
        var newAIGoods: [AIGoods] = []
        outer: for gt in spec.goodsTypeList {
            if colony.adjustedNetProduction(of: gt) < 0 { continue }
            let count = colony.goodsCount(gt)
            let exportAmount = fullExport.contains(ObjectIdentifier(gt)) || partExport.contains(ObjectIdentifier(gt))
                ? count : -1
            if exportAmount <= 0 { continue }
            let priority = exportAmount >= capacity ? TransportableAIObject.importantDelivery
                : exportAmount >= GoodsContainer.cargoSize ? TransportableAIObject.fullDelivery : 0

            // Update existing goods of the type, dropping trivial ones.
            for aig in exportGoods {
                guard let goods = aig.goods, goods.type === gt else { continue }
                if goods.amount <= exportAmount || exportAmount >= AIColony.exportMinimum {
                    goods.amount = exportAmount
                    newAIGoods.append(aig)
                } else {
                    dropExportGoods(aig)
                }
                continue outer
            }
            // Export new goods, to Europe if possible.
            let destination: (any Location)? = owner.canTrade(gt) ? europe : nil
            if exportAmount >= AIColony.exportMinimum {
                let newGoods = AIGoods(aiMain, colony, gt, exportAmount, destination)
                newGoods.transportPriority = priority
                newAIGoods.append(newGoods)
            }
        }
        exportGoods = newAIGoods.sortedByDescendingValue()
    }

    // MARK: Wishes

    var currentWishes: [Wish] { wishes }

    var goodsWishes: [GoodsWish] { wishes.compactMap { $0 as? GoodsWish } }

    var workerWishes: [WorkerWish] { wishes.compactMap { $0 as? WorkerWish } }

    func addWish(_ wish: Wish) {
        wishes.append(wish)
    }

    /// Complete a wish (completeWish).
    ///
    /// - Returns: False if the colony did not wish for it.
    @discardableResult
    func completeWish(_ wish: Wish) -> Bool {
        guard let i = wishes.firstIndex(where: { $0 === wish }) else { return false }
        wishes.remove(at: i)
        (aiOwner as? EuropeanAIPlayer)?.completeWish(wish)
        wish.dispose()
        requestRearrange()
        return true
    }

    /// Complete the wishes something delivered satisfies: goods, or a
    /// unit at the end of its wish realization mission.
    func completeWish(transportable t: TransportableAIObject) -> Bool {
        if let aig = t as? AIGoods, let goods = aig.goods { return completeWish(goods as AbstractGoods) }
        if let aiu = t as? AIUnit, aiu.isCompleteWishRealizationMission(colony) {
            completeWish(aiu.unit)
            aiu.removeMission()
            return true
        }
        return false
    }

    /// Complete the wishes some goods arriving satisfy.
    @discardableResult
    func completeWish(_ goods: AbstractGoods) -> Bool {
        var ret = false
        for wish in wishes where wish.satisfiedBy(goods) { ret = completeWish(wish) || ret }
        return ret
    }

    /// Complete the wishes a unit arriving satisfies.
    @discardableResult
    func completeWish(_ unit: Unit) -> Bool {
        var ret = false
        for wish in wishes where wish.satisfiedBy(unit) { ret = completeWish(wish) || ret }
        return ret
    }

    /// Wish for goods, or update the wish, keeping the larger value
    /// (requireGoodsWish).
    private func requireGoodsWish(_ type: GoodsType, _ amount: Int, _ value: Int) {
        if let gw = goodsWishes.first(where: { $0.goodsType === type }) {
            gw.update(type, amount, gw.value + 1)
        } else {
            wishes.append(GoodsWish(aiMain, colony, value, amount, type))
        }
    }

    /// Wish for a worker, or update the wish (requireWorkerWish).
    private func requireWorkerWish(_ type: UnitType, _ expertNeeded: Bool, _ value: Int) {
        if let ww = workerWishes.first(where: { $0.unitType === type }) {
            ww.update(type, expertNeeded, ww.value + 1)
        } else {
            wishes.append(WorkerWish(aiMain, colony, value, type, expertNeeded))
        }
    }

    private func updateWishes() {
        updateWorkerWishes()
        updateGoodsWishes()
        wishes = wishes.sortedByDescendingValue()
    }

    /// Wish for experts to replace non-experts, the scarcest production
    /// first, or for more people (updateWorkerWishes).
    private func updateWorkerWishes() {
        guard let spec = specification, let owner = colony.owner else { return }
        let baseValue = 25, priorityMax = 50, priorityDecay = 5, multipleBonus = 5, multipleMax = 5

        // The goods being made, the least first.
        var made = JavaHashSet<GoodsType>(javaHash: { $0.javaHashCode })
        for wl in colony.availableWorkLocations {
            for u in wl.unitList { if let wt = u.workType { made.insert(wt.storedAs) } }
        }
        let producing = made.elements.stableSorted {
            colony.adjustedNetProduction(of: $0) < colony.adjustedNetProduction(of: $1)
        }

        var experts = TypeCountMap<UnitType>()
        for unit in colony.unitList {
            guard let goods = unit.workType, goods !== unit.type?.expertProduction,
                  let expert = spec.expert(producing: goods) else { continue }
            experts.increment(expert, by: 1)
        }
        for expert in experts.types {
            let index = expert.expertProduction.flatMap { g in producing.firstIndex { $0 === g } } ?? -1
            let value = baseValue + max(0, priorityMax - priorityDecay * index)
                + min(multipleMax, experts.count(expert) - 1) * multipleBonus
            requireWorkerWish(expert, true, value)
        }

        // More people, if there is room.
        if let plan = colonyPlan, experts.isEmpty, colony.governmentChange(colony.unitCount + 1) >= 0 {
            let needFood = colony.foodProduction <= colony.foodConsumption + owner.maximumFoodConsumption
            var expert = spec.defaultUnitType(owner.nationType)
            for p in needFood ? plan.foodPlans : plan.otherWorkPlans where p.workLocation.canBeWorked {
                expert = spec.expert(producing: p.goodsType)
                break
            }
            if let expert {
                requireWorkerWish(expert, false, 50)
            } else {
                aiMain.record(NotYetPorted("a worker wish for no unit type"), colony.name ?? "")
            }
        }
    }

    /// Wish for the goods to build, to improve tiles, to work the
    /// buildings, and to breed; drop wishes no longer needed
    /// (updateGoodsWishes).
    private func updateGoodsWishes() {
        guard let spec = specification else { return }
        let goodsWishValue = 50
        var required = TypeCountMap<GoodsType>()

        if let build = colony.currentlyBuilding {
            for ag in build.requiredGoods {
                if let t = ag.type, colony.adjustedNetProduction(of: t) <= 0 { required.increment(t, by: ag.amount) }
            }
        }
        for plan in tileImprovementPlans {
            guard let role = plan.type?.requiredRole else { continue }
            for ag in role.requiredGoods { if let t = ag.type { required.increment(t, by: ag.amount) } }
        }
        for wl in colony.currentWorkLocations where !(wl.productionInfo?.atMaximumProduction ?? false) {
            for ag in wl.inputs { if let t = ag.type { required.increment(t, by: 100) } }
        }
        for gt in spec.goodsTypeList where gt.isBreedable && colony.goodsCount(gt) < gt.breedingNumber {
            required.increment(gt, by: gt.breedingNumber)
        }

        // Drop wishes no longer needed.
        for wish in wishes {
            guard let gw = wish as? GoodsWish, required.count(gw.goodsType) < colony.goodsCount(gw.goodsType) else {
                continue
            }
            completeWish(wish)
        }

        // Wish for what is missing.
        for type in required.types {
            var requiredType: GoodsType? = type
            while let t = requiredType, !t.isStorable { requiredType = t.inputType }
            guard let requiredType else { continue }
            let amount = min(colony.warehouseCapacity, required.count(type) - colony.goodsCount(requiredType))
            if amount > 0 {
                var value = goodsWishValue
                if colony.canProduce(requiredType) { value /= 10 }
                requireGoodsWish(requiredType, amount, value)
            }
        }
    }

    // MARK: Tile improvements

    var currentTileImprovementPlans: [TileImprovementPlan] { tileImprovementPlans }

    @discardableResult
    func removeTileImprovementPlan(_ plan: TileImprovementPlan) -> Bool {
        guard let i = tileImprovementPlans.firstIndex(where: { $0 === plan }) else { return false }
        tileImprovementPlans.remove(at: i)
        return true
    }

    /// Plan improvements for the tiles being worked, for what they
    /// make, keeping a forested tile (updateTileImprovementPlans).
    private func updateTileImprovementPlans() {
        let wls = colony.availableWorkLocations.compactMap { $0 as? ColonyTile }
        var newPlans: [TileImprovementPlan] = []
        for colonyTile in wls {
            guard let workTile = colonyTile.workTile, workTile.owningSettlement === colony,
                  !newPlans.contains(where: { $0.target === workTile }) else { continue }

            // Food from the centre tile; otherwise what the worker makes.
            let goodsType: GoodsType?
            if colonyTile.isColonyCenterTile {
                goodsType = colonyTile.production.first { $0.isFoodType }?.type
            } else {
                goodsType = colonyTile.isEmpty ? nil : colonyTile.currentWorkType
            }
            guard let goodsType else { continue }

            var plan = tileImprovementPlans.first { $0.target === workTile }
            if let p = plan {
                if !p.update(goodsType) { plan = nil }
            } else if let type = TileImprovementPlan.bestTileImprovementType(workTile, goodsType) {
                plan = TileImprovementPlan(aiMain, workTile, type, type.improvementValue(workTile, goodsType))
            }
            guard let plan else { continue }

            // Do not clear the last forest.
            if let change = plan.type?.change(workTile.type), !change.isForested, !colonyTile.isColonyCenterTile {
                let forests = colony.availableWorkLocations.filter { wl in
                    guard let ct = wl as? ColonyTile, !ct.isColonyCenterTile else { return false }
                    return ct.workTile?.isForested ?? false
                }.count
                if forests <= AIColony.forestMinimum { continue }
            }
            newPlans.append(plan)
        }
        tileImprovementPlans = newPlans.sortedByDescendingValue()
    }

    /// The buildables planned (getPlannedBuildableTypes).
    var plannedBuildableTypes: [BuildableType] { colonyPlan?.buildableTypes ?? [] }

    // MARK: Changes to the colony

    /// The colony should be rearranged, and after a goods party its
    /// export goods of that type change (propertyChange).
    private func propertyChange(_ goodsParty: GoodsType?) {
        requestRearrange()
        guard let goodsType = goodsParty else { return }
        let left = colony.goodsCount(goodsType)
        for aig in exportGoods {
            var remove = false
            if aig.isDisposed {
                remove = true
            } else if aig.goods == nil {
                _ = aig.changeTransport(nil)
                remove = true
            } else if aig.goodsType === goodsType {
                if left > 0 {
                    aig.goods?.amount = left
                } else {
                    _ = aig.changeTransport(nil)
                    remove = true
                }
            }
            if remove {
                removeExportGoods(aig)
                break
            }
        }
    }

    /// Rearrange fully next time.
    func requestRearrange() {
        rearrangeTurn = 0
    }

    public override func dispose() {
        let ours = exportGoods.filter { !$0.isDisposed && $0.goods?.location === colony }
        let objects: [AIObject] = ours + wishes + tileImprovementPlans
        wishes = []
        tileImprovementPlans = []
        for o in objects { o.dispose() }
        colonyPlan = nil
        super.dispose()
    }
}

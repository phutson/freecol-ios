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

/// What Java would have thrown: the AI's turn stops, as Java's does
/// when its turn throws.
struct JavaException: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The AI's plan for a colony (server/ai/ColonyPlan): what to build,
/// in order, and plans for producing goods at each work location, made
/// from the production possible with free colonists, and a trial
/// assignment of workers on a copy of the colony.  AIColony makes the
/// decisions.
///
/// Java keeps its goods type sets and production maps in HashSets and
/// HashMaps, whose order decides ties, so they are kept in Java's order
/// here.
final class ColonyPlan {

    /// Something to build, and its priority.
    private final class BuildPlan {
        let type: BuildableType
        var weight: Double
        var support: Double
        var difficulty = 1.0

        init(_ type: BuildableType, _ weight: Double, _ support: Double) {
            self.type = type
            self.weight = weight
            self.support = support
        }

        var value: Double { weight * support / difficulty }
    }

    /// Production plans must make more than this.
    private static let lowProductionThreshold = 1

    /// Turns of production to keep the input goods for.
    private static let productionTurnoverTurns = 5

    /// The general flavour of a colony, by size.
    private enum ProfileType {
        case outpost, small, medium, large, capital

        init(size: Int) {
            self = size <= 1 ? .outpost : size <= 2 ? .small : size <= 4 ? .medium
                : size <= 8 ? .large : .capital
        }
    }

    private unowned let aiMain: AIMain
    private unowned let colony: Colony
    private var profileType: ProfileType

    private var buildPlans: [BuildPlan] = []
    private var workPlans: [WorkLocationPlan] = []
    /// The goods types to produce, in order.
    private var produce: [GoodsType] = []

    private var libertyGoodsTypes = JavaHashSet<GoodsType>(javaHash: { $0.javaHashCode })
    private var immigrationGoodsTypes = JavaHashSet<GoodsType>(javaHash: { $0.javaHashCode })
    private var militaryGoodsTypes = JavaHashSet<GoodsType>(javaHash: { $0.javaHashCode })
    private var rawBuildingGoodsTypes: [GoodsType] = []
    private var buildingGoodsTypes = JavaHashSet<GoodsType>(javaHash: { $0.javaHashCode })
    private var rawLuxuryGoodsTypes = JavaHashSet<GoodsType>(javaHash: { $0.javaHashCode })
    private var otherRawGoodsTypes = JavaHashSet<GoodsType>(javaHash: { $0.javaHashCode })

    /// Production by goods type and work location, in Java's HashMap
    /// order.
    private typealias Production = JavaHashMap<GoodsType, JavaHashMap<WorkLocation, Int>>

    init(_ aiMain: AIMain, _ colony: Colony) {
        self.aiMain = aiMain
        self.colony = colony
        profileType = ProfileType(size: colony.unitCount)
    }

    private var spec: Specification { colony.specification! }

    // MARK: Public

    var preferredProduction: [GoodsType] { produce }

    var buildableTypes: [BuildableType] { buildPlans.map(\.type) }

    /// The first planned buildable the colony can build now.
    var bestBuildableType: BuildableType? {
        buildPlans.first { colony.canBuild($0.type) }?.type
    }

    /// The food plans for locations that need a worker.
    var foodPlans: [WorkLocationPlan] {
        workPlans.filter { $0.isFoodPlan && !$0.workLocation.canAutoProduce }
    }

    /// The other plans for locations that need a worker.
    var otherWorkPlans: [WorkLocationPlan] {
        workPlans.filter { !$0.isFoodPlan && !$0.workLocation.canAutoProduce }
    }

    /// Suppress plans to make building materials the buildable does not
    /// need, putting them back before a plan that makes something from
    /// them while their stock is low (refine).
    func refine(_ build: BuildableType?) throws {
        let required = colony.fullRequiredGoods(build).compactMap(\.type)
        var suppressed: [ObjectIdentifier: [WorkLocationPlan]] = [:]
        let plans = workPlans
        var offset = 0
        for i in plans.indices {
            let wlp = plans[i]
            let g = wlp.goodsType
            if (rawBuildingGoodsTypes.contains { $0 === g } && !required.contains { $0 === g.outputType })
                || (buildingGoodsTypes.contains(g) && !required.contains { $0 === g }) {
                workPlans.remove(at: i - offset)
                offset += 1
                suppressed[ObjectIdentifier(g), default: []].insert(wlp, at: 0)
                removeFirst(&produce, g)
            } else if g.isRefined, let input = g.inputType,
                      rawBuildingGoodsTypes.contains(where: { $0 === input }) || buildingGoodsTypes.contains(input) {
                var n = 0
                let idx = produce.firstIndex { $0 === g } ?? -1
                var type: GoodsType? = input
                while let t = type {
                    guard var wls = suppressed[ObjectIdentifier(t)] else { break }
                    if colony.goodsCount(t) >= GoodsContainer.cargoSize / 2 { break }
                    n += wls.count
                    while !wls.isEmpty { workPlans.insert(wls.removeFirst(), at: i - offset) }
                    suppressed[ObjectIdentifier(t)] = wls
                    guard idx >= 0 else { throw JavaException("IndexOutOfBoundsException in ColonyPlan.refine") }
                    produce.insert(t, at: idx)
                    type = t.inputType
                }
                offset -= n
            }
        }
    }

    /// Make the build and work plans afresh (update).
    func update() {
        profileType = ProfileType(size: colony.unitCount)
        var production = createProductionMap()
        updateGoodsTypeLists(&production)
        updateRawMaterials(&production)
        updateBuildableTypes()
        updatePlans(production)
    }

    // MARK: Internals

    /// The production of every goods type at every available work
    /// location with a free colonist, unworkable ones included.
    private func createProductionMap() -> Production {
        var production = Production(javaHash: { $0.javaHashCode })
        for wl in colony.availableWorkLocations {
            for g in spec.goodsTypeList {
                let p = wl.genericPotential(g)
                if p > 0 {
                    var m = production[g] ?? JavaHashMap(javaHash: { $0.javaGameObjectHash })
                    _ = m.put(wl, p)
                    _ = production.put(g, m)
                }
            }
        }
        return production
    }

    /// Sort the goods types made into categories, dropping those of no
    /// interest.
    private func updateGoodsTypeLists(_ production: inout Production) {
        libertyGoodsTypes.removeAll()
        immigrationGoodsTypes.removeAll()
        militaryGoodsTypes.removeAll()
        rawBuildingGoodsTypes.removeAll()
        buildingGoodsTypes.removeAll()
        rawLuxuryGoodsTypes.removeAll()
        otherRawGoodsTypes.removeAll()
        for g in production.keys {
            if g.isFoodType {
                // Food is planned separately.
            } else if g.isLibertyType {
                libertyGoodsTypes.insert(g)
            } else if g.isImmigrationType {
                immigrationGoodsTypes.insert(g)
            } else if g.isMilitary {
                militaryGoodsTypes.insert(g)
            } else if g.isRawBuildingMaterial {
                if g.isRawMaterialForUnstorableBuildingMaterial { rawBuildingGoodsTypes.append(g) }
            } else if g.isBuildingMaterial, g.inputType?.isRawBuildingMaterial ?? false {
                if !g.isStorable { buildingGoodsTypes.insert(g) }
            } else if g.isNewWorldGoodsType {
                rawLuxuryGoodsTypes.insert(g)
            } else if g.isRefined, g.inputType?.isNewWorldGoodsType ?? false {
                // Luxuries follow their raw materials.
            } else if g.isFarmed {
                otherRawGoodsTypes.insert(g)
            } else {
                // Java warns: should not happen.
                production.removeValue(forKey: g)
            }
        }
    }

    /// Choose the two best raw materials, by production and price,
    /// dropping the rest.
    private func updateRawMaterials(_ production: inout Production) {
        let player = colony.owner
        let market = player?.market
        let nationType = player?.nationType
        var primary: GoodsType?, secondary: GoodsType?
        var primaryValue = -1, secondaryValue = -1
        produce.removeAll()
        let rawMaterials = rawLuxuryGoodsTypes.elements + otherRawGoodsTypes.elements
        for g in rawMaterials {
            var value = (production[g]?.values ?? []).reduce(0, +)
            if value <= ColonyPlan.lowProductionThreshold {
                production.removeValue(forKey: g)
                continue
            }
            if let market {
                if let output = g.outputType {
                    if production[output] != nil {
                        value *= (market.salePrice(g, 1) + market.salePrice(output, 1)) / 2
                    }
                } else {
                    value *= market.salePrice(g, 1)
                }
            }
            if nationType?.hasModifier(g.id) ?? false { value = (value * 12) / 10 }
            if value > secondaryValue, let s = secondary {
                production.removeValue(forKey: s)
                if let o = s.outputType { production.removeValue(forKey: o) }
                if !rawLuxuryGoodsTypes.remove(s) { otherRawGoodsTypes.remove(s) }
            }
            if value > primaryValue {
                secondary = primary
                secondaryValue = primaryValue
                primary = g
                primaryValue = value
            } else if value > secondaryValue {
                secondary = g
                secondaryValue = value
            }
        }
        if let primary {
            produce.append(primary)
            if let o = primary.outputType { produce.append(o) }
            if let secondary {
                produce.append(secondary)
                if let o = secondary.outputType { produce.append(o) }
            }
        }
    }

    // Relative weights of the kinds of buildable.
    private static let breedingWeight = 0.1
    private static let buildingWeight = 0.9
    private static let defenceWeight = 0.1
    private static let exportWeight = 0.6
    private static let fishWeight = 0.25
    private static let fortifyWeight = 0.3
    private static let immigrationWeight = 0.05
    private static let libertyWeight = 0.75
    private static let militaryWeight = 0.4
    private static let productionWeight = 0.25
    private static let repairWeight = 0.1
    private static let storageWeight = 0.85
    private static let teachWeight = 0.2
    private static let transportWeight = 0.15

    private func findBuildPlan(_ type: BuildableType) -> BuildPlan? {
        buildPlans.first { $0.type === type }
    }

    /// Add a buildable, or raise its priority.
    @discardableResult
    private func prioritize(_ type: BuildableType, _ weight: Double, _ support: Double) -> Bool {
        guard let bp = findBuildPlan(type) else {
            buildPlans.append(BuildPlan(type, weight, support))
            return true
        }
        if bp.weight * bp.support < weight * support {
            bp.weight = weight
            bp.support = support
            return true
        }
        return false
    }

    /// Prioritize a buildable that improves production of a goods type.
    private func prioritizeProduction(_ type: BuildableType, _ goodsType: GoodsType) -> Bool {
        guard let player = colony.owner else { return false }
        let advantage = aiMain.aiPlayer(player)?.aiAdvantage ?? ""
        var factor = 1.0
        if player.nationType?.hasModifier(goodsType.id) ?? false { factor *= 1.2 }
        if goodsType.isMilitary {
            if advantage == "conquest" { factor = 1.2 }
            return prioritize(type, ColonyPlan.militaryWeight * factor, 1.0)
        } else if goodsType.isBuildingMaterial && !goodsType.isStorable {
            return prioritize(type, ColonyPlan.buildingWeight * factor, 1.0)
        } else if goodsType.isLibertyType {
            if player.isREF { return false }
            return prioritize(type, ColonyPlan.libertyWeight, colony.sonsOfLiberty >= 100 ? 0.01 : 1.0)
        } else if goodsType.isImmigrationType {
            if advantage == "immigration" { factor = 1.2 }
            return prioritize(type, ColonyPlan.immigrationWeight * factor, 1.0)
        } else if produce.contains(where: { $0 === goodsType }) {
            if advantage == "trade" { factor = 1.2 }
            let f = 0.1 * Double(goodsType.inputType.map { colony.totalProduction(of: $0) } ?? 0)
            return prioritize(type, ColonyPlan.productionWeight * factor, f)
        }
        return false
    }

    /// Make the build plans.
    private func updateBuildableTypes() {
        guard let euaip = aiMain.aiPlayer(colony.owner) as? EuropeanAIPlayer, let player = colony.owner,
              let tile = colony.tile else { return }
        let advantage = euaip.aiAdvantage
        buildPlans.removeAll()
        let maxLevel: Int
        switch profileType {
        case .outpost, .small: maxLevel = 1
        case .medium: maxLevel = 2
        case .large: maxLevel = 3
        case .capital: maxLevel = 4
        }
        for type in spec.buildingTypeList where colony.canBuild(type) {
            // Defence and export are exempt from the level check.
            if type.hasModifier(Modifier.defence) {
                prioritize(type, ColonyPlan.fortifyWeight * (advantage == "conquest" ? 1.1 : 1.0), 1.0)
            }
            if type.hasAbility(Ability.export) {
                prioritize(type, ColonyPlan.exportWeight * (advantage == "trade" ? 1.1 : 1.0), 1.0)
            }
            if type.level > maxLevel { continue }
            if type.hasAbility(Ability.produceInWater) {
                var factor = 0.0
                if !colony.hasAbility(Ability.produceInWater) && tile.isShore {
                    var landFood = 0, seaFood = 0
                    for t in tile.surroundingTiles(1, 1)
                    where t.owningSettlement === colony || player.canClaimForSettlement(t) {
                        for ag in t.sortedPotential where ag.isFoodType {
                            if t.isLand { landFood += ag.amount } else { seaFood += ag.amount }
                        }
                    }
                    factor = seaFood + landFood == 0 ? 0.0 : Double(seaFood) / Double(seaFood + landFood)
                }
                prioritize(type, ColonyPlan.fishWeight, factor)
            }
            if type.hasAbility(Ability.build) {
                let factor = advantage == "building" ? 1.1 : 1.0
                let support = type.abilities(Ability.build).contains { $0.hasScope } ? 0.1 : 1.0
                prioritize(type, ColonyPlan.buildingWeight * factor, support)
            }
            if type.hasAbility(Ability.teach) {
                prioritize(type, ColonyPlan.teachWeight, 1.0)
            }
            if type.hasAbility(Ability.repairUnits) {
                prioritize(type, ColonyPlan.repairWeight * (advantage == "naval" ? 1.1 : 1.0), 1.0)
            }
            if let output = type.producedGoodsType {
                _ = prioritizeProduction(type, output)
            } else {
                for g in spec.goodsTypeList where type.hasModifier(g.id) {
                    _ = prioritizeProduction(type, g)
                }
                if type.hasModifier(Modifier.warehouseStorage) {
                    prioritize(type, ColonyPlan.storageWeight * (advantage == "trade" ? 1.1 : 1.0), 1.0)
                }
                if type.hasModifier(Modifier.breedingDivisor) {
                    prioritize(type, ColonyPlan.breedingWeight, 1.0)
                }
            }
        }

        var wagonNeed = 0.0
        if !colony.isConnectedPort {
            let wagons = euaip.neededWagons(tile)
            wagonNeed = wagons <= 0 ? 0.0 : wagons > 3 ? 1.0 : Double(wagons) / 3.0
        }
        for unitType in spec.unitTypeList where colony.canBuild(unitType) {
            if unitType.hasAbility(Ability.navalUnit) {
                // Java does not decide to build ships yet.
            } else if unitType.isDefensive {
                if euaip.needsMoreArtillery { prioritize(unitType, ColonyPlan.defenceWeight, 1.0) }
            } else if wagonNeed > 0.0 && unitType.hasAbility(Ability.carryGoods) {
                prioritize(unitType, ColonyPlan.transportWeight * (advantage == "trade" ? 1.1 : 1.0), wagonNeed)
            }
        }

        // Weight by the goods still needed, more for goods not made here.
        for bp in buildPlans {
            var difficulty = 0
            for ag in bp.type.requiredGoods {
                guard let type = ag.type, ag.amount > colony.goodsCount(type) else { continue }
                let local = produce.contains { $0 === type.inputType }
                difficulty += (ag.amount - colony.goodsCount(type)) * (local ? 1 : 5)
            }
            bp.difficulty = max(1.0, Double(difficulty).squareRoot())
        }
        buildPlans = buildPlans.stableSorted { $0.value > $1.value }
    }

    /// Make a plan for each possible production at a location that can
    /// be worked or produces by itself, complete the goods to produce,
    /// and keep the plans that need a worker, the most wanted first.
    private func updatePlans(_ production: Production) {
        workPlans.removeAll()
        for (g, m) in production.entries
        where !g.isStorable || g.limitIgnored || colony.goodsCount(g) < colony.warehouseCapacity {
            for wl in m.keys where wl.canBeWorked || wl.canAutoProduce {
                workPlans.append(WorkLocationPlan(aiMain, wl, g))
            }
        }
        updateProductionList(production)
        workPlans = workPlans.filter { $0.workLocation.canBeWorked }
        let order: (WorkLocationPlan) -> Int = { wp in
            let gt = wp.goodsType
            let i = self.produce.firstIndex { $0 === gt } ?? -1
            return i < 0 && !gt.isFoodType ? 99999 : i
        }
        workPlans = workPlans.stableSorted { a, b in
            let oa = order(a), ob = order(b)
            if oa != ob { return oa < ob }
            let pa = -a.workLocation.genericPotential(a.goodsType)
            let pb = -b.workLocation.genericPotential(b.goodsType)
            if pa != pb { return pa < pb }
            return GoodsType.compare(a.goodsType, b.goodsType) < 0
        }
    }

    /// Add the other goods types to the production list, which has the
    /// raw materials chosen (updateProductionList).
    private func updateProductionList(_ production: Production) {
        let total: (GoodsType) -> Int = { gt in (production[gt]?.values ?? []).reduce(0, +) }
        let byProduction: ([GoodsType]) -> [GoodsType] = { $0.stableSorted { total($0) > total($1) } }

        // Liberty first, while it is needed.
        if colony.sonsOfLiberty < 100 {
            produce.insert(contentsOf: byProduction(libertyGoodsTypes.elements.filter { production[$0] != nil }),
                           at: 0)
        }

        // Raw and building materials first of all.
        rawBuildingGoodsTypes = byProduction(rawBuildingGoodsTypes)
        let indexer: (GoodsType) -> Int = { gt in
            self.rawBuildingGoodsTypes.firstIndex { $0 === gt.inputType } ?? -1
        }
        let toAdd = buildingGoodsTypes.elements.filter { gt in
            production[gt] != nil
                && ((gt.inputType.map { colony.goodsCount($0) } ?? 0) >= GoodsContainer.cargoSize / 2
                    || (gt.inputType.map { production[$0] != nil } ?? false))
        }.stableSorted { indexer($0) > indexer($1) }
        for make in toAdd.reversed() {
            if let raw = make.inputType, production[raw] != nil {
                if colony.goodsCount(raw) >= GoodsContainer.cargoSize / 2 {
                    produce.append(raw) // Enough in stock: last.
                    produce.insert(make, at: 0)
                } else {
                    produce.insert(make, at: 0)
                    produce.insert(raw, at: 0)
                }
            } else {
                produce.insert(make, at: 0)
            }
        }

        // Military goods after the lucrative production.
        produce += byProduction(militaryGoodsTypes.elements.filter { production[$0] != nil })

        // Immigration last.
        if colony.owner?.europe != nil {
            produce += byProduction(immigrationGoodsTypes.elements.filter { production[$0] != nil })
        }
    }

    private func findPlan(_ goodsType: GoodsType, _ plans: [WorkLocationPlan]) -> WorkLocationPlan? {
        plans.first { $0.goodsType === goodsType }
    }

    /// The best worker for a plan (getBestWorker): the one adding most
    /// to production; of equals, an expert, then one that can become
    /// the expert with the most relevant experience, then the least
    /// skilled.
    static func bestWorker(_ wl: WorkLocation, _ goodsType: GoodsType, _ workers: [Unit]) -> Unit? {
        guard !workers.isEmpty, let colony = wl.colony else { return nil }
        let outputType = goodsType.isStoredAs ? goodsType.storedAs : goodsType

        // Accept a lone worker that does something, to avoid emptying
        // the colony.
        if workers.count == 1 {
            let u = workers[0]
            if !wl.canAdd(u) { return nil }
            let oldLoc = u.location
            let oldWork = u.workType
            _ = u.setLocation(wl)
            u.changeWorkType(goodsType)
            let production = wl.productionOf(u, goodsType)
            _ = u.setLocation(oldLoc)
            u.changeWorkType(oldWork)
            return production > 0 ? u : nil
        }

        var todo = workers
        var best: [Unit] = []
        var bestValue = colony.adjustedNetProduction(of: outputType)
        var special: Unit?
        for u in todo where wl.canAdd(u) {
            let oldLoc = u.location
            let oldWork = u.workType
            _ = u.setLocation(wl)
            u.changeWorkType(goodsType)
            let value = colony.adjustedNetProduction(of: outputType)
            if value > bestValue {
                bestValue = value
                best = [u]
                if u.type?.expertProduction === goodsType { special = u }
            } else if value == bestValue && !best.isEmpty {
                best.append(u)
                if u.type?.expertProduction === goodsType { special = u }
            }
            _ = u.setLocation(oldLoc)
            u.changeWorkType(oldWork)
        }
        switch best.count {
        case 0: return nil
        case 1: return best[0]
        default: todo = best
        }
        // Several winners including an expert: they are all experts.
        if let special { return special }

        // Favour those that can become the expert by experience, avoid
        // those that can become something else, and favour relevant
        // experience.
        let expert = colony.specification?.expert(producing: goodsType)
        best = []
        bestValue = Int.min
        for u in todo {
            let relevant = u.workType === goodsType
            var score = relevant ? u.experience : -u.experience
            if let expert, u.unitChange(UnitChangeType.experience, expert) != nil {
                score += 10000
            } else if expert != nil, u.unitChange(UnitChangeType.experience) != nil {
                score -= 10000
            }
            if score > bestValue {
                best = [u]
                bestValue = score
            } else if score == bestValue {
                best.append(u)
            }
        }
        switch best.count {
        case 0: break
        case 1: return best[0]
        default: todo = best
        }

        // The least skilled, keeping experts for their own work.
        var worstSkill = Int.max
        special = nil
        for u in todo where (u.type?.skill ?? 0) < worstSkill {
            special = u
            worstSkill = u.type?.skill ?? 0
        }
        return special
    }

    /// Equip a unit fully for a role from a colony's store.
    private static func fullEquipUnit(_ unit: Unit, _ role: Role, _ colony: Colony) -> Bool {
        colony.equipForRole(unit, role, role.maximumCount)
    }

    /// Try the plan with the workers on a copy of the colony
    /// (assignWorkers): outdoor experts outside, then workers greedily
    /// to the plans, food when needed, then experts swapped into their
    /// work and the rest armed.
    ///
    /// - Parameters:
    ///   - workers: The units to place, replaced by the copy's.
    ///   - preferScout: Make scouts rather than soldiers.
    /// - Returns: The copy with the workers in place, or nil if none
    ///   could work.
    func assignWorkers(_ workers: inout [Unit], _ preferScout: Bool) throws -> Colony? {
        guard let foodType = spec.primaryFoodType, let defaultRole = spec.defaultRole else { return nil }

        var produce = preferredProduction
        var foodPlans = self.foodPlans
        var workPlans = otherWorkPlans

        let col = try colony.copyColony()
        guard let tile = col.tile else { return nil }

        // The copy's units in place of the workers.
        workers = workers.compactMap { col.corresponding($0) }

        // Everyone to the tile, without equipment.
        for u in workers {
            _ = u.setLocation(tile)
            _ = col.equipForRole(u, defaultRole, 0)
        }

        // Outdoor experts outside, scouts before soldiers if preferred.
        var outdoorRoles: [Role?] = [spec.roleWithAbility(Ability.improveTerrain), nil,
                                     spec.roleWithAbility(Ability.speakWithChief)]
        if preferScout { outdoorRoles.swapAt(1, 2) }
        for outdoorRole in outdoorRoles {
            for u in workers {
                if workers.count <= 1 { break }
                if let role = outdoorRole {
                    if u.type === role.expertUnit && ColonyPlan.fullEquipUnit(u, role, col) {
                        workers.removeAll { $0 === u }
                    }
                } else {
                    for r in u.sortedMilitaryRoles
                    where u.type === r.expertUnit && ColonyPlan.fullEquipUnit(u, r, col) {
                        workers.removeAll { $0 === u }
                        break
                    }
                }
            }
        }

        // Greedy assignment of the other workers to the plans.
        let buildGoods = col.currentlyBuilding?.requiredGoods ?? []
        var done = false
        while !done && !workers.isEmpty {
            // Decide what to produce: the plan to try, and the list it
            // came from.
            var fromFood = false
            var wlp: WorkLocationPlan?
            if col.adjustedNetProduction(of: foodType) > 0 {
                while let first = produce.first {
                    if let p = findPlan(first, workPlans) {
                        wlp = p
                        break
                    }
                    produce.removeFirst()
                }
            }
            // Java's List.remove(plan): plans have no identifier, so all
            // are equal and the first in the list goes, whichever it is.
            func removePlan(_ p: WorkLocationPlan) {
                if fromFood {
                    if !foodPlans.isEmpty { foodPlans.removeFirst() }
                } else {
                    if !workPlans.isEmpty { workPlans.removeFirst() }
                }
            }

            while true {
                if wlp == nil {
                    guard let first = foodPlans.first else {
                        done = true // Food plans exhausted.
                        break
                    }
                    fromFood = true
                    wlp = first
                }
                let plan = wlp!
                let goodsType = plan.goodsType
                guard let wl = col.corresponding(plan.workLocation) else {
                    throw JavaException("NullPointerException in ColonyPlan.assignWorkers")
                }
                var best: Unit?
                if !wl.canBeWorked || wl.isFull {
                    removePlan(plan)
                    break
                }
                best = ColonyPlan.bestWorker(wl, goodsType, workers)
                guard let best else {
                    removePlan(plan)
                    break
                }

                // Place the worker.
                _ = best.setLocation(wl)

                // Did it break the production bonus?
                if col.productionBonus < 0 {
                    _ = best.setLocation(tile)
                    done = true
                    break
                }

                // Would the colony starve soon?
                if col.adjustedNetProduction(of: foodType) < 0 {
                    let net = col.adjustedNetProduction(of: foodType)
                    let count = col.goodsCount(foodType)
                    if count / -net < ColonyPlan.productionTurnoverTurns {
                        // Back out and try a food plan, unless this
                        // was one.
                        _ = best.setLocation(tile)
                        wlp = nil
                        if goodsType.isFoodType {
                            done = true
                            break
                        }
                        continue
                    }
                    // Otherwise let the food run down.
                }

                // Would the raw material run out soon?  Keep what the
                // building needs.
                let raw = goodsType.inputType
                let rawNeeded = buildGoods.filter { $0.type === raw }.reduce(0) { $0 + $1.amount }
                if raw == nil || col.adjustedNetProduction(of: raw!) >= 0
                    || (col.goodsCount(raw!) - rawNeeded) / -col.adjustedNetProduction(of: raw!)
                        >= ColonyPlan.productionTurnoverTurns {
                    // Placed: the goods type to the end of the list
                    // for reuse, the plan kept.
                    best.changeWorkType(goodsType)
                    workers.removeAll { $0 === best }
                    if !goodsType.isFoodType, removeFirst(&produce, goodsType) { produce.append(goodsType) }
                    break
                }

                // More raw material is needed: try making it.
                _ = best.setLocation(tile)
                if let rawWlp = findPlan(raw!, workPlans) {
                    if removeFirst(&produce, raw!) { produce.insert(raw!, at: 0) }
                    wlp = rawWlp // From the same list as before, as in Java.
                    continue
                }

                // No raw material: give up the plan and the goods.
                removePlan(plan)
                removeFirst(&produce, goodsType)
                break
            }
        }

        // The rest stay on the tile.
        for u in workers where u.location !== tile { _ = u.setLocation(tile) }

        // If no one is working, find somewhere harmless for one, or
        // somewhere to subsist.
        if col.unitCount == 0 {
            if self.foodPlans.isEmpty {
                locations: for wl in col.availableWorkLocations {
                    for u in workers {
                        for type in libertyGoodsTypes.elements
                        where wl.canAdd(u) && wl.potentialProduction(type, u.type) > 0 {
                            _ = u.setLocation(wl)
                            u.changeWorkType(type)
                            workers.removeAll { $0 === u }
                            break locations
                        }
                    }
                }
            } else {
                plans: for w in self.foodPlans {
                    let goodsType = w.goodsType
                    guard let wl = col.corresponding(w.workLocation) else { continue }
                    for u in workers {
                        let oldWork = u.workType
                        _ = u.setLocation(wl)
                        u.changeWorkType(goodsType)
                        if col.adjustedNetProduction(of: foodType) >= 0 {
                            workers.removeAll { $0 === u }
                            break plans
                        }
                        _ = u.setLocation(tile)
                        u.changeWorkType(oldWork)
                    }
                }
            }
        }

        // Swap misplaced experts into their work.
        var experts: [Unit] = []
        var nonExperts: [Unit] = []
        for u in col.unitList {
            if let ep = u.type?.expertProduction {
                if ep !== u.workType { experts.append(u) }
            } else {
                nonExperts.append(u)
            }
        }
        // Java's iterator: a removal does not disturb the walk.
        var e = 0
        while e < experts.count {
            let u1 = experts[e]
            if u1.trySwapExpert(experts) != nil || u1.trySwapExpert(nonExperts) != nil {
                experts.remove(at: e)
            } else {
                e += 1
            }
        }
        for u in workers where u.type?.expertProduction != nil {
            if let other = u.trySwapExpert(col.unitList) {
                workers.removeAll { $0 === u }
                workers.append(other)
            }
        }

        // Arm what remains as far as possible: the least skilled first,
        // then by expertise and production wanted, then experience.
        let key: (Unit) -> (Int, Int, Int) = { u in
            let ep = u.type?.expertProduction
            return (u.skillLevel, ep == nil ? 1 : 0, ep.flatMap { e in produce.firstIndex { $0 === e } } ?? -1)
        }
        let soldiers = workers.stableSorted { a, b in
            let ka = key(a), kb = key(b)
            if ka != kb { return ka > kb } // reversed
            return a.experience < b.experience
        }
        for u in soldiers where u.skillLevel <= 0 {
            for role in u.sortedMilitaryRoles where ColonyPlan.fullEquipUnit(u, role, col) {
                workers.removeAll { $0 === u }
                break
            }
        }
        for u in col.unitList where !u.hasDefaultRole {
            u.changeRole(defaultRole, 0) // Java warns
        }

        if col.unitCount <= 0 {
            col.releaseCopy()
            return nil
        }
        return col
    }
}

/// Remove the first occurrence, as Java's List.remove(Object).
@discardableResult
func removeFirst<T: AnyObject>(_ list: inout [T], _ element: T) -> Bool {
    guard let i = list.firstIndex(where: { $0 === element }) else { return false }
    list.remove(at: i)
    return true
}

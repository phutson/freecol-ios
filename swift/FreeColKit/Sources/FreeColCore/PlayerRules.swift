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

import Foundation
import FreeColUtil

/// A player's rules: migration, liberty and founding fathers, taxes and
/// trade, prices in Europe, claiming land and the AI's value of a
/// colony site (the rest of common/model/Player).
extension Player {

    /// The parts of a colony site's value (Player.ColonyValueCategory).
    /// The goods checks follow the last, one for each goods type the
    /// rules want checked.
    public enum ColonyValueCategory: Int, CaseIterable {
        case override, production, tile, europe, resource, adjacent, food, level, nearby, goods
    }

    /// Values for a colony site that rule it out
    /// (Player.NoValueType).
    public enum NoValueType: Int {
        case bogus = -1, terrain = -2, rumour = -3, settled = -4, food = -5, inland = -6
        case polar = -7, island1 = -8

        public var double: Double { Double(rawValue) }

        /// Java's fromValue: anything unknown is bogus.
        public static func from(_ i: Int) -> NoValueType {
            NoValueType(rawValue: i) ?? .bogus
        }
    }

    // MARK: Migration

    /// Immigration points, which only colonial players collect.
    public var immigration: Int {
        get { isColonial ? immigrationPoints : 0 }
        set { if isColonial { immigrationPoints = newValue } }
    }

    public func modifyImmigration(_ amount: Int) {
        immigrationPoints = max(0, immigrationPoints + amount)
    }

    /// Spend the immigration points for a migrant, keeping any surplus
    /// if the rules save overflow.
    public func reduceImmigration() {
        guard isColonial else { return }
        let cost = (specification?.getBoolean(GameOptions.saveProductionOverflow) ?? false)
            ? immigrationRequired : immigrationPoints
        immigrationPoints = cost > immigrationPoints ? 0 : immigrationPoints - cost
    }

    /// Raise the immigration needed for the next migrant, keeping any
    /// religious unrest bonus.
    public func updateImmigrationRequired() {
        guard isColonial, let spec = specification else { return }
        let turn = game?.turn
        let base = spec.getInteger(GameOptions.crossesIncrement) ?? 0
        // The bonus has already reduced immigrationRequired; apply it to
        // the unreduced target plus the increment.
        let unreduced = Int(JavaMath.round(Float(immigrationRequired)
            / apply(1, turn: turn, Modifier.religiousUnrestBonus)))
        immigrationRequired = Int(JavaMath.toInt(apply(Float(unreduced + base), turn: turn,
                                                       Modifier.religiousUnrestBonus)))
    }

    /// Whether there is enough immigration for a migrant.
    public var checkEmigrate: Bool {
        isColonial && immigrationRequired <= immigrationPoints
    }

    /// The immigration the colonies and Europe produce each turn.
    public var totalImmigrationProduction: Int {
        guard isColonial, let spec = specification else { return 0 }
        let types = spec.immigrationGoodsTypeList
        var production = colonyList.reduce(0) { sum, c in
            sum + types.reduce(0) { $0 + c.totalProduction(of: $1) }
        }
        if let europe { production += europe.immigration(production) }
        return production
    }

    // MARK: Liberty and founding fathers

    /// Liberty, which only players with founding fathers collect.
    public var liberty: Int {
        get { canHaveFoundingFathers ? libertyPoints : 0 }
        set { if canHaveFoundingFathers { libertyPoints = newValue } }
    }

    public func modifyLiberty(_ amount: Int) {
        liberty = max(0, libertyPoints + amount)
        if isRebel { interventionBells += amount }
    }

    /// Set the bells bonus of the abilities that add tax to bells
    /// (Thomas Paine) to the tax rate.
    ///
    /// - Returns: Whether any bonus was set.
    @discardableResult
    public func recalculateBellsBonus() -> Bool {
        var ret = false
        for ability in abilities(Ability.addTaxToBells) {
            guard let source = ability.source else { continue }
            for modifier in modifiers("model.goods.bells") where modifier.source?.id == source.id {
                modifier.value = Float(tax)
                ret = true
            }
        }
        return ret
    }

    /// The liberty the colonies will make next turn.
    public var libertyProductionNextTurn: Int {
        guard let spec = specification else { return 0 }
        let types = spec.libertyGoodsTypeList
        let nextTurn = colonyList.reduce(0) { sum, c in
            sum + types.reduce(0) { $0 + c.totalProduction(of: $1) }
        }
        return Int(JavaMath.toInt(apply(Float(nextTurn), turn: game?.turn, Modifier.liberty)))
    }

    /// The average rebel percentage of the player's colonies.
    public var sonsOfLiberty: Int {
        let colonies = colonyList
        return colonies.isEmpty ? 0 : colonies.reduce(0) { $0 + $1.sonsOfLiberty } / colonies.count
    }

    public var remainingFoundingFatherCost: Int {
        totalFoundingFatherCost - liberty
    }

    /// The liberty needed for the next founding father.
    public var totalFoundingFatherCost: Int {
        let base = specification?.getInteger(GameOptions.foundingFatherFactor) ?? 0
        let count = fatherCount
        return count == 0 ? base : 2 * (count + 1) * base + 1
    }

    /// Why independence can not be declared, as Java's message key, or
    /// nil if it can (checkDeclareIndependence gives the template).
    public var checkDeclareIndependenceKey: String? {
        guard playerType == .colonial else { return "model.player.colonialIndependence" }
        let event = specification?.getEvent("model.event.declareIndependence")
        return event?.limitValues.first(where: { !$0.evaluate(self) })?.descriptionKey
    }

    // MARK: Forces

    /// The Royal Expeditionary Force waiting to sail, for colonial
    /// players.
    public var refUnits: [AbstractUnit]? {
        playerType == .colonial ? monarch?.expeditionaryForce.unitList : nil
    }

    /// The offensive units, grouped by type and role in Java's HashMap
    /// order.  Units without offence of their own count as the default
    /// type.
    public var militaryUnits: [AbstractUnit] {
        guard let spec = specification else { return [] }
        let defaultType = spec.defaultUnitType(nationType)
        let milUnits = units.filter(\.isOffensiveUnit)
        var unitHash = JavaHashMap<UnitType, JavaHashMap<String, Int>>(
            initialCapacity: milUnits.count, javaHash: { $0.javaHashCode })
        for unit in milUnits {
            var unitType = defaultType
            if (unit.type?.offence ?? 0) > 0 || unit.hasAbility(Ability.expertSoldier) {
                unitType = unit.type
            }
            guard let unitType, let roleId = unit.role?.id else { continue }
            var roleMap = unitHash[unitType]
                ?? JavaHashMap<String, Int>(initialCapacity: spec.militaryRolesList.count,
                                            javaHash: JavaString.hashCode)
            _ = roleMap.put(roleId, (roleMap[roleId] ?? 0) + 1)
            _ = unitHash.put(unitType, roleMap)
        }
        var result: [AbstractUnit] = []
        for (type, roles) in unitHash.entries {
            for (roleId, n) in roles.entries {
                result.append(AbstractUnit(id: type.id, roleId: roleId, number: n))
            }
        }
        return result
    }

    /// Java's strengthRatio: our share of the combined strength.
    public static func strengthRatio(_ ours: Double, _ theirs: Double) -> Double {
        ours == 0.0 ? 0.0 : ours / (ours + theirs)
    }

    // MARK: Taxes and trade

    /// Set the tax, and the bells bonus that follows it.
    public func setTax(_ amount: Int) {
        tax = amount
        if recalculateBellsBonus() {
            for c in colonyList { c.invalidateCache() }
        }
    }

    /// The arrears owed for goods under boycott.
    public func arrears(_ type: GoodsType) -> Int {
        market?.arrears(type) ?? 0
    }

    public func canTrade(_ type: GoodsType) -> Bool {
        canTrade(type, .europe)
    }

    /// Whether goods can be traded: not boycotted, or through a custom
    /// house allowed to ignore the boycott or trading with a friendly
    /// European.
    public func canTrade(_ type: GoodsType, _ access: Market.Access) -> Bool {
        if arrears(type) == 0 { return true }
        guard access == .customHouse, let spec = specification else { return false }
        return spec.getBoolean(GameOptions.customIgnoreBoycott)
            || (hasAbility(Ability.customHouseTradesWithForeignCountries)
                && (game?.liveEuropeanPlayers(excluding: self).contains {
                    stance($0) == .peace || stance($0) == .alliance
                } ?? false))
    }

    public func sales(_ goodsType: GoodsType) -> Int {
        market?.sales(goodsType) ?? 0
    }

    public func modifySales(_ goodsType: GoodsType, _ amount: Int) {
        market?.modifySales(goodsType, amount)
    }

    public func hasTraded(_ goodsType: GoodsType) -> Bool {
        market?.hasBeenTraded(goodsType) ?? false
    }

    /// The colony goods that would sell for most (up to a hold's worth),
    /// of the traded goods not under boycott, the first of equals.
    public var mostValuableGoods: Goods? {
        guard isEuropean, let market else { return nil }
        var best: Goods?
        var bestValue = Int.min
        for c in colonyList {
            for g in c.compactGoodsList {
                guard let type = g.type, arrears(type) <= 0, hasTraded(type) else { continue }
                let value = market.salePrice(type, min(g.amount, GoodsContainer.cargoSize))
                if best == nil || value > bestValue {
                    best = g
                    bestValue = value
                }
            }
        }
        return best
    }

    public func incomeBeforeTaxes(_ goodsType: GoodsType) -> Int {
        market?.incomeBeforeTaxes(goodsType) ?? 0
    }

    public func modifyIncomeBeforeTaxes(_ goodsType: GoodsType, _ amount: Int) {
        market?.modifyIncomeBeforeTaxes(goodsType, amount)
    }

    public func incomeAfterTaxes(_ goodsType: GoodsType) -> Int {
        market?.incomeAfterTaxes(goodsType) ?? 0
    }

    public func modifyIncomeAfterTaxes(_ goodsType: GoodsType, _ amount: Int) {
        market?.modifyIncomeAfterTaxes(goodsType, amount)
    }

    // MARK: Prices in Europe

    public var europeanRecruitPrice: Int {
        europe?.currentRecruitPrice ?? 0
    }

    /// The price of units in Europe, with the goods for their role.
    public func europeanPurchasePrice(_ au: AbstractUnit) -> Int {
        guard let spec = specification, let unitType = au.type(spec), let market, unitType.hasPrice,
              let europe else { return Constants.infinity }
        return au.number * (europe.unitPrice(unitType) + (au.role(spec)?.requiredGoodsPrice(market) ?? 0))
    }

    /// The price to hire mercenaries: their mercenary price, or their
    /// price if they have none.
    public func mercenaryHirePrice(_ au: AbstractUnit) -> Int {
        guard let spec = specification, let unitType = au.type(spec) else { return 0 }
        var price = unitType.mercenaryPrice
        if price < 0 { price = unitType.price }
        // Java's int arithmetic, which wraps (an undefined price of
        // Integer.MIN_VALUE for two units gives 0).
        return Int(Int32(truncatingIfNeeded: price) &* Int32(truncatingIfNeeded: au.number))
    }

    // MARK: Claiming land

    /// What land costs this player: 0 if free, -1 if not for sale, or
    /// the natives' price.
    public func landPrice(_ tile: Tile) -> Int {
        guard let spec = specification else { return 0 }
        let nationOwner = tile.owner
        if nationOwner == nil || nationOwner === self { return 0 }
        if tile.hasSettlement { return -1 }
        if nationOwner!.isEuropean {
            // Nailed down by a European colony, or only an abandoned claim.
            return tile.owningSettlement?.owner === nationOwner ? -1 : 0
        }
        // Native land: only the specific food types count, not the
        // aggregate food type.
        let food = spec.goodsTypeList.filter { $0 !== spec.primaryFoodType }
            .reduce(0) { $0 + tile.potentialProduction($1, nil) }
        let price = (spec.getInteger(GameOptions.landPriceFactor) ?? 0) * food + 100
        return Int(JavaMath.toInt(apply(Float(price), turn: game?.turn, Modifier.landPaymentModifier)))
    }

    private func canOwnTileReason(_ tile: Tile) -> NoClaimReason {
        if tile.unitList.contains(where: { $0.owner !== self && $0.isOffensiveUnit }) {
            return .occupied // Held against us
        }
        if isEuropean { return tile.hasLostCityRumour ? .rumour : .none }
        return tile.isLand ? .none : .water
    }

    public func canOwnTile(_ tile: Tile) -> Bool {
        canOwnTileReason(tile) == .none
    }

    /// Why this player could not claim a tile for a settlement, or none.
    public func canClaimForSettlementReason(_ tile: Tile) -> NoClaimReason {
        let reason = canOwnTileReason(tile)
        if reason != .none { return reason }
        if tile.hasSettlement { return .settlement }
        guard let tileOwner = tile.owner else { return .none }
        if tileOwner === self { return tile.isInUse ? .worked : .none }
        let price = landPrice(tile)
        return price < 0 ? .europeans : price > 0 ? .natives : .none
    }

    public func canClaimForSettlement(_ tile: Tile) -> Bool {
        canClaimForSettlementReason(tile) == .none
    }

    /// Why this player could not found a settlement on a tile, or none.
    /// Native land is free for the first colony if the rules say so.
    public func canClaimToFoundSettlementReason(_ tile: Tile) -> NoClaimReason {
        if !(tile.type?.canSettle ?? false) { return .terrain }
        let reason = canClaimForSettlementReason(tile)
        if reason != .natives { return reason }
        if !tile.adjacentColonies.isEmpty { return .settlement }
        return canClaimFreeCenterTile(tile) ? .none : .natives
    }

    public func canClaimToFoundSettlement(_ tile: Tile) -> Bool {
        canClaimToFoundSettlementReason(tile) == .none
    }

    private func canClaimFreeCenterTile(_ tile: Tile) -> Bool {
        guard isEuropean, let tileOwner = tile.owner, tileOwner.isIndian else { return false }
        let build = specification?.getString(GameOptions.buildOnNativeLand)
        return build == GameOptions.buildOnNativeLandAlways
            || (build == GameOptions.buildOnNativeLandFirst && hasZeroSettlements)
            || (build == GameOptions.buildOnNativeLandFirstAndUncontacted && hasZeroSettlements
                && tileOwner.stance(self) == .uncontacted)
    }

    /// No settlements, or only one that is not yet on its tile.
    private var hasZeroSettlements: Bool {
        settlements.isEmpty || (settlements.count == 1 && settlements[0].tile?.settlement == nil)
    }

    /// Whether a tile is free to improve: unowned, ours, or free land.
    public func canClaimForImprovement(_ tile: Tile) -> Bool {
        tile.owner == nil || tile.owner === self || landPrice(tile) == 0
    }

    /// Whether a tile could be had for an improvement, by claim or by
    /// buying it.
    public func canAcquireForImprovement(_ tile: Tile) -> Bool {
        canClaimForImprovement(tile) || landPrice(tile) > 0
    }

    /// The tiles a settlement on a tile could claim, ring by ring out
    /// to a radius, each reachable through claimable tiles.
    public func claimableTiles(_ centerTile: Tile, _ radius: Int) -> [Tile] {
        var tiles: [Tile] = []
        guard canClaimToFoundSettlement(centerTile), radius >= 0 else { return tiles }
        var layer: [Tile] = [centerTile]
        if radius >= 1 {
            for _ in 1...radius {
                let lastLayer = layer
                tiles += layer
                layer = lastLayer.flatMap { $0.surroundingTiles(1, 1) }
                    .filter { t in !tiles.contains { $0 === t } && canClaimForSettlement(t) }
            }
        }
        tiles += layer
        return tiles
    }

    // MARK: Colony site values (for the AI)

    /// The parts of the value of a colony on a tile, multiplied together
    /// for the value.  A negative first part is a NoValueType ruling the
    /// site out.
    public func allColonyValues(_ tile: Tile) -> [Double] {
        // Want a few settlements before taking risks
        let lowSettlementNumber = 3
        // Would like a caravel to reach high seas in 3 moves
        let longPathTiles = 12

        // Applied once
        let modHasResource = 0.75
        let modFoodLow = 0.75
        let modSteal = 0.5
        let modInland = 0.5

        // Applied per surrounding tile
        let modOwnedEuropean = 0.67
        let modOwnedNative = 0.8

        // Applied per goods production, per surrounding tile
        let modHighProduction = 1.2
        let modGoodProduction = 1.1

        // Applied per occurrence (own colony only once), by range.
        // Colonies should be placed at distance 3 from each other, the
        // closest without overlap.
        let modOwnColony = [0.0, 0.0, 0.0, 2.00, 0.75, 0.9, 1.50, 1, 1, 1.25]
        let modEnemyColony = [0.0, 0.0, 0.0, 0.70, 0.50, 0.9, 1.25, 1, 1, 1.10]
        let modNeutralColony = [0.0, 0.0, 0.0, 1.00, 0.80, 0.9, 1.25, 1, 1, 1.10]
        let modIndianSettlement = [0.0, 0.0, 0.9, 1.00, 1.00, 1.0, 1.00, 1, 1, 1.00]
        let modEnemyUnit = [0.4, 0.5, 0.6, 0.75, 0.90, 0.0, 0.00, 0, 0, 0.00]
        let distanceMax = modOwnColony.count

        // Goods production in excess of this on a tile counts as
        // good/high
        let goodProduction = 4
        let highProduction = 8

        // Overall food production is low or very low if less than...
        let foodLow = 4
        let foodVeryLow = 1

        typealias C = ColonyValueCategory
        var values = Array(repeating: 1.0, count: C.allCases.count)
        func set(_ c: C, _ v: Double) { values[c.rawValue] = v }
        func scale(_ c: C, _ v: Double) { values[c.rawValue] *= v }
        func fail(_ n: NoValueType) -> [Double] {
            set(.override, n.double)
            return values
        }

        // Penalize some problems more in the first colonies: development
        // rises from 1/lowSettlementNumber to 1.
        let development = Double(min(lowSettlementNumber, settlementCount)) / Double(lowSettlementNumber)
        let portCount = numberOfPorts

        if tile.isPolar && settlementCount < lowSettlementNumber { return fail(.polar) }

        switch canClaimToFoundSettlementReason(tile) {
        case .none:
            break
        case .terrain, .water:
            return fail(.terrain)
        case .rumour:
            if !hasSettlements { return fail(.rumour) }
            set(.tile, development)
        case .occupied: // transient we hope
            set(.tile, modEnemyUnit[0])
        case .settlement, .worked, .europeans:
            return fail(.settled)
        case .natives: // If we have no ports, we are desperate enough to steal
            if let owningTile = tile.owningSettlement?.tile, owningTile.isAdjacent(tile) {
                return fail(.settled)
            }
            let price = landPrice(tile)
            if price > 0 && portCount > 0 && !checkGold(price) { set(.tile, modSteal) }
        }

        guard let spec = specification, let foodType = spec.primaryFoodType else { return fail(.bogus) }
        var production = TypeCountMap<GoodsType>()

        // Start with the food production.
        let initialFood = tile.bestFoodProduction?.amount ?? 0
        if initialFood <= foodVeryLow { return fail(.food) }
        production.increment(foodType, by: initialFood)
        set(.production, Double(initialFood) * Double(foodType.productionWeight))

        // Penalty if there is no direct connection to the high seas, or
        // if it is too long.
        let tilesToHighSeas = tile.highSeasCount
        if tilesToHighSeas < 0 {
            if portCount < lowSettlementNumber { return fail(.inland) }
            set(.europe, modInland)
        } else if tilesToHighSeas >= longPathTiles {
            // In proportion to the length, but by its square for the
            // first colony.
            let trip = Double(longPathTiles) / Double(tilesToHighSeas)
            set(.europe, javaPow(trip, 2.0 - development))
        } else {
            set(.europe, 1.0 + 0.25 * (Double(longPathTiles) / Double(longPathTiles - tilesToHighSeas)))
        }

        // Production on a resource tile can not be improved much.
        set(.resource, tile.hasResource ? modHasResource : 1.0)

        // Java's HashSets; only their sizes matter.
        var highProductionTypes = Set<ObjectIdentifier>()
        var goodProductionTypes = Set<ObjectIdentifier>()
        var land = 0
        for t in tile.surroundingTiles(1, 1) where t.type != nil {
            if t.settlement != nil { return fail(.settled) } // Should not happen, tested above
            if t.isLand { land += 1 }

            var pf = 1.0
            if let tOwner = t.owner, !owns(t) {
                if tOwner.isEuropean {
                    if portCount < lowSettlementNumber { return fail(.settled) }
                    // Java multiplies left to right, rounding at each step.
                    values[C.adjacent.rawValue] = values[C.adjacent.rawValue] * modOwnedEuropean * development
                    continue // Always ignore production from this tile
                }
                pf = modOwnedNative
                if portCount > 0 { pf *= development }
            }

            // Count production
            for ag in t.sortedPotential {
                guard var type = ag.type else { continue }
                if type.isFoodType { type = foodType }
                var amount = ag.amount
                if !t.isLand { // Penalize water early
                    amount = Int(JavaMath.toInt(Double(amount) * development))
                }
                // int * float is float arithmetic in Java.
                values[C.production.rawValue] += Double(Float(amount) * type.productionWeight) * pf
                production.increment(type, by: amount)
                // A few tiles with distinct high production are better
                // than many tiles with low production.
                if amount > highProduction {
                    highProductionTypes.insert(ObjectIdentifier(type))
                } else if amount > goodProduction {
                    goodProductionTypes.insert(ObjectIdentifier(type))
                }
            }

            for u in t.unitList where !owns(u) && u.isOffensiveUnit && atWar(with: u.owner) {
                scale(.adjacent, modEnemyUnit[1])
            }
        }
        if land <= 1 { return fail(.island1) } // Never settle the 1-tile islands

        for g in highProductionTypes {
            scale(.level, modHighProduction)
            goodProductionTypes.remove(g)
        }
        if !goodProductionTypes.isEmpty {
            values[C.level.rawValue] = values[C.level.rawValue] * modGoodProduction
                * Double(goodProductionTypes.count)
        }

        // Other settlements at a distance.
        if let map = game?.map {
            for radius in 1..<distanceMax {
                for t in map.circleTiles(tile, filled: false, radius: radius) {
                    guard let settlement = t.settlement else { continue }
                    if settlement is IndianSettlement {
                        scale(.nearby, modIndianSettlement[radius])
                    } else if owns(settlement) {
                        scale(.nearby, modOwnColony[radius])
                    } else if atWar(with: settlement.owner) {
                        scale(.nearby, modEnemyColony[radius])
                    } else {
                        scale(.nearby, modNeutralColony[radius])
                    }
                }
            }
        }

        // Check the key goods.
        if production.count(foodType) < foodLow { scale(.food, modFoodLow) }
        var a = C.goods.rawValue - 1
        for type in production.types {
            let amount = production.count(type)
            let threshold = Double(type.lowProductionThreshold)
            if threshold > 0.0 {
                a += 1
                if a == values.count { values.append(1.0) }
                if Double(amount) < threshold {
                    let fraction = Double(amount) / threshold
                    let zeroValue = Double(type.zeroProductionFactor)
                    values[a] = (1.0 - fraction) * zeroValue + fraction
                }
            }
        }
        return values
    }

    /// The value of a colony on a tile: the product of its parts, or a
    /// negative NoValueType.
    public func colonyValue(_ tile: Tile) -> Int {
        let values = allColonyValues(tile)
        if values[0] < 0.0 { return Int(JavaMath.round(values[0])) }
        var v = 1.0
        for d in values { v *= d }
        return Int(JavaMath.round(v))
    }

    // MARK: Miscellaneous

    /// The most food any unit type available to this player eats.
    public var maximumFoodConsumption: Int {
        if maximumFoodConsumptionCache < 0, let spec = specification {
            var best: Int?
            for ut in spec.unitTypeList where ut.isAvailableTo([self]) {
                best = max(best ?? Int.min, spec.foodGoodsTypeList.reduce(0) { $0 + ut.consumption(of: $1) })
            }
            maximumFoodConsumptionCache = best ?? Int(Int32.min) // Java's MAX_DEFAULT
        }
        return maximumFoodConsumptionCache
    }
}

/// Java's Math.pow for the cases used here (finite positive bases).
func javaPow(_ x: Double, _ y: Double) -> Double {
    pow(x, y)
}

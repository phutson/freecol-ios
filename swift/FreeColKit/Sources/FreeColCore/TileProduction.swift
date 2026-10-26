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

import FreeColUtil

/// The goods produced and consumed by something in a turn
/// (common/model/ProductionInfo).
public struct ProductionInfo: CustomStringConvertible {

    public var maximumProduction: [AbstractGoods] = []
    public var production: [AbstractGoods] = []
    public var maximumConsumption: [AbstractGoods] = []
    public var consumption: [AbstractGoods] = []

    public init() {}

    /// How much more of each goods could be produced.
    public var productionDeficit: [AbstractGoods] {
        guard !maximumProduction.isEmpty else { return [] }
        return production.compactMap { ag in
            let max = maximumProduction.first { $0.type === ag.type }
            let amount = (max?.amount ?? 0) - ag.amount
            return amount <= 0 ? nil : AbstractGoods(ag.type, amount)
        }
    }

    /// How much more of each goods could be consumed (or less, where
    /// negative).
    public var consumptionDeficit: [AbstractGoods] {
        guard !maximumConsumption.isEmpty else { return [] }
        return consumption.compactMap { ag in
            let max = maximumConsumption.first { $0.type === ag.type }
            let amount = (max?.amount ?? 0) - ag.amount
            return amount == 0 ? nil : AbstractGoods(ag.type, amount)
        }
    }

    /// Whether production is at its maximum.  Java compares production
    /// with the maximum consumption here; that is kept.
    public var atMaximumProduction: Bool {
        if maximumProduction.isEmpty { return true }
        for ag in production {
            if let max = maximumConsumption.first(where: { $0.type === ag.type }),
               max.amount > ag.amount {
                return false
            }
        }
        return true
    }

    private func append(_ result: inout String, _ key: String, _ list: [AbstractGoods]) {
        guard !list.isEmpty else { return }
        result += key + ": "
        result += list.map { goods in
            var s = "\(goods)"
            if let type = goods.type, type.storedAs !== type {
                s += " [\(type.storedAs.id ?? "null")]"
            }
            return s
        }.joined(separator: ", ")
        result += "\n"
    }

    public var description: String {
        var result = ""
        append(&result, "Production", production)
        append(&result, " Consumption", consumption)
        append(&result, " Maximum Production", maximumProduction)
        append(&result, " Maximum Consumption", maximumConsumption)
        return result
    }
}

/// A unit type working with a production type
/// (common/model/production/WorkerAssignment).
public struct WorkerAssignment {
    public let unitType: UnitType?
    public let productionType: ProductionType?

    public init(_ unitType: UnitType?, _ productionType: ProductionType?) {
        self.unitType = unitType
        self.productionType = productionType
    }
}

/// The production of a tile, worked by a unit or as a colony center
/// (common/model/production/TileProductionCalculator).
///
/// The owner's modifiers come with Player; until then the owner is
/// always nil, as it is for a tile's potential production.
public struct TileProductionCalculator {

    public let owner: Player?
    /// The colony's production bonus from rebels (or penalty from
    /// tories).
    public let colonyProductionBonus: Int

    public init(owner: Player?, colonyProductionBonus: Int) {
        self.owner = owner
        self.colonyProductionBonus = colonyProductionBonus
    }

    /// The production from a tile.
    public func basicProductionInfo(_ tile: Tile, turn: Turn?, _ workerAssignment: WorkerAssignment,
                                    colonyCenterTile: Bool) -> ProductionInfo {
        var pi = ProductionInfo()
        // No production type means a tile type that produces nothing,
        // or a unit that cannot work it.
        guard let productionType = workerAssignment.productionType else { return pi }
        if colonyCenterTile {
            for output in productionType.outputs {
                guard let gt = output.type else { continue }
                let n = centerTileProduction(turn, tile, gt)
                if n > 0 { pi.production.append(AbstractGoods(gt, n)) }
            }
        } else {
            for gt in productionType.outputs.compactMap(\.type) {
                let n = unitProduction(turn, tile, workerAssignment, gt)
                if n > 0 { pi.production.append(AbstractGoods(gt, n)) }
            }
        }
        return pi
    }

    /// The goods a unit produces on a tile.
    public func unitProduction(_ turn: Turn?, _ tile: Tile, _ workerAssignment: WorkerAssignment?,
                               _ goodsType: GoodsType) -> Int {
        guard let workerAssignment, let productionType = workerAssignment.productionType,
              productionType.outputs.contains(where: { $0.type === goodsType }),
              let unitType = workerAssignment.unitType else { return 0 }
        let base = baseProduction(tile, productionType, goodsType, unitType)
        return max(0, Int(JavaMath.toInt(FeatureContainer.applyModifiers(
            Float(base), turn: turn, productionModifiers(turn, tile, goodsType, unitType)))))
    }

    private func centerTileProduction(_ turn: Turn?, _ tile: Tile, _ goodsType: GoodsType) -> Int {
        let production = tile.baseProduction(nil, goodsType, nil)
        return max(0, Int(JavaMath.toInt(FeatureContainer.applyModifiers(
            Float(production), turn: turn, centerTileProductionModifiers(turn, tile, goodsType)))))
    }

    private func baseProduction(_ tile: Tile, _ productionType: ProductionType,
                                _ goodsType: GoodsType, _ unitType: UnitType) -> Int {
        guard goodsType.isFarmed else { return 0 }
        return max(0, tile.baseProduction(productionType, goodsType, unitType))
    }

    /// The modifiers to a unit's production on a tile.
    public func productionModifiers(_ turn: Turn?, _ tile: Tile, _ goodsType: GoodsType,
                                    _ unitType: UnitType?) -> [Modifier] {
        guard let unitType, tile.canProduce(goodsType, unitType) else { return [] }
        return tile.productionModifiers(goodsType, unitType)
            + unitType.modifiers(goodsType.id, for: tile.type, turn: turn)
            + (owner?.modifiers(goodsType.id, for: unitType, turn: turn) ?? [])
            + ProductionUtils.rebelProductionModifiers(tile, colonyProductionBonus, goodsType, unitType)
    }

    /// The modifiers to a colony center tile's production.
    public func centerTileProductionModifiers(_ turn: Turn?, _ tile: Tile,
                                              _ goodsType: GoodsType) -> [Modifier] {
        guard tile.canProduce(goodsType, nil) else { return [] }
        // Java's old code also had the colony's and owner's modifiers
        // here, but they do not seem to affect center tiles.
        return tile.productionModifiers(goodsType, nil)
            + ProductionUtils.rebelProductionModifiers(tile, colonyProductionBonus, goodsType, nil)
    }
}

/// Production modifiers from a colony's rebels
/// (common/model/production/ProductionUtils).
public enum ProductionUtils {

    /// The rebel modifiers for a building's production.
    public static func rebelProductionModifiers(_ buildingType: BuildingType?,
                                                _ colonyProductionBonus: Int,
                                                _ goodsType: GoodsType,
                                                _ unitType: UnitType?) -> [Modifier] {
        guard colonyProductionBonus != 0 else { return [] }
        let rebelFactor = buildingType?.rebelFactor ?? 1
        let bonus = Int(JavaMath.toInt((Float(colonyProductionBonus) * rebelFactor).rounded(.down)))
        return [rebelModifier(Modifier.colonyProductionIndex, goodsType, bonus)]
    }

    /// The rebel modifiers for a tile's production.  Experts and
    /// multiplying resources double up the bonus, but not a penalty.
    public static func rebelProductionModifiers(_ tile: Tile, _ colonyProductionBonus: Int,
                                                _ goodsType: GoodsType,
                                                _ unitType: UnitType?) -> [Modifier] {
        guard colonyProductionBonus != 0 else { return [] }
        guard let unitType else {
            // Unattended
            return colonyProductionBonus < 0 ? []
                : [rebelModifier(Modifier.colonyTileProductionIndex, goodsType, colonyProductionBonus)]
        }
        var rebelFactor: Float = 1
        if let expert = unitType.expertProduction, expert === goodsType {
            rebelFactor *= 2
        }
        if let resource = tile.resource {
            let multiplicative = resource.productionModifiers(goodsType, unitType)
                .filter { $0.type == .multiplicative }
            rebelFactor = FeatureContainer.applyModifiers(rebelFactor, turn: tile.game?.turn,
                                                          multiplicative)
        }
        // Java multiplies in float, then floors the value widened to double.
        let scaled = Double(Float(colonyProductionBonus) * rebelFactor).rounded(.down)
        let bonus = Int(JavaMath.toInt(max(Double(colonyProductionBonus), scaled)))
        return [rebelModifier(Modifier.colonyTileProductionIndex, goodsType, bonus)]
    }

    private static func rebelModifier(_ index: Int, _ goodsType: GoodsType, _ bonus: Int) -> Modifier {
        Modifier(goodsType.id, Float(bonus), .additive,
                 source: goodsType.specification?.getType(Specification.SourceId.solModifier),
                 index: index)
    }
}

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
import FreeColXML

/// Something in a colony that consumes goods: a unit, a building or a
/// build queue (common/model/Consumer).  Consumers are served in order
/// of priority, highest first.
public protocol Consumer: AnyObject {
    /// The goods consumed per turn.
    var consumedGoods: [AbstractGoods] { get }
    /// The priority (Java's getPriority).
    var consumerPriority: Int { get }
    /// The modifiers to consumption with an id.
    func consumptionModifiers(_ id: String) -> [Modifier]
}

/// A queue of things for a colony to build, or of units to grow
/// (common/model/BuildQueue).
public final class BuildQueue<T: BuildableType>: Consumer, CustomStringConvertible {

    /// What happens when the first item is finished.
    public enum CompletionAction: JavaEnum {
        case remove, removeExceptLast, shuffle, addRandom

        public var javaName: String {
            switch self {
            case .remove: "REMOVE"
            case .removeExceptLast: "REMOVE_EXCEPT_LAST"
            case .shuffle: "SHUFFLE"
            case .addRandom: "ADD_RANDOM"
            }
        }
    }

    public private(set) var values: [T] = []
    public var completionAction: CompletionAction
    private let priority: Int
    private weak var colony: Colony?

    public init(_ colony: Colony, _ action: CompletionAction, _ priority: Int) {
        self.colony = colony
        completionAction = action
        self.priority = priority
    }

    public func clear() { values = [] }
    public func add(_ buildable: T) { values.append(buildable) }
    public func setValues(_ newValues: [T]) { values = newValues }
    public func remove(at index: Int) { values.remove(at: index) }
    public var count: Int { values.count }
    public var isEmpty: Bool { values.isEmpty }

    /// The item being built.
    public var currentlyBuilding: T? {
        values.first
    }

    /// Put an item first.  A building already queued moves to the
    /// front; nil clears the queue.
    public func setCurrentlyBuilding(_ buildable: T?) {
        guard let buildable else {
            clear()
            return
        }
        if buildable is BuildingType, let i = values.firstIndex(where: { $0 === buildable }) {
            values.remove(at: i)
        }
        values.insert(buildable, at: 0)
    }

    /// What building the first item would consume, given the goods
    /// available: all the required goods at once, or nothing.
    public func productionInfo(_ input: [AbstractGoods]) -> ProductionInfo {
        var result = ProductionInfo()
        guard let current = currentlyBuilding else { return result }
        let overflow = colony?.specification?.getBoolean(GameOptions.saveProductionOverflow) ?? false
        var consumption: [AbstractGoods] = []
        for ag in current.requiredGoods {
            guard let available = input.first(where: { $0.type === ag.type }),
                  ag.amount <= available.amount else { return result } // Build nothing
            let amount = (overflow || (ag.type?.isStorable ?? false)) ? ag.amount : available.amount
            consumption.append(AbstractGoods(ag.type, amount))
        }
        result.consumption = consumption
        return result
    }

    // MARK: Consumer

    public var consumedGoods: [AbstractGoods] {
        currentlyBuilding?.requiredGoods ?? []
    }

    public var consumerPriority: Int {
        priority
    }

    public func consumptionModifiers(_ id: String) -> [Modifier] {
        []
    }

    public var description: String {
        "[BuildQueue (\(colony?.name ?? "null"))" + values.map { " \($0.id ?? "null")" }.joined() + "]"
    }
}

/// When a colony exports and imports goods (common/model/ExportData).
public final class ExportData: FreeColObject {

    public static let tag = "exportData"

    private static let highLevelDefault = 90
    private static let lowLevelDefault = 10
    private static let exportLevelDefault = 50

    public var highLevel = ExportData.highLevelDefault
    public var lowLevel = ExportData.lowLevelDefault
    /// The import level, or -1 for the warehouse capacity.
    public var importLevel = -1
    public var exportLevel = ExportData.exportLevelDefault
    public var exported = false

    public init(_ goodsType: GoodsType, importLevel: Int) {
        super.init()
        id = goodsType.id
        self.importLevel = importLevel
    }

    public init(reading xr: FreeColXMLReader) throws {
        super.init()
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        ExportData.tag
    }

    public func effectiveImportLevel(_ capacity: Int) -> Int {
        importLevel >= 0 ? importLevel : capacity
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        exported = xr.attribute("exported", default: false)
        highLevel = xr.attribute("highLevel", default: ExportData.highLevelDefault)
        lowLevel = xr.attribute("lowLevel", default: ExportData.lowLevelDefault)
        importLevel = xr.attribute("importLevel", default: -1)
        exportLevel = xr.attribute("exportLevel", default: ExportData.exportLevelDefault)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("exported", exported)
        xw.writeAttribute("highLevel", highLevel)
        xw.writeAttribute("lowLevel", lowLevel)
        xw.writeAttribute("importLevel", importLevel)
        xw.writeAttribute("exportLevel", exportLevel)
    }
}

/// Goods produced in a colony, with goods stored as another type (such
/// as the food types, stored as food) kept as a tree under the type
/// they are stored as (common/model/ProductionMap).
public final class ProductionMap {

    /// A stored-as type with the goods stored as it
    /// (ProductionMap.ProductionTree).
    final class ProductionTree {
        var root: AbstractGoods
        var leafs: [AbstractGoods]

        init(_ root: AbstractGoods, _ leafs: [AbstractGoods]) {
            self.leafs = leafs.map { AbstractGoods(copying: $0) }
            self.root = AbstractGoods(root.type, root.amount + leafs.reduce(0) { $0 + $1.amount })
        }

        func add(_ goods: AbstractGoods) {
            precondition(goods.type?.storedAs === root.type,
                         "\(goods.type?.id ?? "null") is not stored as \(root.type?.id ?? "null")")
            if let leaf = leafs.first(where: { $0.type === goods.type }) {
                leaf.amount += goods.amount
            } else {
                leafs.append(AbstractGoods(copying: goods))
            }
            root.amount += goods.amount
        }

        @discardableResult
        func remove(_ goods: AbstractGoods) -> Int {
            let consumed = goods.amount
            if goods.type === root.type {
                root.amount -= consumed
                for leaf in leafs { leaf.amount = min(leaf.amount, root.amount) }
            } else if let leaf = leafs.first(where: { $0.type === goods.type }) {
                leaf.amount -= consumed
                root.amount -= consumed
            }
            return consumed
        }

        func get(_ type: GoodsType) -> AbstractGoods? {
            if root.type === type { return root }
            return leafs.first { $0.type === type }.map { AbstractGoods(type, $0.amount) }
        }
    }

    private enum Entry {
        case amount(Int)
        case tree(ProductionTree)
    }

    private var cache: [ObjectIdentifier: Entry] = [:]

    public init() {}

    /// The amount of a goods type produced.
    public func get(_ type: GoodsType) -> AbstractGoods {
        switch cache[ObjectIdentifier(type)] {
        case nil: return AbstractGoods(type, 0)
        case .amount(let n): return AbstractGoods(type, n)
        // Java returns null for a tree that does not hold the type,
        // which can not happen as trees are only stored for their types.
        case .tree(let tree): return tree.get(type)!
        }
    }

    public func add(_ goods: AbstractGoods) {
        guard let goodsType = goods.type else { return }
        let key = ObjectIdentifier(goodsType)
        switch cache[key] {
        case nil:
            let rootType = goodsType.storedAs
            if rootType === goodsType {
                cache[key] = .amount(goods.amount)
            } else {
                // A leaf of a production tree.
                let rootKey = ObjectIdentifier(rootType)
                let tree: ProductionTree
                if case .tree(let t)? = cache[rootKey] {
                    t.add(goods)
                    tree = t
                } else {
                    var amount = 0
                    if case .amount(let n)? = cache[rootKey] { amount = n }
                    tree = ProductionTree(AbstractGoods(rootType, amount), [goods])
                    cache[rootKey] = .tree(tree)
                }
                // The same entry for the goods type itself.
                cache[key] = .tree(tree)
            }
        case .amount(let n):
            cache[key] = .amount(n + goods.amount)
        case .tree(let tree):
            tree.add(goods)
        }
    }

    public func remove(_ goods: AbstractGoods) {
        guard let goodsType = goods.type else { return }
        if case .tree(let tree)? = cache[ObjectIdentifier(goodsType)] {
            tree.remove(goods)
        } else {
            add(AbstractGoods(goodsType, -goods.amount))
        }
    }

    public func add(_ goods: [AbstractGoods]) {
        goods.forEach { add($0) }
    }

    public func remove(_ goods: [AbstractGoods]) {
        goods.forEach { remove($0) }
    }
}

/// A colony's production and consumption, worked out when needed and
/// kept until something changes (common/model/ProductionCache).
///
/// The colony tiles produce first, then each consumer in order of
/// priority takes what it needs of what has been produced so far (and
/// what is in store), and adds what it produces.
public final class ProductionCache {

    private weak var colony: Colony?
    private var netProduction = TypeCountMap<GoodsType>()
    private var productionAndConsumption: [ObjectIdentifier: ProductionInfo] = [:]
    /// The goods types whose stored amounts affect the result.
    private var goodsUsed: Set<ObjectIdentifier> = []
    private var upToDate = false

    public init(_ colony: Colony) {
        self.colony = colony
    }

    private func update() {
        if upToDate { return }
        reallyUpdate()
        upToDate = true
    }

    private func reallyUpdate() {
        guard let colony, let spec = colony.specification else { return }
        productionAndConsumption = [:]
        netProduction = TypeCountMap()
        goodsUsed = []
        let production = ProductionMap()

        for colonyTile in colony.colonyTiles {
            let info = colonyTile.basicProductionInfo
            production.add(info.production)
            productionAndConsumption[ObjectIdentifier(colonyTile)] = info
            for goods in info.production {
                guard let type = goods.type else { continue }
                goodsUsed.insert(ObjectIdentifier(type))
                netProduction.increment(type.storedAs, by: goods.amount)
            }
        }

        // Bells for the units that use none, which unit consumption does
        // not handle.
        if let bells = spec.getGoodsType("model.goods.bells") {
            let free = spec.getInteger(GameOptions.unitsThatUseNoBells) ?? 0
            let amount = min(free, colony.unitCount)
            var bellsInfo = ProductionInfo()
            bellsInfo.production.append(AbstractGoods(bells, amount))
            productionAndConsumption[ObjectIdentifier(self)] = bellsInfo
            netProduction.increment(bells, by: amount)
        }

        for consumer in colony.consumers {
            let modifiers = consumer.consumptionModifiers(Modifier.consumeOnlySurplusProduction)
            var goods: [AbstractGoods] = []
            for g in consumer.consumedGoods {
                guard let type = g.type else { continue }
                goodsUsed.insert(ObjectIdentifier(type))
                let surplus = AbstractGoods(copying: production.get(type))
                if modifiers.isEmpty {
                    surplus.amount += colony.goodsCount(type)
                } else {
                    surplus.amount = Int(JavaMath.toInt(FeatureContainer.applyModifiers(
                        Float(surplus.amount), turn: nil, modifiers)))
                }
                goods.append(surplus)
            }
            var info: ProductionInfo?
            if let building = consumer as? Building {
                let outputs = building.outputs.compactMap(\.type).map { outputType -> AbstractGoods in
                    let newOutput = AbstractGoods(copying: production.get(outputType))
                    newOutput.amount += colony.goodsCount(outputType)
                    return newOutput
                }
                for o in outputs { if let t = o.type { goodsUsed.insert(ObjectIdentifier(t)) } }
                info = building.adjustedProductionInfo(goods, outputs)
            } else if let unit = consumer as? Unit {
                info = unit.productionInfo(goods)
            } else if let queue = consumer as? BuildQueue<BuildableType> {
                info = queue.productionInfo(goods)
            } else if let queue = consumer as? BuildQueue<UnitType> {
                info = queue.productionInfo(goods)
            }
            guard let info else { continue }
            production.add(info.production)
            production.remove(info.consumption)
            for g in info.production { if let t = g.type { netProduction.increment(t.storedAs, by: g.amount) } }
            for g in info.consumption { if let t = g.type { netProduction.increment(t.storedAs, by: -g.amount) } }
            productionAndConsumption[ObjectIdentifier(consumer)] = info
        }
    }

    public func invalidate() {
        upToDate = false
    }

    /// Invalidate if a goods type affects the result.
    public func invalidate(_ goodsType: GoodsType) {
        if goodsUsed.contains(ObjectIdentifier(goodsType)) { upToDate = false }
    }

    public func isProducing(_ goodsType: GoodsType) -> Bool {
        update()
        return productionAndConsumption.values.contains { $0.production.contains { $0.type === goodsType } }
    }

    public func isConsuming(_ goodsType: GoodsType) -> Bool {
        update()
        return productionAndConsumption.values.contains { $0.consumption.contains { $0.type === goodsType } }
    }

    public func netProduction(of type: GoodsType?) -> Int {
        update()
        return netProduction.count(type)
    }

    /// The production of a work location, unit or queue.
    public func productionInfo(of object: AnyObject) -> ProductionInfo? {
        update()
        return productionAndConsumption[ObjectIdentifier(object)]
    }

    /// The net production of every goods type.
    public var productionMap: TypeCountMap<GoodsType> {
        update()
        var result = TypeCountMap<GoodsType>()
        result.putAll(netProduction)
        return result
    }
}

/// The production of a building with its workers, given the inputs and
/// room for outputs (common/model/production/BuildingProductionCalculator).
extension BuildingType {
    /// What a unit type (or none) could make of a goods type here, with
    /// plenty of input and space and no colony or owner bonuses.
    public func potentialProduction(_ goodsType: GoodsType, _ unitType: UnitType?) -> Int {
        let bpc = BuildingProductionCalculator(owner: nil, colonyFeatureContainer: FeatureContainer(),
                                               colonyProductionBonus: 0)
        let productionType = ProductionType.bestProductionType(
            goodsType, in: availableProductionTypes(unattended: unitType == nil))
        let moreThanEnoughInputGoods = 1000
        let moreThanEnoughWarehouseCapacity = 10000
        let inputGoods = (productionType?.inputs ?? []).map { AbstractGoods($0.type, moreThanEnoughInputGoods) }
        // Specification types have no game, so this is always turn 1.
        let pi = bpc.adjustedProductionInfo(self, turn: Turn(1), [WorkerAssignment(unitType, productionType)],
                                            inputGoods, [], warehouseCapacity: moreThanEnoughWarehouseCapacity)
        return pi.production.first { $0.type === goodsType }?.amount ?? 0
    }
}

public struct BuildingProductionCalculator {

    private static let epsilon = 0.0001

    public let owner: Player?
    public let colonyFeatureContainer: FeatureContainer
    public let colonyProductionBonus: Int

    public init(owner: Player?, colonyFeatureContainer: FeatureContainer, colonyProductionBonus: Int) {
        self.owner = owner
        self.colonyFeatureContainer = colonyFeatureContainer
        self.colonyProductionBonus = colonyProductionBonus
    }

    /// The production and consumption, scaled down for short inputs
    /// and (for buildings that avoid it) full warehouses.
    public func adjustedProductionInfo(_ buildingType: BuildingType, turn: Turn?,
                                       _ workerAssignments: [WorkerAssignment],
                                       _ inputs: [AbstractGoods], _ outputs: [AbstractGoods],
                                       warehouseCapacity: Int) -> ProductionInfo {
        var result = ProductionInfo()
        let buildingOutputs = goods(buildingType, workerAssignments, \.outputs)
        if buildingOutputs.isEmpty { return result }
        let buildingInputs = goods(buildingType, workerAssignments, \.inputs)
        let spec = buildingType.specification
        let avoidOverflow = buildingType.hasAbility(Ability.avoidExcessProduction)
        // The actual multiplier between the nominal goods and what is
        // consumed and produced, and the most it could be but for
        // limits such as short inputs.
        var maximumRatio = 0.0, minimumRatio = Double.greatestFiniteMagnitude

        if buildingType.hasAbility(Ability.autoProduction) {
            // Breeding is special.
            for output in buildingOutputs where output.isPositive {
                guard let goodsType = output.type else { continue }
                let available = outputs.first { $0.type === goodsType }?.amount ?? 0
                if available >= warehouseCapacity {
                    minimumRatio = 0
                    maximumRatio = 0
                } else {
                    let divisor = Int(JavaMath.toInt(buildingType.apply(0, turn: turn, Modifier.breedingDivisor)))
                    let factor = Int(JavaMath.toInt(buildingType.apply(0, turn: turn, Modifier.breedingFactor)))
                    // Integer division, as Java's.
                    let production = (available < goodsType.breedingNumber || divisor <= 0) ? 0
                        : ((available - 1) / divisor + 1) * factor
                    let newRatio = Double(production) / Double(output.amount)
                    minimumRatio = min(minimumRatio, newRatio)
                    maximumRatio = max(maximumRatio, newRatio)
                }
            }
        } else {
            for output in buildingOutputs {
                guard let goodsType = output.type else { continue }
                let production = Float(determineProduction(buildingType, workerAssignments, turn, goodsType))
                // Java divides as floats here.
                let newRatio = Double(production / Float(output.amount))
                minimumRatio = min(minimumRatio, newRatio)
                maximumRatio = max(maximumRatio, newRatio)
            }
        }

        // Reduce the minimum ratio for any input in short supply.
        for input in buildingInputs {
            let required = Int64(JavaMath.toLong((Double(input.amount) * minimumRatio).rounded(.down)))
            var available = Int64(AbstractGoods.count(of: input.type, in: inputs))
            if buildingType.hasAbility(Ability.autoProduction) { available = max(0, available) }
            // Experts in factories may produce some goods without inputs.
            if available < required
                && buildingType.hasAbility(Ability.expertsUseConnections)
                && (spec?.getBoolean(GameOptions.expertsHaveConnections) ?? false) {
                let expert = expertUnitType(buildingType)
                let experts = workerAssignments.filter { $0.unitType === expert }.count
                let minimumGoodsInput = Int64(buildingType.expertConnectionProduction * experts)
                if minimumGoodsInput > available { available = minimumGoodsInput }
            }
            if available < required {
                minimumRatio *= Double(available) / Double(required)
            }
        }

        // Clamp production at the warehouse capacity where the building
        // avoids excess production.
        if avoidOverflow {
            for output in buildingOutputs {
                var production = Double(output.amount) * minimumRatio
                if production <= 0 { continue }
                let headroom = Double(warehouseCapacity)
                    - Double(AbstractGoods.count(of: output.type, in: outputs))
                if production > headroom {
                    minimumRatio = min(minimumRatio, headroom / Double(output.amount))
                }
                production = Double(output.amount) * maximumRatio
                if production > headroom {
                    maximumRatio = min(maximumRatio, headroom / Double(output.amount))
                }
            }
        }

        for input in buildingInputs {
            let consumption = Int(JavaMath.toInt((Double(input.amount) * minimumRatio
                + BuildingProductionCalculator.epsilon).rounded(.down)))
            let maximumConsumption = Int(JavaMath.toInt((Double(input.amount) * maximumRatio).rounded(.down)))
            result.consumption.append(AbstractGoods(input.type, consumption))
            if consumption < maximumConsumption {
                result.maximumConsumption.append(AbstractGoods(input.type, maximumConsumption))
            }
        }
        for output in buildingOutputs {
            // A little extra to counter rounding errors.
            let production = Int(JavaMath.toInt((Double(output.amount) * minimumRatio
                + BuildingProductionCalculator.epsilon).rounded(.down)))
            let maximumProduction = Int(JavaMath.toInt((Double(output.amount) * maximumRatio).rounded(.down)))
            result.production.append(AbstractGoods(output.type, production))
            if production < maximumProduction {
                result.maximumProduction.append(AbstractGoods(output.type, maximumProduction))
            }
        }
        return result
    }

    /// The expert for what a building produces when worked.
    public func expertUnitType(_ buildingType: BuildingType) -> UnitType? {
        guard let spec = buildingType.specification,
              let pt = ProductionType.bestProductionType(nil, in: buildingType.availableProductionTypes(unattended: false))
        else { return nil }
        return pt.outputs.lazy.compactMap { $0.type.flatMap(spec.expert(producing:)) }.first
    }

    /// The unattended and worked inputs or outputs, totalled by type in
    /// Java's HashMap order.
    private func goods(_ buildingType: BuildingType, _ workerAssignments: [WorkerAssignment],
                       _ part: KeyPath<ProductionType, [AbstractGoods]>) -> [AbstractGoods] {
        let all = buildingType.availableProductionTypes(unattended: true).flatMap { $0[keyPath: part] }
            + workerAssignments.compactMap(\.productionType).flatMap { $0[keyPath: part] }
        var amounts = JavaHashMap<GoodsType, Int>(javaHash: { $0.javaHashCode })
        for ag in all {
            guard let type = ag.type else { continue }
            amounts.put(type, (amounts[type] ?? 0) + ag.amount)
        }
        return amounts.entries.map { AbstractGoods($0.key, $0.value) }
    }

    private func determineProduction(_ buildingType: BuildingType, _ workerAssignments: [WorkerAssignment],
                                     _ turn: Turn?, _ goodsType: GoodsType) -> Int {
        var production = Float(workerAssignments.reduce(0) {
            $0 + unitProduction(turn, buildingType, $1, goodsType)
        })
        // Unattended production always applies for buildings.
        production += Float(buildingType.baseProduction(nil, goodsType, nil))
        production = FeatureContainer.applyModifiers(production, turn,
                                                     productionModifiers(turn, buildingType, goodsType, nil))
        return Int(JavaMath.toInt(Double(production).rounded(.down)))
    }

    private func unitProduction(_ turn: Turn?, _ buildingType: BuildingType,
                                _ workerAssignment: WorkerAssignment, _ goodsType: GoodsType) -> Int {
        guard let pt = workerAssignment.productionType,
              pt.outputs.contains(where: { $0.type === goodsType }) else { return 0 }
        let base = buildingType.baseProduction(pt, goodsType, workerAssignment.unitType)
        return max(0, Int(JavaMath.toInt(FeatureContainer.applyModifiers(
            Float(base), turn: turn,
            productionModifiers(turn, buildingType, goodsType, workerAssignment.unitType)))))
    }

    private func productionModifiers(_ turn: Turn?, _ buildingType: BuildingType, _ goodsType: GoodsType,
                                     _ unitType: UnitType?) -> [Modifier] {
        let id = goodsType.id
        if let unitType {
            // With a unit, the unit-specific bonuses apply.
            return buildingType.modifiers(id, for: unitType, turn: turn)
                + ProductionUtils.rebelProductionModifiers(buildingType, colonyProductionBonus, goodsType, unitType)
                + buildingType.competenceModifiers(id, unitType, turn: turn)
                + (owner?.modifiers(id, for: unitType, turn: turn) ?? [])
        }
        // Without one, only the building's bonuses.
        return colonyFeatureContainer.modifiers(id, for: buildingType, turn: turn)
            + (owner?.modifiers(id, for: buildingType, turn: turn) ?? [])
    }
}

extension FeatureContainer {
    /// Apply modifiers in order (an unlabelled turn argument, for the
    /// calculators ported from Java).
    static func applyModifiers(_ number: Float, _ turn: Turn?, _ modifiers: [Modifier]) -> Float {
        applyModifiers(number, turn: turn, modifiers)
    }
}

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

/// Somewhere in a colony units work: a building or a colony tile
/// (common/model/WorkLocation).
///
/// The colony holds its work locations, which hold the units working
/// there; the reference back to the colony is weak.
///
/// evaluateFor and the labels are in Valuation.swift and Labels.swift.
/// Not yet ported: copyIn.
open class WorkLocation: UnitLocation, Ownable {

    /// A suggested change of worker (WorkLocation.Suggestion).
    public struct Suggestion {
        public weak var workLocation: WorkLocation?
        public let oldType: UnitType?
        public let newType: UnitType?
        public let goodsType: GoodsType?
        public let amount: Int

        /// More first, then by goods type, then by unit type (Java's
        /// descendingAmountComparator), as -1, 0 or 1.
        public static func compareDescendingAmount(_ a: Suggestion, _ b: Suggestion) -> Int {
            if a.amount != b.amount { return a.amount > b.amount ? -1 : 1 }
            let c = GoodsType.compare(a.goodsType, b.goodsType)
            if c != 0 { return c }
            return FreeColObject.compareIds(a.newType, b.newType)
        }
    }

    /// The colony this work location is in (read as colony).
    private weak var colonyHere: Colony?
    public private(set) var productionType: ProductionType?

    /// A work location that is about to be read.
    public override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// A new work location in a colony.
    public init(game: Game, colony: Colony) {
        super.init(game: game)
        colonyHere = colony
    }

    public func setColony(_ colony: Colony?) {
        colonyHere = colony
    }

    /// Change the production type, telling the colony.
    public final func setProductionType(_ newProductionType: ProductionType?) {
        if !Self.sameProductionType(newProductionType, productionType) {
            productionType = newProductionType
            colony?.invalidateCache()
        }
    }

    /// Java's Utils.equals for production types.
    static func sameProductionType(_ a: ProductionType?, _ b: ProductionType?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): a.isEqual(to: b)
        default: false
        }
    }

    /// The work type of the first unit here.
    public var currentWorkType: GoodsType? {
        guard let unit = firstUnit, unit.type != nil else { return nil }
        return unit.workType
    }

    /// Choose the best production type for the units here.
    public func updateProductionType() {
        setProductionType(bestProductionType(unattended: isEmpty, currentWorkType))
    }

    public func bestProductionType(unattended: Bool, _ workType: GoodsType?) -> ProductionType? {
        ProductionType.bestProductionType(workType, in: availableProductionTypes(unattended: unattended))
    }

    /// The best occupation here for a unit, trying the colony's work
    /// type choices in turn.
    /// Put a unit to its best work here.
    @discardableResult
    public func setWorkFor(_ unit: Unit) -> Bool {
        occupation(for: unit, userMode: false)?.install(unit) ?? false
    }

    public func occupation(for unit: Unit, userMode: Bool) -> Occupation? {
        guard let colony else { return nil }
        let best = Occupation()
        var bestAmount = 0
        for types in colony.workTypeChoices(unit, userMode: userMode) {
            bestAmount = best.improve(unit, self, bestAmount, types)
            if best.workType != nil { break }
        }
        return best.workType == nil ? nil : best
    }

    /// The best occupation here for a unit type (or the owner's default
    /// unit type).
    public func occupation(for unitType: UnitType?) -> Occupation? {
        guard let spec = specification,
              let unitType = unitType ?? spec.defaultUnitType(owner?.nationType) else { return nil }
        let best = Occupation()
        _ = best.improve(unitType, self, 0, spec.goodsTypeList)
        return best.workType == nil ? nil : best
    }

    public func work(for unit: Unit) -> GoodsType? {
        occupation(for: unit, userMode: true)?.workType
    }

    @discardableResult
    public func setWork(for unit: Unit) -> Bool {
        occupation(for: unit, userMode: false)?.install(unit) ?? false
    }

    private func suggestion(_ unit: Unit?, _ productionType: ProductionType?,
                            _ goodsType: GoodsType?) -> Suggestion? {
        guard let productionType, let goodsType,
              (unit != nil && contains(unit!)) || !isFull,
              let spec = specification, let owner, let colony else { return nil }
        let expert = spec.expert(producing: goodsType)
        guard let better = expert ?? spec.defaultUnitType(owner.nationType) else { return nil }
        if let unit, better === unit.type { return nil }
        var delta = potentialProduction(goodsType, better)
        if let unit { delta -= potentialProduction(goodsType, unit.type) }
        let inputs = productionType.inputs.compactMap(\.type).map { colony.netProduction(of: $0) }
        delta = min(delta, inputs.min() ?? Int(Int32.max))
        if delta <= 0 { return nil }
        if owner.playerType == .independent
            && ((goodsType.isLibertyType && colony.sonsOfLiberty >= 100) || goodsType.isImmigrationType) {
            return nil
        }
        guard goodSuggestionCheck(better, unit, goodsType) else { return nil }
        return Suggestion(workLocation: self, oldType: unit?.type, newType: better,
                          goodsType: goodsType, amount: delta)
    }

    /// Whether a suggestion is worth making; buildings and colony tiles
    /// say.
    open func goodSuggestionCheck(_ unitType: UnitType, _ unit: Unit?, _ goodsType: GoodsType) -> Bool {
        false
    }

    /// Suggested changes of worker: for each unit here, and (keyed by
    /// nil) for a new unit.
    public var suggestions: [(unit: Unit?, suggestion: Suggestion)] {
        var result: [(unit: Unit?, suggestion: Suggestion)] = []
        if !canBeWorked || canTeach { return result }
        let occ = occupation(for: nil as UnitType?)
        for u in unitList where u.teacher == nil {
            let work = u.workType ?? occ?.workType
            if let sug = suggestion(u, productionType, work) { result.append((u, sug)) }
        }
        if let occ, let work = occ.workType, !isFull,
           let sug = suggestion(nil, occ.productionType, work) {
            result.append((nil, sug))
        }
        return result
    }

    public var inputs: [AbstractGoods] {
        productionType?.inputs ?? []
    }

    public var outputs: [AbstractGoods] {
        productionType?.outputs ?? []
    }

    public func produces(_ goodsType: GoodsType?) -> Bool {
        outputs.contains { $0.type === goodsType }
    }

    public var hasInputs: Bool {
        !inputs.isEmpty
    }

    public var hasOutputs: Bool {
        !(productionType?.outputs.isEmpty ?? true)
    }

    public var canBeWorked: Bool {
        noWorkReason == .none
    }

    public var canTeach: Bool {
        hasAbility(Ability.teach)
    }

    public var productionInfo: ProductionInfo? {
        colony?.productionInfo(of: self)
    }

    public var production: [AbstractGoods] {
        productionInfo?.production ?? []
    }

    public func totalProduction(of goodsType: GoodsType) -> Int {
        AbstractGoods.count(of: goodsType, in: production)
    }

    public func maximumProduction(of goodsType: GoodsType) -> Int {
        guard let info = productionInfo else { return 0 }
        if let ag = info.maximumProduction.first(where: { $0.type === goodsType }) { return ag.amount }
        return totalProduction(of: goodsType)
    }

    /// The expert for what this work location produces when worked.
    public var expertUnitType: UnitType? {
        guard let spec = specification,
              let pt = bestProductionType(unattended: false, nil) else { return nil }
        return pt.outputs.lazy.compactMap { $0.type.flatMap(spec.expert(producing:)) }.first
    }

    /// The production of goods by the owner's default unit type here.
    public func genericPotential(_ goodsType: GoodsType) -> Int {
        potentialProduction(goodsType, specification?.defaultUnitType(owner?.nationType))
    }

    /// What a unit here produces of goods, if that is its work.
    public func unitProduction(_ unit: Unit?, _ goodsType: GoodsType) -> Int {
        guard let unit, unit.workType === goodsType else { return 0 }
        let base = baseProduction(productionType, goodsType, unit.type)
        return max(0, Int(JavaMath.toInt(FeatureContainer.applyModifiers(
            Float(base), turn: game?.turn, productionModifiers(goodsType, unit.type)))))
    }

    /// What a unit would produce of goods here.
    public func production(of unit: Unit, _ goodsType: GoodsType) -> Int {
        produces(goodsType) ? max(0, potentialProduction(goodsType, unit.type)) : 0
    }

    /// What a unit would make of a goods type here, if it were here
    /// (getProductionOf).
    public func productionOf(_ unit: Unit, _ goodsType: GoodsType) -> Int {
        produces(goodsType) ? max(0, potentialProduction(goodsType, unit.type)) : 0
    }

    /// What a unit type (or nobody) could produce of goods here.
    public func potentialProduction(_ goodsType: GoodsType, _ unitType: UnitType?) -> Int {
        if !canProduce(goodsType, unitType) { return 0 }
        if unitType != nil {
            switch noWorkReason {
            case .none, .alreadyPresent, .claimRequired:
                break
            case .capacityExceeded where unitCapacity > 0:
                break // Could work after a reorganization
            default:
                return 0
            }
        }
        let amount = baseProduction(nil, goodsType, unitType)
        let modified = Int(JavaMath.toInt(FeatureContainer.applyModifiers(
            Float(amount), turn: game?.turn, productionModifiers(goodsType, unitType))))
        return max(0, modified)
    }

    public func productionDeficit(_ goodsType: GoodsType) -> AbstractGoods? {
        productionInfo?.productionDeficit.first { $0.type === goodsType }
    }

    // MARK: Location

    public final override var tile: Tile? {
        colony?.tile
    }

    /// Add a unit, which then works here.  It is an error to add what
    /// can not be added.
    @discardableResult
    open override func add(_ locatable: any Locatable) -> Bool {
        let reason = noAddReason(locatable)
        switch reason {
        case .none: break
        case .alreadyPresent: return true
        default: preconditionFailure("Can not add \(locatable) to \(self) because \(reason)")
        }
        let unit = locatable as! Unit
        guard super.add(unit) else { return false }
        unit.setState(.inColony)
        unit.movesLeft = 0
        setWork(for: unit)
        colony?.invalidateCache()
        return true
    }

    @discardableResult
    open override func remove(_ locatable: any Locatable) -> Bool {
        guard let unit = locatable as? Unit else { preconditionFailure("Not a unit: \(locatable)") }
        if !contains(unit) { return true }
        guard super.remove(unit) else { return false }
        unit.setState(.active)
        unit.movesLeft = 0
        if isEmpty { updateProductionType() }
        colony?.invalidateCache()
        return true
    }

    public final override var settlement: Settlement? {
        colonyHere
    }

    public final override var rank: Int {
        LocationRank.of(tile)
    }

    /// Only people who are not damaged can work.
    open override func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        if let unit = locatable as? Unit, unit.isDamaged { return .workerDamaged }
        guard let unit = locatable as? Unit, unit.isPerson else { return .wrongType }
        return super.noAddReason(unit)
    }

    // MARK: For subclasses (abstract in Java)

    open var isAvailable: Bool { fatalError("abstract") }
    open var isCurrent: Bool { fatalError("abstract") }
    open var noWorkReason: NoAddReason { fatalError("abstract") }
    open var workTile: Tile? { fatalError("abstract") }
    open var level: Int { fatalError("abstract") }
    open var canAutoProduce: Bool { fatalError("abstract") }
    open func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool { fatalError("abstract") }
    open func baseProduction(_ productionType: ProductionType?, _ goodsType: GoodsType?,
                             _ unitType: UnitType?) -> Int { fatalError("abstract") }
    open func productionModifiers(_ goodsType: GoodsType?, _ unitType: UnitType?) -> [Modifier] {
        fatalError("abstract")
    }
    open func availableProductionTypes(unattended: Bool) -> [ProductionType] { fatalError("abstract") }
    open var competenceFactor: Float { fatalError("abstract") }
    open var rebelFactor: Float { fatalError("abstract") }

    // MARK: Ownable

    public var owner: Player? {
        colony?.owner
    }

    // MARK: Reading XML

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        colonyHere = try xr.findFreeColGameObject(game!, "colony", Colony.self, required: true)
    }

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("colony", colonyHere)
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        productionType?.toXML(xw)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == ProductionType.tag {
            productionType = try ProductionType(xr, specification: specification)
        } else {
            try super.readChild(xr)
        }
    }
}

/// A unit's place in a colony: where it works, at what, and how
/// (common/model/Occupation).
public final class Occupation: CustomStringConvertible {

    public weak var workLocation: WorkLocation?
    public var productionType: ProductionType?
    public var workType: GoodsType?

    public init(_ workLocation: WorkLocation? = nil, _ productionType: ProductionType? = nil,
                _ workType: GoodsType? = nil) {
        self.workLocation = workLocation
        self.productionType = productionType
        self.workType = workType
    }

    /// Put a unit to work here.
    @discardableResult
    public func install(_ unit: Unit) -> Bool {
        guard let workLocation, unit.setLocation(workLocation) else { return false }
        if !WorkLocation.sameProductionType(productionType, workLocation.productionType) {
            workLocation.setProductionType(productionType)
        }
        if workType !== unit.workType { unit.changeWorkType(workType) }
        return true
    }

    private func improve(_ unitType: UnitType?, _ wl: WorkLocation, _ bestAmount: Int,
                         _ workTypes: [GoodsType], alone: Bool) -> Int {
        guard let colony = wl.colony else { return bestAmount }
        var bestAmount = bestAmount
        let productionTypes = alone ? wl.availableProductionTypes(unattended: false)
            : [wl.productionType].compactMap { $0 }
        for pt in productionTypes {
            for gt in workTypes where pt.output(of: gt) != nil {
                let minInput = pt.inputs.compactMap(\.type)
                    .map { max(colony.netProduction(of: $0), colony.goodsCount($0)) }
                    .min() ?? Int(Int32.max)
                let potential = wl.potentialProduction(gt, unitType)
                let amount = min(minInput, potential)
                if bestAmount < amount {
                    bestAmount = amount
                    workLocation = wl
                    productionType = pt
                    workType = gt
                }
            }
        }
        return bestAmount
    }

    /// Improve on the best occupation found so far with work for a unit
    /// at a work location.
    ///
    /// - Returns: The new best amount.
    public func improve(_ unit: Unit, _ wl: WorkLocation, _ bestAmount: Int,
                        _ workTypes: [GoodsType]) -> Int {
        // Can the unit work there?
        let present = unit.location === wl
        if !present && !wl.canAdd(unit) { return bestAmount }
        // The unit can choose the production type if it will be alone,
        // or none is set yet.
        let alone = wl.productionType == nil || wl.isEmpty || (present && wl.unitCount == 1)
        return improve(unit.type, wl, bestAmount, workTypes, alone: alone)
    }

    /// Improve on the best occupation found so far with work for a unit
    /// type at a work location.
    public func improve(_ unitType: UnitType, _ wl: WorkLocation, _ bestAmount: Int,
                        _ workTypes: [GoodsType]) -> Int {
        improve(unitType, wl, bestAmount, workTypes, alone: wl.isEmpty)
    }

    public var description: String {
        "[Occupation \(workLocation.map { "\($0)" } ?? "null")"
            + (workType.map { " \($0.suffix ?? "null")" } ?? "") + "]"
    }
}

/// A building in a colony (common/model/Building).
///
/// Not yet ported: copyIn.
public final class Building: WorkLocation, GameObjectReadable, Consumer {

    public static let tag = "building"

    public private(set) var type: BuildingType?

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// A new building, producing what its type does by default.
    public init(game: Game, colony: Colony, type: BuildingType) {
        self.type = type
        super.init(game: game, colony: colony)
        updateProductionType()
    }

    public override var xmlTagName: String {
        Building.tag
    }

    /// Change the type, moving the type's features in the colony.
    ///
    /// - Returns: The units that no longer fit.
    private func setType(_ newBuildingType: BuildingType?) -> [Unit] {
        if let type { colony?.removeFeatures(of: type) }
        var eject: [Unit] = []
        if let newBuildingType {
            type = newBuildingType
            updateProductionType()
            colony?.addFeatures(of: newBuildingType)
            eject += unitList.filter { !canAddType($0.type) }
        }
        var extra = unitCount - unitCapacity - eject.count
        for unit in unitList {
            if extra <= 0 { break }
            if !eject.contains(where: { $0 === unit }) {
                eject.append(unit)
                extra -= 1
            }
        }
        return eject
    }

    public var canBuildNext: Bool {
        colony?.canBuild(type?.upgradesTo) ?? false
    }

    public var canBeDamaged: Bool {
        guard let type, let colony else { return false }
        return !type.isAutomaticBuild && !colony.isAutomaticBuild(type)
    }

    /// Damage the building to its previous level.
    ///
    /// - Returns: The units that no longer fit, or nil if it can not be
    ///   damaged.
    public func downgrade() -> [Unit]? {
        guard canBeDamaged else { return nil }
        let ret = setType(type?.upgradesFrom)
        colony?.invalidateCache()
        return ret
    }

    /// Upgrade the building to its next level.
    ///
    /// - Returns: The units that no longer fit, or nil if it can not be
    ///   upgraded.
    public func upgrade() -> [Unit]? {
        guard canBuildNext else { return nil }
        let ret = setType(type?.upgradesTo)
        colony?.invalidateCache()
        return ret
    }

    public func canAddType(_ unitType: UnitType?) -> Bool {
        guard let unitType, let type else { return false }
        return canBeWorked && type.canAdd(unitType)
    }

    /// The production with the inputs and outputs available.
    public func adjustedProductionInfo(_ inputs: [AbstractGoods], _ outputs: [AbstractGoods]) -> ProductionInfo {
        guard let type, let colony else { return ProductionInfo() }
        let pc = BuildingProductionCalculator(owner: owner, colonyFeatureContainer: colony.featureContainer!,
                                              colonyProductionBonus: colony.productionBonus)
        let assignments = unitList.map { WorkerAssignment($0.type, productionType) }
        return pc.adjustedProductionInfo(type, turn: game?.turn, assignments, inputs, outputs,
                                         warehouseCapacity: colony.warehouseCapacity)
    }

    // MARK: Location

    public override func up() -> any Location {
        colony!
    }

    public override var shortDescription: String {
        "\(colony?.name ?? "null")-\(type?.suffix ?? "null")"
    }

    public override func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        var reason = super.noAddReason(locatable)
        if reason == .none, let unitType = (locatable as? Unit)?.type, let type {
            reason = type.noAddReason(unitType)
            if reason == .none { reason = noWorkReason }
        }
        return reason
    }

    public override var unitCapacity: Int {
        type?.workPlaces ?? 0
    }

    // MARK: WorkLocation

    public override func goodSuggestionCheck(_ better: UnitType, _ unit: Unit?, _ goodsType: GoodsType) -> Bool {
        guard canAddType(better), let colony else { return false }
        if level > 1 || unit != nil { return true }
        if colony.totalProduction(of: goodsType) == 0, let bt = colony.currentlyBuilding,
           bt.requiredGoods.contains(where: { $0.type === goodsType }) {
            return true
        }
        return false
    }

    public override var isAvailable: Bool { true }
    public override var isCurrent: Bool { true }
    public override var noWorkReason: NoAddReason { .none }
    public override var workTile: Tile? { nil }
    public override var level: Int { type?.level ?? 0 }

    public override var canAutoProduce: Bool {
        hasAbility(Ability.autoProduction)
    }

    public override func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        type?.canProduce(goodsType, unitType) ?? false
    }

    public override func baseProduction(_ productionType: ProductionType?, _ goodsType: GoodsType?,
                                        _ unitType: UnitType?) -> Int {
        type?.baseProduction(productionType, goodsType, unitType) ?? 0
    }

    public override func productionModifiers(_ goodsType: GoodsType?, _ unitType: UnitType?) -> [Modifier] {
        guard let colony else { return [] }
        let id = goodsType?.id
        let turn = game?.turn
        if let unitType {
            return modifiers(id, for: unitType, turn: turn)
                + (goodsType.map { colony.productionModifiers($0, unitType, self) } ?? [])
                + (type?.competenceModifiers(id, unitType, turn: turn) ?? [])
                + (owner?.modifiers(id, for: unitType, turn: turn) ?? [])
        }
        return colony.modifiers(id, for: type, turn: turn) + (owner?.modifiers(id, for: type, turn: turn) ?? [])
    }

    public override func availableProductionTypes(unattended: Bool) -> [ProductionType] {
        type?.availableProductionTypes(unattended: unattended) ?? []
    }

    public override var competenceFactor: Float { type?.competenceFactor ?? 1 }
    public override var rebelFactor: Float { type?.rebelFactor ?? 1 }

    // MARK: Consumer

    public var consumedGoods: [AbstractGoods] {
        inputs
    }

    public var consumerPriority: Int {
        type?.priority ?? 0
    }

    public func consumptionModifiers(_ id: String) -> [Modifier] {
        modifiers(id)
    }

    // MARK: Features

    /// A building's abilities and modifiers are its type's.
    public override func abilities(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                                   turn: Turn? = nil) -> [Ability] {
        type?.abilities(id, for: target, turn: turn) ?? []
    }

    public override func modifiers(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                                   turn: Turn? = nil) -> [Modifier] {
        type?.modifiers(id, for: target, turn: turn) ?? []
    }

    public override var scopeType: FreeColSpecObjectType? {
        type
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        type = try specification.flatMap { try xr.getType($0, "buildingType", BuildingType.self) }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("buildingType", type)
    }

    public override var description: String {
        "[\(id ?? "null") \(type.map { JavaString.lastPart($0.id ?? "", ".") } ?? "")"
            + "/\(colony?.name ?? "NO-COLONY")]"
    }
}

/// A tile a colony works (common/model/ColonyTile).  The colony's own
/// tile is its center tile, which produces unattended.
///
/// Not yet ported: labels, evaluateFor and copyIn.
public final class ColonyTile: WorkLocation, GameObjectReadable {

    public static let tag = "colonyTile"

    /// The number of units that can work a tile.
    public static let tileUnitCapacity = 1

    /// The tile worked.  The map holds it.
    public private(set) weak var workTileHere: Tile?

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// A new colony tile, producing what the tile does by default.
    public init(game: Game, colony: Colony, workTile: Tile) {
        workTileHere = workTile
        super.init(game: game, colony: colony)
        updateProductionType()
    }

    public override var xmlTagName: String {
        ColonyTile.tag
    }

    public var isColonyCenterTile: Bool {
        workTileHere === tile
    }

    public func setWorkTile(_ tile: Tile?) {
        workTileHere = tile
    }

    public var occupyingUnit: Unit? {
        workTileHere?.occupyingUnit
    }

    public var isOccupied: Bool {
        workTileHere?.isOccupied ?? false
    }

    /// The tile's production by its worker, or unattended for the
    /// center tile.
    public var basicProductionInfo: ProductionInfo {
        guard let workTileHere, let colony else { return ProductionInfo() }
        let tpc = TileProductionCalculator(owner: owner, colonyProductionBonus: colony.productionBonus)
        return tpc.basicProductionInfo(workTileHere, turn: game?.turn,
                                       WorkerAssignment(unitList.first?.type, productionType),
                                       colonyCenterTile: isColonyCenterTile)
    }

    /// How much an improvement would help: the change in food for the
    /// center tile (or a loss of goods the colony needs), otherwise the
    /// change in the worker's production.
    public func improvedBy(_ ti: TileImprovementType) -> Int {
        guard let tile = workTileHere, let colony, tile.owningSettlement === colony,
              !tile.hasTileImprovement(ti), let oldType = tile.type,
              ti.isTileTypeAllowed(oldType), let productionType,
              let spec = specification else { return 0 }
        let resource = tile.resource
        let newType = ti.change(oldType)
        if productionType.unattended {
            guard let newType else {
                return spec.foodGoodsTypeList.reduce(0) { $0 + ti.bonus($1) }
            }
            let newProd = newType.possibleProduction(unattended: true)
            var food = newProd.filter(\.isFoodType).reduce(0) { $0 + $1.amount }
            for ag in production {
                guard let goodsType = ag.type else { continue }
                if goodsType.isFoodType {
                    food -= ag.amount
                } else if colony.isConsuming(goodsType) {
                    let change = -ag.amount + newProd.filter { $0.type === goodsType }.reduce(0) { $0 + $1.amount }
                    if change < 0 && change + colony.netProduction(of: goodsType) < 0 { return change }
                }
            }
            return food
        }
        guard let unit = firstUnit, let work = currentWorkType else { return 0 }
        let unitType = unit.type
        guard let newType else { return ti.bonus(work) }
        let old = oldType.potentialProduction(work, unitType)
        if let resource {
            return newType.potentialProduction(work, unitType) - resource.applyBonus(work, unitType, old)
        }
        return newType.potentialProduction(work, unitType) - old
    }

    // MARK: Location

    public override func up() -> any Location {
        colony!
    }

    public override var shortDescription: String {
        let direction = tile.flatMap { t in workTileHere.flatMap { t.direction(to: $0) } }
        return "\(colony?.name ?? "null")-\(workTileHere?.type?.suffix ?? "null")"
            + "-\(direction.map { "\($0)" } ?? "null")"
    }

    public override func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        let reason = super.noAddReason(locatable)
        return reason != .none ? reason : noWorkReason
    }

    public override var unitCapacity: Int {
        isColonyCenterTile ? 0 : ColonyTile.tileUnitCapacity
    }

    // MARK: WorkLocation

    public override func goodSuggestionCheck(_ unitType: UnitType, _ unit: Unit?, _ goodsType: GoodsType) -> Bool {
        guard let tile = workTileHere, let owner else { return false }
        return owner.owns(tile) || owner.canClaimForSettlement(tile)
    }

    public override var isAvailable: Bool {
        guard let workTileHere else { return false }
        return isCurrent || (owner?.canClaimForSettlement(workTileHere) ?? false)
    }

    public override var isCurrent: Bool {
        workTileHere?.owningSettlement === colony
    }

    public override var noWorkReason: NoAddReason {
        guard let tile = workTileHere, let colony, let owner else { return .wrongType }
        if isColonyCenterTile { return .colonyCenter }
        if !colony.hasAbility(Ability.produceInWater) && !tile.isLand { return .missingAbility }
        if tile.owningSettlement === colony { return .none }
        switch owner.canClaimForSettlementReason(tile) {
        case .none: return .claimRequired
        case .terrain, .rumour, .water: return .missingAbility
        case .settlement: return owner.owns(tile.settlement) ? .anotherColony : .ownedByEnemy
        case .occupied: return .occupiedByEnemy
        case .worked: return .anotherColony
        case .europeans: return .ownedByEnemy
        case .natives: return .claimRequired
        }
    }

    public override var workTile: Tile? { workTileHere }

    /// Levels mean nothing for colony tiles.
    public override var level: Int { 0 }

    public override var canAutoProduce: Bool {
        isColonyCenterTile
    }

    public override func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        workTileHere?.canProduce(goodsType, unitType) ?? false
    }

    public override func baseProduction(_ productionType: ProductionType?, _ goodsType: GoodsType?,
                                        _ unitType: UnitType?) -> Int {
        workTileHere?.baseProduction(productionType, goodsType, unitType) ?? 0
    }

    public override func productionModifiers(_ goodsType: GoodsType?, _ unitType: UnitType?) -> [Modifier] {
        guard let workTileHere, let goodsType, let colony else { return [] }
        return TileProductionCalculator(owner: owner, colonyProductionBonus: colony.productionBonus)
            .productionModifiers(game?.turn, workTileHere, goodsType, unitType)
    }

    public override func availableProductionTypes(unattended: Bool) -> [ProductionType] {
        guard let type = workTileHere?.type, unattended == isColonyCenterTile else { return [] }
        return type.availableProductionTypes(unattended: unattended)
    }

    public override var competenceFactor: Float { 1 }
    public override var rebelFactor: Float { 1 }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        workTileHere = try xr.makeFreeColObject(game!, "workTile", Tile.self, required: true)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("workTile", workTileHere)
    }

    public override var description: String {
        "[\(id ?? "null") \(workTileHere.map { "\($0)" } ?? "null")/\(colony?.name ?? "NO-COLONY")]"
    }
}

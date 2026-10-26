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

/// A European colony (common/model/Colony).
///
/// The colony holds its buildings and colony tiles, which hold the
/// units working in them.
///
/// The prices and value, which need the market, are in
/// Valuation.swift.
///
/// Not yet ported:
/// Defence and plunder are in Defence.swift.
///
/// - the warnings (getUnbuildableMessage, checkForGovMgtChangeMessage,
///   getProductionWarnings) for the server's turn reports (Phase 3);
///   the labels are in Labels.swift;
/// - copyColony, getCorresponding, copyIn and the
///   integrity checks.
public final class Colony: Settlement, GameObjectReadable {

    public static let tag = "colony"

    /// Liberty needed per rebel.
    public static let libertyPerRebel = 200
    /// The most units to consider adding or removing.
    public static let changeUpperBound = 10
    public static let famineTurns = 3
    public static let tradeMargin = 5

    public static let governmentVeryGood = 2
    public static let governmentGood = 1
    public static let governmentOrdinary = 0
    public static let governmentBad = -1
    public static let governmentVeryBad = -2

    /// Why a colony can not build something (Colony.NoBuildReason).
    public enum NoBuildReason: JavaEnum, CustomStringConvertible {
        case none, notBuilding, notBuildable, populationTooSmall, missingBuildAbility
        case missingAbility, wrongUpgrade, coastal, limitExceeded

        public var javaName: String {
            switch self {
            case .none: "NONE"
            case .notBuilding: "NOT_BUILDING"
            case .notBuildable: "NOT_BUILDABLE"
            case .populationTooSmall: "POPULATION_TOO_SMALL"
            case .missingBuildAbility: "MISSING_BUILD_ABILITY"
            case .missingAbility: "MISSING_ABILITY"
            case .wrongUpgrade: "WRONG_UPGRADE"
            case .coastal: "COASTAL"
            case .limitExceeded: "LIMIT_EXCEEDED"
            }
        }

        public var description: String {
            javaName
        }
    }

    /// The buildings by the id of their first level's type, in Java's
    /// HashMap order (which decides the order buildings are tried in).
    private var buildingMap = JavaHashMap<String, Building>(javaHash: JavaString.hashCode)
    public private(set) var colonyTiles: [ColonyTile] = []
    private var exportDataMap = JavaHashMap<String, ExportData>(javaHash: JavaString.hashCode)
    private var libertyPoints = 0
    public private(set) var sonsOfLibertyPercent = 0
    public private(set) var oldSonsOfLiberty = 0
    public private(set) var tories = 0
    public private(set) var oldTories = 0
    public var productionBonus = 0
    private var immigrationPoints = 0
    public var established = Turn(0)
    public private(set) lazy var buildQueue = BuildQueue<BuildableType>(self, .removeExceptLast,
                                                                          ConsumerPriority.colony)
    public private(set) lazy var populationQueue = BuildQueue<UnitType>(self, .shuffle,
                                                                         ConsumerPriority.population)
    /// The unit count others see, or -1.
    public var displayUnitCount = -1
    private lazy var productionCache = ProductionCache(self)

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// Create a colony (the model side of Java's ServerColony
    /// constructor): the colony tiles, the buildings the colony gets
    /// for nothing, and the default build and population queues.  It
    /// is not on the map until placeSettlement.
    ///
    /// - Parameters:
    ///   - game: The game, which issues the identifier.
    ///   - owner: The owner.
    ///   - name: The colony's name.
    ///   - tile: Where the colony is.
    public override init(game: Game, owner: Player, name: String?, tile: Tile) {
        super.init(game: game, owner: owner, name: name, tile: tile)
        let spec = specification!
        setGoodsContainer(GoodsContainer(game: game, parent: self))
        sonsOfLibertyPercent = 0
        oldSonsOfLiberty = 0
        established = game.turn

        colonyTiles.append(ColonyTile(game: game, colony: self, workTile: tile))
        for t in tile.surroundingTiles(radius) {
            colonyTiles.append(ColonyTile(game: game, colony: self, workTile: t))
        }
        for buildingType in spec.buildingTypeList where buildingType.isAutomaticBuild || isAutomaticBuild(buildingType) {
            addBuilding(Building(game: game, colony: self, type: buildingType))
        }
        // The default queues, set after adding the buildings as that
        // checks the build queue, and these might fail the population
        // check.
        if isLandLocked {
            buildQueue.add(spec.getBuildingType("model.building.warehouse")!)
        } else {
            buildQueue.add(spec.getBuildingType("model.building.docks")!)
            addPortAbility()
        }
        for unitType in spec.unitTypes(withAnyAbility: Ability.bornInColony) where unitType.needsGoodsToBuild {
            populationQueue.add(unitType)
        }
    }

    public override var xmlTagName: String {
        Colony.tag
    }

    /// The work locations, and the units in them, go with the colony.
    public override var disposables: [FreeColGameObject] {
        allWorkLocations.flatMap(\.disposables) + super.disposables
    }

    // MARK: Buildings and colony tiles

    /// The buildings, in Java's HashMap order.
    public var buildings: [Building] {
        buildingMap.values
    }

    /// The building of a type's family.
    public func building(_ type: BuildingType) -> Building? {
        buildingMap[type.firstLevel.id ?? ""]
    }

    /// The colony tile working a tile.
    public func colonyTile(_ tile: Tile?) -> ColonyTile? {
        colonyTiles.first { $0.workTile === tile }
    }

    /// The export settings for goods, made if missing.
    public func exportData(_ goodsType: GoodsType) -> ExportData {
        if let result = exportDataMap[goodsType.id ?? ""] { return result }
        let result = ExportData(goodsType, importLevel: warehouseCapacity)
        setExportData(result)
        return result
    }

    /// The export settings set, in Java's HashMap order.
    public var exportDataValues: [ExportData] {
        exportDataMap.values
    }

    public func setExportData(_ data: ExportData) {
        exportDataMap.put(data.id ?? "", data)
    }

    public override var sonsOfLiberty: Int {
        sonsOfLibertyPercent
    }

    public func modifyImmigration(_ amount: Int) {
        immigrationPoints += amount
    }

    public func setBuildQueue(_ queue: [BuildableType]) {
        buildQueue.setValues(queue)
    }

    public func setPopulationQueue(_ queue: [UnitType]) {
        populationQueue.setValues(queue)
    }

    // MARK: Occupations

    /// Work types to try for a unit, as groups tried in turn: in user
    /// mode its current and expert work first, otherwise the goods it
    /// needs that are short; then food, luxuries and everything.
    public func workTypeChoices(_ unit: Unit, userMode: Bool) -> [[GoodsType]] {
        guard let spec = specification, let unitType = unit.type else { return [] }
        var result: [[GoodsType]] = []
        var tried = Set<ObjectIdentifier>()

        func accumulate(_ workTypes: [GoodsType]) {
            let left = workTypes.filter { !tried.contains(ObjectIdentifier($0)) }
            if !left.isEmpty {
                result.append(left)
                tried.formUnion(left.map(ObjectIdentifier.init))
            }
        }
        func accumulate(_ workType: GoodsType?) {
            if let workType { accumulate(workType.equivalentTypes) }
        }

        // The food and other goods the unit needs that are short now,
        // as Java's HashSets (their order decides ties).
        var food = JavaHashMap<GoodsType, Bool>(javaHash: { $0.javaHashCode })
        var nonFood = JavaHashMap<GoodsType, Bool>(javaHash: { $0.javaHashCode })
        for ag in unitType.consumedGoods where productionCache.netProduction(of: ag.type) < ag.amount {
            for t in ag.type?.equivalentTypes ?? [] {
                if ag.isFoodType { food.put(t, true) } else { nonFood.put(t, true) }
            }
        }
        if userMode {
            accumulate(unit.workType)
            accumulate(unitType.expertProduction)
            accumulate(unit.experienceType)
            accumulate(food.keys)
            accumulate(nonFood.keys)
        } else {
            accumulate(food.keys)
            accumulate(nonFood.keys)
            accumulate(unit.workType)
            accumulate(unitType.expertProduction)
            accumulate(unit.experienceType)
        }
        accumulate(spec.foodGoodsTypeList)
        accumulate(spec.newWorldLuxuryGoodsTypeList)
        accumulate(spec.goodsTypeList)
        return result
    }

    private func occupation(for unit: Unit, _ workTypes: [GoodsType]) -> Occupation? {
        if workTypes.isEmpty { return nil }
        let best = Occupation()
        var bestAmount = 0
        for wl in currentWorkLocations {
            bestAmount = best.improve(unit, wl, bestAmount, workTypes)
        }
        return best.workLocation == nil ? nil : best
    }

    /// The best occupation for a unit in this colony.
    public func occupation(for unit: Unit, userMode: Bool) -> Occupation? {
        for types in workTypeChoices(unit, userMode: userMode) {
            if let occupation = occupation(for: unit, types) { return occupation }
        }
        return nil
    }

    // MARK: Work locations

    /// The colony tiles, then the buildings.
    public var allWorkLocations: [WorkLocation] {
        colonyTiles + buildings
    }

    public var availableWorkLocations: [WorkLocation] {
        allWorkLocations.filter(\.isAvailable)
    }

    public var currentWorkLocations: [WorkLocation] {
        allWorkLocations.filter(\.isCurrent)
    }

    /// Add a building, with its type's features.
    @discardableResult
    public func addBuilding(_ building: Building?) -> Bool {
        guard let building, let type = building.type, let id = type.firstLevel.id else { return false }
        buildingMap.put(id, building)
        addFeatures(of: type)
        return true
    }

    @discardableResult
    public func removeBuilding(_ building: Building) -> Bool {
        guard let type = building.type, let id = type.firstLevel.id,
              buildingMap.removeValue(forKey: id) != nil else { return false }
        removeFeatures(of: type)
        return true
    }

    private func addColonyTile(_ ct: ColonyTile?) {
        if let ct { colonyTiles.append(ct) }
    }

    public func workLocation(withAbility ability: String) -> WorkLocation? {
        currentWorkLocations.first { $0.hasAbility(ability) }
    }

    public func workLocation(withModifier modifier: String) -> WorkLocation? {
        currentWorkLocations.first { $0.hasModifier(modifier) }
    }

    public func workLocations(consuming goodsType: GoodsType) -> [WorkLocation] {
        currentWorkLocations.filter { $0.inputs.contains { $0.type === goodsType } }
    }

    public func workLocations(producing goodsType: GoodsType) -> [WorkLocation] {
        currentWorkLocations.filter { $0.outputs.contains { $0.type === goodsType } }
    }

    public func workLocation(producing goodsType: GoodsType) -> WorkLocation? {
        workLocations(producing: goodsType).first
    }

    /// The best work location for a unit to make goods, or for any work.
    public func workLocation(for unit: Unit, _ goodsType: GoodsType? = nil) -> WorkLocation? {
        if let goodsType { return occupation(for: unit, goodsType.equivalentTypes)?.workLocation }
        return occupation(for: unit, userMode: false)?.workLocation
    }

    public func isTileInUse(_ tile: Tile) -> Bool {
        guard let ct = colonyTile(tile) else { return false }
        return !ct.isEmpty
    }

    public var warehouse: Building? {
        workLocation(withModifier: Modifier.warehouseStorage) as? Building
    }

    public var hasStockade: Bool {
        stockade != nil
    }

    public var stockade: Building? {
        workLocation(withModifier: Modifier.defence) as? Building
    }

    public var stockadeKey: String? {
        stockade?.type?.suffix
    }

    /// The disasters that can strike the colony's tiles.
    public var disasterChoices: [RandomChoice<Disaster>] {
        colonyTiles.flatMap { $0.workTile?.disasterChoices ?? [] }
    }

    // MARK: Building

    /// Whether the owner gets a building for nothing.
    public func isAutomaticBuild(_ buildingType: BuildingType) -> Bool {
        let value = owner?.apply(100, turn: game?.turn, Modifier.buildingPriceBonus, for: buildingType) ?? 100
        return value == 0 && canBuild(buildingType)
    }

    public var buildableUnits: [UnitType] {
        (specification?.unitTypeList ?? []).filter { $0.needsGoodsToBuild && canBuild($0) }
    }

    /// The turns to finish building something: the turns if it will
    /// finish, Constants.undefined if no goods are coming, or -(turns +
    /// 1) if blocked by a goods type not being made (which is put in
    /// needed).
    public func turnsToComplete(_ buildable: BuildableType, needed: AbstractGoods? = nil) -> Int {
        let required = buildable.requiredGoods
        var turns = 0, satisfied = 0, failing = 0, underway = 0
        let info = productionCache.productionInfo(of: buildQueue)
        for ag in required {
            guard let type = ag.type else { continue }
            let amountNeeded = ag.amount
            let amountAvailable = goodsCount(type)
            if amountAvailable >= amountNeeded {
                satisfied += 1
                continue
            }
            var production = productionCache.netProduction(of: type)
            if let consumption = info?.consumption.first(where: { $0.type === type }) {
                // Add what the build queue itself will consume.
                production += consumption.amount
            }
            if production <= 0 {
                failing += 1
                if let needed {
                    needed.type = type
                    needed.amount = amountNeeded - amountAvailable
                }
                continue
            }
            underway += 1
            let amountRemaining = amountNeeded - amountAvailable
            var eta = amountRemaining / production
            if amountRemaining % production != 0 { eta += 1 }
            turns = max(turns, eta)
        }
        return satisfied + underway == required.count ? turns
            : failing == required.count ? Constants.undefined
            : -(turns + 1)
    }

    /// Whether enough goods are here to breed.
    public func canBreed(_ goodsType: GoodsType) -> Bool {
        goodsType.breedingNumber < Constants.infinity && goodsType.breedingNumber <= goodsCount(goodsType)
    }

    public var currentlyBuilding: BuildableType? {
        buildQueue.currentlyBuilding
    }

    public func setCurrentlyBuilding(_ buildable: BuildableType?) {
        buildQueue.setCurrentlyBuilding(buildable)
    }

    public var canBuild: Bool {
        canBuild(currentlyBuilding)
    }

    public func canBuild(_ buildableType: BuildableType?) -> Bool {
        noBuildReason(buildableType, nil) == .none
    }

    /// Why this colony can not build something, assuming some other
    /// things are built first.
    public func noBuildReason(_ buildableType: BuildableType?, _ assumeBuilt: [BuildableType]?) -> NoBuildReason {
        guard let buildableType else { return .notBuilding }
        if !buildableType.needsGoodsToBuild { return .notBuildable }
        if buildableType.requiredPopulation > unitCount { return .populationTooSmall }
        if buildableType.hasAbility(Ability.coastalOnly) && !(tile?.isCoastland ?? false) { return .coastal }
        if buildableType.requiredAbilities.contains(where: { $0.value != hasAbility($0.key) }) {
            return .missingAbility
        }
        if !buildableType.limits.allSatisfy({ $0.evaluate(self) }) { return .limitExceeded }
        return buildableType.canBeBuiltInColony(self, assumeBuilt ?? [])
    }

    /// The goods still missing to build something.
    public func requiredGoods(_ type: BuildableType) -> [AbstractGoods] {
        type.requiredGoods.compactMap { ag in
            ag.amount > goodsCount(ag.type) ? AbstractGoods(ag.type, ag.amount - goodsCount(ag.type)) : nil
        }
    }

    /// The goods missing to build something, including the raw
    /// materials for missing goods, raw materials first.
    public func fullRequiredGoods(_ buildable: BuildableType?) -> [AbstractGoods] {
        guard let buildable else { return [] }
        var required: [AbstractGoods] = []
        for ag in buildable.requiredGoods {
            var type = ag.type
            while let t = type {
                if ag.amount <= goodsCount(t) { break }
                required.insert(AbstractGoods(t, ag.amount - goodsCount(t)), at: 0)
                type = t.inputType
            }
        }
        return required
    }

    // MARK: Liberty

    public override var liberty: Int {
        libertyPoints
    }

    public override var immigration: Int {
        immigrationPoints
    }

    /// Add liberty goods, and update rebels and the production bonus.
    public func addLiberty(_ amount: Int) {
        if amount > 0, let bells = specification?.libertyGoodsTypeList.first {
            addGoods(bells, amount)
        }
        updateSoL()
        updateProductionBonus()
    }

    /// Change the liberty, for the colony and its owner.
    public func modifyLiberty(_ amount: Int) {
        // Liberty always counts for the owner too (founding fathers).
        owner?.modifyLiberty(amount)
        libertyPoints = max(0, libertyPoints + amount)
        updateSoL()
        updateProductionBonus()
        // With the bell accumulation cap, liberty stops at 100%.
        if (specification?.getBoolean(GameOptions.bellAccumulationCapped) ?? false)
            && sonsOfLibertyPercent >= 100 {
            libertyPoints = Colony.libertyPerRebel * unitCount
        }
    }

    public func updateSoL() {
        let uc = unitCount
        oldSonsOfLiberty = sonsOfLibertyPercent
        oldTories = tories
        sonsOfLibertyPercent = calculateSoLPercentage(uc, liberty)
        tories = Colony.calculateToryCount(uc, sonsOfLibertyPercent)
    }

    private func calculateSoLPercentage(_ uc: Int, _ liberty: Int) -> Int {
        if uc <= 0 { return -1 }
        // Java: float membership = (liberty * 100.0f) / (200 * uc)
        var membership = (Float(liberty) * 100) / Float(Colony.libertyPerRebel * uc)
        membership = FeatureContainer.applyModifiers(membership, turn: game?.turn,
                                                     owner?.modifiers(Modifier.sol) ?? [])
        membership = min(max(membership, 0), 100)
        return Int(JavaMath.toInt(membership))
    }

    public static func calculateRebelCount(_ uc: Int, _ solPercent: Int) -> Int {
        Int(JavaMath.toInt((0.01 * Double(solPercent) * Double(uc)).rounded(.down)))
    }

    public static func calculateToryCount(_ uc: Int, _ solPercent: Int) -> Int {
        uc - calculateRebelCount(uc, solPercent)
    }

    private func governmentLimits() -> (veryBad: Int, bad: Int, veryGood: Int, good: Int) {
        let spec = specification
        return (spec?.getInteger(GameOptions.veryBadGovernmentLimit) ?? 0,
                spec?.getInteger(GameOptions.badGovernmentLimit) ?? 0,
                spec?.getInteger(GameOptions.veryGoodGovernmentLimit) ?? 0,
                spec?.getInteger(GameOptions.goodGovernmentLimit) ?? 0)
    }

    /// The message for a change in the colony's government after its
    /// rebels changed, if there is one (checkForGovMgtChangeMessage).
    public func checkForGovMgtChangeMessage() -> ModelMessage? {
        let limits = governmentLimits()
        var msgId: String?
        var number = 0
        var msgType = ModelMessage.MessageType.governmentEfficiency
        if sonsOfLibertyPercent >= limits.veryGood {
            // There are no tories left.
            if oldSonsOfLiberty < limits.veryGood {
                msgId = "model.colony.veryGoodGovernment"
                msgType = .sonsOfLiberty
                number = limits.veryGood
            }
        } else if sonsOfLibertyPercent >= limits.good {
            if oldSonsOfLiberty == limits.veryGood {
                msgId = "model.colony.lostVeryGoodGovernment"
                msgType = .sonsOfLiberty
                number = limits.veryGood
            } else if oldSonsOfLiberty < limits.good {
                msgId = "model.colony.goodGovernment"
                msgType = .sonsOfLiberty
                number = limits.good
            }
        } else {
            if oldSonsOfLiberty >= limits.good {
                msgId = "model.colony.lostGoodGovernment"
                msgType = .sonsOfLiberty
                number = limits.good
            }
            // Now that no bonus is applied, penalties may.
            if tories > limits.veryBad {
                if oldTories <= limits.veryBad { msgId = "model.colony.veryBadGovernment" }
            } else if tories > limits.bad {
                if oldTories <= limits.bad {
                    msgId = "model.colony.badGovernment"
                } else if oldTories > limits.veryBad {
                    msgId = "model.colony.governmentImproved1"
                }
            } else if oldTories > limits.bad {
                msgId = "model.colony.governmentImproved2"
            }
        }
        guard let msgId else { return nil }
        return ModelMessage(msgType, msgId, self, specification?.getGoodsType("model.goods.bells"))
            .addName("%colony%", name)
            .addAmount("%number%", number)
    }

    private func calculateProductionBonus(_ solPercent: Int) -> Int {
        let limits = governmentLimits()
        if solPercent >= limits.veryGood { return Colony.governmentVeryGood }
        if solPercent >= limits.good { return Colony.governmentGood }
        let tc = Colony.calculateToryCount(unitCount, solPercent)
        return tc > limits.veryBad ? Colony.governmentVeryBad
            : tc > limits.bad ? Colony.governmentBad
            : Colony.governmentOrdinary
    }

    @discardableResult
    public func updateProductionBonus() -> Bool {
        let newBonus = calculateProductionBonus(sonsOfLibertyPercent)
        if productionBonus != newBonus {
            invalidateCache()
            productionBonus = newBonus
            return true
        }
        return false
    }

    /// How many units to add (or with a penalty, remove) without the
    /// government getting worse.
    public var preferredSizeChange: Int {
        productionBonus < 0 ? -unitsToRemove : unitsToAdd
    }

    public var unitsToAdd: Int {
        let pop = unitCount
        for i in 1...Colony.changeUpperBound where governmentChange(pop + i) == -1 {
            return i - 1
        }
        return Colony.changeUpperBound
    }

    public var unitsToRemove: Int {
        let pop = unitCount
        if pop > 1 {
            for i in 1..<pop where governmentChange(pop - i) == 1 { return i }
        }
        return 0
    }

    /// The turns of liberty production to the next change of
    /// government, to good government and to very good government
    /// (-1 where it would never happen).
    public func rebelHelper(_ libertyProduction: Int) -> [Int] {
        var ret = [-1, -1, -1]
        if libertyProduction <= 0 { return ret }
        let uc = unitCount
        var liberty = self.liberty
        var solPercent = calculateSoLPercentage(uc, liberty)
        let bonus0 = calculateProductionBonus(solPercent)
        var n = 0, bonus = bonus0
        while true {
            if bonus != bonus0 && ret[0] < 0 { ret[0] = n }
            if bonus == Colony.governmentGood && ret[1] < 0 { ret[1] = n }
            if bonus == Colony.governmentVeryGood && ret[2] < 0 {
                ret[2] = n
                break
            }
            liberty += libertyProduction
            solPercent = calculateSoLPercentage(uc, liberty)
            bonus = calculateProductionBonus(solPercent)
            n += 1
        }
        return ret
    }

    /// Whether a unit count would make the government better (1),
    /// worse (-1) or neither (0).
    public func governmentChange(_ unitCount: Int) -> Int {
        let limits = governmentLimits()
        let newSoLPercent = calculateSoLPercentage(unitCount, liberty)
        let newToryCount = Colony.calculateToryCount(unitCount, newSoLPercent)
        let oldSoLPercent = sonsOfLibertyPercent
        let oldToryCount = tories
        var result = 0
        if newSoLPercent >= limits.veryGood {
            // No tories left.
            if oldSoLPercent < limits.veryGood { result = 1 }
        } else if newSoLPercent >= limits.good {
            if oldSoLPercent >= limits.veryGood {
                result = -1
            } else if oldSoLPercent < limits.good {
                result = 1
            }
        } else if oldSoLPercent >= limits.good {
            result = -1
        } else {
            // With no bonus, penalties may apply.
            if newToryCount > limits.veryBad {
                if oldToryCount <= limits.veryBad { result = -1 }
            } else if newToryCount > limits.bad {
                if oldToryCount <= limits.bad {
                    result = -1
                } else if oldToryCount > limits.veryBad {
                    result = 1
                }
            } else if oldToryCount > limits.bad {
                result = 1
            }
        }
        return result
    }

    // MARK: Units and population

    /// Put a unit to its best work here, or leave it on the tile.
    @discardableResult
    public func joinColony(_ unit: Unit) -> Bool {
        let ret = occupation(for: unit, userMode: false)?.install(unit) ?? false
        if !ret { unit.setLocation(tile) } // Java logs a warning
        return ret
    }

    public var canReducePopulation: Bool {
        Float(unitCount) > apply(0, turn: game?.turn, Modifier.minimumColonySize)
    }

    /// Update the rebels and production bonus after the population
    /// changes.  Java also asks AI colonies to rearrange.
    public func updatePopulation() {
        updateSoL()
        updateProductionBonus()
    }

    /// Start or stop a unit teaching or learning.
    public func updateEducation(_ unit: Unit, enable: Bool) {
        guard let wl = unit.workLocation, wl.colony === self else {
            preconditionFailure("updateEducation(\(unit)) unit not at work location in this colony.")
        }
        if enable {
            if wl.canTeach {
                if unit.student == nil, let student = findStudent(unit) {
                    unit.setStudent(student)
                    student.setTeacher(unit)
                    unit.turnsOfTraining = 0 // The teacher starts teaching
                    unit.changeWorkType(nil)
                }
            } else if unit.teacher == nil, let teacher = findTeacher(unit) {
                unit.setTeacher(teacher)
                teacher.setStudent(unit)
            }
        } else if wl.canTeach {
            if let student = unit.student {
                student.setTeacher(nil)
                unit.setStudent(nil)
                unit.turnsOfTraining = 0 // The teacher stops teaching
            }
        } else if let teacher = unit.teacher {
            teacher.setStudent(nil)
            unit.setTeacher(nil)
        }
    }

    public var isUndead: Bool {
        firstUnit?.isUndead ?? false
    }

    public var apparentUnitCount: Int {
        displayUnitCount > 0 ? displayUnitCount : unitCount
    }

    // MARK: Defence and attack

    /// The best defending unit type the owner can have.
    public var bestDefenderType: UnitType? {
        var best: UnitType?
        for ut in specification?.unitTypeList ?? []
        where ut.defence > 0 && !ut.isNaval && ut.isAvailableTo([owner]) {
            if best == nil || ut.defence > best!.defence { best = ut }
        }
        return best
    }

    /// Whether an attacker could pillage the colony.
    public func canBePillaged(_ attacker: Unit) -> Bool {
        !hasStockade && attacker.hasAbility(Ability.pillageUnprotectedColony)
            && !(burnableBuildings.isEmpty && (tile?.navalUnits.isEmpty ?? true)
                 && (lootableGoodsList.isEmpty || !(attacker.type?.canCarryGoods ?? false)
                     || !attacker.hasSpaceLeft)
                 && !canBePlundered)
    }

    public var canBePlundered: Bool {
        owner?.checkGold(1) ?? false
    }

    public var burnableBuildings: [Building] {
        buildings.filter(\.canBeDamaged)
    }

    public var lootableGoodsList: [Goods] {
        goodsList.filter(\.isStorable)
    }

    /// Whether more enemy offensive units than our defenders are on the
    /// colony's tiles.
    public var isUnderSiege: Bool {
        var friendlyUnits = 0, enemyUnits = 0
        for u in colonyTiles.flatMap({ $0.workTile?.unitList ?? [] }) {
            if u.owner === owner {
                if u.isDefensiveUnit { friendlyUnits += 1 }
            } else if owner?.atWar(with: u.owner) ?? false {
                if u.isOffensiveUnit { enemyUnits += 1 }
            }
        }
        return enemyUnits > friendlyUnits
    }

    // MARK: Education

    public func canTrain(_ unit: Unit) -> Bool {
        canTrain(unit.type)
    }

    public func canTrain(_ unitType: UnitType?) -> Bool {
        hasAbility(Ability.teach) && buildings.contains { $0.canTeach && $0.canAddType(unitType) }
    }

    public var teachers: [Unit] {
        buildings.filter(\.canTeach).flatMap(\.unitList)
    }

    /// A teacher free to teach a student, unless students are chosen by
    /// hand.
    public func findTeacher(_ student: Unit) -> Unit? {
        if specification?.getBoolean(GameOptions.allowStudentSelection) ?? false { return nil }
        return teachers.first { $0.student == nil && student.canBeStudent($0) }
    }

    /// The student for a teacher: the least skilled, then one working
    /// in the teacher's trade, then the first.
    public func findStudent(_ teacher: Unit) -> Unit? {
        if specification?.getBoolean(GameOptions.allowStudentSelection) ?? false { return nil }
        let expertProduction = teacher.type?.expertProduction
        func key(_ u: Unit) -> (Int, Int) {
            (u.skillLevel, u.workType === expertProduction ? 0 : 1)
        }
        var best: Unit?
        for u in unitList where u.teacher == nil && u.canBeStudent(teacher) {
            if best == nil || key(u) < key(best!) { best = u }
        }
        return best
    }

    // MARK: Production

    public func isProducing(_ goodsType: GoodsType) -> Bool {
        productionCache.isProducing(goodsType)
    }

    public func isConsuming(_ goodsType: GoodsType) -> Bool {
        productionCache.isConsuming(goodsType)
    }

    /// The units, buildings and queues, highest priority first.
    public var consumers: [Consumer] {
        let all: [Consumer] = unitList + buildings + [buildQueue, populationQueue]
        return all.stableSorted { $0.consumerPriority > $1.consumerPriority }
    }

    /// The consumption of goods here; some units use no bells.
    public override func consumption(of goodsType: GoodsType) -> Int {
        var result = super.consumption(of: goodsType)
        if let spec = specification, spec.getGoodsType("model.goods.bells") === goodsType {
            result -= spec.getInteger(GameOptions.unitsThatUseNoBells) ?? 0
        }
        return max(0, result)
    }

    public var foodProduction: Int {
        (specification?.foodGoodsTypeList ?? []).reduce(0) { $0 + totalProduction(of: $1) }
    }

    /// Turns until the food runs out, or -1 if it is not running out.
    public var starvationTurns: Int {
        guard let foodType = specification?.primaryFoodType else { return -1 }
        let food = goodsCount(foodType)
        let newFood = adjustedNetProduction(of: foodType)
        return newFood >= 0 ? -1 : food / -newFood
    }

    /// Turns until a new colonist is born, or -1 if never.
    public var newColonistTurns: Int {
        guard let foodType = specification?.primaryFoodType else { return -1 }
        let food = goodsCount(foodType)
        let newFood = adjustedNetProduction(of: foodType)
        return food + newFood >= Settlement.foodPerColonist ? 1
            : newFood <= 0 ? -1
            : (Settlement.foodPerColonist - food) / newFood + 1
    }

    /// The rebel bonus (or tory penalty) to production at a work
    /// location.
    public func productionModifiers(_ goodsType: GoodsType, _ unitType: UnitType?,
                                    _ wl: WorkLocation) -> [Modifier] {
        if productionBonus == 0 { return [] }
        // Java: (int)Math.floor(productionBonus * wl.getRebelFactor()),
        // a float widened to double.
        let bonus = Int(JavaMath.toInt(Double(Float(productionBonus) * wl.rebelFactor).rounded(.down)))
        return [Modifier(goodsType.id, Float(bonus), .additive,
                         source: specification?.getType(Specification.SourceId.solModifier),
                         index: Modifier.colonyProductionIndex)]
    }

    public func netProduction(of goodsType: GoodsType?) -> Int {
        productionCache.netProduction(of: goodsType)
    }

    public func isProductive(_ workLocation: WorkLocation) -> Bool {
        guard let first = productionCache.productionInfo(of: workLocation)?.production.first else { return false }
        return first.amount > 0
    }

    /// The net production, adding back what the queues consume.
    public func adjustedNetProduction(of goodsType: GoodsType) -> Int {
        let queued = [productionCache.productionInfo(of: buildQueue),
                      productionCache.productionInfo(of: populationQueue)]
            .reduce(0) { $0 + AbstractGoods.count(of: goodsType, in: $1?.consumption ?? []) }
        return productionCache.netProduction(of: goodsType) + queued
    }

    public var productionMap: TypeCountMap<GoodsType> {
        productionCache.productionMap
    }

    /// The production of a work location, unit or queue.
    public func productionInfo(of object: AnyObject) -> ProductionInfo? {
        productionCache.productionInfo(of: object)
    }

    public func updateProductionTypes() {
        for wl in availableWorkLocations { wl.updateProductionType() }
    }

    /// Whether the colony could produce goods: it is, it can breed them,
    /// or a work location could with its inputs.
    public func canProduce(_ goodsType: GoodsType) -> Bool {
        if netProduction(of: goodsType) > 0 { return true }
        if goodsType.isBreedable { return goodsCount(goodsType) >= goodsType.breedingNumber }
        return workLocations(producing: goodsType).contains { wl in
            wl.genericPotential(goodsType) > 0
                && wl.inputs.allSatisfy { $0.type.map(canProduce) ?? false }
        }
    }

    // MARK: Planning

    /// An improvement worth making to a tile, or a rumour worth
    /// exploring (Colony.TileImprovementSuggestion).
    public struct TileImprovementSuggestion {
        public let tile: Tile
        /// The improvement, or nil to explore a rumour.
        public let tileImprovementType: TileImprovementType?
        public let amount: Int

        public var isExploration: Bool {
            tileImprovementType == nil
        }
    }

    /// Rumours next door, then improvements to the available tiles, most
    /// useful first.
    public var tileImprovementSuggestions: [TileImprovementSuggestion] {
        guard let spec = specification, let tile else { return [] }
        var result = tile.surroundingTiles(1, 1).filter(\.hasLostCityRumour).map {
            TileImprovementSuggestion(tile: $0, tileImprovementType: nil, amount: Constants.infinity)
        }
        for ct in colonyTiles where ct.isAvailable {
            guard let workTile = ct.workTile else { continue }
            for ti in spec.tileImprovementTypeList where !ti.isNatural {
                let amount = ct.improvedBy(ti)
                if amount > 0 {
                    result.append(TileImprovementSuggestion(tile: workTile, tileImprovementType: ti,
                                                            amount: amount))
                }
            }
        }
        return result.stableSorted { a, b in
            a.amount != b.amount ? a.amount > b.amount : FreeColObject.compareIds(a.tile, b.tile) < 0
        }
    }

    /// A unit doing an expert's job that would do better swapped with
    /// the expert, or nil.
    public func betterExpert(_ expert: Unit) -> Unit? {
        guard let production = expert.workType, let expertType = expert.type,
              let expertise = expertType.expertProduction, production !== expertise else { return nil }
        var bestExpert: Unit?
        var bestImprovement = 0
        for nonExpert in unitList where nonExpert.workType === expertise && nonExpert.type !== expertType {
            var expertNow = 0, nonExpertNow = 0, expertPotential = 0, nonExpertPotential = 0
            if let ewl = expert.workLocation {
                expertNow = ewl.potentialProduction(expertise, expertType)
                nonExpertPotential = ewl.potentialProduction(expertise, nonExpert.type)
            }
            if let nwl = nonExpert.workLocation {
                nonExpertNow = nwl.potentialProduction(expertise, nonExpert.type)
                expertPotential = nwl.potentialProduction(expertise, expertType)
            }
            let improvement = expertPotential + nonExpertPotential - expertNow - nonExpertNow
            if improvement > bestImprovement {
                bestImprovement = improvement
                bestExpert = nonExpert
            }
        }
        return bestExpert
    }

    /// Whether goods are any use: independent players need no more
    /// bells at 100% rebels, and no crosses.
    public func goodsUseful(_ goodsType: GoodsType) -> Bool {
        if owner?.playerType == .independent
            && ((goodsType.isLibertyType && sonsOfLiberty >= 100) || goodsType.isImmigrationType) {
            return false
        }
        return true
    }

    /// Goods that make liberty or immigration change those.
    private func modifySpecialGoods(_ goodsType: GoodsType, _ amount: Int) {
        let turn = game?.turn
        let libertyMods = goodsType.modifiers(Modifier.liberty)
        if !libertyMods.isEmpty {
            modifyLiberty(Int(JavaMath.toInt(FeatureContainer.applyModifiers(Float(amount), turn: turn,
                                                                              libertyMods))))
        }
        let immigrationMods = goodsType.modifiers(Modifier.immigration)
        if !immigrationMods.isEmpty {
            let migration = Int(JavaMath.toInt(FeatureContainer.applyModifiers(Float(amount), turn: turn,
                                                                                 immigrationMods)))
            modifyImmigration(migration)
            owner?.modifyImmigration(migration)
        }
    }

    // MARK: Features

    /// The colony's abilities and its owner's.
    public override func abilities(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                                   turn: Turn? = nil) -> [Ability] {
        let turn = turn ?? game?.turn
        return super.abilities(id, for: target, turn: turn) + (owner?.abilities(id, for: target, turn: turn) ?? [])
    }

    // MARK: Location

    /// Units join the colony's best work for them.
    @discardableResult
    public override func add(_ locatable: any Locatable) -> Bool {
        if let unit = locatable as? Unit { return joinColony(unit) }
        return super.add(locatable)
    }

    @discardableResult
    public override func remove(_ locatable: any Locatable) -> Bool {
        if locatable is Unit {
            if let wl = locatable.location as? WorkLocation, wl.colony === self { return wl.remove(locatable) }
            return false
        }
        return super.remove(locatable)
    }

    public override func contains(_ locatable: any Locatable) -> Bool {
        if locatable is Unit { return availableWorkLocations.contains { $0.contains(locatable) } }
        return super.contains(locatable)
    }

    /// The units working in the colony.
    public override var unitCount: Int {
        currentWorkLocations.reduce(0) { $0 + $1.unitCount }
    }

    public override var unitList: [Unit] {
        currentWorkLocations.flatMap(\.unitList)
    }

    // MARK: GoodsLocation

    public override func invalidateCache() {
        productionCache.invalidate()
    }

    public override var goodsCapacity: Int {
        Int(JavaMath.toInt(apply(0, turn: game?.turn, Modifier.warehouseStorage)))
    }

    @discardableResult
    public override func addGoods(_ type: GoodsType, _ amount: Int) -> Bool {
        super.addGoods(type, amount)
        productionCache.invalidate(type)
        modifySpecialGoods(type, amount)
        return true
    }

    @discardableResult
    public override func removeGoods(_ type: GoodsType, _ amount: Int) -> Goods? {
        let removed = super.removeGoods(type, amount)
        productionCache.invalidate(type)
        if let removed { modifySpecialGoods(type, -removed.amount) }
        return removed
    }

    // MARK: Settlement

    public override var upkeep: Int {
        buildings.reduce(0) { $0 + ($1.type?.upkeep ?? 0) }
    }

    public override func totalProduction(of goodsType: GoodsType) -> Int {
        currentWorkLocations.reduce(0) { $0 + $1.totalProduction(of: goodsType) }
    }

    /// Whether goods can be spared, keeping enough to breed and what the
    /// current build needs.
    public override func canProvideGoods(_ requiredGoods: [AbstractGoods]) -> Bool {
        let buildable = currentlyBuilding
        for goods in requiredGoods {
            guard let type = goods.type else { return false }
            var available = goodsCount(type)
            if type.breedingNumber != Constants.infinity { available -= type.breedingNumber }
            if let buildable { available -= AbstractGoods.count(of: type, in: buildable.requiredGoods) }
            if available < goods.amount { return false }
        }
        return true
    }

    public override func hasContacted(_ player: Player?) -> Bool {
        guard let player else { return false }
        return player.isEuropean || owner?.stance(player) != .uncontacted
    }

    /// How the AI values attacking this colony: more people, fewer
    /// fortifications.
    public func calculateSettlementValue(_ value: Int, _ unit: Unit?) -> Int {
        var value = value + unitCount
        if let stockade { value -= 200 * stockade.level }
        return value
    }

    // MARK: Trade routes

    private func returnPresent(_ goodsType: GoodsType, _ turns: Int) -> Int {
        max(0, goodsCount(goodsType) + turns * netProduction(of: goodsType))
    }

    public func availableGoodsCount(_ goodsType: GoodsType) -> Int {
        goodsCount(goodsType)
    }

    public func exportAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        max(0, returnPresent(goodsType, turns) - exportData(goodsType).exportLevel)
    }

    public func importAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        if goodsType.limitIgnored { return GoodsContainer.hugeCargoSize }
        let present = returnPresent(goodsType, turns)
        let capacity = (specification?.getBoolean(GameOptions.enhancedTradeRoutes) ?? false)
            ? exportData(goodsType).effectiveImportLevel(warehouseCapacity)
            : warehouseCapacity
        return max(0, capacity - present)
    }

    func addPortAbility() {
        addAbility(Ability(Ability.hasPort))
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        established = Turn(xr.attribute("established", default: 0))
        sonsOfLibertyPercent = xr.attribute("sonsOfLiberty", default: 0)
        oldSonsOfLiberty = xr.attribute("oldSonsOfLiberty", default: 0)
        tories = xr.attribute("tories", default: 0)
        oldTories = xr.attribute("oldTories", default: 0)
        libertyPoints = xr.attribute("liberty", default: 0)
        immigrationPoints = xr.attribute("immigration", default: 0)
        productionBonus = xr.attribute("productionBonus", default: 0)
        displayUnitCount = xr.attribute("unitCount", default: -1)
    }

    // MARK: Writing XML

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("name", id: name)
        xw.writeAttribute("established", established.number)
        xw.writeAttribute("sonsOfLiberty", sonsOfLibertyPercent)
        if xw.validFor(owner) {
            xw.writeAttribute("oldSonsOfLiberty", oldSonsOfLiberty)
            xw.writeAttribute("tories", tories)
            xw.writeAttribute("oldTories", oldTories)
            xw.writeAttribute("liberty", libertyPoints)
            xw.writeAttribute("immigration", immigrationPoints)
            xw.writeAttribute("productionBonus", productionBonus)
        } else {
            // Java traces a count of zero, which is a bug elsewhere;
            // a negative one means no count.
            let uc = apparentUnitCount
            if uc > 0 { xw.writeAttribute("unitCount", uc) }
        }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if xw.validFor(owner) {
            for key in exportDataMap.keys.sorted(by: { JavaString.compare($0, $1) < 0 }) {
                exportDataMap[key]!.toXML(xw)
            }
            for wl in sortedById(allWorkLocations) { wl.toXML(xw) }
            for item in buildQueue.values { xw.writeIdElement("buildQueueItem", item.id) }
            for item in populationQueue.values { xw.writeIdElement("populationQueueItem", item.id) }
        } else {
            stockade?.toXML(xw)
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        buildingMap.removeAll()
        colonyTiles = []
        exportDataMap.removeAll()
        buildQueue.clear()
        populationQueue.clear()
        try super.readChildren(xr)
        invalidateCache()
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let game = game!
        let spec = specification
        switch xr.localName {
        case "buildQueueItem":
            if let spec, let bt = try xr.getType(spec, FreeColObject.idTag, BuildableType.self) {
                buildQueue.add(bt)
            }
            try xr.closeTag("buildQueueItem")
        case "populationQueueItem":
            if let spec, let ut = try xr.getType(spec, FreeColObject.idTag, UnitType.self) {
                populationQueue.add(ut)
            }
            try xr.closeTag("populationQueueItem")
        case Building.tag:
            addBuilding(try xr.readFreeColObject(game, Building.self))
        case ColonyTile.tag:
            addColonyTile(try xr.readFreeColObject(game, ColonyTile.self))
        case ExportData.tag:
            setExportData(try ExportData(reading: xr))
        default:
            try super.readChild(xr)
        }
    }

    public override var description: String {
        name ?? "null"
    }
}

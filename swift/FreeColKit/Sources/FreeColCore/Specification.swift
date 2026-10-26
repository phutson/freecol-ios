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
import FreeColXML

/// The rules of a game (common/model/Specification).
///
/// So far this reads a resolved specification: the form Java writes
/// for clients and into saved games, where inheritance between rule
/// sets and mods has already been applied.  Types are created when
/// first mentioned, as forward declarations, then filled in when their
/// own element is read.
///
/// Not yet ported (step 4): reading the rule set files themselves
/// ("extends" between rule sets, mods), the option classes, difficulty
/// levels, and the compatibility fixes Java applies after loading.
/// Option values are read from the options section into a simple
/// store, so getString, getInteger and getBoolean work meanwhile.
public final class Specification {

    public static let tag = "freecol-specification"
    public static let defaultRoleId = "model.role.default"
    public static let numberOfAges = 3
    private static let defaultFoodType = "model.goods.food"
    private static let defaultNationType = "model.nationType.default"

    /// The ids of the built-in modifier sources (Java's static Source
    /// objects).  Each specification registers its own Source per id.
    public enum SourceId {
        public static let ambushBonus = "model.source.ambushBonus"
        public static let amphibiousAttackPenalty = "model.source.amphibiousAttack"
        public static let artilleryPenalty = "model.source.artilleryInTheOpen"
        public static let attackBonus = "model.source.attackBonus"
        public static let baseDefence = "model.source.baseDefence"
        public static let baseOffence = "model.source.baseOffence"
        public static let cargoPenalty = "model.source.cargoPenalty"
        public static let colonyGoodsParty = "model.source.colonyGoodsParty"
        public static let fortificationBonus = "model.source.fortified"
        public static let indianRaidBonus = "model.source.artilleryAgainstRaid"
        public static let movementPenalty = "model.source.movementPenalty"
        public static let shipTradePenalty = "model.source.shipTradePenalty"
        public static let solModifier = "model.source.solModifier"

        /// In Java's registration order.
        static let all = [movementPenalty, artilleryPenalty, attackBonus, fortificationBonus,
                          indianRaidBonus, amphibiousAttackPenalty, baseOffence, baseDefence,
                          cargoPenalty, ambushBonus, colonyGoodsParty, shipTradePenalty,
                          solModifier]
    }

    /// A built-in source of modifiers (Specification.Source).
    public final class Source: FreeColSpecObjectType {
        public required init(id: String?, specification: Specification?) {
            super.init(id: id, specification: specification)
        }
        public override var xmlTagName: String { "source" }
    }

    // MARK: State

    public internal(set) var id: String?
    public internal(set) var version: String?
    public internal(set) var difficultyLevel: String?
    /// Set once loading is complete; unknown type ids are then errors.
    public internal(set) var isInitialized = false

    var allTypes = JavaHashMap<String, FreeColSpecObjectType>(
        initialCapacity: 256, javaHash: JavaString.hashCode)
    var allAbilities: [String: [Ability]] = [:]
    var allModifiers: [String: [Modifier]] = [:]
    /// Every option by id, and every option group by id (Java's
    /// allOptions and allOptionGroups HashMaps).
    var allOptions = JavaHashMap<String, AbstractOption>(javaHash: JavaString.hashCode)
    var allOptionGroups = JavaHashMap<String, OptionGroup>(javaHash: JavaString.hashCode)
    private var fakeUnitChangeIds = 0
    /// Finds parent rule sets and compatibility files while loading.
    var source: RulesSource?

    /// The turn calendar from the game options (Java's static Turn
    /// settings, set by clean()).
    public internal(set) var turnCalendar = TurnCalendar.standard
    /// The first turns of the three ages.
    public internal(set) var ages = [1, 0, 0]

    public internal(set) var gameAbilities: [Ability] = []
    public internal(set) var specialModifiers: [Modifier] = []
    public internal(set) var buildingTypeList: [BuildingType] = []
    public internal(set) var disasters: [Disaster] = []
    public internal(set) var europeanNationTypes: [EuropeanNationType] = []
    public internal(set) var events: [Event] = []
    public internal(set) var foundingFathers: [FoundingFather] = []
    public internal(set) var goodsTypeList: [GoodsType] = []
    public internal(set) var indianNationTypes: [IndianNationType] = []
    public internal(set) var nations: [Nation] = []
    public internal(set) var resourceTypeList: [ResourceType] = []
    public internal(set) var rolesList: [Role] = []
    public internal(set) var tileTypeList: [TileType] = []
    public internal(set) var tileImprovementTypeList: [TileImprovementType] = []
    public internal(set) var unitChangeTypeList: [UnitChangeType] = []
    public internal(set) var unitTypeList: [UnitType] = []

    // Derived in clean().
    public internal(set) var storableGoodsTypeList: [GoodsType] = []
    public internal(set) var farmedGoodsTypeList: [GoodsType] = []
    public internal(set) var foodGoodsTypeList: [GoodsType] = []
    public internal(set) var newWorldGoodsTypeList: [GoodsType] = []
    public internal(set) var newWorldLuxuryGoodsTypeList: [GoodsType] = []
    public internal(set) var libertyGoodsTypeList: [GoodsType] = []
    public internal(set) var immigrationGoodsTypeList: [GoodsType] = []
    public internal(set) var rawBuildingGoodsTypeList: [GoodsType] = []
    public internal(set) var rawMaterialsForUnstorableBuildingMaterials: [GoodsType] = []
    public internal(set) var rawMaterialsForStorableBuildingMaterials: [GoodsType] = []
    public internal(set) var europeanNations: [Nation] = []
    public internal(set) var refNations: [Nation] = []
    public internal(set) var indianNations: [Nation] = []
    public internal(set) var nationTypes: [NationType] = []
    public internal(set) var refNationTypes: [EuropeanNationType] = []
    public internal(set) var buildableUnitTypes: [UnitType] = []
    var experts: [ObjectIdentifier: UnitType] = [:]
    private var unitTypesTrainedInEurope: [UnitType] = []
    private var unitTypesPurchasedInEurope: [UnitType] = []
    public internal(set) var fastestLandUnitType: UnitType?
    public internal(set) var fastestNavalUnitType: UnitType?
    private var defaultUnitTypes: [UnitType] = []
    private var militaryRoles: [Role]?

    /// An empty specification with the built-in sources.
    public init() {
        for sourceId in SourceId.all {
            allTypes.put(sourceId, Source(id: sourceId, specification: nil))
        }
    }

    /// An empty specification with an id, for tests and tools.
    public convenience init(id: String?) {
        self.init()
        self.id = id
    }

    /// Read a resolved specification document.
    ///
    /// - Parameters:
    ///   - data: The XML, with a freecol-specification root.
    ///   - source: Where to find the rule set it extends, if any.
    ///
    /// As Java's Specification(InputStream): read, prepare with the
    /// document's difficulty level, then clean.
    public convenience init(resolved data: Data, source: RulesSource? = nil) throws {
        self.init()
        self.source = source
        try load(data)
        try prepare(advantages: nil, difficulty: difficultyLevel)
        clean()
        isInitialized = true
    }

    /// Read the specification element a reader is on, as saved games
    /// hold it (Java's Specification(FreeColXMLReader)): read, prepare
    /// with its difficulty level, then clean.
    public convenience init(reading xr: FreeColXMLReader) throws {
        self.init()
        try readFromXML(xr)
        try prepare(advantages: nil, difficulty: difficultyLevel)
        clean()
        isInitialized = true
    }

    /// Read a document into this specification (Java's load).
    func load(_ data: Data) throws {
        let xr = try FreeColXMLReader(data: data)
        try xr.nextTag()
        try readFromXML(xr)
    }

    /// The next number for a unit change without an id.
    func nextFakeUnitChangeId() -> Int {
        fakeUnitChangeIds += 1
        return fakeUnitChangeIds
    }

    // MARK: Types

    /// Any type by id.
    public func getType(_ id: String?) -> FreeColSpecObjectType? {
        id.flatMap { allTypes[$0] }
    }

    /// A type by id, if it exists and has the given class.  Java throws
    /// for the wrong class; this returns nil.
    public func getAlreadyInitializedType<T: FreeColSpecObjectType>(_ id: String?,
                                                                    _ type: T.Type) -> T? {
        getType(id) as? T
    }

    /// A type by id, created as a forward declaration if not yet known.
    /// Once loading is complete an unknown id is an error.
    public func findType<T: FreeColSpecObjectType>(_ id: String, _ type: T.Type) throws -> T {
        if let existing = getType(id) {
            guard let typed = existing as? T else {
                throw FreeColXMLError("\(id) is a \(Swift.type(of: existing)), not a \(T.self)")
            }
            return typed
        }
        if isInitialized { throw FreeColXMLError("Undefined FCGOT: \(id)") }
        let created = T(id: id, specification: self)
        allTypes.put(id, created)
        return created
    }

    /// Types of a class that have, or lack, any of some abilities, in
    /// Java's HashMap order of the type registry.
    public func types<T: FreeColSpecObjectType>(_ type: T.Type, withAnyAbility abilities: [String]) -> [T] {
        allTypes.values.compactMap { $0 as? T }
            .filter { t in !t.isAbstractType && abilities.contains { a in t.hasAbility(a) } }
    }

    public func types<T: FreeColSpecObjectType>(_ type: T.Type, withoutAbilities abilities: [String]) -> [T] {
        allTypes.values.compactMap { $0 as? T }
            .filter { t in !t.isAbstractType && !abilities.contains { a in t.hasAbility(a) } }
    }

    /// The rule types whose abilities with an id have a value.
    public func typesProviding(_ id: String, _ value: Bool) -> [FreeColSpecObjectType] {
        abilities(id).filter { $0.value == value }.compactMap { $0.source as? FreeColSpecObjectType }
    }

    // MARK: Abilities and modifiers

    /// Record an ability under its id.
    public func addAbility(_ ability: Ability) {
        allAbilities[ability.id ?? "", default: []].append(ability)
    }

    /// Note that an ability id exists.
    public func addAbility(_ id: String) {
        if allAbilities[id] == nil { allAbilities[id] = [] }
    }

    /// Every ability recorded with an id.
    public func abilities(_ id: String) -> [Ability] {
        allAbilities[id] ?? []
    }

    /// Whether any recorded ability with an id is true.
    public func hasAbility(_ id: String) -> Bool {
        abilities(id).contains { $0.value }
    }

    /// Record a modifier under its id.
    public func addModifier(_ modifier: Modifier) {
        allModifiers[modifier.id ?? "", default: []].append(modifier)
    }

    /// Every modifier recorded with an id.
    public func modifiers(_ id: String) -> [Modifier] {
        allModifiers[id] ?? []
    }

    // MARK: Options (Java's OptionContainer)

    /// Every registered option by id (Java's allOptions).
    public var registeredOptions: [String: AbstractOption] {
        Dictionary(uniqueKeysWithValues: allOptions.entries.map { ($0.key, $0.value) })
    }

    /// Every registered option group by id (Java's allOptionGroups).
    public var registeredOptionGroups: [String: OptionGroup] {
        Dictionary(uniqueKeysWithValues: allOptionGroups.entries.map { ($0.key, $0.value) })
    }

    /// The option with an id, if it has the given kind.
    public func option<T: AbstractOption>(_ id: String?, as type: T.Type) -> T? {
        id.flatMap { allOptions[$0] } as? T
    }

    /// Whether there is an option of a kind with an id.
    public func hasOption<T: AbstractOption>(_ id: String?, _ type: T.Type) -> Bool {
        option(id, as: T.self) != nil
    }

    /// Whether there is any option with an id.
    public func hasOption(_ id: String) -> Bool {
        allOptions[id] != nil
    }

    /// The option group with an id.
    public func optionGroup(_ id: String?) -> OptionGroup? {
        id.flatMap { allOptionGroups[$0] }
    }

    public func getString(_ id: String) -> String? { option(id, as: StringOption.self)?.value }
    public func getText(_ id: String) -> String? { option(id, as: TextOption.self)?.value }
    public func getBoolean(_ id: String) -> Bool { option(id, as: BooleanOption.self)?.value ?? false }
    public func getInteger(_ id: String) -> Int? { option(id, as: IntegerOption.self)?.value }
    public func getPercentage(_ id: String) -> Int? { option(id, as: PercentageOption.self)?.value }
    public func getRange(_ id: String) -> Int? { option(id, as: RangeOption.self)?.value }
    public func getSelection(_ id: String) -> Int? { option(id, as: SelectOption.self)?.value }
    /// Set an option's value (the OptionContainer setters).  It is an
    /// error if there is no such option.
    public func setBoolean(_ id: String, _ value: Bool) {
        option(id, as: BooleanOption.self)!.setValue(value)
    }

    public func setInteger(_ id: String, _ value: Int) {
        option(id, as: IntegerOption.self)!.setValue(value)
    }

    public func setIntegerMinimum(_ id: String, _ value: Int) {
        option(id, as: IntegerOption.self)!.minimumValue = value
    }

    public func getUnitList(_ id: String) -> [AbstractUnit] {
        option(id, as: UnitListOption.self)?.optionValues ?? []
    }

    /// Register the options of a group, and its groups (Java's
    /// addOptionGroup).
    func addOptionGroup(_ group: OptionGroup, recursive: Bool) {
        for o in group.options {
            if let g = o as? OptionGroup {
                allOptionGroups.put(g.id ?? "", g)
                if recursive { addOptionGroup(g, recursive: true) }
            } else {
                allOptions.put(o.id ?? "", o)
            }
        }
    }

    /// Register one option.
    func addAbstractOption(_ option: AbstractOption) {
        allOptions.put(option.id ?? "", option)
    }

    /// The difficulty levels, in order.
    public var difficultyLevels: [OptionGroup] {
        (optionGroup("difficultyLevels")?.options ?? []).compactMap { $0 as? OptionGroup }
    }

    /// The group of a difficulty level.
    public func difficultyOptionGroup(_ id: String?) -> OptionGroup? {
        difficultyLevels.first { $0.id == id }
    }

    /// Make a difficulty level's options the current ones.
    public func applyDifficultyLevel(_ level: OptionGroup?) {
        guard let level else { return } // Java warns.
        addOptionGroup(level, recursive: true)
        difficultyLevel = level.id
    }

    /// Apply a difficulty level by id.
    public func applyDifficultyLevel(_ id: String) {
        applyDifficultyLevel(difficultyOptionGroup(id))
    }

    /// The game options group.
    public var gameOptions: OptionGroup? { optionGroup(GameOptions.tag) }

    /// The map generator options group.
    public var mapGeneratorOptions: OptionGroup? { optionGroup(MapGeneratorOptions.tag) }

    /// The age of a turn: 0, 1 or 2, or -1 before the first.
    public func age(_ turn: Turn) -> Int {
        let n = turn.number
        return n < ages[0] ? -1 : n < ages[1] ? 0 : n < ages[2] ? 1 : 2
    }

    /// The opening sell price of goods: the lower of the minimum and
    /// maximum price options if present, otherwise the goods' own.
    public func getInitialPrice(_ goodsType: GoodsType?) -> Int {
        guard let goodsType else { return 0 }
        let suffix = goodsType.suffix(afterPrefix: "model.goods.") ?? ""
        if let lo = getInteger("model.option.\(suffix).minimumPrice"),
           let hi = getInteger("model.option.\(suffix).maximumPrice") {
            return min(lo, hi)
        }
        return goodsType.initialSellPrice
    }

    // MARK: Lookups

    public func getBuildingType(_ id: String?) -> BuildingType? { getAlreadyInitializedType(id, BuildingType.self) }
    public func getDisaster(_ id: String?) -> Disaster? { getAlreadyInitializedType(id, Disaster.self) }
    public func getEvent(_ id: String?) -> Event? { getAlreadyInitializedType(id, Event.self) }
    public func getFoundingFather(_ id: String?) -> FoundingFather? { getAlreadyInitializedType(id, FoundingFather.self) }
    public func getGoodsType(_ id: String?) -> GoodsType? { getAlreadyInitializedType(id, GoodsType.self) }
    public func getTileImprovementType(_ id: String?) -> TileImprovementType? { getAlreadyInitializedType(id, TileImprovementType.self) }
    public func getNationType(_ id: String?) -> NationType? { getAlreadyInitializedType(id, NationType.self) }
    public func getNation(_ id: String?) -> Nation? { getAlreadyInitializedType(id, Nation.self) }
    public func getResourceType(_ id: String?) -> ResourceType? { getAlreadyInitializedType(id, ResourceType.self) }
    public func getRole(_ id: String?) -> Role? { getAlreadyInitializedType(id, Role.self) }
    public func getTileType(_ id: String?) -> TileType? { getAlreadyInitializedType(id, TileType.self) }
    public func getUnitType(_ id: String?) -> UnitType? { getAlreadyInitializedType(id, UnitType.self) }

    public var primaryFoodType: GoodsType? { getGoodsType(Specification.defaultFoodType) }
    public var defaultNationType: NationType? { getNationType(Specification.defaultNationType) }
    public var unknownEnemyNation: Nation? { getNation(Nation.unknownNationId) }
    public var defaultRole: Role? { getRole(Specification.defaultRoleId) }
    public var hillsTileTypeList: [TileType] { tileTypeList.filter(\.isHills) }
    public var mountainsTileTypeList: [TileType] { tileTypeList.filter(\.isMountains) }

    /// The European nation types players can choose.
    public var visibleEuropeanNationTypes: [EuropeanNationType] {
        europeanNationTypes.filter { $0.id != "model.nationType.optionOnly" }
    }

    /// The offensive roles, strongest first (a stable sort, as Java's).
    public var militaryRolesList: [Role] {
        if militaryRoles == nil {
            militaryRoles = rolesList.filter(\.isOffensive)
                .enumerated()
                .sorted { a, b in
                    let c = Role.compareMilitary(a.element, b.element)
                    return c != 0 ? c < 0 : a.offset < b.offset
                }
                .map(\.element)
        }
        return militaryRoles!
    }

    /// The roles REF units can take.
    public func refRoles(naval: Bool) -> [Role] {
        (naval ? [defaultRole].compactMap { $0 } : militaryRolesList)
            .filter { $0.requiresAbility(Ability.refUnit) }
    }

    /// The first role with an ability.
    public func roleWithAbility(_ id: String) -> Role? {
        rolesList.first { $0.hasAbility(id) }
    }

    public var missionaryRole: Role? { roleWithAbility(Ability.establishMission) }
    public var pioneerRole: Role? { roleWithAbility(Ability.improveTerrain) }
    public var scoutRole: Role? { roleWithAbility(Ability.speakWithChief) }

    /// The unit change type with an id.
    /// Add a unit change type made in code.
    public func addUnitChangeType(_ uct: UnitChangeType) {
        unitChangeTypeList.append(uct)
    }

    public func getUnitChangeType(_ id: String?) -> UnitChangeType? {
        unitChangeTypeList.first { $0.id == id }
    }

    /// The changes of a kind from a unit type.
    public func unitChanges(_ id: String, _ from: UnitType?) -> [UnitTypeChange] {
        getUnitChangeType(id)?.unitChanges(from) ?? []
    }

    /// The first change of a kind from a type, to a type if given.
    public func unitChange(_ id: String, _ from: UnitType?, _ to: UnitType? = nil) -> UnitTypeChange? {
        getUnitChangeType(id)?.unitChange(from, to)
    }

    /// The turns of training a teacher needs for a student.
    public func neededTurnsOfTraining(_ teacher: UnitType, _ student: UnitType) -> Int? {
        guard let learn = student.teachingType(teacher) else { return nil }
        return unitChange(UnitChangeType.education, student, learn)?.turns
    }

    /// The basic colonist (Java notes this should go).
    public var defaultUnitType: UnitType? {
        getUnitType("model.unit.freeColonist")
    }

    /// The default unit type for a kind of nation.
    public func defaultUnitType(_ nationType: NationType?) -> UnitType? {
        let indian = nationType?.isIndian == true
        let ref = nationType?.isREF == true
        let match = defaultUnitTypes.first { ut in
            let bornIndian = ut.hasAbility(Ability.bornInIndianSettlement)
            let refUnit = ut.hasAbility(Ability.refUnit)
            if nationType == nil || !(indian || ref) { return !bornIndian && !refUnit }
            if indian { return bornIndian && !refUnit }
            return !bornIndian && refUnit
        }
        return match ?? defaultUnitType
    }

    /// The expert unit for producing goods.
    public func expert(producing goodsType: GoodsType) -> UnitType? {
        experts[ObjectIdentifier(goodsType)]
    }

    public func unitTypes(withAnyAbility abilities: String...) -> [UnitType] {
        types(UnitType.self, withAnyAbility: abilities)
    }

    public func unitTypes(withoutAbilities abilities: String...) -> [UnitType] {
        types(UnitType.self, withoutAbilities: abilities)
    }

    /// The REF unit types, naval or not, in registry order.
    public func refUnitTypes(naval: Bool) -> [UnitType] {
        unitTypes(withAnyAbility: Ability.refUnit).filter { $0.isNaval == naval }
    }

    // MARK: Reading

    /// The type list each section fills, and the index of the next type
    /// in it (Java keeps one reader per section, so the second
    /// european-nation-types section continues the numbering).
    private var sectionIndexes: [String: Int] = [:]

    func readFromXML(_ xr: FreeColXMLReader) throws {
        let newId = xr.readId()
        if id == nil { id = newId }
        if difficultyLevel == nil {
            difficultyLevel = xr.attribute("difficulty-level", default: nil as String?)
                ?? xr.attribute("difficultyLevel", default: nil as String?)
        }
        if version == nil { version = xr.attribute("version", default: nil as String?) }
        if let parentId = xr.attribute("extends", default: nil as String?) {
            // Read the parent rule set first, into this specification.
            guard let source, let parent = try source.rulesData(parentId) else {
                throw FreeColXMLError("Failed to open parent specification: \(parentId)")
            }
            try load(parent)
            isInitialized = false
        }
        while try xr.moreTags() {
            let section = xr.localName
            switch section {
            case "equipment-types":
                // @compat 0.11.0
                try xr.swallowTag(section)
            case "building-types": try readTypes(xr, section, BuildingType.self) { self.buildingTypeList.append($0) }
            case "disasters": try readTypes(xr, section, Disaster.self) { self.disasters.append($0) }
            case "european-nation-types":
                try readTypes(xr, section, EuropeanNationType.self) { self.europeanNationTypes.append($0) }
            case "events": try readTypes(xr, section, Event.self) { self.events.append($0) }
            case "founding-fathers": try readTypes(xr, section, FoundingFather.self) { self.foundingFathers.append($0) }
            case "goods-types": try readTypes(xr, section, GoodsType.self) { self.goodsTypeList.append($0) }
            case "indian-nation-types":
                try readTypes(xr, section, IndianNationType.self) { self.indianNationTypes.append($0) }
            case "nations": try readTypes(xr, section, Nation.self) { self.nations.append($0) }
            case "resource-types": try readTypes(xr, section, ResourceType.self) { self.resourceTypeList.append($0) }
            case "roles": try readTypes(xr, section, Role.self) { self.rolesList.append($0) }
            case "tile-types": try readTypes(xr, section, TileType.self) { self.tileTypeList.append($0) }
            case "tile-improvement-types", "tileimprovement-types":
                try readTypes(xr, "tile-improvement-types", TileImprovementType.self) {
                    self.tileImprovementTypeList.append($0)
                }
            case "unit-change-types":
                try readTypes(xr, section, UnitChangeType.self) { self.unitChangeTypeList.append($0) }
            case "unit-types": try readTypes(xr, section, UnitType.self) { self.unitTypeList.append($0) }
            case "abilities":
                while try xr.moreTags() {
                    let a = try Ability(xr, specification: self)
                    addAbility(a)
                    gameAbilities.append(a)
                }
            case "modifiers":
                while try xr.moreTags() {
                    let m = try Modifier(xr, specification: self)
                    addModifier(m)
                    specialModifiers.append(m)
                }
            case "options":
                try readOptions(xr)
            default:
                // Java logs "No reader found" and goes on; the reader
                // must still skip the element.
                try xr.swallowTag(section)
            }
        }
    }

    /// Port of Specification.TypeReader.
    private func readTypes<T: FreeColSpecObjectType>(_ xr: FreeColXMLReader, _ section: String,
                                                     _ type: T.Type, add: (T) -> Void) throws {
        var index = sectionIndexes[section] ?? 0
        defer { sectionIndexes[section] = index }
        var seen = Set(listForSection(section).map(ObjectIdentifier.init))
        while try xr.moreTags() {
            let tag = xr.localName
            guard let typeId = xr.readId() else {
                // Java warns about a missing id and moves on.
                try xr.swallowTag(tag)
                continue
            }
            if tag == "delete" {
                // Java warns if there is nothing to delete.
                if let removed = allTypes.removeValue(forKey: typeId) {
                    removeFromList(section, removed)
                    seen.remove(ObjectIdentifier(removed))
                }
                try xr.closeTag(tag)
                continue
            }
            let object: T = getAlreadyInitializedType(typeId, T.self) ?? {
                let created = T(id: typeId, specification: self)
                allTypes.put(typeId, created)
                return created
            }()
            if object.id != nil && xr.attribute("preserve", default: false) {
                try object.readChildren(xr)
            } else {
                try object.readFromXML(xr)
            }
            if !object.isAbstractType && !seen.contains(ObjectIdentifier(object)) {
                add(object)
                seen.insert(ObjectIdentifier(object))
                object.index = index
                index += 1
            }
        }
    }

    private func listForSection(_ section: String) -> [FreeColSpecObjectType] {
        switch section {
        case "building-types": buildingTypeList
        case "disasters": disasters
        case "european-nation-types": europeanNationTypes
        case "events": events
        case "founding-fathers": foundingFathers
        case "goods-types": goodsTypeList
        case "indian-nation-types": indianNationTypes
        case "nations": nations
        case "resource-types": resourceTypeList
        case "roles": rolesList
        case "tile-types": tileTypeList
        case "tile-improvement-types": tileImprovementTypeList
        case "unit-change-types": unitChangeTypeList
        case "unit-types": unitTypeList
        default: []
        }
    }

    /// Port of Specification.OptionReader: each top-level group is read
    /// into the existing group with its id, or a new one, then its
    /// options are registered.
    private func readOptions(_ xr: FreeColXMLReader) throws {
        while try xr.moreTags() {
            let tag = xr.localName
            let recursive = xr.attribute("recursive", default: true)
            guard tag == OptionGroup.tag else {
                // Java warns and steps on.
                try xr.nextTag()
                continue
            }
            let groupId = xr.readId() ?? ""
            let group = allOptionGroups[groupId] ?? {
                let g = OptionGroup(id: groupId, specification: self)
                allOptionGroups.put(groupId, g)
                return g
            }()
            try group.readFromXML(xr)
            addOptionGroup(group, recursive: recursive)
        }
    }

    /// Remove a deleted type from its section's list.
    private func removeFromList(_ section: String, _ type: FreeColSpecObjectType) {
        switch section {
        case "building-types": buildingTypeList.removeAll { $0 === type }
        case "disasters": disasters.removeAll { $0 === type }
        case "european-nation-types": europeanNationTypes.removeAll { $0 === type }
        case "events": events.removeAll { $0 === type }
        case "founding-fathers": foundingFathers.removeAll { $0 === type }
        case "goods-types": goodsTypeList.removeAll { $0 === type }
        case "indian-nation-types": indianNationTypes.removeAll { $0 === type }
        case "nations": nations.removeAll { $0 === type }
        case "resource-types": resourceTypeList.removeAll { $0 === type }
        case "roles": rolesList.removeAll { $0 === type }
        case "tile-types": tileTypeList.removeAll { $0 === type }
        case "tile-improvement-types": tileImprovementTypeList.removeAll { $0 === type }
        case "unit-change-types": unitChangeTypeList.removeAll { $0 === type }
        case "unit-types": unitTypeList.removeAll { $0 === type }
        default: break
        }
    }

    // MARK: After loading

    /// Work out everything derived from the types and options (Java's
    /// clean()): the goods, nation and unit lists, option choices, the
    /// turn calendar, the ages and the customs house coast rule.
    func clean() {
        GoodsType.setDerivedAttributes(self)
        storableGoodsTypeList = goodsTypeList.filter(\.isStorable)
        farmedGoodsTypeList = goodsTypeList.filter(\.isFarmed)
        foodGoodsTypeList = goodsTypeList.filter(\.isFoodType)
        newWorldGoodsTypeList = goodsTypeList.filter(\.isNewWorldGoodsType)
        newWorldLuxuryGoodsTypeList = goodsTypeList.filter { $0.isNewWorldGoodsType && $0.isNewWorldLuxuryType }
        libertyGoodsTypeList = goodsTypeList.filter(\.isLibertyType)
        immigrationGoodsTypeList = goodsTypeList.filter(\.isImmigrationType)
        rawBuildingGoodsTypeList = goodsTypeList.filter { $0.isRawBuildingMaterial && !$0.isFoodType }
        rawMaterialsForStorableBuildingMaterials = rawBuildingGoodsTypeList
            .filter { !$0.isRawMaterialForUnstorableBuildingMaterial }
        rawMaterialsForUnstorableBuildingMaterials = goodsTypeList
            .filter { $0.isRawMaterialForUnstorableBuildingMaterial && !$0.isFoodType }

        refNations = []
        europeanNations = []
        indianNations = []
        for nation in nations where !nation.isUnknownEnemy {
            if nation.type?.isEuropean == true {
                if nation.type?.isREF == true { refNations.append(nation) } else { europeanNations.append(nation) }
            } else {
                indianNations.append(nation)
            }
        }

        nationTypes = indianNationTypes as [NationType] + europeanNationTypes as [NationType]
        refNationTypes += europeanNationTypes.filter(\.isREF)
        europeanNationTypes.removeAll { t in refNationTypes.contains { $0 === t } }

        experts = [:]
        unitTypesTrainedInEurope = []
        unitTypesPurchasedInEurope = []
        defaultUnitTypes = []
        var bestLand = -1, bestNaval = -1
        for unitType in unitTypeList {
            if unitType.isDefaultUnitType { defaultUnitTypes.append(unitType) }
            // Java never clears this list, so repeated cleans duplicate it.
            if unitType.needsGoodsToBuild && !unitType.hasAbility(Ability.bornInColony) {
                buildableUnitTypes.append(unitType)
            }
            if let goods = unitType.expertProduction { experts[ObjectIdentifier(goods)] = unitType }
            if unitType.hasPrice {
                if unitType.skill > 0 {
                    unitTypesTrainedInEurope.append(unitType)
                } else if !unitType.hasSkill {
                    unitTypesPurchasedInEurope.append(unitType)
                }
            }
            if unitType.isNaval {
                if bestNaval < unitType.movement {
                    bestNaval = unitType.movement
                    fastestNavalUnitType = unitType
                }
            } else if bestLand < unitType.movement {
                bestLand = unitType.movement
                fastestLandUnitType = unitType
            }
        }
        militaryRoles = nil

        for og in allOptionGroups.values { og.generateChoices() }

        // Java's Turn.initialize, with Java's int defaults for missing
        // options (it would throw).
        turnCalendar = TurnCalendar(startingYear: getInteger(GameOptions.startingYear) ?? 0,
                                    seasonYear: getInteger(GameOptions.seasonYear) ?? 0,
                                    seasonNumber: getInteger(GameOptions.seasons) ?? 0)
        var badAges = !hasOption(GameOptions.ages, TextOption.self)
        if !badAges, let text = getText(GameOptions.ages) {
            let parts = text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            badAges = parts.count != Specification.numberOfAges - 1
            if !badAges {
                if let y1 = JavaString.parseInt(parts[0]), let y2 = JavaString.parseInt(parts[1]) {
                    ages[0] = 1
                    ages[1] = turnCalendar.turnNumber(year: Int(y1))
                    ages[2] = turnCalendar.turnNumber(year: Int(y2))
                    if ages[1] < 1 || ages[2] < 1 {
                        badAges = true
                    } else if ages[1] > ages[2] {
                        ages.swapAt(1, 2)
                    }
                } else {
                    badAges = true
                }
            }
        } else {
            badAges = true
        }
        if badAges {
            // Java warns about bad ages.
            ages = [1, turnCalendar.turnNumber(year: 1600), turnCalendar.turnNumber(year: 1700)]
        }

        let customsOnCoast = getBoolean(GameOptions.customsOnCoast)
        for a in getBuildingType("model.building.customHouse")?.abilities(Ability.coastalOnly) ?? [] {
            a.value = customsOnCoast
        }
    }
}

extension FreeColXMLReader {

    /// A type named by an attribute, created as a forward declaration if
    /// needed (Java's getType), or nil if the attribute is missing.
    public func getType<T: FreeColSpecObjectType>(_ spec: Specification, _ attribute: String,
                                                  _ type: T.Type) throws -> T? {
        // @compat 0.11.x: "id" attributes get their old forms upgraded.
        let value = attribute == "id" ? readId() : self.attribute(attribute, default: nil as String?)
        return try value.map { try spec.findType($0, T.self) }
    }

    /// A type named by an attribute that must already be read, or nil if
    /// the attribute is missing (Java's getAlreadyInitializedType, which
    /// throws for a type not yet read).
    public func getAlreadyInitializedType<T: FreeColSpecObjectType>(_ spec: Specification,
                                                                    _ attribute: String,
                                                                    _ type: T.Type) throws -> T? {
        guard let value = self.attribute(attribute, default: nil as String?) else { return nil }
        guard let found = spec.getAlreadyInitializedType(value, T.self) else {
            throw FreeColXMLError("The object \"\(value)\" of type \"\(T.self)\" was referenced"
                + " from a \"\(attribute)\" attribute before being initialized.")
        }
        return found
    }
}

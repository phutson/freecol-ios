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

extension FreeColObject {
    /// Java's hashCode for an object compared by id
    /// (FreeColObject.hashCode, via Utils.hashCode: 31 for no id).
    public var javaHashCode: Int32 {
        id.map(JavaString.hashCode) ?? 31
    }
}

/// Counts by rule type (common/model/TypeCountMap), iterating in
/// Java's HashMap order so lists made from it come out as Java's do.
public struct TypeCountMap<T: FreeColSpecObjectType> {

    private var values = JavaHashMap<T, Int>(javaHash: { $0.javaHashCode })

    public init() {}

    /// The count for a type, or 0.
    public func count(_ type: T?) -> Int {
        type.flatMap { values[$0] } ?? 0
    }

    /// Add to a count, removing the entry if a matching subtraction
    /// brings it to zero (Java's incrementCount).
    public mutating func increment(_ type: T, by amount: Int) {
        if let old = values[type] {
            if old == -amount {
                values.removeValue(forKey: type)
            } else {
                values.put(type, old + amount)
            }
        } else {
            values.put(type, amount)
        }
    }

    /// The types, in Java's order.
    public var types: [T] {
        values.keys
    }

    /// Copy every count from another map (Java's putAll).
    public mutating func putAll(_ other: TypeCountMap<T>) {
        values.putAll(other.values)
    }

    public var isEmpty: Bool {
        values.isEmpty
    }
}

/// A kind of unit (common/model/UnitType).
///
/// Not yet ported: the build queue index methods (for the UI).
public final class UnitType: BuildableType {

    public static let tag = "unit-type"

    public static let defaultOffence = 0
    public static let defaultDefence = 1

    public private(set) var baseOffence = UnitType.defaultOffence
    public private(set) var baseDefence = UnitType.defaultDefence
    public var space = 0
    public private(set) var isDefaultUnitType = false
    public var hitPoints = 0
    private var spaceTakenValue = 1
    public var skill = Constants.undefined
    public private(set) var price = Constants.undefined
    public var mercenaryPrice = Constants.undefined
    public private(set) var movement = 3
    public var lineOfSight = 1
    public private(set) var recruitProbability = 0
    public private(set) var expertProduction: GoodsType?
    public private(set) var scoreValue = 0
    public private(set) var maximumExperience = 0
    public var attackRange = 0
    public private(set) var maximumAttrition = Constants.infinity
    public private(set) var priority = ConsumerPriority.unit
    public private(set) var skillTaught: UnitType?
    public private(set) var defaultRole: Role?
    private var consumption: TypeCountMap<GoodsType>?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
        defaultRole = specification?.defaultRole
    }

    public override var xmlTagName: String {
        UnitType.tag
    }

    /// The unit type methods scopes can name (Java finds any getter by
    /// reflection; the ModifierTest names getLineOfSight).
    public override func scopeMethodValue(_ methodName: String) -> String? {
        switch methodName {
        case "getLineOfSight": "\(lineOfSight)"
        case "getSpace": "\(space)"
        case "getSpaceTaken": "\(spaceTaken)"
        case "getHitPoints": "\(hitPoints)"
        case "getSkill": "\(skill)"
        case "getMovement": "\(movement)"
        case "getPrice": "\(price)"
        default: super.scopeMethodValue(methodName)
        }
    }

    /// The message key for this unit working.
    public var workingAsKey: String {
        "\(id ?? "null").workingAs"
    }

    public var canCarryUnits: Bool { hasAbility(Ability.carryUnits) }
    public var canCarryGoods: Bool { hasAbility(Ability.carryGoods) }
    public var canCarryTreasure: Bool { hasAbility(Ability.carryTreasure) }

    /// The offence with this type's own modifiers.
    public var offence: Double {
        Double(apply(Float(baseOffence), turn: nil, Modifier.offence))
    }

    public var isOffensive: Bool {
        baseOffence > UnitType.defaultOffence
    }

    /// The defence with this type's own modifiers.
    public var defence: Double {
        Double(apply(Float(baseDefence), turn: nil, Modifier.defence))
    }

    public var isDefensive: Bool {
        baseDefence > UnitType.defaultDefence
    }

    /// The space this unit takes on a carrier: at least one more than it
    /// can carry itself.
    public var spaceTaken: Int {
        get { max(spaceTakenValue, space + 1) }
        set { spaceTakenValue = newValue }
    }

    public var isRecruitable: Bool {
        recruitProbability > 0
    }

    public var hasMaximumAttrition: Bool {
        maximumAttrition != Constants.infinity
    }

    /// The roles this unit type is the expert for.
    public var expertRoles: [Role] {
        (specification?.rolesList ?? []).filter { $0.expertUnit === self }
    }

    /// The role id to show this unit type with.
    public var displayRoleId: String {
        expertRoles.first?.id ?? Specification.defaultRoleId
    }

    /// The type this unit becomes when taught by a teacher, possibly in
    /// steps, or nil if it cannot learn from it.
    public func teachingType(_ teacherType: UnitType) -> UnitType? {
        guard let spec = specification, let taught = teacherType.skillTaught else { return nil }
        let taughtLevel = taught.skill
        if skill >= taughtLevel { return nil }
        var todo: [UnitType] = []
        for uc in spec.unitChanges(UnitChangeType.education, self) {
            guard let to = uc.to else { continue }
            if to === taught { return taught }
            if to.skill < taughtLevel { todo.append(to) }
        }
        return todo.first { $0.teachingType(teacherType) != nil }
    }

    public var isNaval: Bool { hasAbility(Ability.navalUnit) }
    public var isPerson: Bool { hasAbility(Ability.person) }
    public var canBuildColony: Bool { hasAbility(Ability.foundColony) }
    public var canMoveToHighSeas: Bool { isNaval }
    public var hasSkill: Bool { skill != Constants.undefined }
    public var hasPrice: Bool { price != Constants.undefined }

    /// How much of a goods type this unit consumes each turn.
    public func consumption(of goodsType: GoodsType?) -> Int {
        consumption?.count(goodsType) ?? 0
    }

    /// The goods consumed, in Java's HashMap order of the consumption map.
    public var consumedGoods: [AbstractGoods] {
        guard let consumption else { return [] }
        return consumption.types.filter { consumption.count($0) != 0 }
            .map { AbstractGoods($0, consumption.count($0)) }
    }

    /// The modifiers to consumption of a goods type.
    public func consumptionModifiers(_ id: String?) -> [Modifier] {
        modifiers(id)
    }

    /// Units that are not people need something in the colony (or
    /// assumed built) with the build ability for them.
    public override func canBeBuiltInColony(_ colony: Colony, _ assumeBuilt: [BuildableType]) -> Colony.NoBuildReason {
        if !hasAbility(Ability.person) && !colony.hasAbility(Ability.build, for: self)
            && !assumeBuilt.contains(where: { $0.hasAbility(Ability.build, for: self) }) {
            return .missingBuildAbility
        }
        return .none
    }

    // MARK: Reading XML

    /// The int setters Java's UnitType has, for partial reads (values
    /// parsed with Integer.valueOf).
    public override func setPartialAttribute(_ name: String, _ value: String) -> Bool {
        guard let v = JavaString.parseInt(value).map(Int.init) else {
            return super.setPartialAttribute(name, value)
        }
        switch name {
        case "line-of-sight": lineOfSight = v
        case "space": space = v
        case "hit-points": hitPoints = v
        case "space-taken": spaceTaken = v
        case "skill": skill = v
        case "mercenary-price": mercenaryPrice = v
        case "attack-range": attackRange = v
        default: return super.setPartialAttribute(name, value)
        }
        return true
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        let parent = try spec.flatMap { try xr.getAlreadyInitializedType($0, "extends", UnitType.self) } ?? self
        func pick(_ old: String, _ new: String) -> String {
            xr.hasAttribute(old) ? old : new
        }
        baseOffence = xr.attribute("offence", default: parent.baseOffence)
        baseDefence = xr.attribute("defence", default: parent.baseDefence)
        isDefaultUnitType = xr.attribute(pick("defaultUnit", "default-unit"), default: false)
        movement = xr.attribute("movement", default: parent.movement)
        lineOfSight = xr.attribute(pick("lineOfSight", "line-of-sight"), default: parent.lineOfSight)
        scoreValue = xr.attribute(pick("scoreValue", "score-value"), default: parent.scoreValue)
        space = xr.attribute("space", default: parent.space)
        hitPoints = xr.attribute(pick("hitPoints", "hit-points"), default: parent.hitPoints)
        attackRange = xr.attribute("attack-range", default: parent.attackRange)
        spaceTakenValue = xr.attribute(pick("spaceTaken", "space-taken"), default: parent.spaceTakenValue)
        maximumExperience = xr.attribute(pick("maximumExperience", "maximum-experience"),
                                         default: parent.maximumExperience)
        maximumAttrition = xr.attribute(pick("maximumAttrition", "maximum-attrition"),
                                        default: parent.maximumAttrition)
        // Java's default for the skill taught is the type itself.
        skillTaught = try spec.flatMap {
            try xr.getType($0, pick("skillTaught", "skill-taught"), UnitType.self)
        } ?? self
        recruitProbability = xr.attribute(pick("recruitProbability", "recruit-probability"),
                                          default: parent.recruitProbability)
        priority = xr.attribute("priority", default: ConsumerPriority.unit)
        skill = xr.attribute("skill", default: parent.skill)
        price = xr.attribute("price", default: parent.price)
        mercenaryPrice = xr.attribute("mercenary-price", default: parent.mercenaryPrice)
        expertProduction = try spec.flatMap {
            try xr.getType($0, "expert-production", GoodsType.self)
        } ?? parent.expertProduction
        if parent !== self, !xr.hasAttribute("required-population") {
            requiredPopulation = parent.requiredPopulation
        }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("offence", baseOffence)
        xw.writeAttribute("defence", baseDefence)
        xw.writeAttribute("default-unit", isDefaultUnitType)
        xw.writeAttribute("movement", movement)
        xw.writeAttribute("line-of-sight", lineOfSight)
        xw.writeAttribute("score-value", scoreValue)
        xw.writeAttribute("space", space)
        xw.writeAttribute("space-taken", spaceTakenValue)
        xw.writeAttribute("hit-points", hitPoints)
        xw.writeAttribute("attack-range", attackRange)
        xw.writeAttribute("maximum-experience", maximumExperience)
        if maximumAttrition != Constants.infinity { xw.writeAttribute("maximum-attrition", maximumAttrition) }
        xw.writeAttribute("recruit-probability", recruitProbability)
        if skill != Constants.undefined { xw.writeAttribute("skill", skill) }
        if price != Constants.undefined { xw.writeAttribute("price", price) }
        if mercenaryPrice != Constants.undefined { xw.writeAttribute("mercenary-price", mercenaryPrice) }
        xw.writeAttribute("skill-taught", skillTaught)
        xw.writeAttribute("expert-production", expertProduction)
        xw.writeAttribute("priority", priority)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if let defaultRole, defaultRole !== specification?.defaultRole {
            xw.writeIdElement("default-role", defaultRole.id)
        }
        if let consumption {
            for type in consumption.types {
                xw.writeStartElement("consumes")
                xw.writeAttribute(FreeColObject.idTag, type)
                xw.writeAttribute("value", consumption.count(type))
                xw.writeEndElement()
            }
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        consumption = nil
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        let spec = specification
        defaultRole = spec?.defaultRole
        let parent = try spec.flatMap { try xr.getAlreadyInitializedType($0, "extends", UnitType.self) } ?? self
        if parent !== self {
            defaultRole = parent.defaultRole
            if let theirs = parent.consumption {
                if consumption == nil { consumption = TypeCountMap() }
                consumption!.putAll(theirs)
            }
            addFeatures(of: parent)
            if parent.isAbstractType {
                featureContainer?.replaceSource(parent, self)
            }
        }
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let spec = specification
        let tag = xr.localName
        switch tag {
        case "consumes":
            if let spec, let type = try xr.getType(spec, "id", GoodsType.self) {
                if consumption == nil { consumption = TypeCountMap() }
                consumption!.increment(type, by: xr.attribute("value", default: Constants.undefined))
            }
            try xr.closeTag(tag)
        case "default-equipment":
            // @compat 0.10.x
            try xr.swallowTag(tag)
        case "default-role":
            defaultRole = try spec.flatMap { try xr.getType($0, "id", Role.self) } ?? spec?.defaultRole
            try xr.closeTag(tag)
        case "downgrade", "upgrade":
            // @compat 0.11.x: unit changes moved to unit-change-types.
            try xr.closeTag(tag, others: [Scope.tag])
        default:
            try super.readChild(xr)
        }
    }
}

/// One possible change of unit type, such as a free colonist becoming
/// a veteran (common/model/UnitTypeChange).
public final class UnitTypeChange: FreeColSpecObjectType {

    public static let tag = "unit-type-change"

    public private(set) var from: UnitType?
    public private(set) var to: UnitType?
    public private(set) var probability = 0
    public private(set) var turns = -1

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    /// Read a change from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader, specification: Specification?) throws {
        self.init(id: xr.readId(), specification: specification)
        try readFromXML(xr)
    }

    /// A change made in code (Java's tests set the fields directly).
    public convenience init(id: String?, specification: Specification?, from: UnitType?, to: UnitType?,
                            probability: Int, turns: Int) {
        self.init(id: id, specification: specification)
        self.from = from
        self.to = to
        self.probability = probability
        self.turns = turns
    }

    public override var xmlTagName: String {
        UnitTypeChange.tag
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        from = try spec.flatMap { try xr.getType($0, "from", UnitType.self) }
        to = try spec.flatMap { try xr.getType($0, "to", UnitType.self) }
        probability = xr.attribute("probability", default: 0)
        turns = xr.attribute("turns", default: -1)
        if id == nil || id == "" {
            // Java counts these across the whole process; here per
            // specification, so the numbers can differ.
            id = "model.unitChange.faked.\(spec?.nextFakeUnitChangeId() ?? 0)"
        }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("from", from)
        xw.writeAttribute("to", to)
        xw.writeAttribute("probability", probability)
        if turns > 0 { xw.writeAttribute("turns", turns) }
    }

    /// Java's toString: "from->to/probability[/turns]".
    public override var description: String {
        var s = "\(from?.suffix ?? "null")->\(to?.suffix ?? "null")/\(probability)"
        if turns > 0 { s += "/\(turns)" }
        return s
    }
}

/// A kind of unit change, such as education or promotion, with all the
/// possible changes of that kind (common/model/UnitChangeType).
public final class UnitChangeType: FreeColSpecObjectType {

    public static let tag = "unit-change-type"

    public static let capture = "model.unitChange.capture"
    public static let clearSkill = "model.unitChange.clearSkill"
    public static let conversion = "model.unitChange.conversion"
    public static let creation = "model.unitChange.creation"
    public static let demotion = "model.unitChange.demotion"
    public static let education = "model.unitChange.education"
    public static let enterColony = "model.unitChange.enterColony"
    public static let experience = "model.unitChange.experience"
    public static let foundingFather = "model.unitChange.foundingFather"
    public static let independence = "model.unitChange.independence"
    public static let lostCity = "model.unitChange.lostCity"
    public static let natives = "model.unitChange.natives"
    public static let promotion = "model.unitChange.promotion"
    public static let undead = "model.unitChange.undead"

    /// Whether the unit changes owner (capture).
    public private(set) var ownerChange = false
    /// The changes by starting type, in Java's HashMap order.
    private var changes = JavaHashMap<UnitTypeKey, [UnitTypeChange]>(javaHash: { $0.javaHash })

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        UnitChangeType.tag
    }

    /// Add a change.
    public func addUnitTypeChange(_ uc: UnitTypeChange) {
        let key = UnitTypeKey(uc.from)
        changes.put(key, (changes[key] ?? []) + [uc])
    }

    /// The changes from a unit type, in the order read.
    public func unitChanges(_ from: UnitType?) -> [UnitTypeChange] {
        changes[UnitTypeKey(from)] ?? []
    }

    /// The first change from a type, to a type if given.
    public func unitChange(_ from: UnitType?, _ to: UnitType?) -> UnitTypeChange? {
        unitChanges(from).first { to == nil || $0.to === to }
    }

    /// Remove all changes from a type.
    public func deleteUnitChanges(_ from: UnitType?) {
        changes.removeValue(forKey: UnitTypeKey(from))
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        ownerChange = xr.attribute("owner-change", default: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("owner-change", ownerChange)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for list in changes.values {
            for uc in list { uc.toXML(xw) }
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        changes.removeAll()
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == UnitTypeChange.tag {
            addUnitTypeChange(try UnitTypeChange(xr, specification: specification))
        } else {
            try super.readChild(xr)
        }
    }
}

/// A HashMap key for an optional unit type, compared and hashed by id
/// as Java's HashMap does (a null key hashes to 0).
struct UnitTypeKey: Hashable {
    let type: UnitType?

    init(_ type: UnitType?) {
        self.type = type
    }

    var javaHash: Int32 {
        type?.javaHashCode ?? 0
    }

    static func == (a: UnitTypeKey, b: UnitTypeKey) -> Bool {
        switch (a.type, b.type) {
        case (nil, nil): true
        case let (x?, y?): x == y
        default: false
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(type)
    }
}

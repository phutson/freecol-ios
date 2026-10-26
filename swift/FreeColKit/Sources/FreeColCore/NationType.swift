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

/// A kind of nation with its advantages (common/model/NationType).
/// Abstract in Java: the concrete kinds are European and Indian.
open class NationType: FreeColSpecObjectType {

    /// How many settlements a nation starts with.
    public enum SettlementNumber: JavaEnum {
        case low, average, high
        public var javaName: String {
            switch self { case .low: "LOW"; case .average: "AVERAGE"; case .high: "HIGH" }
        }
    }

    /// How aggressive a nation is.
    public enum AggressionLevel: JavaEnum {
        case low, average, high
        public var javaName: String {
            switch self { case .low: "LOW"; case .average: "AVERAGE"; case .high: "HIGH" }
        }
    }

    public private(set) var numberOfSettlements = SettlementNumber.average
    public private(set) var aggression = AggressionLevel.average
    private var settlementTypeList: [SettlementType]?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    /// The kinds of settlement, in the order read.
    public var settlementTypes: [SettlementType] {
        settlementTypeList ?? []
    }

    /// The capital settlement kind.
    public var capitalType: SettlementType? {
        settlementType(capital: true)
    }

    /// The first settlement kind that is, or is not, a capital.
    public func settlementType(capital: Bool) -> SettlementType? {
        settlementTypes.first { $0.isCapital == capital }
    }

    /// The settlement kind with an id.
    public func settlementType(id: String?) -> SettlementType? {
        settlementTypes.first { $0.id == id }
    }

    open var isEuropean: Bool { false }
    open var isIndian: Bool { false }
    open var isREF: Bool { false }

    /// The methods scopes may name on a nation type.
    public override func scopeMethodValue(_ methodName: String) -> String? {
        switch methodName {
        case "isEuropean": "\(isEuropean)"
        case "isIndian": "\(isIndian)"
        case "isREF": "\(isREF)"
        default: super.scopeMethodValue(methodName)
        }
    }

    // MARK: Reading XML

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let parent = try specification.flatMap {
            try xr.getAlreadyInitializedType($0, "extends", NationType.self)
        } ?? self
        numberOfSettlements = xr.attribute("number-of-settlements", SettlementNumber.self,
                                           default: parent.numberOfSettlements) ?? .average
        aggression = xr.attribute("aggression", AggressionLevel.self,
                                  default: parent.aggression) ?? .average
    }

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("number-of-settlements", numberOfSettlements)
        xw.writeAttribute("aggression", aggression)
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for st in settlementTypes { st.toXML(xw, tag: "settlement") }
    }

    open override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        settlementTypeList = nil
    }

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        let parent = try specification.flatMap {
            try xr.getAlreadyInitializedType($0, "extends", NationType.self)
        } ?? self
        if parent !== self {
            if let theirs = parent.settlementTypeList {
                settlementTypeList = (settlementTypeList ?? []) + theirs
            }
            addFeatures(of: parent)
            if parent.isAbstractType {
                featureContainer?.replaceSource(parent, self)
            }
        }
        try super.readChildren(xr)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "settlement" {
            let st = SettlementType(id: nil, specification: specification)
            try st.readFromXML(xr)
            settlementTypeList = (settlementTypeList ?? []) + [st]
        } else {
            try super.readChild(xr)
        }
    }
}

/// A European nation's kind, with its starting units
/// (common/model/EuropeanNationType).
public final class EuropeanNationType: NationType {

    public static let tag = "european-nation-type"

    private var ref = false
    /// Starting units by "default" or "expert", then by unit id, as
    /// Java's nested HashMaps.
    private var startingUnitMap = JavaHashMap<String, JavaHashMap<String?, AbstractUnit>>(
        javaHash: JavaString.hashCode)

    /// Java's hash for a possibly null String key.
    private static func optionalHash(_ s: String?) -> Int32 {
        s.map(JavaString.hashCode) ?? 0
    }

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        EuropeanNationType.tag
    }

    public override var isEuropean: Bool { true }
    public override var isREF: Bool { ref }

    /// The starting units for the game options' choice of experts.
    public var startingUnits: [AbstractUnit] {
        startingUnits(specification?.getBoolean("model.option.expertStartingUnits") == true
                      ? "expert" : "default")
    }

    /// The default starting units, overridden by those for a key, in
    /// Java's HashMap order.
    public func startingUnits(_ key: String) -> [AbstractUnit] {
        var result = JavaHashMap<String?, AbstractUnit>(javaHash: EuropeanNationType.optionalHash)
        if let defaults = startingUnitMap["default"] { result.putAll(defaults) }
        if let chosen = startingUnitMap[key] { result.putAll(chosen) }
        return result.values
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let parent = try specification.flatMap {
            try xr.getAlreadyInitializedType($0, "extends", EuropeanNationType.self)
        } ?? self
        ref = xr.attribute("ref", default: parent.ref)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("ref", ref)
    }

    /// The default starting units, then the expert ones, each as Java's
    /// HashMap orders them.
    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for (key, expert) in [("default", false), ("expert", true)] {
            for e in startingUnitMap[key]?.entries ?? [] {
                xw.writeStartElement("unit")
                xw.writeAttribute(FreeColObject.idTag, id: e.key)
                xw.writeAttribute("type", e.value)
                xw.writeAttribute("role", id: e.value.roleId)
                if expert { xw.writeAttribute("expert-starting-units", expert) }
                xw.writeEndElement()
            }
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        startingUnitMap.removeAll()
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        let parent = try specification.flatMap {
            try xr.getAlreadyInitializedType($0, "extends", EuropeanNationType.self)
        } ?? self
        if parent !== self {
            for e in parent.startingUnitMap.entries {
                startingUnitMap.put(e.key, JavaHashMap(copying: e.value))
            }
        }
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "unit" {
            let id = xr.readId()
            let type = xr.attribute("type", default: nil as String?)
            let role = xr.attribute("role", default: Specification.defaultRoleId) ?? Specification.defaultRoleId
            let key = xr.attribute("expert-starting-units", default: false) ? "expert" : "default"
            var units = startingUnitMap[key] ?? JavaHashMap(javaHash: EuropeanNationType.optionalHash)
            units.put(id, AbstractUnit(id: type, roleId: role, number: 1))
            startingUnitMap.put(key, units)
            try xr.closeTag("unit")
        } else {
            try super.readChild(xr)
        }
    }
}

/// A native nation's kind, with the skills its settlements teach
/// (common/model/IndianNationType).
///
/// Not yet ported: generateSkillsForTile, which needs Tile.
public final class IndianNationType: NationType {

    public static let tag = "indian-nation-type"

    private var skillList: [RandomChoice<UnitType>]?
    private var regionList: [String]?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        IndianNationType.tag
    }

    public override var isIndian: Bool { true }

    /// The message key for the settlements, singular or plural.
    public func settlementTypeKey(plural: Bool) -> String {
        "\(settlementType(capital: false)?.id ?? "null")" + (plural ? ".plural" : "")
    }

    /// The skills taught, with their weights.
    public var skills: [RandomChoice<UnitType>] {
        skillList ?? []
    }

    /// The regions this nation prefers.
    public var regions: [String] {
        regionList ?? []
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        skillList = nil
        regionList = nil
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for choice in skills {
            xw.writeStartElement("skill")
            xw.writeAttribute(FreeColObject.idTag, choice.object)
            xw.writeAttribute("probability", choice.probability)
            xw.writeEndElement()
        }
        for region in regions { xw.writeIdElement("region", region) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        let parent = try specification.flatMap {
            try xr.getAlreadyInitializedType($0, "extends", IndianNationType.self)
        } ?? self
        if parent !== self {
            if let s = parent.skillList, !s.isEmpty { skillList = (skillList ?? []) + s }
            if let r = parent.regionList, !r.isEmpty { regionList = (regionList ?? []) + r }
        }
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "skill":
            if let spec = specification, let type = try xr.getType(spec, "id", UnitType.self) {
                skillList = (skillList ?? []) + [RandomChoice(type, xr.attribute("probability", default: 0))]
            }
            try xr.closeTag("skill")
        case "region":
            if let id = xr.readId() { regionList = (regionList ?? []) + [id] }
            try xr.closeTag("region")
        default:
            try super.readChild(xr)
        }
    }
}

/// A kind of settlement a nation builds (common/model/SettlementType).
///
/// The plunder range for a unit is in Defence.swift.
public final class SettlementType: FreeColSpecObjectType {

    public static let tag = "settlementType"

    public private(set) var isCapital = false
    public private(set) var visibleRadius = 2
    public private(set) var claimableRadius = 1
    public private(set) var extraClaimableRadius = 2
    public private(set) var wanderingRadius = 4
    public private(set) var minimumSize = 3
    public private(set) var maximumSize = 10
    public private(set) var minimumGrowth = 1
    public private(set) var maximumGrowth = 10
    public private(set) var tradeBonus = 1
    public private(set) var convertThreshold = 100
    private var plunderTypeList: [PlunderType]?
    /// The range of gifts given to visitors, if any.
    public private(set) var gifts: RandomRange?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        SettlementType.tag
    }

    /// The goods a settlement of this type can store.
    public var warehouseCapacity: Int {
        GoodsContainer.cargoSize * claimableRadius
    }

    /// The plunder kinds, in the order read.
    public var plunderTypes: [PlunderType] {
        plunderTypeList ?? []
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        // @compat 0.11.3: camelCase names win where present; the
        // defaults are the current values.
        func read(_ old: String, _ new: String, _ current: Int) -> Int {
            xr.attribute(xr.hasAttribute(old) ? old : new, default: current)
        }
        isCapital = xr.attribute("capital", default: isCapital)
        minimumSize = read("minimumSize", "minimum-size", minimumSize)
        maximumSize = read("maximumSize", "maximum-size", maximumSize)
        visibleRadius = read("visibleRadius", "visible-radius", visibleRadius)
        claimableRadius = read("claimableRadius", "claimable-radius", claimableRadius)
        extraClaimableRadius = read("extraClaimableRadius", "extra-claimable-radius", extraClaimableRadius)
        wanderingRadius = read("wanderingRadius", "wandering-radius", wanderingRadius)
        minimumGrowth = read("minimumGrowth", "minimum-growth", minimumGrowth)
        maximumGrowth = read("maximumGrowth", "maximum-growth", maximumGrowth)
        tradeBonus = read("tradeBonus", "trade-bonus", tradeBonus)
        convertThreshold = read("convertThreshold", "convert-threshold", convertThreshold)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("capital", isCapital)
        xw.writeAttribute("minimum-size", minimumSize)
        xw.writeAttribute("maximum-size", maximumSize)
        xw.writeAttribute("visible-radius", visibleRadius)
        xw.writeAttribute("claimable-radius", claimableRadius)
        xw.writeAttribute("extra-claimable-radius", extraClaimableRadius)
        xw.writeAttribute("wandering-radius", wanderingRadius)
        xw.writeAttribute("minimum-growth", minimumGrowth)
        xw.writeAttribute("maximum-growth", maximumGrowth)
        xw.writeAttribute("trade-bonus", tradeBonus)
        xw.writeAttribute("convert-threshold", convertThreshold)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for pt in plunderTypes { pt.toXML(xw) }
        if let gifts {
            xw.writeStartElement("gifts")
            gifts.writeAttributes(xw)
            xw.writeEndElement()
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        plunderTypeList = nil
        gifts = nil
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "gifts":
            gifts = RandomRange(xr)
            try xr.closeTag("gifts")
        case PlunderType.tag:
            let pt = PlunderType(id: nil, specification: specification)
            try pt.readFromXML(xr)
            plunderTypeList = (plunderTypeList ?? []) + [pt]
        default:
            try super.readChild(xr)
        }
    }
}

/// What can be plundered from a settlement, and for whom
/// (common/model/PlunderType).
public final class PlunderType: FreeColSpecObjectType {

    public static let tag = "plunder"

    public private(set) var plunder: RandomRange?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        PlunderType.tag
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        plunder = RandomRange(xr)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        plunder?.writeAttributes(xw)
    }
}

/// A random amount: with a probability, a value in a range times a
/// factor (common/model/RandomRange).
public struct RandomRange: Equatable, Sendable {
    public let probability: Int
    public let minimum: Int
    public let maximum: Int
    public let factor: Int

    public init(probability: Int, minimum: Int, maximum: Int, factor: Int) {
        precondition(probability >= 0, "Negative probability \(probability)")
        precondition(minimum <= maximum, "Min \(minimum) > Max \(maximum)")
        self.probability = probability
        self.minimum = minimum
        self.maximum = maximum
        self.factor = factor
    }

    /// Read from the current element's attributes (Java's factor
    /// defaults to 0 when read, unlike the constructor's 1).
    public init(_ xr: FreeColXMLReader) {
        probability = xr.attribute("probability", default: 0)
        minimum = xr.attribute("minimum", default: 0)
        maximum = xr.attribute("maximum", default: 0)
        factor = xr.attribute("factor", default: 0)
    }

    public func writeAttributes(_ xw: FreeColXMLWriter) {
        xw.writeAttribute("probability", probability)
        xw.writeAttribute("minimum", minimum)
        xw.writeAttribute("maximum", maximum)
        xw.writeAttribute("factor", factor)
    }

    /// A random amount, using the generator as Java does: one draw for
    /// the probability unless it is certain, then one for the value.
    public func amount(_ prefix: String, _ random: JavaRandom, continuous: Bool) -> Int {
        guard probability >= 100
            || (probability > 0
                && RandomUtils.randomInt("\(prefix) check-probability", random, 100) < Int32(probability))
        else { return 0 }
        let range = maximum - minimum + 1
        if continuous {
            let r = Int(RandomUtils.randomInt("\(prefix) random-range", random, Int32(range * factor)))
            return r + minimum * factor
        }
        let r = Int(RandomUtils.randomInt("\(prefix) random-range", random, Int32(range)))
        return (r + minimum) * factor
    }
}

/// A unit described by type id, role id and number, not belonging to a
/// game (common/model/AbstractUnit).  Its id is the unit type id.
///
/// The labels are in Labels.swift.  Not yet ported: matching against a
/// Unit.
public final class AbstractUnit: FreeColObject {

    public static let tag = "abstractUnit"

    /// The role id; Java allows none, which the fixes repair.
    public var roleId: String? = Specification.defaultRoleId
    public var number = 1

    public init(id: String?, roleId: String?, number: Int) {
        super.init()
        self.id = id
        self.roleId = roleId
        self.number = number
    }

    /// Read an abstract unit from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader) throws {
        self.init(id: nil, roleId: Specification.defaultRoleId, number: 1)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        AbstractUnit.tag
    }

    public func type(_ spec: Specification) -> UnitType? { spec.getUnitType(id) }
    public func role(_ spec: Specification) -> Role? { spec.getRole(roleId) }

    /// The offence of all these units in their role.
    public func offence(_ spec: Specification) -> Double {
        Double(number) * ((type(spec)?.offence ?? 0) + (role(spec)?.offence ?? 0))
    }

    /// Whether another has the same type, role and number.
    public func matchAll(_ other: AbstractUnit) -> Bool {
        id == other.id && roleId == other.roleId && number == other.number
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        roleId = xr.attribute("role", default: Specification.defaultRoleId)
        number = xr.attribute("number", default: 1)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let roleId { xw.writeAttribute("role", roleId) }
        xw.writeAttribute("number", number)
    }

    /// Java's toString: "<number> <type id> (<role id>)".
    public override var description: String {
        "\(number) \(id ?? "null") (\(roleId ?? "null"))"
    }
}

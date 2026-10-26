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

/// A nation that can take part in a game (common/model/Nation).
///
/// Colors are ARGB values in the form of `java.awt.Color.getRGB()`, as
/// the Java model now keeps them.  Not yet ported: names from messages,
/// and picking a nation name not in a game.
public final class Nation: FreeColSpecObjectType {

    public static let tag = "nation"
    public static let unknownNationId = "model.nation.unknownEnemy"
    /// Alpha bits of a fully opaque ARGB color.
    public static let opaque: Int32 = Int32(bitPattern: 0xFF00_0000)
    /// The last resort unknown nation color (opaque black, as ARGB).
    public static let unknownNationRGB = opaque

    public var type: NationType?
    public private(set) var isSelectable = false
    public private(set) var refNation: Nation?
    public private(set) var preferredLatitude = 0
    public private(set) var startsOnEastCoast = true
    /// The ARGB color, or nil if not set.
    public var rgb: Int32?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        Nation.tag
    }

    public var isUnknownEnemy: Bool {
        id == Nation.unknownNationId
    }

    /// The European nation whose REF this is.
    public var rebelNation: Nation? {
        specification?.europeanNations.first { $0.refNation === self }
    }

    /// The message key of the ruler's name.
    public var rulerNameKey: String {
        "\(id ?? "null").ruler"
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        type = try spec.flatMap { try xr.getType($0, "nation-type", NationType.self) }
        isSelectable = xr.attribute("selectable", default: false)
        preferredLatitude = xr.attribute(xr.hasAttribute("preferredLatitude")
                                         ? "preferredLatitude" : "preferred-latitude", default: 0)
        startsOnEastCoast = xr.attribute(xr.hasAttribute("startsOnEastCoast")
                                         ? "startsOnEastCoast" : "starts-on-east-coast", default: true)
        refNation = try spec.flatMap { try xr.getType($0, "ref", Nation.self) }
        let color = xr.attribute("color", default: Constants.undefined)
        // Saved colors are opaque, as java.awt.Color(int) made them.
        if color != Constants.undefined { rgb = Nation.opaque | Int32(truncatingIfNeeded: color) }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("nation-type", type)
        xw.writeAttribute("selectable", isSelectable)
        xw.writeAttribute("preferred-latitude", preferredLatitude)
        xw.writeAttribute("starts-on-east-coast", startsOnEastCoast)
        xw.writeAttribute("ref", refNation)
        if let rgb { xw.writeAttribute("color", Int(rgb)) }
    }
}

/// A founding father, with the events and units joining brings
/// (common/model/FoundingFather).
public final class FoundingFather: FreeColSpecObjectType {

    public static let tag = "founding-father"

    /// The kinds of founding father.
    public enum FoundingFatherType: JavaEnum {
        case trade, exploration, military, political, religious
        public var javaName: String {
            switch self {
            case .trade: "TRADE"
            case .exploration: "EXPLORATION"
            case .military: "MILITARY"
            case .political: "POLITICAL"
            case .religious: "RELIGIOUS"
            }
        }
        /// The message key of the type's name.
        public var typeKey: String {
            "model.foundingFather.\(javaName.lowercased())"
        }
    }

    public var type: FoundingFatherType?
    private var weights = [Int](repeating: 0, count: Specification.numberOfAges)
    private var eventList: [Event]?
    private var unitList: [AbstractUnit]?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        FoundingFather.tag
    }

    /// The chance of being offered in an age, or 0 outside the ages.
    /// Whether a player could elect this father: only Europeans, and
    /// only those the scopes allow.
    public func isAvailableTo(_ player: Player) -> Bool {
        player.isEuropean && appliesTo(player)
    }

    public func weight(_ age: Int) -> Int {
        (0..<weights.count).contains(age) ? weights[age] : 0
    }

    public var events: [Event] {
        eventList ?? []
    }

    /// Replace the events.
    public func setEvents(_ events: [Event]) {
        eventList = events
    }

    public var units: [AbstractUnit] {
        unitList ?? []
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        type = xr.attribute("type", FoundingFatherType.self, default: nil)
        for i in weights.indices {
            weights[i] = xr.attribute("weight\(i + 1)", default: 0)
        }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let type { xw.writeAttribute("type", type) }
        for (i, w) in weights.enumerated() { xw.writeAttribute("weight\(i + 1)", w) }
    }

    /// The units are written by type alone, as Java does.
    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for event in events { event.toXML(xw) }
        for unit in units { xw.writeIdElement("unit", unit.id) }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        eventList = nil
        unitList = nil
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "unit":
            unitList = (unitList ?? []) + [try AbstractUnit(xr)]
        case Event.tag:
            let e = Event(id: nil, specification: specification)
            try e.readFromXML(xr)
            eventList = (eventList ?? []) + [e]
        case "upgrade":
            // @compat 0.11.x
            try xr.closeTag("upgrade")
        default:
            try super.readChild(xr)
        }
    }
}

/// Something that can happen, possibly limited by conditions
/// (common/model/Event).
public final class Event: FreeColSpecObjectType {

    public static let tag = "event"

    public var value: String?
    public var scoreValue = 0
    /// The limits by id, in Java's HashMap order.
    private var limits: JavaHashMap<String?, Limit>?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        Event.tag
    }

    /// The limits, in Java's HashMap order.
    public var limitValues: [Limit] {
        limits?.values ?? []
    }

    /// The limit with an id.
    public func limit(_ id: String?) -> Limit? {
        limits?[id]
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        value = xr.attribute("value", default: nil as String?)
        scoreValue = xr.attribute(xr.hasAttribute("scoreValue") ? "scoreValue" : "score-value", default: 0)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", id: value)
        if scoreValue != 0 { xw.writeAttribute("score-value", scoreValue) }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for limit in limitValues { limit.toXML(xw) }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        limits = nil
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == Limit.tag {
            let limit = try Limit(xr, specification: specification)
            if limits == nil { limits = JavaHashMap(javaHash: { $0.map(JavaString.hashCode) ?? 0 }) }
            limits!.put(limit.id, limit)
        } else {
            try super.readChild(xr)
        }
    }
}

/// A condition comparing two operands (common/model/Limit).
///
/// Not yet ported: evaluating against a game, player or settlement.
public final class Limit: FreeColSpecObjectType {

    public static let tag = "limit"

    /// How the operands are compared.
    public enum Operator: JavaEnum {
        case eq, lt, gt, le, ge
        public var javaName: String {
            switch self { case .eq: "EQ"; case .lt: "LT"; case .gt: "GT"; case .le: "LE"; case .ge: "GE" }
        }
    }

    public var `operator`: Operator?
    public var leftHandSide = Operand()
    public var rightHandSide = Operand()

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    /// Read a limit from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader, specification: Specification?) throws {
        self.init(id: nil, specification: specification)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        Limit.tag
    }

    /// Whether the left operand applies to an object.
    public func appliesTo(object: FreeColObject?) -> Bool {
        leftHandSide.appliesTo(object)
    }

    /// Whether either operand has a type.
    public func hasOperandType(_ type: Operand.OperandType) -> Bool {
        leftHandSide.operandType == type || rightHandSide.operandType == type
    }

    /// Compare two values: true when either is unknown.
    public func evaluate(_ lhs: Int?, _ rhs: Int?) -> Bool {
        guard let lhs, let rhs else { return true }
        switch `operator` {
        case .eq: return lhs == rhs
        case .lt: return lhs < rhs
        case .gt: return lhs > rhs
        case .le: return lhs <= rhs
        case .ge: return lhs >= rhs
        case nil: return false
        }
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        `operator` = xr.attribute("operator", Operator.self, default: nil)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let `operator` { xw.writeAttribute("operator", `operator`) }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        leftHandSide.toXML(xw, tag: "left-hand-side")
        rightHandSide.toXML(xw, tag: "right-hand-side")
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "left-hand-side", "leftHandSide":
            leftHandSide = Operand()
            try leftHandSide.readFromXML(xr)
        case "right-hand-side", "rightHandSide":
            rightHandSide = Operand()
            try rightHandSide.readFromXML(xr)
        default:
            try super.readChild(xr)
        }
    }

    /// Java's toString: "lhs OPERATOR rhs".
    public override var description: String {
        "\(leftHandSide) \(`operator`?.javaName ?? "null") \(rightHandSide)"
    }
}

/// One side of a limit: a fixed value, or something counted
/// (common/model/Operand).
///
/// Not yet ported: the values counted in a game, for a player or in a
/// settlement.
public final class Operand: Scope {

    /// What is counted.
    public enum OperandType: JavaEnum {
        case units, buildings, settlements, foundingFathers, year, option, none
        public var javaName: String {
            switch self {
            case .units: "UNITS"
            case .buildings: "BUILDINGS"
            case .settlements: "SETTLEMENTS"
            case .foundingFathers: "FOUNDING_FATHERS"
            case .year: "YEAR"
            case .option: "OPTION"
            case .none: "NONE"
            }
        }
    }

    /// Where it is counted.
    public enum ScopeLevel: JavaEnum {
        case settlement, player, game, none
        public var javaName: String {
            switch self {
            case .settlement: "SETTLEMENT"
            case .player: "PLAYER"
            case .game: "GAME"
            case .none: "NONE"
            }
        }
    }

    public var operandType = OperandType.none
    public var scopeLevel = ScopeLevel.none
    /// A fixed value, if any.
    public var value: Int?

    public override init() {
        super.init()
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        operandType = xr.attribute(xr.hasAttribute("operandType") ? "operandType" : "operand-type",
                                   OperandType.self, default: OperandType.none) ?? .none
        scopeLevel = xr.attribute(xr.hasAttribute("scopeLevel") ? "scopeLevel" : "scope-level",
                                  ScopeLevel.self, default: ScopeLevel.none) ?? .none
        let v = xr.attribute("value", default: Constants.infinity)
        if v != Constants.infinity { value = v }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("operand-type", operandType)
        xw.writeAttribute("scope-level", scopeLevel)
        if let value { xw.writeAttribute("value", value) }
    }

    public override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? Operand else { return false }
        return operandType == other.operandType && scopeLevel == other.scopeLevel
            && value == other.value && super.isEqual(to: other)
    }

    public override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(operandType)
        hasher.combine(scopeLevel)
        hasher.combine(value)
    }

    /// Java's toString: the value, or the scope description relabelled.
    public override var description: String {
        if let value { return String(value) }
        let scope = super.description
        let rest = scope.firstIndex(of: " ").map { String(scope[$0...]) } ?? ""
        return "[Operand type=\(operandType.javaName) scopeLevel=\(scopeLevel.javaName)" + rest
    }
}

/// A disaster that can strike a colony, with its possible effects
/// (common/model/Disaster).
public final class Disaster: FreeColSpecObjectType {

    public static let tag = "disaster"
    public static let bankruptcy = "model.disaster.bankruptcy"

    /// How many effects a disaster has.
    public enum Effects: JavaEnum {
        case one, several, all
        public var javaName: String {
            switch self { case .one: "ONE"; case .several: "SEVERAL"; case .all: "ALL" }
        }
    }

    public private(set) var isNatural = false
    public private(set) var numberOfEffects = Effects.one
    private var effectList: [RandomChoice<Effect>]?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        Disaster.tag
    }

    /// The effects, with their weights.
    public var effects: [RandomChoice<Effect>] {
        effectList ?? []
    }

    private func addEffect(_ effect: Effect) {
        effectList = (effectList ?? []) + [RandomChoice(effect, effect.probability)]
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let parent = try specification.flatMap {
            try xr.getAlreadyInitializedType($0, "extends", Disaster.self)
        } ?? self
        isNatural = xr.attribute("natural", default: parent.isNatural)
        numberOfEffects = xr.hasAttribute("effects")
            ? (xr.attribute("effects", Effects.self, default: .one) ?? .one)
            : parent.numberOfEffects
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("natural", isNatural)
        xw.writeAttribute("effects", numberOfEffects)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for choice in effects { choice.object.toXML(xw) }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        effectList = nil
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        let parent = try specification.flatMap {
            try xr.getAlreadyInitializedType($0, "extends", Disaster.self)
        } ?? self
        if parent !== self && !parent.effects.isEmpty {
            if effectList == nil { effectList = [] }
            for choice in parent.effects {
                let effect = Effect(copying: choice.object)
                effect.featureContainer?.replaceSource(parent, self)
                addEffect(effect)
            }
        }
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == Effect.tag {
            let effect = Effect(id: nil, specification: specification)
            try effect.readFromXML(xr)
            effect.featureContainer?.replaceSource(nil, self)
            addEffect(effect)
        } else {
            try super.readChild(xr)
        }
    }

    /// Java's toString: "[id effect...]".
    public override var description: String {
        "[\(id ?? "null")" + effects.map { " \($0.object)" }.joined() + "]"
    }
}

/// One effect of a disaster (common/model/Effect).
public final class Effect: FreeColSpecObjectType {

    public static let tag = "effect"

    public static let damagedUnit = "model.disaster.effect.damagedUnit"
    public static let lossOfUnit = "model.disaster.effect.lossOfUnit"
    public static let lossOfMoney = "model.disaster.effect.lossOfMoney"
    public static let lossOfGoods = "model.disaster.effect.lossOfGoods"
    public static let lossOfTileProduction = "model.disaster.effect.lossOfTileProduction"
    public static let lossOfBuilding = "model.disaster.effect.lossOfBuilding"
    public static let lossOfBuildingProduction = "model.disaster.effect.lossOfBuildingProduction"

    public private(set) var probability = 0

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    /// A copy of another effect, sharing its scopes and features.
    public convenience init(copying other: Effect) {
        self.init(id: other.id, specification: other.specification)
        probability = other.probability
        for s in other.scopes { addScope(s) }
        addFeatures(of: other)
    }

    public override var xmlTagName: String {
        Effect.tag
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        probability = xr.attribute("probability", default: 0)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("probability", probability)
    }

    /// Java's toString: "[id probability=N% scope...]".
    public override var description: String {
        "[\(id ?? "null") probability=\(probability)%" + scopes.map { " \($0)" }.joined() + "]"
    }
}

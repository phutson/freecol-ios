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

/// A change to a number, such as +50% offence or +2 grain
/// (common/model/Modifier).
///
/// All arithmetic is in `Float`, as in Java, so results match to the
/// last bit.  The modifier id constants are in ModifierIds.swift.
public final class Modifier: Feature {

    public static let tag = "modifier"

    /// How a modifier changes a number.  The order matters: at the same
    /// index, additive modifiers apply first, then multiplicative, then
    /// percentage.
    public enum ModifierType: Int, JavaEnum {
        case additive
        case multiplicative
        case percentage

        /// The Java enum constant name, as in toString and saved games.
        public var javaName: String {
            switch self {
            case .additive: "ADDITIVE"
            case .multiplicative: "MULTIPLICATIVE"
            case .percentage: "PERCENTAGE"
            }
        }

    }

    /// The marker value for an unknown modifier (Java's Float.MIN_VALUE,
    /// the smallest positive float).  Applying it makes the result unknown.
    public static let unknown = Float.leastNonzeroMagnitude

    public static let defaultModifierIndex = 0

    // Production indexes.
    public static let resourceProductionIndex = 10
    public static let colonyProductionIndex = 20
    public static let expertProductionIndex = 30
    public static let colonyTileProductionIndex = 35
    public static let fatherProductionIndex = 40
    public static let improvementProductionIndex = 50
    public static let autoProductionIndex = 60
    public static let buildingProductionIndex = 70
    public static let nationProductionIndex = 80
    public static let partyProductionIndex = 90
    public static let disasterProductionIndex = 100
    public static let defaultProductionIndex = 100

    // Combat indexes.
    public static let baseCombatIndex = 10
    public static let unitAdditiveCombatIndex = 20
    public static let unitNormalCombatIndex = 40
    public static let roleCombatIndex = 30
    public static let generalCombatIndex = 50

    /// How this modifier changes a number.
    public var type: ModifierType
    /// The amount.
    public var value: Float
    /// How much the value changes each turn, if it has an increment.
    public var increment: Float = 0
    /// How the increment is applied, or nil for none.
    public var incrementType: ModifierType?
    /// The order of application: lower indexes apply first.
    public var modifierIndex = Modifier.defaultModifierIndex

    /// Create a modifier.  Its specification is the source's, as in Java.
    public init(_ id: String?, _ value: Float, _ type: ModifierType,
                source: FreeColObject? = nil,
                index: Int = Modifier.defaultModifierIndex) {
        self.value = value
        self.type = type
        super.init(specification: source?.specification)
        self.id = id
        self.source = source
        modifierIndex = index
    }

    /// A copy of a modifier (Java's makeModifier).
    public convenience init(copying other: Modifier) {
        self.init(other.id, other.value, other.type)
        copyFeature(from: other)
        increment = other.increment
        incrementType = other.incrementType
        modifierIndex = other.modifierIndex
    }

    /// A copy of a template whose value counts down from a start turn
    /// (Java's makeTimedModifier).  Without a duration, it lasts until
    /// the increments use up the value, which only makes sense for
    /// additive increments (as Java notes).
    public static func makeTimedModifier(_ id: String, template: Modifier,
                                         start: Turn) -> Modifier {
        let modifier = Modifier(copying: template)
        modifier.id = id
        let inc = template.increment
        var duration = template.duration
        modifier.temporary = template.temporary
        if duration == 0 {
            duration = Int(JavaMath.toInt(template.value / -inc))
        }
        modifier.setIncrement(template.incrementType, inc, firstTurn: start,
                              lastTurn: Turn(start.number + duration))
        return modifier
    }

    public override var xmlTagName: String {
        Modifier.tag
    }

    /// Read a modifier from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader, specification: Specification?) throws {
        self.init(nil, Modifier.unknown, .additive)
        setSpecification(specification)
        try readFromXML(xr)
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        // Java reads a missing type as null and fails later; here it is
        // an error straight away.
        guard let readType = xr.attribute("type", ModifierType.self, default: nil) else {
            throw FreeColXMLError("Modifier without a type: \(xr.currentTag)")
        }
        type = readType
        value = xr.attribute("value", default: Modifier.unknown)
        // @compat 0.11.3: "incrementType" became "increment-type".
        let incrementTag = xr.hasAttribute("incrementType") ? "incrementType" : "increment-type"
        if xr.hasAttribute(incrementTag) {
            incrementType = xr.attribute(incrementTag, ModifierType.self, default: nil)
            increment = xr.attribute("increment", default: Modifier.unknown)
        } else {
            incrementType = nil
            increment = 0
        }
        modifierIndex = xr.attribute("index", default: Modifier.defaultModifierIndex)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", value)
        xw.writeAttribute("type", type)
        if let incrementType {
            xw.writeAttribute("increment-type", incrementType)
            xw.writeAttribute("increment", increment)
        }
        if modifierIndex >= 0 { xw.writeAttribute("index", modifierIndex) }
    }

    /// Whether a value is not the unknown marker.
    public static func isFloatKnown(_ value: Float) -> Bool {
        JavaMath.floatCompare(value, unknown) != 0
    }

    /// Whether this modifier's value is known.
    public var isKnown: Bool {
        Modifier.isFloatKnown(value)
    }

    /// Whether the value changes over time.
    public var hasIncrement: Bool {
        incrementType != nil
    }

    /// Set an increment and the turns it runs between.
    public func setIncrement(_ type: ModifierType?, _ increment: Float,
                             firstTurn: Turn, lastTurn: Turn?) {
        incrementType = type
        self.increment = increment
        self.firstTurn = firstTurn
        self.lastTurn = lastTurn
    }

    /// The value in a turn: 0 outside its time limits, and with any
    /// increments since the first turn applied.  A modifier with an
    /// increment needs a turn, as in Java.
    public func value(at turn: Turn?) -> Float {
        guard appliesTo(turn: turn) else { return 0 }
        guard let incrementType else { return value }
        guard let turn, let firstTurn else {
            preconditionFailure("Incremented modifier needs a turn: \(self)")
        }
        let f = Float(turn.number - firstTurn.number) * increment
        return Modifier.apply(value, f, incrementType)
    }

    /// Apply a value to a base number with this modifier's type.
    public func apply(_ base: Float, _ value: Float) -> Float {
        Modifier.apply(base, value, type)
    }

    private static func apply(_ base: Float, _ value: Float, _ type: ModifierType) -> Float {
        switch type {
        case .additive: base + value
        case .multiplicative: base * value
        case .percentage: base + (base * value) / 100
        }
    }

    /// Apply this modifier's value to a number.
    public func applyTo(_ number: Float) -> Float {
        apply(number, value)
    }

    /// Apply this modifier's value in a turn to a number.
    public func applyTo(_ number: Float, turn: Turn?) -> Float {
        incrementType == nil ? apply(number, value) : apply(number, value(at: turn))
    }

    // MARK: Application order

    /// The order modifiers are applied in, as -1, 0 or 1 (Java's
    /// ascendingModifierIndexComparator): index, then type, then id,
    /// then source id, then value, increment type (none first),
    /// increment, first turn and last turn (none first).  Modifiers
    /// still tied apply the same operation, so their order does not
    /// matter.
    public static func compareForApplication(_ a: Modifier, _ b: Modifier) -> Int {
        func cmp<T: Comparable>(_ x: T, _ y: T) -> Int { x < y ? -1 : x > y ? 1 : 0 }
        func cmpTurn(_ x: Turn?, _ y: Turn?) -> Int {
            switch (x, y) {
            case (nil, nil): 0
            case (nil, _): -1
            case (_, nil): 1
            case let (x?, y?): cmp(x.number, y.number)
            }
        }
        var c = cmp(a.modifierIndex, b.modifierIndex)
        if c != 0 { return c }
        c = cmp(a.type.rawValue, b.type.rawValue)
        if c != 0 { return c }
        c = FreeColObject.compareIds(a, b)
        if c != 0 { return c }
        c = FreeColObject.compareIds(a.source, b.source)
        if c != 0 { return c }
        c = JavaMath.floatCompare(a.value, b.value)
        if c != 0 { return c }
        c = cmp(a.incrementType.map { $0.rawValue + 1 } ?? 0,
                b.incrementType.map { $0.rawValue + 1 } ?? 0)
        if c != 0 { return c }
        c = JavaMath.floatCompare(a.increment, b.increment)
        if c != 0 { return c }
        c = cmpTurn(a.firstTurn, b.firstTurn)
        if c != 0 { return c }
        return cmpTurn(a.lastTurn, b.lastTurn)
    }

    /// Modifiers in application order.  Swift's sort is not stable, but
    /// modifiers it could reorder apply the same operation.
    public static func sortedForApplication<S: Sequence>(_ modifiers: S) -> [Modifier]
        where S.Element == Modifier {
        modifiers.sorted { compareForApplication($0, $1) < 0 }
    }

    // MARK: FreeColObject

    public override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? Modifier else { return false }
        return JavaMath.floatCompare(value, other.value) == 0
            && JavaMath.floatCompare(increment, other.increment) == 0
            && modifierIndex == other.modifierIndex
            && type == other.type
            && incrementType == other.incrementType
            && super.isEqual(to: other)
    }

    public override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(JavaMath.floatToIntBits(value))
        hasher.combine(JavaMath.floatToIntBits(increment))
        hasher.combine(type)
        hasher.combine(incrementType)
        hasher.combine(modifierIndex)
    }

    /// Java's toString, which the reference dumps record.
    public override var description: String {
        var s = "[Modifier \(id ?? "null")"
        if let source { s += " (\(source.id ?? "null"))" }
        s += " \(type.javaName) \(JavaNumberFormat.string(value))"
        if modifierIndex >= Modifier.defaultModifierIndex { s += " index=\(modifierIndex)" }
        if hasScope {
            s += " [" + scopes.map { " \($0)" }.joined() + " ]"
        }
        return s + "]"
    }
}

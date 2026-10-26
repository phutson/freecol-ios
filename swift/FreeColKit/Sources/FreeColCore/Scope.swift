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

/// A condition limiting what a feature applies to (common/model/Scope).
///
/// A scope can require a specification type, an ability, and the
/// result of a named method, and can be negated.  Java calls the
/// named method, and an object's getType(), by reflection; here
/// objects answer through `FreeColObject.scopeType` and
/// `FreeColObject.scopeMethodValue(_:)`.
///
/// Not final: Operand (limits) extends it.
open class Scope: FreeColObject {

    public static let tag = "scope"

    /// The specification type id required, if any.
    public var type: String?
    /// An ability required, if any.
    public var abilityId: String?
    /// The value the ability must have.
    public var abilityValue = true
    /// A method whose result is checked, if any.
    public var methodName: String?
    /// The required method result, as Java's String.valueOf gives it.
    public var methodValue: String?
    /// What the scope says about a missing object.
    public var matchesNull = true
    /// Whether the result is negated.
    public var matchNegated = false

    public override init() {
        super.init()
    }

    open override var xmlTagName: String {
        Scope.tag
    }

    /// Scopes have no identifiers, so unlike other objects no id is read.
    /// Several attributes had camelCase names before 0.11.3.
    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        func pick(_ old: String, _ new: String) -> String {
            xr.hasAttribute(old) ? old : new
        }
        matchNegated = xr.attribute(pick("matchNegated", "match-negated"), default: false)
        matchesNull = xr.attribute(pick("matchesNull", "matches-null"), default: true)
        type = xr.attribute("type", default: nil as String?)
        abilityId = xr.attribute("ability-id", default: nil as String?)
        abilityValue = xr.attribute("ability-value", default: true)
        methodName = xr.attribute(pick("methodName", "method-name"), default: nil as String?)
        methodValue = xr.attribute(pick("methodValue", "method-value"), default: nil as String?)
    }

    /// Scopes have no identifiers, so none is written.
    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        xw.writeAttribute("match-negated", matchNegated)
        xw.writeAttribute("matches-null", matchesNull)
        if let type { xw.writeAttribute("type", type) }
        if let abilityId {
            xw.writeAttribute("ability-id", abilityId)
            xw.writeAttribute("ability-value", abilityValue)
        }
        if let methodName {
            xw.writeAttribute("method-name", methodName)
            if let methodValue { xw.writeAttribute("method-value", methodValue) }
        }
    }

    /// Java's hashCode, which orders a type's scopes when written.
    public var javaHash: Int32 {
        func h(_ s: String?) -> Int32 { s.map(JavaString.hashCode) ?? 0 }
        var hash = javaHashCode
        hash = 31 &* hash &+ h(type)
        hash = 31 &* hash &+ h(abilityId)
        hash = 31 &* hash &+ (abilityValue ? 1 : 0)
        hash = 31 &* hash &+ h(methodName)
        hash = 31 &* hash &+ h(methodValue)
        hash = 31 &* hash &+ (matchesNull ? 1 : 0)
        return 31 &* hash &+ (matchNegated ? 1 : 0)
    }

    /// The key describing this scope: the type, the ability, or the
    /// method as "scope.method.<name>".
    public var key: String? {
        if let type { return type }
        if let abilityId { return abilityId }
        if let methodName { return "scope.method.\(methodName)" }
        return nil
    }

    /// Whether this scope applies to an object.
    ///
    /// Each condition that fails returns `matchNegated`; if all pass,
    /// the result is `!matchNegated`.
    open func appliesTo(_ object: FreeColObject?) -> Bool {
        guard let object else { return matchesNull }
        if let type {
            if object is FreeColSpecObjectType {
                if type != object.id { return matchNegated }
            } else {
                guard let objectType = object.scopeType, type == objectType.id else {
                    return matchNegated
                }
            }
        }
        if let abilityId, object.hasAbility(abilityId) != abilityValue {
            return matchNegated
        }
        if let methodName {
            // Java compares String.valueOf(result), which is "null" when
            // the method does not exist or returns null.
            let value = object.scopeMethodValue(methodName) ?? "null"
            if value != methodValue { return matchNegated }
        }
        return !matchNegated
    }

    // MARK: FreeColObject

    open override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? Scope else { return false }
        return matchNegated == other.matchNegated
            && matchesNull == other.matchesNull
            && type == other.type
            && abilityId == other.abilityId
            && abilityValue == other.abilityValue
            && methodName == other.methodName
            && methodValue == other.methodValue
            && super.isEqual(to: other)
    }

    open override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(type)
        hasher.combine(abilityId)
        hasher.combine(abilityValue)
        hasher.combine(methodName)
        hasher.combine(methodValue)
        hasher.combine(matchesNull)
        hasher.combine(matchNegated)
    }

    /// Java's toString, which appears in modifier descriptions.
    open override var description: String {
        var s = "[Scope \(type ?? "null")"
        if let abilityId { s += " \(abilityId)=\(abilityValue)" }
        if let methodName { s += " \(methodName)=\(methodValue ?? "null")" }
        if matchesNull { s += " matches-null" }
        if matchNegated { s += " match-negated" }
        return s + "]"
    }
}

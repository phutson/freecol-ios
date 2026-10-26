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

import FreeColXML

/// A rule type, such as a unit type or goods type
/// (common/model/FreeColSpecObjectType).
///
/// Every rule type has a feature container (created when first
/// needed), may be abstract (only a base for others while reading), has
/// an index (its position in the specification's list for its kind),
/// and may have scopes of its own, separate from its features' scopes.
///
/// Types are created by the specification when first mentioned, by id,
/// so every subclass has the required `init(id:specification:)`.
open class FreeColSpecObjectType: FreeColSpecObject, Named {

    private var container: FeatureContainer?
    private var scopeList: [Scope]?

    /// Whether this type only exists to be extended while reading.
    public private(set) var isAbstractType = false

    /// The position in the specification's list for this kind of type,
    /// or -1.  Not saved.
    public internal(set) var index = -1

    /// Create a type.
    ///
    /// - Parameters:
    ///   - id: The type identifier, such as "model.unit.freeColonist".
    ///   - specification: The specification it belongs to.
    public required init(id: String?, specification: Specification?) {
        super.init(specification: specification)
        self.id = id
    }

    /// The message key of the description.
    public final var descriptionKey: String {
        "\(id ?? "null").description"
    }

    public final override var featureContainer: FeatureContainer? {
        if container == nil { container = FeatureContainer() }
        return container
    }

    // MARK: Scopes

    /// The type's own scopes.
    public final var scopes: [Scope] {
        scopeList ?? []
    }

    /// Add a scope.
    public final func addScope(_ scope: Scope) {
        if scopeList == nil { scopeList = [] }
        scopeList!.append(scope)
    }

    /// Replace the scopes (Java's copyScopes).
    public final func copyScopes(_ newScopes: [Scope]) {
        if scopeList == nil && newScopes.isEmpty { return }
        scopeList = newScopes
    }

    /// Remove a scope (the first equal one, as Java's List.remove).
    public final func removeScope(_ scope: Scope) {
        if let i = scopeList?.firstIndex(where: { $0 == scope }) { scopeList!.remove(at: i) }
    }

    /// Whether the type's scopes allow an object: true with no scopes,
    /// otherwise if any applies.
    open func appliesTo(_ object: FreeColObject?) -> Bool {
        guard let scopeList, !scopeList.isEmpty else { return true }
        return scopeList.contains { $0.appliesTo(object) }
    }

    // MARK: Named

    public var nameKey: String {
        "\(id ?? "null").name"
    }

    // MARK: Reading XML

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        isAbstractType = xr.attribute("abstract", default: false)
    }

    open override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        container?.clear()
        if scopeList != nil { scopeList = [] }
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        let spec = specification
        switch xr.localName {
        case Ability.tag:
            if xr.attribute("delete", default: false) {
                if let id = xr.readId() { removeAbilities(id) }
                try xr.closeTag(Ability.tag)
            } else {
                let ability = try Ability(xr, specification: spec)
                if ability.source == nil { ability.source = self }
                addAbility(ability)
                spec?.addAbility(ability)
            }
        case Modifier.tag:
            if xr.attribute("delete", default: false) {
                if let id = xr.readId() { removeModifiers(id) }
                try xr.closeTag(Modifier.tag)
            } else {
                let modifier = try Modifier(xr, specification: spec)
                if modifier.source == nil { modifier.source = self }
                addModifier(modifier)
                spec?.addModifier(modifier)
            }
        case Scope.tag:
            let scope = Scope()
            try scope.readFromXML(xr)
            addScope(scope)
        default:
            try super.readChild(xr)
        }
    }

    // MARK: Writing XML
    //
    // Types write their abilities, modifiers and scopes; the abstract
    // flag is not written, as no abstract types are left once read.

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for ability in sortedAbilities { ability.toXML(xw) }
        for modifier in sortedModifiers { modifier.toXML(xw) }
        // Java sorts the scopes in place by hash code first.
        if let list = scopeList {
            scopeList = list.stableSorted { $0.javaHash < $1.javaHash }
            for scope in scopeList! { scope.toXML(xw) }
        }
    }

    // MARK: FreeColObject

    /// Java's toString for a type is just its id, which matters where
    /// Java turns a type into a string, as scope method values do.
    open override var description: String {
        id ?? "null"
    }
}

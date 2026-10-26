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

/// The common part of abilities and modifiers (common/model/Feature):
/// where it came from, when it applies, and what it applies to.
///
/// The source is held weakly.  Sources are owned elsewhere (rule
/// types by the specification, game objects by their containers), and
/// a colony's features often name the colony itself as their source,
/// which would be a reference cycle if held strongly.
///
/// Not yet ported: copyIn.
open class Feature: FreeColSpecObject, Named {

    /// The object this feature comes from, if any.
    public weak var source: FreeColObject?
    /// The first turn the feature applies in, if limited.
    public var firstTurn: Turn?
    /// The last turn the feature applies in, if limited.
    public var lastTurn: Turn?
    /// How many turns a timed feature lasts.
    public var duration = 0
    /// Whether the feature is temporary.
    public var temporary = false

    /// The scopes.  Java distinguishes having no scope container from
    /// having an empty one, and that affects equality, so nil and []
    /// are kept apart here too.
    private var scopeList: [Scope]?

    public override init(specification: Specification?) {
        super.init(specification: specification)
    }

    /// Whether this feature stands alone, rather than coming from a
    /// building, founding father, nation type or settlement type that
    /// adds it again when loaded.
    public var isIndependent: Bool {
        !(source is BuildingType || source is FoundingFather || source is NationType
          || source is SettlementType)
    }

    /// Copy the Feature part of another feature (Java's copyIn).
    func copyFeature(from other: Feature) {
        id = other.id
        setSpecification(other.specification)
        source = other.source
        firstTurn = other.firstTurn
        lastTurn = other.lastTurn
        duration = other.duration
        temporary = other.temporary
        copyScopes(other.scopes)
    }

    /// Whether the feature only applies for a limited time.
    public final var hasTimeLimit: Bool {
        firstTurn != nil || lastTurn != nil
    }

    /// Whether the feature applies in a turn.  It always applies when
    /// no turn is given.
    public func appliesTo(turn: Turn?) -> Bool {
        guard let turn else { return true }
        if let firstTurn, turn.number < firstTurn.number { return false }
        if let lastTurn, turn.number > lastTurn.number { return false }
        return true
    }

    /// Whether the feature applies to an object in a turn.
    public func appliesTo(_ object: FreeColObject?, turn: Turn?) -> Bool {
        appliesTo(turn: turn) && appliesTo(object)
    }

    /// Whether the feature has expired by a turn.
    public func isOutOfDate(_ turn: Turn?) -> Bool {
        guard let turn, let lastTurn else { return false }
        return turn.number > lastTurn.number
    }

    // MARK: Scopes

    /// Whether there are any scopes.
    public final var hasScope: Bool {
        !(scopeList?.isEmpty ?? true)
    }

    /// The scopes, in the order added.
    public final var scopes: [Scope] {
        scopeList ?? []
    }

    /// Replace the scopes (Java's copyScopes).
    public final func copyScopes(_ newScopes: [Scope]) {
        if scopeList == nil {
            if newScopes.isEmpty { return }
            scopeList = []
        }
        scopeList = newScopes
    }

    /// Add a scope.
    public final func addScope(_ scope: Scope) {
        if scopeList == nil { scopeList = [] }
        scopeList!.append(scope)
    }

    /// Remove all scopes, keeping the (now empty) container.
    public final func clearScopes() {
        if scopeList != nil { scopeList = [] }
    }

    /// Whether the feature applies to an object: true if there are no
    /// scopes, otherwise if any scope applies.
    public func appliesTo(_ object: FreeColObject?) -> Bool {
        guard let scopeList, !scopeList.isEmpty else { return true }
        return scopeList.contains { $0.appliesTo(object) }
    }

    // MARK: Reading XML

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        if let str = xr.attribute("source", default: nil as String?) {
            // Java leaves the source alone without a specification.
            if let spec = specification { source = spec.getType(str) }
        } else {
            source = nil
        }
        let first = xr.attribute("firstTurn", default: Int(Int32.min))
        if first != Int(Int32.min) { firstTurn = Turn(first) }
        let last = xr.attribute("lastTurn", default: Int(Int32.min))
        if last != Int(Int32.min) { lastTurn = Turn(last) }
        duration = xr.attribute("duration", default: 0)
        temporary = xr.attribute("temporary", default: false)
    }

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        clearScopes()
        try super.readChildren(xr)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == Scope.tag {
            let scope = Scope()
            try scope.readFromXML(xr)
            addScope(scope)
        } else {
            try super.readChild(xr)
        }
    }

    // MARK: Writing XML

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("source", source)
        if let firstTurn { xw.writeAttribute("firstTurn", firstTurn.number) }
        if let lastTurn { xw.writeAttribute("lastTurn", lastTurn.number) }
        if duration != 0 { xw.writeAttribute("duration", duration) }
        if temporary { xw.writeAttribute("temporary", temporary) }
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for scope in scopes { scope.toXML(xw) }
    }

    // MARK: Named

    public var nameKey: String {
        "\(id ?? "null").name"
    }

    // MARK: FreeColObject

    /// Java's equals: same source object, times, duration, temporary
    /// flag and scopes (in any order), and the same identifier.
    open override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? Feature else { return false }
        guard source === other.source,
              duration == other.duration,
              temporary == other.temporary,
              firstTurn?.number == other.firstTurn?.number,
              lastTurn?.number == other.lastTurn?.number,
              Feature.equalScopes(scopeList, other.scopeList) else { return false }
        return super.isEqual(to: other)
    }

    /// Java's ScopeContainer.equalScopes: two missing containers are
    /// equal, a missing one never equals a present (even empty) one,
    /// and present ones are equal if they hold the same scopes in any
    /// order.
    private static func equalScopes(_ a: [Scope]?, _ b: [Scope]?) -> Bool {
        guard let a else { return b == nil }
        guard let b else { return false }
        guard a.count == b.count else { return false }
        var unmatched = b
        for scope in a {
            guard let i = unmatched.firstIndex(of: scope) else { return false }
            unmatched.remove(at: i)
        }
        return true
    }

    open override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(source.map(ObjectIdentifier.init))
        hasher.combine(firstTurn?.number)
        hasher.combine(lastTurn?.number)
        hasher.combine(duration)
        hasher.combine(temporary)
        // Order-independent, like the scope equality.
        hasher.combine(scopes.reduce(0) { $0 &+ $1.hashValue })
    }
}

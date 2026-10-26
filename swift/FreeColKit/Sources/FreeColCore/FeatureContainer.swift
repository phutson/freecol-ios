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

/// The abilities and modifiers of an object, by id
/// (common/model/FeatureContainer).
///
/// Features are held in sets, so equal features (see Feature's
/// equality) are only held once, as in Java.
///
/// Java returns lookups as streams over hash sets, in no particular
/// order.  Swift's set order changes from run to run, so lookups here
/// return a fixed order instead: modifiers in application order and
/// abilities by id, source and value.  Code ported from Java must
/// still not depend on any order Java did not guarantee.
///
/// Not thread safe (Java locks); the engine runs inside one actor.
public final class FeatureContainer {

    private var abilities: [String: Set<Ability>]? {
        didSet { abilityLookups.removeAll() }
    }
    /// Lookups by id without a target or turn, the commonest kind
    /// (unit types asked whether they are naval, and so on), kept until
    /// the abilities change.  Abilities do not change once added.
    private var abilityLookups: [String: [Ability]] = [:]
    private var modifiers: [String: Set<Modifier>]?

    public init() {}

    // MARK: Abilities

    /// All abilities held, without filtering.
    public var abilityValues: [Ability] {
        FeatureContainer.ordered(abilities.map { $0.values.flatMap { $0 } } ?? [])
    }

    /// Whether a non-empty set of abilities are all true (Java's
    /// allAbilities).  No abilities at all means false.
    public static func allAbilities<S: Sequence>(_ abilities: S) -> Bool
        where S.Element == Ability {
        var ret = false
        for ability in abilities {
            if !ability.value { return false }
            ret = true
        }
        return ret
    }

    /// Whether the abilities with an id that apply are all true.
    public func hasAbility(_ id: String?, for target: FreeColSpecObjectType? = nil,
                           turn: Turn? = nil) -> Bool {
        FeatureContainer.allAbilities(self.abilities(id, for: target, turn: turn))
    }

    /// Whether there is any ability with an id, applicable or not.
    public func containsAbilityKey(_ key: String) -> Bool {
        !self.abilities(key, for: nil, turn: nil).isEmpty
    }

    /// The abilities with an id (or all, for nil) that apply to a
    /// target in a turn.
    public func abilities(_ id: String?, for target: FreeColSpecObjectType? = nil,
                          turn: Turn? = nil) -> [Ability] {
        guard let abilities else { return [] }
        if let id, target == nil, turn == nil, let found = abilityLookups[id] { return found }
        // Each id's set holds distinct abilities, and equal abilities
        // share an id, so the candidates are distinct already.
        let candidates: [Ability] = id.map { (abilities[$0] ?? []).filter { $0.appliesTo(target, turn: turn) } }
            ?? abilities.values.flatMap { $0 }.filter { $0.appliesTo(target, turn: turn) }
        let result = candidates.count < 2 ? candidates : FeatureContainer.ordered(candidates)
        if let id, target == nil, turn == nil { abilityLookups[id] = result }
        return result
    }

    /// Add an ability.
    ///
    /// - Returns: false if an equal ability was already present.
    @discardableResult
    public func addAbility(_ ability: Ability?) -> Bool {
        guard let ability else { return false }
        if abilities == nil { abilities = [:] }
        return abilities![ability.id ?? "", default: []].insert(ability).inserted
    }

    /// Remove an ability.
    ///
    /// - Returns: The ability, or nil if it was not present.
    @discardableResult
    public func removeAbility(_ ability: Ability?) -> Ability? {
        guard let ability, abilities != nil,
              abilities![ability.id ?? ""]?.remove(ability) != nil else { return nil }
        return ability
    }

    /// Remove all abilities with an id.
    public func removeAbilities(_ id: String) {
        abilities?[id] = nil
    }

    // MARK: Modifiers

    /// All modifiers held, without filtering.
    public var modifierValues: [Modifier] {
        Modifier.sortedForApplication(Set(modifiers.map { $0.values.flatMap { $0 } } ?? []))
    }

    /// The modifiers with an id (or all, for nil) that apply to a
    /// target in a turn.
    public func modifiers(_ id: String?, for target: FreeColSpecObjectType? = nil,
                          turn: Turn? = nil) -> [Modifier] {
        guard let modifiers else { return [] }
        // As for abilities, the candidates are distinct already (unless
        // a held modifier was changed, which Java would not notice
        // either).
        let candidates: [Modifier] = id.map { (modifiers[$0] ?? []).filter { $0.appliesTo(target, turn: turn) } }
            ?? modifiers.values.flatMap { $0 }.filter { $0.appliesTo(target, turn: turn) }
        return candidates.count < 2 ? candidates : Modifier.sortedForApplication(candidates)
    }

    /// Apply modifiers to a number, in application order.  An unknown
    /// modifier value makes the result unknown.
    public static func applyModifiers<S: Sequence>(_ number: Float, turn: Turn?,
                                                   _ modifiers: S) -> Float
        where S.Element == Modifier {
        var result = number
        for m in Modifier.sortedForApplication(modifiers) {
            let value = m.value(at: turn)
            if JavaMath.floatCompare(value, Modifier.unknown) == 0 { return value }
            result = m.apply(result, value)
        }
        return result
    }

    /// Add a modifier.
    ///
    /// - Returns: false if an equal modifier was already present.
    @discardableResult
    public func addModifier(_ modifier: Modifier?) -> Bool {
        guard let modifier else { return false }
        if modifiers == nil { modifiers = [:] }
        return modifiers![modifier.id ?? "", default: []].insert(modifier).inserted
    }

    /// Remove a modifier.
    ///
    /// - Returns: The modifier, or nil if it was not present.
    @discardableResult
    public func removeModifier(_ modifier: Modifier?) -> Modifier? {
        guard let modifier, modifiers != nil,
              modifiers![modifier.id ?? ""]?.remove(modifier) != nil else { return nil }
        return modifier
    }

    /// Remove all modifiers with an id.
    public func removeModifiers(_ id: String) {
        modifiers?[id] = nil
    }

    // MARK: Whole containers

    /// Add all the features of another object.
    public func addFeatures(of object: FreeColObject) {
        guard let other = object.featureContainer else { return }
        if let theirs = other.abilities {
            if abilities == nil { abilities = [:] }
            for (key, set) in theirs { abilities![key, default: []].formUnion(set) }
        }
        if let theirs = other.modifiers {
            if modifiers == nil { modifiers = [:] }
            for (key, set) in theirs { modifiers![key, default: []].formUnion(set) }
        }
    }

    /// Remove the features that came from another object, for the ids
    /// that object has features for.
    public func removeFeatures(of object: FreeColObject) {
        guard let other = object.featureContainer else { return }
        if abilities != nil, let theirs = other.abilities {
            for key in theirs.keys where abilities![key] != nil {
                abilities![key] = abilities![key]!.filter { $0.source !== object }
            }
        }
        if modifiers != nil, let theirs = other.modifiers {
            for key in theirs.keys where modifiers![key] != nil {
                modifiers![key] = modifiers![key]!.filter { $0.source !== object }
            }
        }
    }

    /// Replace the contents with another container's.
    public func copy(_ other: FeatureContainer?) {
        clear()
        guard let other else { return }
        for a in other.abilityValues { addAbility(a) }
        for m in other.modifierValues { addModifier(m) }
    }

    /// Remove everything.
    public func clear() {
        if abilities != nil { abilities = [:] }
        if modifiers != nil { modifiers = [:] }
    }

    /// Give copies of the features from one source a new source (all
    /// features, if oldSource is nil).
    public func replaceSource(_ oldSource: FreeColSpecObjectType?,
                              _ newSource: FreeColSpecObjectType?) {
        for ability in abilities(nil) where oldSource == nil || ability.source === oldSource {
            removeAbility(ability)
            let replacement = Ability(copying: ability)
            replacement.source = newSource
            addAbility(replacement)
        }
        for modifier in modifiers(nil) where oldSource == nil || modifier.source === oldSource {
            removeModifier(modifier)
            let replacement = Modifier(copying: modifier)
            replacement.source = newSource
            addModifier(replacement)
        }
    }

    /// Abilities by id, then source id, then value, for a stable order.
    private static func ordered<S: Sequence>(_ abilities: S) -> [Ability]
        where S.Element == Ability {
        abilities.sorted { a, b in
            let c = FreeColObject.compareIds(a, b)
            if c != 0 { return c < 0 }
            let s = FreeColObject.compareIds(a.source, b.source)
            if s != 0 { return s < 0 }
            return !a.value && b.value
        }
    }
}

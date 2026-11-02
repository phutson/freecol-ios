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

import FreeColCore
import FreeColIO
import FreeColServer

/// What a player may choose before a new game, as Java's start game
/// panel offers it: a nation and its advantage (PlayersTable), which
/// other nations play, and the map generator and game options
/// (OptionGroupUI), named as Java names them.
public struct NewGameSetup: Sendable {

    public struct NationChoice: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        /// Whether the player may take it: a selectable European nation.
        public let isPlayable: Bool
        public let isEuropean: Bool
        /// Whether it plays unless left out (not "not available").
        public let playsByDefault: Bool
        /// Its own nation type, the advantage it has unless another is
        /// chosen.
        public let nationTypeId: String
    }

    public struct Advantage: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
    }

    public enum OptionKind: Sendable, Equatable {
        case boolean
        case integer(minimum: Int, maximum: Int)
        case select([SelectItem])
    }

    public struct SelectItem: Sendable, Equatable {
        public let value: Int
        public let label: String
    }

    public struct Option: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let description: String
        public let kind: OptionKind
        public let value: GameEngine.OptionValue
        public let isEditable: Bool
    }

    public struct Group: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let options: [Option]
        public let groups: [Group]
    }

    public let nations: [NationChoice]
    /// The advantages on offer (the visible European nation types).
    public let advantages: [Advantage]
    /// The map generator options, then the game options.
    public let groups: [Group]

    /// The choices for a rule set and difficulty, with the spec's own
    /// values.
    public static func load(_ data: FreeColDataDirectory, rules: String, difficulty: String,
                            messages: MessageBundle) throws -> NewGameSetup {
        try Messages.$scopedBundle.withValue(messages) {
            let spec = try data.loadSpecification(rules, difficulty: difficulty)
            let nationOptions = NationOptions(specification: spec)
            let nations = spec.nations.compactMap { n -> NationChoice? in
                guard let id = n.id, !n.isUnknownEnemy, let state = nationOptions.nationState(n) else { return nil }
                let european = n.type?.isEuropean ?? false
                return NationChoice(id: id, name: Messages.name(n), isPlayable: european && n.isSelectable,
                                    isEuropean: european, playsByDefault: state != .notAvailable,
                                    nationTypeId: n.type?.id ?? "")
            }
            let advantages = spec.visibleEuropeanNationTypes.compactMap { t in
                t.id.map { Advantage(id: $0, name: Messages.name(t)) }
            }
            let groups = [spec.mapGeneratorOptions, spec.gameOptions].compactMap { $0.flatMap { group($0) } }
            return NewGameSetup(nations: nations, advantages: advantages, groups: groups)
        }
    }

    /// A group as the option dialogs show it, without the options they
    /// can not edit here (files, text, unit lists), or nil if nothing is
    /// left.
    private static func group(_ g: OptionGroup, editable: Bool = true) -> Group? {
        guard g.isVisible, let id = g.id else { return nil }
        let editable = editable && g.isEditable
        var options: [Option] = []
        var groups: [Group] = []
        for o in g.options {
            if let sub = o as? OptionGroup {
                if let s = group(sub, editable: editable) { groups.append(s) }
            } else if let option = option(o, editable) {
                options.append(option)
            }
        }
        if options.isEmpty && groups.isEmpty { return nil }
        return Group(id: id, name: Messages.name(id), options: options, groups: groups)
    }

    private static func option(_ o: AbstractOption, _ editable: Bool) -> Option? {
        guard let id = o.id else { return nil }
        let kind: OptionKind
        let value: GameEngine.OptionValue
        switch o {
        case let b as BooleanOption:
            kind = .boolean
            value = .boolean(b.value)
        case let s as SelectOption:
            kind = .select(s.itemValues.map { item in
                let label = item.label ?? String(item.value)
                return SelectItem(value: item.value, label: s.localizedLabels ? localized(label) : label)
            })
            value = .integer(s.value)
        case let i as IntegerOption:
            kind = .integer(minimum: i.minimumValue, maximum: i.maximumValue)
            value = .integer(i.value)
        default:
            return nil
        }
        let description = Messages.shortDescription(id)
        return Option(id: id, name: Messages.name(id), description: description == Messages.shortDescriptionKey(id) ? "" : description,
                      kind: kind, value: value, isEditable: editable)
    }

    /// A choice's label: its message, as Java shows it, or failing that
    /// its name, or the last word of its key (Java shows the key).
    private static func localized(_ key: String) -> String {
        let message = Messages.message(key)
        if message != key { return message }
        let name = Messages.name(key)
        if name != Messages.nameKey(key) { return name }
        let word = key.split(separator: ".").last.map(String.init) ?? key
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}

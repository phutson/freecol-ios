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

/// The changes an action or a new turn makes, and who may see each
/// (common/networking/ChangeSet).
///
/// The server's code adds changes as it changes the game; then
/// `build(_:)` gives each player what it is told, in Java's order.  Some
/// helpers also change the game (adding an ability, a history event or
/// a sale), as Java's do.
///
/// Working out what a player is told asks what it can see, and with fog
/// of war that refreshes its views of the tiles it sees, as in Java.
public final class ChangeSet {

    /// Whether a change is visible to a player.
    enum SeeCheck {
        case visible, invisible, special
    }

    /// Who a change is visible to (ChangeSet.See): all players, those
    /// who can see what changed, or just one, adjusted for a player
    /// who always, perhaps or never sees it.
    public struct See {

        enum Kind {
            case all, perhaps, only
        }

        let kind: Kind
        private(set) weak var seeAlways: Player?
        private(set) weak var seePerhaps: Player?
        private(set) weak var seeNever: Player?

        private init(_ kind: Kind) {
            self.kind = kind
        }

        /// Visible to every player.
        public static func all() -> See { See(.all) }

        /// Visible to the players who can see what changed.
        public static func perhaps() -> See { See(.perhaps) }

        /// Visible to one player only.
        public static func only(_ player: Player?) -> See { See(.only).always(player) }

        /// Also visible to a player.
        public func always(_ player: Player?) -> See {
            var see = self
            see.seeAlways = player
            return see
        }

        /// Visible to a player if it can see what changed.
        public func perhapsOnly(_ player: Player?) -> See {
            var see = self
            see.seePerhaps = player
            return see
        }

        /// Never visible to a player.
        public func except(_ player: Player?) -> See {
            var see = self
            see.seeNever = player
            return see
        }

        func check(_ player: Player?) -> SeeCheck {
            if let player {
                if player === seeNever { return .invisible }
                if player === seeAlways { return .visible }
                if player === seePerhaps { return .special }
            }
            switch kind {
            case .only: return .invisible
            case .all: return .visible
            case .perhaps: return .special
            }
        }
    }

    /// One change (ChangeSet.Change and its subclasses).
    enum Change {
        case attack(See, attacker: Unit, defender: Unit, success: Bool, defenderInSettlement: Bool)
        case attribute(See, key: String, value: String)
        case feature(See, parent: FreeColGameObject, child: FreeColObject, add: Bool)
        case message(See, ServerMessage)
        case move(See, unit: Unit, oldLocation: any Location, newTile: Tile)
        case object(See, FreeColGameObject?)
        case partial(See, [(key: String, value: String)])
        case players(See, [Player])
        case remove(See, tile: Tile?, contents: [FreeColGameObject])
        case spy(See, unit: Unit, settlement: Settlement)
        case stance(See, first: Player, stance: Player.Stance, second: Player)

        var see: See {
            switch self {
            case .attack(let see, _, _, _, _), .attribute(let see, _, _), .feature(let see, _, _, _),
                 .message(let see, _), .move(let see, _, _, _), .object(let see, _),
                 .partial(let see, _), .players(let see, _), .remove(let see, _, _),
                 .spy(let see, _, _), .stance(let see, _, _, _):
                return see
            }
        }

        /// Whether this change is about an object (Change.matches).
        func matches(_ fcgo: FreeColGameObject) -> Bool {
            if case .object(_, let o) = self { return o === fcgo }
            return false
        }

        /// Whether a player is told of this change (isNotifiable).
        func isNotifiable(_ player: Player) -> Bool {
            let check = see.check(player)
            switch self {
            case .attack(_, let attacker, let defender, _, _):
                switch check {
                case .visible: return true
                case .invisible: return false
                case .special: break
                }
                // Not canSeeUnit, which says no for units in
                // settlements, which should be animated.
                return player.owns(attacker) || player.owns(defender)
                    || (player.canSee(attacker.tile) && player.canSee(defender.tile))
            case .move(_, let unit, let oldLocation, _):
                if player.isAI { return false }
                switch check {
                case .visible: return true
                case .invisible: return false
                case .special: break
                }
                return Change.seeOld(player, unit, oldLocation) || player.canSeeUnit(unit)
            case .object(_, let fcgo):
                switch check {
                case .visible: return true
                case .invisible: return false
                case .special: break
                }
                guard let fcgo else { return false }
                if let unit = fcgo as? Unit { return player.canSeeUnit(unit) }
                if let ownable = fcgo as? Ownable, player.owns(ownable) { return true }
                // Work locations report their colony's tile, but are
                // never seen from outside.
                if fcgo is WorkLocation { return false }
                if let location = fcgo as? any Location { return player.canSee(location.tile) }
                return false
            case .remove(_, let tile, _):
                switch check {
                case .visible: return true
                case .invisible: return false
                case .special: break
                }
                // The tile must be visible with no other player's
                // settlement on it.
                guard let tile, player.canSee(tile) else { return false }
                guard let settlement = tile.settlement else { return true }
                return settlement.isDisposed || player.owns(settlement)
            case .attribute, .feature, .message, .partial, .players, .spy, .stance:
                return check == .visible
            }
        }

        /// Whether a player saw the unit's old location: its own unit,
        /// or a visible tile without a settlement, not aboard a unit.
        static func seeOld(_ player: Player, _ unit: Unit, _ oldLocation: any Location) -> Bool {
            if player.owns(unit) { return true }
            guard let oldTile = oldLocation.tile, player.canSee(oldTile) else { return false }
            return !(oldTile.hasSettlement || oldLocation is Unit)
        }

        /// A further change a player must also be told of: a unit seen
        /// leaving to where the player can not see it is removed.
        func consequence(_ player: Player) -> Change? {
            guard case .move(_, let unit, let oldLocation, _) = self,
                  Change.seeOld(player, unit, oldLocation), !player.canSeeUnit(unit),
                  !unit.isDisposed else { return nil }
            return .remove(.only(player), tile: unit.location as? Tile, contents: [unit])
        }

        /// What a player is told of this change (toMessage).
        func message(_ player: Player) throws -> PlayerChange? {
            switch self {
            case .attack(_, let attacker, let defender, let success, let inSettlement):
                guard isNotifiable(player) else { return nil }
                let a = player.owns(attacker) ? attacker : try attacker.reduceVisibility(attacker.tile, player)
                let d = player.owns(defender) ? defender : try defender.reduceVisibility(defender.tile, player)
                let attackerVisible = player.canSeeUnit(attacker)
                let defenderVisible = player.canSeeUnit(defender) && (!inSettlement || player.owns(defender))
                return .animateAttack(attacker: a, defender: d, success: success,
                                      addAttacker: !attackerVisible, addDefender: !defenderVisible)
            case .attribute(_, let key, let value):
                return .attribute(key: key, value: value)
            case .feature(_, let parent, let child, let add):
                guard isNotifiable(player) else { return nil }
                return .feature(parent: parent, add: add, children: [child])
            case .message(_, let message):
                guard isNotifiable(player) else { return nil }
                return .message(message)
            case .move(_, let unit, let oldLocation, let newTile):
                guard isNotifiable(player), let oldTile = oldLocation.tile else { return nil }
                let u = player.owns(unit) ? unit : try unit.reduceVisibility(oldTile, player)
                return .animateMove(unit: u, oldTile: oldTile, newTile: newTile,
                                    appears: !Change.seeOld(player, unit, oldLocation))
            case .object(_, let fcgo):
                guard isNotifiable(player), let fcgo else { return nil }
                return .update([fcgo], destination: player)
            case .partial(_, let fields):
                return .partial(fields)
            case .players(_, let players):
                guard isNotifiable(player) else { return nil }
                return .addPlayers(players, destination: player)
            case .remove(_, let tile, let contents):
                guard let main = contents.last else { return nil }
                let full = (main as? Ownable).map(player.owns) ?? false
                return .remove(divertId: tile?.id ?? player.id ?? "", objects: full ? contents : [main])
            case .spy(_, let unit, let settlement):
                guard isNotifiable(player) else { return nil }
                return .spy(unit: unit, settlement: settlement)
            case .stance(_, let first, let stance, let second):
                guard isNotifiable(player) else { return nil }
                return .stance(stance, first: first, second: second)
            }
        }
    }

    private(set) var changes: [Change] = []

    public init() {}

    /// A copy of another change set's changes.
    public init(copying other: ChangeSet) {
        changes = other.changes
    }

    public var isEmpty: Bool {
        changes.isEmpty
    }

    public func clear() {
        changes = []
    }

    /// Take back the updates of an object.
    public func remove(_ fcgo: FreeColGameObject) {
        changes.removeAll { $0.matches(fcgo) }
    }

    /// Add another change set's changes.
    public func merge(_ other: ChangeSet) {
        changes += other.changes
    }

    // MARK: Adding changes

    /// Updates of objects.
    @discardableResult
    public func add(_ see: See, _ objects: FreeColGameObject?...) -> ChangeSet {
        add(see, objects)
    }

    /// Updates of objects.
    @discardableResult
    public func add(_ see: See, _ objects: [FreeColGameObject?]) -> ChangeSet {
        for o in objects { changes.append(.object(see, o)) }
        return self
    }

    /// A message.
    @discardableResult
    public func add(_ see: See, message: ServerMessage) -> ChangeSet {
        changes.append(.message(see, message))
        return self
    }

    /// An attack, with copies of the units made now, as they may move,
    /// die or be captured before the players are told.
    @discardableResult
    public func addAttack(_ see: See, _ attacker: Unit, _ defender: Unit, _ success: Bool) throws -> ChangeSet {
        changes.append(.attack(see, attacker: try attacker.copy(), defender: try defender.copy(),
                               success: success, defenderInSettlement: defender.tile?.hasSettlement ?? false))
        return self
    }

    /// A setting merged into what each player is told.
    @discardableResult
    public func addAttribute(_ see: See, _ key: String, _ value: String) -> ChangeSet {
        changes.append(.attribute(see, key: key, value: value))
        return self
    }

    /// An object leaving where others could see it.
    @discardableResult
    public func addDisappear(_ owner: Player, _ tile: Tile, _ fcgo: FreeColGameObject) -> ChangeSet {
        changes.append(.remove(.perhaps().except(owner), tile: tile, contents: [fcgo]))
        changes.append(.object(.perhaps().except(owner), tile))
        return self
    }

    /// Add or remove an ability, telling its owner.
    @discardableResult
    public func addAbility(_ player: Player, _ object: FreeColGameObject, _ ability: Ability,
                           _ add: Bool) -> ChangeSet {
        changes.append(.feature(.only(player), parent: object, child: ability, add: add))
        if add { object.addAbility(ability) } else { object.removeAbility(ability) }
        return self
    }

    /// Add or remove a modifier, telling its owner.
    @discardableResult
    public func addModifier(_ player: Player, _ object: FreeColGameObject, _ modifier: Modifier,
                            _ add: Bool) -> ChangeSet {
        changes.append(.feature(.only(player), parent: object, child: modifier, add: add))
        if add { object.addModifier(modifier) } else { object.removeModifier(modifier) }
        return self
    }

    /// A history event for every live European player.
    @discardableResult
    public func addGlobalHistory(_ game: Game, _ history: HistoryEvent) -> ChangeSet {
        for p in game.liveEuropeanPlayers { addHistory(p, history) }
        return self
    }

    /// A message for every live European player but one.
    @discardableResult
    public func addGlobalMessage(_ game: Game, _ omit: Player?, _ message: ModelMessage) -> ChangeSet {
        for p in game.liveEuropeanPlayers where p !== omit { addMessage(p, message) }
        return self
    }

    /// A history event, added to the player's history.
    @discardableResult
    public func addHistory(_ player: Player, _ history: HistoryEvent) -> ChangeSet {
        changes.append(.feature(.only(player), parent: player, child: history, add: true))
        player.addHistory(history)
        return self
    }

    /// A message for a player.  As in Java, it is not added to the
    /// player's messages here.
    @discardableResult
    public func addMessage(_ player: Player, _ message: ModelMessage) -> ChangeSet {
        changes.append(.feature(.only(player), parent: player, child: message, add: true))
        return self
    }

    /// A unit moving to a tile, from a location.
    @discardableResult
    public func addMove(_ see: See, _ unit: Unit, _ location: any Location, _ tile: Tile) -> ChangeSet {
        changes.append(.move(see, unit: unit, oldLocation: location, newTile: tile))
        return self
    }

    /// New values of some of an object's fields, as name and value.
    @discardableResult
    public func addPartial(_ see: See, _ fcgo: FreeColGameObject,
                           _ fields: (String, String)...) -> ChangeSet {
        var map = fields.map { (key: $0.0, value: $0.1) }
        map.removeAll { $0.key == "id" }
        map.append((key: "id", value: fcgo.id ?? ""))
        changes.append(.partial(see, map))
        return self
    }

    /// A new player, for the others.
    @discardableResult
    public func addNewPlayer(_ player: Player) -> ChangeSet {
        changes.append(.players(.all().except(player), [player]))
        return self
    }

    /// New players, for everyone.
    @discardableResult
    public func addPlayers(_ players: [Player]) -> ChangeSet {
        changes.append(.players(.all(), players))
        return self
    }

    /// An object removed from a location, with what goes with it.
    @discardableResult
    public func addRemove(_ see: See, _ location: (any Location)?, _ object: FreeColGameObject) -> ChangeSet {
        changes.append(.remove(see, tile: location as? Tile, contents: object.disposables))
        return self
    }

    /// Objects removed from a location.
    @discardableResult
    public func addRemoves(_ see: See, _ location: (any Location)?, _ objects: [FreeColGameObject]) -> ChangeSet {
        for o in objects { addRemove(see, location, o) }
        return self
    }

    /// A sale to a settlement, recorded for the player.
    @discardableResult
    public func addSale(_ player: Player, _ settlement: Settlement, _ type: GoodsType, _ price: Int) -> ChangeSet {
        guard let game = settlement.game else { return self }
        let sale = LastSale(settlement, type, when: game.turn, price: price)
        changes.append(.feature(.only(player), parent: player, child: sale, add: true))
        player.addLastSale(sale)
        return self
    }

    /// A unit spying on a settlement, for its owner.
    @discardableResult
    public func addSpy(_ unit: Unit, _ settlement: Settlement) -> ChangeSet {
        changes.append(.spy(.only(unit.owner), unit: unit, settlement: settlement))
        return self
    }

    /// A player's stance towards another.
    @discardableResult
    public func addStance(_ see: See, _ first: Player, _ stance: Player.Stance, _ second: Player) -> ChangeSet {
        changes.append(.stance(see, first: first, stance: stance, second: second))
        return self
    }

    // MARK: Telling a player

    /// What a player is told of these changes (build), or nil for
    /// nothing: the changes it may see, in Java's order (by priority,
    /// keeping the order added), with updates merged and messages for
    /// the same object merged, and the settings gathered separately.
    public func build(_ player: Player) throws -> PlayerUpdate? {
        if changes.isEmpty { return nil }
        var messages: [PlayerChange] = []
        var diverted: [PlayerChange] = []
        for change in changes {
            guard change.isNotifiable(player), let m = try change.message(player) else { continue }
            if m.canMerge { diverted.append(m) } else { messages.append(m) }
            if let c = change.consequence(player), let m2 = try c.message(player) {
                if m2.canMerge { diverted.append(m2) } else { messages.append(m2) }
            }
        }
        messages = messages.stableSorted { $0.priority < $1.priority }
        diverted = diverted.stableSorted { $0.priority < $1.priority }

        var merged: [PlayerChange] = []
        for m in messages {
            if let head = merged.last, let both = head.merging(m) {
                merged[merged.count - 1] = both
            } else {
                merged.append(m)
            }
        }
        var update = PlayerUpdate(messages: merged)
        for case .attribute(let key, let value) in diverted { update.setAttribute(key, value) }
        return update.isEmpty ? nil : update
    }
}

extension Sequence {
    /// Sorted, keeping equal elements in order, as Java's sort does.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            areInIncreasingOrder(a.element, b.element)
                || (!areInIncreasingOrder(b.element, a.element) && a.offset < b.offset)
        }.map(\.element)
    }
}

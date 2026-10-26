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
import FreeColXML

/// The order players are told things in (Message.MessagePriority):
/// animations first, removals last.
public enum MessagePriority: Int, Comparable, Sendable {
    case attribute = -1
    case animation = 0
    case early = 1
    case addPlayer = 4
    case stance = 5
    case partial = 9
    case update = 10
    case normal = 15
    case owned = 20
    case late = 90
    case last = 99
    case remove = 100

    public static func < (a: MessagePriority, b: MessagePriority) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// A message the server's code adds to a change set itself, such as a
/// new turn starting (Java's Message subclasses other than those the
/// change set makes).
public protocol ServerMessage: AnyObject {
    /// The XML element name.
    var tag: String { get }
    var priority: MessagePriority { get }
    /// Whether it is one of Java's AttributeMessages, which take the
    /// update's settings when alone (MultipleMessage.simplify).
    var isAttributeMessage: Bool { get }
    /// The attributes, in any order.
    var attributes: [(key: String, value: String)] { get }
    func writeChildren(_ xw: FreeColXMLWriter)
}

/// One thing a player is told (one of Java's messages).
public enum PlayerChange {
    /// An attack to show (AnimateAttackMessage), with the units as the
    /// player may see them, included if the player could not see them.
    case animateAttack(attacker: Unit, defender: Unit, success: Bool, addAttacker: Bool, addDefender: Bool)
    /// A setting (AttributeMessage), merged into the whole update.
    case attribute(key: String, value: String)
    /// Features, history, messages or sales added to or removed from
    /// an object (FeatureChangeMessage).
    case feature(parent: FreeColGameObject, add: Bool, children: [FreeColObject])
    /// A message the server's code added.
    case message(ServerMessage)
    /// A move to show (AnimateMoveMessage), with the unit (or its
    /// carrier) included if it appears from where the player could not
    /// see it.
    case animateMove(unit: Unit, oldTile: Tile, newTile: Tile, appears: Bool)
    /// Objects to update, as the player sees them (UpdateMessage).
    case update([FreeColGameObject], destination: Player)
    /// New values of some fields of an object (PartialMessage).
    case partial([(key: String, value: String)])
    /// New players (AddPlayerMessage).
    case addPlayers([Player], destination: Player)
    /// Objects to remove (RemoveMessage), and where they were (a tile,
    /// or the player).
    case remove(divertId: String, objects: [FreeColGameObject])
    /// A settlement spied on (SpySettlementMessage).
    case spy(unit: Unit, settlement: Settlement)
    /// A stance change (SetStanceMessage).
    case stance(Player.Stance, first: Player, second: Player)

    public var priority: MessagePriority {
        switch self {
        case .animateAttack, .animateMove: .animation
        case .attribute: .attribute
        case .feature: .owned
        case .message(let m): m.priority
        case .update: .update
        case .partial: .partial
        case .addPlayers: .addPlayer
        case .remove: .remove
        case .spy: .normal
        case .stance: .stance
        }
    }

    /// Whether this is a setting, gathered apart (canMerge).
    var canMerge: Bool {
        if case .attribute = self { return true }
        return false
    }

    /// This and another message as one, if Java merges them: updates
    /// always, feature changes to the same object either way.
    func merging(_ other: PlayerChange) -> PlayerChange? {
        switch (self, other) {
        case let (.update(a, destination), .update(b, _)):
            return .update(a + b, destination: destination)
        case let (.feature(p, add, a), .feature(q, add2, b)) where p.id == q.id && add == add2:
            return .feature(parent: p, add: add, children: a + b)
        default:
            return nil
        }
    }

    // MARK: Java's message XML

    var tag: String {
        switch self {
        case .animateAttack: "animateAttack"
        case .attribute: "attribute"
        case .feature: "featureChange"
        case .message(let m): m.tag
        case .animateMove: "animateMove"
        case .update: "update"
        case .partial: "partial"
        case .addPlayers: "addPlayer"
        case .remove: "remove"
        case .spy: "spySettlement"
        case .stance: "setStance"
        }
    }

    /// Whether this is one of Java's AttributeMessages.
    var isAttributeMessage: Bool {
        if case .message(let m) = self { return m.isAttributeMessage }
        return true
    }

    var attributes: [(key: String, value: String)] {
        switch self {
        case let .animateAttack(attacker, defender, success, _, _):
            return [("attacker", attacker.id ?? ""), ("attackerTile", attacker.tile?.id ?? ""),
                    ("defender", defender.id ?? ""), ("defenderTile", defender.tile?.id ?? ""),
                    ("success", success ? "true" : "false")]
        case let .attribute(key, value):
            return [(key, value)]
        case let .feature(parent, add, _):
            return [("id", parent.id ?? ""), ("add", add ? "true" : "false")]
        case .message(let m):
            return m.attributes
        case let .animateMove(unit, oldTile, newTile, _):
            return [("unit", unit.id ?? ""), ("newTile", newTile.id ?? ""), ("oldTile", oldTile.id ?? "")]
        case .update, .addPlayers:
            return []
        case .partial(let fields):
            return fields
        case let .remove(divertId, objects):
            return [("divert", divertId)] + objects.enumerated().map { ("x\($0.offset)", $0.element.id ?? "") }
                + [("xLength", String(objects.count))]
        case let .spy(unit, settlement):
            return [("settlement", settlement.id ?? ""), ("unit", unit.id ?? "")]
        case let .stance(stance, first, second):
            return [("stance", stance.javaName), ("first", first.id ?? ""), ("second", second.id ?? "")]
        }
    }

    func writeChildren(_ xw: FreeColXMLWriter) {
        switch self {
        case let .animateAttack(attacker, defender, _, addAttacker, addDefender):
            if addAttacker { (attacker.isOnCarrier ? attacker.carrier : attacker)?.toXML(xw) }
            if addDefender { (defender.isOnCarrier ? defender.carrier : defender)?.toXML(xw) }
        case .feature(_, _, let children):
            for c in children { c.toXML(xw) }
        case .message(let m):
            m.writeChildren(xw)
        case let .animateMove(unit, _, _, appears):
            if appears { (unit.isOnCarrier ? unit.carrier : unit)?.toXML(xw) }
        case let .update(objects, destination):
            let ws = xw.replaceScope(.toClient(destination))
            for o in objects { o.toXML(xw) }
            xw.replaceScope(ws)
        case let .addPlayers(players, destination):
            let ws = xw.replaceScope(.toClient(destination))
            for p in players { p.toXML(xw) }
            xw.replaceScope(ws)
        case .spy(_, let settlement):
            // The spy sees the settlement as the server does.
            let ws = xw.clientPlayer == nil ? nil : xw.replaceScope(.toServer())
            settlement.tile?.toXML(xw)
            if let ws { xw.replaceScope(ws) }
        case .attribute, .partial, .remove, .stance:
            break
        }
    }

    /// Write as Java's message, with some settings added to its own
    /// attributes, replacing any of the same name.
    func toXML(_ xw: FreeColXMLWriter, settings: [(key: String, value: String)] = []) {
        xw.writeStartElement(tag)
        var all = attributes
        for s in settings {
            if let i = all.firstIndex(where: { $0.key == s.key }) { all[i].value = s.value } else { all.append(s) }
        }
        for a in all { xw.writeAttribute(a.key, a.value) }
        writeChildren(xw)
        xw.writeEndElement()
    }
}

/// What one player is told of a change set: its messages in order and
/// the settings gathered from it (Java's MultipleMessage).
public struct PlayerUpdate {

    public private(set) var messages: [PlayerChange]
    /// The settings, as a map: a later value for a key replaces an
    /// earlier one, in its place.
    public private(set) var attributes: [(key: String, value: String)] = []

    init(messages: [PlayerChange]) {
        self.messages = messages
    }

    mutating func setAttribute(_ key: String, _ value: String) {
        if let i = attributes.firstIndex(where: { $0.key == key }) {
            attributes[i].value = value
        } else {
            attributes.append((key, value))
        }
    }

    public var isEmpty: Bool {
        messages.isEmpty && attributes.isEmpty
    }

    /// Write as the message Java sends: one message alone (with the
    /// settings added to its attributes, if it is one of Java's
    /// AttributeMessages, as Java's simplify does), or a "multiple" of
    /// them with the settings.
    public func toXML(_ xw: FreeColXMLWriter) {
        if messages.count == 1 {
            let m = messages[0]
            if attributes.isEmpty {
                m.toXML(xw)
                return
            }
            if m.isAttributeMessage {
                m.toXML(xw, settings: attributes)
                return
            }
        }
        xw.writeStartElement("multiple")
        for a in attributes { xw.writeAttribute(a.key, a.value) }
        for m in messages { m.toXML(xw) }
        xw.writeEndElement()
    }
}

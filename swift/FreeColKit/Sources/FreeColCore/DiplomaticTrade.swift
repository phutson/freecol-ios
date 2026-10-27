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

/// An agreement between two Europeans, made of trade items
/// (common/model/DiplomaticTrade): peace at first contact, a scout's
/// negotiation, a carrier's trade, or tribute.  Like a native trade, its
/// identifier is empty and it is not registered with the game.  The
/// players are weak.
public final class DiplomaticTrade: FreeColGameObject {

    public static let tag = "diplomaticTrade"

    /// What brought the players together (DiplomaticTrade.TradeContext).
    public enum TradeContext: JavaEnum {
        /// First contact between Europeans.
        case contact
        /// A scout negotiating.
        case diplomatic
        /// A carrier trading.
        case trade
        /// An offensive unit demanding.
        case tribute

        public var javaName: String {
            switch self {
            case .contact: "CONTACT"
            case .diplomatic: "DIPLOMATIC"
            case .trade: "TRADE"
            case .tribute: "TRIBUTE"
            }
        }

        public var key: String { javaName.lowercased() }
    }

    /// Where the negotiation is (DiplomaticTrade.TradeStatus).
    public enum TradeStatus: JavaEnum {
        case proposeTrade, acceptTrade, rejectTrade

        public var javaName: String {
            switch self {
            case .proposeTrade: "PROPOSE_TRADE"
            case .acceptTrade: "ACCEPT_TRADE"
            case .rejectTrade: "REJECT_TRADE"
            }
        }
    }

    public var context: TradeContext?
    public var status: TradeStatus = .rejectTrade
    public weak var sender: Player?
    public weak var recipient: Player?
    public private(set) var items: [TradeItem] = []
    public private(set) var version = 0

    /// A new proposal.
    public init(game: Game, context: TradeContext, sender: Player?, recipient: Player?, items: [TradeItem] = [],
                version: Int = 0) {
        self.context = context
        self.sender = sender
        self.recipient = recipient
        status = .proposeTrade
        self.items = items
        self.version = version
        super.init(game: game, id: "") // Identifier not required
    }

    /// Read an agreement from the element the reader is on.
    public init(game: Game, _ xr: FreeColXMLReader) throws {
        super.init(game: game, id: "")
        try readFromXML(xr)
    }

    /// Peace between two players (makePeaceTreaty).
    public static func makePeaceTreaty(_ context: TradeContext, _ sender: Player, _ recipient: Player)
        -> DiplomaticTrade {
        let game = sender.game!
        let dt = DiplomaticTrade(game: game, context: context, sender: sender, recipient: recipient)
        dt.add(StanceTradeItem(game: game, source: sender, destination: recipient, stance: .peace))
        dt.add(StanceTradeItem(game: game, source: recipient, destination: sender, stance: .peace))
        return dt
    }

    public override var xmlTagName: String {
        DiplomaticTrade.tag
    }

    public override var isInternable: Bool {
        false
    }

    public func otherPlayer(_ player: Player?) -> Player? {
        sender === player ? recipient : sender
    }

    /// Add an item, replacing one of the same kind if it is unique.
    public func add(_ item: TradeItem) {
        if item.isUnique { items.removeAll { type(of: $0) == type(of: item) } }
        items.append(item)
    }

    public func incrementVersion() {
        version += 1
    }

    /// Drop an item.
    public func remove(_ item: TradeItem) {
        if let i = items.firstIndex(where: { $0 === item }) { items.remove(at: i) }
    }

    /// Drop every item.
    public func clear() {
        items = []
    }

    public var isEmpty: Bool { items.isEmpty }

    public var stance: Player.Stance? {
        items.lazy.compactMap { ($0 as? StanceTradeItem)?.stance }.first
    }

    // MARK: XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        context = xr.attribute("context", TradeContext.self, default: nil)
        sender = try xr.findFreeColGameObject(game!, "sender", Player.self, required: false)
        recipient = try xr.findFreeColGameObject(game!, "recipient", Player.self, required: false)
        status = xr.attribute("status", TradeStatus.self, default: .rejectTrade) ?? .rejectTrade
        version = xr.attribute("version", default: 0)
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        items = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let game = game!
        switch xr.localName {
        case ColonyTradeItem.tag: add(try ColonyTradeItem(game: game, xr))
        case GoldTradeItem.tag: add(try GoldTradeItem(game: game, xr))
        case GoodsTradeItem.tag: add(try GoodsTradeItem(game: game, xr))
        case InciteTradeItem.tag: add(try InciteTradeItem(game: game, xr))
        case StanceTradeItem.tag: add(try StanceTradeItem(game: game, xr))
        case UnitTradeItem.tag: add(try UnitTradeItem(game: game, xr))
        default: try super.readChild(xr)
        }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let context { xw.writeAttribute("context", context) }
        xw.writeAttribute("sender", sender)
        xw.writeAttribute("recipient", recipient)
        xw.writeAttribute("status", status)
        xw.writeAttribute("version", version)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for item in items { item.toXML(xw) }
    }

    public override var description: String {
        "[\(id ?? "") \(context?.javaName ?? "null") \(status.javaName) from=\(sender?.id ?? "null")"
            + " to=\(recipient?.id ?? "null") version=\(version) [" + items.map { " \($0)" }.joined() + " ]]"
    }
}

/// Gold offered in a trade (common/model/GoldTradeItem).
public final class GoldTradeItem: TradeItem {

    public static let tag = "goldTradeItem"

    public var gold = 0

    public init(game: Game, source: Player?, destination: Player?, gold: Int) {
        self.gold = gold
        super.init(game: game, id: "model.tradeItem.gold.name", source: source, destination: destination)
    }

    public override init(game: Game, _ xr: FreeColXMLReader) throws {
        try super.init(game: game, xr)
    }

    public override var xmlTagName: String { GoldTradeItem.tag }
    public override var isValid: Bool { gold >= 0 && (source?.checkGold(gold) ?? false) }
    public override var isUnique: Bool { true }
    public override var tradeGold: Int { gold }

    public override func evaluateFor(_ player: Player) -> Int {
        !isValid ? TradeItem.invalidTradeItem : source === player ? -gold : gold
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        gold = xr.attribute("gold", default: Int(Int32.min))
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("gold", gold)
    }

    public override var description: String { "[\(id ?? "") \(gold)]" }
}

/// A change of stance offered in a trade (common/model/StanceTradeItem).
public final class StanceTradeItem: TradeItem {

    public static let tag = "stanceTradeItem"

    public var stance: Player.Stance?

    public init(game: Game, source: Player?, destination: Player?, stance: Player.Stance) {
        self.stance = stance
        super.init(game: game, id: "model.tradeItem.stance.name", source: source, destination: destination)
    }

    public override init(game: Game, _ xr: FreeColXMLReader) throws {
        try super.init(game: game, xr)
    }

    public override var xmlTagName: String { StanceTradeItem.tag }
    public override var isValid: Bool { stance != nil }
    public override var isUnique: Bool { true }
    public override var tradeStance: Player.Stance? { stance }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        stance = xr.attribute("stance", Player.Stance.self, default: nil)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let stance { xw.writeAttribute("stance", stance) }
    }

    public override var description: String { "[\(id ?? "") \(stance?.javaName ?? "null")]" }
}

/// A colony offered in a trade (common/model/ColonyTradeItem), named by
/// identifier, as the other side may not see it.
public final class ColonyTradeItem: TradeItem {

    public static let tag = "colonyTradeItem"

    public private(set) var colonyId: String?
    public private(set) var colonyName: String?

    public init(game: Game, source: Player?, destination: Player?, colony: Colony) {
        colonyId = colony.id
        colonyName = colony.name
        super.init(game: game, id: "model.tradeItem.colony.name", source: source, destination: destination)
    }

    public override init(game: Game, _ xr: FreeColXMLReader) throws {
        try super.init(game: game, xr)
    }

    public override var xmlTagName: String { ColonyTradeItem.tag }
    public override var isValid: Bool { colonyId != nil }
    public override var isUnique: Bool { false }

    public override func colony(_ game: Game) -> Colony? {
        game.getFreeColGameObject(colonyId) as? Colony
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        colonyId = xr.attribute("colony", default: nil)
        colonyName = xr.attribute("colonyName", default: nil)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let colonyId { xw.writeAttribute("colony", colonyId) }
        if let colonyName { xw.writeAttribute("colonyName", colonyName) }
    }

    public override var description: String { "[\(id ?? "") \(colonyName ?? "null")]" }
}

/// A unit offered in a trade (common/model/UnitTradeItem).
public final class UnitTradeItem: TradeItem {

    public static let tag = "unitTradeItem"

    public weak var unit: Unit?

    public init(game: Game, source: Player?, destination: Player?, unit: Unit) {
        self.unit = unit
        super.init(game: game, id: "model.tradeItem.unit.name", source: source, destination: destination)
    }

    public override init(game: Game, _ xr: FreeColXMLReader) throws {
        try super.init(game: game, xr)
    }

    public override var xmlTagName: String { UnitTradeItem.tag }

    public override var isValid: Bool {
        guard let unit else { return false }
        return unit.owner === source && (unit.type?.isAvailableTo([destination]) ?? false)
    }

    public override var isUnique: Bool { false }
    public override var tradeUnit: Unit? { unit }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        unit = try xr.findFreeColGameObject(game!, "unit", Unit.self, required: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("unit", unit)
    }

    public override var description: String { "[\(id ?? "") \(unit?.id ?? "null")]" }
}

/// Inciting a player against another, offered in a trade
/// (common/model/InciteTradeItem).
public final class InciteTradeItem: TradeItem {

    public static let tag = "inciteTradeItem"

    public weak var victim: Player?

    public init(game: Game, source: Player?, destination: Player?, victim: Player) {
        self.victim = victim
        super.init(game: game, id: "model.tradeItem.incite.name", source: source, destination: destination)
    }

    public override init(game: Game, _ xr: FreeColXMLReader) throws {
        try super.init(game: game, xr)
    }

    public override var xmlTagName: String { InciteTradeItem.tag }

    public override var isValid: Bool {
        victim != nil && victim !== source && victim !== destination
    }

    public override var isUnique: Bool { true }
    public override var tradeVictim: Player? { victim }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        victim = try xr.findFreeColGameObject(game!, "victim", Player.self, required: true)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("victim", victim)
    }

    public override var description: String { "[\(id ?? "") \(victim?.id ?? "null")]" }
}

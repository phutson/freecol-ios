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

/// Something offered in a trade, from one player to another
/// (common/model/TradeItem).  Trade items are not registered with the
/// game.
///
/// The goods items are here, for native trade; the diplomatic items
/// (colonies, gold, stances, units, incitement) are with DiplomaticTrade.
/// The players are weak.
open class TradeItem: FreeColGameObject {

    /// The value of an item that is not valid.
    public static let invalidTradeItem = Int(Int32.min)

    public weak var source: Player?
    public weak var destination: Player?

    public init(game: Game, id: String?, source: Player?, destination: Player?) {
        self.source = source
        self.destination = destination
        super.init(game: game, id: id)
    }

    /// Read an item from the element the reader is on.
    public init(game: Game, _ xr: FreeColXMLReader) throws {
        super.init(game: game, id: "")
        try readFromXML(xr)
    }

    open override var isInternable: Bool {
        false
    }

    /// The player on the other side from one.
    public func other(_ player: Player?) -> Player? {
        player === source ? destination : source
    }

    open var isValid: Bool { false }
    open var isUnique: Bool { false }
    open var goods: Goods? { nil }
    /// What the item gives, by kind (TradeItem.getColony, getGold,
    /// getStance, getUnit and getVictim).
    open func colony(_ game: Game) -> Colony? { nil }
    open var tradeGold: Int { 0 }
    open var tradeStance: Player.Stance? { nil }
    open var tradeUnit: Unit? { nil }
    open var tradeVictim: Player? { nil }

    /// The value of the item to a player.
    open func evaluateFor(_ player: Player) -> Int {
        TradeItem.invalidTradeItem
    }

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        source = try xr.findFreeColGameObject(game!, "source", Player.self, required: false)
        destination = try xr.findFreeColGameObject(game!, "destination", Player.self, required: false)
    }

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("source", source)
        xw.writeAttribute("destination", destination)
    }
}

/// Goods offered in a trade (common/model/GoodsTradeItem).
open class GoodsTradeItem: TradeItem {

    public static let tag = "goodsTradeItem"

    private var tradedGoods: Goods?

    public init(game: Game, source: Player?, destination: Player?, goods: Goods?) {
        tradedGoods = goods
        super.init(game: game, id: "model.tradeItem.goods.name", source: source, destination: destination)
    }

    public override init(game: Game, _ xr: FreeColXMLReader) throws {
        try super.init(game: game, xr)
    }

    open override var xmlTagName: String {
        GoodsTradeItem.tag
    }

    open override var goods: Goods? {
        tradedGoods
    }

    public func setGoods(_ goods: Goods?) {
        tradedGoods = goods
    }

    /// Valid when the source owns where the goods are.
    open override var isValid: Bool {
        guard let goods = tradedGoods, goods.type != nil, goods.amount > 0,
              let owned = goods.location as? Ownable else { return false }
        return source?.owns(owned) ?? false
    }

    open override var isUnique: Bool { false }

    /// What the goods would fetch (or cost) in the player's market,
    /// after tax when bought from another.
    open override func evaluateFor(_ player: Player) -> Int {
        guard isValid, let goods = tradedGoods, let type = goods.type else {
            return TradeItem.invalidTradeItem
        }
        let market = player.market
        if source === player {
            return market.map { $0.bidPrice(type, goods.amount) } ?? -2 * goods.amount
        }
        guard let market else { return 2 * goods.amount }
        return Int(JavaMath.round(Double(market.salePrice(type, goods.amount))
            * (1.0 - Double(player.tax) / 100.0)))
    }

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        tradedGoods = nil
        try super.readChildren(xr)
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        tradedGoods?.toXML(xw)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == Goods.tag {
            tradedGoods = try Goods(game: game!, reading: xr)
        } else {
            try super.readChild(xr)
        }
    }
}

/// Goods offered in a trade with a native settlement, with the price
/// and the haggling so far (common/model/NativeTradeItem).
public final class NativeTradeItem: GoodsTradeItem {

    public static let nativeTag = "nativeTradeItem"

    /// No price yet.
    public static let priceUnset = 0
    /// No sale at any price.
    public static let priceInvalid = -1

    public var price = NativeTradeItem.priceUnset
    public var haggleCount = 0

    public override init(game: Game, source: Player?, destination: Player?, goods: Goods?) {
        super.init(game: game, source: source, destination: destination, goods: goods)
    }

    public convenience init(copying nti: NativeTradeItem) {
        self.init(game: nti.goods!.game!, source: nti.source, destination: nti.destination, goods: nti.goods)
        price = nti.price
        haggleCount = nti.haggleCount
    }

    public override init(game: Game, _ xr: FreeColXMLReader) throws {
        try super.init(game: game, xr)
    }

    public override var xmlTagName: String {
        NativeTradeItem.nativeTag
    }

    public var priceIsSet: Bool { price != NativeTradeItem.priceUnset }
    public var priceIsValid: Bool { price > 0 }

    /// Java's descendingPriceComparator: highest price first, then
    /// fewest haggles, then goods type order, as -1, 0 or 1.
    public static func compareDescendingPrice(_ a: NativeTradeItem, _ b: NativeTradeItem) -> Int {
        if a.price != b.price { return a.price > b.price ? -1 : 1 }
        if a.haggleCount != b.haggleCount { return a.haggleCount < b.haggleCount ? -1 : 1 }
        return GoodsType.compare(a.goods?.type, b.goods?.type)
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        price = xr.attribute("price", default: NativeTradeItem.priceInvalid)
        haggleCount = xr.attribute("haggleCount", default: -1)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("price", price)
        xw.writeAttribute("haggleCount", haggleCount)
    }

    /// Java's toString, with the goods' identifier for its name (Java
    /// uses the translated name, which a toString should not need).
    public override var description: String {
        "[\(id ?? "null") \(goods?.amount ?? 0) \(goods?.type?.id ?? "null") \(price) \(haggleCount)]"
    }
}

/// A trading session between a European unit and a native settlement
/// (common/model/NativeTrade).  Sessions are not registered with the
/// game; the unit and settlement are weak.
public final class NativeTrade: FreeColGameObject {

    public static let tag = "nativeTrade"

    /// The steps of a trading session (NativeTrade.NativeTradeAction).
    public enum NativeTradeAction: JavaEnum, CustomStringConvertible {
        // Requests from the European trader
        case open, close, buy, sell, gift
        // Positive responses from the native trader
        case ackOpen, ackBuy, ackSell, ackGift, ackBuyHaggle, ackSellHaggle
        // Negative responses from the native trader
        case nakGoods, nakHaggle, nakHostile, nakNosale, nakInvalid

        public var javaName: String {
            switch self {
            case .open: "OPEN"
            case .close: "CLOSE"
            case .buy: "BUY"
            case .sell: "SELL"
            case .gift: "GIFT"
            case .ackOpen: "ACK_OPEN"
            case .ackBuy: "ACK_BUY"
            case .ackSell: "ACK_SELL"
            case .ackGift: "ACK_GIFT"
            case .ackBuyHaggle: "ACK_BUY_HAGGLE"
            case .ackSellHaggle: "ACK_SELL_HAGGLE"
            case .nakGoods: "NAK_GOODS"
            case .nakHaggle: "NAK_HAGGLE"
            case .nakHostile: "NAK_HOSTILE"
            case .nakNosale: "NAK_NOSALE"
            case .nakInvalid: "NAK_INVALID"
            }
        }

        /// Whether the action ends the session.
        public var isClosing: Bool {
            switch self {
            case .close, .nakHaggle, .nakHostile, .nakNosale, .nakInvalid: true
            default: false
            }
        }

        /// Whether the European side sends it.
        public var isEuropean: Bool {
            switch self {
            case .open, .close, .buy, .sell, .gift: true
            default: false
            }
        }

        public var description: String {
            javaName
        }
    }

    public private(set) weak var unit: Unit?
    public private(set) weak var indianSettlement: IndianSettlement?
    public var count = 0
    public var buy = false
    public var sell = false
    public var gift = false
    public var item: NativeTradeItem?
    public private(set) var unitToSettlement: [NativeTradeItem] = []
    public private(set) var settlementToUnit: [NativeTradeItem] = []

    /// A new session, with everything still possible.
    public init(unit: Unit, indianSettlement: IndianSettlement) {
        self.unit = unit
        self.indianSettlement = indianSettlement
        buy = true
        sell = true
        gift = true
        super.init(game: unit.game!, id: "") // Identifier not needed
    }

    /// Read a session from the element the reader is on.
    public init(game: Game, _ xr: FreeColXMLReader) throws {
        super.init(game: game, id: nil)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        NativeTrade.tag
    }

    public override var isInternable: Bool {
        false
    }

    private var atWar: Bool {
        indianSettlement?.owner?.atWar(with: unit?.owner) ?? false
    }

    /// The session's key, "<unit id>-<settlement id>".
    public var key: String {
        NativeTrade.key(unit, indianSettlement)
    }

    public static func key(_ unit: Unit?, _ settlement: IndianSettlement?) -> String {
        "\(unit?.id ?? "null")-\(settlement?.id ?? "null")"
    }

    /// Whether buying is still possible: not at war, space on the unit
    /// and something priced to buy.
    public var canBuy: Bool {
        buy && !atWar && (unit?.spaceLeft ?? 0) > 0 && settlementToUnit.contains { $0.priceIsValid }
    }

    public var canSell: Bool {
        sell && !atWar && unitToSettlement.contains { $0.priceIsValid }
    }

    public var canGift: Bool {
        gift && (unit?.hasGoodsCargo ?? false)
    }

    public var hasNotTraded: Bool {
        buy && sell && gift
    }

    public var isDone: Bool {
        count < 0 || (!canBuy && !canSell && !canGift)
    }

    public func setDone() {
        count = -1
    }

    public func addToUnit(_ nti: NativeTradeItem) {
        unitToSettlement.append(nti)
    }

    /// Remove the items with equal goods (Java's Goods.equals: the same
    /// location, type, amount and identifier).
    public func removeFromUnit(_ nti: NativeTradeItem) {
        func equal(_ a: Goods?, _ b: Goods?) -> Bool {
            guard let a, let b else { return a == nil && b == nil }
            return a.location === b.location && a.type === b.type && a.amount == b.amount && a.id == b.id
        }
        unitToSettlement.removeAll { equal($0.goods, nti.goods) }
    }

    public func isCompatible(_ nt: NativeTrade) -> Bool {
        key == nt.key
    }

    /// List the goods each side has to offer.
    public func initialize() {
        guard let unit, let settlement = indianSettlement, let game = unit.game else { return }
        let unitPlayer = unit.owner, settlementPlayer = settlement.owner
        for g in unit.goodsList {
            unitToSettlement.append(NativeTradeItem(game: game, source: unitPlayer,
                                                    destination: settlementPlayer, goods: g))
        }
        for g in settlement.sellGoods(unit) {
            settlementToUnit.append(NativeTradeItem(game: game, source: settlementPlayer,
                                                    destination: unitPlayer, goods: g))
        }
    }

    /// Take the items from a compatible session, unless it is "equal"
    /// to this one.  As in Java, equal means the same game and the same
    /// identifier, and every session's identifier is empty, so between
    /// two sessions of a game this does nothing.
    public func mergeFrom(_ nt: NativeTrade) {
        if isCompatible(nt) && !(nt.game === game && nt.id == id) {
            unitToSettlement = nt.unitToSettlement
            settlementToUnit = nt.settlementToUnit
            item = nt.item
        }
    }

    /// Offer only the best few of the settlement's goods.
    public func limitSettlementToUnit(_ n: Int) {
        let best = settlementToUnit.filter(\.priceIsValid)
            .stableSorted { NativeTradeItem.compareDescendingPrice($0, $1) < 0 }
        if best.count <= n { return }
        for nti in best[n...] { nti.price = NativeTradeItem.priceInvalid }
    }

    public static func haggleUp(_ price: Int) -> Int {
        (price * 11) / 10
    }

    public static func haggleDown(_ price: Int) -> Int {
        (price * 9) / 10
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        buy = xr.attribute("buy", default: false)
        count = xr.attribute("count", default: -1)
        gift = xr.attribute("gift", default: false)
        sell = xr.attribute("sell", default: false)
        indianSettlement = try xr.findFreeColGameObject(game!, "settlement", IndianSettlement.self,
                                                        required: false)
        unit = try xr.findFreeColGameObject(game!, "unit", Unit.self, required: false)
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        unitToSettlement = []
        settlementToUnit = []
        item = nil
        try super.readChildren(xr)
    }

    // MARK: Writing XML

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("buy", buy)
        xw.writeAttribute("count", count)
        xw.writeAttribute("gift", gift)
        xw.writeAttribute("sell", sell)
        xw.writeAttribute("settlement", indianSettlement)
        xw.writeAttribute("unit", unit)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        xw.writeStartElement("settlementToUnit")
        for nti in settlementToUnit { nti.toXML(xw) }
        xw.writeEndElement()
        xw.writeStartElement("unitToSettlement")
        for nti in unitToSettlement { nti.toXML(xw) }
        xw.writeEndElement()
        item?.toXML(xw)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let game = game!
        switch xr.localName {
        case "settlementToUnit", "unitToSettlement":
            let toUnit = xr.localName == "settlementToUnit"
            while try xr.moreTags() {
                if xr.localName == NativeTradeItem.nativeTag {
                    let nti = try NativeTradeItem(game: game, xr)
                    if toUnit { settlementToUnit.append(nti) } else { unitToSettlement.append(nti) }
                } else {
                    xr.warn("\(toUnit ? "SettlementToUnit" : "UnitToSettlement")-item expected, not: \(xr.localName)")
                    try xr.swallowTag(xr.localName)
                }
            }
        case NativeTradeItem.nativeTag:
            item = try NativeTradeItem(game: game, xr)
        default:
            try super.readChild(xr)
        }
    }

    public override var description: String {
        "[\(NativeTrade.tag) \(unit?.id ?? "null") \(indianSettlement?.id ?? "null")"
            + " buy=\(buy) sell=\(sell) gift=\(gift) count=\(count)"
            + " item=\(item.map { "\($0)" } ?? "null") unitToSettlement["
            + unitToSettlement.map { " \($0)" }.joined() + "] settlementToUnit["
            + settlementToUnit.map { " \($0)" }.joined() + " ]]"
    }
}

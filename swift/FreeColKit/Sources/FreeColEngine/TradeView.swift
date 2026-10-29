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

// What Java's client shows when trading with natives (the client
// InGameController's nativeTradeHandler and nativeTrade, and the GUI's
// trade choices) and negotiating with other Europeans (NegotiationDialog).

/// A trade with a native settlement, at one of its steps: the natives'
/// answer, and what the player may do next.
public struct NativeTradeScreen: Sendable, Equatable {
    /// Goods the player could buy or sell.
    public struct Item: Sendable, Equatable {
        public let label: String
        public let price: Int
        /// The question of buying or selling it at the price (buy.text,
        /// sell.text).
        public let text: String
        /// For buying: whether the player can pay.
        public let canBuy: Bool
        /// For selling: the choice of giving it instead (which, as in
        /// Java, does nothing).
        public let giftLabel: String
    }

    public let unitId: String
    public let settlementId: String
    /// What the natives said to the last step (or the welcome).
    public let prompt: String
    /// What is shown after the first time.
    public let welcome: String
    public let canBuy: Bool
    public let canSell: Bool
    public let canGift: Bool
    /// The goods offered for sale, the best three at most.
    public let buy: [Item]
    /// The player's goods the natives would buy.
    public let sell: [Item]
    /// The player's goods to give.
    public let gift: [String]
    /// The goods haggled over, at the natives' new price: to buy (or
    /// sell) at it, or not.
    public let haggleBuy: Item?
    public let haggleSell: Item?
    public let labels: Labels

    /// The fixed texts of the trade's questions.
    public struct Labels: Sendable, Equatable {
        public let toBuy = Messages.message("tradeProposition.toBuy")
        public let toSell = Messages.message("tradeProposition.toSell")
        public let toGift = Messages.message("tradeProposition.toGift")
        public let buyQuestion = Messages.message("buyProposition.text")
        public let sellQuestion = Messages.message("sellProposition.text")
        public let giftQuestion = Messages.message("gift.text")
        public let takeBuy = Messages.message("buy.takeOffer")
        public let haggleBuy = Messages.message("buy.moreGold")
        public let takeSell = Messages.message("sell.takeOffer")
        public let haggleSell = Messages.message("sell.moreGold")
        public let nothing = Messages.message("nothing")
        public let cancel = Messages.message("cancel")
    }
}

/// The player's next step in a native trade.
public enum NativeTradeChoice: Sendable, Equatable {
    /// Buy goods (by their place in the screen's list, or nil for the
    /// goods haggled over), at the price or haggling for less.
    case buy(Int?, haggle: Bool)
    /// Sell goods, at the price or haggling for more.
    case sell(Int?, haggle: Bool)
    case gift(Int)
    /// Done trading.
    case close
}

/// One item of an agreement between Europeans.
public enum TradeOffer: Sendable, Equatable, Hashable {
    case gold(fromPlayer: Bool, amount: Int)
    /// A stance (Java's names) both are to take.
    case stance(fromPlayer: Bool, stance: String)
    case colony(fromPlayer: Bool, colonyId: String)
    /// Goods, from where they are (none for goods asked for).
    case goods(fromPlayer: Bool, goodsTypeId: String, amount: Int, locationId: String?)
    case unit(fromPlayer: Bool, unitId: String)
    /// To make war on another player.
    case incite(fromPlayer: Bool, victimId: String)

    public var fromPlayer: Bool {
        switch self {
        case .gold(let p, _), .stance(let p, _), .colony(let p, _), .goods(let p, _, _, _), .unit(let p, _),
             .incite(let p, _):
            p
        }
    }

    /// Of which there is one at most in an agreement (TradeItem.isUnique).
    public var isUnique: Bool {
        switch self {
        case .gold, .stance, .incite: true
        case .colony, .goods, .unit: false
        }
    }

    /// The kind of item, as the dialog clears them.
    public var kind: String {
        switch self {
        case .gold: "gold"
        case .stance: "stance"
        case .colony: "colony"
        case .goods: "goods"
        case .unit: "unit"
        case .incite: "incite"
        }
    }

    /// Put an item on the table (DiplomaticTrade.add): one of a unique
    /// kind replaces the one there, whoever gives it.
    public static func adding(_ item: TradeOffer, to items: [TradeOffer]) -> [TradeOffer] {
        (item.isUnique ? items.filter { $0.kind != item.kind } : items) + [item]
    }
}

/// A negotiation with another European, to show the player: one the
/// player starts, or a proposal received.
public struct Negotiation: Sendable, Equatable {
    /// The player's unit or colony negotiating.
    public let ourId: String
    /// The other's colony or unit.
    public let otherId: String
    public let otherPlayerId: String
    /// Java's TradeContext name (CONTACT, DIPLOMATIC, TRADE, TRIBUTE).
    public let context: String
    /// Whether the player made the agreement (or the other did).
    public let playerSent: Bool
    /// How many times the agreement has been sent; one never sent can
    /// not be accepted.
    public let version: Int
    /// What is on the table.
    public let items: [TradeOffer]
    public let comment: String
    /// For one the player starts by a move, the direction moved in.
    public let direction: String?
}

/// The negotiation as NegotiationDialog shows it, for what is on the
/// table now.
public struct NegotiationScreen: Sendable, Equatable {
    public struct Choice: Sendable, Equatable {
        public let id: String
        public let label: String
    }

    public struct GoodsChoice: Sendable, Equatable {
        public let goodsTypeId: String
        public let amount: Int
        public let label: String
        public let locationId: String?
    }

    /// Gold either side could give: at most, the text saying so, and
    /// how much is on the table (-1 for none).
    public struct Gold: Sendable, Equatable {
        public let maximum: Int
        public let text: String
        public let given: Int
    }

    public let title: String
    public let comment: String
    /// "<we> require of <them>" and "<we> offer <them>".
    public let demand: String
    public let offer: String
    public let goldDemand: Gold
    public let goldOffer: Gold
    /// The stances to choose from (Java's names), if they may be traded.
    public let stances: [Choice]?
    public let stance: String?
    public let coloniesDemand: [Choice]?
    public let coloniesOffer: [Choice]?
    public let goodsDemand: [GoodsChoice]?
    public let goodsOffer: [GoodsChoice]?
    /// The players either side could be asked to make war on.
    public let inciteDemand: [Choice]?
    public let inciteOffer: [Choice]?
    public let unitsDemand: [Choice]?
    public let unitsOffer: [Choice]?
    /// The agreement in words: the comment, then what the player
    /// offers, then what it asks in return.
    public let summary: [String]
    /// The answers: accepting (only an agreement sent before, and
    /// unchanged), sending, and cancelling (none at first contact).
    public let accept: String?
    public let acceptEnabled: Bool
    public let send: String
    public let cancel: String?
    public let labels: Labels

    public struct Labels: Sendable, Equatable {
        public let gold = Messages.name("model.tradeItem.gold")
        public let stance = Messages.name("model.tradeItem.stance")
        public let colony = Messages.name("model.tradeItem.colony")
        public let goods = Messages.name("model.tradeItem.goods")
        public let incite = Messages.name("model.tradeItem.incite")
        public let unit = Messages.name("model.tradeItem.unit")
        public let add = Messages.message("negotiationDialog.add")
        public let clear = Messages.message("negotiationDialog.clear")
    }
}

extension PlayerView {

    // MARK: Native trade

    /// What the client shows of a step of a native trade
    /// (nativeTradeHandler); the trade's goods for sale already limited
    /// to the best three.
    static func nativeTradeScreen(_ action: NativeTrade.NativeTradeAction, _ nt: NativeTrade,
                                  _ player: Player) -> NativeTradeScreen? {
        guard let is_ = nt.indianSettlement, let unit = nt.unit, let owner = is_.owner else { return nil }
        func withGoods(_ key: String) -> StringTemplate {
            let t = StringTemplate.template(key)
            if let type = nt.item?.goods?.type { _ = t.addNamed("%goodsType%", type) }
            return t
        }
        func said(_ key: String) -> String {
            Messages.message(withGoods(key)
                .addStringTemplate("%nation%", owner.nationLabel)
                .addStringTemplate("%settlement%", locationLabel(is_, for: player))) ?? ""
        }
        let welcome = Messages.message(StringTemplate.template("trade.welcome")
            .addStringTemplate("%nation%", owner.nationLabel)
            .addStringTemplate("%settlement%", locationLabel(is_, for: unit.owner))) ?? ""
        let prompt: String
        switch action {
        case .ackBuy: prompt = said("trade.bought")
        case .ackSell: prompt = said("trade.sold")
        case .ackGift: prompt = said("trade.gave")
        case .nakGoods:
            prompt = Messages.message(withGoods("trade.noTradeGoods")) ?? ""
        default: prompt = welcome
        }
        let market = unit.owner?.market
        func buyItem(_ nti: NativeTradeItem) -> NativeTradeScreen.Item? {
            guard let g = nti.goods, let type = g.type else { return nil }
            let label = g.label(sellable: true)
            return NativeTradeScreen.Item(
                label: Messages.message(label) ?? "", price: nti.price,
                text: Messages.message(StringTemplate.template("buy.text")
                    .addStringTemplate("%nation%", owner.nationLabel).addStringTemplate("%goods%", label)
                    .addAmount("%gold%", nti.price)
                    .addAmount("%euprice%", market?.bidPrice(type, g.amount) ?? 0)) ?? "",
                canBuy: unit.owner?.checkGold(nti.price) ?? false, giftLabel: "")
        }
        func sellItem(_ nti: NativeTradeItem) -> NativeTradeScreen.Item? {
            guard let g = nti.goods, let type = g.type else { return nil }
            let label = g.label(sellable: true)
            return NativeTradeScreen.Item(
                label: Messages.message(label) ?? "", price: nti.price,
                text: Messages.message(StringTemplate.template("sell.text")
                    .addStringTemplate("%nation%", owner.nationLabel).addStringTemplate("%goods%", label)
                    .addAmount("%gold%", nti.price)
                    .addAmount("%euprice%", market?.salePrice(type, g.amount) ?? 0)) ?? "",
                canBuy: false,
                giftLabel: Messages.message(StringTemplate.template("sell.gift")
                    .addStringTemplate("%goods%", label)) ?? "")
        }
        return NativeTradeScreen(
            unitId: unit.id ?? "", settlementId: is_.id ?? "", prompt: prompt, welcome: welcome,
            canBuy: nt.canBuy, canSell: nt.canSell, canGift: nt.canGift,
            buy: nt.settlementToUnit.filter(\.priceIsValid).compactMap(buyItem),
            sell: nt.unitToSettlement.filter(\.priceIsValid).compactMap(sellItem),
            gift: nt.unitToSettlement.map { Messages.message($0.goods?.label(sellable: true)) ?? "" },
            haggleBuy: action == .ackBuyHaggle ? nt.item.flatMap(buyItem) : nil,
            haggleSell: action == .ackSellHaggle ? nt.item.flatMap(sellItem) : nil,
            labels: NativeTradeScreen.Labels())
    }

    // MARK: Negotiation

    static let hugeDemand = 100000

    /// The items of an agreement, from the player's side.
    static func offers(_ agreement: DiplomaticTrade, _ player: Player) -> [TradeOffer] {
        agreement.items.compactMap { item in
            let mine = item.source === player
            switch item {
            case let i as GoldTradeItem: return .gold(fromPlayer: mine, amount: i.gold)
            case let i as StanceTradeItem: return i.stance.map { .stance(fromPlayer: mine, stance: $0.javaName) }
            case let i as ColonyTradeItem: return i.colonyId.map { .colony(fromPlayer: mine, colonyId: $0) }
            case let i as UnitTradeItem: return i.unit?.id.map { .unit(fromPlayer: mine, unitId: $0) }
            case let i as InciteTradeItem: return i.victim?.id.map { .incite(fromPlayer: mine, victimId: $0) }
            case let i as GoodsTradeItem:
                guard let g = i.goods, let type = g.type?.id else { return nil }
                return .goods(fromPlayer: mine, goodsTypeId: type, amount: g.amount, locationId: g.location?.id)
            default: return nil
            }
        }
    }

    /// The agreement, made on the player's copy of the game, objects it
    /// does not have looked up elsewhere.
    func agreement(_ n: Negotiation, _ items: [TradeOffer], _ status: DiplomaticTrade.TradeStatus,
                   lookup: (String) -> FreeColGameObject?) -> DiplomaticTrade? {
        func find<T: FreeColGameObject>(_ id: String?, _ type: T.Type) -> T? {
            guard let id else { return nil }
            return game.getFreeColGameObject(id, as: type) ?? lookup(id) as? T
        }
        guard let other = find(n.otherPlayerId, Player.self),
              let context = DiplomaticTrade.TradeContext.allCases.first(where: { $0.javaName == n.context })
        else { return nil }
        let me = player
        func ends(_ fromPlayer: Bool) -> (Player, Player) { fromPlayer ? (me, other) : (other, me) }
        var tradeItems: [TradeItem] = []
        for item in items {
            let (source, destination) = ends(item.fromPlayer)
            switch item {
            case let .gold(_, amount):
                tradeItems.append(GoldTradeItem(game: game, source: source, destination: destination, gold: amount))
            case let .stance(_, name):
                if let stance = Player.Stance.allCases.first(where: { $0.javaName == name }) {
                    tradeItems.append(StanceTradeItem(game: game, source: source, destination: destination,
                                                      stance: stance))
                }
            case let .colony(_, id):
                if let colony = find(id, Colony.self) {
                    tradeItems.append(ColonyTradeItem(game: game, source: source, destination: destination,
                                                      colony: colony))
                }
            case let .unit(_, id):
                if let unit = find(id, Unit.self) {
                    tradeItems.append(UnitTradeItem(game: game, source: source, destination: destination, unit: unit))
                }
            case let .incite(_, id):
                if let victim = find(id, Player.self) {
                    tradeItems.append(InciteTradeItem(game: game, source: source, destination: destination,
                                                      victim: victim))
                }
            case let .goods(_, typeId, amount, locationId):
                guard let type = game.specification?.getGoodsType(typeId) else { continue }
                let location = locationId.flatMap { find($0, FreeColGameObject.self) } as? any Location
                tradeItems.append(GoodsTradeItem(game: game, source: source, destination: destination,
                                                 goods: Goods(game: game, location: location, type: type,
                                                              amount: amount)))
            }
        }
        let (sender, recipient) = ends(n.playerSent)
        let dt = DiplomaticTrade(game: game, context: context, sender: sender, recipient: recipient,
                                 items: tradeItems, version: n.version)
        dt.status = status
        return dt
    }

    /// What NegotiationDialog shows for the items on the table, its
    /// panels updated for them; `changed` once the player has changed
    /// them.  The other's gold is as its nation summary has it.
    func negotiationScreen(_ n: Negotiation, _ items: [TradeOffer], changed: Bool,
                           otherGold: Int) -> NegotiationScreen? {
        guard let other = game.getFreeColGameObject(n.otherPlayerId, as: Player.self),
              let context = DiplomaticTrade.TradeContext.allCases.first(where: { $0.javaName == n.context })
        else { return nil }
        let nation = player.countryLabel, otherNation = other.countryLabel
        let demand = StringTemplate.template("negotiationDialog.demand")
            .addStringTemplate("%nation%", nation).addStringTemplate("%otherNation%", otherNation)
        let offer = StringTemplate.template("negotiationDialog.offer")
            .addStringTemplate("%nation%", nation).addStringTemplate("%otherNation%", otherNation)
        func gold(_ amount: Int, _ fromPlayer: Bool) -> NegotiationScreen.Gold {
            let given = items.lazy.compactMap { item -> Int? in
                if case let .gold(p, g) = item, p == fromPlayer { return g }
                return nil
            }.first ?? -1
            return NegotiationScreen.Gold(
                maximum: amount,
                text: Messages.message(StringTemplate.template("negotiationDialog.goldAvailable")
                    .addAmount("%amount%", amount)) ?? "",
                given: given)
        }
        let myGold = player.gold == Player.goldNotAccounted ? PlayerView.hugeDemand : player.gold

        // The panels each context has.
        let hasStance = context != .trade, hasColonies = context == .diplomatic
        let hasIncite = context != .trade, hasTrade = context == .trade

        var stances: [NegotiationScreen.Choice]?
        if hasStance {
            let s = player.stance(other)
            var list: [Player.Stance] = [s != .war ? .war : .ceaseFire]
            if s != .peace && s != .uncontacted { list.append(.peace) }
            if s == .peace { list.append(.alliance) }
            stances = list.map { NegotiationScreen.Choice(id: $0.javaName, label: Messages.name($0)) }
        }
        func colonies(_ source: Player, _ fromPlayer: Bool) -> [NegotiationScreen.Choice] {
            let given = Set(items.compactMap { item -> String? in
                if case let .colony(p, id) = item, p == fromPlayer { return id }
                return nil
            })
            return source.colonyList.filter { !given.contains($0.id ?? "") }
                .map { NegotiationScreen.Choice(id: $0.id ?? "", label: $0.name ?? "") }
        }
        func incite(_ source: Player, _ target: Player) -> [NegotiationScreen.Choice] {
            game.livePlayers(excluding: source).filter { $0 !== target && source.stance($0).isIncitable }
                .map { NegotiationScreen.Choice(id: $0.id ?? "", label: Messages.message($0.nationLabel) ?? "") }
        }
        // GoodsTradeItemPanel: the goods less those on the table.
        func goods(_ all: [(GoodsType, Int, String?)], _ fromPlayer: Bool) -> [NegotiationScreen.GoodsChoice] {
            var available = all
            for item in items {
                guard case let .goods(p, typeId, amount, _) = item, p == fromPlayer,
                      let i = available.firstIndex(where: { $0.0.id == typeId }) else { continue }
                if available[i].1 <= amount { available.remove(at: i) } else { available[i].1 -= amount }
            }
            return available.map { type, amount, location in
                NegotiationScreen.GoodsChoice(goodsTypeId: type.id ?? "", amount: amount,
                                              label: Messages.message(AbstractGoods(type, amount).label) ?? "",
                                              locationId: location)
            }
        }
        func units(_ all: [Unit], _ fromPlayer: Bool) -> [NegotiationScreen.Choice] {
            let given = Set(items.compactMap { item -> String? in
                if case let .unit(p, id) = item, p == fromPlayer { return id }
                return nil
            })
            return all.filter { !given.contains($0.id ?? "") }
                .map { NegotiationScreen.Choice(id: $0.id ?? "", label: Messages.message($0.label) ?? "") }
        }
        var goodsDemand: [NegotiationScreen.GoodsChoice]?, goodsOffer: [NegotiationScreen.GoodsChoice]?
        var unitsDemand: [NegotiationScreen.Choice]?, unitsOffer: [NegotiationScreen.Choice]?
        if hasTrade {
            let any = (game.specification?.storableGoodsTypeList ?? []).map { ($0, GoodsContainer.cargoSize, String?.none) }
            goodsDemand = goods(any, false)
            let ourUnit = game.getFreeColGameObject(n.ourId, as: Unit.self)
            let ourColony = game.getFreeColGameObject(n.ourId, as: Colony.self)
            let ours = (ourUnit?.goodsList ?? ourColony?.compactGoodsList ?? []).compactMap { g in
                g.type.map { ($0, min(g.amount, GoodsContainer.cargoSize), n.ourId as String?) }
            }
            goodsOffer = goods(ours, true)
            unitsDemand = units([], false)
            var ul: [Unit] = []
            if let u = ourUnit {
                if u.isCarrier { ul = u.unitList } else if u.isOnCarrier { ul = u.carrier?.unitList ?? [] } else { ul = [u] }
            } else if let c = ourColony {
                ul = c.unitList
            }
            unitsOffer = units(ul, true)
        }

        // The summary.
        let market = player.market
        func label(_ item: TradeOffer, saleDir: Bool) -> String {
            switch item {
            case let .gold(_, amount):
                return Messages.message(StringTemplate.template(Messages.descriptionKey("model.tradeItem.gold"))
                    .addAmount("%amount%", amount)) ?? ""
            case let .stance(_, name):
                return Player.Stance.allCases.first { $0.javaName == name }.map { Messages.message(.key($0)) ?? "" }
                    ?? ""
            case let .colony(_, id):
                let name = game.getFreeColGameObject(id, as: Colony.self)?.name
                return Messages.message(StringTemplate.template(Messages.descriptionKey("model.tradeItem.colony"))
                    .addName("%colony%", name)) ?? ""
            case let .unit(_, id):
                return Messages.message(game.getFreeColGameObject(id, as: Unit.self)?.label) ?? ""
            case let .incite(_, id):
                return Messages.message(StringTemplate.template(Messages.descriptionKey("model.tradeItem.incite"))
                    .addStringTemplate("%nation%", game.getFreeColGameObject(id, as: Player.self)?.nationLabel))
                    ?? ""
            case let .goods(_, typeId, amount, _):
                guard let type = game.specification?.getGoodsType(typeId) else { return "" }
                let text = Messages.message(AbstractGoods(type, amount).label) ?? ""
                let price = saleDir
                    ? StringTemplate.template("negotiationDialog.euSalePrice")
                        .addAmount("%priceTotal%", market?.salePrice(type, amount) ?? 0)
                    : StringTemplate.template("negotiationDialog.euBuyPrice")
                        .addAmount("%priceTotal%", market?.bidPrice(type, amount) ?? 0)
                return text + " " + (Messages.message(price) ?? "")
            }
        }
        var summary = [n.comment]
        let offers = items.filter(\.fromPlayer), demands = items.filter { !$0.fromPlayer }
        if !offers.isEmpty {
            summary.append(Messages.message(offer) ?? "")
            summary += offers.map { label($0, saleDir: true) }
        }
        if !demands.isEmpty {
            summary.append(offers.isEmpty ? Messages.message(demand) ?? "" : Messages.message("negotiationDialog.exchange"))
            summary += demands.map { label($0, saleDir: false) }
        }

        let stance = items.lazy.compactMap { item -> String? in
            if case let .stance(_, s) = item { return s }
            return nil
        }.first
        return NegotiationScreen(
            title: Messages.message("negotiationDialog.title." + context.key),
            comment: n.comment, demand: Messages.message(demand) ?? "", offer: Messages.message(offer) ?? "",
            goldDemand: gold(otherGold == Player.goldNotAccounted ? PlayerView.hugeDemand : otherGold, false),
            goldOffer: gold(myGold, true),
            stances: stances, stance: stance,
            coloniesDemand: hasColonies && other.isEuropean ? colonies(other, false) : nil,
            coloniesOffer: hasColonies ? colonies(player, true) : nil,
            goodsDemand: goodsDemand, goodsOffer: goodsOffer,
            inciteDemand: hasIncite ? incite(other, player) : nil,
            inciteOffer: hasIncite ? incite(player, other) : nil,
            unitsDemand: unitsDemand, unitsOffer: unitsOffer,
            summary: summary,
            accept: n.version > 0 ? Messages.message("negotiationDialog.accept") : nil,
            acceptEnabled: n.version > 0 && !changed,
            send: Messages.message("negotiationDialog.send"),
            cancel: n.version > 0 || context != .contact ? Messages.message("negotiationDialog.cancel") : nil,
            labels: NegotiationScreen.Labels())
    }

    /// The comment on an agreement the player sends to a settlement
    /// (DiplomaticTrade.getSendMessage).
    static func sendMessage(_ context: DiplomaticTrade.TradeContext, _ player: Player,
                            _ settlement: Settlement) -> String {
        Messages.message(StringTemplate.template("model.diplomaticTrade.send." + context.key)
            .addStringTemplate("%nation%", settlement.owner?.countryLabel)
            .addStringTemplate("%settlement%", locationLabel(settlement, for: player))) ?? ""
    }

    /// The comment on an agreement received (getReceiveMessage).
    static func receiveMessage(_ context: DiplomaticTrade.TradeContext, _ other: Player) -> String {
        Messages.message(StringTemplate.template("model.diplomaticTrade.receive." + context.key)
            .addStringTemplate("%nation%", other.countryLabel)) ?? ""
    }

    /// The question before demanding tribute of another European
    /// (confirmEuropeanTribute): the text and the most to ask, or what
    /// is told when the other is broke.
    static func europeanTribute(_ attacker: Unit, _ colony: Colony, _ summary: NationSummary?)
        -> (text: String, maximum: Int?) {
        guard let player = attacker.owner, let other = colony.owner else { return ("", nil) }
        let levels = ["low", "normal", "high"]
        let strength = player.calculateStrength(naval: false)
        let otherStrength = summary?.militaryStrength ?? strength
        let mil = otherStrength <= 1 || otherStrength * 5 < strength ? 0
            : strength == 0 || strength * 5 < otherStrength ? 2 : 1
        let gold = summary?.gold ?? 0
        if gold == 0 {
            return (Messages.message(StringTemplate.template("confirmTribute.broke")
                .addStringTemplate("%nation%", other.nationLabel)) ?? "", nil)
        }
        let fin = gold <= 100 ? 0 : gold <= 1000 ? 1 : 2
        return (Messages.message(StringTemplate.template("confirmTribute.european")
            .addStringTemplate("%nation%", other.nationLabel)
            .addStringTemplate("%danger%", StringTemplate.template("danger." + levels[mil]))
            .addStringTemplate("%finance%", StringTemplate.template("finance." + levels[fin]))) ?? "", gold)
    }
}

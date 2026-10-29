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

import Foundation
import FreeColCore
@testable import FreeColEngine
@testable import FreeColServer
import FreeColTestSupport
import Testing

/// Trading and negotiating through the engine, as the client does:
/// buying, selling, giving and haggling at a native settlement, and
/// proposing agreements to other Europeans (a peace at first contact, a
/// trade, tribute), with the computer players' answers, and spying.
@Suite struct TradePlayTests {

    typealias V = TradeViewTests

    static func trade(_ r: CommandResult) -> NativeTradeScreen? {
        V.requests(r).lazy.compactMap { if case .nativeTrade(let s) = $0 { s } else { nil } }.first
    }

    static func negotiation(_ r: CommandResult) -> Negotiation? {
        V.requests(r).lazy.compactMap { if case .negotiation(let n) = $0 { n } else { nil } }.first
    }

    static func notices(_ r: CommandResult) -> [String] {
        r.events.compactMap { if case .notice(let n) = $0 { n } else { nil } }
    }

    /// The trader by a settlement with goods to sell, its trade opened.
    static func open(_ unitId: String = "unit:6260", _ direction: String = "SW") async throws
        -> (GameEngine, NativeTradeScreen) {
        let engine = try await V.engine("natives")
        let r = try await engine.play(.move(unitId: unitId, direction: direction))
        return (engine, try #require(trade(r), "\(r.events)"))
    }

    static func amount(_ s: GameSnapshot, _ unitId: String, _ goods: String) -> Int {
        s.unit(unitId)?.goods.first { $0.typeId == goods }?.amount ?? 0
    }

    @Test func sell() async throws {
        let (engine, screen) = try await Self.open()
        let item = try #require(screen.sell.first)
        let before = await engine.snapshot()
        let r = await engine.respond(.nativeTrade(screen), .trade(.sell(0, haggle: false)))
        #expect(r.refusal == nil)
        #expect(r.snapshot.player?.gold == (before.player?.gold ?? 0) + item.price)
        let next = try #require(Self.trade(r))
        #expect(next.prompt.hasPrefix("Your") || next.prompt != next.welcome)
        #expect(!next.canSell && next.sell.count == screen.sell.count - 1)
        // Then done.
        let closed = await engine.respond(.nativeTrade(next), .trade(.close))
        #expect(Self.trade(closed) == nil && closed.refusal == nil)
    }

    @Test func buy() async throws {
        let (engine, screen) = try await Self.open("unit:6262", "S")
        #expect(screen.canBuy)
        let item = try #require(screen.buy.first)
        let before = await engine.snapshot()
        let r = await engine.respond(.nativeTrade(screen), .trade(.buy(0, haggle: false)))
        #expect(r.refusal == nil)
        #expect(r.snapshot.player?.gold == (before.player?.gold ?? 0) - item.price)
        #expect(Self.amount(r.snapshot, "unit:6262", "model.goods.cotton") > Self.amount(before, "unit:6262",
                                                                                          "model.goods.cotton"))
        #expect(Self.trade(r).map { !$0.canBuy } ?? true)
    }

    /// Once nothing is left to do, the trade is closed: sold, bought,
    /// and what was bought given.
    @Test func finishedTradeCloses() async throws {
        let (engine, screen) = try await Self.open("unit:6262", "S")
        var r = await engine.respond(.nativeTrade(screen), .trade(.sell(0, haggle: false)))
        var next = try #require(Self.trade(r), "\(r.events)")
        #expect(next.canBuy && !next.canSell)
        r = await engine.respond(.nativeTrade(next), .trade(.buy(0, haggle: false)))
        next = try #require(Self.trade(r), "\(r.events)")
        #expect(!next.canBuy && next.canGift)
        r = await engine.respond(.nativeTrade(next), .trade(.gift(0)))
        #expect(r.refusal == nil && Self.trade(r) == nil, "\(r.events)")
        var open = true
        _ = try await engine.serverActs { game, _, _, _ in
            let unit = game.getFreeColGameObject("unit:6262", as: Unit.self)
            let settlement = game.getFreeColGameObject(screen.settlementId, as: IndianSettlement.self)
            open = game.sessions.lookup(NativeTradeSession.key(unit, settlement)) != nil
            return ChangeSet()
        }
        #expect(!open)
    }

    @Test func gift() async throws {
        let (engine, screen) = try await Self.open()
        let before = await engine.snapshot()
        let goods = before.unit("unit:6260")?.goods ?? []
        let r = await engine.respond(.nativeTrade(screen), .trade(.gift(0)))
        #expect(r.refusal == nil)
        #expect(r.snapshot.player?.gold == before.player?.gold)
        #expect((r.snapshot.unit("unit:6260")?.goods.count ?? 0) == goods.count - 1)
        let next = try #require(Self.trade(r))
        #expect(!next.canGift && next.prompt != next.welcome)
    }

    /// Haggling: the natives offer more, or will not trade at all.
    @Test func haggle() async throws {
        let (engine, screen) = try await Self.open()
        let item = try #require(screen.sell.first)
        let r = await engine.respond(.nativeTrade(screen), .trade(.sell(0, haggle: true)))
        #expect(r.refusal == nil)
        if let next = Self.trade(r) {
            let offer = try #require(next.haggleSell)
            #expect(offer.label == item.label && offer.price > 0)
            // Taken at the new price.
            let gold = r.snapshot.player?.gold ?? 0
            let sold = await engine.respond(.nativeTrade(next), .trade(.sell(nil, haggle: false)))
            #expect(sold.snapshot.player?.gold == gold + offer.price)
        } else {
            #expect(Self.notices(r) == [Messages.message("trade.noTradeHaggle")].compactMap { $0 }
                    || !Self.notices(r).isEmpty)
            #expect(r.snapshot.unit("unit:6260")?.movesLeft == 0)
        }
    }

    // MARK: Negotiation

    /// A scout proposes to give gold for nothing; the French answer.
    @Test func negotiate() async throws {
        let engine = try await V.engine("diplomacy")
        let d = try #require(await V.direction(engine, "unit:6252", "ENTER_FOREIGN_COLONY_WITH_SCOUT"))
        let r = try await V.play(engine, .move(unitId: "unit:6252", direction: d), ["scoutColony": "negotiate"])
        let n = try #require(Self.negotiation(r))
        let gold = r.snapshot.player?.gold ?? 0
        let items = TradeOffer.adding(.gold(fromPlayer: true, amount: 100), to: [])
        let screen = try #require(await engine.negotiationScreen(n, items: items, changed: true))
        #expect(screen.goldOffer.given == 100 && screen.accept == nil)
        let answer = await engine.respond(.negotiation(n), .agreement(.send, items))
        #expect(answer.refusal == nil)
        let told = Self.notices(answer)
        #expect(!told.isEmpty || Self.negotiation(answer) != nil, "\(answer.events)")
        if told.contains(where: { $0.contains("accepted") }) {
            #expect(answer.snapshot.player?.gold == gold - 100)
        }
        // The scout has negotiated this turn.
        #expect(answer.snapshot.unit("unit:6252")?.movesLeft == 0)
    }

    /// Cancelling a negotiation the player started sends nothing.
    @Test func cancelNegotiation() async throws {
        let engine = try await V.engine("diplomacy")
        let d = try #require(await V.direction(engine, "unit:6252", "ENTER_FOREIGN_COLONY_WITH_SCOUT"))
        let r = try await V.play(engine, .move(unitId: "unit:6252", direction: d), ["scoutColony": "negotiate"])
        let n = try #require(Self.negotiation(r))
        let answer = await engine.respond(.negotiation(n), .agreement(.cancel, []))
        #expect(answer.events.isEmpty)
        #expect(answer.snapshot.unit("unit:6252")?.movesLeft == r.snapshot.unit("unit:6252")?.movesLeft)
    }

    /// Meeting the English: the peace treaty is shown, sent, and agreed.
    @Test func firstContact() async throws {
        let engine = try await V.engine("diplomacy")
        // The game was made with the soldier on tiles the player had not
        // explored, as no game would have it.
        _ = try await engine.serverActs { game, _, human, _ in
            _ = human.exploreForUnit(game.getFreeColGameObject("unit:6248", as: Unit.self))
            return ChangeSet()
        }
        let path = try #require(await engine.destinationPath("unit:6248"))
        let d = try #require(path.steps.first { $0.direction != nil }?.direction)
        let r = try await engine.play(.move(unitId: "unit:6248", direction: d))
        let n = try #require(Self.negotiation(r), "\(r.events)")
        #expect(n.context == "CONTACT" && n.version == 0 && n.playerSent)
        #expect(n.items == [.stance(fromPlayer: false, stance: "PEACE")])
        let screen = try #require(await engine.negotiationScreen(n, items: n.items, changed: false))
        #expect(screen.accept == nil && screen.cancel == nil)
        let answer = await engine.respond(.negotiation(n), .agreement(.send, n.items))
        #expect(answer.refusal == nil)
        let accepted = Messages.$scopedBundle.withValue(GameEngineTests.english) {
            Messages.message(StringTemplate.template("diplomacy.offerAccepted")
                .addStringTemplate("%nation%", StringTemplate.key("model.nation.english.name")))
        }
        #expect(Self.notices(answer).contains(accepted ?? ""), "\(answer.events)")
    }

    /// A French scout beside a colony offers gold; the player accepts.
    @Test func acceptProposal() async throws {
        let engine = try await V.engine("diplomacy")
        var colonyId = ""
        let events = try await engine.serverActs { game, _, human, _ in
            let spec = try #require(game.specification)
            let french = try #require(game.livePlayers.first { $0.nationId == "model.nation.french" })
            let colony = try #require(human.colonyList.first)
            colonyId = colony.id ?? ""
            let tile = try #require(colony.tile?.surroundingTiles(1, 1).first {
                $0.isLand && $0.settlement == nil && $0.units.isEmpty
            })
            let scout = try #require(french.units.first { $0.tile != nil && !$0.isNaval })
            scout.changeRole(try #require(spec.getRole("model.role.scout")), 1)
            _ = scout.setLocation(tile)
            let dt = DiplomaticTrade(game: game, context: .diplomatic, sender: french, recipient: human,
                                     items: [GoldTradeItem(game: game, source: french, destination: human, gold: 100)])
            let session = DiplomacySession.register(scout, settlement: colony, otherUnit: nil, in: game.sessions)
            let cs = ChangeSet()
            try french.csDiplomacy(session, dt, cs)
            return cs
        }
        let n = try #require(events.compactMap { e -> Negotiation? in
            if case .request(.negotiation(let n)) = e { return n }
            return nil
        }.first, "\(events)")
        #expect(n.ourId == colonyId && !n.playerSent && n.version == 1 && n.direction == nil)
        #expect(n.items == [.gold(fromPlayer: false, amount: 100)])
        let screen = try #require(await engine.negotiationScreen(n, items: n.items, changed: false))
        #expect(screen.accept != nil && screen.acceptEnabled && screen.cancel != nil)
        let changed = try #require(await engine.negotiationScreen(n, items: [], changed: true))
        #expect(!changed.acceptEnabled)
        let gold = await engine.snapshot().player?.gold ?? 0
        let r = await engine.respond(.negotiation(n), .agreement(.accept, n.items))
        #expect(r.refusal == nil)
        #expect(r.snapshot.player?.gold == gold + 100)
    }

    /// A merchantman offers its furs for gold.
    @Test func tradeWithColony() async throws {
        let engine = try await V.engine("diplomacy")
        let d = try #require(await V.direction(engine, "unit:6255", "ENTER_SETTLEMENT_WITH_CARRIER_AND_GOODS"))
        let r = try await engine.play(.move(unitId: "unit:6255", direction: d))
        let n = try #require(Self.negotiation(r))
        let screen = try #require(await engine.negotiationScreen(n, items: [], changed: false))
        let furs = try #require(screen.goodsOffer?.first)
        let items = [TradeOffer.goods(fromPlayer: true, goodsTypeId: furs.goodsTypeId, amount: furs.amount,
                                      locationId: furs.locationId),
                     .gold(fromPlayer: false, amount: 50)]
        let answer = await engine.respond(.negotiation(n), .agreement(.send, items))
        #expect(answer.refusal == nil)
        #expect(!Self.notices(answer).isEmpty || Self.negotiation(answer) != nil, "\(answer.events)")
        if Self.notices(answer).contains(where: { $0.contains("accepted") }) {
            #expect(Self.amount(answer.snapshot, "unit:6255", "model.goods.furs") == 0)
        }
    }

    /// A soldier demands tribute of a French colony.
    @Test func europeanTribute() async throws {
        let engine = try await V.engine("diplomacy")
        let d = try #require(await V.direction(engine, "unit:6254", "ATTACK_SETTLEMENT"))
        let gold = await engine.snapshot().player?.gold ?? 0
        let r = try await V.play(engine, .move(unitId: "unit:6254", direction: d),
                                 ["settlement": "tribute", "tributeAmount": "100"])
        #expect(r.refusal == nil && r.question == nil)
        let told = Self.notices(r) + r.notices
        #expect(!told.isEmpty, "\(r.events)")
        if told.contains(where: { $0.contains("accepted") }) { #expect(r.snapshot.player?.gold == gold + 100) }
        #expect(r.snapshot.unit("unit:6254")?.movesLeft == 0)
    }

    /// A scout looks into a French colony.
    @Test func spy() async throws {
        let engine = try await V.engine("diplomacy")
        let d = try #require(await V.direction(engine, "unit:6253", "ENTER_FOREIGN_COLONY_WITH_SCOUT"))
        let r = try await V.play(engine, .move(unitId: "unit:6253", direction: d), ["scoutColony": "spy"])
        #expect(r.refusal == nil)
        let seen = r.events.compactMap { if case .spied(let s) = $0 { s } else { nil } }
        let colony = try #require(seen.first, "\(r.events)")
        #expect(!colony.name.isEmpty && !colony.warehouse.isEmpty)
        #expect(r.snapshot.unit("unit:6253")?.movesLeft == 0)
    }
}

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
import FreeColIO
import FreeColServer
import FreeColTestSupport
import Testing

/// What the player is shown trading with natives and negotiating with
/// Europeans, through the engine, against Java's client (TradeOracle.java):
/// the natives' answer to a trade opened and the goods to buy, sell and
/// give; the negotiation dialog for agreements started and received; and
/// the question before demanding tribute of a colony.
@Suite struct TradeViewTests {

    static let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    static func java(_ name: String) throws -> JSONValue {
        let archive = try ZipArchive(contentsOf: PlayerViewTests.oracle.appendingPathComponent("trades.zip"))
        return try JSONValue.parse(try #require(try archive.contents(of: name + "-dutch.json")))
    }

    static func engine(_ game: String) async throws -> GameEngine {
        let url = PlayerViewTests.oracle.appendingPathComponent("games/freecol-\(game)-seed1.fsg")
        let engine = try GameEngine(loading: url, messages: GameEngineTests.english)
        _ = try await engine.play(.startTurn)
        return engine
    }

    static func bool(_ v: JSONValue?) -> Bool? {
        if case .bool(let b) = v { return b }
        return nil
    }

    static func int(_ v: JSONValue?) -> Int? { v?.intValue.map { Int($0) } }

    static func str(_ v: JSONValue?) -> String {
        if let i = v?.intValue { return String(i) }
        if let b = bool(v) { return String(b) }
        return v?.stringValue ?? "-"
    }

    static func row(_ v: JSONValue?) -> String { (v?.arrayValue ?? []).map { str($0) }.joined(separator: "|") }

    static func rows(_ v: JSONValue?) -> [String] {
        guard let v else { return ["none"] }
        return (v.arrayValue ?? []).map { $0.arrayValue != nil ? row($0) : str($0) }
    }

    /// Make a move, answering the questions as given (by their id's
    /// prefix).
    static func play(_ engine: GameEngine, _ action: GameEngine.PlayAction, _ picks: [String: String])
        async throws -> CommandResult {
        var answers: [String: String] = [:]
        for _ in 0..<10 {
            let r = try await engine.play(action, answers: answers)
            guard let q = r.question else { return r }
            let prefix = String(q.id.prefix { $0 != ":" })
            guard let pick = picks[prefix] else { return r }
            answers[q.id] = pick
        }
        return try await engine.play(action, answers: answers)
    }

    /// The direction a unit would move in to make a move of a type.
    static func direction(_ engine: GameEngine, _ unitId: String, _ moveType: String) async -> String? {
        guard let i = await engine.moveTypes(unitId)?.firstIndex(of: moveType) else { return nil }
        return directions[i]
    }

    static func requests(_ r: CommandResult) -> [ServerRequest] {
        r.events.compactMap { if case .request(let q) = $0 { q } else { nil } }
    }

    static func diff(_ ours: [String: [String]], _ theirs: [String: [String]]) -> [String] {
        var diffs: [String] = []
        for key in Set(ours.keys).union(theirs.keys).sorted() where ours[key] != theirs[key] {
            let o = ours[key] ?? [], t = theirs[key] ?? []
            let i = Array(zip(o, t)).firstIndex { $0 != $1 } ?? min(o.count, t.count)
            diffs.append("\(key) [\(i)]: ours \(i < o.count ? o[i] : "none"), Java's \(i < t.count ? t[i] : "none")")
        }
        return diffs
    }

    // MARK: Native trade

    static func ours(_ s: NativeTradeScreen) -> [String: [String]] {
        var menu: [String] = []
        if s.canBuy { menu.append(s.labels.toBuy) }
        if s.canSell { menu.append(s.labels.toSell) }
        if s.canGift { menu.append(s.labels.toGift) }
        return ["welcome": [s.welcome, s.prompt], "menu": menu,
                "buy": s.buy.map { "\($0.label)|\($0.price)|\($0.text)|\($0.canBuy)" },
                "sell": s.sell.map { "\($0.label)|\($0.price)|\($0.text)|\($0.giftLabel)" },
                "gift": s.gift]
    }

    static func javas(_ t: JSONValue) -> [String: [String]] {
        ["welcome": [str(t["welcome"]), str(t["welcome"])], "menu": rows(t["menu"]),
         "buy": (t["buy"]?.arrayValue ?? []).map {
             "\(str($0["label"]))|\(str($0["price"]))|\(str($0["text"]))|\(str($0["canBuy"]))"
         },
         "sell": (t["sell"]?.arrayValue ?? []).map {
             "\(str($0["label"]))|\(str($0["price"]))|\(str($0["text"]))|\(str($0["gift"]))"
         },
         "gift": rows(t["gift"])]
    }

    static var nativeTrades: [String] {
        ((try? java("natives"))?["nativeTrades"]?.arrayValue ?? []).map { str($0["unit"]) }
    }

    /// A laden wagon train enters a settlement: the natives answer as
    /// Java's do, and the player is shown what Java's client shows.
    @Test(arguments: nativeTrades)
    func nativeTradeOpensAsJava(_ unitId: String) async throws {
        let t = try #require(try Self.java("natives")["nativeTrades"]?.arrayValue?.first { Self.str($0["unit"]) == unitId })
        let engine = try await Self.engine("natives")
        let r = try await Self.play(engine, .move(unitId: unitId, direction: Self.str(t["direction"])), [:])
        let action = Self.str(t["action"])
        if let notice = t["notice"] {
            #expect(r.events.contains(.notice(Self.str(notice))), "\(action): \(r.events)")
            return
        }
        let screens = Self.requests(r).compactMap { if case .nativeTrade(let s) = $0 { s } else { nil } }
        if Self.bool(t["done"]) == true {
            #expect(screens.isEmpty)
            return
        }
        let screen = try #require(screens.first, "No trade: \(r.events) \(r.refusal ?? "")")
        #expect(screen.unitId == unitId && screen.settlementId == Self.str(t["settlement"]))
        let diffs = Self.diff(Self.ours(screen), Self.javas(t))
        #expect(diffs.isEmpty, Comment(rawValue: "\(unitId):\n" + diffs.joined(separator: "\n")))
    }

    // MARK: Negotiation

    static func offer(_ v: JSONValue, our: String) -> TradeOffer? {
        let a = (v.arrayValue ?? []).map { str($0) }
        guard a.count == 3 else { return nil }
        let mine = a[1] == "player"
        switch a[0] {
        case "gold": return .gold(fromPlayer: mine, amount: Int(a[2]) ?? 0)
        case "stance": return .stance(fromPlayer: mine, stance: a[2])
        case "colony": return .colony(fromPlayer: mine, colonyId: a[2])
        case "unit": return .unit(fromPlayer: mine, unitId: a[2])
        case "incite": return .incite(fromPlayer: mine, victimId: a[2])
        case "goods":
            let parts = a[2].split(separator: ":")
            return .goods(fromPlayer: mine, goodsTypeId: String(parts[0]), amount: Int(parts[1]) ?? 0,
                          locationId: mine ? our : nil)
        default: return nil
        }
    }

    static func negotiation(_ n: JSONValue) -> (Negotiation, [TradeOffer]) {
        let our = str(n["our"])
        let items = (n["items"]?.arrayValue ?? []).compactMap { offer($0, our: our) }
        return (Negotiation(ourId: our, otherId: str(n["other"]), otherPlayerId: str(n["otherPlayer"]),
                            context: str(n["context"]), playerSent: bool(n["playerSent"]) ?? true,
                            version: int(n["version"]) ?? 0, items: items, comment: str(n["comment"]),
                            direction: nil), items)
    }

    static func ours(_ s: NegotiationScreen) -> [String: [String]] {
        func choices(_ c: [NegotiationScreen.Choice]?) -> [String] { c.map { $0.map { "\($0.id)|\($0.label)" } } ?? ["none"] }
        func goods(_ c: [NegotiationScreen.GoodsChoice]?) -> [String] {
            c.map { $0.map { "\($0.goodsTypeId)|\($0.amount)|\($0.label)" } } ?? ["none"]
        }
        return ["texts": [s.title, s.comment, s.demand, s.offer],
                "goldDemand": ["\(s.goldDemand.maximum)|\(s.goldDemand.text)|\(s.goldDemand.given)"],
                "goldOffer": ["\(s.goldOffer.maximum)|\(s.goldOffer.text)|\(s.goldOffer.given)"],
                "stances": s.stances.map { [$0.map(\.id).joined(separator: "|"), $0.map(\.label).joined(separator: "|"),
                                            s.stance ?? ""] } ?? ["none"],
                "coloniesDemand": choices(s.coloniesDemand), "coloniesOffer": choices(s.coloniesOffer),
                "inciteDemand": choices(s.inciteDemand), "inciteOffer": choices(s.inciteOffer),
                "goodsDemand": goods(s.goodsDemand), "goodsOffer": goods(s.goodsOffer),
                "unitsDemand": choices(s.unitsDemand), "unitsOffer": choices(s.unitsOffer),
                "summary": s.summary, "buttons": [s.accept, s.send, s.cancel].compactMap { $0 }]
    }

    static func javas(negotiation n: JSONValue) -> [String: [String]] {
        func gold(_ v: JSONValue?) -> [String] { [row(v)] }
        var stances = ["none"]
        if let s = n["stances"]?.arrayValue {
            stances = [row(s[0]), row(s[1]), str(s[2])]
        }
        return ["texts": [str(n["title"]), str(n["comment"]), str(n["demand"]), str(n["offer"])],
                "goldDemand": gold(n["goldDemand"]), "goldOffer": gold(n["goldOffer"]), "stances": stances,
                "coloniesDemand": rows(n["coloniesDemand"]), "coloniesOffer": rows(n["coloniesOffer"]),
                "inciteDemand": rows(n["inciteDemand"]), "inciteOffer": rows(n["inciteOffer"]),
                "goodsDemand": rows(n["goodsDemand"]), "goodsOffer": rows(n["goodsOffer"]),
                "unitsDemand": rows(n["unitsDemand"]), "unitsOffer": rows(n["unitsOffer"]),
                "summary": rows(n["summary"]), "buttons": rows(n["buttons"])]
    }

    static var negotiations: [String] {
        ((try? java("diplomacy"))?["negotiations"]?.arrayValue ?? []).map { str($0["name"]) }
    }

    /// The negotiation dialog, for agreements with and without items on
    /// the table, in each context.
    @Test(arguments: negotiations)
    func negotiationShowsAsJava(_ name: String) async throws {
        let n = try #require(try Self.java("diplomacy")["negotiations"]?.arrayValue?.first { Self.str($0["name"]) == name })
        let engine = try await Self.engine("diplomacy")
        let (negotiation, items) = Self.negotiation(n)
        let screen = try #require(await engine.negotiationScreen(negotiation, items: items, changed: false))
        let diffs = Self.diff(Self.ours(screen), Self.javas(negotiation: n))
        #expect(diffs.isEmpty, Comment(rawValue: "\(name):\n" + diffs.joined(separator: "\n")))
    }

    /// A scout negotiating with a colony, and a merchantman trading with
    /// one, are shown the negotiation Java's client starts.
    @Test(arguments: [("envoy", "ENTER_FOREIGN_COLONY_WITH_SCOUT", ["scoutColony": "negotiate"]),
                      ("merchant", "ENTER_SETTLEMENT_WITH_CARRIER_AND_GOODS", [:])])
    func negotiationStartsAsJava(_ name: String, _ moveType: String, _ picks: [String: String]) async throws {
        let n = try #require(try Self.java("diplomacy")["negotiations"]?.arrayValue?.first { Self.str($0["name"]) == name })
        let engine = try await Self.engine("diplomacy")
        let unitId = Self.str(n["our"])
        let d = try #require(await Self.direction(engine, unitId, moveType))
        let r = try await Self.play(engine, .move(unitId: unitId, direction: d), picks)
        let started = Self.requests(r).compactMap { if case .negotiation(let s) = $0 { s } else { nil } }
        let negotiation = try #require(started.first, "\(r.events) \(r.question.map { "\($0)" } ?? "")")
        #expect(negotiation.ourId == unitId && negotiation.otherId == Self.str(n["other"]))
        #expect(negotiation.otherPlayerId == Self.str(n["otherPlayer"]))
        #expect(negotiation.context == Self.str(n["context"]) && negotiation.version == 0 && negotiation.playerSent)
        #expect(negotiation.items.isEmpty && negotiation.direction == d)
        #expect(negotiation.comment == Self.str(n["comment"]))
    }

    /// Received agreements are commented as Java's are.
    @Test func receivedComments() throws {
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let saved = try FreeColSavegameFile(url: PlayerViewTests.oracle.appendingPathComponent(
                "games/freecol-diplomacy-seed1.fsg")).readServerGame()
            let server = try #require(saved.game as? ServerGame)
            for n in try Self.java("diplomacy")["negotiations"]?.arrayValue ?? [] where Self.int(n["version"]) != 0
                || Self.str(n["context"]) == "CONTACT" {
                let other = try #require(server.getFreeColGameObject(Self.str(n["otherPlayer"]), as: Player.self))
                let context = try #require(DiplomaticTrade.TradeContext.allCases.first {
                    $0.javaName == Self.str(n["context"])
                })
                #expect(PlayerView.receiveMessage(context, other) == Self.str(n["comment"]))
            }
        }
    }

    /// A soldier demanding tribute of a colony is asked how much, with
    /// Java's question.
    @Test func europeanTributeAsJava() async throws {
        for t in try Self.java("diplomacy")["tributes"]?.arrayValue ?? [] {
            let engine = try await Self.engine("diplomacy")
            let unitId = Self.str(t["unit"])
            let d = try #require(await Self.direction(engine, unitId, "ATTACK_SETTLEMENT"))
            let r = try await Self.play(engine, .move(unitId: unitId, direction: d), ["settlement": "tribute"])
            if let broke = t["broke"] {
                #expect(r.notices.contains(Self.str(broke)))
            } else {
                let q = try #require(r.question)
                #expect(q.id == "tributeAmount:\(unitId)")
                #expect(q.text == Self.str(t["text"]))
                #expect(q.suggestion == Self.str(t["maximum"]))
            }
        }
    }
}

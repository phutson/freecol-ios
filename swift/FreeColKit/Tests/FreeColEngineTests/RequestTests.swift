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
import FreeColUtil
import Testing

/// What the server asks the player, passed on by the engine, and the
/// player's answers: the monarch, the Continental Congress, the
/// Fountain of Youth and Brewster's emigrants, native demands and loot.
@Suite struct RequestTests {

    static func engine(_ game: String) async throws -> GameEngine {
        let url = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("games/freecol-\(game)-seed1.fsg")
        let engine = try GameEngine(loading: url, messages: GameEngineTests.english)
        _ = try await engine.play(.startTurn)
        return engine
    }

    static func requests(_ events: [EngineEvent]) -> [ServerRequest] {
        events.compactMap { if case .request(let r) = $0 { r } else { nil } }
    }

    /// The monarch raises the tax on the most valuable goods; the player
    /// accepts.
    @Test func monarchRaisesTax() async throws {
        let engine = try await Self.engine("commands")
        let before = try #require(await engine.snapshot().player?.tax)
        let events = try await engine.serverActs { game, _, human, _ in
            let spec = try #require(game.specification)
            let furs = try #require(spec.getGoodsType("model.goods.furs"))
            let colony = try #require(human.colonyList.first)
            let goods = Goods(game: game, location: colony, type: furs, amount: 100)
            let template = StringTemplate.template(Monarch.MonarchAction.raiseTaxAct.textKey)
                .addStringTemplate("%goods%", StringTemplate.key(furs)).addAmount("%amount%", before + 5)
                .addAmount("%number%", 1).addName("%newWorld%", human.newLandName)
            MonarchSession.register(human, .raiseTaxAct, tax: before + 5, goods: goods, in: game.sessions)
            return ChangeSet().add(.only(human), message: MonarchActionMessage(.raiseTaxAct, template,
                                                                               human.nationId ?? "").setTax(before + 5))
        }
        let request = try #require(Self.requests(events).first)
        guard case let .monarch(action, title, text, yes, no) = request else {
            Issue.record("Not the monarch: \(request)")
            return
        }
        #expect(action == "RAISE_TAX_ACT")
        #expect(yes != nil && !no.isEmpty && !text.isEmpty && !title.isEmpty)
        let r = await engine.respond(request, .accept(true))
        #expect(r.refusal == nil)
        #expect(r.snapshot.player?.tax == before + 5)
    }

    /// News from the monarch needs no answer.
    @Test func monarchNews() async throws {
        let engine = try await Self.engine("commands")
        let events = try await engine.serverActs { _, _, human, _ in
            ChangeSet().add(.only(human), message: MonarchActionMessage(
                .waiveTax, StringTemplate.template(Monarch.MonarchAction.waiveTax.textKey), human.nationId ?? ""))
        }
        let request = try #require(Self.requests(events).first)
        guard case let .monarch(_, _, text, yes, _) = request else {
            Issue.record("Not the monarch: \(request)")
            return
        }
        #expect(yes == nil && !text.isEmpty)
    }

    @Test func chooseFather() async throws {
        let engine = try await Self.engine("commands")
        let events = try await engine.serverActs { game, _, human, _ in
            let spec = try #require(game.specification)
            let fathers = ["model.foundingFather.adamSmith", "model.foundingFather.hernandoDeSoto"]
                .compactMap { spec.getFoundingFather($0) }
            human.setOfferedFathers(fathers)
            return ChangeSet().add(.only(human), message: ChooseFoundingFatherMessage(fathers, nil))
        }
        let request = try #require(Self.requests(events).first)
        guard case let .chooseFather(offers) = request else {
            Issue.record("Not a father: \(request)")
            return
        }
        #expect(offers.map { $0.id } == ["model.foundingFather.adamSmith", "model.foundingFather.hernandoDeSoto"])
        #expect(offers.allSatisfy { !$0.name.isEmpty && !$0.typeName.isEmpty })
        _ = await engine.respond(request, .choice("model.foundingFather.adamSmith"))
        #expect(await engine.congressReport().currentId == "model.foundingFather.adamSmith")
    }

    @Test func fountainOfYouth() async throws {
        let engine = try await Self.engine("commands")
        let docks = try #require(await engine.europeScreen()).docks.count
        let events = try await engine.serverActs { _, _, human, _ in
            human.remainingEmigrants = 2
            return ChangeSet().add(.only(human), message: FountainOfYouthMessage(2))
        }
        let request = try #require(Self.requests(events).first)
        guard case let .emigrate(count, fountain, _, choices) = request else {
            Issue.record("Not emigration: \(request)")
            return
        }
        #expect(count == 2 && fountain && choices.count == 3)
        _ = await engine.respond(request, .choice("0"))
        _ = await engine.respond(request, .choice("2"))
        #expect(try #require(await engine.europeScreen()).docks.count == docks + 2)
    }

    @Test func brewsterChoosesEmigrant() async throws {
        let url = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("games/freecol-europe-seed1.fsg")
        let engine = try GameEngine(loading: url, messages: GameEngineTests.english)
        let docks = try #require(await engine.europeScreen()).docks.count
        _ = try await engine.serverActs { _, _, human, _ in
            human.immigration = human.immigrationRequired
            return ChangeSet()
        }
        let start = try await engine.play(.startTurn)
        let request = try #require(Self.requests(start.events).first)
        guard case let .emigrate(count, fountain, _, choices) = request else {
            Issue.record("Not emigration: \(request)")
            return
        }
        #expect(count == 1 && !fountain && choices.count == 3)
        let r = await engine.respond(request, .choice("1"))
        #expect(r.refusal == nil)
        #expect(try #require(await engine.europeScreen()).docks.count == docks + 1)
    }

    @Test func nativeDemand() async throws {
        let engine = try await Self.engine("natives")
        var colonyId = "", food = 0
        let events = try await engine.serverActs { game, controller, human, _ in
            let foodType = try #require(game.specification?.getGoodsType("model.goods.food"))
            // A brave next to a colony with food asks for some.
            let natives = try #require(game.livePlayers.first { $0.isIndian && $0.units.contains { !$0.isNaval } })
            let brave = try #require(natives.units.first { $0.tile != nil })
            var found: (Colony, Tile)?
            for c in human.colonyList where found == nil && c.goodsCount(foodType) > 50 {
                if let t = c.tile?.surroundingTiles(1, 1).first(where: { t in
                    t.isLand && t.settlement == nil && t.units.allSatisfy { $0.owner === natives }
                }) {
                    found = (c, t)
                }
            }
            let (colony, tile) = try #require(found)
            colonyId = colony.id ?? ""
            food = colony.goodsCount(foodType)
            _ = brave.setLocation(tile)
            brave.movesLeft = 3
            return try #require(try controller.perform(.indianDemand(unit: brave.id, colony: colony.id,
                                                                     type: "model.goods.food", amount: "50", result: nil),
                                                      by: natives))
        }
        let request = try #require(Self.requests(events).first)
        guard case let .nativeDemand(_, colony, goods, amount, title, text, _, _) = request else {
            Issue.record("Not a demand: \(request)")
            return
        }
        #expect(colony == colonyId && goods == "model.goods.food" && amount == 50)
        #expect(!title.isEmpty && !text.isEmpty)
        _ = await engine.respond(request, .accept(true))
        let after = try #require(await engine.colonyScreen(colonyId))
        #expect(after.warehouse.first { $0.typeId == "model.goods.food" }?.amount == food - 50)
    }

    @Test func lootCargo() async throws {
        let engine = try await Self.engine("commands")
        var winnerId = ""
        let events = try await engine.serverActs { game, _, human, _ in
            let winner = try #require(human.units.first { $0.isNaval && $0.hasSpaceLeft })
            winnerId = winner.id ?? ""
            let loser = try #require(game.livePlayers.first { $0 !== human && $0.isEuropean }?.units.first { $0.isNaval })
            let spec = try #require(game.specification)
            let capture = [Goods(game: game, location: nil, type: spec.getGoodsType("model.goods.sugar")!, amount: 60),
                           Goods(game: game, location: nil, type: spec.getGoodsType("model.goods.rum")!, amount: 40)]
            _ = LootSession.register(winner, loser, capture, in: game.sessions)
            return ChangeSet().add(.only(human), message: LootCargoMessage(winner, loser.id ?? "", capture))
        }
        let request = try #require(Self.requests(events).first)
        guard case let .loot(winner, _, goods, space, _) = request else {
            Issue.record("Not loot: \(request)")
            return
        }
        #expect(winner == winnerId && goods.count == 2 && space > 0)
        let r = await engine.respond(request, .goods([goods[0]]))
        #expect(r.refusal == nil)
        #expect(r.snapshot.unit(winnerId)?.goods.contains { $0.typeId == "model.goods.sugar" && $0.amount == 60 } == true)
    }
}

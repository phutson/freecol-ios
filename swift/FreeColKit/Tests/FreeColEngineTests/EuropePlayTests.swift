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
import FreeColEngine
import FreeColServer
import FreeColTestSupport
import Testing

/// Europe through the engine, as its panel does: buying and selling,
/// boycotts, recruiting, training, boarding, roles and sailing.
@Suite struct EuropePlayTests {

    static func engine() async throws -> GameEngine {
        let url = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("games/freecol-europe-seed1.fsg")
        let engine = try GameEngine(loading: url, messages: GameEngineTests.english)
        _ = try await engine.play(.startTurn)
        return engine
    }

    static func europe(_ engine: GameEngine) async throws -> EuropeScreen {
        try #require(await engine.europeScreen())
    }

    @Test func buyAndSell() async throws {
        let engine = try await Self.engine()
        var asked: [String] = []
        let before = try await Self.europe(engine)
        let ship = try #require(before.carriers.first { $0.spaceLeft > 0 })
        let offer = try #require(ship.loads["model.goods.sugar"])
        #expect(offer.amount == 100)
        _ = try await PlayTests.playAccepting(engine, .load(goodsTypeId: "model.goods.sugar", amount: 100,
                                                            carrierId: ship.id), asked: &asked)
        let bought = try await Self.europe(engine)
        #expect(bought.carrier(ship.id)?.goods.contains { $0.typeId == "model.goods.sugar" && $0.amount == 100 } == true)
        #expect(bought.gold == before.gold - offer.price)

        // Furs are boycotted: selling them asks, and paying the arrears
        // (asked again) lifts the boycott.
        let furs = try #require(before.market.first { $0.typeId == "model.goods.furs" })
        #expect(!furs.canTrade && furs.arrears > 0)
        _ = try await PlayTests.playAccepting(engine, .unload(goodsTypeId: "model.goods.furs", amount: 100,
                                                              carrierId: ship.id), asked: &asked)
        #expect(asked.contains("boycott:model.goods.furs"))
        #expect(asked.contains("payArrears:model.goods.furs"))
        let paid = try await Self.europe(engine)
        #expect(paid.market.first { $0.typeId == "model.goods.furs" }?.canTrade == true)
        #expect(paid.gold == bought.gold - furs.arrears)
        // Now they sell.
        _ = try await engine.play(.unload(goodsTypeId: "model.goods.furs", amount: 100, carrierId: ship.id))
        let sold = try await Self.europe(engine)
        #expect(sold.carrier(ship.id)?.goods.contains { $0.typeId == "model.goods.furs" } == false)
        #expect(sold.gold > paid.gold)
    }

    @Test func recruitTrainAndBoard() async throws {
        let engine = try await Self.engine()
        let before = try await Self.europe(engine)
        #expect(before.canRecruit)
        _ = try await engine.play(.recruit(index: 0))
        let recruited = try await Self.europe(engine)
        #expect(recruited.docks.count == before.docks.count + 1)
        #expect(recruited.gold == before.gold - before.recruitPrice)

        let cheapest = try #require(recruited.train.first { $0.affordable })
        _ = try await engine.play(.train(unitTypeId: cheapest.typeId))
        let trained = try await Self.europe(engine)
        #expect(trained.docks.count == recruited.docks.count + 1)
        #expect(trained.gold == recruited.gold - cheapest.price)
        // One too dear is refused, with Java's notice.
        if let dear = trained.train.first(where: { !$0.affordable }) {
            let r = try await engine.play(.train(unitTypeId: dear.typeId))
            #expect(!r.notices.isEmpty)
            #expect(try await Self.europe(engine).docks.count == trained.docks.count)
        }

        let ship = try #require(trained.carriers.first { !$0.canBoard.isEmpty })
        let passenger = try #require(ship.canBoard.first)
        _ = try await engine.play(.board(unitId: passenger, carrierId: ship.id))
        let boarded = try await Self.europe(engine)
        #expect(boarded.carrier(ship.id)?.unitIds.contains(passenger) == true)
        #expect(!boarded.docks.contains(passenger))
        _ = try await engine.play(.leaveShip(unitId: passenger))
        #expect(try await Self.europe(engine).docks.contains(passenger))
    }

    @Test func rolesAndSailing() async throws {
        let engine = try await Self.engine()
        var asked: [String] = []
        let before = try await Self.europe(engine)
        // A colonist on the docks armed as a soldier, bought here.
        var armed: (String, RoleChoice)?
        for id in before.docks where armed == nil {
            if let c = await engine.roleChoices(id).first(where: { $0.roleId == "model.role.soldier" && $0.price > 0 }) {
                armed = (id, c)
            }
        }
        let (soldier, choice) = try #require(armed)
        _ = try await engine.play(.equip(unitId: soldier, roleId: choice.roleId, count: choice.count))
        #expect(await engine.snapshot().unit(soldier)?.roleId == "model.role.soldier")
        #expect(try await Self.europe(engine).gold == before.gold - choice.price)

        // A ship sails for the New World, leaving the docks' colonists.
        let ship = try #require(before.carriers.first { $0.spaceLeft > 0 })
        let map = try #require(await engine.destinations(ship.id).first)
        _ = try await PlayTests.playAccepting(engine, .sail(carrierId: ship.id, destinationId: map.id), asked: &asked)
        #expect(asked.contains("leaveColonists:\(ship.id)"))
        let sailing = try await Self.europe(engine)
        #expect(!sailing.inPort.contains(ship.id))
        #expect(sailing.toAmerica.contains(ship.id))
    }
}

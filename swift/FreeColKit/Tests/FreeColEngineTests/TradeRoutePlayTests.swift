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

/// Trade routes through the engine, as the client uses them: made,
/// refused when unusable, given to a unit, followed, and deleted.  The
/// monarch's mercenaries, answered as any request of his.
@Suite struct TradeRoutePlayTests {

    /// A merchantman in one port, with sugar there to carry to another.
    static func setUp() async throws -> (engine: GameEngine, ship: String, from: String, to: String) {
        let engine = try await RequestTests.engine("commands")
        var ship = "", from = "", to = ""
        _ = try await engine.serverActs { game, _, human, _ in
            let ports = human.colonyList.filter(\.isConnectedPort)
            try #require(ports.count >= 2)
            let unit = try #require(human.units.first { $0.isNaval && $0.isCarrier && !$0.isAtSea })
            for g in unit.compactGoodsList { unit.goodsContainer?.removeGoods(g.type!, g.amount) }
            _ = unit.setLocation(ports[0].tile)
            unit.movesLeft = unit.initialMovesLeft
            let sugar = try #require(game.specification?.getGoodsType("model.goods.sugar"))
            ports[0].goodsContainer?.addGoods(sugar, 200)
            ship = unit.id ?? ""
            from = ports[0].id ?? ""
            to = ports[1].id ?? ""
            return ChangeSet()
        }
        return (engine, ship, from, to)
    }

    static func stop(_ id: String, _ cargo: [String]) -> TradeStopInfo {
        TradeStopInfo(locationId: id, locationName: "", cargo: cargo)
    }

    @Test func makeAndRefuse() async throws {
        let (engine, _, from, to) = try await Self.setUp()
        var r = try await engine.play(.newTradeRoute)
        #expect(r.refusal == nil && r.notices.isEmpty)
        _ = try await engine.play(.newTradeRoute)
        var screen = await engine.tradeRoutes()
        #expect(screen.routes.count == 2 && screen.routes[0].name != screen.routes[1].name)
        #expect(screen.locations.contains { $0.locationId == from } && !screen.goodsIds.isEmpty)
        var route = screen.routes[0]

        // One stop is not enough, nor stops with nothing to load, nor a
        // goods type loaded everywhere; nor another route's name.
        route.stops = [Self.stop(from, ["model.goods.sugar"])]
        r = try await engine.play(.updateTradeRoute(route))
        #expect(!r.notices.isEmpty)
        route.stops = [Self.stop(from, []), Self.stop(to, [])]
        r = try await engine.play(.updateTradeRoute(route))
        #expect(!r.notices.isEmpty)
        route.stops = [Self.stop(from, ["model.goods.sugar"]), Self.stop(to, ["model.goods.sugar"])]
        r = try await engine.play(.updateTradeRoute(route))
        #expect(!r.notices.isEmpty)
        var clash = route
        clash.name = screen.routes[1].name
        clash.stops = [Self.stop(from, ["model.goods.sugar"]), Self.stop(to, [])]
        r = try await engine.play(.updateTradeRoute(clash))
        #expect(!r.notices.isEmpty)
        #expect(await engine.tradeRoutes().routes[0].stops.isEmpty)

        // A good one.
        route.name = "Sugar"
        route.stops = [Self.stop(from, ["model.goods.sugar"]), Self.stop(to, [])]
        r = try await engine.play(.updateTradeRoute(route))
        #expect(r.notices.isEmpty)
        screen = await engine.tradeRoutes()
        #expect(screen.routes[0].name == "Sugar" && screen.routes[0].stops.map(\.cargo) == [["model.goods.sugar"], []])

        // Deleted.
        _ = try await engine.play(.deleteTradeRoute(routeId: route.id))
        #expect(await engine.tradeRoutes().routes.count == 1)
    }

    /// A ship loads at the first stop, sails, unloads at the second, and
    /// deleting the route frees it.
    @Test func follow() async throws {
        let (engine, ship, from, to) = try await Self.setUp()
        _ = try await engine.play(.newTradeRoute)
        var route = try #require(await engine.tradeRoutes().routes.first)
        route.stops = [Self.stop(from, ["model.goods.sugar"]), Self.stop(to, [])]
        _ = try await engine.play(.updateTradeRoute(route))
        _ = try await engine.play(.assignTradeRoute(unitId: ship, routeId: route.id))
        #expect(await engine.tradeRoutes().routes[0].unitIds == [ship])
        let stock = try #require(await engine.colonyScreen(to)).warehouse.first { $0.typeId == "model.goods.sugar" }?.amount ?? 0

        // The first turn's orders load the sugar.
        var answers: [String: String] = [:]
        var r = try await engine.play(.executeGotoOrders)
        while let q = r.question, answers.count < 10 {
            answers[q.id] = q.choices.first?.id ?? ""
            r = try await engine.play(.executeGotoOrders, answers: answers)
        }
        #expect(r.refusal == nil)
        #expect((r.snapshot.unit(ship)?.goods.first { $0.typeId == "model.goods.sugar" }?.amount ?? 0) > 0)

        // Turns pass until it arrives and unloads.
        var delivered = false
        for _ in 0..<40 where !delivered {
            r = try await engine.play(.endTurn, answers: ["endTurn": "yes"])
            let n = try #require(await engine.colonyScreen(to)).warehouse.first { $0.typeId == "model.goods.sugar" }?.amount ?? 0
            delivered = n > stock
        }
        #expect(delivered)
        #expect(await engine.tradeRoutes().routes[0].unitIds == [ship])

        _ = try await engine.play(.deleteTradeRoute(routeId: route.id))
        #expect(await engine.tradeRoutes().routes.isEmpty)
    }

    /// Taking a route from a unit, or clearing its orders, ends it.
    @Test func clear() async throws {
        let (engine, ship, from, to) = try await Self.setUp()
        _ = try await engine.play(.newTradeRoute)
        var route = try #require(await engine.tradeRoutes().routes.first)
        route.stops = [Self.stop(from, ["model.goods.sugar"]), Self.stop(to, [])]
        _ = try await engine.play(.updateTradeRoute(route))
        _ = try await engine.play(.assignTradeRoute(unitId: ship, routeId: route.id))
        _ = try await engine.play(.clearOrders(unitId: ship))
        #expect(await engine.tradeRoutes().routes[0].unitIds.isEmpty)
    }

    /// The monarch offers mercenaries; they are accepted and paid for.
    @Test func mercenaries() async throws {
        let engine = try await RequestTests.engine("commands")
        let before = try #require(await engine.snapshot().player?.gold)
        var price = 0
        let events = try await engine.serverActs { game, _, human, random in
            let spec = try #require(game.specification)
            _ = try #require(spec.getUnitType("model.unit.veteranSoldier"))
            let mercs = [AbstractUnit(id: "model.unit.veteranSoldier", roleId: "model.role.soldier", number: 2)]
            price = 200
            human.modifyGold(1000)
            let template = StringTemplate.template(Monarch.MonarchAction.monarchMercenaries.textKey)
                .addAmount("%gold%", price).addStringTemplate("%mercenaries%", AbstractUnit.listLabel(", ", mercs))
            MonarchSession.register(human, .monarchMercenaries, mercenaries: mercs, price: price, in: game.sessions)
            return ChangeSet().add(.only(human), message: MonarchActionMessage(.monarchMercenaries, template,
                                                                               human.nationId ?? ""))
        }
        let request = try #require(RequestTests.requests(events).first)
        guard case let .monarch(action, _, _, yes, _) = request else {
            Issue.record("Not the monarch: \(request)")
            return
        }
        #expect(action == "MONARCH_MERCENARIES" && yes != nil)
        let r = await engine.respond(request, .accept(true))
        #expect(r.refusal == nil)
        #expect(r.snapshot.player?.gold == before + 1000 - price)
    }
}

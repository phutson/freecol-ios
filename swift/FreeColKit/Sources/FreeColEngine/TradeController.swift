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
import FreeColServer

/// Trading and negotiating at a settlement (the client
/// InGameController's moveTrade, moveDiplomacy, moveSpy and the
/// European half of moveTribute).
extension PlayController {

    /// A laden carrier at a settlement (moveTrade): a trade to negotiate
    /// with a colony, or one opened with natives, which they answer.
    func moveTrade(_ unitId: String, _ direction: Direction) -> Bool {
        guard clearGotoOrders(unitId), let u = unit(unitId), let s = settlement(unitId, direction) else {
            return false
        }
        if let colony = s as? Colony {
            negotiate(u, colony, .trade, direction)
        } else if let is_ = s as? IndianSettlement {
            _ = command(.nativeTrade(action: NativeTrade.NativeTradeAction.open.javaName,
                                     trade: CommandElement(serializing: NativeTrade(unit: u, indianSettlement: is_))))
        }
        return false
    }

    /// Show the player a negotiation it starts with a colony
    /// (showNegotiationDialog), to send if not cancelled.
    func negotiate(_ u: Unit, _ colony: Colony, _ context: DiplomaticTrade.TradeContext, _ direction: Direction) {
        guard let unitId = u.id, let colonyId = colony.id, let otherId = colony.owner?.id else { return }
        requests.append(.negotiation(Negotiation(
            ourId: unitId, otherId: colonyId, otherPlayerId: otherId, context: context.javaName, playerSent: true,
            version: 0, items: [], comment: PlayerView.sendMessage(context, view.player, colony),
            direction: direction.javaName)))
    }

    /// Spy on a foreign colony (moveSpy).
    func moveSpy(_ unitId: String, _ direction: Direction) -> Bool {
        if let colony = settlement(unitId, direction) as? Colony, !view.player.owns(colony) {
            _ = command(.spySettlement(unit: unitId, settlement: colony.id))
        }
        return false
    }

    /// Demand tribute of a European colony (moveTribute): how much,
    /// by Java's question, then an agreement of peace for the gold,
    /// sent at once (moveDiplomacy).
    func moveEuropeanTribute(_ unitId: String, _ colony: Colony, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let other = colony.owner, let otherId = other.id else { return false }
        // The other's summary, as the server sends it.
        let summary = (game.getFreeColGameObject(otherId) as? Player).map { NationSummary($0, human) }
        let (text, maximum) = PlayerView.europeanTribute(u, colony, summary)
        guard let maximum else {
            notices.append(text)
            return false
        }
        let q = PlayQuestion(id: "tributeAmount:\(unitId)", text: text, choices: [], suggestion: String(maximum),
                             unitId: unitId)
        guard let answer = ask(q), let amount = Int(answer), amount > 0, amount <= maximum else { return false }
        let player = view.player
        if other === player.refPlayer { return false }
        let dt = DiplomaticTrade.makePeaceTreaty(.tribute, player, other)
        dt.add(GoldTradeItem(game: view.game, source: other, destination: player, gold: amount))
        _ = command(.diplomacy(our: unitId, other: colony.id, agreement: CommandElement(serializing: dt)))
        return false
    }
}

/// A trade route as the player edits it (TradeRouteInputPanel).
public struct TradeRouteInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var isSilent: Bool
    public var stops: [TradeStopInfo]
    /// The units following it.
    public var unitIds: [String]

    public init(id: String, name: String, isSilent: Bool, stops: [TradeStopInfo], unitIds: [String]) {
        self.id = id
        self.name = name
        self.isSilent = isSilent
        self.stops = stops
        self.unitIds = unitIds
    }
}

public struct TradeStopInfo: Sendable, Equatable {
    public var locationId: String
    public var locationName: String
    /// The goods to load there; all else is unloaded.
    public var cargo: [String]

    public init(locationId: String, locationName: String, cargo: [String]) {
        self.locationId = locationId
        self.locationName = locationName
        self.cargo = cargo
    }
}

/// The player's routes, and what they can be made of.
public struct TradeRoutesScreen: Sendable, Equatable {
    public let routes: [TradeRouteInfo]
    /// Europe and the player's colonies, by identifier and name.
    public let locations: [TradeStopInfo]
    /// The storable goods, by identifier, and their names.
    public let goodsIds: [String]
    public let goodsNames: [String]
}

extension PlayerView {
    func tradeRoutesScreen() -> TradeRoutesScreen {
        func stop(_ loc: any Location, _ cargo: [String]) -> TradeStopInfo {
            TradeStopInfo(locationId: loc.id ?? "", locationName: Messages.message(locationLabel(loc, for: player)) ?? "",
                          cargo: cargo)
        }
        let routes = player.tradeRoutes.map { r in
            TradeRouteInfo(id: r.id ?? "", name: r.name ?? "", isSilent: r.isSilent,
                           stops: r.stopList.compactMap { s in s.location.map { stop($0, s.cargo.compactMap(\.id)) } },
                           unitIds: r.assignedUnits.compactMap(\.id))
        }
        var locations: [TradeStopInfo] = []
        if let europe = player.europe { locations.append(stop(europe, [])) }
        locations += player.colonyList.map { stop($0, []) }
        let goods = game.specification?.storableGoodsTypeList ?? []
        return TradeRoutesScreen(routes: routes, locations: locations, goodsIds: goods.compactMap(\.id),
                                 goodsNames: goods.map { Messages.name($0) })
    }
}

extension Unit {
    /// Whether the unit can go on with its trade route (isReadyToTrade).
    var isReadyToTrade: Bool {
        !isDamagedAndUnderForcedRepair && !isAtSea && !isOnCarrier && !isInColony && tradeRoute != nil
            && state != .fortifying && state != .skipped && movesLeft > 0
    }
}

/// Trade routes (the client InGameController's followTradeRoute,
/// loadUnitAtStop and unloadUnitAtStop).  Java's summary of a unit's
/// activity is off by default and not offered here.  The player's copy of
/// the game is read afresh after each command, so stops are held by index.
extension PlayController {

    func newTradeRoute() {
        if command(.newTradeRoute) { updateGUI() }
    }

    func updateTradeRoute(_ info: TradeRouteInfo) {
        let stops = info.stops.map { s in
            CommandElement(tag: TradeRouteStop.tag, attributes: ["location": s.locationId],
                           children: s.cargo.map { CommandElement(tag: "cargo", attributes: ["id": $0]) })
        }
        // A name another route has is refused (verifyUniqueName).
        if view.player.tradeRoutes.contains(where: { $0.id != info.id && $0.name == info.name }) {
            tell(StringTemplate.template("model.tradeRoute.duplicateName").addName("%name%", info.name))
            return
        }
        let route = CommandElement(tag: TradeRoute.tag, attributes: ["id": info.id, "name": info.name,
                                                                     "silent": String(info.isSilent)], children: stops)
        if command(.updateTradeRoute(route: route)) { updateGUI() }
    }

    func deleteTradeRoute(_ routeId: String) {
        if command(.deleteTradeRoute(route: routeId)) { updateGUI() }
    }

    func assignTradeRoute(_ unitId: String, _ routeId: String?) {
        if assignRoute(unitId, routeId) { updateGUI() }
    }

    /// Whether a unit with a trade route may lose it (confirmClearTradeRoute).
    func confirmClearTradeRoute(_ unitId: String) -> Bool {
        guard let u = unit(unitId), let route = u.tradeRoute else { return true }
        let t = StringTemplate.template("clearTradeRoute.text").addStringTemplate("%unit%", u.label(.national))
            .addName("%route%", route.name)
        return confirm("clearTradeRoute:\(unitId)", unitId, t, "yes", "no")
    }

    /// Give a unit a route, or none (askAssignTradeRoute).
    func assignRoute(_ unitId: String, _ routeId: String?) -> Bool {
        guard let u = unit(unitId) else { return false }
        if routeId == u.tradeRoute?.id { return true }
        if routeId != nil && u.tradeRoute != nil && !confirmClearTradeRoute(unitId) { return false }
        return command(.assignTradeRoute(unit: unitId, route: routeId)) && unit(unitId)?.tradeRoute?.id == routeId
    }

    /// The stops from the unit's current one on, as indices.
    private func stopIndices(_ u: Unit) -> [Int] {
        guard let n = u.tradeRoute?.stopCount, n > 0, let stops = u.currentStops, !stops.isEmpty else { return [] }
        return (0..<n).map { (u.currentStop + $0) % n }
    }

    func followTradeRoute(_ unitId: String) -> Bool {
        guard let u = unit(unitId), let route = u.tradeRoute else { return true }
        // Validate the whole route.
        if !route.stopList.allSatisfy({ TradeRoute.isStopValid(u, $0) }) {
            clearOrders(unitId)
            return false
        }
        var stops = stopIndices(u)
        while !stops.isEmpty {
            let index = stops.removeFirst()
            guard let u = unit(unitId), let stop = u.tradeRoute?.stop(index) else { return true }
            if !u.atStop(stop) {
                if u.movesLeft <= 0 || u.state == .skipped { break }
                guard let destination = stop.location, let path = PlayerView.path(u.findPath(destination)) else {
                    _ = changeState(unitId, .skipped)
                    break
                }
                _ = movePath(unitId, path)
                if question != nil { return false }
                guard let u = unit(unitId), let stop = u.tradeRoute?.stop(index) else { return true }
                if !u.atStop(stop) {
                    _ = changeState(unitId, .skipped)
                    break
                }
            }
            unloadUnitAtStop(unitId)
            if question != nil { return false }
            loadUnitAtStop(unitId)
            if question != nil { return false }
            guard let u = unit(unitId), u.movesLeft > 0, let route = u.tradeRoute else { break }
            // The next stop with work to do.
            var more = stopIndices(u)
            if let first = more.first, let s = route.stop(first), u.atStop(s) { more.removeFirst() }
            guard let next = more.first(where: { i in route.stop(i).map { $0.hasWork(u, 0) } ?? false }) else {
                // No work anywhere on the route: wait.
                _ = changeState(unitId, .skipped)
                break
            }
            while let first = stops.first, first != next { stops.removeFirst() }
            if !command(.setCurrentStop(unit: unitId, index: String(next))) {
                _ = changeState(unitId, .skipped)
                break
            }
        }
        return true
    }

    /// Unload what is not to be loaded at this stop (unloadUnitAtStop).
    private func unloadUnitAtStop(_ unitId: String) {
        guard let start = unit(unitId), start.tradeLocation != nil, let wanted = start.stop?.cargo else { return }
        for g in start.compactGoodsList.map({ ($0.type, $0.amount) }) {
            guard let type = g.0, let typeId = type.id, !wanted.contains(where: { $0 === type }), g.1 > 0,
                  let u = unit(unitId), let here = u.tradeLocation,
                  let t = view.game.specification?.getGoodsType(typeId) else { continue }
            let atStop = here.importAmount(t, 0)
            var amount = g.1
            if amount > atStop {
                // Java's option to ask, its default.
                let overflow = StringTemplate.template("traderoute.warehouseCapacity")
                    .addStringTemplate("%unit%", u.label(.national))
                    .addStringTemplate("%colony%", locationLabel(here as? any Location))
                    .addAmount("%amount%", amount - atStop).addNamed("%goods%", t)
                if !confirm("overflow:\(unitId):\(typeId)", unitId, overflow, "yes", "no") {
                    if question != nil { return }
                    if atStop == 0 { continue }
                    amount = atStop
                }
            }
            if amount == 0 { continue }
            if !command(.unloadGoods(type: typeId, amount: String(amount), carrier: unitId))
                || unit(unitId)?.goodsCount(t) == g.1 { break }
        }
    }

    /// Load what is to be loaded at this stop (loadUnitAtStop).
    private func loadUnitAtStop(_ unitId: String) {
        guard let u = unit(unitId), u.tradeLocation != nil, let stop = u.stop,
              let spec = view.game.specification else { return }
        let enhanced = spec.getBoolean(GameOptions.enhancedTradeRoutes)
        var toLoad: [(type: GoodsType, amount: Int)] = stop.compactCargo.compactMap { ag in
            ag.type.map { ($0, ag.amount) }
        }
        for g in u.compactGoodsList {
            guard let i = toLoad.firstIndex(where: { $0.type === g.type }) else { continue }
            if toLoad[i].amount <= g.amount { toLoad.remove(at: i) } else { toLoad[i].amount -= g.amount }
        }
        var plan: [(typeId: String, amount: Int)] = []
        var unloadFirst: [(typeId: String, amount: Int)] = []
        for item in toLoad {
            let type = item.type
            let present = stop.availableGoodsCount(type)
            let exportAmount = stop.exportAmount(type, 0)
            var importAmount = Constants.infinity
            var found = false
            if enhanced {
                var turns = 0
                var start: (any Location)? = u.location
                for trs in (u.currentStops ?? []).dropFirst() {
                    guard let from = start, let to = trs.location else { continue }
                    turns += u.turnsToReach(from, to)
                    let amountIn = trs.importAmount(type, turns), amountOut = trs.exportAmount(type, turns)
                    if !trs.compactCargo.contains(where: { $0.type === type }) || amountIn > amountOut {
                        importAmount = amountIn
                        found = true
                        break
                    }
                    start = to
                }
            }
            var amount = item.amount
            if (enhanced && !found) || present <= 0 || exportAmount <= 0 || importAmount <= 0 {
                amount = 0
            } else if exportAmount <= importAmount && exportAmount < amount {
                amount = exportAmount
            } else if importAmount <= exportAmount && importAmount < amount {
                let already = u.goodsCount(type)
                if already >= importAmount {
                    if already > importAmount, let id = type.id { unloadFirst.append((id, already - importAmount)) }
                    amount = 0
                } else {
                    amount = importAmount - already
                }
            }
            if amount > 0, let id = type.id { plan.append((id, amount)) }
        }
        for (id, amount) in unloadFirst {
            _ = command(.unloadGoods(type: id, amount: String(amount), carrier: unitId))
        }
        if enhanced { plan = plan.stableSorted { $0.amount > $1.amount } }
        let locationId = stop.location?.id
        for (id, amount) in plan {
            guard let u = unit(unitId), let type = view.game.specification?.getGoodsType(id),
                  u.loadableAmount(type) >= amount else { return }
            let old = u.goodsCount(type)
            load(id, amount, onto: unitId, from: locationId)
            if unit(unitId)?.goodsCount(type) == old { return }
        }
    }
}

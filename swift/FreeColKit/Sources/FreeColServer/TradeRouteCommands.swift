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

/// Trade route commands, checked as the messages' serverHandlers check
/// them, then carried out as InGameController does.
extension InGameController {

    func performTradeRoute(_ command: PlayerCommand, by player: Player) throws -> ChangeSet? {
        switch command {
        case .newTradeRoute:
            let base = Messages.message("nameCache.base.tradeRoute")
            var name = base, i = 1
            while player.tradeRoute(byName: name, excluding: nil) != nil {
                name = base + String(i)
                i += 1
            }
            player.addTradeRoute(TradeRoute(game: game, name: name, owner: player))
            return ChangeSet().add(.only(player), player)

        case let .updateTradeRoute(element):
            guard let element, let id = element.attributes["id"], let name = element.attributes["name"] else {
                throw CommandRefused("Bogus route")
            }
            guard let route = game.getFreeColGameObject(id) as? TradeRoute, player.owns(route) else {
                throw CommandRefused("Not an existing trade route: \(id)")
            }
            // Changed, and put back if it will not do.
            let (oldName, oldSilent, oldStops) = (route.name, route.isSilent, route.stopList)
            route.name = name
            route.isSilent = element.attributes["silent"] == "true"
            route.clearStops()
            for e in element.children where e.tag == TradeRouteStop.tag {
                let stop = TradeRouteStop(game: game, location: game.getFreeColGameObject(e.attributes["location"])
                    as? any Location)
                for c in e.children where c.tag == "cargo" {
                    if let gt = game.specification?.getGoodsType(c.attributes["id"]) { stop.addCargo(gt) }
                }
                route.addStop(stop)
            }
            if let fail = route.verify {
                route.name = oldName
                route.isSilent = oldSilent
                route.clearStops()
                for stop in oldStops { route.addStop(stop) }
                throw CommandRefused(Messages.message(fail) ?? "Invalid route")
            }
            return ChangeSet().add(.only(player), route)

        case let .assignTradeRoute(unitId, routeId):
            let unit = try ours(player, unitId, Unit.self)
            let route = try routeId.map { try ours(player, $0, TradeRoute.self) }
            // A unit at sea whose route is taken away goes on to its stop.
            if route == nil, unit.isAtSea, let stop = unit.stop {
                unit.destination = stop.location
            } else {
                unit.destination = nil
            }
            unit.tradeRoute = route
            if let route {
                let found = route.stopList.firstIndex { Map.isSameLocation(unit.location, $0.location) }
                unit.currentStop = found ?? 0
            }
            return ChangeSet().add(.only(player), unit)

        case let .deleteTradeRoute(routeId):
            let route = try ours(player, routeId, TradeRoute.self)
            let dropped = player.removeTradeRoute(route)
            let cs = ChangeSet().add(.only(player), player)
            for u in dropped { _ = cs.add(.only(player), u) }
            return cs

        case let .setCurrentStop(unitId, indexString):
            let unit = try ours(player, unitId, Unit.self)
            guard let route = unit.tradeRoute else {
                throw CommandRefused("Unit has no trade route: \(unitId ?? "null")")
            }
            guard let index = indexString.flatMap({ Int($0) }), index >= 0, index < route.stopCount else {
                throw CommandRefused("Invalid stop index: \(indexString ?? "null")")
            }
            unit.currentStop = index
            return ChangeSet().add(.only(player), unit)

        default:
            preconditionFailure("Not a trade route command: \(command)")
        }
    }
}

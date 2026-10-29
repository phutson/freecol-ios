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

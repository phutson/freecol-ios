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
import FreeColIO
import FreeColUtil
import FreeColXML

/// The server's game (server/model/ServerGame), which issues the
/// identifiers of the objects made while playing.
///
/// Not yet ported: the Spanish succession itself (only whether it is
/// due), and the rest of ServerGame.
public final class ServerGame: Game {

    /// The names handed out so far (Java's static NameCache).
    public let nameCache = NameCache()

    /// The sessions waiting for answers (Java's static Session map).
    public let sessions = Sessions()

    /// Issue the next identifier number, counting from the saved game's.
    public override func getNextId() -> Int {
        defer { nextId += 1 }
        return nextId
    }

    /// Finish the sessions left unanswered, and move on to the next
    /// turn, telling everyone (csNextTurn).
    public func csNextTurn(_ cs: ChangeSet) throws {
        try sessions.completeAll(cs)
        turn = turn.next()
        cs.add(.all(), message: NewTurnMessage(turn))
    }

    /// Each live player's new turn, then the Spanish succession if it
    /// is due (csNewTurn).
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        for player in livePlayers { try player.csNewTurn(random, cs) }
        if let succession = specification?.getEvent("model.event.spanishSuccession"), !spanishSuccession {
            try csSpanishSuccession(succession, cs)
        }
    }

    /// Who has won, if anyone: an independent player, the last
    /// European, or the last human, as the victory options say
    /// (checkForWinner).
    public func checkForWinner() -> Player? {
        guard let spec = specification else { return nil }
        if spec.getBoolean(GameOptions.victoryDefeatRef) == true,
           let winner = liveEuropeanPlayers.first(where: { $0.playerType == .independent }) {
            return winner
        }
        if spec.getBoolean(GameOptions.victoryDefeatEuropeans) == true {
            let winners = liveEuropeanPlayers.filter { !$0.isREF }
            if winners.count == 1 { return winners[0] }
        }
        if spec.getBoolean(GameOptions.victoryDefeatHumans) == true {
            let winners = liveEuropeanPlayers.filter { !$0.isAI }
            if winners.count == 1 { return winners[0] }
        }
        return nil
    }

    /// The player after the current one, skipping the dead and the
    /// unknown enemy (getNextPlayer).
    public var nextPlayer: Player? {
        if players.isEmpty { return nil }
        let start = currentPlayer.flatMap { c in players.firstIndex { $0 === c } } ?? -1
        var index = start
        repeat {
            index += 1
            if index >= players.count { index = 0 }
            let p = players[index]
            if !p.isUnknownEnemy && !p.isDead { return p }
        } while index != start && !(start == -1 && index == players.count - 1)
        return nil
    }

    /// Whether the next player starts a new turn (isNextPlayerInNewTurn).
    public var isNextPlayerInNewTurn: Bool {
        let next = nextPlayer
        let ci = currentPlayer.flatMap { c in players.firstIndex { $0 === c } } ?? -1
        let ni = next.flatMap { n in players.firstIndex { $0 === n } } ?? -1
        return ci > ni || currentPlayer === next
    }

    /// Whether the Spanish succession is due, and the strongest and the
    /// weakest AI players (spanishSuccessionReady).
    private func spanishSuccessionReady(_ event: Event) -> (ready: Bool, strong: Player?, weak: Player?) {
        guard let yearLimit = event.limit("model.limit.spanishSuccession.year"),
              yearLimit.evaluate(self) else { return (false, nil, nil) }
        let weakLimit = event.limit("model.limit.spanishSuccession.weakestPlayer")
        let strongLimit = event.limit("model.limit.spanishSuccession.strongestPlayer")
        var weakAI: Player?, strongAI: Player?
        var weakScore = Int(Int32.max), strongScore = Int(Int32.min)
        var ready = false
        for player in liveEuropeanPlayers where !player.isREF {
            // Anyone can trigger it, but assets pass between AIs only.
            ready = ready || (strongLimit?.evaluate(player) ?? true)
            if !player.isAI { continue }
            let score = player.spanishSuccessionScore
            if strongAI == nil || strongScore < score {
                strongScore = score
                strongAI = player
            }
            if (weakLimit?.evaluate(player) ?? true) && (weakAI == nil || weakScore > score) {
                weakScore = score
                weakAI = player
            }
        }
        return (ready, strongAI, weakAI)
    }

    /// The Spanish succession: the weakest AI cedes everything to the
    /// strongest (csSpanishSuccession).
    ///
    /// - Throws: NotYetPorted when it happens, as changing the owner of
    ///   colonies and units comes with player actions.
    private func csSpanishSuccession(_ event: Event, _ cs: ChangeSet) throws {
        let (ready, strong, weak) = spanishSuccessionReady(event)
        guard ready, let strong, let weak, strong !== weak else { return }
        throw NotYetPorted("the Spanish succession (csSpanishSuccession)")
    }
}

/// A new turn has begun (NewTurnMessage).
public final class NewTurnMessage: ServerMessage {
    public let turn: Turn

    public init(_ turn: Turn) {
        self.turn = turn
    }

    public var tag: String { "newTurn" }
    public var priority: MessagePriority { .normal }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("turn", String(turn.number))] }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

extension FreeColSavegameFile {
    /// Read a game to play on: as readGame, into a server game.
    public func readServerGame(specification: Specification? = nil) throws -> SavedGame {
        try readGame(specification: specification) { ServerGame(specification: $0) }
    }
}

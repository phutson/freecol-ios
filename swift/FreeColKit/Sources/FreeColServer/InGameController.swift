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
import FreeColUtil

/// The server's control of a game in progress
/// (server/control/InGameController): so far the turn cycle.
///
/// Java sends each change set to the connected players as it goes.
/// Here the players a game has connected (Java's players with a
/// connection: the humans and, in a game on one machine, the AIs too)
/// are given by `isConnected`, and what each is sent goes to `deliver`.
///
/// The players' commands are in InGameCommands.swift.
///
/// Not yet ported: the Royal Expeditionary Force arriving (it needs the
/// REF's AI to place it), independence being granted, high scores, the
/// debug runs, and the commands not in PlayerCommand.
public final class InGameController {

    public let game: ServerGame
    public var random: JavaRandom
    /// A game with one human player, where an AI that wins does not end
    /// the game.
    public var singlePlayer: Bool
    /// Whether a player is connected, and so sent changes.
    public var isConnected: (Player) -> Bool = { _ in true }
    /// Where the changes sent to a player go.
    public var deliver: (Player, PlayerUpdate) -> Void = { _, _ in }

    private var debugMonarch: (player: Player, action: Monarch.MonarchAction)?

    public init(game: ServerGame, random: JavaRandom, singlePlayer: Bool = true) {
        self.game = game
        self.random = random
        self.singlePlayer = singlePlayer
    }

    /// Make a player's monarch take an action when the player's turn
    /// next starts (setMonarchAction, a debug aid in Java).
    public func setMonarchAction(_ player: Player, _ action: Monarch.MonarchAction) {
        debugMonarch = (player, action)
    }

    // MARK: Sending

    /// The connected players, but some (getConnectedPlayers).
    func connectedPlayers(excluding exclude: Player? = nil) -> [Player] {
        game.players.filter { isConnected($0) && $0 !== exclude }
    }

    private func sendToList(_ players: [Player], _ cs: ChangeSet) throws {
        for p in players {
            if let update = try cs.build(p) { deliver(p, update) }
        }
    }

    private func sendToAll(_ cs: ChangeSet) throws {
        try sendToList(connectedPlayers(), cs)
    }

    /// Send changes to the connected players but one (sendToOthers).
    func sendToOthers(_ player: Player, _ cs: ChangeSet) throws {
        try sendToList(connectedPlayers(excluding: player), cs)
    }

    /// Change a stance, telling everyone (changeStance), as the AI does
    /// directly rather than by a command.
    public func changeStance(_ player: Player, _ stance: Player.Stance, _ other: Player,
                             _ symmetric: Bool) throws {
        let cs = ChangeSet()
        if try player.csChangeStance(stance, other, symmetric, cs) { try sendToAll(cs) }
    }

    // MARK: The turn cycle

    /// End the current player's turn, and go on to the next player that
    /// is alive, through new turns, deaths and the end of the game, and
    /// start its turn (endTurn).  The others are sent the changes as it
    /// goes.
    ///
    /// - Returns: The changes for the player whose turn ended.
    /// - Throws: NotYetPorted for what is not ported yet.
    public func endTurn(_ serverPlayer: Player) throws -> ChangeSet {
        var winner = game.checkForWinner()
        guard var current = game.currentPlayer, current === serverPlayer else {
            preconditionFailure("It is not \(serverPlayer.name ?? "null")'s turn")
        }

        let cs = ChangeSet()
        while true {
            try current.csEndTurn(cs)
            current.clearModelMessages()

            if game.isNextPlayerInNewTurn {
                try game.csNextTurn(cs)
                try game.csNewTurn(random, cs)
                try sendToAll(cs)
                cs.clear()
            }

            guard let next = game.nextPlayer else { preconditionFailure("Can not get next player") }
            current = next

            // Remove the dead, and go on.
            switch current.checkForDeath() {
            case .isDefeated:
                for p in current.rebels { try csGiveIndependence(current, p, cs) }
                try current.csWithdraw(cs)
            case .isDead:
                try current.csWithdraw(cs)
            case .isAutorecruit:
                try current.csEmigrate(0, .survival, random, cs)
            case .isAlive:
                break
            }
            if !cs.isEmpty {
                try sendToAll(cs)
                cs.clear()
            }
            if current.isDead { continue }

            // With no humans left the best score wins.
            let connected = connectedPlayers()
            if connected.allSatisfy(\.isAI) {
                winner = connected.enumerated().sorted {
                    $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
                }.first?.element
                game.currentPlayer = nil
                if let winner { cs.add(.all(), message: GameEndedMessage(winner, false)) }
                try sendToAll(cs)
                cs.clear()
            }

            // Has the current player won?  Not an AI in a game with one
            // human, which would stop revenge mode.
            if let winner, winner === current, !(singlePlayer && winner.isAI) {
                if !winner.isAI { throw NotYetPorted("high scores (HighScore.newHighScore)") }
                cs.add(.all(), message: GameEndedMessage(winner, false))
                try sendToAll(cs)
                cs.clear()
            }

            // What waits until just before the player moves.
            game.currentPlayer = current
            if current.isREF && current.entryTile == nil {
                throw NotYetPorted("the REF arriving (csLaunchREF, which needs the REF's AI)")
            }
            try current.csStartTurn(random, cs)

            cs.add(.all(), message: SetCurrentPlayerMessage(current))
            if current.playerType == .colonial {
                let monarch = current.monarch
                var action: Monarch.MonarchAction?
                if let debug = debugMonarch, debug.player === current {
                    action = debug.action
                    debugMonarch = nil
                } else if let monarch {
                    action = RandomChoice.weightedRandom("Choose monarch action", monarch.actionChoices(), random)
                }
                if let action, let monarch, monarch.actionIsValid(action) {
                    try csMonarchAction(current, action, cs)
                }
            }

            // The current player last, so it does not start moving
            // before the others are told.
            var players = connectedPlayers(excluding: current)
            players.append(current)
            if let i = players.firstIndex(where: { $0 === serverPlayer }) { players.remove(at: i) }
            try sendToList(players, cs)
            return cs
        }
    }

    // MARK: The monarch

    /// A European nation that no one plays, at random, as a message key
    /// (Nation.getRandomNonPlayerNationNameKey).
    func randomNonPlayerNationNameKey() -> String {
        let nations = ["dutch", "english", "french", "spanish", "danish", "portuguese", "swedish", "russian",
                       "austrian", "german", "prussian", "turkish"]
        let start = Int(RandomUtils.randomInt("Random nation", random, Int32(nations.count)))
        for index in 0..<nations.count {
            let nationId = "model.nation." + nations[(start + index) % nations.count]
            if game.player(byNationId: nationId) == nil { return Messages.nameKey(nationId) }
        }
        return ""
    }

    /// The monarch acts (csMonarchAction): changing the tax, adding to
    /// the REF, making war or peace, sending support, or offering
    /// mercenaries.  Tax raises and the monarch's mercenaries wait for
    /// an answer, in a session.
    public func csMonarchAction(_ player: Player, _ action: Monarch.MonarchAction, _ cs: ChangeSet) throws {
        guard let monarch = player.monarch, monarch.actionIsValid(action), let spec = game.specification
        else { return }
        let messageId = action.textKey
        let monarchKey = player.nationId ?? ""

        switch action {
        case .noAction:
            break
        case .raiseTaxWar, .raiseTaxAct:
            let taxRaise = monarch.raiseTax(random)
            guard let goods = player.mostValuableGoods, let goodsType = goods.type else { break }
            var template = StringTemplate.template(messageId)
                .addStringTemplate("%goods%", StringTemplate.key(goodsType))
                .addAmount("%amount%", taxRaise)
            if action == .raiseTaxWar {
                template = template.add("%nation%", randomNonPlayerNationNameKey())
            } else {
                template = template.addAmount("%number%", Int(RandomUtils.randomInt("Tax act goods", random, 6)))
                    .addName("%newWorld%", player.newLandName)
            }
            cs.add(.only(player), message: MonarchActionMessage(action, template, monarchKey).setTax(taxRaise))
            MonarchSession.register(player, action, tax: taxRaise, goods: goods, in: game.sessions)
        case .lowerTaxWar, .lowerTaxOther:
            let oldTax = player.tax
            let taxLower = monarch.lowerTax(random)
            player.csSetTax(taxLower, cs)
            var template = StringTemplate.template(messageId)
                .addAmount("%difference%", oldTax - taxLower)
                .addAmount("%newTax%", taxLower)
            if action == .lowerTaxWar {
                template = template.add("%nation%", randomNonPlayerNationNameKey())
            } else {
                template = template.addAmount("%number%", Int(RandomUtils.randomInt("Lower tax reason", random, 5)))
            }
            cs.add(.only(player), message: MonarchActionMessage(action, template, monarchKey))
        case .waiveTax:
            cs.add(.only(player), message: MonarchActionMessage(action, StringTemplate.template(messageId),
                                                                monarchKey))
        case .addToREF:
            guard let additions = monarch.addToREF(random), let type = additions.type(spec) else { break }
            let template = StringTemplate.template(messageId)
                .addAmount("%number%", additions.number)
                .addNamed("%unit%", type)
            cs.add(.only(player), monarch)
            cs.add(.only(player), message: MonarchActionMessage(action, template, monarchKey))
        case .declarePeace:
            let friends = monarch.collectPotentialFriends()
            guard let friend = RandomUtils.randomMember("Choose friend", friends, random) else { break }
            try player.csChangeStance(.peace, friend, true, cs)
            cs.add(.only(player), message: MonarchActionMessage(action, StringTemplate.template(messageId)
                .addStringTemplate("%nation%", friend.nationLabel), monarchKey))
        case .declareWar:
            let enemies = monarch.collectPotentialEnemies()
            guard let enemy = RandomUtils.randomMember("Choose enemy", enemies, random) else { break }
            let warSupport = monarch.warSupport(enemy, random)
            var warGold = 0
            if !warSupport.isEmpty {
                player.createUnits(warSupport, player.europe, random)
                warGold = spec.getInteger(GameOptions.warSupportGold) ?? 0
                warGold += (warGold / 10) * (Int(RandomUtils.randomInt("War support gold", random, 5)) - 2)
                _ = player.modifyGold(warGold)
                cs.addPartial(.only(player), player, ("gold", String(player.gold)), ("score", String(player.score)))
            }
            try player.csChangeStance(.war, enemy, true, cs)
            cs.add(.only(player), message: MonarchActionMessage(action, StringTemplate.template(
                warSupport.isEmpty ? messageId : "model.monarch.action.declareWarSupported.text")
                .addStringTemplate("%nation%", enemy.nationLabel)
                .addStringTemplate("%force%", AbstractUnit.listLabel(", ", warSupport))
                .addAmount("%gold%", warGold), monarchKey))
        case .supportLand, .supportSea:
            let support = monarch.support(random, naval: action == .supportSea)
            if support.isEmpty { break }
            player.createUnits(support, player.europe, random)
            cs.add(.only(player), player.europe)
            cs.add(.only(player), message: MonarchActionMessage(action, StringTemplate.template(messageId)
                .addStringTemplate("%addition%", AbstractUnit.listLabel(", ", support)), monarchKey))
        case .monarchMercenaries:
            var mercenaries: [AbstractUnit] = []
            let price = monarch.loadMercenaries(random, &mercenaries)
            if price <= 0 { break }
            cs.add(.only(player), message: MonarchActionMessage(action, StringTemplate.template(messageId)
                .addAmount("%gold%", price)
                .addStringTemplate("%mercenaries%", AbstractUnit.listLabel(", ", mercenaries)), monarchKey))
            MonarchSession.register(player, action, mercenaries: mercenaries, price: price, in: game.sessions)
        case .hessianMercenaries:
            var hessians: [AbstractUnit] = []
            let price = monarch.loadMercenaries(random, &hessians)
            if price <= 0 { break }
            player.csMercenaries(price, hessians, action, random, cs)
        case .displeasure, .forceTax:
            break
        }
    }
}

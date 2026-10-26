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
import FreeColIO
import FreeColServer
import FreeColUtil
import FreeColXML

/// The game engine as the user interface sees it: an actor that owns
/// one single-player game and runs it off the main thread.
///
/// The interface sends the human player's commands and asks for
/// snapshots, plain values of what that player can see, which it may
/// keep and read anywhere.  Nothing of the live game leaves the actor.
/// The other players are computer players; until the AI is ported they
/// end their turns at once.
///
/// The boundary is the one a network would need: commands in, and the
/// changes one player may see out.
public actor GameEngine {

    /// A setting for the map generator or game options.
    public enum OptionValue: Sendable, Equatable {
        case integer(Int)
        case boolean(Bool)
    }

    public enum EngineError: Error, CustomStringConvertible {
        case noHumanPlayer
        case notPlayersTurn
        case failed(String)

        public var description: String {
            switch self {
            case .noHumanPlayer: "The game has no human player"
            case .notPlayersTurn: "It is not the player's turn"
            case .failed(let reason): reason
            }
        }
    }

    private let game: ServerGame
    private let random: JavaRandom
    private let controller: InGameController
    private let human: Player
    private let messages: MessageBundle
    /// What the human player was shown since it was last asked.
    private let shown = Shown()

    /// Collects what the human player is sent, as events.
    private final class Shown {
        var events: [EngineEvent] = []
    }

    private init(game: ServerGame, random: JavaRandom, messages: MessageBundle) throws {
        guard let human = game.livePlayers.first(where: { !$0.isAI }) else { throw EngineError.noHumanPlayer }
        self.game = game
        self.random = random
        self.human = human
        self.messages = messages
        let controller = InGameController(game: game, random: random)
        let shown = self.shown
        controller.deliver = { player, update in
            if player === human { shown.events += GameEngine.events(update, for: human) }
        }
        self.controller = controller
    }

    /// Start a new game, as the server does for one human player.
    ///
    /// - Parameters:
    ///   - data: The game's data directory.
    ///   - rules: The rule set ("freecol" or "classic").
    ///   - difficulty: The difficulty level.
    ///   - options: Map generator and game option settings, by id.
    ///   - seed: The random seed; a random one if nil.
    ///   - playerName: The human player's name.
    ///   - messages: The translated strings to use.
    public init(newGame data: FreeColDataDirectory, rules: String = "freecol",
                difficulty: String = "model.difficulty.medium", options: [String: OptionValue] = [:],
                seed: Int64? = nil, playerName: String, messages: MessageBundle) throws {
        let random = JavaRandom(seed: seed ?? Int64.random(in: Int64.min...Int64.max))
        let game = try Messages.$scopedBundle.withValue(messages) { () throws -> ServerGame in
            let spec = try data.loadSpecification(rules, difficulty: difficulty)
            for (id, value) in options {
                switch value {
                case .integer(let i): spec.setInteger(id, i)
                case .boolean(let b): spec.setBoolean(id, b)
                }
            }
            return ServerGame.startNewGame(spec, random, playerName: playerName)
        }
        try self.init(game: game, random: random, messages: messages)
    }

    /// Load a saved game, Java's or one this engine saved.
    public init(loading url: URL, messages: MessageBundle) throws {
        let saved = try Messages.$scopedBundle.withValue(messages) {
            try FreeColSavegameFile(url: url).readServerGame()
        }
        guard let game = saved.game as? ServerGame else { throw EngineError.failed("Not a server game") }
        // Java's server forgets whose turn it was, and the first player
        // to log in takes it (LoginMessage).
        if game.currentPlayer == nil { game.currentPlayer = game.livePlayers.first { !$0.isAI } }
        try self.init(game: game, random: saved.serverRandom ?? JavaRandom(seed: Int64.random(in: 0...Int64.max)),
                      messages: messages)
    }

    /// The state of the game's random number generator, as a save
    /// records it, so two games can be seen to be playing on alike.
    public var randomState: String {
        random.serializedState
    }

    /// The human player's identifier.
    public var playerId: String {
        human.id ?? ""
    }

    /// What the human player can see now.
    public func snapshot() -> GameSnapshot {
        Messages.$scopedBundle.withValue(messages) { SnapshotBuilder(game: game, player: human).build() }
    }

    /// Carry out one of the human player's commands.  A refused command
    /// changes nothing and says why.
    public func perform(_ command: PlayerCommand) -> CommandResult {
        Messages.$scopedBundle.withValue(messages) {
            shown.events = []
            var refusal: String?
            do {
                if let cs = try controller.perform(command, by: human), let update = try cs.build(human) {
                    shown.events += GameEngine.events(update, for: human)
                }
            } catch let e as CommandRefused {
                refusal = e.message
            } catch {
                refusal = "\(error)"
            }
            return result(refusal)
        }
    }

    /// End the human player's turn: the others play theirs (ending them
    /// at once, until the AI is ported), through the new turn, until it
    /// is the human player's turn again or the game ends.
    public func endTurn() throws -> CommandResult {
        try Messages.$scopedBundle.withValue(messages) {
            guard game.currentPlayer === human else { throw EngineError.notPlayersTurn }
            shown.events = []
            do {
                if let update = try controller.endTurn(human).build(human) {
                    shown.events += GameEngine.events(update, for: human)
                }
                // The computer players.  Each new turn passes every
                // player once, so this is plenty.
                var steps = 0
                while let current = game.currentPlayer, current !== human, !human.isDead,
                      steps < 4 * game.players.count + 4 {
                    _ = try controller.endTurn(current)
                    steps += 1
                }
            } catch let e as NotYetPorted {
                throw EngineError.failed(e.description)
            }
            return result(nil)
        }
    }

    /// Save the game, as Java's server does, so Java can load it too
    /// (without the AI's objects, which are not ported).
    public func save(to url: URL) throws {
        let xw = FreeColXMLWriter(scope: .toSave())
        xw.writeStartElement("savedGame")
        xw.writeAttribute("owner", "FreeCol")
        xw.writeAttribute("publicServer", false)
        xw.writeAttribute("singleplayer", true)
        xw.writeAttribute("version", FreeColSavegameFile.savegameVersion)
        xw.writeAttribute("randomState", random.serializedState)
        xw.writeAttribute("debug", "")
        game.toXML(xw)
        xw.writeEndElement()
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + xw.xml
        let properties = "map.width=\(game.map?.width ?? 0)\nmap.height=\(game.map?.height ?? 0)\n"
        let data = ZipArchive.archive([
            (FreeColSavegameFile.propertiesFile, Data(properties.utf8)),
            (FreeColSavegameFile.savegameFile, Data(xml.utf8)),
        ])
        try data.write(to: url, options: .atomic)
    }

    private func result(_ refusal: String?) -> CommandResult {
        let events = shown.events
        shown.events = []
        return CommandResult(refusal: refusal, events: events,
                             snapshot: SnapshotBuilder(game: game, player: human).build())
    }

    /// The events in what a player was sent: moves and attacks to show,
    /// and messages.
    private static func events(_ update: PlayerUpdate, for player: Player) -> [EngineEvent] {
        var ret: [EngineEvent] = []
        for change in update.messages {
            switch change {
            case let .animateMove(unit, oldTile, newTile, _):
                ret.append(.unitMoved(unitId: unit.id ?? "", from: MapPosition(x: oldTile.x, y: oldTile.y),
                                      to: MapPosition(x: newTile.x, y: newTile.y)))
            case let .animateAttack(attacker, defender, success, _, _):
                ret.append(.attack(attackerId: attacker.id ?? "", defenderId: defender.id ?? "",
                                   attackerWon: success))
            case let .feature(parent, add, children) where add && parent === player:
                for case let m as ModelMessage in children { ret.append(.message(SnapshotBuilder.message(m))) }
            default:
                break
            }
        }
        return ret
    }
}

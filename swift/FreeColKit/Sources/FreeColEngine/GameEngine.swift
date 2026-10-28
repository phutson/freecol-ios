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
import FreeColAI
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
/// The other players are computer players, played by the AI.
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
    private let ai: AIMain
    private let human: Player
    private let messages: MessageBundle
    /// What the human player was shown since it was last asked.
    private let shown = Shown()
    /// The human player's client, playing on the map.
    private let play: PlayController

    /// Collects what the human player is sent, as events.
    private final class Shown {
        var events: [EngineEvent] = []
    }

    /// - Parameter savedAI: The AI's objects, for a saved game: the AI
    ///   is read from them, or made afresh if there are none.
    private init(game: ServerGame, random: JavaRandom, messages: MessageBundle,
                 savedAI: FreeColXMLReader?? = nil) throws {
        guard let human = game.livePlayers.first(where: { !$0.isAI }) else { throw EngineError.noHumanPlayer }
        self.game = game
        self.random = random
        self.human = human
        self.messages = messages
        let controller = InGameController(game: game, random: random)
        let ai = Messages.$scopedBundle.withValue(messages) {
            savedAI.map { AIMain.loading($0, game: game, controller: controller) }
                ?? AIMain(game: game, controller: controller)
        }
        let shown = self.shown
        controller.deliver = { player, update in
            if player === human {
                shown.events += GameEngine.events(update, for: human)
            } else if player.isAI {
                ai.handle(update, for: player)
            }
        }
        self.controller = controller
        self.ai = ai
        play = PlayController(game: game, human: human) { command in
            do {
                if let cs = try controller.perform(command, by: human), let update = try cs.build(human) {
                    shown.events += GameEngine.events(update, for: human)
                }
                return nil
            } catch let e as CommandRefused {
                return e.message
            } catch {
                return "\(error)"
            }
        }
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
        game.finishLoading()
        // Java's server forgets whose turn it was, and the first player
        // to log in takes it (LoginMessage).
        if game.currentPlayer == nil { game.currentPlayer = game.livePlayers.first { !$0.isAI } }
        try self.init(game: game, random: saved.serverRandom ?? JavaRandom(seed: Int64.random(in: 0...Int64.max)),
                      messages: messages, savedAI: .some(saved.aiMain))
    }

    /// The state of the game's random number generator, as a save
    /// records it, so two games can be seen to be playing on alike.
    public var randomState: String {
        random.serializedState
    }

    /// What the AI met that Java's would not have (commands not yet
    /// ported, and the like), which Java logs and plays on through.
    public var aiProblems: [String] {
        ai.errors
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
            play.invalidate()
            return result(refusal)
        }
    }

    /// End the human player's turn: the others play theirs, through the
    /// new turn, until it is the human player's turn again or the game
    /// ends.
    public func endTurn() throws -> CommandResult {
        try Messages.$scopedBundle.withValue(messages) {
            guard game.currentPlayer === human else { throw EngineError.notPlayersTurn }
            shown.events = []
            do {
                if let update = try controller.endTurn(human).build(human) {
                    shown.events += GameEngine.events(update, for: human)
                }
                // The computer players play their turns as they are
                // given them, ending each.  Any whose AI did not is
                // ended here.  Each new turn passes every player once,
                // so this is plenty.
                var steps = 0
                while let current = game.currentPlayer, current !== human, !human.isDead,
                      steps < 4 * game.players.count + 4 {
                    _ = try controller.endTurn(current)
                    steps += 1
                }
            } catch let e as NotYetPorted {
                play.invalidate()
                throw EngineError.failed(e.description)
            }
            play.invalidate()
            return result(nil)
        }
    }

    // MARK: Playing on the map

    /// Something the player does on the map, as Java's client does it.
    public enum PlayAction: Sendable, Equatable {
        /// The player's turn begins: choose the first unit to move.
        case startTurn
        /// Make a unit (or none) the one being moved.
        case select(unitId: String?)
        /// Move on to the next unit, leaving this one for later.
        case wait
        /// Move one tile (N, NE...).
        case move(unitId: String, direction: String)
        /// Go along a goto path to its end.
        case goTo(unitId: String, destination: PathPlace)
        /// Sentry or fortify (Java's unit state names).
        case changeState(unitId: String, state: String)
        /// Done with this unit this turn.
        case skip(unitId: String)
        /// Improve the tile (a tile improvement type).
        case improve(unitId: String, improvementTypeId: String)
        /// Found a colony, or join the one here.
        case buildColony(unitId: String)
        case disband(unitId: String)
        case clearOrders(unitId: String)
        case executeGotoOrders
        /// Put a colonist to work in a building or on a tile of its
        /// colony.
        case work(unitId: String, workLocationId: String)
        /// Take a colonist out of its colony onto the colony's tile.
        case putOutsideColony(unitId: String)
        /// Change what a colonist works at (a goods type).
        case changeWorkType(unitId: String, goodsTypeId: String)
        /// Set what a colony builds, first to last.
        case setBuildQueue(colonyId: String, queue: [String])
        /// End the turn: the other players play theirs, and the new
        /// turn begins.
        case endTurn
    }

    /// Do something on the map, with the answers to the questions asked
    /// so far (by question id).
    public func play(_ action: PlayAction, answers: [String: String] = [:]) throws -> CommandResult {
        try Messages.$scopedBundle.withValue(messages) {
            shown.events = []
            var ended = false
            play.run(answers) {
                switch action {
                case .startTurn: play.startTurn()
                case .select(let id): play.select(id)
                case .wait: play.nextUnit(wait: true)
                case let .move(id, name):
                    if let d = Direction.allDirections.first(where: { $0.javaName == name }) { play.moveUnit(id, d) }
                case let .goTo(id, destination): play.goTo(id, destination)
                case let .changeState(id, name):
                    if let state = Unit.UnitState.allCases.first(where: { $0.javaName == name }) {
                        play.changeState(id, state)
                    }
                case .skip(let id): play.skip(id)
                case let .improve(id, type): play.improve(id, type)
                case .buildColony(let id): play.buildColony(id)
                case .disband(let id): play.disband(id)
                case .clearOrders(let id): play.clearOrders(id)
                case .executeGotoOrders: play.executeGotoOrders()
                case let .work(id, wl): play.work(id, at: wl)
                case .putOutsideColony(let id): play.putOutsideColony(id)
                case let .changeWorkType(id, goods):
                    let colony = play.unit(id)?.colony?.id
                    play.changeWorkType(id, goods)
                    play.updateProduction(colony)
                case let .setBuildQueue(colony, queue): play.setBuildQueue(colony, queue)
                case .endTurn: ended = play.endTurn(showDialog: true)
                }
            }
            if ended {
                // The server is told, the others play, and the player's
                // new turn begins.
                let events = shown.events
                _ = try endTurn()
                shown.events = events + shown.events
                if game.currentPlayer === human { play.startTurn() }
            }
            var r = result(nil)
            r.question = play.question
            r.notices = play.notices
            r.activeUnitId = play.activeUnitId
            r.colonyToShow = play.colonyToShow
            return r
        }
    }

    /// The unit the player is moving, if any.
    public var activeUnitId: String? {
        play.activeUnitId
    }

    /// What a move in each direction would do (Java's move type names,
    /// north first and clockwise), for a unit of the player's.
    public func moveTypes(_ unitId: String) -> [String]? {
        Messages.$scopedBundle.withValue(messages) {
            play.view.unit(unitId).map { play.view.moveTypes($0).map(\.javaName) }
        }
    }

    /// The path the goto cursor shows from a unit to a tile, if it can
    /// go there.
    public func gotoPath(_ unitId: String, to position: MapPosition) -> UnitPath? {
        Messages.$scopedBundle.withValue(messages) {
            guard let u = play.view.unit(unitId), let t = play.view.tile(position) else { return nil }
            return play.view.gotoPath(u, to: t)
        }
    }

    /// The path a unit would take to Europe.
    public func europePath(_ unitId: String) -> UnitPath? {
        Messages.$scopedBundle.withValue(messages) {
            play.view.unit(unitId).flatMap { play.view.europePath($0) }
        }
    }

    /// The path to a unit's destination, if it has one.
    public func destinationPath(_ unitId: String) -> UnitPath? {
        Messages.$scopedBundle.withValue(messages) {
            play.view.unit(unitId).flatMap { play.view.destinationPath($0) }
        }
    }

    /// The unit actions open to a unit of the player's, on the player's
    /// turn.
    public func unitActions(_ unitId: String) -> UnitActions? {
        Messages.$scopedBundle.withValue(messages) {
            guard game.currentPlayer === human else { return nil }
            return play.view.unit(unitId).map { play.view.actions($0) }
        }
    }

    /// One of the player's colonies, as its panel shows it.
    public func colonyScreen(_ colonyId: String) -> ColonyScreen? {
        Messages.$scopedBundle.withValue(messages) {
            guard let colony = play.view.game.getFreeColGameObject(colonyId, as: Colony.self),
                  play.view.player.owns(colony) else { return nil }
            return play.view.colonyScreen(colony)
        }
    }

    /// Save the game, as Java's server does, AI and all, so Java can
    /// load it too.
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
        ai.toXML(xw)
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

    /// What the server asks the player, for the requests the interface
    /// answers so far.
    private static func request(_ m: ServerMessage) -> ServerRequest? {
        switch m {
        case let m as NewLandNameMessage:
            return .newLandName(unitId: m.unit.id ?? "", suggestion: m.name, text: Messages.message("newLand.text"))
        case let m as NewRegionNameMessage:
            let text = StringTemplate.template("nameRegion.text").addStringTemplate("%type%", m.region.label)
            return .newRegionName(regionId: m.region.id ?? "", tileId: m.tile.id ?? "", unitId: m.unit.id ?? "",
                                  suggestion: m.name, text: Messages.message(text) ?? "")
        case let m as FirstContactMessage where !m.other.isEuropean:
            var title = "firstContactDialog.meeting." + (m.other.nation?.suffix ?? "")
            if !Messages.containsKey(title) { title = "firstContactDialog.meeting.natives" }
            let text = StringTemplate.template(m.tile != nil ? "firstContactDialog.welcomeOffer.text"
                                                             : "firstContactDialog.welcomeSimple.text")
                .addStringTemplate("%nation%", m.other.nationLabel)
                .addName("%camps%", String(m.other.settlementCount))
                .add("%settlementType%", (m.other.nationType as? IndianNationType)?.settlementTypeKey(plural: true))
            return .firstContact(playerId: m.player.id ?? "", otherId: m.other.id ?? "", tileId: m.tile?.id,
                                 title: Messages.message(title), text: Messages.message(text) ?? "")
        default:
            return nil
        }
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
            case let .message(m):
                if let request = request(m) { ret.append(.request(request)) }
            default:
                break
            }
        }
        return ret
    }
}

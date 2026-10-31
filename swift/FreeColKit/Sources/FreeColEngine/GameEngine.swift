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
        /// The native trade under way, as the client holds it.
        var trade: NativeTrade?
        /// Whether that trade is done, to be closed.
        var tradeDone = false

        func take(_ update: PlayerUpdate, _ player: Player) {
            events += GameEngine.events(update, for: player, shown: self)
        }
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
                shown.take(update, human)
            } else if player.isAI {
                ai.handle(update, for: player)
            }
        }
        self.controller = controller
        self.ai = ai
        play = PlayController(game: game, human: human) { command in
            do {
                if let cs = try controller.perform(command, by: human), let update = try cs.build(human) {
                    shown.take(update, human)
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
                    shown.take(update, human)
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
                    shown.take(update, human)
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
        /// Trade routes: a new one, its name and stops changed, deleted,
        /// and given to a unit (or taken away).
        case activateAll(MapPosition)
        case renameColony(colonyId: String, name: String)
        case cashIn(unitId: String)
        case newTradeRoute
        case updateTradeRoute(TradeRouteInfo)
        case deleteTradeRoute(routeId: String)
        case assignTradeRoute(unitId: String, routeId: String?)
        /// Send a unit to a place chosen from its destinations.
        case selectDestination(unitId: String, destinationId: String)
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
        /// Recruit one of the emigrants at the docks (0 to 2).
        case recruit(index: Int)
        /// Train or buy a unit in Europe.
        case train(unitTypeId: String)
        /// Load goods onto a carrier: bought in Europe, or from its
        /// colony (or another carrier, if given).
        case load(goodsTypeId: String, amount: Int, carrierId: String, sourceId: String? = nil)
        /// Unload goods from a carrier: sold in Europe, or into its
        /// colony.
        case unload(goodsTypeId: String, amount: Int, carrierId: String)
        /// Unload all a carrier holds.
        case unloadAll(carrierId: String)
        case payArrears(goodsTypeId: String)
        /// Board a carrier where the unit is.
        case board(unitId: String, carrierId: String)
        case leaveShip(unitId: String)
        /// Sail a ship from Europe (to the map or a colony), or for
        /// Europe.
        case sail(carrierId: String, destinationId: String)
        /// Change a unit's role (Java's role ids), with its count.
        case equip(unitId: String, roleId: String, count: Int)
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
                case let .selectDestination(id, destination): play.selectDestination(id, destination)
                case .activateAll(let p): play.activateAll(p)
                case let .renameColony(id, name): play.renameColony(id, name)
                case .cashIn(let id): play.cashIn(id)
                case .newTradeRoute: play.newTradeRoute()
                case .updateTradeRoute(let route): play.updateTradeRoute(route)
                case .deleteTradeRoute(let id): play.deleteTradeRoute(id)
                case let .assignTradeRoute(unit, route): play.assignTradeRoute(unit, route)
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
                case .recruit(let i): play.recruit(i)
                case .train(let type): play.train(type)
                case let .load(goods, amount, carrier, source): play.load(goods, amount, onto: carrier, from: source)
                case let .unload(goods, amount, carrier): play.unload(goods, amount, from: carrier)
                case .unloadAll(let carrier): play.unloadAll(carrier)
                case .payArrears(let goods): play.payArrears(goods)
                case let .board(unit, carrier): play.board(unit, carrier)
                case .leaveShip(let unit): play.leaveShip(unit)
                case let .sail(carrier, destination): play.sail(carrier, to: destination)
                case let .equip(unit, role, count): play.equip(unit, role, count)
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
            r = CommandResult(refusal: r.refusal, events: r.events + play.requests.map { .request($0) },
                              snapshot: r.snapshot, question: r.question, notices: r.notices,
                              activeUnitId: r.activeUnitId, colonyToShow: r.colonyToShow)
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

    /// Answer something the server asked, by the command the request
    /// names.
    public func respond(_ request: ServerRequest, _ answer: RequestAnswer) -> CommandResult {
        let command: PlayerCommand?
        switch (request, answer) {
        case let (.newLandName(unit, suggestion, _), .name(name)):
            command = .newLandName(unit: unit, name: name.isEmpty ? suggestion : name)
        case let (.newRegionName(region, tile, unit, suggestion, _), .name(name)):
            command = .newRegionName(region: region, tile: tile, unit: unit, name: name.isEmpty ? suggestion : name)
        case let (.firstContact(player, other, tile, _, _), .accept(yes)):
            command = .firstContact(player: player, other: other, tile: tile, result: String(yes))
        case let (.monarch(action, _, _, yes, _), .accept(accepted)):
            command = yes == nil ? nil : .monarchAction(action: action, result: String(accepted))
        case let (.chooseFather, .choice(id)):
            command = .chooseFoundingFather(father: id)
        case let (.emigrate, .choice(index)):
            command = Int(index).map { .emigrateUnit(slot: String(Europe.MigrationType.migrantIndexToSlot($0))) }
        case let (.nativeDemand(unit, colony, type, amount, _, _, _, _), .accept(accepted)):
            command = .indianDemand(unit: unit, colony: colony, type: type, amount: String(amount),
                                    result: (accepted ? IndianDemandAction.accept : .reject).javaName)
        case let (.loot(winner, loser, _, _, _), .goods(taken)):
            command = taken.isEmpty ? nil : .lootCargo(winner: winner, loser: loser, goods: taken.map {
                CommandElement(tag: "goods", attributes: ["type": $0.typeId, "amount": String($0.amount)])
            })
        case let (.incite(unit, settlement, enemy, gold, _), .accept(yes)):
            command = yes ? .incite(unit: unit, settlement: settlement, enemy: enemy, gold: String(gold)) : nil
        case let (.nativeTrade, .trade(choice)):
            command = nativeTrade(choice)
        case let (.negotiation(n), .agreement(answer, items)):
            command = diplomacy(n, answer, items)
        default:
            command = nil
        }
        guard let command else {
            shown.events = []
            return result(nil)
        }
        return perform(command)
    }

    /// The next step of the native trade under way (nativeTrade): what
    /// to buy, sell or give, or close it.
    private func nativeTrade(_ choice: NativeTradeChoice) -> PlayerCommand? {
        guard let nt = shown.trade else { return nil }
        let action: NativeTrade.NativeTradeAction
        switch choice {
        case let .buy(index, haggle), let .sell(index, haggle):
            let buying = if case .buy = choice { true } else { false }
            let items = (buying ? nt.settlementToUnit : nt.unitToSettlement).filter(\.priceIsValid)
            guard let item = index.map({ items.indices.contains($0) ? items[$0] : nil }) ?? nt.item else {
                return nil
            }
            nt.item = item
            if haggle { item.price = NativeTradeItem.priceUnset }
            action = buying ? .buy : .sell
        case .gift(let index):
            guard nt.unitToSettlement.indices.contains(index) else { return nil }
            nt.item = nt.unitToSettlement[index]
            action = .gift
        case .close:
            shown.trade = nil
            action = .close
        }
        return .nativeTrade(action: action.javaName, trade: CommandElement(serializing: nt))
    }

    /// The agreement as answered, for the server (moveDiplomacy, or the
    /// answer to a proposal): one the player starts and then cancels is
    /// not sent, nor one to the REF.
    private func diplomacy(_ n: Negotiation, _ answer: NegotiationAnswer, _ items: [TradeOffer]) -> PlayerCommand? {
        let status: DiplomaticTrade.TradeStatus = switch answer {
        case .accept: .acceptTrade
        case .send: .proposeTrade
        case .cancel: .rejectTrade
        }
        if n.direction != nil {
            if status == .rejectTrade { return nil }
            if let other = game.getFreeColGameObject(n.otherPlayerId) as? Player, other === human.refPlayer {
                return nil
            }
        }
        guard let dt = play.view.agreement(n, items, status, lookup: { game.getFreeColGameObject($0) }) else {
            return nil
        }
        return .diplomacy(our: n.ourId, other: n.otherId, agreement: CommandElement(serializing: dt))
    }

    /// A negotiation as its dialog shows it, for the items on the table
    /// (`changed` once the player has changed them).
    public func negotiationScreen(_ n: Negotiation, items: [TradeOffer], changed: Bool) -> NegotiationScreen? {
        Messages.$scopedBundle.withValue(messages) {
            // The other's gold, as its nation summary has it.
            let gold = (game.getFreeColGameObject(n.otherPlayerId) as? Player).map { NationSummary($0, human).gold }
            return play.view.negotiationScreen(n, items, changed: changed, otherGold: gold ?? Player.goldNotAccounted)
        }
    }

    /// The choice of the next emigrant, from the three waiting now, with
    /// a number still to choose.
    public func emigrationRequest(count: Int, fountainOfYouth: Bool) -> ServerRequest {
        Messages.$scopedBundle.withValue(messages) {
            GameEngine.emigration(count, fountainOfYouth: fountainOfYouth, europe: play.view.player.europe)
        }
    }

    /// The Continental Congress, as its report shows it.
    public func congressReport() -> CongressReport {
        Messages.$scopedBundle.withValue(messages) { play.view.congressReport() }
    }

    /// The religion report, for each immigration goods type.
    public func religionReport() -> [ReligionReport] {
        Messages.$scopedBundle.withValue(messages) { play.view.religionReport() }
    }

    /// The military (land) or naval report.
    public func unitReport(military: Bool) -> UnitReport {
        Messages.$scopedBundle.withValue(messages) { play.view.unitReport(military: military) }
    }

    /// What a long press on a tile offers.
    public func tileMenu(_ position: MapPosition) -> TileMenu? {
        Messages.$scopedBundle.withValue(messages) {
            play.view.tile(position).map { play.view.tileMenu($0, activeUnit: play.unit(play.activeUnitId)) }
        }
    }

    /// The player's trade routes, and what they can be made of.
    public func tradeRoutes() -> TradeRoutesScreen {
        Messages.$scopedBundle.withValue(messages) { play.view.tradeRoutesScreen() }
    }

    /// The cargo report.
    public func cargoReport() -> UnitReport {
        Messages.$scopedBundle.withValue(messages) { play.view.unitReport(.cargo) }
    }

    /// The summary of a player the server would send.
    private func summary(_ id: String) -> NationSummary? {
        (game.getFreeColGameObject(id) as? Player).map { NationSummary($0, human) }
    }

    public func explorationReport() -> [RegionRow] { Messages.$scopedBundle.withValue(messages) { play.view.explorationReport() } }
    public func historyReport() -> [HistoryRow] { Messages.$scopedBundle.withValue(messages) { play.view.historyReport() } }
    public func educationReport() -> [SchoolRow] { Messages.$scopedBundle.withValue(messages) { play.view.educationReport() } }
    public func tradeReport() -> TradeReport { Messages.$scopedBundle.withValue(messages) { play.view.tradeReport() } }
    public func requirementsReport() -> [RequirementsRow] { Messages.$scopedBundle.withValue(messages) { play.view.requirementsReport() } }
    public func labourReport() -> [LabourRow] { Messages.$scopedBundle.withValue(messages) { play.view.labourReport() } }
    public func colonyReport() -> [ColonyReportRow] { Messages.$scopedBundle.withValue(messages) { play.view.colonyReport() } }
    public func productionReport(goodsTypeIds: [String]) -> ProductionReport {
        Messages.$scopedBundle.withValue(messages) { play.view.productionReport(goodsTypeIds) }
    }
    /// The goods the production report can show, by identifier and name.
    public func productionGoods() -> [(id: String, name: String)] {
        Messages.$scopedBundle.withValue(messages) { play.view.productionGoods.map { ($0.id ?? "", Messages.name($0)) } }
    }
    public func foreignReport() -> [ForeignRow] {
        Messages.$scopedBundle.withValue(messages) { play.view.foreignReport(summary: { summary($0) }) }
    }
    public func nativesReport() -> [NativeNationRow] {
        Messages.$scopedBundle.withValue(messages) { play.view.nativesReport(summary: { summary($0) }) }
    }

    /// For tests: the server acts on the human player, as it may during
    /// another player's turn, and the player is shown what it is sent.
    func serverActs(_ body: (ServerGame, InGameController, Player, JavaRandom) throws -> ChangeSet) throws
        -> [EngineEvent] {
        try Messages.$scopedBundle.withValue(messages) {
            let cs = try body(game, controller, human, random)
            play.invalidate()
            guard let update = try cs.build(human) else { return [] }
            return GameEngine.events(update, for: human, shown: shown)
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

    /// The player's Europe, as its panel shows it.
    public func europeScreen() -> EuropeScreen? {
        Messages.$scopedBundle.withValue(messages) { play.view.europeScreen() }
    }

    /// The role changes the unit menu offers a unit of the player's in
    /// Europe or a settlement.
    public func roleChoices(_ unitId: String) -> [RoleChoice] {
        Messages.$scopedBundle.withValue(messages) {
            play.view.unit(unitId).map { play.view.roleChoices($0) } ?? []
        }
    }

    /// The places a unit could be sent to, as Java's destination dialog
    /// lists them (for a ship in Europe, where it could sail for).
    public func destinations(_ unitId: String, order: DestinationOrder = .owner) -> [DestinationChoice] {
        Messages.$scopedBundle.withValue(messages) {
            play.view.unit(unitId).map { play.view.destinations($0, order: order) } ?? []
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
        // A trade with nothing left to do is closed (nativeTrade).
        if shown.tradeDone, let nt = shown.trade {
            shown.tradeDone = false
            shown.trade = nil
            if let cs = try? controller.perform(.nativeTrade(action: NativeTrade.NativeTradeAction.close.javaName,
                                                             trade: CommandElement(serializing: nt)), by: human),
               let update = try? cs.build(human) {
                shown.take(update, human)
            }
            play.invalidate()
        }
        let events = shown.events
        shown.events = []
        return CommandResult(refusal: refusal, events: events,
                             snapshot: SnapshotBuilder(game: game, player: human).build())
    }

    /// What the server asks the player, for the requests the interface
    /// answers so far.
    private static func request(_ m: ServerMessage, _ player: Player) -> ServerRequest? {
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
        case let m as MonarchActionMessage:
            let key = m.action.textKey
            let base = String(key.dropLast(".text".count))
            let yes = Messages.containsKey(base + ".yes") ? Messages.message(base + ".yes") : nil
            let no = Messages.message(Messages.containsKey(base + ".no") ? base + ".no" : "close")
            let header = Messages.containsKey(base + ".header") ? base + ".header" : "monarchDialog.default"
            return .monarch(action: m.action.javaName, title: Messages.message(header),
                            text: Messages.message(StringTemplate.copy(key, m.template)) ?? "", yes: yes, no: no)
        case let m as ChooseFoundingFatherMessage:
            return .chooseFather(fathers: m.fathers.map { f in
                FatherOffer(id: f.id ?? "", name: Messages.name(f),
                            typeName: f.type.map { Messages.message($0.typeKey) } ?? "",
                            description: Messages.description(f.id))
            })
        case let m as FountainOfYouthMessage:
            return emigration(m.migrants, fountainOfYouth: true, europe: player.europe)
        case let m as IndianDemandMessage where m.result == nil:
            let nation = Messages.message(m.unit.owner?.nationLabel) ?? ""
            let t: StringTemplate, yes: String, no: String
            if let type = m.type, type.isFoodType {
                t = StringTemplate.template("indianDemand.food.text")
                (yes, no) = ("indianDemand.food.yes", "indianDemand.food.no")
            } else if let type = m.type {
                t = StringTemplate.template("indianDemand.other.text").addNamed("%goods%", type)
                (yes, no) = ("accept", "indianDemand.other.no")
            } else {
                t = StringTemplate.template("indianDemand.gold.text")
                (yes, no) = ("accept", "indianDemand.gold.no")
            }
            _ = t.addName("%nation%", nation).addName("%colony%", m.colony.name).addAmount("%amount%", m.amount)
            return .nativeDemand(unitId: m.unit.id ?? "", colonyId: m.colony.id ?? "", goodsTypeId: m.type?.id,
                                 amount: m.amount,
                                 title: Messages.message(StringTemplate.template("nativeDemandDialog.name")
                                     .addName("%colony%", m.colony.name)) ?? "",
                                 text: Messages.message(t) ?? "", yes: Messages.message(yes), no: Messages.message(no))
        case let m as LootCargoMessage:
            return .loot(winnerId: m.winner.id ?? "", loserId: m.loserId,
                         goods: m.goods.map { GoodsAmount(typeId: $0.type?.id ?? "", amount: $0.amount) },
                         spaceLeft: m.winner.spaceLeft, title: Messages.message("captureGoodsDialog.title"))
        case let m as InciteMessage where m.gold >= 0:
            return .incite(unitId: m.unit.id ?? "", settlementId: m.settlement.id ?? "", enemyId: m.enemy.id ?? "",
                           gold: m.gold,
                           text: Messages.message(StringTemplate.template("missionarySettlement.inciteConfirm")
                               .addStringTemplate("%enemy%", m.enemy.nationLabel).addAmount("%amount%", m.gold)) ?? "")
        default:
            return nil
        }
    }

    /// What the player is told in answer to its own command: what a
    /// scout heard from a chief (scoutSpeakToChiefHandler).
    private static func notice(_ m: ServerMessage) -> String? {
        guard let m = m as? ScoutSpeakToChiefMessage else { return nil }
        let t: StringTemplate
        switch m.result {
        case "": return nil
        case "die": t = .key("scoutSettlement.speakDie")
        case "expert": t = StringTemplate.template("scoutSettlement.expertScout").addNamed("%unit%", m.unit.type!)
        case "tales": t = .key("scoutSettlement.speakTales")
        case "nothing":
            t = StringTemplate.template("scoutSettlement.speakNothing")
                .addStringTemplate("%nation%", m.unit.owner?.nationLabel)
        default: t = StringTemplate.template("scoutSettlement.speakBeads").add("%amount%", m.result)
        }
        return Messages.message(t)
    }

    /// A step of a native trade, from the natives (nativeTradeHandler):
    /// the next to show, or what they refused.  The client keeps its
    /// own copy of the trade, its goods for sale limited to the best
    /// three.
    private static func nativeTrade(_ m: NativeTradeMessage, _ player: Player, _ shown: Shown?) -> EngineEvent? {
        let refusal: String
        switch m.action {
        case .nakHaggle: refusal = "trade.noTradeHaggle"
        case .nakHostile: refusal = "trade.noTradeHostile"
        case .nakNosale: refusal = "trade.nothingToSell"
        case .ackOpen, .ackBuy, .ackSell, .ackGift, .ackBuyHaggle, .ackSellHaggle, .nakGoods:
            guard let game = m.trade.game, let xr = try? FreeColXMLReader(string: m.trade.serialize(.toClient(player))),
                  (try? xr.nextTag()) != nil, let nt = try? NativeTrade(game: game, xr) else { return nil }
            nt.limitSettlementToUnit(3)
            shown?.trade = nt
            if nt.isDone {
                shown?.tradeDone = true
                return nil
            }
            return PlayerView.nativeTradeScreen(m.action, nt, player).map { .request(.nativeTrade($0)) }
        default:
            return nil
        }
        shown?.trade = nil
        return .notice(Messages.message(StringTemplate.template(refusal)) ?? "")
    }

    /// A step of a negotiation (diplomacyHandler): a proposal to answer,
    /// or the answer to one.
    private static func diplomacy(_ m: DiplomacyMessage, _ player: Player) -> EngineEvent? {
        guard let agreement = m.agreement, let other = agreement.otherPlayer(player), let context = agreement.context
        else { return nil }
        switch agreement.status {
        case .acceptTrade:
            return .notice(Messages.message(StringTemplate.template("diplomacy.offerAccepted")
                .addStringTemplate("%nation%", other.nationLabel)) ?? "")
        case .rejectTrade:
            return .notice(Messages.message(StringTemplate.template("diplomacy.offerRejected")
                .addStringTemplate("%nation%", other.nationLabel)) ?? "")
        case .proposeTrade:
            return .request(.negotiation(Negotiation(
                ourId: m.ourId, otherId: m.otherId, otherPlayerId: other.id ?? "", context: context.javaName,
                playerSent: agreement.sender === player, version: agreement.version,
                items: PlayerView.offers(agreement, player),
                comment: PlayerView.receiveMessage(context, other), direction: nil)))
        }
    }

    /// What a spy sees of a colony: its panel, as its owner sees it
    /// (spySettlementHandler).
    private static func spied(_ settlement: Settlement) -> ColonyScreen? {
        guard let colony = settlement as? Colony, let owner = colony.owner, let game = colony.game, let id = colony.id,
              let view = try? PlayerView(of: game, for: owner),
              let copy = view.game.getFreeColGameObject(id, as: Colony.self) else { return nil }
        return view.colonyScreen(copy)
    }

    /// Choosing emigrants (EmigrationDialog): from the three waiting.
    static func emigration(_ count: Int, fountainOfYouth: Bool, europe: Europe? = nil) -> ServerRequest {
        var text = Messages.message("emigrationDialog.chooseImmigrant")
        if fountainOfYouth {
            text = Messages.message(LostCityRumour.RumourType.fountainOfYouth.descriptionKey) + "\n\n" + text
        }
        return .emigrate(count: count, fountainOfYouth: fountainOfYouth, text: text,
                         choices: (europe?.expandedRecruitables(full: false) ?? []).map {
                             Messages.message($0.singleLabel) ?? ""
                         })
    }

    /// The events in what a player was sent: moves and attacks to show,
    /// and messages.
    private static func events(_ update: PlayerUpdate, for player: Player, shown: Shown?) -> [EngineEvent] {
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
            case let .spy(_, settlement):
                if let screen = spied(settlement) { ret.append(.spied(screen)) }
            case let .message(m as NativeTradeMessage):
                if let event = nativeTrade(m, player, shown) { ret.append(event) }
            case let .message(m as DiplomacyMessage):
                if let event = diplomacy(m, player) { ret.append(event) }
            case let .message(m):
                if let request = request(m, player) {
                    ret.append(.request(request))
                } else if let notice = notice(m) {
                    ret.append(.notice(notice))
                }
            default:
                break
            }
        }
        return ret
    }
}

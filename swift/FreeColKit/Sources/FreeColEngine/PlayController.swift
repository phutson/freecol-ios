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

/// Something the client asks the player before going on: a
/// confirmation, a choice, or a name.  The interface asks it, then makes
/// the same request again with the answer.
public struct PlayQuestion: Sendable, Equatable {
    /// What is asked, unique within the request ("highseas:unit:12").
    public let id: String
    public let text: String
    /// The answers to choose from, the first the one to accept.  None
    /// for a name, which is typed.
    public let choices: [PlayChoice]
    /// For a name: the name to offer.
    public var suggestion: String?
    /// The unit the question is about, if any.
    public var unitId: String?
}

public struct PlayChoice: Sendable, Equatable {
    public let id: String
    public let label: String
}

/// Something the server asks the player, which the interface answers
/// with the command it names.
public enum ServerRequest: Sendable, Equatable {
    /// Name the new land (a newLandName command).
    case newLandName(unitId: String, suggestion: String, text: String)
    /// Name a region found (a newRegionName command).
    case newRegionName(regionId: String, tileId: String, unitId: String, suggestion: String, text: String)
    /// First contact with natives: welcome, and perhaps land offered (a
    /// firstContact command, accepted or not).
    case firstContact(playerId: String, otherId: String, tileId: String?, title: String, text: String)
}

/// Java's client InGameController, for playing on the map: moving
/// units, sending them to a destination, the unit actions, and ending
/// the turn, with the questions Java's GUI asks along the way.
///
/// Its decisions are made on the player's copy of the game, read afresh
/// after each command, and its commands go to the server.  The
/// player's answers are given with the request; at the first question
/// without one, the request stops and returns it.  Asking again with
/// the answer makes the same decisions up to there, and goes on.
final class PlayController {

    /// What the client is doing with the units (InGameController.MoveMode).
    enum MoveMode: Int, Comparable {
        case nextActiveUnit, executeGotoOrders, endTurn

        static func < (a: MoveMode, b: MoveMode) -> Bool { a.rawValue < b.rawValue }
    }

    private let game: ServerGame
    private let human: Player
    /// Send a command to the server: nil if it was carried out, or why
    /// not.
    private let send: (PlayerCommand) -> String?
    private var cached: PlayerView?

    var cycle = ActiveUnitCycle()
    private var goingTo = GoingToCycle()
    var moveMode = MoveMode.nextActiveUnit
    /// The unit the player is moving (GUI.getActiveUnit).
    var activeUnitId: String?

    // What one request was answered, asked and told.
    private var answers: [String: String] = [:]
    private(set) var question: PlayQuestion?
    private(set) var notices: [String] = []
    private(set) var colonyToShow: String?
    /// Whether the GUI is to be updated at the end of the request, and
    /// whether a new active unit is to be chosen anyway.
    private var updateRequested = false
    private var updateUnitRequested = false

    init(game: ServerGame, human: Player, send: @escaping (PlayerCommand) -> String?) {
        self.game = game
        self.human = human
        self.send = send
    }

    /// The player's copy of the game as it is now.
    var view: PlayerView {
        if let cached { return cached }
        do {
            let v = try PlayerView(of: game, for: human)
            cached = v
            return v
        } catch {
            preconditionFailure("The player's copy of the game can not be read: \(error)")
        }
    }

    /// The game has changed, by a command or another player's turn.
    func invalidate() {
        cached = nil
    }

    // MARK: Requests

    /// Run a request with the answers given so far.
    func run(_ answers: [String: String], _ body: () -> Void) {
        self.answers = answers
        question = nil
        notices = []
        colonyToShow = nil
        updateRequested = false
        updateUnitRequested = false
        body()
        if updateRequested && question == nil { finishUpdate() }
    }

    private var ourTurn: Bool { game.currentPlayer === human }

    private func unit(_ id: String?) -> Unit? { id.flatMap { view.unit($0) } }

    /// Send a command; a refusal is told to the player, as Java shows
    /// the server's error.
    private func command(_ c: PlayerCommand) -> Bool {
        let refusal = send(c)
        invalidate()
        if let refusal { notices.append(refusal) }
        return refusal == nil
    }

    private func tell(_ t: StringTemplate) {
        notices.append(Messages.message(t) ?? "")
    }

    /// The answer to a question, or nil if it is not answered yet (and
    /// then the request stops at it).
    private func ask(_ q: PlayQuestion) -> String? {
        if let a = answers[q.id] { return a }
        if question == nil { question = q }
        return nil
    }

    private func confirm(_ id: String, _ unitId: String?, _ text: StringTemplate, _ yes: String, _ no: String) -> Bool {
        ask(PlayQuestion(id: id, text: Messages.message(text) ?? "",
                         choices: [PlayChoice(id: "yes", label: Messages.message(yes)),
                                   PlayChoice(id: "no", label: Messages.message(no))],
                         unitId: unitId)) == "yes"
    }

    /// Ask for the GUI to be brought up to date at the end of the
    /// request (Java's updateGUI, run later).
    private func updateGUI(_ updateUnit: Bool = false) {
        updateRequested = true
        if updateUnit { updateUnitRequested = true }
    }

    /// Choose a new active unit if the current one is done
    /// (InGameController.updateGUI).
    private func finishUpdate() {
        let active = unit(activeUnitId)
        if updateUnitRequested || active == nil || !(active?.isCandidateForNextActiveUnit ?? false) {
            updateActiveUnit()
        }
    }

    /// Make the next unit active, or, with none left, carry out the goto
    /// orders (InGameController.updateActiveUnit).
    private func updateActiveUnit() {
        if moveMode != .nextActiveUnit {
            if activeUnitId != nil { moveMode = .nextActiveUnit }
            return
        }
        if let next = cycle.next(view) {
            activeUnitId = next.id
            return
        }
        if !doExecuteGotoOrders() { return }
        activeUnitId = nil
    }

    // MARK: The turn

    /// The player's turn begins (InGameController.setCurrentPlayer).
    func startTurn() {
        run([:]) {
            moveMode = .nextActiveUnit
            cycle.reset()
            goingTo.reset()
            activeUnitId = nil
            updateGUI()
        }
    }

    /// Select a unit to move (GUI.changeView).
    func select(_ unitId: String?) {
        activeUnitId = unit(unitId)?.id
    }

    /// Move on to the next unit (InGameController.nextActiveUnit and
    /// waitUnit).
    func nextUnit(wait: Bool) {
        guard ourTurn else { return }
        updateGUI(wait)
    }

    /// The units still waiting for orders, which the end turn dialog
    /// lists.
    var waitingUnitIds: [String] {
        view.player.units.filter(\.isCandidateForNextActiveUnit).compactMap(\.id)
    }

    /// End the turn, if all is well (InGameController.doEndTurn):
    /// asking first if units are waiting, then skipping those that
    /// could still move, and carrying out the goto orders.
    ///
    /// - Returns: Whether the server can be told the turn is over.
    func endTurn(showDialog: Bool) -> Bool {
        if showDialog {
            let waiting = view.player.units.filter(\.isCandidateForNextActiveUnit)
            if !waiting.isEmpty {
                let t = StringTemplate.template("endTurnDialog.areYouSure").addAmount("%number%", waiting.count)
                if !confirm("endTurn", nil, t, "ok", "cancel") { return false }
            }
        }
        moveMode = max(moveMode, .endTurn)
        activeUnitId = nil
        for u in view.player.units.filter(\.couldMove).compactMap(\.id) {
            if let unit = unit(u), unit.state != .skipped { _ = changeState(u, .skipped) }
        }
        if !doExecuteGotoOrders() || moveMode < .endTurn { return false }
        moveMode = .nextActiveUnit
        return true
    }

    // MARK: Goto orders

    /// Move the units with destinations as far as they go, the active
    /// one first (InGameController.doExecuteGotoOrders).
    ///
    /// - Returns: False if a unit needs the player's attention.
    func doExecuteGotoOrders() -> Bool {
        var active = activeUnitId
        var ret = true
        moveMode = max(moveMode, .executeGotoOrders)
        // Trade routes are not followed yet.
        if question != nil { return false }
        if let active { goingTo.setNext(active, view) }
        while let u = goingTo.next(view), let id = u.id {
            activeUnitId = id
            if !moveToDestination(id) {
                ret = false
                break
            }
            if active == id { active = nil }
        }
        if ret { activeUnitId = unit(active)?.id }
        return ret
    }

    /// Send a unit along a goto path to its end
    /// (InGameController.goToTile).
    func goTo(_ unitId: String, _ end: PathPlace) {
        guard ourTurn, let u = unit(unitId) else { return }
        let destination: (any Location)?
        switch end {
        case .tile(let p): destination = view.tile(p)
        case .europe: destination = view.player.europe
        case .carrier(let id, _): destination = view.game.getFreeColGameObject(id, as: Unit.self)
        }
        guard let destination, setDestination(u, destination) else { return }
        _ = moveToDestination(unitId)
        updateGUI()
    }

    /// The path a unit's destination takes (or Java's goto cursor, to
    /// a place).
    private func setDestination(_ u: Unit, _ destination: (any Location)?) -> Bool {
        if u.destination === destination as AnyObject? || (u.destination == nil && destination == nil) { return true }
        guard let id = u.id, command(.setDestination(unit: id, destination: destination?.id)) else { return false }
        return unit(id)?.destination?.id == destination?.id
    }

    /// Clear a unit's destination (askClearGotoOrders; trade routes are
    /// not assigned yet).
    private func clearGotoOrders(_ unitId: String) -> Bool {
        guard let u = unit(unitId) else { return false }
        return setDestination(u, nil)
    }

    /// Move a unit towards its destination (moveToDestination).
    ///
    /// - Returns: True if all is well, false if the player should look
    ///   at the unit.
    private func moveToDestination(_ unitId: String) -> Bool {
        guard let u = unit(unitId) else { return true }
        let player = view.player
        if !ourTurn || u.isAtSea || u.movesLeft <= 0 || u.state == .skipped { return true }
        if u.tradeRoute != nil { return true }
        guard let destination = u.destination else { return true }
        if !changeState(unitId, .active) { return true }
        guard let u = unit(unitId), let path = PlayerView.path(u.findPath(destination)) else {
            if let u = unit(unitId) {
                tell(StringTemplate.template("info.moveToDestinationFailed")
                    .addStringTemplate("%unit%", u.label(.national))
                    .addStringTemplate("%location%", locationLabel(u.location, for: player))
                    .addStringTemplate("%destination%", locationLabel(destination, for: player)))
            }
            _ = changeState(unitId, .skipped)
            return false
        }
        let destinationId = destination.id
        if !movePath(unitId, path) { return false }
        guard let u = unit(unitId) else { return true }
        if let d = u.destination ?? view.game.getFreeColGameObject(destinationId) as? any Location,
           u.isAtLocation(d) {
            let colony = u.hasTile ? u.tile?.colony : nil
            if !clearGotoOrders(unitId) { return false }
            if let colony {
                if checkCashInTreasureTrain(unitId) { return true }
                colonyToShow = colony.id
                return false
            }
            return (unit(unitId)?.movesLeft ?? 0) == 0
        }
        return true
    }

    /// Follow a path (movePath).
    private func movePath(_ unitId: String, _ path: UnitPath) -> Bool {
        for step in path.steps {
            guard let u = unit(unitId) else { return false }
            switch step.place {
            case .tile(let p):
                if let t = u.tile, t.x == p.x, t.y == p.y { continue }
                guard let name = step.direction, let d = Direction.allDirections.first(where: { $0.javaName == name }) else {
                    if u.isInEurope { return moveAwayFromEurope(unitId) }
                    return false
                }
                if !moveDirection(unitId, d, interactive: false) {
                    return unit(unitId)?.moveType(d) == .moveNoMoves
                }
            case .europe:
                if u.isInEurope { continue }
                if let t = u.tile, t.isDirectlyHighSeasConnected { return moveTowardEurope(unitId) }
                return false
            case .carrier(let id, _):
                if u.location?.id == id { continue }
                return step.direction.flatMap { n in Direction.allDirections.first { $0.javaName == n } }
                    .map { moveEmbark(unitId, $0) } ?? false
            }
        }
        return true
    }

    // MARK: Moves

    /// Move a unit one tile, as the player asked (moveUnit).
    func moveUnit(_ unitId: String, _ direction: Direction) {
        guard ourTurn, let u = unit(unitId), let oldTile = u.tile else { return }
        let old = (oldTile.x, oldTile.y)
        if !clearGotoOrders(unitId) { return }
        _ = changeState(unitId, .active)
        _ = moveDirection(unitId, direction, interactive: true)
        updateGUI()
        if let u = unit(unitId), let t = u.tile, (t.x, t.y) != old, !u.couldMove, let colony = t.colony {
            colonyToShow = colony.id
        }
    }

    /// Move a unit in a direction, by what the move would do
    /// (moveDirection).
    ///
    /// - Returns: True if automatic movement can go on.
    private func moveDirection(_ unitId: String, _ direction: Direction, interactive: Bool) -> Bool {
        guard let u = unit(unitId), let oldTile = u.tile else { return false }
        let destination = u.destination
        var destinationImminent = destination != nil
            && Map.isSameLocation(oldTile.neighbour(direction), destination)
        let mt = u.moveType(direction)
        var result = mt.isLegal
        let illegal = interactive || destinationImminent
        func noAccess(_ key: String, nation: Bool, unit addUnit: Bool) {
            guard illegal else { return }
            var t = StringTemplate.template(key)
            if nation { t = t.addStringTemplate("%nation%", nationAt(oldTile, direction)) }
            if addUnit { t = t.addStringTemplate("%unit%", u.label(.national)) }
            tell(t)
        }
        switch mt {
        case .moveHighSeas:
            if destination is Europe && view.player.europe != nil {
                result = moveTowardEurope(unitId)
            } else if destination == nil {
                result = moveHighSeas(unitId, direction)
            } else {
                result = moveTile(unitId, direction)
            }
        case .move: result = moveTile(unitId, direction)
        case .exploreLostCityRumour: result = moveExplore(unitId, direction)
        case .attackUnit: result = moveAttack(unitId, direction)
        case .embark: result = moveEmbark(unitId, direction)
        case .enterIndianSettlementWithFreeColonist: result = moveLearnSkill(unitId, direction)
        case .attackSettlement, .enterIndianSettlementWithScout, .enterIndianSettlementWithMissionary,
             .enterForeignColonyWithScout, .enterSettlementWithCarrierAndGoods:
            // Dealing with settlements comes with the screens for it.
            if illegal { notices.append(Messages.message("model.option.notYetAvailable")) }
            result = false
        case .moveNoAccessBeached: noAccess("move.noAccessBeached", nation: true, unit: false)
        case .moveNoAccessContact: noAccess("move.noAccessContact", nation: true, unit: false)
        case .moveNoAccessGoods: noAccess("move.noAccessGoods", nation: true, unit: true)
        case .moveNoAccessLand:
            _ = moveDisembark(unitId, direction)
        case .moveNoAccessMissionBan: noAccess("move.noAccessMissionBan", nation: true, unit: true)
        case .moveNoAccessSettlement: noAccess("move.noAccessSettlement", nation: true, unit: true)
        case .moveNoAccessSkill: noAccess("move.noAccessSkill", nation: false, unit: true)
        case .moveNoAccessTrade: noAccess("move.noAccessTrade", nation: true, unit: false)
        case .moveNoAccessWar: noAccess("move.noAccessWar", nation: true, unit: false)
        case .moveNoAccessWater: noAccess("move.noAccessWater", nation: false, unit: true)
        case .moveNoAttackMarine: noAccess("move.noAttackWater", nation: false, unit: true)
        case .moveNoMoves:
            // Not this turn, but perhaps the next.
            destinationImminent = false
            _ = changeState(unitId, .skipped)
        case .moveNoTile: noAccess("move.noTile", nation: false, unit: true)
        default:
            result = false
        }
        if destinationImminent && unit(unitId) != nil && question == nil {
            // Arrived, or failed at the last step: either way the orders
            // are done.
            if !clearGotoOrders(unitId) { result = false }
        }
        return result && question == nil
    }

    /// The nation on a neighbouring tile (getNationAt).
    private func nationAt(_ tile: Tile, _ direction: Direction) -> StringTemplate? {
        guard let t = tile.neighbour(direction) else { return nil }
        let player = t.settlement?.owner ?? t.firstUnit?.owner ?? view.game.unknownEnemy
        return player?.nationLabel
    }

    /// An ordinary move (moveTile).
    private func moveTile(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId) else { return false }
        let discover = u.tile?.neighbour(direction)?.discoverableRegion != nil
        if !command(.move(unit: unitId, direction: direction.javaName)) {
            _ = changeState(unitId, .skipped)
            return false
        }
        guard unit(unitId) != nil, !checkCashInTreasureTrain(unitId), let u = unit(unitId) else { return false }
        if u.isInColony, u.isCarrier, u.tradeRoute == nil, let tile = u.tile,
           Map.isSameLocation(tile, u.destination) {
            colonyToShow = tile.colony?.id
            return false
        }
        return !discover
    }

    /// Onto the high seas: perhaps sail to Europe (moveHighSeas).
    private func moveHighSeas(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let oldTile = u.tile else { return false }
        let newTile = oldTile.neighbour(direction)
        if newTile == nil || (!oldTile.isDirectlyHighSeasConnected && newTile!.isDirectlyHighSeasConnected) {
            if u.destination is Europe { return moveTowardEurope(unitId) }
            let t = StringTemplate.template("highseas.text").addAmount("%number%", u.sailTurns)
            if confirm("highseas:\(unitId)", unitId, t, "highseas.yes", "highseas.no") {
                return moveTowardEurope(unitId)
            }
            if question != nil { return false }
        }
        return moveTile(unitId, direction)
    }

    /// Sail for Europe (moveTowardEurope).
    private func moveTowardEurope(_ unitId: String) -> Bool {
        if let europe = view.player.europe?.id, command(.moveTo(unit: unitId, destination: europe)) {
            updateGUI()
        }
        return false
    }

    /// Sail from Europe to the map (moveAwayFromEurope; emigrants are
    /// not loaded automatically, by default).
    private func moveAwayFromEurope(_ unitId: String) -> Bool {
        guard let map = view.game.map?.id else { return false }
        let ret = command(.moveTo(unit: unitId, destination: map))
        if ret { updateGUI() }
        return ret
    }

    /// Explore a rumour, if the player is sure (moveExplore).
    private func moveExplore(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let tile = u.tile?.neighbour(direction) else { return false }
        if !confirm("exploreLostCityRumour:\(unitId)", unitId, .key("exploreLostCityRumour.text"),
                    "exploreLostCityRumour.yes", "exploreLostCityRumour.no") {
            if question == nil, u.destination != nil { _ = clearGotoOrders(unitId) }
            return false
        }
        if tile.lostCityRumour?.type == .mounds
            && !confirm("exploreMoundsRumour:\(unitId)", unitId, .key("exploreMoundsRumour.text"),
                        "exploreLostCityRumour.yes", "exploreLostCityRumour.no") {
            if question == nil { _ = command(.declineMounds(unit: unitId, direction: direction.javaName)) }
            return false
        }
        _ = moveTile(unitId, direction)
        return false
    }

    /// Attack a unit, if the player is sure (moveAttack).
    private func moveAttack(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let target = u.tile?.neighbour(direction),
              let defender = target.firstUnit, !(u.owner?.owns(defender) ?? true) else { return false }
        if clearGotoOrders(unitId), confirmHostileAction(unitId, target), confirmPreCombat(unitId, target) {
            _ = command(.attack(unit: unitId, direction: direction.javaName))
        }
        return false
    }

    /// Confirm an act of war, unless at war already
    /// (GUI.confirmHostileAction).
    private func confirmHostileAction(_ unitId: String, _ target: Tile) -> Bool {
        guard let attacker = unit(unitId) else { return false }
        if attacker.hasAbility(Ability.piracy) { return true }
        let enemy: Player?
        if let s = target.settlement {
            enemy = s.owner
        } else if target === attacker.tile {
            guard let owner = target.owner else { return true }
            enemy = owner
        } else {
            guard let defender = target.defendingUnit(attacker) else { return true }
            if defender.hasAbility(Ability.piracy) { return true }
            enemy = defender.owner
        }
        let key: String
        switch attacker.owner?.stance(enemy) ?? .peace {
        case .war: return true
        case .ceaseFire: key = "confirmHostile.ceaseFire"
        case .alliance: key = "confirmHostile.alliance"
        case .uncontacted, .peace: key = "confirmHostile.peace"
        }
        let t = StringTemplate.template(key).addStringTemplate("%nation%", enemy?.nationLabel)
        return confirm("confirmHostile:\(unitId)", unitId, t, "confirmHostile.yes", "cancel")
    }

    /// Show the odds, and let the player think again (the pre-combat
    /// dialog, which the client shows by default).
    private func confirmPreCombat(_ unitId: String, _ target: Tile) -> Bool {
        guard let attacker = unit(unitId), let cm = view.game.combatModel as CombatModel? else { return false }
        let defender: FreeColGameObject? = target.settlement ?? target.defendingUnit(attacker)
        let offence = cm.offencePower(attacker, defender)
        let defence = cm.defencePower(attacker, defender)
        let odds = cm.calculateCombatOdds(attacker, defender).win
        let name = Messages.message(attacker.label(.national)) ?? ""
        let other = (defender as? Unit).flatMap { Messages.message($0.label(.national)) }
            ?? (defender as? Settlement)?.name ?? ""
        func f(_ d: Double) -> String { String(Int((d * 10).rounded())) .inserting(".") }
        let text = "\(name): \(f(offence))\n\(other): \(f(defence))\n"
            + Messages.message("model.option.guiShowPreCombat.name") + ": \(Int((odds * 100).rounded()))%"
        return ask(PlayQuestion(id: "preCombat:\(unitId)", text: text,
                                choices: [PlayChoice(id: "yes", label: Messages.message("ok")),
                                          PlayChoice(id: "no", label: Messages.message("cancel"))],
                                unitId: unitId)) == "yes"
    }

    /// Board a carrier next to the unit (moveEmbark).
    private func moveEmbark(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let destinationTile = u.tile?.neighbour(direction) else { return false }
        if u.colony != nil && !confirmLeaveColony(unitId) { return false }
        let carriers = destinationTile.units.filter { $0.canAdd(u) }
        var carrierId: String?
        if carriers.count == 1 {
            carrierId = carriers[0].id
        } else if carriers.count > 1 {
            let choices = carriers.map { PlayChoice(id: $0.id ?? "", label: Messages.message($0.label(.national)) ?? "") }
            carrierId = ask(PlayQuestion(id: "embark:\(unitId)", text: Messages.message("embark.text"),
                                         choices: choices + [PlayChoice(id: "none", label: Messages.message("none"))],
                                         unitId: unitId))
            if carrierId == "none" { return false }
        }
        guard let carrierId else { return false }
        if clearGotoOrders(unitId),
           command(.embark(unit: unitId, carrier: carrierId, direction: direction.javaName)),
           unit(unitId)?.location?.id == carrierId {
            // Aboard.
        } else if question == nil {
            _ = changeState(unitId, .skipped)
        }
        return false
    }

    /// Leave a ship onto the land next to it (moveDisembark).
    private func moveDisembark(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let tile = u.tile?.neighbour(direction) else { return false }
        if let first = tile.firstUnit, first.owner !== u.owner { return false }
        let ids = u.units.filter { $0.moveType(tile).isProgress }.compactMap(\.id)
        if ids.isEmpty { return false }
        for id in ids { _ = changeState(id, .active) }
        if ids.count == 1 {
            if confirm("disembark:\(unitId)", unitId, .key("disembark.text"), "ok", "cancel") {
                _ = moveDirection(ids[0], direction, interactive: false)
            }
        } else {
            var choices = ids.compactMap { id in
                unit(id).map { PlayChoice(id: id, label: Messages.message($0.label(.national)) ?? "") }
            }
            choices.append(PlayChoice(id: unitId, label: Messages.message("all")))
            choices.append(PlayChoice(id: "none", label: Messages.message("none")))
            switch ask(PlayQuestion(id: "disembark:\(unitId)", text: Messages.message("disembark.text"),
                                    choices: choices, unitId: unitId)) {
            case nil, "none": break
            case unitId: for id in ids { _ = moveDirection(id, direction, interactive: false) }
            case let id?: _ = moveDirection(id, direction, interactive: false)
            }
        }
        return true
    }

    /// Learn from natives (moveLearnSkill).
    private func moveLearnSkill(_ unitId: String, _ direction: Direction) -> Bool {
        guard clearGotoOrders(unitId), command(.askSkill(unit: unitId, direction: direction.javaName)),
              let u = unit(unitId), let settlement = u.tile?.neighbour(direction)?.settlement as? IndianSettlement
        else { return false }
        if let skill = settlement.learnableSkill {
            if u.unitChange(UnitChangeType.natives) == nil {
                tell(StringTemplate.template("info.cantLearnSkill")
                    .addStringTemplate("%unit%", u.label(.national)).addNamed("%skill%", skill))
            } else if confirm("learnSkill:\(unitId)", unitId,
                              StringTemplate.template("learnSkill.text").addNamed("%skill%", skill),
                              "learnSkill.yes", "learnSkill.no"),
                      command(.learnSkill(unit: unitId, direction: direction.javaName)) {
                if let after = unit(unitId) {
                    if after.type !== view.game.specification?.getUnitType(skill.id) { tell(.key("learnSkill.leave")) }
                } else {
                    tell(.key("learnSkill.die"))
                }
            }
        } else {
            tell(.key("info.noMoreSkill"))
        }
        return false
    }

    /// Cash in a treasure train in a colony, if the player agrees
    /// (checkCashInTreasureTrain).
    private func checkCashInTreasureTrain(_ unitId: String) -> Bool {
        guard ourTurn, let u = unit(unitId), u.canCarryTreasure, u.canCashInTreasureTrain else { return false }
        if view.player.europe != nil && !u.isInEurope {
            let fee = u.transportFee
            let t = fee == 0 ? StringTemplate.template("cashInTreasureTrain.free")
                : StringTemplate.template("cashInTreasureTrain.pay")
                    .addAmount("%fee%", view.game.specification?.getInteger(GameOptions.treasureTransportFee) ?? 0)
            if !confirm("cashInTreasureTrain:\(unitId)", unitId, t, "accept", "reject") { return false }
        }
        return command(.cashInTreasureTrain(unit: unitId)) && unit(unitId) == nil
    }

    private func confirmLeaveColony(_ unitId: String) -> Bool {
        // Java warns when a colony would lose what it needs; that comes
        // with the colony screen.
        true
    }

    // MARK: Unit actions

    /// Change a unit's state (changeState), asking first before
    /// fortifying on another's land.
    @discardableResult
    func changeState(_ unitId: String, _ state: Unit.UnitState) -> Bool {
        guard ourTurn, let u = unit(unitId) else { return false }
        if u.state == state { return true }
        if !u.checkSetState(state) { return false }
        if state == .fortifying && u.isOffensiveUnit && !u.isOwnerHidden,
           let tile = u.tile, let enemy = tile.owningSettlement?.owner,
           enemy !== view.player, view.player.stance(enemy) != .alliance,
           !confirmHostileAction(unitId, tile) {
            return false
        }
        let ret = command(.changeState(unit: unitId, state: state.javaName)) && unit(unitId)?.state == state
        if ret { updateGUI() }
        return ret
    }

    /// Skip a unit this turn (SkipUnitAction).
    func skip(_ unitId: String) {
        if unit(unitId)?.state != .skipped { changeState(unitId, .skipped) }
        if unit(unitId)?.state == .skipped { nextUnit(wait: false) }
    }

    /// Start improving the tile (changeWorkImprovementType), claiming it
    /// first if need be.
    func improve(_ unitId: String, _ improvementTypeId: String) {
        guard ourTurn, let u = unit(unitId), let tile = u.tile, u.checkSetState(.improving),
              let type = view.game.specification?.getTileImprovementType(improvementTypeId), !type.isNatural
        else { return }
        let player = view.player
        guard player.owns(tile) || claimTile(tile, claimant: unitId, price: player.landPrice(tile)) else { return }
        updateGUI()
        if command(.changeWorkImprovementType(unit: unitId, improvementType: improvementTypeId)),
           unit(unitId)?.workImprovement?.type?.id == improvementTypeId {
            updateGUI()
        }
    }

    /// Claim a tile, buying or taking it from natives (askClaimTile).
    private func claimTile(_ tile: Tile, claimant: String, price: Int) -> Bool {
        let player = view.player
        var price = price
        if price < 0 { return false }
        if price > 0 {
            guard let owner = tile.owner else { return false }
            var choices: [PlayChoice] = []
            let text: StringTemplate
            if owner.hasContacted(player) {
                text = StringTemplate.template("indianLand.text").addStringTemplate("%player%", owner.nationLabel)
                if player.checkGold(price) {
                    choices.append(PlayChoice(id: "accept", label: Messages.message(
                        StringTemplate.template("indianLand.pay").addAmount("%amount%", price)) ?? ""))
                }
            } else {
                text = .template("indianLand.unknown")
            }
            choices.append(PlayChoice(id: "steal", label: Messages.message("indianLand.take")))
            choices.append(PlayChoice(id: "cancel", label: Messages.message("indianLand.cancel")))
            switch ask(PlayQuestion(id: "claim:\(tile.id ?? "")", text: Messages.message(text) ?? "",
                                    choices: choices, unitId: claimant)) {
            case "accept": break
            case "steal": price = Constants.stealLand
            default: return false
            }
        }
        guard let tileId = tile.id, command(.claimLand(tile: tileId, claimant: claimant, price: String(price))),
              let t = view.tile(MapPosition(x: tile.x, y: tile.y)) else { return false }
        return view.player.owns(t)
    }

    /// Found a colony, or join the one here (buildColony).
    func buildColony(_ unitId: String) {
        guard ourTurn, let u = unit(unitId), let tile = u.tile else { return }
        if !u.canBuildColony {
            tell(StringTemplate.template("buildColony.badUnit").addName("%unit%", u.name))
            return
        }
        if let colony = tile.colony {
            if command(.joinColony(colony: colony.id, unit: unitId)), unit(unitId)?.state == .inColony {
                updateGUI()
                colonyToShow = colony.id
            }
            return
        }
        let player = view.player
        switch player.canClaimToFoundSettlementReason(tile) {
        case .none, .natives: break
        case let reason:
            tell(.key("model.noClaimReason.\(reason.javaName.lowercased()).description"))
            return
        }
        let warnings = PlayerView.buildColonyWarnings(tile, u)
        if !warnings.isEmpty {
            let t = StringTemplate.label("\n")
            for w in warnings { _ = t.addStringTemplate(w) }
            if !confirm("buildColonyWarnings:\(unitId)", unitId, t, "buildColony.yes", "buildColony.no") { return }
        }
        let suggestion = game.nameCache.settlementName(human, nil)
        guard let name = ask(PlayQuestion(id: "colonyName:\(unitId)", text: Messages.message("nameColony.text"),
                                          choices: [], suggestion: suggestion, unitId: unitId)) else {
            game.nameCache.putSettlementName(human, suggestion)
            return
        }
        if name.isEmpty {
            tell(.key("enterSomeText"))
            return
        }
        if human.settlement(byName: name) != nil {
            tell(StringTemplate.template("nameColony.notUnique").addName("%name%", name))
            return
        }
        if name != suggestion { game.nameCache.putSettlementName(human, suggestion) }
        var ret = player.owns(tile)
        if !ret {
            ret = claimTile(tile, claimant: unitId, price: player.landPrice(tile))
            if !ret { game.nameCache.putSettlementName(human, name) }
        }
        if ret, command(.buildColony(name: name, unit: unitId)),
           let t = view.tile(MapPosition(x: tile.x, y: tile.y)), let colony = t.colony {
            for id in t.units.compactMap(\.id) { _ = checkCashInTreasureTrain(id) }
            updateGUI()
            colonyToShow = colony.id
        }
    }

    /// Disband a unit, if the player is sure (disbandUnit).
    func disband(_ unitId: String) {
        guard ourTurn, unit(unitId) != nil else { return }
        if !confirm("disbandUnit:\(unitId)", unitId, .key("disbandUnit.text"), "disbandUnit.yes", "cancel") { return }
        if command(.disbandUnit(unit: unitId)), unit(unitId) == nil { updateGUI() }
    }

    /// Clear a unit's orders (clearOrders), asking first if it is
    /// improving a tile.
    func clearOrders(_ unitId: String) {
        guard ourTurn, let u = unit(unitId) else { return }
        if u.state == .improving {
            let t = StringTemplate.template("clearOrders.text").addAmount("%turns%", u.workTurnsLeft)
            if !confirm("clearOrders:\(unitId)", unitId, t, "ok", "cancel") { return }
        }
        if clearGotoOrders(unitId), changeState(unitId, .active) { updateGUI() }
    }

    /// Carry out the goto orders now (executeGotoOrders).
    func executeGotoOrders() {
        guard ourTurn else { return }
        _ = doExecuteGotoOrders()
    }
}

/// The units with destinations to move towards, round by where they
/// are (Player.getNextGoingToUnit), kept by identifier.
struct GoingToCycle {
    private var waiting: [String] = []

    mutating func reset() {
        waiting = []
    }

    private func refill(_ view: PlayerView) -> [String] {
        view.player.units.filter(\.goingToDestination).sorted { $0.rank < $1.rank }.compactMap(\.id)
    }

    /// Put a unit first, if it is going somewhere (setNextGoingToUnit).
    mutating func setNext(_ id: String, _ view: PlayerView) {
        guard let u = view.unit(id), u.goingToDestination else { return }
        let sentinel = waiting.first
        while !waiting.isEmpty {
            if waiting[0] == id { return }
            waiting.removeFirst()
        }
        waiting = refill(view)
        while !waiting.isEmpty && waiting[0] != sentinel {
            if waiting[0] == id { return }
            waiting.removeFirst()
        }
    }

    mutating func next(_ view: PlayerView) -> Unit? {
        while !waiting.isEmpty {
            let id = waiting.removeFirst()
            if let u = view.unit(id), u.goingToDestination { return u }
        }
        waiting = refill(view)
        while !waiting.isEmpty {
            let id = waiting.removeFirst()
            if let u = view.unit(id), u.goingToDestination { return u }
        }
        return nil
    }
}

private extension String {
    /// A number of tenths written with its point ("125" → "12.5").
    func inserting(_ point: String) -> String {
        let s = count < 2 ? String(repeating: "0", count: 2 - count) + self : self
        return String(s.dropLast()) + point + String(s.suffix(1))
    }
}

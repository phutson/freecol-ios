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

/// What the questions about entering a settlement say (the GUI's
/// getScoutIndianSettlementChoice, getMissionaryChoice,
/// getArmedUnitSettlementChoice, getScoutForeignColonyChoice and
/// confirmNativeTribute), made on the player's copy of the game.
extension PlayerView {

    /// A scout's greeting at a native settlement, with the number of the
    /// owner's settlements ("many" if not known).
    static func scoutGreeting(_ settlement: IndianSettlement, _ player: Player, settlements: Int) -> StringTemplate {
        guard let owner = settlement.owner else { return .key("") }
        guard settlement.hasContacted(player) else {
            return StringTemplate.template("scoutSettlement.greetUncontacted")
                .addStringTemplate("%nation%", owner.nationLabel)
        }
        let skillPart = settlement.learnableSkill.map {
            StringTemplate.template("scoutSettlement.skill").addNamed("%skill%", $0)
        } ?? StringTemplate.name(" ")
        let present = settlement.wantedGoodsCount
        var goodsPart = StringTemplate.name(" ")
        if present > 0 {
            goodsPart = StringTemplate.template("scoutSettlement.trade." + String(present))
            for i in 0..<present {
                if let g = settlement.wantedGoods(i) { _ = goodsPart.addNamed("%goods\(i + 1)%", g) }
            }
        }
        return StringTemplate.template("scoutSettlement.greetings")
            .addStringTemplate("%alarmPart%", settlement.alarmLevelLabel(player))
            .addStringTemplate("%nation%", owner.nationLabel)
            .addStringTemplate("%settlement%", locationLabel(settlement, for: player))
            .addName("%number%", settlements <= 0 ? Messages.message("many") : String(settlements))
            .add("%settlementType%", (owner.nationType as? IndianNationType)?.settlementTypeKey(plural: true))
            .addStringTemplate("%skillPart%", skillPart)
            .addStringTemplate("%goodsPart%", goodsPart)
    }

    /// A missionary's question at a native settlement.
    static func missionaryQuestion(_ settlement: IndianSettlement, _ player: Player) -> StringTemplate {
        guard settlement.hasContacted(player) else {
            return .template("missionarySettlement.questionUncontacted")
        }
        let q = StringTemplate.template("missionarySettlement.question")
            .addStringTemplate("%settlement%", locationLabel(settlement, for: player))
        return StringTemplate.label("\n\n").addStringTemplate(settlement.alarmLevelLabel(player)).addStringTemplate(q)
    }

    /// Whether a missionary could establish a mission here, or denounce
    /// another's (getMissionaryChoice).
    static func missionaryOptions(_ settlement: IndianSettlement, _ player: Player) -> (establish: Bool, denounce: Bool) {
        let establish = settlement.missionary == nil
        return (establish, !establish && settlement.missionary?.owner !== player)
    }

    /// The warning before demanding tribute of natives (confirmNativeTribute).
    static func nativeTributeWarning(_ attacker: Unit, _ settlement: IndianSettlement) -> StringTemplate {
        guard let player = attacker.owner, let other = settlement.owner else { return .key("") }
        let strength = player.calculateStrength(naval: false)
        let key = other.settlementCount >= strength ? "confirmTribute.unwise"
            : other.stance(player) == .ceaseFire ? "confirmTribute.warLikely"
            : settlement.alarm(player)?.level == .happy ? "confirmTribute.happy"
            : "confirmTribute.normal"
        return StringTemplate.template(key)
            .addStringTemplate("%settlement%", locationLabel(settlement, for: player))
            .addStringTemplate("%nation%", other.nationLabel)
    }

    /// The question a scout is asked at a foreign colony.
    static func scoutColonyText(_ unit: Unit, _ colony: Colony) -> StringTemplate {
        StringTemplate.template("scoutColony.text").addStringTemplate("%unit%", unit.label(.national))
            .addName("%colony%", colony.name)
    }
}

/// Entering a settlement (the client InGameController's
/// moveScoutIndianSettlement, moveUseMissionary, moveAttackSettlement,
/// moveTribute and moveScoutColony).
extension PlayController {

    private func settlement(_ unitId: String, _ direction: Direction) -> Settlement? {
        unit(unitId)?.tile?.neighbour(direction)?.settlement
    }

    private func choose(_ id: String, _ unitId: String, _ text: StringTemplate, _ choices: [(String, String)])
        -> String? {
        ask(PlayQuestion(id: id, text: Messages.message(text) ?? "",
                         choices: choices.map { PlayChoice(id: $0.0, label: Messages.message($0.1)) }
                             + [PlayChoice(id: "cancel", label: Messages.message("cancel"))],
                         unitId: unitId))
    }

    /// A scout at a native settlement: speak with the chief, demand
    /// tribute or attack.
    func moveScoutIndianSettlement(_ unitId: String, _ direction: Direction) -> Bool {
        guard clearGotoOrders(unitId) else { return false }
        if answers["scout:\(unitId)"] == nil
            && !command(.scoutIndianSettlement(unit: unitId, direction: direction.javaName)) { return false }
        guard let is_ = settlement(unitId, direction) as? IndianSettlement, let ownerId = is_.owner?.id else {
            return false
        }
        // The owner's settlements, as the server's summary counts them.
        let count = (game.getFreeColGameObject(ownerId) as? Player)?.settlementCount ?? 0
        let text = PlayerView.scoutGreeting(is_, view.player, settlements: count)
        switch choose("scout:\(unitId)", unitId, text, [("speak", "scoutSettlement.speak"),
                                                       ("tribute", "scoutSettlement.tribute"),
                                                       ("attack", "scoutSettlement.attack")]) {
        case "attack":
            if let tile = is_.tile, confirmPreCombat(unitId, tile) {
                _ = command(.attack(unit: unitId, direction: direction.javaName))
            }
        case "speak":
            _ = command(.scoutSpeakToChief(unit: unitId, settlement: is_.id))
        case "tribute":
            return moveTribute(unitId, direction)
        default:
            break
        }
        return false
    }

    /// A missionary at a native settlement: establish a mission,
    /// denounce another's, or incite the natives against an enemy.
    func moveUseMissionary(_ unitId: String, _ direction: Direction) -> Bool {
        guard clearGotoOrders(unitId), let is_ = settlement(unitId, direction) as? IndianSettlement else { return false }
        let player = view.player
        let (establish, denounce) = PlayerView.missionaryOptions(is_, player)
        var choices: [(String, String)] = []
        if establish { choices.append(("establish", "missionarySettlement.establish")) }
        if denounce { choices.append(("denounce", "missionarySettlement.heresy")) }
        choices.append(("incite", "missionarySettlement.incite"))
        switch choose("missionary:\(unitId)", unitId, PlayerView.missionaryQuestion(is_, player), choices) {
        case "establish", "denounce":
            _ = command(.missionary(unit: unitId, direction: direction.javaName,
                                    denounce: String(answers["missionary:\(unitId)"] == "denounce")))
        case "incite":
            let enemies = view.game.livePlayers.filter { $0.isEuropean && $0 !== player }
            let options = enemies.compactMap { p in p.id.map { ($0, Messages.message(p.countryLabel) ?? "") } }
            let q = PlayQuestion(id: "inciteEnemy:\(unitId)",
                                 text: Messages.message("missionarySettlement.inciteQuestion"),
                                 choices: options.map { PlayChoice(id: $0.0, label: $0.1) }
                                     + [PlayChoice(id: "cancel", label: Messages.message("missionarySettlement.cancel"))],
                                 unitId: unitId)
            if let enemy = ask(q), enemy != "cancel" {
                // The server answers with the price, which is asked of the
                // player in turn (inciteHandler).
                _ = command(.incite(unit: unitId, settlement: is_.id, enemy: enemy, gold: "-1"))
            }
        default:
            break
        }
        return false
    }

    /// An armed unit at another's settlement: demand tribute or attack
    /// (moveAttackSettlement).
    func moveAttackSettlement(_ unitId: String, _ direction: Direction) -> Bool {
        guard let s = settlement(unitId, direction), let tile = s.tile, !view.player.owns(s) else { return false }
        let text = (s as? IndianSettlement)?.alarmLevelLabel(view.player)
            ?? (s as? Colony)?.alarmLevelLabel(view.player) ?? .key("")
        switch choose("settlement:\(unitId)", unitId, text, [("tribute", "armedUnitSettlement.tribute"),
                                                            ("attack", "armedUnitSettlement.attack")]) {
        case "attack":
            if confirmHostileAction(unitId, tile), confirmPreCombat(unitId, tile) {
                _ = command(.attack(unit: unitId, direction: direction.javaName))
            }
        case "tribute":
            return moveTribute(unitId, direction)
        default:
            break
        }
        return false
    }

    /// Demand tribute (moveTribute): of natives, after the warning; of
    /// Europeans, by negotiation.
    func moveTribute(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let s = settlement(unitId, direction) else { return false }
        if let is_ = s as? IndianSettlement {
            if confirm("tribute:\(unitId)", unitId, PlayerView.nativeTributeWarning(u, is_),
                       "confirmTribute.yes", "confirmTribute.no") {
                _ = command(.demandTribute(unit: unitId, direction: direction.javaName))
            }
        } else {
            // Tribute from Europeans is negotiated, which comes with
            // diplomacy.
            notices.append(Messages.message("model.option.notYetAvailable"))
        }
        return false
    }

    /// A scout at a foreign colony: negotiate, spy or attack
    /// (moveScoutColony).  Negotiating and spying come with diplomacy.
    func moveScoutColony(_ unitId: String, _ direction: Direction) -> Bool {
        guard let u = unit(unitId), let colony = settlement(unitId, direction) as? Colony,
              clearGotoOrders(unitId) else { return false }
        switch choose("scoutColony:\(unitId)", unitId, PlayerView.scoutColonyText(u, colony),
                      [("negotiate", "scoutColony.negotiate"), ("spy", "scoutColony.spy"),
                       ("attack", "scoutColony.attack")]) {
        case "attack":
            return moveAttackSettlement(unitId, direction)
        case "negotiate", "spy":
            notices.append(Messages.message("model.option.notYetAvailable"))
        default:
            break
        }
        return true
    }
}

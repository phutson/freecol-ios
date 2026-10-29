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

/// Negotiating with other Europeans, answering first contacts and the
/// monarch, and declaring independence: checked as the messages'
/// serverHandler checks them, then carried out as InGameController does.
extension InGameController {

    func performDiplomacy(_ command: PlayerCommand, by player: Player) throws -> ChangeSet? {
        switch command {
        case let .diplomacy(ourId, otherId, agreementElement):
            guard let agreementElement else { throw CommandRefused("Null diplomatic agreement") }
            let agreement = try DiplomaticTrade(game: game, reader(agreementElement))
            return try diplomacy(player, ourId, otherId, agreement)

        case let .firstContact(playerId, otherId, tileId, result):
            guard let first = game.getFreeColGameObject(playerId) as? Player else {
                throw CommandRefused("Invalid player: \(playerId ?? "null")")
            }
            if first !== player { throw CommandRefused("Not our player: \(playerId ?? "null")") }
            guard let other = game.getFreeColGameObject(otherId) as? Player else {
                throw CommandRefused("Invalid other player: \(otherId ?? "null")")
            }
            if other === player { throw CommandRefused("First contact with self!?!") }
            let tile = game.getFreeColGameObject(tileId) as? Tile
            return try nativeFirstContact(player, other, tile, result == "true")

        case let .monarchAction(actionName, result):
            let action = actionName.flatMap { Monarch.MonarchAction(javaName: $0) }
            guard let session = game.sessions.lookup(Session.makeKey("MonarchSession", player.id ?? "", ""))
                    as? MonarchSession else {
                throw CommandRefused("Bogus monarch action: \(action.map { "\($0)" } ?? "null")")
            }
            if action != session.action {
                throw CommandRefused("Session action mismatch, \(session.action) expected: "
                                     + (action.map { "\($0)" } ?? "null"))
            }
            let cs = ChangeSet()
            try session.complete(result == "true", cs)
            return cs

        case let .declareIndependence(nationName, countryName):
            guard let nationName, !nationName.isEmpty else { throw CommandRefused("Empty nation name.") }
            guard let countryName, !countryName.isEmpty else { throw CommandRefused("Empty country name.") }
            if player.checkDeclareIndependence() != nil { throw CommandRefused("Declaration blocked") }
            return try declareIndependence(player, nationName, countryName)

        case let .spySettlement(unitId, settlementId):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.hasAbility(Ability.spyOnColony) {
                throw CommandRefused("Unit lacks ability to spy on colony: \(unitId ?? "null")")
            }
            guard let colony = game.getFreeColGameObject(settlementId) as? Colony, let tile = colony.tile else {
                throw CommandRefused("Not a colony: \(settlementId ?? "null")")
            }
            if !(unit.tile?.isAdjacent(tile) ?? false) {
                throw CommandRefused("Unit \(unitId ?? "null") not adjacent to colony: \(settlementId ?? "null")")
            }
            let type = unit.moveType(tile)
            if type != .enterForeignColonyWithScout {
                throw CommandRefused("Unable to enter at: \(colony.name ?? ""): \(type.whyIllegal)")
            }
            // What the spy sees (spySettlement).
            let cs = ChangeSet().addSpy(unit, colony)
            unit.movesLeft = 0
            cs.addPartial(.only(player), unit, ("movesLeft", String(unit.movesLeft)))
            return cs

        default:
            preconditionFailure("Not a diplomacy command: \(command)")
        }
    }

    /// Check the two sides of a negotiation, then go on by its context
    /// (DiplomacyMessage.serverHandler).
    private func diplomacy(_ player: Player, _ ourId: String?, _ otherId: String?,
                           _ agreement: DiplomaticTrade) throws -> ChangeSet {
        var ourUnit: Unit?, ourColony: Colony?
        guard let our = game.getFreeColGameObject(ourId) else {
            throw CommandRefused("Missing our object: \(ourId ?? "null")")
        }
        if let u = our as? Unit {
            if !player.owns(u) { throw CommandRefused("Not our unit: \(ourId ?? "null")") }
            if !u.hasTile { throw CommandRefused("Our unit is not on the map: \(ourId ?? "null")") }
            ourUnit = u
        } else if let c = our as? Colony {
            if !player.owns(c) { throw CommandRefused("Not our settlement: \(ourId ?? "null")") }
            ourColony = c
        } else {
            throw CommandRefused("Our object is bogus: \(our)")
        }

        var otherUnit: Unit?, otherColony: Colony?, otherPlayer: Player?
        guard let other = game.getFreeColGameObject(otherId) else {
            throw CommandRefused("Missing other object: \(otherId ?? "null")")
        }
        if let u = other as? Unit {
            if player.owns(u) { throw CommandRefused("Contacting our unit? \(otherId ?? "null")") }
            guard let ut = u.tile else { throw CommandRefused("Other unit is not on the map: \(otherId ?? "null")") }
            if let ourUnit, !(ourUnit.tile?.isAdjacent(ut) ?? false) {
                throw CommandRefused("Our unit \(ourId ?? "null") is not adjacent to other unit \(otherId ?? "null")")
            }
            if let ourColony, !(ourColony.tile?.isAdjacent(ut) ?? false) {
                throw CommandRefused("Our colony \(ourId ?? "null") is not adjacent to other unit \(otherId ?? "null")")
            }
            otherUnit = u
            otherPlayer = u.owner
        } else if let c = other as? Colony {
            if player.owns(c) { throw CommandRefused("Contacting our colony? \(otherId ?? "null")") }
            if let ourUnit, let ct = c.tile, !(ourUnit.tile?.isAdjacent(ct) ?? false) {
                throw CommandRefused("Our unit \(ourId ?? "null") is not adjacent to other colony \(otherId ?? "null")")
            }
            if let ourColony, let ct = c.tile, !(ourColony.tile?.isAdjacent(ct) ?? false) {
                throw CommandRefused("Our colony \(ourId ?? "null") is not adjacent to other colony "
                                     + (otherId ?? "null"))
            }
            otherColony = c
            otherPlayer = c.owner
        } else {
            throw CommandRefused("Other object is bogus: \(other)")
        }
        if ourUnit == nil && otherUnit == nil { throw CommandRefused("Both units null") }

        guard let sender = agreement.sender else { throw CommandRefused("Null sender in agreement.") }
        guard let recipient = agreement.recipient else { throw CommandRefused("Null recipient in agreement.") }
        if sender.isREF || recipient.isREF { throw CommandRefused("The REF does not negotiate") }

        switch agreement.context {
        case .contact:
            return try europeanFirstContact(player, ourUnit, ourColony, otherUnit, otherColony, agreement)
        case .diplomatic:
            if let ourUnit {
                if !ourUnit.hasAbility(Ability.negotiate) {
                    throw CommandRefused("Unit lacks ability to negotiate: \(ourUnit)")
                }
                guard let otherColony else { throw CommandRefused("Null other settlement") }
                return try diplomacy(player, ourUnit, otherColony, agreement)
            }
            if !otherUnit!.hasAbility(Ability.negotiate) {
                throw CommandRefused("Unit lacks ability to negotiate: \(otherUnit!)")
            }
            return try diplomacy(player, ourColony!, otherUnit!, agreement)
        case .trade:
            if let ourUnit {
                if !ourUnit.isCarrier { throw CommandRefused("Unit is not a carrier: \(ourUnit)") }
                if !player.hasAbility(Ability.tradeWithForeignColonies) {
                    throw CommandRefused("Player lacks ability to trade with other Europeans: \(player)")
                }
                guard let otherColony else { throw CommandRefused("Null other settlement") }
                return try diplomacy(player, ourUnit, otherColony, agreement)
            }
            if !otherUnit!.isCarrier { throw CommandRefused("Unit is not a carrier: \(otherUnit!)") }
            if !(otherPlayer?.hasAbility(Ability.tradeWithForeignColonies) ?? false) {
                throw CommandRefused("Player lacks ability to trade with other Europeans: \(otherPlayer!)")
            }
            return try diplomacy(player, ourColony!, otherUnit!, agreement)
        case .tribute:
            if let ourUnit {
                if !ourUnit.isOffensiveUnit || ourUnit.isNaval {
                    throw CommandRefused("Unit is not an offensive land unit: \(ourUnit)")
                }
                guard let otherColony else { throw CommandRefused("Null other settlement") }
                return try diplomacy(player, ourUnit, otherColony, agreement)
            }
            if !otherUnit!.isOffensiveUnit || otherUnit!.isNaval {
                throw CommandRefused("Unit is not an offensive land unit: \(otherUnit!)")
            }
            return try diplomacy(player, ourColony!, otherUnit!, agreement)
        case nil:
            throw CommandRefused("Invalid diplomacy for null")
        }
    }

    /// A unit's negotiation with another's colony, started by a proposal
    /// (diplomacy).
    private func diplomacy(_ player: Player, _ ourUnit: Unit, _ otherColony: Colony,
                           _ agreement: DiplomaticTrade) throws -> ChangeSet {
        var session = game.sessions.lookup(DiplomacySession.key(ourUnit, otherColony)) as? DiplomacySession
        if session == nil {
            if agreement.status != .proposeTrade {
                throw CommandRefused("Missing uc-diplomacy session for \(ourUnit.id ?? "null")/"
                                     + "\(otherColony.id ?? "null") with \(agreement)")
            }
            session = DiplomacySession.register(ourUnit, settlement: otherColony, otherUnit: nil, in: game.sessions)
        }
        let cs = ChangeSet()
        try player.csDiplomacy(session!, agreement, cs)
        try sendToOthers(player, cs)
        return cs
    }

    /// A colony's answer to another's unit (diplomacy).
    private func diplomacy(_ player: Player, _ ourColony: Colony, _ otherUnit: Unit,
                           _ agreement: DiplomaticTrade) throws -> ChangeSet {
        guard let session = game.sessions.lookup(DiplomacySession.key(otherUnit, ourColony)) as? DiplomacySession
        else {
            throw CommandRefused("Missing cu-diplomacy session for \(otherUnit.id ?? "null")/"
                                 + "\(ourColony.id ?? "null") with \(agreement)")
        }
        let cs = ChangeSet()
        try player.csDiplomacy(session, agreement, cs)
        try sendToOthers(player, cs)
        return cs
    }

    /// An answer to a first contact between Europeans
    /// (europeanFirstContact).
    private func europeanFirstContact(_ player: Player, _ ourUnit: Unit?, _ ourColony: Colony?, _ otherUnit: Unit?,
                                      _ otherColony: Colony?, _ agreement: DiplomaticTrade) throws -> ChangeSet {
        let err = "Missing contact diplomacy session for "
        let ds: DiplomacySession
        let compatible: Bool
        if let ourColony {
            guard let s = DiplomacySession.findContactSession(otherUnit?.owner, ourColony.owner, in: game.sessions)
            else { throw CommandRefused(err + "\(ourColony.id ?? "null") and \(otherUnit?.id ?? "null")") }
            ds = s
            compatible = ds.isCompatible(ourColony, otherUnit)
        } else if let otherUnit {
            guard let s = DiplomacySession.findContactSession(ourUnit?.owner, otherUnit.owner, in: game.sessions)
            else { throw CommandRefused(err + "\(ourUnit?.id ?? "null") and \(otherUnit.id ?? "null")") }
            ds = s
            compatible = ds.isCompatible(ourUnit, otherUnit)
        } else {
            guard let s = DiplomacySession.findContactSession(ourUnit?.owner, otherColony?.owner, in: game.sessions)
            else { throw CommandRefused(err + "\(ourUnit?.id ?? "null") and \(otherColony?.id ?? "null")") }
            ds = s
            compatible = ds.isCompatible(ourUnit, otherColony)
        }
        let cs = ChangeSet()
        if compatible {
            try player.csDiplomacy(ds, agreement, cs)
            try sendToOthers(player, cs)
        }
        return cs
    }

    /// The answer to meeting natives: accepting the land they offered,
    /// or refusing peace, which insults them (nativeFirstContact).
    private func nativeFirstContact(_ player: Player, _ other: Player, _ tile: Tile?,
                                    _ result: Bool) throws -> ChangeSet {
        let cs = ChangeSet()
        var session: DiplomacySession?
        if let tile, let u = tile.firstUnit, let s = tile.owningSettlement {
            session = DiplomacySession.findContactSession(u.owner, s.owner, in: game.sessions)
        }
        if result {
            if let tile {
                if session == nil { throw CommandRefused("No diplomacy for: \(tile.id ?? "null")") }
                try tile.cacheUnseen()
                tile.changeOwnership(player, nil)
                cs.add(.perhaps(), tile)
            }
        } else {
            try other.csModifyTension(player, Tension.tensionAddMajor, nil, cs)
            other.addMissionBan(player)
        }
        if let session { try session.completeFirstContact(cs) }
        try sendToOthers(player, cs)
        return cs
    }
}

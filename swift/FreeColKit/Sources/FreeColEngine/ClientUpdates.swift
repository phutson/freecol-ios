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
import FreeColXML

/// Keeping the player's copy of the game up to date as Java's client
/// does, from what the server sends it after each command (the client
/// handlers of UpdateMessage, PartialMessage, RemoveMessage and the
/// rest), rather than reading the whole game again, which takes a
/// noticeable time on a big map.  What is not handled here says so, and
/// the copy is then read again in full.
extension PlayerView {

    struct Unhandled: Error, CustomStringConvertible {
        let description: String
    }

    /// Apply what the server told the player.
    ///
    /// - Throws: Unhandled for a message this does not handle, or a
    ///   reading error; the copy must then be read again.
    func apply(_ update: PlayerUpdate, sentTo serverPlayer: Player) throws {
        let xw = FreeColXMLWriter(scope: .toClient(serverPlayer))
        update.toXML(xw)
        let xr = try FreeColXMLReader(string: xw.xml)
        try xr.nextTag()
        try applyMessage(xr)
        placeholders += xr.retainedObjects
        // The client's view may have changed (updateHandler).
        player.invalidateCanSeeTiles()
    }

    /// Read the player itself again, as the server has it now: its own
    /// fields change without a message saying so (its tension towards
    /// others, for one), and they are few to read.
    func rereadPlayer(_ serverPlayer: Player) throws {
        let xr = try FreeColXMLReader(string: serverPlayer.serialize(.toClient(serverPlayer)))
        try xr.nextTag()
        guard try xr.readFreeColObject(game, Player.self) === player else {
            throw Unhandled(description: "player read again")
        }
        placeholders += xr.retainedObjects
        player.invalidateCanSeeTiles()
    }

    /// Messages that change nothing in the copy: questions and notices,
    /// whose answers come back as commands.
    private static let notices: Set<String> = ["newLandName", "newRegionName", "firstContact"]

    private func applyMessage(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        switch tag {
        case "multiple":
            // Its own attributes are settings for the interface (sound).
            while try xr.moreTags() { try applyMessage(xr) }
        case "update", "addPlayer":
            // Objects as the player sees them, read into its copies.
            while try xr.moreTags() { try readObject(xr) }
            if tag == "addPlayer" { throw Unhandled(description: "addPlayer") }
        case "animateMove", "animateAttack":
            // Units appearing from out of sight, which Java reads as
            // copies for the animation alone, not into the game.
            try xr.swallowTag(tag)
        case "partial":
            try partial(xr.allAttributes)
            try xr.closeTag(tag)
        case "remove":
            try remove(xr.allAttributes)
            try xr.closeTag(tag)
        case "featureChange":
            try featureChange(xr)
        case "setStance":
            let attributes = xr.allAttributes
            guard let first = game.getFreeColGameObject(attributes["first"], as: Player.self),
                  let second = game.getFreeColGameObject(attributes["second"], as: Player.self),
                  let stance = Player.Stance.allCases.first(where: { $0.javaName == attributes["stance"] }) else {
                throw Unhandled(description: "setStance \(attributes)")
            }
            _ = first.setStance(second, stance)
            try xr.closeTag(tag)
        default:
            guard Self.notices.contains(tag) else { throw Unhandled(description: tag) }
            try xr.swallowTag(tag)
        }
    }

    /// Read an object into the copy: into the object of the same
    /// identifier, as the reader does, or a new one.
    private func readObject(_ xr: FreeColXMLReader) throws {
        let read: FreeColGameObject?
        switch xr.localName {
        case Unit.tag: read = try xr.readFreeColObject(game, Unit.self)
        case Tile.tag: read = try xr.readFreeColObject(game, Tile.self)
        case Colony.tag: read = try xr.readFreeColObject(game, Colony.self)
        case IndianSettlement.tag: read = try xr.readFreeColObject(game, IndianSettlement.self)
        case Player.tag: read = try xr.readFreeColObject(game, Player.self)
        case Europe.tag: read = try xr.readFreeColObject(game, Europe.self)
        case HighSeas.tag: read = try xr.readFreeColObject(game, HighSeas.self)
        default: throw Unhandled(description: "update of \(xr.localName)")
        }
        if read == nil { throw Unhandled(description: "unread \(xr.localName)") }
    }

    /// New values for some fields (partialHandler), those the server
    /// sends.
    private func partial(_ attributes: [String: String]) throws {
        guard let object = game.getFreeColGameObject(attributes["id"]) else {
            throw Unhandled(description: "partial of a missing object")
        }
        for (key, value) in attributes where key != "id" {
            switch (object, key) {
            case let (p as Player, "gold"): p.gold = Int(value) ?? p.gold
            case let (p as Player, "score"): p.score = Int(value) ?? p.score
            case let (p as Player, "name"): p.name = value
            case let (p as Player, "newLandName"): p.newLandName = value
            case let (p as Player, "dead"): p.isDead = value == "true"
            case let (p as Player, "bankrupt"): p.bankrupt = value == "true"
            case let (p as Player, "attackedByPrivateers"): p.attackedByPrivateers = value == "true"
            case let (u as Unit, "movesLeft"): u.movesLeft = Int(value) ?? u.movesLeft
            case let (u as Unit, "hitPoints"): u.hitPoints = Int(value) ?? u.hitPoints
            case let (u as Unit, "experience"): u.experience = Int(value) ?? u.experience
            case let (u as Unit, "name"): u.name = value
            case let (g as Game, "spanishSuccession"): g.spanishSuccession = value == "true"
            default: throw Unhandled(description: "partial \(key) of \(type(of: object))")
            }
        }
        if (object as? Player) === player || ((object as? Ownable)?.owner === player) {
            player.invalidateCanSeeTiles()
        }
    }

    /// Objects gone from the player's sight or the game (removeHandler).
    private func remove(_ attributes: [String: String]) throws {
        let count = Int(attributes["xLength"] ?? "") ?? 0
        let divert = game.getFreeColGameObject(attributes["divert"])
        for i in 0..<count {
            guard let object = game.getFreeColGameObject(attributes["x\(i)"]) else { continue }
            if let divert { player.divertModelMessages(object, divert) }
            if let settlement = object as? Settlement {
                _ = settlement.owner?.removeSettlement(settlement)
            } else if let unit = object as? Unit {
                _ = unit.owner?.removeUnit(unit)
            }
            object.disposeResources()
        }
    }

    /// Features, history, sales and messages added or removed
    /// (featureChangeHandler).
    private func featureChange(_ xr: FreeColXMLReader) throws {
        let attributes = xr.allAttributes
        guard let parent = game.getFreeColGameObject(attributes["id"]) else {
            throw Unhandled(description: "featureChange of a missing object")
        }
        let add = attributes["add"] == "true"
        let spec = game.specification
        while try xr.moreTags() {
            switch (xr.localName, parent) {
            case (Ability.tag, _):
                let ability = try Ability(xr, specification: spec)
                if add { _ = parent.addAbility(ability) } else { _ = parent.removeAbility(ability) }
            case (Modifier.tag, _):
                let modifier = try Modifier(xr, specification: spec)
                if add { _ = parent.addModifier(modifier) } else { _ = parent.removeModifier(modifier) }
            case let (HistoryEvent.historyEventTag, p as Player) where add:
                p.addHistory(try HistoryEvent(reading: xr))
            case let (LastSale.tag, p as Player) where add:
                p.addLastSale(try LastSale(xr))
            case let (ModelMessage.modelMessageTag, p as Player) where add:
                p.addModelMessage(try ModelMessage(reading: xr))
            default:
                throw Unhandled(description: "featureChange \(xr.localName)")
            }
        }
    }
}

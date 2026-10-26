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
import FreeColXML

/// Whose turn it is now (SetCurrentPlayerMessage).
public final class SetCurrentPlayerMessage: ServerMessage {
    public unowned let player: Player

    public init(_ player: Player) {
        self.player = player
    }

    public var tag: String { "setCurrentPlayer" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("player", player.id ?? "")] }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// A player has died (SetDeadMessage).
public final class SetDeadMessage: ServerMessage {
    public unowned let player: Player

    public init(_ player: Player) {
        self.player = player
    }

    public var tag: String { "setDead" }
    public var priority: MessagePriority { .early }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("player", player.id ?? "")] }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// The game is over (GameEndedMessage).
public final class GameEndedMessage: ServerMessage {
    public unowned let winner: Player
    public let highScore: Bool

    public init(_ winner: Player, _ highScore: Bool) {
        self.winner = winner
        self.highScore = highScore
    }

    public var tag: String { "gameEnded" }
    public var priority: MessagePriority { .normal }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        [("winner", winner.id ?? ""), ("highScore", highScore ? "true" : "false")]
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// The founding fathers to choose one from, one of each type, and the
/// one chosen (ChooseFoundingFatherMessage).
public final class ChooseFoundingFatherMessage: ServerMessage {
    public let fathers: [FoundingFather]
    public let chosen: FoundingFather?

    public init(_ fathers: [FoundingFather], _ chosen: FoundingFather?) {
        self.fathers = fathers
        self.chosen = chosen
    }

    public var tag: String { "chooseFoundingFather" }
    public var priority: MessagePriority { .early }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        var ret = fathers.compactMap { f in f.type.map { ($0.key, f.id ?? "") } }
        if let chosen { ret.append(("foundingFather", chosen.id ?? "")) }
        return ret
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// The monarch acts, with a message to show (MonarchActionMessage).
public final class MonarchActionMessage: ServerMessage {
    public let action: Monarch.MonarchAction
    public let template: StringTemplate
    /// The nation whose monarch acts, or a mercenary leader's number.
    public let monarchKey: String
    public var tax: Int?

    public init(_ action: Monarch.MonarchAction, _ template: StringTemplate, _ monarchKey: String) {
        self.action = action
        self.template = template
        self.monarchKey = monarchKey
    }

    public func setTax(_ tax: Int) -> MonarchActionMessage {
        self.tax = tax
        return self
    }

    public var tag: String { "monarchAction" }
    public var priority: MessagePriority {
        switch action {
        case .raiseTaxAct, .raiseTaxWar, .monarchMercenaries, .hessianMercenaries: .early
        case .noAction, .forceTax, .waiveTax, .displeasure: .normal
        case .lowerTaxOther, .lowerTaxWar, .addToREF, .declarePeace, .declareWar, .supportLand, .supportSea: .late
        }
    }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        var ret = [("action", action.javaName), ("monarch", monarchKey)]
        if let tax { ret.append(("tax", String(tax))) }
        return ret
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {
        template.toXML(xw)
    }
}

extension Monarch.MonarchAction {
    /// The message key of the action's text (getTextKey).
    public var textKey: String {
        "model.monarch.action." + Messages.enumKey(javaName) + ".text"
    }
}

extension FoundingFather.FoundingFatherType {
    /// The type's key (getKey).
    public var key: String {
        Messages.enumKey(javaName)
    }
}

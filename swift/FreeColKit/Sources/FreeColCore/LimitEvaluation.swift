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

import FreeColUtil

/// Evaluating limits against a game, player or settlement (the rest of
/// common/model/Limit and Operand).
///
/// Java finds an operand's named method by reflection; here objects
/// answer through scopeMethodValue, and the rules only name getSoL (a
/// player's) and isConnectedPort (a settlement's).
extension Operand {

    private func ourCount<S: Sequence>(_ objects: S) -> Int where S.Element: FreeColObject {
        objects.filter { appliesTo($0) }.count
    }

    /// The value in a game, or nil if the operand does not count there.
    public func value(in game: Game) -> Int? {
        if let value { return value }
        guard scopeLevel == .game else { return nil }
        switch operandType {
        case .none:
            // Java's default for a missing method is 0.
            return methodName.flatMap(game.scopeMethodValue).flatMap(JavaString.parseInt).map(Int.init) ?? 0
        case .year:
            return game.specification.map { $0.turnCalendar.year(of: game.turn) } ?? 0
        case .option:
            return type.flatMap { game.specification?.getInteger($0) }
        case .units, .buildings, .settlements, .foundingFathers:
            var result = 0
            for player in game.livePlayers {
                switch operandType {
                case .units: result += ourCount(player.units)
                case .buildings: result += player.colonyList.reduce(0) { $0 + ourCount($1.buildings) }
                case .settlements: result += ourCount(player.settlements)
                default: result += ourCount(player.foundingFathers)
                }
            }
            return result
        }
    }

    /// The value for a player, or nil if the operand does not count
    /// there.
    public func value(for player: Player) -> Int? {
        if let value { return value }
        switch scopeLevel {
        case .game: return player.game.flatMap(value(in:))
        case .player: break
        default: return nil
        }
        switch operandType {
        case .units:
            return ourCount(player.units)
        case .buildings:
            return player.colonyList.reduce(0) { $0 + ourCount($1.buildings) }
        case .settlements:
            guard let methodName else {
                return ourCount(player.settlements)
                    + (player.specification?.getInteger(GameOptions.settlementLimitModifier) ?? 0)
            }
            return player.settlements.filter {
                ($0.scopeMethodValue(methodName) ?? "false") == (methodValue ?? "null")
            }.count
        case .foundingFathers:
            return ourCount(player.foundingFathers)
        default:
            return methodName.flatMap(player.scopeMethodValue).flatMap(JavaString.parseInt).map(Int.init)
        }
    }

    /// The value in a settlement (only colonies count), or nil.
    public func value(in settlement: Settlement) -> Int? {
        if let value { return value }
        guard scopeLevel == .settlement, let colony = settlement as? Colony else { return nil }
        switch operandType {
        case .units: return ourCount(colony.unitList)
        case .buildings: return ourCount(colony.buildings)
        default:
            return methodName.flatMap(colony.scopeMethodValue).flatMap(JavaString.parseInt).map(Int.init)
        }
    }
}

extension Limit {

    public func evaluate(_ game: Game) -> Bool {
        let lhs = leftHandSide.scopeLevel == .game ? leftHandSide.value(in: game) : leftHandSide.value
        let rhs = rightHandSide.scopeLevel == .game ? rightHandSide.value(in: game) : rightHandSide.value
        return evaluate(lhs, rhs)
    }

    public func evaluate(_ player: Player) -> Bool {
        func value(_ o: Operand) -> Int? {
            switch o.scopeLevel {
            case .player: return o.value(for: player)
            case .game: return player.game.flatMap(o.value(in:))
            default: return o.value
            }
        }
        return evaluate(value(leftHandSide), value(rightHandSide))
    }

    public func evaluate(_ settlement: Settlement) -> Bool {
        func value(_ o: Operand) -> Int? {
            switch o.scopeLevel {
            case .settlement: return o.value(in: settlement)
            case .player: return settlement.owner.flatMap(o.value(for:))
            case .game: return settlement.game.flatMap(o.value(in:))
            default: return o.value
            }
        }
        return evaluate(value(leftHandSide), value(rightHandSide))
    }
}

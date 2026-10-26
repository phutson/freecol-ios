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

/// A game turn (common/model/Turn), counted from 1.
///
/// A value type: Java's Turn is an immutable object compared by number.
/// The year and season of a turn depend on the game's calendar, which
/// Java keeps in static fields set at game start; here it is a
/// `TurnCalendar` passed explicitly.  The label is in Labels.swift.
/// Not yet ported: save-game suffixes.
public struct Turn: Hashable, Sendable, CustomStringConvertible {

    /// The turn number.
    public let number: Int

    public init(_ number: Int) {
        self.number = number
    }

    /// The following turn.
    public func next() -> Turn {
        Turn(number + 1)
    }

    /// Whether this is the first turn of the game.
    public var isFirstTurn: Bool {
        number == 1
    }

    public var description: String {
        String(number)
    }
}

/// When turns start being split into seasons (Java's static Turn
/// settings, normally initialized from the game options).
public struct TurnCalendar: Hashable, Sendable {

    /// The year of the first turn.
    public var startingYear: Int
    /// The first year with more than one turn.
    public var seasonYear: Int
    /// How many turns each year has from the season year on.
    public var seasonNumber: Int

    /// Java's defaults: 1492, seasons from 1600, two a year.
    public static let standard = TurnCalendar(startingYear: 1492, seasonYear: 1600,
                                              seasonNumber: 2)

    public init(startingYear: Int, seasonYear: Int, seasonNumber: Int) {
        self.startingYear = startingYear
        self.seasonYear = seasonYear
        self.seasonNumber = seasonNumber
    }

    /// The turn number of a year and season (Turn.yearToTurn).
    public func turnNumber(year: Int, season: Int = 0) -> Int {
        var ret = 1
        if year >= startingYear {
            ret += year - startingYear
            if year >= seasonYear {
                ret += (year - seasonYear) * (seasonNumber - 1) + season
            }
        }
        return ret
    }

    /// The year of a turn (Turn.getTurnYear).
    public func year(of turn: Turn) -> Int {
        let year = turn.number - 1 + startingYear
        return year < seasonYear ? year : seasonYear + (year - seasonYear) / seasonNumber
    }

    /// The season of a turn, or -1 before seasons start
    /// (Turn.getTurnSeason).
    public func season(of turn: Turn) -> Int {
        let year = turn.number - 1 + startingYear
        return year < seasonYear ? -1 : (year - seasonYear) % seasonNumber
    }

    /// Whether a turn is the first one with seasons
    /// (Turn.isFirstSeasonTurn).
    public func isFirstSeasonTurn(_ turn: Turn) -> Bool {
        turn.number == turnNumber(year: seasonYear)
    }
}

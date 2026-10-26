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
import Testing

/// GameTest.java.
@Suite(.serialized)
struct GameTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    @Test func game() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let dutchNation = try #require(spec.getNation("model.nation.dutch"))
        game.addPlayer(Player(game: game, nation: dutchNation))
    }

    @Test func addPlayer() {
        // Do *not* use the standard game, so the players are not made.
        let game = ServerTestGame(specification: spec)
        let defaultOptions = NationOptions(specification: spec)
        game.nationOptions = defaultOptions

        var players: [Player] = []
        var counter = 0
        for n in spec.nations {
            if defaultOptions.nationState(n) == .notAvailable {
                counter += 1
            } else {
                let p = Player(game: game, nation: n)
                p.isAI = !(n.type?.isEuropean ?? false) || (n.type?.isREF ?? false)
                game.addPlayer(p)
                players.append(p)
            }
        }

        players = players.enumerated().sorted {
            let c = Player.comparePlayers($0.element, $1.element)
            return c != 0 ? c < 0 : $0.offset < $1.offset
        }.map(\.element)
        game.sortPlayers(Player.comparePlayers)
        #expect(game.players.count == spec.nations.count - counter)
        #expect(game.players.elementsEqual(players, by: ===))
    }

    @Test func turn() {
        let calendar = TurnCalendar.standard
        #expect(calendar.startingYear == 1492)
        #expect(calendar.seasonYear == 1600)
        #expect(calendar.seasonNumber == 2)

        #expect(calendar.year(of: Turn(1)) == 1492)
        #expect(calendar.turnNumber(year: 1492) == 1)
        #expect(calendar.season(of: Turn(1)) == -1)
        #expect(spec.age(Turn(1)) == 0)

        #expect(calendar.year(of: Turn(108)) == 1599)
        #expect(calendar.turnNumber(year: 1599) == 108)
        #expect(calendar.season(of: Turn(108)) == -1)
        #expect(spec.age(Turn(108)) == 0)

        #expect(calendar.year(of: Turn(109)) == 1600)
        #expect(calendar.turnNumber(year: 1600, season: 0) == 109)
        #expect(calendar.season(of: Turn(109)) == 0)
        #expect(spec.age(Turn(109)) == 1)

        #expect(calendar.year(of: Turn(110)) == 1600)
        #expect(calendar.turnNumber(year: 1600, season: 1) == 110)
        #expect(calendar.season(of: Turn(110)) == 1)
        #expect(spec.age(Turn(308)) == 1)

        #expect(calendar.year(of: Turn(309)) == 1700)
        #expect(calendar.turnNumber(year: 1700, season: 0) == 309)
        #expect(calendar.season(of: Turn(309)) == 0)
        #expect(spec.age(Turn(309)) == 2)

        #expect(calendar.year(of: Turn(310)) == 1700)
        #expect(calendar.turnNumber(year: 1700, season: 1) == 310)
        #expect(calendar.season(of: Turn(310)) == 1)
    }
}

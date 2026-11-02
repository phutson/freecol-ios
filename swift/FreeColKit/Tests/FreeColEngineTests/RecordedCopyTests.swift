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
import FreeColCore
@testable import FreeColEngine
import FreeColIO
import FreeColServer
import FreeColTestSupport
import FreeColXML
import Testing

/// A player's copy of the game recorded and read straight back is the
/// copy written as XML text and parsed, as Java's client gets it.
@Suite struct RecordedCopyTests {

    static func textCopy(_ game: Game, _ player: Player) throws -> Game {
        let xr = try FreeColXMLReader(string: game.serialize(.toClient(player)))
        try xr.nextTag()
        let copy = Game(specification: nil)
        copy.isClientCopy = true
        try copy.readFromXML(xr)
        return copy
    }

    @Test(arguments: ["natives", "commands", "europe", "moves", "combat", "colonypanel", "diplomacy", "colonies"])
    func sameAsText(_ name: String) throws {
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let saved = try FreeColSavegameFile(url: PlayerViewTests.oracle.appendingPathComponent(
                "games/freecol-\(name)-seed1.fsg")).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            for player in game.livePlayers {
                // Some test games have units on tiles their player never
                // explored, which the server notices only once the game
                // is first written for that player: write it once first.
                _ = game.serialize(.toClient(player))
                let recorded = PlayController.withoutRules(try PlayerView(of: game, for: player).game.serialize(.toServer()))
                let text = PlayController.withoutRules(try Self.textCopy(game, player).serialize(.toServer()))
                if recorded != text {
                    Issue.record(Comment(rawValue: "\(name), \(player.id ?? ""):\n"
                                         + PlayController.firstDifference(recorded, text)))
                }
            }
        }
    }
}

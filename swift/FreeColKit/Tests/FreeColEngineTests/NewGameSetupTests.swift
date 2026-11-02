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
import Testing

/// What a player may choose before a new game, and a game started with
/// the choices.  The game itself is checked against Java in
/// MapGenTests.newGames.
@Suite struct NewGameSetupTests {

    static let data = FreeColDataDirectory(url: ReferenceDumps.repositoryRoot.appendingPathComponent("data"))

    static func options(_ g: NewGameSetup.Group) -> [NewGameSetup.Option] {
        g.options + g.groups.flatMap(options)
    }

    @Test(arguments: ["freecol", "classic"])
    func choices(_ rules: String) throws {
        let setup = try NewGameSetup.load(Self.data, rules: rules, difficulty: "model.difficulty.medium",
                                          messages: GameEngineTests.english)
        // Java's table: every nation but the unknown enemy and the REF;
        // the Europeans the player may take; four of them play.
        let playable = setup.nations.filter(\.isPlayable)
        #expect(playable.count == 8)
        #expect(playable.filter(\.playsByDefault).map(\.id)
                == ["model.nation.dutch", "model.nation.french", "model.nation.english", "model.nation.spanish"])
        #expect(setup.nations.contains { !$0.isEuropean && $0.playsByDefault })
        #expect(!setup.advantages.contains { $0.id == "model.nationType.optionOnly" || $0.id == "model.nationType.ref" })
        #expect(setup.groups.map(\.id) == ["mapGeneratorOptions", "gameOptions"])
        // Everything is named, not shown by its key.
        var unnamed: [String] = []
        for n in setup.nations where n.name.hasPrefix("model.") { unnamed.append(n.id) }
        for a in setup.advantages where a.name.hasPrefix("model.") { unnamed.append(a.id) }
        for o in setup.groups.flatMap(Self.options) {
            if o.name.hasSuffix(".name") || o.name.hasPrefix("model.") { unnamed.append(o.id) }
            if case .select(let items) = o.kind, items.contains(where: { $0.label.hasPrefix("model.") }) {
                unnamed.append(o.id + " choices")
            }
        }
        #expect(unnamed.isEmpty, Comment(rawValue: unnamed.joined(separator: ", ")))
        let rumours = try #require(setup.groups.flatMap(Self.options).first { $0.id == "model.option.rumourNumber" })
        #expect(rumours.name == "Number of lost city rumors")
        let landMass = try #require(setup.groups.flatMap(Self.options).first { $0.id == "model.option.landMass" })
        #expect(landMass.kind == .integer(minimum: 15, maximum: 75))
        if case .select(let items) = rumours.kind { #expect(items.count == 5) } else { Issue.record("not a choice") }
    }

    /// A game started with the player's choices: its nation, advantage,
    /// the nations left out, and the options.
    @Test func startWithChoices() async throws {
        let setup = try NewGameSetup.load(Self.data, rules: "freecol", difficulty: "model.difficulty.medium",
                                          messages: GameEngineTests.english)
        let rumours = try #require(setup.groups.flatMap(Self.options).first { $0.id == "model.option.rumourNumber" })
        guard case .select(let items) = rumours.kind, let fewest = items.last?.value else {
            Issue.record("rumours are not a choice")
            return
        }
        let choices = NewGameChoices(nationId: "model.nation.swedish", nationTypeId: "model.nationType.naval",
                                     nationStates: ["model.nation.english": .notAvailable,
                                                    "model.nation.apache": .notAvailable])
        let engine = try GameEngine(newGame: Self.data, options: ["model.option.fogOfWar": .boolean(false),
                                                                  "model.option.rumourNumber": .integer(fewest)],
                                    choices: choices, seed: 7, playerName: "Tester",
                                    messages: GameEngineTests.english)
        var checked = false
        _ = try await engine.serverActs { game, _, human, _ in
            #expect(human.nationId == "model.nation.swedish")
            #expect(human.nationType?.id == "model.nationType.naval")
            #expect(human.name == "Tester")
            let ids = Set(game.livePlayers.compactMap(\.nationId))
            #expect(!ids.contains("model.nation.english") && !ids.contains("model.nation.apache"))
            #expect(ids.contains("model.nation.dutch"))
            #expect(game.specification?.getBoolean("model.option.fogOfWar") == false)
            #expect(game.specification?.getInteger("model.option.rumourNumber") == fewest)
            checked = true
            return ChangeSet()
        }
        #expect(checked)
    }
}

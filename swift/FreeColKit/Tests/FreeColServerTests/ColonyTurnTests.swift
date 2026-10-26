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
import FreeColIO
import FreeColServer
import FreeColTestSupport
import FreeColUtil
import FreeColXML
import Testing

/// The colonies' new turns, compared with Java's (ColonyTurnOracle.java)
/// round by round: the game as saved, what each player is told, and
/// the random number generator.
///
/// The game (ColonyTurnGameMaker.java) has colonies about to build a
/// building, upgrade one and build a unit, a colonist about to be born,
/// a student, exports through a custom house, a resource about to run
/// out, an elder statesman, an empty build queue, a damaged ship in a
/// drydock, and colonies that starve.
@Suite(.serialized)
struct ColonyTurnTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()

    /// The US English messages, which Java's oracle loads, as the
    /// custom house's message includes translated text.  They are used
    /// for this test's task only, as other tests change the global ones.
    nonisolated(unsafe) static let english: MessageBundle = {
        let data = ReferenceDumps.repositoryRoot.appendingPathComponent("data")
        let strings = data.appendingPathComponent("strings")
        let numberRules = try! NumberRules(data: Data(contentsOf: strings.appendingPathComponent("plurals.xml")))
        return MessageBundle.load(directory: strings, languageId: "en_US", numberRules: numberRules,
                                  rulesDirectories: ["classic", "freecol"].map {
                                      data.appendingPathComponent("rules/" + $0)
                                  })
    }()

    /// One round, as ColonyTurnOracle runs it: each live player's
    /// colonies' new turns, then each European player's colonies'
    /// warnings.
    static func round(_ game: Game, _ random: JavaRandom) throws -> ChangeSet {
        let cs = ChangeSet()
        for p in game.livePlayers {
            for case let colony as Colony in p.settlements {
                try colony.csNewTurn(random, cs)
            }
        }
        for p in game.livePlayers where p.isEuropean {
            for colony in p.colonyList { colony.csNewTurnWarnings(random, cs) }
        }
        return cs
    }

    static func saveTree(_ game: Game) throws -> JSONValue {
        var tree = try XmlTree.parse(game.serialize(.toSave()))
        XmlTree.removeChild(&tree, Specification.tag)
        XmlTree.maskAttribute(&tree, "UUID", "MASKED")
        return tree
    }

    static func tree(_ update: PlayerUpdate?) throws -> JSONValue {
        guard let update else { return .null }
        let xw = FreeColXMLWriter(scope: .toSave())
        update.toXML(xw)
        return try XmlTree.parse(xw.xml)
    }

    @Test func roundsMatchJava() throws {
        try Messages.$scopedBundle.withValue(Self.english) { try checkRounds() }
    }

    func checkRounds() throws {
        let archive = try ZipArchive(contentsOf: Self.oracleDirectory.appendingPathComponent("colony-turns.zip"))
        let java = try JSONValue.parse(try #require(try archive.contents(of: "colony-turns.json")))
        let rounds = try #require(java["rounds"]?.arrayValue)
        let url = Self.oracleDirectory.appendingPathComponent("games/freecol-colonyturn-seed1.fsg")
        let game = try FreeColSavegameFile(url: url).readServerGame().game
        let random = JavaRandom(seed: try #require(java["seed"]?.intValue))

        for (i, expected) in rounds.enumerated() {
            let cs = try Self.round(game, random)
            var diffs: [String] = []
            for p in game.livePlayers {
                let key = p.nationId ?? "null"
                let swift = try Self.tree(cs.build(p))
                let javaTree = expected["told"]?[key] ?? .null
                if swift == .null || javaTree == .null {
                    if swift != javaTree {
                        diffs.append("told \(key): Swift \(swift == .null ? "nothing" : "something")"
                            + " vs Java \(javaTree == .null ? "nothing" : "something")")
                    }
                } else {
                    diffs += XmlTree.differences(swift, javaTree, "told \(key)", limit: 10)
                }
            }
            diffs += XmlTree.differences(try Self.saveTree(game), expected["save"] ?? .null, "save", limit: 20)
            if random.serializedState != expected["random"]?.stringValue {
                diffs.append("random: Swift \(random.serializedState) vs Java \(expected["random"]?.stringValue ?? "none")")
            }
            if !diffs.isEmpty {
                Issue.record(Comment(rawValue: "round \(i):\n" + diffs.prefix(40).joined(separator: "\n")))
                return
            }
        }
    }
}

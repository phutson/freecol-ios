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

/// Whole new turns (ServerGame.csNextTurn and csNewTurn), compared with
/// Java's.
@Suite(.serialized)
struct NewTurnTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()

    static func game(_ name: String) throws -> SavedGame {
        try FreeColSavegameFile(url: oracleDirectory.appendingPathComponent("games/" + name)).readServerGame()
    }

    /// The game as saved, without the specification (which reading a
    /// written specification changes; see XMLWritingTests) and with the
    /// random UUID masked.
    static func saveTree(_ game: Game) throws -> JSONValue {
        var tree = try XmlTree.parse(game.serialize(.toSave()))
        XmlTree.removeChild(&tree, Specification.tag)
        XmlTree.maskAttribute(&tree, "UUID", "MASKED")
        return tree
    }

    /// One new turn, as TurnRecorder plays it.
    static func turn(_ game: ServerGame, _ random: JavaRandom) throws -> ChangeSet {
        let cs = ChangeSet()
        try game.csNextTurn(cs)
        try game.csNewTurn(random, cs)
        return cs
    }

    /// TurnRecorder's game, played from its first save: after five
    /// turns it is its save at turn 5, and after ten its save at turn
    /// 10, random numbers and all.
    @Test func recordedTurns() throws {
        let start = try Self.game("freecol-seed1-turn000.fsg")
        let game = try #require(start.game as? ServerGame)
        let random = try #require(start.serverRandom)
        for (turns, name) in [(5, "freecol-seed1-turn005.fsg"), (10, "freecol-seed1-turn010.fsg")] {
            while game.turn.number < turns + 1 { _ = try Self.turn(game, random) }
            let java = try Self.game(name)
            let diffs = XmlTree.differences(try Self.saveTree(game), try Self.saveTree(java.game), "save", limit: 30)
            if !diffs.isEmpty {
                Issue.record(Comment(rawValue: "\(name):\n" + diffs.joined(separator: "\n")))
                return
            }
            #expect(random.serializedState == java.serverRandom?.serializedState, "\(name)")
        }
    }

    /// The US English messages, as in ColonyTurnTests.
    static var english: MessageBundle { ColonyTurnTests.english }

    static func tree(_ update: PlayerUpdate?) throws -> JSONValue {
        guard let update else { return .null }
        let xw = FreeColXMLWriter(scope: .toSave())
        update.toXML(xw)
        return try XmlTree.parse(xw.xml)
    }

    /// A game about to do the rest of a new turn (NewTurnGameMaker.java:
    /// disasters every turn, upkeep and bankruptcy, pioneers finishing,
    /// units fortifying and skipping, ships reaching and repaired in
    /// Europe, attrition, a native birth, a missionary and an emigrant),
    /// played for six turns: compared with Java turn by turn
    /// (NewTurnOracle.java).
    @Test func preparedTurns() throws {
        try Messages.$scopedBundle.withValue(Self.english) { try checkPreparedTurns() }
    }

    func checkPreparedTurns() throws {
        let archive = try ZipArchive(contentsOf: Self.oracleDirectory.appendingPathComponent("new-turns.zip"))
        let java = try JSONValue.parse(try #require(try archive.contents(of: "new-turns.json")))
        let rounds = try #require(java["rounds"]?.arrayValue)
        let game = try #require(try Self.game("freecol-newturn-seed1.fsg").game as? ServerGame)
        let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
        for (i, expected) in rounds.enumerated() {
            let cs = try Self.turn(game, random)
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
            diffs = Array(diffs.prefix(20))
            diffs += XmlTree.differences(try Self.saveTree(game), expected["save"] ?? .null, "save", limit: 20)
            if random.serializedState != expected["random"]?.stringValue {
                diffs.append("random differs")
            }
            if !diffs.isEmpty {
                Issue.record(Comment(rawValue: "turn \(i):\n" + diffs.prefix(40).joined(separator: "\n")))
                return
            }
        }
    }
}

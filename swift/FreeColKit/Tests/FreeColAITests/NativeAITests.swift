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

import CryptoKit
import Foundation
import FreeColAI
import FreeColCore
import FreeColIO
import FreeColServer
import FreeColTestSupport
import FreeColUtil
import Testing

/// The natives' AI, compared with Java's playing the same new game
/// (AIOracle.java, with the oracle's patched AIPlayer): rounds in which
/// the human ends its turn and every computer player plays its own, the
/// Europeans' AI only ending their turns.  After each round the game, the
/// server's generator and each AI player's generator must be Java's.
@Suite(.serialized)
struct NativeAITests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()
    static let data = FreeColDataDirectory(url: ReferenceDumps.repositoryRoot.appendingPathComponent("data"))

    static let english: MessageBundle = {
        let data = ReferenceDumps.repositoryRoot.appendingPathComponent("data")
        let strings = data.appendingPathComponent("strings")
        let numberRules = try! NumberRules(data: Data(contentsOf: strings.appendingPathComponent("plurals.xml")))
        return MessageBundle.load(directory: strings, languageId: "en_US", numberRules: numberRules,
                                  rulesDirectories: ["classic", "freecol"].map {
                                      data.appendingPathComponent("rules/" + $0)
                                  })
    }()

    /// Java's recording; FREECOL_AI names a directory of json files (made
    /// with --full) to use instead of the archive.
    static func recorded(_ name: String) throws -> JSONValue {
        if let dir = ProcessInfo.processInfo.environment["FREECOL_AI"] {
            return try JSONValue.parse(try Data(contentsOf: URL(fileURLWithPath: dir)
                .appendingPathComponent(name + ".json")))
        }
        let archive = try ZipArchive(contentsOf: oracleDirectory.appendingPathComponent("ai.zip"))
        return try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
    }

    static func saveTree(_ game: Game) throws -> JSONValue {
        var tree = try XmlTree.parse(game.serialize(.toSave()))
        XmlTree.removeChild(&tree, Specification.tag)
        XmlTree.maskAttribute(&tree, "UUID", "MASKED")
        return tree
    }

    /// Ten rounds of a new game.
    @Test func natives() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("natives")
            let spec = try Self.data.loadSpecification("freecol", difficulty: "model.difficulty.medium")
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let game = ServerGame.startNewGame(spec, random, playerName: "Player")
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(game: game, controller: controller, works: .natives)
            try play(java, game, controller, ai, random, rounds: 10)
        }
    }

    /// Twenty rounds of the command game, whose Dutch and French
    /// colonies the natives visit with gifts and demands.  Its AI is made
    /// afresh, as Java's server does for a saved game without one.
    @Test func nativesWithColonies() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("natives-colonies")
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory
                .appendingPathComponent("games/freecol-commands-seed1.fsg")).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(remaking: game, controller: controller, works: .natives)
            try play(java, game, controller, ai, random, rounds: 20)
        }
    }

    /// Twenty rounds of a game made for the natives' AI
    /// (NativeAIGameMaker.java): the natives at war with the Dutch and
    /// the Spanish, so they demand and attack, happy with the French and
    /// the English, so they bring gifts, and Dutch soldiers beside their
    /// settlements.
    @Test func nativesAtWar() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("natives-war")
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory
                .appendingPathComponent("games/freecol-nativeai-seed1.fsg")).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(remaking: game, controller: controller, works: .natives)
            try play(java, game, controller, ai, random, rounds: 20)
        }
    }

    /// Play the rounds, the human ending its turn each time, and compare
    /// each with Java's.
    func play(_ java: JSONValue, _ game: ServerGame, _ controller: InGameController, _ ai: AIMain,
              _ random: JavaRandom, rounds count: Int) throws {
        let rounds = try #require(java["rounds"]?.arrayValue)
        #expect(rounds.count == count + 1)
        let human = try #require(game.currentPlayer)
        do {
            controller.deliver = { player, update in
                if player.isAI { ai.handle(update, for: player) }
            }
            for (i, expected) in rounds.enumerated() {
                let label = expected["label"]?.stringValue ?? "?"
                if i > 0 {
                    _ = try controller.endTurn(human)
                    #expect(game.currentPlayer === human, "\(label) ended with someone else's turn")
                }
                var diffs = ai.errors
                let save = try Self.saveTree(game)
                if let javaSave = expected["save"] {
                    diffs += XmlTree.differences(save, javaSave, "save", limit: 30)
                } else {
                    let digest = SHA256.hash(data: Data(CanonicalJSON.document(save).utf8))
                        .map { String(format: "%02x", $0) }.joined()
                    if digest != expected["digest"]?.stringValue { diffs.append("save digest differs") }
                }
                if random.serializedState != expected["random"]?.stringValue { diffs.append("random differs") }
                for (id, state) in (expected["aiRandoms"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
                    let player = game.livePlayers.first { $0.id == id }
                    if ai.aiPlayer(player)?.aiRandom.serializedState != state.stringValue {
                        diffs.append("AI random of \(id) differs")
                    }
                }
                if !diffs.isEmpty {
                    Issue.record(Comment(rawValue: "\(label):\n" + diffs.prefix(30).joined(separator: "\n")))
                    return
                }
            }
        }
    }
}

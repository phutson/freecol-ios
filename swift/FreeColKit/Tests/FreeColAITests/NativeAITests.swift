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
@testable import FreeColAI
import FreeColCore
import FreeColIO
import FreeColServer
import FreeColTestSupport
import FreeColUtil
import FreeColXML
import Testing

/// The natives' AI, compared with Java's playing the same new game
/// (AIOracle.java, with the oracle's patched AIPlayer): rounds in which
/// the human ends its turn and every computer player plays its own, the
/// Europeans' AI only ending their turns, or working only their colonies.
/// After each round the game, the server's generator, each AI player's
/// generator and what the AI keeps for each colony must be Java's.
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

    /// What the AI keeps for a colony, as AIOracle.java writes it.
    static func describe(_ aic: AIColony) -> [String] {
        var lines = ["rearrange \(aic.rearrangeTurn)",
                     (["plan"] + aic.plannedBuildableTypes.map { $0.id ?? "" }).joined(separator: " ")]
        for w in aic.currentWishes {
            let what: String
            if let gw = w as? GoodsWish {
                what = "\(gw.goodsType.id ?? "") \(gw.goodsAmount)"
            } else if let ww = w as? WorkerWish {
                what = "\(ww.unitType.id ?? "") \(ww.expertNeeded)"
            } else {
                what = "?"
            }
            let dest = (w.destination as? FreeColGameObject)?.id ?? "null"
            lines.append("wish \(w.id ?? "") \(what) \(w.value) -> \(dest)")
        }
        for tip in aic.currentTileImprovementPlans {
            lines.append("tip \(tip.id ?? "") \(tip.type?.id ?? "") \(tip.target?.id ?? "") \(tip.value)")
        }
        for aig in aic.currentExportGoods {
            let dest = (aig.transportDestination as? FreeColGameObject)?.id ?? "null"
            lines.append("export \(aig.id ?? "") \(aig.goodsType?.id ?? "") \(aig.goods?.amount ?? 0)"
                         + " \(aig.transportPriority) -> \(dest)")
        }
        return lines
    }

    /// Twenty rounds of the command game with the Europeans' colonies
    /// working too (step 2 of Phase 4): their plans, wishes, tile
    /// improvements and exports, and the arrangement of their workers.
    @Test func colonies() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("colonies")
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory
                .appendingPathComponent("games/freecol-commands-seed1.fsg")).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(remaking: game, controller: controller, works: .colonies)
            try play(java, game, controller, ai, random, rounds: 20)
        }
    }

    /// Twenty rounds of the war game with the Europeans' colonies
    /// working too: native demands of the Dutch and Spanish colonies,
    /// and Dutch soldiers on the land around.
    @Test func coloniesAtWar() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("colonies-war")
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory
                .appendingPathComponent("games/freecol-nativeai-seed1.fsg")).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(remaking: game, controller: controller, works: .colonies)
            try play(java, game, controller, ai, random, rounds: 20)
        }
    }

    /// Twenty rounds of a game made for the colonies' AI
    /// (ColonyAIGameMaker.java) with the colonies working: rumours to
    /// explore, tiles to claim, colonies short of food or raw materials,
    /// and one with no one working.
    @Test func coloniesMade() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("colonies-made")
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory
                .appendingPathComponent("games/freecol-colonyai-seed1.fsg")).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(remaking: game, controller: controller, works: .colonies)
            try play(java, game, controller, ai, random, rounds: 20)
        }
    }

    /// Ten rounds of a new game with every computer player working
    /// (step 3 of Phase 4): the Europeans' first missions, transport,
    /// colonies and the rest.
    @Test func allWorking() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("all")
            let spec = try Self.data.loadSpecification("freecol", difficulty: "model.difficulty.medium")
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let game = ServerGame.startNewGame(spec, random, playerName: "Player")
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(game: game, controller: controller, works: .all)
            try play(java, game, controller, ai, random, rounds: 10)
        }
    }

    /// Twenty rounds of a saved game, its AI made afresh, compared with
    /// a recording.
    func playSaved(_ recording: String, _ file: String, _ works: AIMain.Works,
                   rounds count: Int = 20, beforeRound: ((Int, InGameController, Player) throws -> Void)? = nil) throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded(recording)
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory
                .appendingPathComponent("games/" + file)).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(remaking: game, controller: controller, works: works)
            try play(java, game, controller, ai, random, rounds: count, beforeRound: beforeRound)
        }
    }

    /// The command game with every computer player working.
    @Test func allWorkingColonies() throws {
        try playSaved("all-colonies", "freecol-commands-seed1.fsg", .all)
    }

    /// The war game with every computer player working.
    @Test func allWorkingAtWar() throws {
        try playSaved("all-war", "freecol-nativeai-seed1.fsg", .all)
    }

    /// The game made for the colonies' AI with every computer player
    /// working.
    @Test func allWorkingMade() throws {
        try playSaved("all-made", "freecol-colonyai-seed1.fsg", .all)
    }

    /// Every AI working in the units game (from UnitAIGameMaker): gold
    /// to spend, colonists on the docks, scouts, artillery, dragoons and
    /// soldiers, free colonists, and a privateer beside a laden
    /// merchantman.
    @Test func allWorkingUnits() throws {
        try playSaved("all-units", "freecol-unitai-seed1.fsg", .all)
    }

    /// The milestone of doc/swift-port-plan.md's Phase 3: sixty rounds
    /// of two new games, the computer players playing as Java's every
    /// round.
    @Test(arguments: [11, 2])
    func longGame(_ seed: Int) throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.recorded("long-\(seed)")
            let spec = try Self.data.loadSpecification("freecol", difficulty: "model.difficulty.medium")
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let game = ServerGame.startNewGame(spec, random, playerName: "Player")
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(game: game, controller: controller, works: .all)
            try play(java, game, controller, ai, random, rounds: 60)
        }
    }

    /// The REF game (from REFGameMaker): the human declares independence
    /// at the start of the first round, as AIOracle --declare has it,
    /// and the REF arrives, lands and fights, with every AI working.
    @Test func allWorkingREF() throws {
        try playSaved("all-ref", "freecol-ref-seed1.fsg", .all) { round, controller, human in
            guard round == 1 else { return }
            let cs = try controller.perform(.declareIndependence(nationName: "Free Dutch",
                                                                 countryName: "New Holland"), by: human)
            _ = try cs?.build(human)
            #expect(human.isRebel)
        }
    }

    /// A recording of a game saved and loaded again (AIOracle
    /// --reload-at), cut to some of its rounds.
    static func reloadRounds(_ name: String, _ range: ClosedRange<Int>) throws -> JSONValue {
        let java = try recorded(name)
        var doc = try #require(java.objectValue)
        doc["rounds"] = .array(Array(try #require(java["rounds"]?.arrayValue)[range]))
        return .object(doc)
    }

    /// The AI's objects as Java saved them.
    static func javaAITree(_ file: String) throws -> JSONValue {
        let file = try FreeColSavegameFile(url: oracleDirectory.appendingPathComponent("games/" + file))
        let tree = try XmlTree.parse(String(decoding: try file.savegameData(), as: UTF8.self))
        return try #require(tree["children"]?.arrayValue?.first { $0["tag"]?.stringValue == "aiMain" })
    }

    /// The AI written as Java's server saves it, compared with Java's.
    func expectAISaved(_ ai: AIMain, _ file: String) throws {
        let xw = FreeColXMLWriter(scope: .toSave())
        ai.toXML(xw)
        let diffs = XmlTree.differences(try XmlTree.parse(xw.xml), try Self.javaAITree(file), "aiMain", limit: 30)
        #expect(diffs.isEmpty, "\(diffs.joined(separator: "\n"))")
    }

    /// Five rounds of the new game, then the AI saved as Java's was.
    @Test func aiSaved() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.reloadRounds("all-reload", 0...5)
            let spec = try Self.data.loadSpecification("freecol", difficulty: "model.difficulty.medium")
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let game = ServerGame.startNewGame(spec, random, playerName: "Player")
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(game: game, controller: controller, works: .all)
            try play(java, game, controller, ai, random, rounds: 5)
            try expectAISaved(ai, "freecol-aisave-seed11.fsg")
        }
    }

    /// Ten rounds of the units game, then the AI saved as Java's was:
    /// cargoes, export goods, plans, wishes and most missions.
    @Test func aiSavedUnits() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.reloadRounds("units-reload", 0...10)
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory
                .appendingPathComponent("games/freecol-unitai-seed1.fsg")).readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
            let controller = InGameController(game: game, random: random)
            let ai = AIMain(remaking: game, controller: controller, works: .all)
            try play(java, game, controller, ai, random, rounds: 10)
            try expectAISaved(ai, "freecol-aisave-units.fsg")
        }
    }

    /// A game Java saved, AI and all, read back as Java's server reads
    /// it and played on as Java's did after reading it.  Java's first
    /// round is from before saving, with what is not saved, so it is
    /// not compared.  (Written again the AI is not as saved: a loaded
    /// unit's transport priority is its mission's.)
    func playLoaded(_ recording: String, _ file: String, _ range: ClosedRange<Int>) throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let java = try Self.reloadRounds(recording, range)
            let saved = try FreeColSavegameFile(url: Self.oracleDirectory.appendingPathComponent("games/" + file))
                .readServerGame()
            let game = try #require(saved.game as? ServerGame)
            game.finishLoading()
            game.currentPlayer = game.livePlayers.first { !$0.isAI }
            let random = try #require(saved.serverRandom)
            let controller = InGameController(game: game, random: random)
            let ai = AIMain.loading(saved.aiMain, game: game, controller: controller)
            try play(java, game, controller, ai, random, rounds: range.count - 1, fromRound: 1)
        }
    }

    /// The new game saved after round 5, played on to round 10.
    @Test func aiLoaded() throws {
        try playLoaded("all-reload", "freecol-aisave-seed11.fsg", 5...10)
    }

    /// The units game saved after round 10, played on to round 20.
    @Test func aiLoadedUnits() throws {
        try playLoaded("units-reload", "freecol-aisave-units.fsg", 10...20)
    }

    /// Play the rounds, the human ending its turn each time, and compare
    /// each with Java's.
    func play(_ java: JSONValue, _ game: ServerGame, _ controller: InGameController, _ ai: AIMain,
              _ random: JavaRandom, rounds count: Int, fromRound first: Int = 0,
              beforeRound: ((Int, InGameController, Player) throws -> Void)? = nil) throws {
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
                    try beforeRound?(i, controller, human)
                    _ = try controller.endTurn(human)
                    #expect(game.currentPlayer === human, "\(label) ended with someone else's turn")
                }
                if i < first { continue }
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
                if let colonies = expected["aiColonies"]?.objectValue {
                    for (id, lines) in colonies.sorted(by: { $0.key < $1.key }) {
                        let javaLines = (lines.arrayValue ?? []).compactMap(\.stringValue)
                        let colony = game.getFreeColGameObject(id) as? Colony
                        let ours = colony.flatMap { ai.aiColony($0) }.map(Self.describe) ?? ["no AI colony"]
                        if ours != javaLines {
                            diffs.append("AI colony \(id):\n  java: \(javaLines)\n  ours: \(ours)")
                        }
                    }
                }
                if let units = expected["aiUnits"]?.objectValue {
                    var ours: [String: String] = [:]
                    for p in game.liveEuropeanPlayers(excluding: nil) where p.isAI {
                        for u in p.units {
                            guard let aiu = ai.aiUnit(u), let id = u.id else { continue }
                            var what = "none"
                            if let m = aiu.mission {
                                what = String(describing: type(of: m)) + " -> "
                                    + ((m.target as? FreeColGameObject)?.id ?? "null")
                            }
                            if let tr = aiu.transport { what += " on " + (tr.unit.id ?? "") }
                            ours[id] = what
                        }
                    }
                    for id in Set(units.keys).union(ours.keys).sorted()
                    where units[id]?.stringValue != ours[id] {
                        diffs.append("AI unit \(id): Java \(units[id]?.stringValue ?? "missing"), "
                                     + "Swift \(ours[id] ?? "missing")")
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

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
import FreeColCore
import FreeColIO
import FreeColServer
import FreeColTestSupport
import FreeColUtil
import FreeColXML
import Testing

/// Players' commands, compared with Java's server handling the same
/// messages (CommandOracle.java, on the game CommandGameMaker.java
/// makes).
///
/// Each command is read from Java's message XML, as a network would
/// deliver it.  Java refusing it (an error reply) must be Swift
/// throwing CommandRefused; otherwise what every player was sent, the
/// reply, the game and the generator must be Java's.
@Suite(.serialized)
struct CommandTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()

    /// Managing units, colonies and goods, Europe and treasure.
    @Test func colonyAndEurope() throws {
        try Messages.$scopedBundle.withValue(ColonyTurnTests.english) {
            try check("commands", game: "freecol-commands-seed1.fsg")
        }
    }

    /// Dealing with natives: learning (and dying for it), scouting and
    /// speaking to chiefs, missions established and denounced, inciting,
    /// tribute, a whole trade (selling, a gift, buying), the natives'
    /// gifts and demands accepted, rejected and left unanswered, and
    /// nation summaries.
    @Test func natives() throws {
        try Messages.$scopedBundle.withValue(ColonyTurnTests.english) {
            try check("natives", game: "freecol-natives-seed1.fsg")
        }
    }

    /// Moving: a first landing, every kind of lost city rumour, mounds
    /// left alone, a first contact, a region discovered and named,
    /// sentries woken, a ship slowed by an enemy, units leaving a ship
    /// in a colony, a move refused, sailing to and from Europe (turning
    /// round on the way), and new turns for the ships to arrive.
    @Test func moves() throws {
        try Messages.$scopedBundle.withValue(ColonyTurnTests.english) {
            try check("moves", game: "freecol-moves-seed1.fsg")
        }
    }

    /// Combat: soldiers demoted, captured and their equipment taken,
    /// colonies attacked and captured, natives slaughtered and a
    /// settlement destroyed (its missions burned), braves attacking a
    /// colony, ships damaged and evading, cargo looted, a fort
    /// bombarding a ship at the start of a turn, and attacks again after
    /// a new turn, some refused.
    @Test func combat() throws {
        try Messages.$scopedBundle.withValue(ColonyTurnTests.english) {
            try check("combat", game: "freecol-combat-seed1.fsg")
        }
    }

    static func element(_ tree: JSONValue) -> CommandElement {
        var attributes: [String: String] = [:]
        if case .object(let attrs)? = tree["attrs"] {
            for (k, v) in attrs { attributes[k] = v.stringValue }
        }
        return CommandElement(tag: tree["tag"]?.stringValue ?? "", attributes: attributes,
                          children: (tree["children"]?.arrayValue ?? []).map(element))
    }

    static func command(_ tree: JSONValue) throws -> PlayerCommand {
        let e = element(tree)
        return try PlayerCommand(tag: e.tag, attributes: e.attributes, children: e.children)
    }

    func check(_ name: String, game gameFile: String) throws {
        // FREECOL_COMMANDS names a directory of the oracle's output made
        // with --full, for finding where a save differs.
        let java: JSONValue
        if let dir = ProcessInfo.processInfo.environment["FREECOL_COMMANDS"] {
            java = try JSONValue.parse(try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(name + ".json")))
        } else {
            let archive = try ZipArchive(contentsOf: Self.oracleDirectory.appendingPathComponent("commands.zip"))
            java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
        }
        let commands = try #require(java["commands"]?.arrayValue)
        #expect(commands.count >= 25)
        let saved = try FreeColSavegameFile(url: Self.oracleDirectory
            .appendingPathComponent("games/" + gameFile)).readServerGame()
        let game = try #require(saved.game as? ServerGame)
        game.currentPlayer = game.liveEuropeanPlayers.first
        let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
        let igc = InGameController(game: game, random: random)
        var sent: [(to: String, tree: JSONValue)] = []
        var deliveryError: Error?
        igc.deliver = { p, update in
            do {
                sent.append((p.nationId ?? "null", try TurnCycleTests.tree(update)))
            } catch {
                deliveryError = error
            }
        }

        for (i, expected) in commands.enumerated() {
            let label = "\(i) \(expected["label"]?.stringValue ?? "?")"
            let startTurn = expected["startTurn"] == .bool(true)
            let newTurn = expected["newTurn"] == .bool(true) || startTurn
            let player = try #require(newTurn ? game.liveEuropeanPlayers.first
                                          : game.player(byNationId: expected["player"]?.stringValue))
            let javaReply = expected["reply"] ?? .null
            let refused = javaReply["tag"]?.stringValue == "error"
            sent = []
            var diffs: [String] = []
            var cs: ChangeSet?
            if startTurn {
                // The start of the Dutch turn, telling every player.
                let turnChanges = ChangeSet()
                try player.csStartTurn(random, turnChanges)
                for p in game.players {
                    if let update = try turnChanges.build(p) { igc.deliver(p, update) }
                }
            } else if newTurn {
                // As endTurn plays one, telling every player.
                let turnChanges = ChangeSet()
                try game.csNextTurn(turnChanges)
                try game.csNewTurn(random, turnChanges)
                for p in game.players {
                    if let update = try turnChanges.build(p) { igc.deliver(p, update) }
                }
            } else {
                let command = try Self.command(try #require(expected["message"]))
                do {
                    cs = try igc.perform(command, by: player)
                    if refused { diffs.append("Java refused, Swift did not") }
                } catch let e as CommandRefused {
                    if !refused { diffs.append("Swift refused: \(e.message)") }
                }
            }
            if let deliveryError { throw deliveryError }
            let javaSent = expected["sent"]?.arrayValue ?? []
            if sent.map(\.to) != javaSent.map({ $0["to"]?.stringValue ?? "" }) {
                diffs.append("sent to \(sent.map(\.to)) vs Java \(javaSent.map { $0["to"]?.stringValue ?? "" })")
            } else {
                for (j, s) in sent.enumerated() {
                    diffs += XmlTree.differences(s.tree, javaSent[j]["tree"] ?? .null, "sent \(j) to \(s.to)",
                                                 limit: 10)
                    if diffs.count > 20 { break }
                }
            }
            if !refused && !newTurn {
                let reply = try TurnCycleTests.tree(cs?.build(player))
                if reply == .null || javaReply == .null {
                    if reply != javaReply { diffs.append("reply: Swift \(reply == .null ? "none" : "some") vs Java") }
                } else {
                    diffs += XmlTree.differences(reply, javaReply, "reply", limit: 10)
                }
            }
            let save = try NewTurnTests.saveTree(game)
            let digest = SHA256.hash(data: Data(CanonicalJSON.document(save).utf8))
                .map { String(format: "%02x", $0) }.joined()
            if let javaSave = expected["save"] {
                diffs += XmlTree.differences(save, javaSave, "save", limit: 20)
            } else if digest != expected["digest"]?.stringValue {
                diffs.append("save digest differs")
            }
            if random.serializedState != expected["random"]?.stringValue {
                diffs.append("random differs")
            }
            if !diffs.isEmpty {
                Issue.record(Comment(rawValue: "\(name) \(label):\n" + diffs.prefix(40).joined(separator: "\n")))
                return
            }
        }
    }
}

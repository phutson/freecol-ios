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

/// The turn cycle (InGameController.endTurn), compared with Java's
/// (TurnCycleOracle.java, on the games TurnCycleGameMaker.java makes).
///
/// Each call ends the current player's turn and goes on to the next
/// player's; for each, what every player was sent, in order, the reply
/// to the player whose turn ended, the game (as a digest, and in full
/// after the last call) and the generator must be Java's.
@Suite(.serialized)
struct TurnCycleTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()

    /// Every monarch action, each forced once, with founding fathers
    /// (La Salle's free stockades, a frigate, Pocahontas, Coronado and
    /// Fugger), war and peace, a native converted, and tax raises left
    /// unanswered, over four rounds.
    @Test func monarch() throws {
        try check("monarch")
    }

    /// A native nation and a European one dying, one with a mission in
    /// it, a European given a colonist to survive, De Soto, and
    /// Bartolome de las Casas changing a convert, over two rounds.
    @Test func deaths() throws {
        try check("deaths")
    }

    /// Magellan, Brewster, Bolivar and Paine, over a round.
    @Test func fathers() throws {
        try check("fathers")
    }

    func check(_ name: String) throws {
        try Messages.$scopedBundle.withValue(ColonyTurnTests.english) { try checkCalls(name) }
    }

    static func tree(_ update: PlayerUpdate?) throws -> JSONValue {
        guard let update else { return .null }
        let xw = FreeColXMLWriter(scope: .toSave())
        update.toXML(xw)
        return try XmlTree.parse(xw.xml)
    }

    func checkCalls(_ name: String) throws {
        // FREECOL_TURN_CYCLES names a directory of the oracle's output
        // made with --full, for finding where a save differs.
        let java: JSONValue
        if let dir = ProcessInfo.processInfo.environment["FREECOL_TURN_CYCLES"] {
            java = try JSONValue.parse(try Data(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent(name + ".json")))
        } else {
            let archive = try ZipArchive(contentsOf: Self.oracleDirectory.appendingPathComponent("turn-cycles.zip"))
            java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
        }
        let calls = try #require(java["calls"]?.arrayValue)
        let saved = try FreeColSavegameFile(url: Self.oracleDirectory
            .appendingPathComponent("games/freecol-turncycle-\(name)-seed1.fsg")).readServerGame()
        let game = try #require(saved.game as? ServerGame)
        // Loading clears the current player in Java; the human starts.
        game.currentPlayer = game.liveEuropeanPlayers.first { !$0.isAI }
        let random = JavaRandom(seed: try #require(java["seed"]?.intValue))
        let igc = InGameController(game: game, random: random)
        var sent: [(to: String, tree: JSONValue)] = []
        var deliveryError: Error?
        igc.deliver = { p, update in
            do {
                sent.append((p.nationId ?? "null", try Self.tree(update)))
            } catch {
                deliveryError = error
            }
        }

        for (i, expected) in calls.enumerated() {
            let current = try #require(game.currentPlayer, "call \(i): no current player")
            var diffs: [String] = []
            if current.nationId != expected["player"]?.stringValue {
                Issue.record("call \(i): \(current.nationId ?? "null") ends, not \(expected["player"]?.stringValue ?? "?")")
                return
            }
            if let forced = expected["forced"] {
                let p = try #require(game.player(byNationId: forced["player"]?.stringValue))
                let action = try #require(Monarch.MonarchAction.allCases.first {
                    $0.javaName == forced["action"]?.stringValue
                })
                igc.setMonarchAction(p, action)
            }
            sent = []
            let cs = try igc.endTurn(current)
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
            let reply = try Self.tree(cs.build(current))
            if reply == .null || expected["reply"] == .null || expected["reply"] == nil {
                if reply != (expected["reply"] ?? .null) { diffs.append("reply differs") }
            } else {
                diffs += XmlTree.differences(reply, expected["reply"] ?? .null, "reply", limit: 10)
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
                Issue.record(Comment(rawValue: "\(name) call \(i) (\(current.nationId ?? "null")):\n"
                                         + diffs.prefix(40).joined(separator: "\n")))
                return
            }
        }
    }
}

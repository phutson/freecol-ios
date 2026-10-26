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
import FreeColXML
import Testing

typealias Unit = FreeColCore.Unit

/// What each player is told of a set of change sets, compared with
/// what Java sends (ChangeOracle.java): the same scenarios, on the same
/// game, in the same order, as message XML trees.
@Suite(.serialized)
struct ChangeSetTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()

    static func first<T: FreeColObject>(_ list: [T]) -> T {
        list.sorted { FreeColObject.compareIds($0, $1) < 0 }[0]
    }

    /// The first unit of a player directly on a tile.
    static func firstOnMap(_ p: Player) -> Unit {
        first(p.units.filter { $0.location is Tile })
    }

    /// The first unit of a player aboard a ship on a tile.
    static func firstAboard(_ p: Player) -> Unit? {
        let units = p.units.filter { $0.isOnCarrier && $0.carrier?.location is Tile }
        return units.isEmpty ? nil : first(units)
    }

    /// The first neighbour of a tile, in direction order.
    static func neighbour(_ tile: Tile?) -> Tile {
        Direction.allCases.lazy.compactMap { tile?.neighbour($0) }.first!
    }

    /// The scenarios of ChangeOracle, by name, in order.
    static func scenarios(_ game: Game) -> [(String, (ChangeSet) throws -> Void)] {
        let live = game.livePlayers
        let eu = game.liveEuropeanPlayers
        let a = eu[0], b = eu[1]
        let n = live.first { $0.isIndian }!
        let ca = first(a.colonyList), cb = first(b.colonyList)
        let settlement = first(n.indianSettlementList)
        // The first European player is the human one.
        a.isAI = false
        let ua = firstOnMap(a), ub = firstOnMap(b)
        let un = first(n.units)
        let aboard = firstAboard(a)
        let spec = game.specification!
        // A tile next to the human player's unit that it can see,
        // without a settlement.
        let seenTile = Direction.allCases.lazy.compactMap { ua.tile?.neighbour($0) }
            .first { !$0.hasSettlement && a.canSee($0) }!
        return [
            ("01-objects-perhaps", { cs in
                cs.add(.perhaps(), ca, settlement, ua, ub, un, ua.tile, settlement.tile,
                       a.europe, first(ca.buildings), first(ca.colonyTiles), a, n)
            }),
            ("02-objects-only", { cs in
                cs.add(.only(a), ca, ub)
                cs.add(.all().except(a), ua)
                cs.add(.only(a).perhapsOnly(b), ub, ua, cb)
            }),
            ("03-partial", { cs in
                cs.addPartial(.only(a), a, ("gold", "123"), ("score", "45"))
                cs.addPartial(.all(), ca, ("sonsOfLiberty", "50"))
            }),
            ("04-attributes", { cs in
                cs.addAttribute(.only(a), "flush", "true")
                cs.add(.only(a), ua)
                cs.addAttribute(.all(), "sound", "model.sound.test")
            }),
            ("05-attribute-alone", { cs in
                cs.addAttribute(.all(), "flush", "true")
            }),
            ("06-attribute-and-one", { cs in
                cs.addAttribute(.all(), "flush", "true")
                cs.addPartial(.all(), cb, ("name", "Renamed"))
            }),
            ("07-messages", { cs in
                cs.addMessage(a, ModelMessage(.default, "model.test.first", a))
                cs.addMessage(a, ModelMessage(.warning, "model.test.colony", ca))
                cs.addGlobalMessage(game, b, ModelMessage(.default, "model.test.global", ca))
                cs.addHistory(a, HistoryEvent(game.turn, .foundColony, a))
                cs.addGlobalHistory(game, HistoryEvent(game.turn, .spanishSuccession, nil))
                cs.addSale(a, settlement, spec.getGoodsType("model.goods.furs")!, 5)
            }),
            ("08-features", { cs in
                cs.addAbility(a, ca, Ability("model.ability.test", value: true), true)
                cs.addModifier(b, ub, Modifier("model.modifier.test", 2, .additive), true)
                cs.addAbility(a, a, Ability("model.ability.test2", value: false), true)
            }),
            ("09-stance", { cs in
                cs.addStance(.all(), a, .war, b)
                cs.addStance(.only(n), n, .peace, a)
            }),
            ("10-players", { cs in
                cs.addPlayers([b, n])
            }),
            ("11-remove", { cs in
                cs.addRemove(.perhaps(), ub.tile, ub)
                cs.addRemove(.perhaps().always(b), settlement.tile, un)
                cs.addRemoves(.only(a), ca.tile, [ca])
            }),
            ("12-disappear", { cs in
                cs.addDisappear(a, ua.tile!, ua)
            }),
            ("13-move", { cs in
                cs.addMove(.perhaps(), ub, neighbour(ub.tile), ub.tile!)
                cs.addMove(.perhaps(), un, neighbour(un.tile), un.tile!)
                if let aboard {
                    cs.addMove(.perhaps(), aboard, neighbour(aboard.tile), aboard.tile!)
                }
            }),
            ("14-attack", { cs in
                try cs.addAttack(.perhaps(), ua, ub, true)
                try cs.addAttack(.perhaps().always(n), un, ua, false)
            }),
            ("15-spy", { cs in
                cs.addSpy(ua, cb)
            }),
            ("16-mixed", { cs in
                cs.addRemove(.perhaps(), ub.tile, ub)
                cs.add(.perhaps(), ca, cb)
                cs.addStance(.all(), b, .peace, a)
                cs.addMessage(b, ModelMessage(.default, "model.test.mixed", b))
                cs.addPartial(.only(b), b, ("gold", "7"))
                cs.addMove(.perhaps(), ub, neighbour(ub.tile), ub.tile!)
                cs.add(.perhaps(), ub.tile)
                cs.addAttribute(.only(b), "flush", "true")
            }),
            ("17-remove-matching", { cs in
                cs.add(.all(), ca, cb, ua)
                cs.remove(cb)
            }),
            ("18-seen-colony", { cs in
                // Another player's unit moves next to the colony, so
                // that player sees it.
                let near = Direction.allCases.lazy.compactMap { ca.tile?.neighbour($0) }
                    .first { $0.isLand && !$0.hasSettlement }
                _ = first(b.units.filter { $0.location is Tile && !$0.isNaval }).setLocation(near)
                b.invalidateCanSeeTiles()
                cs.add(.perhaps(), ca, ca.tile, first(ca.buildings), first(ca.colonyTiles), first(ca.unitList))
            }),
            ("19-move-out-of-sight", { cs in
                cs.addMove(.perhaps(), ub, seenTile, ub.tile!)
            }),
        ]
    }

    static func tree(_ update: PlayerUpdate?) throws -> JSONValue {
        guard let update else { return .null }
        let xw = FreeColXMLWriter(scope: .toSave())
        update.toXML(xw)
        return try XmlTree.parse(xw.xml)
    }

    @Test func playersAreToldWhatJavaTellsThem() throws {
        let java = try JSONValue.parse(Data(contentsOf: Self.oracleDirectory.appendingPathComponent("changes.json")))
        let url = Self.oracleDirectory.appendingPathComponent("games/freecol-colonies-seed1.fsg")
        let game = try FreeColSavegameFile(url: url).readGame().game
        let scenarios = Self.scenarios(game)
        #expect(scenarios.count + 1 == java.objectValue?.count)
        for (name, make) in scenarios {
            let cs = ChangeSet()
            try make(cs)
            let expected = try #require(java[name]?.objectValue, "\(name)")
            var diffs: [String] = []
            for p in game.livePlayers {
                let key = p.nationId ?? "null"
                let swift = try Self.tree(cs.build(p))
                let javaTree = expected[key] ?? .null
                if swift == .null || javaTree == .null {
                    if swift != javaTree {
                        diffs.append("\(key): Swift \(swift == .null ? "nothing" : "a message")"
                            + " vs Java \(javaTree == .null ? "nothing" : "a message")")
                    }
                } else {
                    diffs += XmlTree.differences(swift, javaTree, key, limit: 10)
                }
            }
            if !diffs.isEmpty {
                Issue.record(Comment(rawValue: "\(name):\n" + diffs.prefix(30).joined(separator: "\n")))
            }
        }
        // The game afterwards: the helpers' changes, and what telling
        // the players did to it.
        var save = try XmlTree.parse(game.serialize(.toSave()))
        XmlTree.removeChild(&save, Specification.tag)
        XmlTree.maskAttribute(&save, "UUID", "MASKED")
        let digest = SHA256.hash(data: Data(CanonicalJSON.document(save).utf8))
            .map { String(format: "%02x", $0) }.joined()
        #expect(digest == java["finalSaveDigest"]?.stringValue)
    }

    // MARK: Without Java

    /// A message the server's code adds itself, such as a new turn.
    final class TestMessage: ServerMessage {
        let tag: String
        let priority: MessagePriority
        let isAttributeMessage: Bool
        let attributes: [(key: String, value: String)]

        init(_ tag: String, _ priority: MessagePriority, attributeMessage: Bool) {
            self.tag = tag
            self.priority = priority
            isAttributeMessage = attributeMessage
            attributes = [("turn", "3")]
        }

        func writeChildren(_ xw: FreeColXMLWriter) {}
    }

    static func xml(_ update: PlayerUpdate?) -> String? {
        guard let update else { return nil }
        let xw = FreeColXMLWriter(scope: .toSave())
        update.toXML(xw)
        return xw.xml
    }

    @Test func messagesGoInPriorityOrderAndSettingsJoinThem() throws {
        let game = try FreeColSavegameFile(url: Self.oracleDirectory.appendingPathComponent(
            "games/freecol-colonies-seed1.fsg")).readGame().game
        let a = game.liveEuropeanPlayers[0], b = game.liveEuropeanPlayers[1]

        let cs = ChangeSet()
        cs.add(.all(), message: TestMessage("late", .late, attributeMessage: false))
        cs.add(.all(), message: TestMessage("early", .early, attributeMessage: false))
        cs.add(.all().except(b), message: TestMessage("hidden", .normal, attributeMessage: false))
        #expect(Self.xml(try cs.build(a)) == "<multiple><early turn=\"3\"/><hidden turn=\"3\"/><late turn=\"3\"/></multiple>")
        #expect(Self.xml(try cs.build(b)) == "<multiple><early turn=\"3\"/><late turn=\"3\"/></multiple>")

        // A lone message takes the settings if it is an attribute
        // message, and is wrapped if not.
        let one = ChangeSet()
        one.add(.only(a), message: TestMessage("plain", .normal, attributeMessage: false))
        one.addAttribute(.only(a), "flush", "true")
        #expect(Self.xml(try one.build(a)) == "<multiple flush=\"true\"><plain turn=\"3\"/></multiple>")
        #expect(try one.build(b) == nil)
        let attr = ChangeSet()
        attr.add(.only(a), message: TestMessage("attr", .normal, attributeMessage: true))
        attr.addAttribute(.only(a), "flush", "true")
        #expect(Self.xml(try attr.build(a)) == "<attr turn=\"3\" flush=\"true\"/>")
        #expect(try ChangeSet().build(a) == nil)
    }

    @Test func seeChecksInOrder() throws {
        let game = try FreeColSavegameFile(url: Self.oracleDirectory.appendingPathComponent(
            "games/freecol-colonies-seed1.fsg")).readGame().game
        let a = game.liveEuropeanPlayers[0], b = game.liveEuropeanPlayers[1]
        let c = game.liveEuropeanPlayers[2]
        func told(_ see: ChangeSet.See, _ p: Player) throws -> Bool {
            try ChangeSet().addAttribute(see, "k", "v").build(p) != nil
        }
        #expect(try told(.all(), a))
        #expect(try !told(.all().except(a), a))
        #expect(try told(.only(a), a) && !told(.only(a), b))
        #expect(try told(.only(a).always(b), b))
        // Never beats always for the same player.
        #expect(try !told(.all().always(c).except(c), c))
        // Attributes are only told to those who see them for certain.
        #expect(try !told(.perhaps(), a))
    }
}

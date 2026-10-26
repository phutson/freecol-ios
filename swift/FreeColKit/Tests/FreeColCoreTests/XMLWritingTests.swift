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
import FreeColTestSupport
import FreeColUtil
import FreeColXML
import Testing

/// The XML written for the maps and saved games, for a saved game and
/// for each European player's client, compared with what Java writes
/// (XmlOracle.java): as trees, so attribute order and the order of
/// abilities and modifiers do not matter.
@Suite(.serialized)
struct XMLWritingTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("xml")

    /// The inputs whose whole trees the oracle keeps.
    static let fullInputs = ["S_Caribbean_Phil.fsm", "freecol-seed1-turn005.fsg",
                             "freecol-colonies-seed1.fsg", "freecol-economy-seed1.fsg"]

    static let javaDigests: [String: String] = {
        guard let data = try? Data(contentsOf: oracleDirectory.appendingPathComponent("digests.json")),
              let json = try? JSONValue.parse(data), let members = json.objectValue else { return [:] }
        return members.compactMapValues(\.stringValue)
    }()

    static func javaDocument(_ name: String) throws -> JSONValue {
        let archive = try ZipArchive(contentsOf: oracleDirectory.appendingPathComponent("full.zip"))
        return try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
    }

    /// The classic rules, as XmlOracle reads the maps with.
    nonisolated(unsafe) static let classic: Specification = {
        try! SpecificationTests.data.loadSpecification("classic", difficulty: "model.difficulty.medium")
    }()

    /// Read a map with the classic rules, or a saved game with its own.
    static func read(_ name: String) throws -> Game {
        try FreeColSavegameFile(url: MapTests.input(name)).readGame(specification: classic).game
    }

    /// A game's tree for a scope, without the specification and with
    /// the random UUID masked, and the specification's tree, as
    /// XmlOracle makes them.
    static func tree(_ game: Game, _ scope: FreeColXMLWriter.WriteScope) throws
        -> (game: JSONValue, specification: JSONValue) {
        var tree = try XmlTree.parse(game.serialize(scope))
        let spec = XmlTree.removeChild(&tree, Specification.tag)
        XmlTree.maskAttribute(&tree, "UUID", "MASKED")
        return (tree, spec ?? .object([:]))
    }

    /// The save tree, its specification, and each live European
    /// player's client tree.
    static func document(_ game: Game) throws -> JSONValue {
        var clients: [String: JSONValue] = [:]
        let save = try tree(game, .toSave())
        for p in game.liveEuropeanPlayers {
            clients[p.nationId ?? "null"] = try tree(game, .toClient(p)).game
        }
        return .object(["save": save.game, "specification": save.specification, "client": .object(clients)])
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Every difference, by scope and element.
    static func differences(_ swift: JSONValue, _ java: JSONValue) -> [String] {
        var out = XmlTree.differences(swift["save"] ?? .null, java["save"] ?? .null, "save")
        out += XmlTree.differences(swift["specification"] ?? .null, java["specification"] ?? .null,
                                   "specification", limit: 10)
        let sc = swift["client"]?.objectValue ?? [:], jc = java["client"]?.objectValue ?? [:]
        for key in Set(sc.keys).union(jc.keys).sorted() {
            guard let s = sc[key], let j = jc[key] else {
                out.append("client \(key): only in \(sc[key] == nil ? "Java" : "Swift")")
                continue
            }
            out += XmlTree.differences(s, j, "client \(key)", limit: 10)
        }
        return out
    }

    @Test(arguments: fullInputs)
    func wholeTrees(_ name: String) throws {
        let game = try Self.read(name)
        let swift = try Self.document(game)
        let java = try Self.javaDocument(name)
        let diffs = Self.differences(swift, java)
        if !diffs.isEmpty {
            Issue.record(Comment(rawValue: "\(name):\n" + diffs.prefix(40).joined(separator: "\n")))
        }
    }

    /// Give every live European player a copy of each settlement tile
    /// as its view, as XmlOracle --stale does.
    static func cacheSettlementTiles(_ game: Game) throws {
        for tile in game.map?.tiles ?? [] where tile.hasSettlement {
            for p in game.liveEuropeanPlayers { tile.setCachedTile(p, try tile.tileToCache()) }
        }
    }

    /// Stale views: copied tiles in the saved game, and shown to each
    /// client instead of the tile.
    @Test func staleViews() throws {
        let name = "freecol-colonies-seed1.fsg"
        let game = try Self.read(name)
        // As XmlOracle does, write the plain document first: that adds
        // the tension each client is shown to the save, and works out
        // what each player can see, which refreshes their views.
        _ = try Self.document(game)
        try Self.cacheSettlementTiles(game)
        let diffs = Self.differences(try Self.document(game), try Self.javaDocument(name + ".stale"))
        if !diffs.isEmpty {
            Issue.record(Comment(rawValue: "\(name):\n" + diffs.prefix(40).joined(separator: "\n")))
        }
    }

    /// A saved game read back gives the same XML: the stale copies are
    /// read without registering them, and written again.
    ///
    /// Writing a copied view for a player works out what the player
    /// can see, which (with fog of war) refreshes the player's views of
    /// the tiles it can see, part way through the save, as in Java.  So
    /// both games are written with that still to do.
    @Test func savedGameReadsBack() throws {
        let game = try Self.read("freecol-colonies-seed1.fsg")
        _ = try Self.document(game)
        try Self.cacheSettlementTiles(game)
        let xr = try FreeColXMLReader(string: game.serialize(.toSave()))
        try xr.nextTag()
        let again = Game(specification: nil)
        try again.readFromXML(xr)
        // The copies are not registered: every object found by id is
        // the one in the map.
        for tile in again.map?.tiles ?? [] where tile.hasSettlement {
            for p in again.liveEuropeanPlayers {
                let view = try #require(tile.cachedTile(p))
                #expect(view !== tile && view.settlement !== tile.settlement)
                #expect(again.getFreeColGameObject(tile.id) === tile)
                #expect(again.getFreeColGameObject(view.settlement?.id) === tile.settlement)
            }
        }
        // The specification is left out: reading it again makes the
        // custom difficulty's groups uneditable, in Java too, as each
        // group added to an uneditable one becomes uneditable.
        for p in game.players { p.invalidateCanSeeTiles() }
        let diffs = XmlTree.differences(try Self.tree(again, .toSave()).game,
                                        try Self.tree(game, .toSave()).game, "save")
        if !diffs.isEmpty {
            Issue.record(Comment(rawValue: diffs.joined(separator: "\n")))
        }
    }

    /// The other maps, by digest of the document.  A debug build takes
    /// a while for a big map, so by default only some are checked;
    /// FREECOL_ALL_MAPS=1 checks them all.
    static let digested: [String] = {
        let all = javaDigests.keys.sorted().filter { !fullInputs.contains($0) && !$0.hasSuffix(".stale") }
        return ProcessInfo.processInfo.environment["FREECOL_ALL_MAPS"] == "1"
            ? all : ["S_AustraliaOceania_Gilolat.fsm", "S_FeudalJapan_Mazim.fsm", "freecol-colonyturn-seed1.fsg",
                   "freecol-newturn-seed1.fsg", "freecol-seed1-turn000.fsg", "freecol-seed1-turn010.fsg"]
    }()

    @Test(arguments: digested)
    func digests(_ name: String) throws {
        let game = try Self.read(name)
        let swift = CanonicalJSON.document(try Self.document(game))
        #expect(Self.sha256(swift) == Self.javaDigests[name], "\(name)")
    }

    /// The digests of the whole trees match the trees, so the digests
    /// stand for the same documents.
    @Test(arguments: fullInputs)
    func fullTreeDigests(_ name: String) throws {
        let java = CanonicalJSON.document(try Self.javaDocument(name))
        #expect(Self.sha256(java) == Self.javaDigests[name])
    }

    // MARK: The writer

    @Test func escapingAndEmptyElements() {
        let xw = FreeColXMLWriter()
        xw.writeStartElement("a")
        xw.writeAttribute("q", "x\"<&>")
        xw.writeStartElement("b")
        xw.writeEndElement()
        xw.writeCharacters("1 < 2 & 3 > \"0\"")
        xw.writeEndElement()
        #expect(xw.xml == "<a q=\"x&quot;&lt;&amp;&gt;\"><b/>1 &lt; 2 &amp; 3 &gt; \"0\"</a>")
    }

    @Test func numbersAsJava() {
        let xw = FreeColXMLWriter()
        xw.writeStartElement("m")
        xw.writeAttribute("f", Float(50))
        xw.writeAttribute("g", Float(0.1))
        xw.writeAttribute("i", -3)
        xw.writeAttribute("b", true)
        xw.writeEndElement()
        #expect(xw.xml == "<m f=\"50.0\" g=\"0.1\" i=\"-3\" b=\"true\"/>")
    }
}

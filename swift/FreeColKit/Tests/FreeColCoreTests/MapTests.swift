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
import Testing

/// The map, tiles and regions read from the bundled maps and a recorded
/// game, compared with what Java computes (MapOracle.java).
@Suite(.serialized)
struct MapTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()
    static let mapsDirectory = ReferenceDumps.repositoryRoot.appendingPathComponent("data/maps")

    /// The recorded game: a generated map with units, cached tiles and
    /// its own specification.
    static let recordedGame = oracleDirectory.appendingPathComponent("games/freecol-seed1-turn005.fsg")

    /// The freecol rules, as Java's MapOracle loads them for maps.
    /// Shared, as in Java; the suite runs one test at a time.
    nonisolated(unsafe) static let freecol: Specification = {
        try! SpecificationTests.data.loadSpecification("freecol", difficulty: "model.difficulty.medium")
    }()

    /// The game with colonies, made by ColonyGameMaker.java.
    static let colonyGame = oracleDirectory.appendingPathComponent("games/freecol-colonies-seed1.fsg")

    /// The colony game with trade routes, sales and the rest of the
    /// economy, made by EconomyGameMaker.java.
    static let economyGame = oracleDirectory.appendingPathComponent("games/freecol-economy-seed1.fsg")

    /// The saved games kept with the tests.
    static let games = ["freecol-seed1-turn005.fsg", "freecol-colonies-seed1.fsg", "freecol-economy-seed1.fsg"]

    static func input(_ name: String) -> URL {
        name.hasSuffix(".fsm") ? mapsDirectory.appendingPathComponent(name)
            : oracleDirectory.appendingPathComponent("games/" + name)
    }

    static func read(_ name: String) throws -> SavedGame {
        try FreeColSavegameFile(url: input(name)).readGame(specification: freecol)
    }

    /// The Java digests: SHA-256 of each file's canonical dump.
    static let digests: [String: String] = {
        let url = oracleDirectory.appendingPathComponent("maps/digests.json")
        guard let json = try? JSONValue.parse(Data(contentsOf: url)),
              let members = json.objectValue else { return [:] }
        return members.compactMapValues(\.stringValue)
    }()

    /// The maps checked by digest.  A debug build takes 10 to 15
    /// seconds for a small map, so by default only two are checked;
    /// FREECOL_ALL_MAPS=1 checks every map, which is best done with
    /// `swift test -c release`.
    static let digestedMaps: [String] = {
        ProcessInfo.processInfo.environment["FREECOL_ALL_MAPS"] == "1"
            ? digests.keys.sorted()
            : ["S_AustraliaOceania_Gilolat.fsm", "S_FeudalJapan_Mazim.fsm"]
    }()

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Against Java

    /// Every value Java records for a small map and the recorded game
    /// matches, compared one by one so differences can be read.
    @Test(arguments: ["S_Caribbean_Phil.fsm"] + games)
    func mapMatchesJava(name: String) throws {
        let archive = try ZipArchive(contentsOf: Self.oracleDirectory.appendingPathComponent("maps/full.zip"))
        let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
        let saved = try Self.read(name)
        #expect(saved.warnings.isEmpty, "\(saved.warnings.prefix(5))")
        let diffs = elementDifferences(MapDerived.of(saved.game), java)
        // FREECOL_DIFF_FILE=path writes every difference, one per line.
        if let path = ProcessInfo.processInfo.environment["FREECOL_DIFF_FILE"], !diffs.isEmpty {
            try (diffs.joined(separator: "\n") + "\n").write(toFile: path + "." + name, atomically: true,
                                                            encoding: .utf8)
        }
        #expect(diffs.count == 0, "first: \(diffs.prefix(20).joined(separator: "\n"))")
    }

    /// The same values for every bundled map, compared by digest.
    @Test(arguments: digestedMaps)
    func mapDigestMatchesJava(name: String) throws {
        let saved = try Self.read(name)
        let document = CanonicalJSON.document(MapDerived.of(saved.game))
        #expect(Self.sha256(document) == Self.digests[name],
                "Run MapOracle on \(name) and diff its output with the Swift dump")
    }

    @Test func everyMapHasADigest() throws {
        let maps = try FileManager.default.contentsOfDirectory(atPath: Self.mapsDirectory.path)
            .filter { $0.hasSuffix(".fsm") }
        #expect(Set(maps).union(Self.games) == Set(Self.digests.keys))
    }

    // MARK: Reading

    @Test func readsSavedGameSettings() throws {
        let map = try Self.read("S_Caribbean_Phil.fsm")
        #expect(map.owner == "mapEditor")
        #expect(map.version == 14)
        #expect(!map.singlePlayer)
        #expect(map.serverRandom != nil)

        let game = try Self.read("freecol-seed1-turn005.fsg")
        // The recorded game carries its own specification.
        #expect(game.game.specification !== Self.freecol)
        #expect(game.game.specification?.id == "freecol")
        #expect(game.game.turn.number == 6)
        #expect(game.serverRandom != nil)
    }

    /// References resolve to the objects read, and the game keeps them
    /// alive: the registry is weak, so anything missing an owner would
    /// vanish.
    @Test func referencesResolve() throws {
        let game = try Self.read("S_Caribbean_Phil.fsm").game
        let map = try #require(game.map)
        let owned = map.tiles.filter { $0.owner != nil }
        #expect(!owned.isEmpty)
        for t in owned {
            #expect(game.players.contains { $0 === t.owner })
            #expect(t.owningSettlement != nil)
        }
        #expect(map.tiles.allSatisfy { $0.region != nil })
        #expect(map.tiles.filter { $0.settlement != nil }.count == 40)
        for t in map.tiles {
            #expect(game.getFreeColGameObject(t.id) === t)
            for item in t.tileItemContainer?.items ?? [] {
                #expect(item.tile === t)
                #expect(game.getFreeColGameObject(item.id) === item)
            }
        }
    }

    /// The game owns its objects: once the game is gone, so is
    /// everything in it.
    @Test func gameOwnsItsObjects() throws {
        weak var tile: Tile?
        weak var region: Region?
        weak var player: Player?
        weak var settlement: Settlement?
        do {
            let game = try Self.read("S_Caribbean_Phil.fsm").game
            tile = game.map?.tiles.first { $0.settlement != nil }
            settlement = tile?.settlement
            region = tile?.region
            player = game.players.first
        }
        #expect(tile == nil)
        #expect(region == nil)
        #expect(player == nil)
        #expect(settlement == nil)
    }

    @Test func badZipFails() throws {
        #expect(throws: ZipError.self) { try ZipArchive(data: Data("not a zip".utf8)) }
        var bytes = [UInt8](try Data(contentsOf: Self.input("S_Caribbean_Phil.fsm")))
        // Damage the compressed savegame.xml: its data starts after the
        // thumbnail and properties; flipping a byte deep inside breaks it.
        bytes[bytes.count / 2] ^= 0xff
        let archive = try ZipArchive(data: Data(bytes))
        #expect(throws: ZipError.self) { try archive.contents(of: FreeColSavegameFile.savegameFile) }
    }

    // MARK: Pieces

    @Test func directions() {
        #expect(Direction.n.step(5, 4) == Map.Position(5, 2))
        #expect(Direction.ne.step(5, 4) == Map.Position(5, 3))
        #expect(Direction.ne.step(5, 5) == Map.Position(6, 4))
        #expect(Direction.allDirections.allSatisfy { $0.reverseDirection.reverseDirection == $0 })
        #expect(Direction.nw.rotate(1) == .n)
        #expect(Direction.n.rotate(-1) == .nw)
        #expect(Direction(javaName: "sw") == .sw)
    }

    @Test func improvementStyles() {
        #expect(TileImprovementStyle("01020") == nil)
        #expect(TileImprovementStyle("0120")?.mask == "0110")
        #expect(TileImprovementStyle("10101010")?.mask == "10101010")
    }

    @Test func distances() {
        // Rows are staggered, so (0,0) and (0,1) are neighbours but
        // (0,0) and (1,1) are not.
        #expect(Map.Position(0, 0).distance(to: Map.Position(0, 1)) == 1)
        #expect(Map.Position(0, 0).distance(to: Map.Position(1, 1)) == 2)
        #expect(Map.Position(0, 0).distance(to: Map.Position(0, 2)) == 1)
        #expect(Map.Position(3, 7).direction(to: Map.Position(4, 6)) == .ne)
    }
}

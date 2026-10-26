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
import Testing

/// New games and their maps, compared with Java making them from the
/// same seed and options (MapGenOracle.java): the land, then the
/// terrain, regions, rivers, lakes and bonuses must be Java's, and the
/// generator left where Java's was.
@Suite(.serialized)
struct MapGenTests {

    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent()
    static let data = FreeColDataDirectory(url: ReferenceDumps.repositoryRoot.appendingPathComponent("data"))

    /// Java's recordings; FREECOL_MAPGEN names a directory of json files
    /// to use instead of the archive.
    static func recorded(_ name: String, _ key: String) throws -> [JSONValue] {
        let java: JSONValue
        if let dir = ProcessInfo.processInfo.environment["FREECOL_MAPGEN"] {
            java = try JSONValue.parse(try Data(contentsOf: URL(fileURLWithPath: dir)
                .appendingPathComponent(name + ".json")))
        } else {
            let archive = try ZipArchive(contentsOf: oracleDirectory.appendingPathComponent("mapgen.zip"))
            java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
        }
        return try #require(java[key]?.arrayValue)
    }

    /// The rules, with a recording's map generator options.
    static func specification(_ expected: JSONValue) throws -> Specification {
        let spec = try data.loadSpecification("freecol", difficulty: "model.difficulty.medium")
        if case .object(let options)? = expected["options"] {
            for (id, value) in options {
                if case .bool(let b) = value { spec.setBoolean(id, b) } else {
                    spec.setInteger(id, Int(try #require(value.intValue)))
                }
            }
        }
        return spec
    }

    /// Whole new games, for a human Dutch player: the other nations'
    /// players, the map with native settlements, lost city rumours and
    /// the Europeans' units, and each player's starting gold, recruits
    /// and prices.
    @Test func newGames() throws {
        let games = try Self.recorded("newgames", "games")
        #expect(games.count == 3)
        try Messages.$scopedBundle.withValue(ColonyTurnTests.english) {
            for expected in games {
                let name = expected["name"]?.stringValue ?? "?"
                let spec = try Self.specification(expected)
                let random = JavaRandom(seed: try #require(expected["seed"]?.intValue))
                let game = ServerGame.startNewGame(spec, random, playerName: "Player")
                var diffs = XmlTree.differences(try NewTurnTests.saveTree(game), expected["save"] ?? .null, "save",
                                                limit: 30)
                if random.serializedState != expected["random"]?.stringValue { diffs.append("random differs") }
                if !diffs.isEmpty {
                    Issue.record(Comment(rawValue: "\(name):\n" + diffs.prefix(30).joined(separator: "\n")))
                }
            }
        }
    }

    /// The land generator types, temperatures and sizes, each a seed.
    @Test func terrain() throws {
        let maps = try Self.recorded("mapgen", "maps")
        #expect(maps.count == 5)
        try Messages.$scopedBundle.withValue(ColonyTurnTests.english) {
            for expected in maps {
                let name = expected["name"]?.stringValue ?? "?"
                let spec = try Self.specification(expected)
                let random = JavaRandom(seed: try #require(expected["seed"]?.intValue))
                let game = ServerGame.newGame(spec, random)
                let cache = RandomUtils.RandomIntCache("simpleMap", random, range: 1 << 16, size: 512)
                let landMap = LandMap(options: spec, cache: cache)
                var land = ""
                for y in 0..<landMap.height {
                    for x in 0..<landMap.width { land += landMap.isLand(x, y) ? "#" : "." }
                    land += "\n"
                }
                if land != expected["land"]?.stringValue {
                    Issue.record(Comment(rawValue: "\(name): land differs"))
                    continue
                }
                if random.serializedState != expected["randomAfterLand"]?.stringValue {
                    Issue.record(Comment(rawValue: "\(name): random differs after the land"))
                    continue
                }
                TerrainGenerator(random).generateMap(game, landMap)
                var diffs = XmlTree.differences(try NewTurnTests.saveTree(game), expected["save"] ?? .null, "save",
                                                limit: 30)
                if random.serializedState != expected["random"]?.stringValue { diffs.append("random differs") }
                if !diffs.isEmpty {
                    Issue.record(Comment(rawValue: "\(name):\n" + diffs.prefix(30).joined(separator: "\n")))
                }
            }
        }
    }
}

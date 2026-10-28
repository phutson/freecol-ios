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
@testable import FreeColEngine
import FreeColIO
import FreeColMap
import FreeColResources
import FreeColServer
import FreeColTestSupport
import FreeColUtil
import Testing

/// The map's images for a player's view of a saved game, compared with
/// the images Java's client would draw (MapImageOracle.java): each
/// tile's base terrain, unexplored edges, hills and mountains, forest,
/// other items, settlement and unit in front, by key and variation.
@Suite struct MapSceneTests {

    static let root = ReferenceDumps.repositoryRoot
    static let oracle = JavaOracle.url.deletingLastPathComponent()

    static let english: MessageBundle = {
        let data = root.appendingPathComponent("data")
        let strings = data.appendingPathComponent("strings")
        let numberRules = try! NumberRules(data: Data(contentsOf: strings.appendingPathComponent("plurals.xml")))
        return MessageBundle.load(directory: strings, languageId: "en_US", numberRules: numberRules,
                                  rulesDirectories: ["classic", "freecol"].map {
                                      data.appendingPathComponent("rules/" + $0)
                                  })
    }()

    /// The images as Java's client loads them: the base data, then the
    /// default rules' images.
    nonisolated(unsafe) static let images: ResourceMapImages = {
        let data = root.appendingPathComponent("data")
        let manager = ResourceManager()
        manager.setBase(try! FreeColDataFile(directory: data.appendingPathComponent("base"))
            .resourceMapping(languageId: "en_US")!)
        manager.setTc(try! FreeColTcFile.resourceMapping(dataDirectory: data, id: "default", languageId: "en_US"))
        return ResourceMapImages(manager)
    }()

    /// A tile's images as the oracle records them.
    struct TileImages: Equatable, CustomStringConvertible {
        var terrain: [String] = []
        var borders: [[String]] = []
        var overlay: [String]?
        var forest: [String]?
        var items: [[String]] = []
        var settlement: String?
        var unit: String?

        var description: String {
            "terrain \(terrain) borders \(borders) overlay \(overlay ?? []) forest \(forest ?? [])"
                + " items \(items) settlement \(settlement ?? "-") unit \(unit ?? "-")"
        }
    }

    static func pair(_ v: JSONValue?) -> [String]? {
        guard let a = v?.arrayValue, a.count == 2 else { return nil }
        return [a[0].stringValue ?? "", String(a[1].intValue ?? -9)]
    }

    /// What the plan draws on each tile, in the oracle's terms.
    static func ours(_ draws: [MapDraw]) -> [String: TileImages] {
        var ret: [String: TileImages] = [:]
        for d in draws {
            guard case let .image(img, _, _, _) = d.drawing else { continue }
            let k = "\(d.x),\(d.y)"
            var t = ret[k] ?? TileImages()
            let p = [img.key, String(img.variation)]
            if t.terrain.isEmpty {
                t.terrain = p
            } else if img.key.hasPrefix("image.tile.model.tile.unexplored.border.") {
                t.borders.append(p)
            } else if img.key.hasPrefix("image.tileoverlay.") {
                t.overlay = p
            } else if img.key.hasPrefix("image.tileforest.") {
                t.forest = p
            } else if img.key.hasPrefix("image.tileitem.model.settlement.") {
                t.settlement = img.key
            } else if img.key.hasPrefix("image.unit.") {
                t.unit = img.key
            } else if img.key.hasPrefix("image.tile.model.improvement.river.") || img.key.hasPrefix("image.abovetile.") {
                continue
            } else {
                t.items.append(p)
            }
            ret[k] = t
        }
        return ret
    }

    @Test(arguments: [("commands-dutch", "freecol-commands-seed1.fsg", "model.nation.dutch"),
                      ("unitai-english", "freecol-unitai-seed1.fsg", "model.nation.english"),
                      ("unitai-french", "freecol-unitai-seed1.fsg", "model.nation.french"),
                      ("unitai-spanish", "freecol-unitai-seed1.fsg", "model.nation.spanish")])
    func tileImagesAsJava(_ name: String, _ file: String, _ nation: String) throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let archive = try ZipArchive(contentsOf: Self.oracle.appendingPathComponent("mapimages.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: Self.oracle.appendingPathComponent("games/" + file))
                .readServerGame()
            let game = try #require(saved.game as? ServerGame)
            let player = try #require(game.livePlayers.first { $0.nationId == nation })
            let snapshot = SnapshotBuilder(game: game, player: player).build()
            let map = snapshot.map
            let ours = Self.ours(MapScene.plan(snapshot, Self.images, columns: 0..<map.width, rows: 0..<map.height))
            var diffs: [String] = []
            for t in try #require(java["tiles"]?.arrayValue) {
                let x = t["x"]?.intValue ?? -1, y = t["y"]?.intValue ?? -1
                var expected = TileImages()
                expected.terrain = Self.pair(t["terrain"]) ?? []
                expected.borders = (t["borders"]?.arrayValue ?? []).compactMap { Self.pair($0) }
                expected.overlay = Self.pair(t["overlay"])
                expected.forest = Self.pair(t["forest"])
                expected.items = (t["items"]?.arrayValue ?? []).compactMap { Self.pair($0) }
                expected.settlement = t["settlement"]?.stringValue
                expected.unit = t["unit"]?.stringValue
                let got = ours["\(x),\(y)"] ?? TileImages()
                if got != expected { diffs.append("tile \(x),\(y):\n  java: \(expected)\n  ours: \(got)") }
            }
            #expect(diffs.isEmpty, Comment(rawValue: "\(diffs.count) tiles differ:\n"
                                               + diffs.prefix(10).joined(separator: "\n")))
        }
    }

    /// Every image the plan names exists, so the screen can draw it.
    @Test func everyImageExists() throws {
        try Messages.$scopedBundle.withValue(Self.english) {
            let saved = try FreeColSavegameFile(url: Self.oracle.appendingPathComponent("games/freecol-unitai-seed1.fsg"))
                .readServerGame()
            let game = try #require(saved.game as? ServerGame)
            for player in game.livePlayers where player.isEuropean {
                let snapshot = SnapshotBuilder(game: game, player: player).build()
                let draws = MapScene.plan(snapshot, Self.images, columns: 0..<snapshot.map.width,
                                          rows: 0..<snapshot.map.height)
                let missing = Set(draws.compactMap { d -> String? in
                    guard case let .image(img, _, _, _) = d.drawing else { return nil }
                    return Self.images.hasImage(img.key) ? nil : img.key
                })
                #expect(missing.isEmpty, "\(player.nationId ?? ""): \(missing.sorted())")
            }
        }
    }
}

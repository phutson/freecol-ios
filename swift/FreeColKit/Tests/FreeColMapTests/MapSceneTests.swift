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
/// the images Java's client would draw: pass by pass, every image and
/// generated picture by Java's caching key and variation
/// (MapLayerOracle.java), and each settlement and unit in front
/// (MapImageOracle.java).
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

    /// The settlement and the unit in front the plan draws on each tile.
    static func ours(_ draws: [MapDraw]) -> [String: (settlement: String?, unit: String?)] {
        var ret: [String: (settlement: String?, unit: String?)] = [:]
        for d in draws {
            guard case let .image(img, _, _, _, _) = d.drawing else { continue }
            let k = "\(d.x),\(d.y)"
            if d.pass == .units {
                ret[k, default: (nil, nil)].unit = img.key
            } else if d.pass == .items && img.key.hasPrefix("image.tileitem.model.settlement.") {
                ret[k, default: (nil, nil)].settlement = img.key
            }
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
                // The terrain and items are checked pass by pass
                // (layersAsJava); here the settlement and unit.
                let got = ours["\(x),\(y)"] ?? (nil, nil)
                let expected = (t["settlement"]?.stringValue, t["unit"]?.stringValue)
                if got.settlement != expected.0 || got.unit != expected.1 {
                    diffs.append("tile \(x),\(y): java \(expected), ours \(got)")
                }
            }
            #expect(diffs.isEmpty, Comment(rawValue: "\(diffs.count) tiles differ:\n"
                                               + diffs.prefix(10).joined(separator: "\n")))
        }
    }

    /// A caching key without where the data is: "file:data/...".
    static func normalized(_ key: String) -> String {
        key.replacingOccurrences(of: "file:[^,]*?/data/", with: "file:data/", options: .regularExpression)
    }

    /// Each tile's draws, pass by pass, by Java's caching key and
    /// variation, as the layer oracle records them.
    static func layers(_ draws: [MapDraw], _ images: MapImages) -> [String: [String: [[String]]]] {
        var ret: [String: [String: [[String]]]] = [:]
        for d in draws {
            let entry: [String]
            switch d.drawing {
            case let .image(img, _, _, _, _):
                if img.key.hasPrefix("image.tileitem.model.settlement.") || d.pass == .units || d.pass == .above {
                    continue
                }
                entry = [normalized(images.cachingKey(img.key) ?? img.key), String(img.variation)]
            case let .composite(c, _):
                entry = [normalized(c.key), String(c.variation)]
            case let .path(segments, color, width):
                // Compared with Java's road painter's shapes.
                var e = [String(color), String(width)]
                for s in segments {
                    switch s {
                    case let .move(x, y): e += ["0", "\(x)", "\(y)"]
                    case let .line(x, y): e += ["1", "\(x)", "\(y)"]
                    case let .quad(cx, cy, x, y): e += ["2", "\(cx)", "\(cy)", "\(x)", "\(y)"]
                    }
                }
                // Roads are drawn with the items, and opaque borders in
                // their own pass.
                let key = d.pass == .items ? "roads" : d.pass == .territory ? "territory" : nil
                if let key { ret["\(d.x),\(d.y)", default: [:]][key, default: []].append(e) }
                continue
            case .fog, .chips, .text, .line, .rectangle, .pathStep, .pathNode:
                continue
            }
            ret["\(d.x),\(d.y)", default: [:]][d.pass.rawValue, default: []].append(entry)
        }
        return ret
    }

    /// The shapes Java recorded on a tile (roads, or borders): colour,
    /// width, and each segment's type (0 move, 1 line, 2 quad) and
    /// points.
    static func number(_ v: JSONValue?) -> Double {
        switch v {
        case let .integer(i): Double(i)
        case let .decimal(d): d
        default: .nan
        }
    }

    static func javaShapes(_ t: JSONValue, _ key: String) -> [[String]] {
        var ret: [[String]] = []
        for shape in t[key]?.arrayValue ?? [] {
            let color = Int32(truncatingIfNeeded: Int64(number(shape["color"])))
            var e: [String] = [String(color), "\(Float(number(shape["width"])))"]
            for seg in shape["segments"]?.arrayValue ?? [] {
                let a: [JSONValue] = seg.arrayValue ?? []
                e.append(String(Int(number(a.first))))
                for v in a.dropFirst() { e.append("\(Float(number(v)))") }
            }
            ret.append(e)
        }
        return ret
    }

    /// Java's fonts by the names the plan gives them (Java falls back
    /// on its logical fonts, Dialog and Serif).
    static let javaFonts = ["Dialog-1-12": "simple-bold-tiny", "Dialog-3-14": "simple-bold+italic-smaller",
                            "Serif-1-14": "normal-bold-smaller"]

    /// A chip, text, line or rectangle Java drew, as the layer oracle
    /// records it.
    static func javaMark(_ m: JSONValue) -> String {
        func i(_ k: String) -> String { String(m[k]?.intValue ?? -9) }
        let kind = m["kind"]?.stringValue ?? "", text = m["text"]?.stringValue ?? ""
        let font = javaFonts[m["font"]?.stringValue ?? ""] ?? m["font"]?.stringValue ?? ""
        switch kind {
        case "chip": return "chip \(text) \(i("background")) \(i("foreground")) \(font) \(i("x")),\(i("y"))"
        case "string": return "string \(text) \(i("foreground")) \(font) \(i("x")),\(i("y"))"
        default: return "\(kind) \(i("color")) \(i("x")),\(i("y")) \(i("x2")),\(i("y2"))"
        }
    }

    /// The same of the plan's draws on a tile.  Where chips and text go
    /// depends on their size, which depends on the fonts, so they are
    /// placed by the sizes Java's are, in order.
    static func ourMarks(_ draws: [MapDraw], sizes: [(w: Int, h: Int)]) -> [String] {
        var sizes = sizes[...]
        var ret: [String] = []
        for d in draws {
            switch d.drawing {
            case let .chips(chips, x, y, _):
                let step = (sizes.first?.w ?? 0) + 2
                for (n, c) in chips.enumerated() {
                    sizes = sizes.dropFirst()
                    ret.append("chip \(c.text) \(c.background) \(c.foreground) \(MapChip.font) \(x + n * step),\(y)")
                }
            case let .text(text, placement, _):
                let size = sizes.popFirst() ?? (0, 0)
                let at = placement.origin(width: size.w, height: size.h)
                ret.append("string \(text.text) \(text.color) \(text.font) \(at.x),\(at.y)")
            case let .line(x1, y1, x2, y2, color):
                ret.append("line \(color) \(x1),\(y1) \(x2),\(y2)")
            case let .rectangle(x, y, w, h, color, filled):
                ret.append("\(filled ? "fillRect" : "drawRect") \(color) \(x),\(y) \(x + w),\(y + h)")
            default:
                continue
            }
        }
        return ret
    }

    /// The views recorded: players' views of saved games, three of them
    /// with other graphics options: the highest quality (mask
    /// variations and forest corners) without animations (rivers and
    /// their mouths with the items), high, and with borders.
    @Test(arguments: ["commands-dutch", "unitai-english", "unitai-french", "unitai-spanish",
                      "unitai-english-highest-still", "unitai-french-high", "unitai-spanish-borders",
                      "natives-dutch", "combat-dutch", "marks-dutch"])
    func layersAsJava(_ name: String) throws {
        let parts = name.split(separator: "-").map(String.init)
        let file = "freecol-\(parts[0])-seed1.fsg", nation = "model.nation." + parts[1]
        var options = MapOptions()
        if parts.contains("highest") { options.graphicsQuality = 40 }
        if parts.contains("high") { options.graphicsQuality = 30 }
        if parts.contains("still") { options.useTerrainAnimations = false }
        if parts.contains("borders") {
            options.displayBorders = true
            options.displayTileText = 3
        }
        try Messages.$scopedBundle.withValue(Self.english) {
            let archive = try ZipArchive(contentsOf: Self.oracle.appendingPathComponent("maplayers.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: Self.oracle.appendingPathComponent("games/" + file))
                .readServerGame()
            let game = try #require(saved.game as? ServerGame)
            let player = try #require(game.livePlayers.first { $0.nationId == nation })
            let snapshot = SnapshotBuilder(game: game, player: player).build()
            let map = snapshot.map
            let draws = MapScene.plan(snapshot, Self.images, options, columns: 0..<map.width, rows: 0..<map.height)
            let ours = Self.layers(draws, Self.images)
            let byTile = Dictionary(grouping: draws) { "\($0.x),\($0.y)" }
            var diffs: [String] = []
            for t in try #require(java["tiles"]?.arrayValue) {
                let x = t["x"]?.intValue ?? -1, y = t["y"]?.intValue ?? -1
                // Settlement chips and numbers are drawn with the items,
                // a unit's with the unit, and names last.
                for (key, pass) in [("chips", MapPass.items), ("unit", .units), ("label", .labels)] {
                    let marks = t[key]?.arrayValue ?? []
                    let expected = marks.map(Self.javaMark)
                    let sizes = marks.filter { $0["w"] != nil }.map { (w: Int($0["w"]?.intValue ?? 0), h: Int($0["h"]?.intValue ?? 0)) }
                    let got = Self.ourMarks((byTile["\(x),\(y)"] ?? []).filter { $0.pass == pass }, sizes: sizes)
                    if got != expected {
                        diffs.append("tile \(x),\(y) \(key):\n  java: \(expected)\n  ours: \(got)")
                    }
                }
                for key in ["roads", "territory"] {
                    let shapes = Self.javaShapes(t, key)
                    let ourShapes = ours["\(x),\(y)"]?[key] ?? []
                    if ourShapes != shapes {
                        diffs.append("tile \(x),\(y) \(key):\n  java: \(shapes)\n  ours: \(ourShapes)")
                    }
                }
                for pass in ["animated", "base", "transitions", "borders", "items"] {
                    let expected = (t[pass]?.arrayValue ?? []).map { r -> [String] in
                        let a = r.arrayValue ?? []
                        return [Self.normalized(a.first?.stringValue ?? ""), String(a.last?.intValue ?? -9)]
                    }
                    let got = ours["\(x),\(y)"]?[pass] ?? []
                    if got != expected {
                        diffs.append("tile \(x),\(y) \(pass):\n  java: \(expected)\n  ours: \(got)")
                    }
                }
            }
            #expect(diffs.isEmpty, Comment(rawValue: "\(diffs.count) differ:\n" + diffs.prefix(8).joined(separator: "\n")))
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
                func keys(_ p: MapPicture) -> [String] {
                    switch p {
                    case let .image(img): return [img.key]
                    case let .masked(a, b): return keys(a) + keys(b)
                    case let .layers(ls): return ls.flatMap { keys($0.picture) }
                    case let .enlarged(a): return keys(a)
                    }
                }
                let missing = Set(draws.flatMap { d -> [String] in
                    switch d.drawing {
                    case let .image(img, _, _, _, _): return [img.key]
                    case let .composite(c, _): return keys(c.picture)
                    case .path, .fog, .chips, .text, .line, .rectangle, .pathStep, .pathNode: return []
                    }
                }.filter { !Self.images.hasImage($0) })
                #expect(missing.isEmpty, "\(player.nationId ?? ""): \(missing.sorted())")
            }
        }
    }
}

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
import FreeColServer
import FreeColTestSupport
import Testing

/// What the colony panel shows and decides, on the player's copy of
/// the game, against Java's (ColonyOracle.java).
@Suite struct ColonyViewTests {

    /// The views ColonyOracle recorded: a saved game and the player's
    /// nation.
    static let views = ["commands-dutch", "aisave-units-dutch", "colonyai-english", "colonyai-french",
                        "colonyai-spanish", "aisave-seed11-english", "unitai-spanish", "colonypanel-dutch"]

    static func gameFile(_ game: String) -> String {
        game.hasPrefix("aisave") ? "freecol-\(game).fsg" : "freecol-\(game)-seed1.fsg"
    }

    static func ints(_ v: JSONValue?) -> [Int] { (v?.arrayValue ?? []).map { Int($0.intValue ?? -9) } }
    static func strings(_ v: JSONValue?) -> [String] { (v?.arrayValue ?? []).map { $0.stringValue ?? "" } }

    /// Our colony screen, section by section, as lines.
    static func ours(_ s: ColonyScreen) -> [String: [String]] {
        var r: [String: [String]] = [:]
        r["population"] = [s.unitCount, s.sonsOfLiberty, s.rebels, s.bonus, s.sizeChange, s.warehouseCapacity]
            .map(String.init)
        r["buildings"] = s.buildings.map { b -> String in
            if let site = b.site { return "site \(site)" }
            var e = "\(b.id ?? "") \(b.typeId ?? "") \(b.unitIds)"
            if let o = b.output { e += " \(o.typeId) \(o.amount)/\(o.maximum)" }
            if let u = b.upkeep { e += " upkeep \(u)" }
            return e
        }
        r["tiles"] = s.tiles.map { t -> String in
            let made = t.made.map { m -> String in m.map { "\($0.typeId) \($0.amount)" } ?? "-" }
            let centre = t.centre.map { "\($0.typeId) \($0.amount)" }
            return "\(t.id) \(t.position.x),\(t.position.y) \(t.unitIds) "
                + made.joined(separator: ",") + " " + centre.joined(separator: ",")
        }
        r["net"] = s.net.map { "\($0.typeId) \($0.amount)" }.sorted()
        r["warehouse"] = s.warehouse.map { "\($0.typeId) \($0.amount)" }.sorted()
        r["building"] = [s.building ?? "-"]
        r["needs"] = s.needs.map { "\($0.typeId) \($0.needed) \($0.held) \($0.net)" }
        r["queue"] = s.queue
        r["buildingChoices"] = s.buildingChoices.map { "\($0.typeId) \($0.locked ?? "-")" }
        r["unitChoices"] = s.unitChoices.map { "\($0.typeId) \($0.locked ?? "-")" }
        r["places"] = s.places.map { p -> String in
            let at = p.places.map { w -> String in
                "\(w.workLocationId) \(w.noAddReason) \(w.workTypeId ?? "-") \(w.claimReason ?? "-")"
            }
            return "\(p.unitId): " + at.joined(separator: "; ")
        }
        return r
    }

    static func str(_ v: JSONValue?) -> String { v?.stringValue ?? "-" }
    static func int(_ v: JSONValue?) -> String { v?.intValue.map { String($0) } ?? "-" }

    /// Java's colony panel, section by section, as lines.
    static func javas(_ c: JSONValue) -> [String: [String]] {
        var r: [String: [String]] = [:]
        r["population"] = ["units", "sonsOfLiberty", "rebels", "bonus", "sizeChange", "warehouseCapacity"]
            .map { int(c[$0]) }
        r["buildings"] = (c["buildings"]?.arrayValue ?? []).map { b -> String in
            if let site = b["site"]?.stringValue { return "site \(site)" }
            var e = "\(str(b["id"])) \(str(b["type"])) \(strings(b["units"]))"
            if let o = b["output"]?.arrayValue { e += " \(str(o[0])) \(int(o[1]))/\(int(o[2]))" }
            if let u = b["upkeep"]?.intValue { e += " upkeep \(u)" }
            return e
        }
        r["tiles"] = (c["tiles"]?.arrayValue ?? []).map { t -> String in
            let made = (t["made"]?.arrayValue ?? []).map { m -> String in
                m.arrayValue.map { "\(str($0[0])) \(int($0[1]))" } ?? "-"
            }
            let centre = (t["centre"]?.arrayValue ?? []).map { g -> String in
                let a = g.arrayValue ?? []
                return "\(str(a[0])) \(int(a[1]))"
            }
            return "\(str(t["id"])) \(int(t["x"])),\(int(t["y"])) \(strings(t["units"])) "
                + made.joined(separator: ",") + " " + centre.joined(separator: ",")
        }
        r["net"] = (c["net"]?.objectValue ?? [:]).map { "\($0.key) \(int($0.value))" }.sorted()
        r["warehouse"] = (c["warehouse"]?.objectValue ?? [:]).map { "\($0.key) \(int($0.value))" }.sorted()
        r["building"] = [str(c["building"])]
        r["needs"] = (c["needs"]?.arrayValue ?? []).map { n -> String in
            let a = n.arrayValue ?? []
            return "\(str(a[0])) \(int(a[1])) \(int(a[2])) \(int(a[3]))"
        }
        r["queue"] = strings(c["queue"])
        for key in ["buildingChoices", "unitChoices"] {
            r[key] = (c[key]?.arrayValue ?? []).map { "\(str($0["type"])) \(str($0["locked"]))" }
        }
        r["places"] = (c["places"]?.arrayValue ?? []).map { p -> String in
            let at = (p["at"]?.arrayValue ?? []).map { w -> String in
                let a = w.arrayValue ?? []
                let claim = a.count > 3 ? str(a[3]) : "-"
                return "\(str(a[0])) \(str(a[1])) \(str(a[2])) \(claim)"
            }
            return "\(str(p["unit"])): " + at.joined(separator: "; ")
        }
        return r
    }

    @Test(arguments: views)
    func showsAsJava(_ name: String) throws {
        let cut = name.lastIndex(of: "-")!
        let game = String(name[..<cut]), nation = String(name[name.index(after: cut)...])
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let archive = try ZipArchive(contentsOf: PlayerViewTests.oracle.appendingPathComponent("colonies.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: PlayerViewTests.oracle.appendingPathComponent(
                "games/" + Self.gameFile(game))).readServerGame()
            let server = try #require(saved.game as? ServerGame)
            let serverPlayer = try #require(server.livePlayers.first { $0.nationId == "model.nation." + nation })
            let view = try PlayerView(of: server, for: serverPlayer)
            let colonies = try #require(java["colonies"]?.arrayValue)
            #expect(!colonies.isEmpty)
            var diffs: [String] = []
            for c in colonies {
                let id = c["id"]?.stringValue ?? ""
                guard let colony = view.game.getFreeColGameObject(id, as: Colony.self),
                      let s = view.colonyScreen(colony) else {
                    diffs.append("\(id): no colony")
                    continue
                }
                let ours = Self.ours(s), theirs = Self.javas(c)
                for key in theirs.keys.sorted() where ours[key] != theirs[key] {
                    let o = ours[key] ?? [], t = theirs[key] ?? []
                    let i = Array(zip(o, t)).firstIndex { $0 != $1 } ?? min(o.count, t.count)
                    diffs.append("\(s.name) \(key) [\(i)]: ours \(i < o.count ? o[i] : "none"), "
                                 + "Java's \(i < t.count ? t[i] : "none")")
                }
            }
            #expect(diffs.isEmpty, Comment(rawValue: "\(name):\n" + diffs.joined(separator: "\n")))
        }
    }
}

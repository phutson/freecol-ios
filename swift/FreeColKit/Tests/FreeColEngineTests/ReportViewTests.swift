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

/// What the reports show, on the player's copy of the game, against
/// Java's (ReportOracle.java).
@Suite struct ReportViewTests {

    static let views = ["commands-dutch": "freecol-commands-seed1.fsg", "europe-dutch": "freecol-europe-seed1.fsg",
                        "fathers-dutch": "freecol-turncycle-fathers-seed1.fsg",
                        "colonyai-english": "freecol-colonyai-seed1.fsg", "combat-dutch": "freecol-combat-seed1.fsg",
                        "monarch-french": "freecol-turncycle-monarch-seed1.fsg"]

    static func str(_ v: JSONValue?) -> String {
        if let i = v?.intValue { return String(i) }
        return v?.stringValue ?? "-"
    }
    static func row(_ v: JSONValue?) -> String { (v?.arrayValue ?? []).map { str($0) }.joined(separator: " ") }

    static func ours(_ c: CongressReport, _ r: [ReligionReport], _ m: UnitReport, _ n: UnitReport) -> [String: [String]] {
        var ret: [String: [String]] = [:]
        ret["congress"] = ["\(c.currentId ?? "-") \(c.liberty) \(c.cost)"]
            + c.production.map { "\($0.typeId) \($0.amount)" } + c.fathers.map { "\($0.id) \($0.type) \($0.state)" }
        ret["religion"] = r.map { "\($0.typeId) \($0.required) \($0.immigration) \($0.production) "
            + $0.colonies.map { "\($0.colonyId) \($0.buildingTypeId)" }.joined(separator: ", ") }
        for (key, u) in [("military", m), ("naval", n)] {
            ret[key] = u.forces.map { "\($0.typeId) \($0.roleId) \($0.number)" }
                + ["ref"] + u.ref.map { "\($0.typeId) \($0.roleId) \($0.number)" }
                + u.places.map { "\($0.name): \($0.unitIds.joined(separator: " "))" }
        }
        return ret
    }

    static func javas(_ d: JSONValue) -> [String: [String]] {
        var ret: [String: [String]] = [:]
        let c = d["congress"]
        ret["congress"] = ["\(str(c?["current"])) \(str(c?["liberty"])) \(str(c?["cost"]))"]
            + (c?["production"]?.arrayValue ?? []).map { row($0) } + (c?["fathers"]?.arrayValue ?? []).map { row($0) }
        ret["religion"] = (d["religion"]?.arrayValue ?? []).map { r in
            "\(str(r["type"])) \(str(r["required"])) \(str(r["immigration"])) \(str(r["production"])) "
                + (r["colonies"]?.arrayValue ?? []).map { row($0) }.joined(separator: ", ")
        }
        for key in ["military", "naval"] {
            let u = d[key]
            let forces: [String] = (u?["forces"]?.arrayValue ?? []).map { row($0) }
            let ref: [String] = (u?["ref"]?.arrayValue ?? []).map { row($0) }
            let places: [String] = (u?["places"]?.arrayValue ?? []).map { p -> String in
                let a = p.arrayValue ?? []
                let ids: [String] = (a[1].arrayValue ?? []).map { str($0) }
                return str(a[0]) + ": " + ids.joined(separator: " ")
            }
            ret[key] = forces + ["ref"] + ref + places
        }
        return ret
    }

    @Test(arguments: views.keys.sorted())
    func showsAsJava(_ name: String) throws {
        let nation = String(name[name.index(after: name.lastIndex(of: "-")!)...])
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let archive = try ZipArchive(contentsOf: PlayerViewTests.oracle.appendingPathComponent("reports.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: PlayerViewTests.oracle.appendingPathComponent(
                "games/" + Self.views[name]!)).readServerGame()
            let server = try #require(saved.game as? ServerGame)
            let serverPlayer = try #require(server.livePlayers.first { $0.nationId == "model.nation." + nation })
            let view = try PlayerView(of: server, for: serverPlayer)
            let ours = Self.ours(view.congressReport(), view.religionReport(), view.unitReport(military: true),
                                 view.unitReport(military: false))
            let theirs = Self.javas(java)
            var diffs: [String] = []
            for key in theirs.keys.sorted() where ours[key] != theirs[key] {
                let o = ours[key] ?? [], t = theirs[key] ?? []
                let i = Array(zip(o, t)).firstIndex { $0 != $1 } ?? min(o.count, t.count)
                diffs.append("\(key) [\(i)]: ours \(i < o.count ? o[i] : "none"), Java's \(i < t.count ? t[i] : "none")")
            }
            #expect(diffs.isEmpty, Comment(rawValue: "\(name):\n" + diffs.joined(separator: "\n")))
        }
    }
}

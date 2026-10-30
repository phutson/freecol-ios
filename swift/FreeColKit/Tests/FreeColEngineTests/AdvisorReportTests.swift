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

/// What the remaining reports show, on the player's copy of the game,
/// against Java's (AdvisorOracle.java).
@Suite struct AdvisorReportTests {

    static let views = ["commands-dutch": "freecol-commands-seed1.fsg", "europe-dutch": "freecol-europe-seed1.fsg",
                        "natives-dutch": "freecol-natives-seed1.fsg", "diplomacy-dutch": "freecol-diplomacy-seed1.fsg",
                        "colonypanel-dutch": "freecol-colonypanel-seed1.fsg",
                        "fathers-dutch": "freecol-turncycle-fathers-seed1.fsg",
                        "aisave-dutch": "freecol-aisave-units.fsg",
                        "colonyai-english": "freecol-colonyai-seed1.fsg"]

    static func j(_ parts: Any?...) -> String {
        parts.map { p -> String in
            guard let p else { return "-" }
            if let o = p as? Int? { return o.map(String.init) ?? "-" }
            if let o = p as? String? { return o ?? "-" }
            return "\(p)"
        }.joined(separator: "|")
    }

    static func ours(_ v: PlayerView, _ server: ServerGame, _ human: Player) -> [String: [String]] {
        let summary: (String) -> NationSummary? = { id in
            (server.getFreeColGameObject(id) as? Player).map { NationSummary($0, human) }
        }
        var r: [String: [String]] = [:]
        let cargo = v.unitReport(.cargo)
        r["cargo"] = cargo.forces.map { j($0.typeId, $0.roleId, $0.number) }
            + cargo.places.map { j($0.name, $0.unitIds.joined(separator: " ")) }
        r["education"] = v.educationReport().map {
            j($0.colonyId, $0.buildingName, $0.teacherIds.joined(separator: " "),
              $0.students.map { "\($0.unitId) \($0.learning)" }.joined(separator: ", "))
        }
        r["exploration"] = v.explorationReport().map { j($0.name, $0.typeName, $0.discoveredIn, $0.discoveredBy, $0.value) }
        r["foreign"] = v.foreignReport(summary: summary).map {
            j($0.country, $0.stance, $0.settlements, $0.units, $0.military, $0.naval, $0.gold,
              $0.fathers, $0.tax, $0.sonsOfLiberty)
        }
        r["history"] = v.historyReport().map { j($0.turn, $0.text) }
        r["natives"] = v.nativesReport(summary: summary).flatMap { n in
            [j(n.nation, n.chieftain, n.settlementType, n.numberOfSettlements, n.tension)] + n.settlements.map {
                j($0.id, $0.name, $0.mission, $0.alarm, $0.skill, $0.mostHated, $0.wanted.joined(separator: ", "))
            }
        }
        let t = v.tradeReport()
        var trade = t.goodsTypeIds.indices.map {
            j(t.goodsTypeIds[$0], t.sold[$0], t.beforeTaxes[$0], t.afterTaxes[$0], t.cargo[$0], t.total[$0], t.delta[$0])
        }
        for c in t.colonies {
            trade.append("\(c.id) \(c.name)")
            trade += t.goodsTypeIds.indices.map {
                j(t.goodsTypeIds[$0], c.stock[$0], c.production[$0], c.exports[$0], c.warnings[$0])
            }
        }
        r["trade"] = trade
        r["requirements"] = v.requirementsReport().flatMap { ["\($0.colonyId) \($0.colonyName)"] + $0.lines }
        let goods = v.productionGoods.compactMap(\.id)
        r["production"] = goods.flatMap { id -> [String] in
            let p = v.productionReport([id])
            guard let c = p.columns.first else { return [] }
            return ["\(id) " + c.buildingTypeIds.joined(separator: " ")] + p.colonies.map { row in
                j(row.id, row.cells[0].net, row.cells[0].buildings.map { $0 ?? "-" }.joined(separator: ", "))
            }
        }
        r["labour"] = v.labourReport().map {
            j($0.typeId, $0.count, String($0.canTrain), $0.places.map { "\($0.name) \($0.count)" }.joined(separator: ", "))
        }
        r["colonies"] = v.colonyReport().flatMap { c in
            [j(c.id, c.name, c.building, c.colonistIds.joined(separator: " "), c.outsideIds.joined(separator: " "))]
                + c.goods.map { j($0.typeId, $0.net, $0.stock, $0.maximum) } + [c.buildings.joined(separator: ", ")]
        }
        return r
    }

    @Test(arguments: views.keys.sorted())
    func showsAsJava(_ name: String) throws {
        let nation = String(name[name.index(after: name.lastIndex(of: "-")!)...])
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let archive = try ZipArchive(contentsOf: PlayerViewTests.oracle.appendingPathComponent("advisors.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: PlayerViewTests.oracle.appendingPathComponent(
                "games/" + Self.views[name]!)).readServerGame()
            let server = try #require(saved.game as? ServerGame)
            let human = try #require(server.livePlayers.first { $0.nationId == "model.nation." + nation })
            let view = try PlayerView(of: server, for: human)
            let ours = Self.ours(view, server, human)
            var diffs: [String] = []
            for (key, value) in (java.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
                let t = (value.arrayValue ?? []).map { $0.stringValue ?? "" }, o = ours[key] ?? []
                if o == t { continue }
                let i = Array(zip(o, t)).firstIndex { $0 != $1 } ?? min(o.count, t.count)
                diffs.append("\(key) [\(i)] of \(o.count)/\(t.count):\n ours  \(i < o.count ? o[i] : "none")\n Java's \(i < t.count ? t[i] : "none")")
            }
            #expect(diffs.isEmpty, Comment(rawValue: "\(name):\n" + diffs.joined(separator: "\n")))
        }
    }
}

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

/// What the Europe panel shows and allows, and the role changes the unit
/// menu offers, on the player's copy of the game, against Java's
/// (EuropeOracle.java).
@Suite struct EuropeViewTests {

    /// The views EuropeOracle recorded, and their saved games.
    static let views = ["europe-dutch": "freecol-europe-seed1.fsg", "commands-dutch": "freecol-commands-seed1.fsg",
                        "colonypanel-dutch": "freecol-colonypanel-seed1.fsg",
                        "colonyai-english": "freecol-colonyai-seed1.fsg",
                        "colonyai-french": "freecol-colonyai-seed1.fsg",
                        "monarch-spanish": "freecol-turncycle-monarch-seed1.fsg"]

    static func str(_ v: JSONValue?) -> String {
        if case .bool(let b)? = v { return String(b) }
        if let i = v?.intValue { return String(i) }
        return v?.stringValue ?? "-"
    }
    static func list(_ v: JSONValue?) -> [String] { (v?.arrayValue ?? []).map { str($0) } }
    static func row(_ v: JSONValue?) -> String { list(v).joined(separator: " ") }

    /// Our Europe, section by section, as lines.
    static func ours(_ e: EuropeScreen, _ roles: [(String, [RoleChoice])]) -> [String: [String]] {
        var r: [String: [String]] = [:]
        r["recruit"] = ["\(e.recruitPrice) \(e.recruitTurns) \(e.canRecruit)"]
            + e.recruitables.map { "\($0.typeId) \($0.roleId ?? "-") \($0.label)" }
        r["train"] = e.train.map { "\($0.typeId) \($0.price) \($0.affordable)" }
        r["purchase"] = e.purchase.map { "\($0.typeId) \($0.price) \($0.affordable)" }
        r["market"] = e.market.map { "\($0.typeId) \($0.paidForSale) \($0.costToBuy) \($0.canTrade) \($0.arrears)" }
        r["places"] = ["docks \(e.docks)", "port \(e.inPort)", "toEurope \(e.toEurope)", "toAmerica \(e.toAmerica)"]
        r["carriers"] = e.carriers.map { c in
            let loads = c.loads.keys.sorted().map { "\($0) \(c.loads[$0]!.amount) \(c.loads[$0]!.price)" }
            return "\(c.id) \(c.goods.map { "\($0.typeId) \($0.amount)" }) \(c.unitIds) \(c.spaceLeft) "
                + "\(c.canBoard) " + loads.joined(separator: ", ")
        }
        r["roles"] = roles.map { u, cs in "\(u): " + cs.map { "\($0.roleId) \($0.count) \($0.price) \($0.text)" }
            .joined(separator: "; ") }
        return r
    }

    /// Java's Europe, section by section, as lines.
    static func javas(_ d: JSONValue) -> [String: [String]] {
        var r: [String: [String]] = [:]
        let rec = d["recruit"]
        r["recruit"] = ["\(str(rec?["price"])) \(str(rec?["turns"])) \(str(rec?["enabled"]))"]
            + (rec?["units"]?.arrayValue ?? []).map { row($0) }
        r["train"] = (d["train"]?.arrayValue ?? []).map { row($0) }
        r["purchase"] = (d["purchase"]?.arrayValue ?? []).map { row($0) }
        r["market"] = (d["market"]?.arrayValue ?? []).map { g in
            "\(str(g["type"])) \(str(g["sale"])) \(str(g["buy"])) \(str(g["canTrade"])) \(str(g["arrears"]))"
        }
        r["places"] = ["docks \(list(d["docks"]))", "port \(list(d["inPort"]))",
                       "toEurope \(list(d["toEurope"]))", "toAmerica \(list(d["toAmerica"]))"]
        r["carriers"] = (d["carriers"]?.arrayValue ?? []).map { c -> String in
            let goods = (c["goods"]?.arrayValue ?? []).map { g -> String in
                let a = list(g)
                return "\(a[0]) \(a[1])"
            }
            let loadMap = c["loads"]?.objectValue ?? [:]
            let loads = loadMap.keys.sorted().map { k -> String in "\(k) \(row(loadMap[k]))" }
            return "\(str(c["id"])) \(goods) \(list(c["units"])) \(str(c["spaceLeft"])) \(list(c["board"])) "
                + loads.joined(separator: ", ")
        }
        r["roles"] = (d["roles"]?.arrayValue ?? []).map { u -> String in
            "\(str(u["unit"])): " + (u["choices"]?.arrayValue ?? []).map { row($0) }.joined(separator: "; ")
        }
        return r
    }

    @Test(arguments: views.keys.sorted())
    func showsAsJava(_ name: String) throws {
        let nation = String(name[name.index(after: name.lastIndex(of: "-")!)...])
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let archive = try ZipArchive(contentsOf: PlayerViewTests.oracle.appendingPathComponent("europe.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: PlayerViewTests.oracle.appendingPathComponent(
                "games/" + Self.views[name]!)).readServerGame()
            let server = try #require(saved.game as? ServerGame)
            let serverPlayer = try #require(server.livePlayers.first { $0.nationId == "model.nation." + nation })
            let view = try PlayerView(of: server, for: serverPlayer)
            let e = try #require(view.europeScreen())
            // The units whose roles Java listed, in Europe and the colonies.
            let roles = (java["roles"]?.arrayValue ?? []).compactMap { u -> (String, [RoleChoice])? in
                guard let id = u["unit"]?.stringValue, let unit = view.game.getFreeColGameObject(id, as: Unit.self)
                else { return nil }
                return (id, view.roleChoices(unit))
            }
            var units = view.player.europe?.units.filter { !$0.isNaval } ?? []
            for c in view.player.colonyList {
                units += c.unitList
                units += c.tile?.units.filter(\.isPerson) ?? []
            }
            #expect(units.compactMap(\.id).sorted() == roles.map(\.0), "the units with roles")
            let ours = Self.ours(e, roles), theirs = Self.javas(java)
            #expect(String(e.gold) == Self.str(java["gold"]))
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

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

/// What a long press on a tile offers, against Java's TilePopup
/// (TileMenuOracle.java), and the actions only it offers.
@Suite struct TileMenuTests {

    static func kind(_ k: TileMenuItem.Kind) -> String {
        switch k {
        case .attack: "attack"
        case .goTo: "goTo"
        case .goToEurope: "goToEurope"
        case .activate: "activate"
        case .fortify: "fortify"
        case .skip: "skip"
        case .cashIn: "cashIn"
        case .clearOrders: "clearOrders"
        case .colony: "colony"
        case .rename: "rename"
        case .settlement: "settlement"
        case .tile: "tile"
        case .unit: "unit"
        case .goods: "goods"
        case .dumpCargo: "dumpCargo"
        case .activateAll: "activateAll"
        }
    }

    @Test(arguments: ["commands", "natives", "diplomacy", "combat"])
    func menusAsJava(_ name: String) throws {
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let archive = try ZipArchive(contentsOf: PlayerViewTests.oracle.appendingPathComponent("tilemenus.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: PlayerViewTests.oracle.appendingPathComponent(
                "games/freecol-\(name)-seed1.fsg")).readServerGame()
            let server = try #require(saved.game as? ServerGame)
            let human = try #require(server.livePlayers.first { !$0.isAI })
            let view = try PlayerView(of: server, for: human)
            var diffs: [String] = []
            for (key, value) in (java.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
                let parts = key.split(separator: " ").map(String.init)
                let tile = try #require(view.tile(MapPosition(x: Int(parts[1])!, y: Int(parts[2])!)))
                let menu = view.tileMenu(tile, activeUnit: view.unit(parts[0]))
                let ours = [menu.title] + menu.items.map { i -> String in
                    var enabled = i.enabled
                    if case let .tile(explored) = i.kind { enabled = explored }
                    return "\(Self.kind(i.kind))|\(i.label)|\(enabled)"
                }
                let theirs = (value.arrayValue ?? []).map { $0.stringValue ?? "" }
                if ours != theirs { diffs.append("\(key): ours \(ours), Java's \(theirs)") }
            }
            #expect(diffs.isEmpty, Comment(rawValue: "\(diffs.count):\n" + diffs.prefix(5).joined(separator: "\n")))
        }
    }

    @Test func renameAndActivateAll() async throws {
        let engine = try await RequestTests.engine("commands")
        let colony = try #require(await engine.snapshot().colonies.first)
        let r = try await engine.play(.renameColony(colonyId: colony.id, name: "New Haven"))
        #expect(r.refusal == nil && r.snapshot.colony(colony.id)?.name == "New Haven")
        // A tile of several of the player's units, all waiting again.
        let snapshot = await engine.snapshot()
        let unit = try #require(snapshot.ownUnits.first { u in
            u.position.map { snapshot.map.tile($0.x, $0.y)?.unitIds.count ?? 0 > 1 } ?? false
        })
        let at = try #require(unit.position)
        _ = try await engine.play(.changeState(unitId: unit.id, state: "SENTRY"))
        let after = try await engine.play(.activateAll(at))
        #expect(after.snapshot.unit(unit.id)?.state == "ACTIVE" && after.activeUnitId != nil)
    }
}

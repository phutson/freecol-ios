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
import FreeColEngine
import FreeColIO
import FreeColTestSupport
import Testing

/// The destinations Java's dialog offers each unit on the map and each
/// ship in Europe (DestinationOracle.java), and sending a unit to one.
@Suite struct DestinationViewTests {

    static let games = ["commands", "europe", "natives", "diplomacy"]

    @Test(arguments: games)
    func destinationsAsJava(_ game: String) async throws {
        let archive = try ZipArchive(contentsOf: PlayerViewTests.oracle.appendingPathComponent("destinations.zip"))
        let java = try JSONValue.parse(try #require(try archive.contents(of: game + "-dutch.json")))
        let engine = try GameEngine(loading: PlayerViewTests.oracle.appendingPathComponent(
            "games/freecol-\(game)-seed1.fsg"), messages: GameEngineTests.english)
        var diffs: [String] = []
        for (unitId, list) in (java["units"]?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
            let theirs = (list.arrayValue ?? []).map { TradeViewTests.row($0) }
            let ours = await engine.destinations(unitId).map { "\($0.id)|\($0.text)|\($0.isOwn)" }
            if ours != theirs { diffs.append("\(unitId): ours \(ours), Java's \(theirs)") }
        }
        #expect(diffs.isEmpty, Comment(rawValue: "\(game):\n" + diffs.joined(separator: "\n")))
    }

    /// The other orders: by name (home first), and by distance.
    @Test func orders() async throws {
        let engine = try GameEngine(loading: PlayerViewTests.oracle.appendingPathComponent(
            "games/freecol-natives-seed1.fsg"), messages: GameEngineTests.english)
        let all = await engine.destinations("unit:5854")
        let byName = await engine.destinations("unit:5854", order: .name)
        let byDistance = await engine.destinations("unit:5854", order: .distance)
        #expect(Set(all.map(\.id)) == Set(byName.map(\.id)) && Set(all.map(\.id)) == Set(byDistance.map(\.id)))
        let names = byName.dropFirst().map(\.name)
        #expect(names == names.sorted())
        #expect(byDistance.map(\.turns) == byDistance.map(\.turns).sorted())
    }

    /// A ship in Europe sent to a colony sails for it.
    @Test func selectDestination() async throws {
        let engine = try GameEngine(loading: PlayerViewTests.oracle.appendingPathComponent(
            "games/freecol-europe-seed1.fsg"), messages: GameEngineTests.english)
        _ = try await engine.play(.startTurn)
        let ship = try #require(await engine.europeScreen()?.carriers.first)
        let colony = try #require(await engine.destinations(ship.id).first { $0.id.hasPrefix("colony:") })
        var answers: [String: String] = [:]
        var r = try await engine.play(.selectDestination(unitId: ship.id, destinationId: colony.id))
        while let q = r.question, answers.count < 5 {
            answers[q.id] = q.choices.first?.id ?? ""
            r = try await engine.play(.selectDestination(unitId: ship.id, destinationId: colony.id), answers: answers)
        }
        #expect(r.refusal == nil)
        #expect(try #require(await engine.europeScreen()).toAmerica.contains(ship.id))
    }
}

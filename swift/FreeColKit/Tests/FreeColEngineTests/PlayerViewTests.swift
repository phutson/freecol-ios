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

/// What the client decides as the player plays, on the player's copy of
/// the game, against what Java's client decides (PlayOracle.java).
@Suite struct PlayerViewTests {

    static let oracle = JavaOracle.url.deletingLastPathComponent()

    /// The views PlayOracle recorded: a saved game and the player's
    /// nation.
    static let views = ["commands-dutch", "moves-dutch", "natives-dutch", "combat-dutch", "diplomacy-dutch",
                        "unitai-english", "unitai-french", "unitai-spanish"]

    /// How far round each unit the oracle recorded goto paths.
    static let gotoRadius = 5

    static func javaPath(_ value: JSONValue?) -> UnitPath? {
        guard let nodes = value?.arrayValue else { return nil }
        return UnitPath(steps: nodes.map { n in
            let a = n.arrayValue ?? []
            let place: PathPlace
            var rest: ArraySlice<JSONValue>
            if let x = a[0].intValue {
                place = .tile(MapPosition(x: Int(x), y: Int(a[1].intValue ?? 0)))
                rest = a[2...]
            } else if a[0].stringValue == "europe" {
                place = .europe
                rest = a[1...]
            } else {
                let tile = a[1].intValue.map { MapPosition(x: Int($0), y: Int(a[2].intValue ?? 0)) }
                place = .carrier(a[0].stringValue ?? "", tile)
                rest = a[3...]
            }
            return PathStep(place: place, turns: Int(rest[rest.startIndex].intValue ?? 0),
                            movesLeft: Int(rest[rest.startIndex + 1].intValue ?? 0),
                            direction: rest[rest.startIndex + 2].stringValue)
        })
    }

    @Test(arguments: views)
    func decidesAsJava(_ name: String) throws {
        let parts = name.split(separator: "-")
        try Messages.$scopedBundle.withValue(GameEngineTests.english) {
            let archive = try ZipArchive(contentsOf: Self.oracle.appendingPathComponent("play.zip"))
            let java = try JSONValue.parse(try #require(try archive.contents(of: name + ".json")))
            let saved = try FreeColSavegameFile(url: Self.oracle.appendingPathComponent("games/freecol-\(parts[0])-seed1.fsg"))
                .readServerGame()
            let game = try #require(saved.game as? ServerGame)
            let serverPlayer = try #require(game.livePlayers.first { $0.nationId == "model.nation." + parts[1] })
            let view = try PlayerView(of: game, for: serverPlayer)
            let map = try #require(view.game.map)
            #expect(java["player"]?.stringValue == view.player.id)
            var diffs: [String] = []
            func check<T: Equatable>(_ what: String, _ ours: T, _ theirs: T) {
                if ours != theirs, diffs.count < 20 { diffs.append("\(what): ours \(ours), Java's \(theirs)") }
            }

            var mine: [String] = []
            for u in try #require(java["units"]?.arrayValue) {
                let id = u["id"]?.stringValue ?? ""
                mine.append(id)
                guard let unit = view.unit(id), let tile = unit.tile else {
                    diffs.append("\(id): not on the map")
                    continue
                }
                check("\(id) moves", view.moveTypes(unit).map(\.javaName), (u["moves"]?.arrayValue ?? []).map { $0.stringValue ?? "" })
                let a = view.actions(unit)
                let ja = u["actions"]
                var ours: [String: Bool] = ["attackRanged": a.attackRanged, "fortify": a.fortify,
                                            "buildColony": a.buildColony, "load": a.load, "unload": a.unload,
                                            "gotoTile": a.gotoTile]
                ours.merge(a.improvements) { x, _ in x }
                var theirs: [String: Bool] = [:]
                for k in ours.keys { if case .bool(let b)? = ja?[k] { theirs[k] = b } }
                check("\(id) actions", ours, theirs)
                if unit.canBuildColony && tile.colony == nil {
                    let warnings = PlayerView.buildColonyWarnings(tile, unit)
                    let t = StringTemplate.label("\n")
                    for w in warnings { _ = t.addStringTemplate(w) }
                    check("\(id) colony warnings", Messages.message(t), u["colonyWarnings"]?.stringValue)
                    check("\(id) claim reason", view.player.canClaimToFoundSettlementReason(tile).javaName,
                          u["claimReason"]?.stringValue)
                    check("\(id) land price", view.player.landPrice(tile), Int(u["landPrice"]?.intValue ?? -9))
                }
                var attacks: [String] = []
                for (d, mt) in zip(Direction.allDirections, view.moveTypes(unit))
                where mt == .attackUnit || mt == .attackSettlement {
                    let target = tile.neighbour(d)
                    let defender: FreeColGameObject? = target?.settlement ?? target?.defendingUnit(unit)
                    let cm = view.game.combatModel
                    attacks.append("\(d.javaName) \(Float(cm.offencePower(unit, defender))) "
                                   + "\(Float(cm.defencePower(unit, defender))) \(cm.calculateCombatOdds(unit, defender).win)")
                }
                check("\(id) attacks", attacks, (u["attacks"]?.arrayValue ?? []).map { a in
                    func n(_ k: String) -> Double {
                        if case .decimal(let d)? = a[k] { return d }
                        return Double(a[k]?.intValue ?? -9)
                    }
                    return "\(a["direction"]?.stringValue ?? "") \(Float(n("offence"))) \(Float(n("defence"))) \(n("win"))"
                })
                check("\(id) destination path", view.destinationPath(unit), Self.javaPath(u["destinationPath"]))
                if unit.isNaval { check("\(id) Europe path", view.europePath(unit), Self.javaPath(u["europePath"])) }
                var gotos: [MapPosition: UnitPath] = [:]
                for g in u["gotos"]?.arrayValue ?? [] {
                    gotos[MapPosition(x: Int(g["x"]?.intValue ?? 0), y: Int(g["y"]?.intValue ?? 0))] = Self.javaPath(g["path"])
                }
                var count = 0
                for t in map.tiles where map.distance(tile, t) <= Self.gotoRadius {
                    let p = MapPosition(x: t.x, y: t.y)
                    let path = view.gotoPath(unit, to: t)
                    if path != nil { count += 1 }
                    check("\(id) goto \(p.x),\(p.y)", path, gotos[p])
                }
                check("\(id) goto count", count, gotos.count)
            }
            check("units on the map", view.player.units.filter {
                $0.location is Tile || ($0.isOnCarrier && $0.hasTile)
            }.compactMap(\.id).sorted(), mine.sorted())
            check("could move", view.player.units.filter(\.couldMove).compactMap(\.id).sorted(),
                  (java["couldMove"]?.arrayValue ?? []).map { $0.stringValue ?? "" })

            var cycle = ActiveUnitCycle()
            let order = (java["nextActive"]?.arrayValue ?? []).map { $0.stringValue }
            check("next active", order.map { _ in cycle.next(view)?.id }, order)
            #expect(diffs.isEmpty, Comment(rawValue: "\(name):\n" + diffs.joined(separator: "\n")))
        }
    }
}

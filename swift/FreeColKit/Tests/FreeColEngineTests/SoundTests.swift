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
import FreeColResources
@testable import FreeColServer
import FreeColTestSupport
import Testing

/// Which sound plays when, as in Java's InGameController and Message, and
/// that the app has a file for each sound in the resources.
@Suite struct SoundTests {

    static func sounds(_ events: [EngineEvent]) -> [String] {
        events.compactMap { if case .sound(let key) = $0 { key } else { nil } }
    }

    static func engine(_ name: String) async throws -> GameEngine {
        let engine = try GameEngine(loading: PlayerViewTests.oracle.appendingPathComponent(
            "games/freecol-\(name)-seed1.fsg"), messages: GameEngineTests.english)
        _ = try await engine.play(.startTurn)
        return engine
    }

    @Test func europe() async throws {
        let engine = try await Self.engine("europe")
        var asked: [String] = []
        let ship = try #require(await engine.europeScreen()?.carriers.first { $0.spaceLeft > 0 })
        var r = try await PlayTests.playAccepting(
            engine, .load(goodsTypeId: "model.goods.sugar", amount: 10, carrierId: ship.id), asked: &asked)
        #expect(Self.sounds(r.events) == ["sound.event.loadCargo"])
        r = try await PlayTests.playAccepting(
            engine, .unload(goodsTypeId: "model.goods.sugar", amount: 10, carrierId: ship.id), asked: &asked)
        #expect(Self.sounds(r.events) == ["sound.event.sellCargo"])

        // Nothing sold, nothing heard.
        r = try await PlayTests.playAccepting(
            engine, .unload(goodsTypeId: "model.goods.sugar", amount: 10, carrierId: ship.id), asked: &asked)
        #expect(Self.sounds(r.events).isEmpty)

        let screen = try #require(await engine.europeScreen())
        var europeId = ""
        _ = try await engine.serverActs { _, _, human, _ in
            europeId = human.europe?.id ?? ""
            return ChangeSet()
        }
        r = try await PlayTests.playAccepting(engine, .sail(carrierId: ship.id, destinationId: europeId),
                                              asked: &asked)
        #expect(Self.sounds(r.events) == ["sound.event.illegalMove"])

        if let walker = screen.docks.first {
            r = try await PlayTests.playAccepting(engine, .board(unitId: walker, carrierId: ship.id), asked: &asked)
            #expect(Self.sounds(r.events) == ["sound.event.loadCargo"])
        }
    }

    @Test func mission() async throws {
        let engine = try await SettlementPlayTests.engine()
        let (missionary, d) = try #require(await SettlementPlayTests.find(engine, "ENTER_INDIAN_SETTLEMENT_WITH_MISSIONARY"))
        let (r, _) = try await SettlementPlayTests.play(engine, .move(unitId: missionary, direction: d),
                                                        ["missionary": "establish"])
        #expect(Self.sounds(r.events) == ["sound.event.missionEstablished"])
    }

    /// Bumping into what can not be entered is heard, a legal move not.
    @Test(arguments: ["MOVE_NO_ACCESS_CONTACT", "MOVE_ILLEGAL"])
    func illegal(_ type: String) async throws {
        let engine = try await Self.engine("diplomacy")
        let (unit, d) = try #require(await SettlementPlayTests.find(engine, type))
        let r = try await engine.play(.move(unitId: unit, direction: d))
        #expect(Self.sounds(r.events) == ["sound.event.illegalMove"])
    }

    @Test func legalMoveIsSilent() async throws {
        let engine = try await Self.engine("natives")
        let (unit, d) = try #require(await SettlementPlayTests.find(engine, "MOVE"))
        let r = try await engine.play(.move(unitId: unit, direction: d))
        #expect(Self.sounds(r.events).isEmpty)
    }

    /// The server's sounds play only in the player's own turn.
    @Test func serverSounds() async throws {
        let engine = try await Self.engine("natives")
        let mine = try await engine.serverActs { game, _, human, _ in
            game.currentPlayer = human
            return ChangeSet().addAttribute(.only(human), "sound", "sound.event.shipSunk")
        }
        #expect(Self.sounds(mine) == ["sound.event.shipSunk"])
        let others = try await engine.serverActs { game, _, human, _ in
            game.currentPlayer = game.livePlayers.first { $0 !== human }
            return ChangeSet().addAttribute(.only(human), "sound", "sound.event.shipSunk")
        }
        #expect(Self.sounds(others).isEmpty)
    }

    /// Meeting a nation plays its music, the first time only, and only
    /// for the side the change is about.
    @Test func meeting() async throws {
        let engine = try await Self.engine("commands")
        var nation = ""
        let first = try await engine.serverActs { game, _, human, _ in
            let other = try #require(game.livePlayers.first { $0 !== human && human.stance($0) == .uncontacted })
            nation = other.nationId ?? ""
            return ChangeSet().addStance(.only(human), human, .peace, other)
        }
        #expect(Self.sounds(first) == ["sound.event.meet." + nation])
        let again = try await engine.serverActs { game, _, human, _ in
            let other = try #require(game.livePlayers.first { $0.nationId == nation })
            return ChangeSet().addStance(.only(human), human, .war, other)
        }
        #expect(Self.sounds(again).isEmpty)
        let reversed = try await engine.serverActs { game, _, human, _ in
            let other = try #require(game.livePlayers.first { $0 !== human && $0.nationId != nation })
            return ChangeSet().addStance(.only(human), other, .peace, human)
        }
        #expect(Self.sounds(reversed).isEmpty)
    }

    /// Every sound in the resources has its converted file, of some
    /// length, and the sounds' kinds are as the resources say.
    @Test func filesExist() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = repository.appendingPathComponent("data")
        let audio = repository.appendingPathComponent("swift/FreeColApp.swiftpm/Sources/Resources/audio")
        let manager = ResourceManager()
        let base = try FreeColDataFile(directory: data.appendingPathComponent("base")).resourceMapping(languageId: "en_US")
        manager.setBase(try #require(base))
        manager.setTc(try FreeColTcFile.resourceMapping(dataDirectory: data, id: "default", languageId: "en_US"))

        let keys = ["sound.intro.general", "sound.intro.model.nation.dutch", "sound.music.playlist.default",
                    "sound.event.meet.model.nation.aztec", "sound.event.fountainOfYouth"]
            + ["buildingComplete", "illegalMove", "alertSound", "missionEstablished", "loadCargo", "unloadCargo",
               "sellCargo", "cashInTreasureTrain", "captureColony", "destroySettlement", "shipSunk"]
                .map { "sound.event." + $0 }
            + ["artillery", "mounted", "naval", "bombard"].map { "sound.attack." + $0 }
        for key in keys {
            let files = manager.convertedSoundFiles(key)
            #expect(!files.isEmpty, Comment(rawValue: key))
            for f in files {
                let size = (try? FileManager.default.attributesOfItem(
                    atPath: audio.appendingPathComponent(f).path)[.size] as? Int) ?? 0
                #expect((size ?? 0) > 1000, Comment(rawValue: "\(key): \(f)"))
            }
        }
        #expect(manager.convertedSoundFiles("sound.music.playlist.default").count == 12)
        #expect(manager.convertedSoundFiles("sound.attack.foot").isEmpty)
        #expect(manager.isMusic("sound.intro.general"))
        #expect(manager.isMusic("sound.event.fountainOfYouth"))
        #expect(!manager.isMusic("sound.event.loadCargo"))
    }
}

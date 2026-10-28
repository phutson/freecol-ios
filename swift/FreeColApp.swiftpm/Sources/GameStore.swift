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

import FreeColCore
import FreeColEngine
import FreeColIO
import FreeColMap
import FreeColResources
import Foundation
import Observation
import UIKit

/// The game being shown: the engine running it, the human player's
/// latest snapshot, and the images to draw it with.
@MainActor @Observable
final class GameStore {
    private(set) var snapshot: GameSnapshot?
    private(set) var images: MapImageStore?
    private(set) var failure: String?
    private var engine: GameEngine?

    /// The game's data, bundled with the app.
    static var dataDirectory: URL? {
        Bundle.main.url(forResource: "data", withExtension: nil)
    }

    /// Load the bundled saved game.
    func loadSample() async {
        guard let data = Self.dataDirectory,
              let save = Bundle.main.url(forResource: "freecol-commands-seed1", withExtension: "fsg",
                                           subdirectory: "games") else {
            failure = "The game's data is missing from the app."
            return
        }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                let messages = try GameStore.messages(data)
                let engine = try GameEngine(loading: save, messages: messages)
                let images = try MapImageStore(dataDirectory: data)
                return (engine, images)
            }.value
            engine = loaded.0
            images = loaded.1
            snapshot = await loaded.0.snapshot()
        } catch {
            failure = "Could not load the game: \(error)"
        }
    }

    /// The English strings, with the rules' own.
    nonisolated static func messages(_ data: URL) throws -> MessageBundle {
        let strings = data.appendingPathComponent("strings")
        let numberRules = try NumberRules(data: Data(contentsOf: strings.appendingPathComponent("plurals.xml")))
        return MessageBundle.load(directory: strings, languageId: "en_US", numberRules: numberRules,
                                  rulesDirectories: ["classic", "freecol"].map {
                                      data.appendingPathComponent("rules/" + $0)
                                  })
    }
}

/// The map's images: found by key as Java's client finds them (the base
/// data, then the default rules' images), and loaded from their files
/// once each.
final class MapImageStore: @unchecked Sendable {
    let lookup: ResourceMapImages
    private var cache: [MapImage: UIImage] = [:]
    private let lock = NSLock()

    init(dataDirectory data: URL) throws {
        let manager = ResourceManager()
        if let base = try FreeColDataFile(directory: data.appendingPathComponent("base"))
            .resourceMapping(languageId: "en_US") {
            manager.setBase(base)
        }
        manager.setTc(try FreeColTcFile.resourceMapping(dataDirectory: data, id: "default", languageId: "en_US"))
        lookup = ResourceMapImages(manager)
    }

    /// The picture for an image, or nil if there is none.
    func image(_ image: MapImage) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[image] { return cached }
        guard let resource = lookup.manager.imageResource(image.key)?.variation(image.variation),
              let url = resource.locator?.fileURL,
              let loaded = UIImage(contentsOfFile: url.path) else { return nil }
        cache[image] = loaded
        return loaded
    }
}

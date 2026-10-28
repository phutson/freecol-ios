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

    private var composites: [String: UIImage] = [:]

    /// The picture for an image, or nil if there is none.
    func image(_ image: MapImage) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return loaded(image)
    }

    private func loaded(_ image: MapImage) -> UIImage? {
        if let cached = cache[image] { return cached }
        guard let resource = lookup.manager.imageResource(image.key)?.variation(image.variation),
              let url = resource.locator?.fileURL,
              let loaded = UIImage(contentsOfFile: url.path) else { return nil }
        cache[image] = loaded
        return loaded
    }

    /// The picture Java makes for a composite, made once per key and
    /// variation, as Java caches them.
    func image(_ composite: MapComposite) -> UIImage? {
        lock.lock()
        defer { lock.unlock() }
        let key = composite.key + "#" + String(composite.variation)
        if let cached = composites[key] { return cached }
        let made = render(composite.picture)
        composites[key] = made
        return made
    }

    private static let tileSize = CGSize(width: MapScene.tileWidth, height: MapScene.tileHeight)

    /// Draw a picture on a clear tile (ImageUtils and the image creators).
    private func render(_ picture: MapPicture) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = MapImageStore.tileSize
        switch picture {
        case let .image(image):
            // Java's image creators take every image at a tile's size.
            guard let i = loaded(image) else { return nil }
            if i.size == size && i.scale == 1 { return i }
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.interpolationQuality = .high
                i.draw(in: CGRect(origin: .zero, size: size))
            }
        case let .masked(content, mask):
            guard let c = render(content), let m = render(mask) else { return nil }
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                c.draw(at: .zero)
                m.draw(at: .zero, blendMode: .destinationIn, alpha: 1)
            }
        case let .layers(layers):
            let rendered = layers.map { (render($0.picture), CGFloat($0.opacity)) }
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                for (image, alpha) in rendered { image?.draw(at: .zero, blendMode: .normal, alpha: alpha) }
            }
        case let .enlarged(mask):
            guard let m = render(mask) else { return nil }
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                context.cgContext.interpolationQuality = .high
                let w = size.width * 1.25, h = size.height * 1.25
                m.draw(in: CGRect(x: -(w - size.width) / 2, y: -(h - size.height) / 2, width: w, height: h))
                m.draw(at: .zero)
            }
        }
    }
}

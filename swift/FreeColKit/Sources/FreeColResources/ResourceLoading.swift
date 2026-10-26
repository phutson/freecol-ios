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
import FreeColIO
import FreeColUtil
import FreeColXML

extension FreeColDataFile {

    /// The prefix of a value that names another key's resource.
    static let resourceScheme = "resource:"

    /// The resource files for a language, in the order Java reads them:
    /// "resources.properties", then the language, country and variant
    /// files (FreeColDirectories.getResourceFileNames).
    public static func resourceFileNames(languageId: String) -> [String] {
        MessageBundle.fileNames(prefix: "resources", suffix: ".properties", languageId: languageId)
    }

    /// The resources this data file maps (FreeColDataFile.getResourceMapping).
    ///
    /// - Parameters:
    ///   - languageId: The language, which picks extra resource files
    ///     (some languages need other fonts).
    ///   - highQuality: Whether to look for images at other sizes, as
    ///     Java does unless it has under 2 GB of memory.
    /// - Returns: nil if a resource file is malformed.
    public func resourceMapping(languageId: String, highQuality: Bool = true) -> ResourceMapping? {
        var properties = JavaProperties()
        for name in Self.resourceFileNames(languageId: languageId) {
            guard let data = data(name) else { continue } // Expected for most languages
            do {
                try properties.load(data)
            } catch {
                return nil
            }
        }
        let rc = ResourceMapping()
        let factory = ResourceFactory()
        var virtualResources: [String] = []
        var listings: [String: [String]?] = [:]
        // Java enumerates its Hashtable; the order only matters when two
        // keys of different kinds name the same file, which the bundled
        // data never does.
        for key in properties.keys.sorted() {
            // Old keys listed the variation; ".r0" is dropped.
            let updatedKey = key.hasSuffix(".r0") ? String(key.dropLast(3)) : key
            let value = properties[key]!
            if value.hasPrefix(Self.resourceScheme) {
                virtualResources.append(updatedKey)
            } else {
                handleNormalResource(factory, rc, key, value, highQuality, &listings)
            }
        }
        handleVirtualResources(virtualResources, properties, rc)
        return rc
    }

    private func handleNormalResource(_ factory: ResourceFactory, _ rc: ResourceMapping, _ key: String,
                                      _ value: String, _ highQuality: Bool,
                                      _ listings: inout [String: [String]?]) {
        let uri = uri(value)
        // The caching key is the data's URI: the same for (and only for)
        // the same data.  The mapping key is not, as mods replace it.
        guard let resource = factory.createResource(key: key, cachingKey: uri.string, uri: uri) else { return }
        // Rivers would need new keys to support variations.
        if let image = resource as? ImageResource, !key.contains(".improvement.river.") {
            extendWithAdditionalSizesAndVariations(factory, image, value, highQuality, &listings)
        }
        rc.add(key, resource)
    }

    /// Resolve the keys whose values name other keys, until no more can
    /// be (Java logs the rest).
    private func handleVirtualResources(_ keys: [String], _ properties: JavaProperties, _ rc: ResourceMapping) {
        var virtualResources = keys
        var progress = true
        while progress && !virtualResources.isEmpty {
            progress = false
            var miss: [String] = []
            for key in virtualResources {
                // Java looks the value up by the key without ".r0", and
                // fails on a key that had it; here it is a miss.
                guard let value = properties[key]?.dropFirst(Self.resourceScheme.count),
                      rc.duplicateResource(String(value), key) else {
                    miss.append(key)
                    continue
                }
                progress = true
            }
            virtualResources = miss
        }
    }

    /// Add an image's other sizes and its variations, found by listing
    /// its directory.
    private func extendWithAdditionalSizesAndVariations(_ factory: ResourceFactory, _ image: ImageResource,
                                                        _ value: String, _ highQuality: Bool,
                                                        _ listings: inout [String: [String]?]) {
        // Java fails here for a name without a dot, or a directory it
        // can not list; the bundled data has neither.
        guard let dot = value.firstIndex(of: "."), dot > value.startIndex else { return }
        let filePath = filePath(value)
        let (parent, filename) = Self.split(filePath)
        guard let listing = Self.sortedListing(parent, &listings) else { return }
        image.addAlternatives(highQuality ? Self.sizes(parent, filename, listing) : [])
        for variationName in Self.findFiles(parent, filename, listing, variation: true) {
            let variationPath = parent + "/" + variationName
            guard let variation = factory.createResource(key: "", cachingKey: image.cachingKey,
                                                         uri: JavaURI(pathString: variationPath)) as? ImageResource
            else { continue }
            variation.addAlternatives(highQuality ? Self.sizes(parent, variationName, listing) : [])
            image.addVariation(variation)
        }
    }

    /// The other sizes of a file, as `Path.toUri()` URIs.
    static func sizes(_ parent: String, _ filename: String, _ listing: [String]) -> [JavaURI] {
        findFiles(parent, filename, listing, variation: false).map { JavaURI(pathString: parent + "/" + $0) }
    }

    /// A path's directory and file name.
    static func split(_ path: String) -> (parent: String, name: String) {
        guard let slash = path.lastIndex(of: "/") else { return (".", path) }
        return (String(path[..<slash]), String(path[path.index(after: slash)...]))
    }

    /// A directory's entries in Java's Path order (by UTF-8 bytes), or
    /// nil if it can not be listed; each directory is listed once.
    static func sortedListing(_ directory: String, _ listings: inout [String: [String]?]) -> [String]? {
        if let cached = listings[directory] { return cached }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory))?
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        listings[directory] = .some(names)
        return names
    }

    /// The names of the other sizes ("name.size2.png") or the
    /// variations ("name1.png", "name12.png": the name without its
    /// trailing digits and one or two digits) of a file.
    static func findFiles(_ parent: String, _ filename: String, _ listing: [String],
                          variation: Bool) -> [String] {
        guard let dot = filename.lastIndex(of: ".") else { return [] }
        var prefix = Array(filename[..<dot].utf8)
        let suffix = Array(filename[dot...].utf8)
        func isDigit(_ b: UInt8) -> Bool { b >= UInt8(ascii: "0") && b <= UInt8(ascii: "9") }
        if variation {
            while let last = prefix.last, isDigit(last) { prefix.removeLast() }
        }
        let size = Array(".size".utf8)
        return listing.filter { name in
            let bytes = Array(name.utf8)
            guard bytes.count >= prefix.count + suffix.count, bytes.starts(with: prefix),
                  bytes.reversed().starts(with: suffix.reversed()) else { return false }
            let middle = bytes[prefix.count..<(bytes.count - suffix.count)]
            if variation {
                return (1...2).contains(middle.count) && middle.allSatisfy(isDigit) && name != filename
            }
            return middle.count > size.count && middle.starts(with: size)
                && middle.dropFirst(size.count).allSatisfy(isDigit)
        }
    }
}

/// A total conversion: the data of a look for the game, which may build
/// on another (common/io/FreeColTcFile).  The bundled one is "default".
public enum FreeColTcFile {

    /// The resource mapping of a total conversion, after its parent's
    /// (so its own resources win).
    ///
    /// - Parameters:
    ///   - dataDirectory: The data directory, holding the total
    ///     conversions by id.
    ///   - id: The total conversion, such as "default".
    public static func resourceMapping(dataDirectory: URL, id: String, languageId: String,
                                       highQuality: Bool = true) throws -> ResourceMapping {
        let file = try FreeColDataFile(directory: dataDirectory.appendingPathComponent(id))
        let result = ResourceMapping()
        if let parent = try parentId(file) {
            result.addAll(try resourceMapping(dataDirectory: dataDirectory, id: parent, languageId: languageId,
                                              highQuality: highQuality))
        }
        result.addAll(file.resourceMapping(languageId: languageId, highQuality: highQuality))
        return result
    }

    /// The parent named by a data file's mod.xml, if any.
    static func parentId(_ file: FreeColDataFile) throws -> String? {
        guard let data = file.data("mod.xml") else { return nil }
        let xr = try FreeColXMLReader(data: data)
        try xr.nextTag()
        return xr.attribute("parent", default: nil as String?)
    }
}

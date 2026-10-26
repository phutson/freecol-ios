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

import CryptoKit
import Foundation
import FreeColIO
import FreeColResources
import FreeColTestSupport
import FreeColUtil
import Testing

/// The resource mappings, colours, fonts, animated font, animations and
/// properties documents, compared with what Java makes of them
/// (ResourceOracle.java).
@Suite(.serialized)
struct ResourceTests {

    static let dataDirectory = ReferenceDumps.repositoryRoot.appendingPathComponent("data")
    static let oracleDirectory = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("resources")

    /// The data directory's URI, as Java writes it, which the oracle
    /// replaces with "data/".
    static let root = JavaURI(file: dataDirectory).string

    static func javaDocument(_ name: String) throws -> JSONValue {
        let archive = try ZipArchive(contentsOf: oracleDirectory.appendingPathComponent("full.zip"))
        return try JSONValue.parse(try #require(try archive.contents(of: name)))
    }

    static let javaDigests: [String: String] = {
        guard let data = try? Data(contentsOf: oracleDirectory.appendingPathComponent("digests.json")),
              let json = try? JSONValue.parse(data), let members = json.objectValue else { return [:] }
        return members.compactMapValues(\.stringValue)
    }()

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Dumps, as ResourceOracle writes them

    static func rel(_ uri: String?) -> JSONValue {
        guard var s = uri else { return .null }
        if s.hasPrefix("file:///") { s = "file:/" + s.dropFirst("file:///".count) }
        return .string(s.hasPrefix(root) ? "data/" + s.dropFirst(root.count) : s)
    }

    static func uris(_ uris: [JavaURI]?) -> JSONValue {
        uris.map { .array($0.map { rel($0.string) }) } ?? .null
    }

    static func font(_ f: FontDescriptor) -> JSONValue {
        .object(["name": .string(f.name), "style": .integer(Int64(f.style)), "size": .integer(Int64(f.size))])
    }

    static func resource(_ r: Resource) -> JSONValue {
        var m: [String: JSONValue] = [
            "type": .string(r.typeName),
            "cachingKey": rel(r.cachingKey),
            "locator": rel(r.locator?.string),
        ]
        switch r {
        case let c as ColorResource:
            m["rgb"] = .integer(Int64(c.rgb))
        case let f as FontResource:
            if case .named(let d) = f.font { m["font"] = font(d) }
        case let s as StringResource:
            m["string"] = .string(s.string)
        case let a as AudioResource:
            m["files"] = .array(a.files.map { rel(JavaURI(filePath: $0).string) }.sorted { "\($0)" < "\($1)" })
        case let i as ImageResource:
            m["alternatives"] = uris(i.alternatives)
            m["variations"] = .array(i.variations.map { v in
                .object(["cachingKey": rel(v.cachingKey), "locator": rel(v.locator?.string),
                         "alternatives": uris(v.alternatives)])
            })
        default:
            break
        }
        return .object(m)
    }

    static func mapping(_ rm: ResourceMapping) -> JSONValue {
        .object(rm.allResources.mapValues(resource))
    }

    /// The client's merged mapping for a language.
    static func merged(_ languageId: String) throws -> ResourceMapping {
        try ResourceManager(dataDirectory: dataDirectory, languageId: languageId).merged
    }

    // MARK: Against Java

    @Test(arguments: ["en_US", "ru"])
    func mappingMatchesJava(_ languageId: String) throws {
        let diffs = elementDifferences(Self.mapping(try Self.merged(languageId)),
                                       try Self.javaDocument("mapping-\(languageId).json"))
        #expect(diffs.isEmpty, "\(diffs.count) differences, first: \(diffs.prefix(20).joined(separator: "\n"))")
    }

    /// The languages checked by digest: by default some with resource
    /// files of their own and some without (each takes a few seconds in
    /// a debug build); FREECOL_ALL_MAPS=1 checks every one.
    static let digestedLanguages: [String] = {
        ProcessInfo.processInfo.environment["FREECOL_ALL_MAPS"] == "1" ? Array(javaDigests.keys)
            : ["ar", "be-tarask", "de", "ja", "zh-hant", "zh_CN"]
    }()

    @Test func mappingsMatchJavaInOtherLanguages() throws {
        #expect(Self.javaDigests.count > 50)
        var failed: [String] = []
        for (id, digest) in Self.javaDigests.sorted(by: { $0.key < $1.key })
        where Self.digestedLanguages.contains(id) {
            let document = CanonicalJSON.document(Self.mapping(try Self.merged(id)))
            if Self.sha256(document) != digest {
                failed.append(id)
                if let path = ProcessInfo.processInfo.environment["FREECOL_DIFF_FILE"] {
                    try document.write(toFile: path + "-" + id, atomically: true, encoding: .utf8)
                }
            }
        }
        #expect(failed.isEmpty, "Languages that differ: \(failed)")
    }

    @Test func modMappingsMatchJava() throws {
        var mods: [String: JSONValue] = [:]
        let modsDirectory = Self.dataDirectory.appendingPathComponent("mods")
        for name in try FileManager.default.contentsOfDirectory(atPath: modsDirectory.path) {
            let dir = modsDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("mod.xml").path) else { continue }
            let rm = try FreeColDataFile(directory: dir).resourceMapping(languageId: "en_US")
            mods[name] = rm.map(Self.mapping)
        }
        let diffs = elementDifferences(.object(mods), try Self.javaDocument("mods.json"))
        #expect(diffs.isEmpty, "\(diffs.count) differences, first: \(diffs.prefix(20).joined(separator: "\n"))")
    }

    static let decoding: JSONValue = try! javaDocument("decoding.json")

    @Test func colorsDecodeAsInJava() throws {
        let colors = try #require(Self.decoding["colors"]?.objectValue)
        for (name, rgb) in colors {
            #expect(JSONValue.integer(Int64(JavaColor.decode(name))) == rgb, "\(name)")
        }
    }

    @Test func fontsDecodeAsInJava() throws {
        let fonts = try #require(Self.decoding["fonts"]?.objectValue)
        for (name, f) in fonts {
            #expect(Self.font(FontDescriptor.decode(name)) == f, "\(name)")
        }
    }

    @Test func animatedFontMatchesJava() throws {
        let java = try #require(Self.decoding["faf"])
        let faf = try FAFile(Data(contentsOf: Self.dataDirectory
            .appendingPathComponent("base/resources/fonts/signature.faf")))
        func points(_ p: [FAFile.Point]) -> JSONValue {
            .array(p.map { .array([.integer(Int64($0.x)), .integer(Int64($0.y))]) })
        }
        func entry(_ s: String) -> JSONValue {
            let d = faf.dimension(s)
            return .object(["width": .integer(Int64(d.width)), "height": .integer(Int64(d.height)),
                            "points": points(faf.points(s))])
        }
        var doc: [String: JSONValue] = ["maxHeight": .integer(Int64(faf.maxHeight))]
        doc["names"] = .object(Dictionary(uniqueKeysWithValues: faf.names.keys.map { ($0, entry($0)) }))
        doc["chars"] = .object(Dictionary(uniqueKeysWithValues: faf.letters.keys.map {
            let s = String(decoding: [$0], as: UTF16.self)
            return (s, entry(s))
        }))
        let text = faf.onlyValidCharacters("Thomas Jefferson")
        doc["text"] = .string(text)
        let d = faf.dimension(text)
        doc["textWidth"] = .integer(Int64(d.width))
        doc["textHeight"] = .integer(Int64(d.height))
        doc["textPoints"] = points(faf.points(text))
        let diffs = elementDifferences(.object(doc), java)
        #expect(diffs.isEmpty, "first: \(diffs.prefix(20).joined(separator: "\n"))")
    }

    @Test func animationsMatchJava() throws {
        let java = try #require(Self.decoding["sza"]?.objectValue)
        #expect(java.count > 10)
        var doc: [String: JSONValue] = [:]
        for key in java.keys {
            let sza = try SimpleZippedAnimation(contentsOf: Self.dataDirectory
                .appendingPathComponent(String(key.dropFirst("data/".count))))
            doc[key] = .object([
                "width": .integer(Int64(sza.width)), "height": .integer(Int64(sza.height)),
                "frames": .array(sza.frames.map {
                    .object(["duration": .integer(Int64($0.durationInMs)), "width": .integer(Int64($0.width)),
                             "height": .integer(Int64($0.height))])
                }),
            ])
        }
        let diffs = elementDifferences(.object(doc), .object(java))
        #expect(diffs.isEmpty, "first: \(diffs.prefix(20).joined(separator: "\n"))")
    }

    @Test func propertiesParseAsInJava() throws {
        let samples = try #require(Self.decoding["properties"]?.arrayValue)
        #expect(samples.count > 5)
        for sample in samples {
            let text = try #require(sample["text"]?.stringValue)
            // ISO 8859-1: one byte per character.
            let data = Data(text.unicodeScalars.map { UInt8($0.value) })
            let properties = try JavaProperties(data)
            let swift = JSONValue.object(properties.values.mapValues { .string($0) })
            #expect(swift == sample["properties"], "\(text.debugDescription)")
        }
    }

    // MARK: Behaviour

    @Test func malformedUnicodeEscapeFails() {
        #expect(throws: JavaPropertiesError.self) { try JavaProperties(Data("a=\\u12".utf8)) }
    }

    @Test func layersReplaceEarlierKeys() throws {
        let manager = try ResourceManager(dataDirectory: Self.dataDirectory, languageId: "en_US")
        let before = try #require(manager.imageResource("image.background.MiniMap"))
        let mod = ResourceMapping()
        let replacement = ImageResource(cachingKey: "x", locator: JavaURI(string: "file:/x.png"))
        mod.add("image.background.MiniMap", replacement)
        manager.setMods([mod])
        #expect(manager.imageResource("image.background.MiniMap") === replacement)
        manager.setMods([])
        #expect(manager.imageResource("image.background.MiniMap") === before)
    }

    @Test func missingLookupsUseJavaReplacements() throws {
        let manager = ResourceManager()
        #expect(manager.color("color.none") == ColorResource.replacementColor)
        #expect(manager.color("color.none", replacement: 7) == 7)
        #expect(manager.string("none") == "X")
        #expect(manager.string("none", default: nil) == nil)
    }

    @Test func keysNeedTheirKindsPrefix() {
        let rm = ResourceMapping()
        let color = ColorResource(cachingKey: "c", rgb: -1)
        #expect(!rm.add("image.wrong", color))
        #expect(rm.add("color.right", color))
        #expect(rm.duplicateResource("color.right", "color.copy"))
        #expect(rm.colorResources["color.copy"] === color)
    }

    // MARK: Data prepared for iOS

    /// With the Ogg files converted, sounds and playlists use the AAC
    /// files, while the mapping keeps Java's locators.
    @Test func convertedSoundsAreUsed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ios-formats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("music"),
                                                withIntermediateDirectories: true)
        for name in ["beep.m4a", "music/a.m4a", "music/b.m4a", "music/notes.txt", "intro.video.mp4"] {
            try Data([0]).write(to: dir.appendingPathComponent(name))
        }
        try Data("""
            sound.beep=beep.ogg
            sound.music.playlist=music
            sound.missing=missing.ogg
            video.intro=intro.video.ogg
            """.utf8).write(to: dir.appendingPathComponent("resources.properties"))
        let rm = try #require(try FreeColDataFile(directory: dir).resourceMapping(languageId: "en_US"))
        let beep = try #require(rm.audioResources["sound.beep"])
        #expect(beep.locator?.string.hasSuffix("/beep.ogg") == true)
        #expect(beep.files.map { ($0 as NSString).lastPathComponent } == ["beep.m4a"])
        let playlist = try #require(rm.audioResources["sound.music.playlist"])
        #expect(Set(playlist.files.map { ($0 as NSString).lastPathComponent }) == ["a.m4a", "b.m4a"])
        #expect(rm.audioResources["sound.missing"] == nil)
        #expect(rm.videoResources["video.intro"]?.url?.lastPathComponent == "intro.video.mp4")
    }

    static let iosData = ReferenceDumps.repositoryRoot.appendingPathComponent("build/ios-data")

    /// The data from swift/scripts/prepare-ios-data.sh, if it has been
    /// made, maps the same keys as data/, with every sound playable.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: iosData.path)))
    func preparedDataMapsTheSameKeys() throws {
        let original = try ResourceManager(dataDirectory: Self.dataDirectory, languageId: "en_US").merged
        let prepared = try ResourceManager(dataDirectory: Self.iosData, languageId: "en_US").merged
        // The video is left out without ffmpeg.
        let missing = Set(original.allResources.keys).subtracting(prepared.allResources.keys)
        #expect(missing.subtracting(["video.opening"]).isEmpty, "\(missing.sorted())")
        for (key, audio) in prepared.audioResources {
            #expect(!audio.files.isEmpty, "\(key)")
            #expect(audio.files.allSatisfy { !$0.hasSuffix(".ogg") }, "\(key)")
            #expect(audio.files.count == original.audioResources[key]?.files.count, "\(key)")
        }
    }

    @Test func propertyList() {
        let p = PropertyList("a=1,b=two,c=3")
        #expect(p.int("a", default: 0) == 1)
        #expect(p.string("b") == "two")
        #expect(p.int("missing", default: 9) == 9)
    }
}

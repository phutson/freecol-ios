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
import FreeColIO
import FreeColUtil

/// Something the client shows or plays: a colour, font, string,
/// animated font, animation, sound, video or image
/// (common/resources/Resource).
///
/// Resources here only describe and parse; decoding images and sound
/// and drawing belong to the user interface (Phase 5).  Resources are
/// classes, as in Java: a mapping can hold one resource under several
/// keys, and the loader adds to resources it has already made.
open class Resource: CustomStringConvertible {

    /// The key resources with the same data share: the URI of the
    /// data, not the mapping key, which a mod can change.
    public let cachingKey: String
    /// Where the data is.
    public let locator: JavaURI?

    public init(cachingKey: String, locator: JavaURI?) {
        self.cachingKey = cachingKey
        self.locator = locator
    }

    /// The Java class name, which the mapping keys its tables by.
    open var typeName: String { "Resource" }

    open var description: String {
        "\(typeName)(\(cachingKey))"
    }
}

/// A colour, from "urn:color:..." (common/resources/ColorResource).
public final class ColorResource: Resource {

    /// The colour Java uses when one is missing or bad: magenta.
    public static let replacementColor: Int32 = JavaColor.magenta

    public static let scheme = "color:"

    /// The colour as Java's Color.getRGB: alpha, red, green, blue.
    public let rgb: Int32

    public init(cachingKey: String, locator: JavaURI) {
        let name = String(locator.schemeSpecificPart.dropFirst(ColorResource.scheme.count))
        rgb = JavaColor.decode(name)
        super.init(cachingKey: cachingKey, locator: locator)
    }

    /// A colour made in code.
    public init(cachingKey: String, rgb: Int32) {
        self.rgb = rgb
        super.init(cachingKey: cachingKey, locator: nil)
    }

    public override var typeName: String { "ColorResource" }

    public var alpha: Int { Int((UInt32(bitPattern: rgb) >> 24) & 0xFF) }
    public var red: Int { Int((UInt32(bitPattern: rgb) >> 16) & 0xFF) }
    public var green: Int { Int((UInt32(bitPattern: rgb) >> 8) & 0xFF) }
    public var blue: Int { Int(UInt32(bitPattern: rgb) & 0xFF) }
}

/// A font: a TrueType file, or a logical font named as Java's
/// Font.decode reads it, from "urn:font:..."
/// (common/resources/FontResource).
public final class FontResource: Resource {

    public static let scheme = "font:"

    /// What the font is.
    public enum Font: Equatable, Sendable {
        /// A TrueType file.
        case file(URL)
        /// A font by name, style and size (Font.decode).
        case named(FontDescriptor)
    }

    public let font: Font

    /// - Returns: nil if the font file is missing, where Java's
    ///   Font.createFont fails.
    public init?(cachingKey: String, locator: JavaURI) {
        if let path = locator.path, path.hasSuffix(".ttf") {
            guard let url = locator.fileURL, FileManager.default.fileExists(atPath: url.path) else {
                return nil
            }
            font = .file(url)
        } else {
            font = .named(FontDescriptor.decode(
                String(locator.schemeSpecificPart.dropFirst(FontResource.scheme.count))))
        }
        super.init(cachingKey: cachingKey, locator: locator)
    }

    public override var typeName: String { "FontResource" }
}

/// A string, written in quotes in a mapping (common/resources/StringResource).
public final class StringResource: Resource {

    /// What Java shows for a missing string.
    public static let replacementString = "X"

    public let string: String

    public init(cachingKey: String, locator: JavaURI) {
        // Java takes the URI path, without the closing quote and up to
        // the last opening one.
        var data = locator.path ?? ""
        if data.hasSuffix("\"") { data.removeLast() }
        if let idx = data.lastIndex(of: "\""), idx > data.startIndex {
            data = String(data[data.index(after: idx)...])
        }
        string = data
        super.init(cachingKey: cachingKey, locator: locator)
    }

    public override var typeName: String { "StringResource" }
}

/// An animated font, for the signatures on the declaration of
/// independence (common/resources/FAFileResource).
public final class FAFileResource: Resource {

    public let faFile: FAFile

    /// - Returns: nil if the file can not be read or is not an
    ///   animated font.
    public init?(cachingKey: String, locator: JavaURI) {
        guard let url = locator.fileURL, let data = try? Data(contentsOf: url),
              let faf = try? FAFile(data) else { return nil }
        faFile = faf
        super.init(cachingKey: cachingKey, locator: locator)
    }

    public override var typeName: String { "FAFileResource" }
}

/// An animation, a zip of images and a list of how long to show each
/// (common/resources/SZAResource).  It is read when first asked for.
public final class SZAResource: Resource {

    private var animation: SimpleZippedAnimation?

    public override init(cachingKey: String, locator: JavaURI?) {
        super.init(cachingKey: cachingKey, locator: locator)
    }

    public override var typeName: String { "SZAResource" }

    /// The animation, or nil if it can not be read.
    public var simpleZippedAnimation: SimpleZippedAnimation? {
        if animation == nil, let url = locator?.fileURL {
            animation = try? SimpleZippedAnimation(contentsOf: url)
        }
        return animation
    }
}

/// A sound, or a directory of them to choose from at random, such as a
/// music playlist (common/resources/AudioResource).
public final class AudioResource: Resource {

    /// The paths of the sound files.
    public let files: [String]

    /// - Returns: nil if the file is missing.  Java also refuses files
    ///   it can not decode; decoding is left to the user interface.
    public init?(cachingKey: String, locator: JavaURI) {
        guard locator.fileURL != nil, var path = locator.path else { return nil }
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            // The data prepared for iOS has the Ogg files as AAC.
            guard let converted = IOSFormats.convertedAudio(path),
                  FileManager.default.fileExists(atPath: converted) else { return nil }
            path = converted
        }
        if isDirectory.boolValue {
            if path.hasSuffix("/") { path.removeLast() }
            let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
            files = names.filter { name in IOSFormats.audioSuffixes.contains { name.hasSuffix($0) } }
                .map { path + "/" + $0 }
        } else {
            files = [path]
        }
        super.init(cachingKey: cachingKey, locator: locator)
    }

    public override var typeName: String { "AudioResource" }

    /// A sound chosen at random, or nil if there are none.
    public func audio<G: RandomNumberGenerator>(using generator: inout G) -> URL? {
        files.randomElement(using: &generator).map { URL(fileURLWithPath: $0) }
    }
}

/// A video (common/resources/VideoResource).
public final class VideoResource: Resource {

    public override init(cachingKey: String, locator: JavaURI?) {
        super.init(cachingKey: cachingKey, locator: locator)
    }

    public override var typeName: String { "VideoResource" }

    /// The video file: the one named, or in the data prepared for iOS,
    /// the MPEG-4 file it was converted to.
    public var url: URL? {
        guard let path = locator?.path else { return nil }
        if !FileManager.default.fileExists(atPath: path), let converted = IOSFormats.convertedVideo(path),
           FileManager.default.fileExists(atPath: converted) {
            return URL(fileURLWithPath: converted)
        }
        return URL(fileURLWithPath: path)
    }
}

/// The formats the data prepared for iOS uses instead of Java's
/// (swift/scripts/prepare-ios-data.sh): iOS plays neither Ogg Vorbis
/// nor Theora, so sounds are AAC (".m4a") and the video MPEG-4
/// (".mp4").  The mappings still name the Java files, so caching keys
/// and locators stay as Java has them; only the file read changes.
public enum IOSFormats {

    /// The sound files found in a directory, such as a playlist: Java's
    /// Ogg and WAV, and the converted AAC.
    public static let audioSuffixes = [".ogg", ".wav", ".m4a"]

    /// The AAC file an Ogg sound was converted to.
    public static func convertedAudio(_ path: String) -> String? {
        path.hasSuffix(".ogg") && !path.hasSuffix(".video.ogg") ? String(path.dropLast(4)) + ".m4a" : nil
    }

    /// The MPEG-4 file an Ogg video was converted to.
    public static func convertedVideo(_ path: String) -> String? {
        path.hasSuffix(".video.ogg") ? String(path.dropLast(4)) + ".mp4" : nil
    }
}

/// An image, with copies at other sizes and variations to choose from
/// (common/resources/ImageResource).
///
/// Java keeps the decoded images here too; here the user interface
/// decodes them.  What is ported is which files go with an image:
/// - alternatives: the same image at other sizes ("name.size2.png"),
///   which Java loads to scale from the closest;
/// - variations: other pictures of the same thing ("name1.png",
///   "name2.png"), each with its own alternatives, for variety.
public final class ImageResource: Resource {

    /// The other sizes of the image, or nil if none were looked for.
    public private(set) var alternatives: [JavaURI]?
    /// The variations.  Java numbers them from 0, and this image comes
    /// after them.
    public private(set) var variations: [ImageResource] = []

    public override init(cachingKey: String, locator: JavaURI?) {
        super.init(cachingKey: cachingKey, locator: locator)
    }

    public override var typeName: String { "ImageResource" }

    public func addAlternatives(_ uris: [JavaURI]) {
        alternatives = (alternatives ?? []) + uris
    }

    public func addVariation(_ variation: ImageResource) {
        variations.append(variation)
    }

    /// The number of pictures: this one and its variations.
    public var numberOfVariations: Int {
        variations.count + 1
    }

    /// A variation by number, or this image for a number past them.
    /// (Java fails on a negative number; this gives the image.)
    public func variation(_ number: Int) -> ImageResource {
        number >= 0 && number < variations.count ? variations[number] : self
    }

    /// The variation number for a seed, as Java chooses it with
    /// `new Random(seed).nextInt(n)`.
    public func variationNumber(seed: Int32) -> Int {
        let random = JavaRandom(seed: Int64(seed))
        return Int(random.nextInt(Int32(variations.count + 1)))
    }

    /// The variation number for an animation tick.
    public func variationNumber(ticks: Int64) -> Int {
        Int(ticks % Int64(variations.count + 1))
    }

    /// All the files of this image: itself and its other sizes.
    public var allLocators: [JavaURI] {
        (locator.map { [$0] } ?? []) + (alternatives ?? [])
    }
}

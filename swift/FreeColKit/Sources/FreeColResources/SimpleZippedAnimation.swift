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

/// An animation in a zip file: images, and "animation.txt" listing
/// them in order as "FILENAME (TIMEms)"
/// (common/io/sza/SimpleZippedAnimation).
///
/// Java decodes the images here; here each frame keeps its image data
/// and size, and the user interface decodes it.
public struct SimpleZippedAnimation: Sendable {

    public static let animationDescriptorFile = "animation.txt"

    /// One image of the animation and how long to show it.
    public struct Frame: Sendable {
        /// The image's name in the zip.
        public let name: String
        /// The image file's data.
        public let imageData: Data
        public let width: Int
        public let height: Int
        public let durationInMs: Int
    }

    public let frames: [Frame]
    /// The size of the largest frame.
    public let width: Int
    public let height: Int

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    /// - Throws: SimpleZippedAnimationError if the descriptor is missing
    ///   or bad, or names an image that is missing or not an image.
    public init(data: Data) throws {
        let zip = try ZipArchive(data: data)
        guard let descriptor = try zip.contents(of: Self.animationDescriptorFile) else {
            throw SimpleZippedAnimationError("\(Self.animationDescriptorFile) is missing from the SZA")
        }
        let text = String(decoding: descriptor, as: UTF8.self)
        var lines: [String] = []
        text.enumerateLines { line, _ in lines.append(line) }
        guard !lines.isEmpty else {
            throw SimpleZippedAnimationError("\(Self.animationDescriptorFile) is missing from the SZA")
        }
        var frames: [Frame] = []
        for line in lines {
            let units = Array(line.utf16)
            let open = units.firstIndex(of: UInt16(UInt8(ascii: "(")))
            let ms = Self.indexOf(units, Array("ms)".utf16))
            guard let open, let ms, ms > open else {
                throw SimpleZippedAnimationError("\(Self.animationDescriptorFile) should use the format:"
                    + " FILNAME (TIMEms) in: \(line)")
            }
            let name = String(decoding: units[..<open], as: UTF16.self)
                .trimmingCharacters(in: .javaWhitespace)
            guard let duration = JavaString.parseInt(String(decoding: units[(open + 1)..<ms], as: UTF16.self))
            else { throw SimpleZippedAnimationError("Bad time in: \(line)") }
            guard let imageData = try zip.contents(of: name), let size = ImageSize.of(imageData) else {
                throw SimpleZippedAnimationError("Could not find referenced image: \(name)")
            }
            frames.append(Frame(name: name, imageData: imageData, width: size.width, height: size.height,
                                durationInMs: Int(duration)))
        }
        self.frames = frames
        width = frames.map(\.width).max() ?? 0
        height = frames.map(\.height).max() ?? 0
    }

    /// The first place a sequence of code units starts, if any.
    private static func indexOf(_ s: [UInt16], _ pattern: [UInt16]) -> Int? {
        guard pattern.count <= s.count else { return nil }
        return (0...(s.count - pattern.count)).first { s[$0..<($0 + pattern.count)].elementsEqual(pattern) }
    }

    /// The size Java gives a scaled copy (createScaledVersion).
    public func scaledSize(_ scale: Float) -> (width: Int, height: Int) {
        (Int(JavaMath.toInt(Float(width) * scale)), Int(JavaMath.toInt(Float(height) * scale)))
    }
}

/// A bad animation file.
public struct SimpleZippedAnimationError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

/// The pixel size of a PNG or JPEG image, from its header.
public enum ImageSize {

    /// The width and height, or nil if the data is not a PNG or JPEG.
    public static func of(_ data: Data) -> (width: Int, height: Int)? {
        let b = [UInt8](data.prefix(64 * 1024))
        func be16(_ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
        func be32(_ i: Int) -> Int { be16(i) << 16 | be16(i + 2) }
        // PNG: the signature, then the IHDR chunk with width and height.
        if b.count >= 24, b[0..<8].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return (be32(16), be32(20))
        }
        // JPEG: the first start-of-frame segment.
        if b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 {
            var i = 2
            while i + 9 < b.count {
                guard b[i] == 0xFF else { return nil }
                let marker = b[i + 1]
                if (0xC0...0xCF).contains(marker) && ![0xC4, 0xC8, 0xCC].contains(marker) {
                    return (be16(i + 7), be16(i + 5))
                }
                i += 2 + be16(i + 2)
            }
        }
        return nil
    }
}

extension CharacterSet {
    /// What Java's String.trim removes: everything up to a space.
    static let javaWhitespace = CharacterSet(charactersIn: Unicode.Scalar(0)...Unicode.Scalar(0x20))
}

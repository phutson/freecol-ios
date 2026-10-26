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

/// A URI as Java's resource code uses it: the string Java would write,
/// which resources keep as their caching key and locator, and the file
/// it names, if it is a file.
///
/// Java makes them three ways: `new URI("urn:...")` for colours and
/// fonts, `File.toURI()` for the files a mapping names ("file:/a/b",
/// with a slash after a directory), and `Path.toUri()` for the image
/// sizes and variations found by listing a directory ("file:///a/b").
public struct JavaURI: Hashable, Sendable, CustomStringConvertible {

    /// The URI as Java writes it.
    public let string: String
    /// The file, for a file URI.
    public let fileURL: URL?

    /// A URI that is not a file, such as "urn:color:0xffffff".
    public init(string: String) {
        self.string = string
        fileURL = nil
    }

    /// A file's URI as `File.toURI()` writes it.
    public init(file url: URL) {
        self.init(filePath: url.path)
    }

    /// A file's URI as `File.toURI()` writes it, from its path.  Paths
    /// are kept as given: Java does not resolve "." or "..", nor change
    /// the Unicode normalization, which going through a URL's path
    /// would.
    public init(filePath path: String) {
        string = "file:" + JavaURI.quote(JavaURI.slashify(path), encodeNonASCII: false)
        fileURL = URL(fileURLWithPath: path)
    }

    /// A file's URI as `Path.toUri()` writes it.
    public init(path url: URL) {
        self.init(pathString: url.path)
    }

    /// A file's URI as `Path.toUri()` writes it, from its path.
    public init(pathString path: String) {
        string = "file://" + JavaURI.quote(JavaURI.slashify(path), encodeNonASCII: true)
        fileURL = URL(fileURLWithPath: path)
    }

    public var description: String {
        string
    }

    /// The scheme, such as "urn" or "file".
    public var scheme: String? {
        string.firstIndex(of: ":").map { String(string[..<$0]) }
    }

    /// Everything after the scheme, decoded (URI.getSchemeSpecificPart).
    public var schemeSpecificPart: String {
        guard let colon = string.firstIndex(of: ":") else { return string }
        let rest = String(string[string.index(after: colon)...])
        return rest.removingPercentEncoding ?? rest
    }

    /// The decoded path of a file URI, or nil for a urn
    /// (URI.getPath).
    public var path: String? {
        guard fileURL != nil else { return nil }
        var rest = schemeSpecificPart
        if rest.hasPrefix("//") { rest.removeFirst(2) }
        return rest
    }

    /// Java's File.slashify: a slash after a directory.
    private static func slashify(_ path: String) -> String {
        var isDirectory: ObjCBool = false
        if !path.hasSuffix("/"),
           FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
            return path + "/"
        }
        return path
    }

    /// Quote the characters a URI path can not hold, as java.net.URI
    /// does (and, for Path.toUri, all non-ASCII characters too).
    static func quote(_ path: String, encodeNonASCII: Bool) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'();:@&=+$,/".utf8)
        var result = ""
        for scalar in path.unicodeScalars {
            if scalar.isASCII {
                let b = UInt8(scalar.value)
                if allowed.contains(b) {
                    result.unicodeScalars.append(scalar)
                } else {
                    result += String(format: "%%%02X", b)
                }
            } else if encodeNonASCII || scalar.properties.generalCategory == .control
                || scalar.properties.isWhitespace {
                for b in String(scalar).utf8 { result += String(format: "%%%02X", b) }
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

/// A directory of FreeCol data, such as data/base or a mod
/// (common/io/FreeColDataFile).
///
/// Java also reads zipped data files; only directories are supported
/// here, which is all the bundled data uses.
public struct FreeColDataFile: Sendable {

    /// The directory.
    public let directory: URL

    /// - Throws: FreeColDataFileError if the directory does not exist.
    public init(directory: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FreeColDataFileError("File \(directory.lastPathComponent) does not exist")
        }
        self.directory = directory.standardizedFileURL
    }

    /// The URI of a name in this data file: a urn as it is, otherwise
    /// the file it names here (FreeColDataFile.getURI).
    public func uri(_ name: String) -> JavaURI {
        if name.hasPrefix("urn:") { return JavaURI(string: name) }
        return JavaURI(filePath: filePath(name))
    }

    /// The path a name stands for, as `new File(directory, name)` makes
    /// it: repeated slashes and a final slash are dropped.
    public func filePath(_ name: String) -> String {
        var normalized = ""
        for c in name where !(c == "/" && normalized.hasSuffix("/")) { normalized.append(c) }
        if normalized.count > 1, normalized.hasSuffix("/") { normalized.removeLast() }
        if normalized.hasPrefix("/") { normalized.removeFirst() }
        return normalized.isEmpty ? directory.path : directory.path + "/" + normalized
    }

    /// The file a name stands for.
    public func fileURL(_ name: String) -> URL {
        URL(fileURLWithPath: filePath(name))
    }

    /// The contents of a file here, or nil if there is none.
    public func data(_ name: String) -> Data? {
        try? Data(contentsOf: fileURL(name))
    }
}

/// A data file that can not be used.
public struct FreeColDataFileError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

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

/// Java's java.util.Properties, as `load(InputStream)` reads it: the
/// resource mappings (resources*.properties) use this format, unlike
/// the message files, which FreeCol reads line by line itself.
///
/// The format:
/// - the bytes are ISO 8859-1, one character each;
/// - lines end at `\n`, `\r` or `\r\n`, and a line ending in an odd
///   number of backslashes continues on the next, whose leading white
///   space is dropped;
/// - white space is space, tab and form feed; a line whose first
///   non-white character is `#` or `!` is a comment;
/// - the key ends at the first unescaped `=`, `:` or white space; then
///   white space, at most one `=` or `:`, and more white space are
///   skipped, and the rest is the value;
/// - `\t`, `\n`, `\r`, `\f` and `\uXXXX` are escapes, and a backslash
///   before any other character stands for that character.
///
/// Loading again adds to the properties, replacing the values of keys
/// already there.
public struct JavaProperties: Sendable {

    /// The properties, by key.
    public private(set) var values: [String: String] = [:]

    public init() {}

    /// Properties read from data.
    ///
    /// - Throws: JavaPropertiesError for a malformed `\u` escape, as
    ///   Java throws IllegalArgumentException.
    public init(_ data: Data) throws {
        try load(data)
    }

    public subscript(key: String) -> String? {
        values[key]
    }

    public var keys: Dictionary<String, String>.Keys {
        values.keys
    }

    public var isEmpty: Bool {
        values.isEmpty
    }

    public mutating func put(_ key: String, _ value: String) {
        values[key] = value
    }

    /// Read more properties.
    public mutating func load(_ data: Data) throws {
        // ISO 8859-1: each byte is the character with that code.
        let chars = data.map { UInt16($0) }
        var lines = LineReader(chars)
        while let line = lines.next() {
            let n = line.count
            var keyLen = 0
            var valueStart = n
            var hasSep = false
            var precedingBackslash = false
            while keyLen < n {
                let c = line[keyLen]
                if (c == eq || c == colon) && !precedingBackslash {
                    valueStart = keyLen + 1
                    hasSep = true
                    break
                } else if isWhite(c) && !precedingBackslash {
                    valueStart = keyLen + 1
                    break
                }
                precedingBackslash = c == backslash ? !precedingBackslash : false
                keyLen += 1
            }
            while valueStart < n {
                let c = line[valueStart]
                if !isWhite(c) {
                    if !hasSep && (c == eq || c == colon) {
                        hasSep = true
                    } else {
                        break
                    }
                }
                valueStart += 1
            }
            let key = try Self.unescape(line[0..<keyLen])
            let value = try Self.unescape(line[min(valueStart, n)..<n])
            values[key] = value
        }
    }

    // MARK: Lines

    /// Java's LineReader: logical lines, without comments, blank lines,
    /// leading white space or line continuations.
    private struct LineReader {
        let chars: [UInt16]
        var pos = 0

        init(_ chars: [UInt16]) {
            self.chars = chars
        }

        mutating func next() -> [UInt16]? {
            var line: [UInt16] = []
            var skipWhiteSpace = true
            var appendedLineBegin = false
            var precedingBackslash = false
            var skipLF = false
            while true {
                guard pos < chars.count else {
                    if line.isEmpty { return nil }
                    // A backslash at the end of the input is dropped.
                    if precedingBackslash { line.removeLast() }
                    return line
                }
                let c = chars[pos]
                pos += 1
                if skipLF {
                    skipLF = false
                    if c == lf { continue }
                }
                if skipWhiteSpace {
                    if isWhite(c) { continue }
                    if !appendedLineBegin && (c == cr || c == lf) { continue }
                    skipWhiteSpace = false
                    appendedLineBegin = false
                }
                if line.isEmpty && (c == hash || c == bang) {
                    // A comment: skip the rest of the natural line.
                    while pos < chars.count, chars[pos] != lf, chars[pos] != cr { pos += 1 }
                    skipWhiteSpace = true
                    continue
                }
                if c != lf && c != cr {
                    line.append(c)
                    precedingBackslash = c == backslash ? !precedingBackslash : false
                    continue
                }
                // The end of a natural line.
                if line.isEmpty {
                    skipWhiteSpace = true
                    continue
                }
                if pos >= chars.count {
                    if precedingBackslash { line.removeLast() }
                    return line
                }
                guard precedingBackslash else { return line }
                // The backslash continues the line on the next, without
                // its leading white space or the \n of a \r\n.
                line.removeLast()
                skipWhiteSpace = true
                appendedLineBegin = true
                precedingBackslash = false
                if c == cr { skipLF = true }
            }
        }
    }

    // MARK: Escapes

    /// Java's loadConvert.
    private static func unescape(_ chars: ArraySlice<UInt16>) throws -> String {
        var out: [UInt16] = []
        var i = chars.startIndex
        while i < chars.endIndex {
            var c = chars[i]
            i += 1
            if c == backslash {
                // A backslash at the very end stands for nothing.
                guard i < chars.endIndex else { break }
                c = chars[i]
                i += 1
                if c == UInt16(UInt8(ascii: "u")) {
                    var value: UInt16 = 0
                    for _ in 0..<4 {
                        guard i < chars.endIndex, let d = hexValue(chars[i]) else {
                            throw JavaPropertiesError("Malformed \\uxxxx encoding.")
                        }
                        value = (value << 4) + d
                        i += 1
                    }
                    out.append(value)
                } else {
                    switch c {
                    case UInt16(UInt8(ascii: "t")): out.append(tab)
                    case UInt16(UInt8(ascii: "r")): out.append(cr)
                    case UInt16(UInt8(ascii: "n")): out.append(lf)
                    case UInt16(UInt8(ascii: "f")): out.append(ff)
                    default: out.append(c)
                    }
                }
            } else {
                out.append(c)
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    private static func hexValue(_ c: UInt16) -> UInt16? {
        switch c {
        case 0x30...0x39: c - 0x30
        case 0x41...0x46: c - 0x41 + 10
        case 0x61...0x66: c - 0x61 + 10
        default: nil
        }
    }
}

/// A malformed properties document.
public struct JavaPropertiesError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

private let lf: UInt16 = 0x0A
private let cr: UInt16 = 0x0D
private let tab: UInt16 = 0x09
private let ff: UInt16 = 0x0C
private let space: UInt16 = 0x20
private let eq = UInt16(UInt8(ascii: "="))
private let colon = UInt16(UInt8(ascii: ":"))
private let hash = UInt16(UInt8(ascii: "#"))
private let bang = UInt16(UInt8(ascii: "!"))
private let backslash = UInt16(UInt8(ascii: "\\"))

private func isWhite(_ c: UInt16) -> Bool {
    c == space || c == tab || c == ff
}

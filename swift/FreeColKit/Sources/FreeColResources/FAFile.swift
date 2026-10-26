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
import FreeColUtil

/// A font animation file (common/resources/FAFile): the points to draw,
/// in order, to write a text by hand, as the signatures on the
/// declaration of independence are drawn.
///
/// The file has a header line "FontAnimationFile", the maximum height,
/// then whole names (each a line with the name, a line "width height
/// count", and lines of x and y), then "[Chars]" and the letters (each
/// a line starting with the letter, then "advance count", and lines of
/// x and y).  Carriage returns are ignored.
public struct FAFile: Sendable {

    public struct Point: Hashable, Sendable {
        public let x: Int
        public let y: Int

        public init(_ x: Int, _ y: Int) {
            self.x = x
            self.y = y
        }
    }

    /// A name drawn as a whole.
    public struct Name: Sendable {
        public let points: [Point]
        public let width: Int
        public let height: Int
    }

    /// A letter: its points and how far it moves the pen.
    public struct Letter: Sendable {
        public let points: [Point]
        public let advance: Int
    }

    public private(set) var maxHeight = 0
    /// The names, by name.
    public private(set) var names: [String: Name] = [:]
    /// The letters, by UTF-16 code unit, as Java's chars.
    public private(set) var letters: [UInt16: Letter] = [:]

    /// Read an animated font.
    ///
    /// - Throws: FAFileError if it is not one, or a number is bad (where
    ///   Java throws a RuntimeException).
    public init(_ data: Data) throws {
        let text = String(decoding: data.filter { $0 != 0x0D }, as: UTF8.self)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // BufferedReader has no line after a final newline.
        if text.hasSuffix("\n") { lines.removeLast() }
        var index = 0
        func readLine() -> String? {
            guard index < lines.count else { return nil }
            defer { index += 1 }
            return lines[index]
        }
        func tokens(_ line: String) -> [Substring] {
            line.split(whereSeparator: { " \t\n\r\u{0C}".contains($0) })
        }
        func int(_ s: Substring?) throws -> Int {
            guard let s, let v = JavaString.parseInt(String(s)) else {
                throw FAFileError("Bad number in FAF: \(s ?? "nothing")")
            }
            return Int(v)
        }
        func numbers(_ line: String, _ count: Int) throws -> [Int] {
            let t = tokens(line)
            return try (0..<count).map { try int($0 < t.count ? t[$0] : nil) }
        }

        guard let header = readLine(), header.hasPrefix("FontAnimationFile") else {
            throw FAFileError("Not a FAF")
        }
        guard let heightLine = readLine() else { throw FAFileError("Max height expected") }
        maxHeight = try int(tokens(heightLine).first)

        var line = readLine()
        while let name = line, !name.hasPrefix("[Chars]") {
            guard let sizeLine = readLine() else { break }
            let size = try numbers(sizeLine, 3)
            guard let xLine = readLine() else { break }
            let xs = try numbers(xLine, size[2])
            guard let yLine = readLine() else { break }
            let ys = try numbers(yLine, size[2])
            names[name] = Name(points: zip(xs, ys).map { Point($0, $1) }, width: size[0], height: size[1])
            line = readLine()
        }

        line = readLine()
        while let letterLine = line {
            guard let letter = letterLine.utf16.first else { throw FAFileError("Empty letter line") }
            let rest = String(decoding: letterLine.utf16.dropFirst(), as: UTF16.self)
            let header = try numbers(rest, 2)
            guard let xLine = readLine() else { break }
            let xs = try numbers(xLine, header[1])
            guard let yLine = readLine() else { break }
            let ys = try numbers(yLine, header[1])
            letters[letter] = Letter(points: zip(xs, ys).map { Point($0, $1) }, advance: header[0])
            line = readLine()
        }
    }

    /// The text without the letters this font lacks.
    public func onlyValidCharacters(_ text: String) -> String {
        String(decoding: text.utf16.filter { letters[$0] != nil }, as: UTF16.self)
    }

    /// The size of a name, or of a text drawn letter by letter: the
    /// advances, plus the first letter's leftmost and the last
    /// letter's rightmost point, by the maximum height.  Every letter
    /// must be in the font.
    public func dimension(_ text: String) -> (width: Int, height: Int) {
        if let name = names[text] { return (name.width, name.height) }
        let units = Array(text.utf16)
        var width: Int32 = 0
        for c in units { width &+= Int32(letters[c]!.advance) }
        // Int.MAX_VALUE if the first letter has no points, as in Java.
        var firstMinX = Int32.max
        for p in letters[units[0]]!.points where Int32(p.x) < firstMinX { firstMinX = Int32(p.x) }
        width &+= firstMinX
        var lastMaxX: Int32 = 0
        for p in letters[units[units.count - 1]]!.points where Int32(p.x) > lastMaxX { lastMaxX = Int32(p.x) }
        width &+= lastMaxX
        return (Int(width), maxHeight)
    }

    /// The points to draw a name, or a text letter by letter.
    public func points(_ text: String) -> [Point] {
        if let name = names[text] { return name.points }
        var result: [Point] = []
        var x = 0
        for c in text.utf16 {
            let letter = letters[c]!
            for p in letter.points { result.append(Point(p.x + x, p.y)) }
            x += letter.advance
        }
        return result
    }
}

/// A file that is not an animated font.
public struct FAFileError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

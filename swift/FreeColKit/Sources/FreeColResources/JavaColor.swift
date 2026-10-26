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

import FreeColUtil

/// Colours as Java's ColorResource decodes them: "0x" and hex digits
/// (with alpha if more than six digits), or the name of one of
/// java.awt.Color's constants.  Anything else is magenta.
public enum JavaColor {

    public static let magenta: Int32 = argb(255, 0, 255)

    /// java.awt.Color's named constants, in both spellings Java has.
    static let named: [String: Int32] = {
        let colors: [(String, String, Int32)] = [
            ("white", "WHITE", argb(255, 255, 255)),
            ("lightGray", "LIGHT_GRAY", argb(192, 192, 192)),
            ("gray", "GRAY", argb(128, 128, 128)),
            ("darkGray", "DARK_GRAY", argb(64, 64, 64)),
            ("black", "BLACK", argb(0, 0, 0)),
            ("red", "RED", argb(255, 0, 0)),
            ("pink", "PINK", argb(255, 175, 175)),
            ("orange", "ORANGE", argb(255, 200, 0)),
            ("yellow", "YELLOW", argb(255, 255, 0)),
            ("green", "GREEN", argb(0, 255, 0)),
            ("magenta", "MAGENTA", argb(255, 0, 255)),
            ("cyan", "CYAN", argb(0, 255, 255)),
            ("blue", "BLUE", argb(0, 0, 255)),
        ]
        var result: [String: Int32] = [:]
        for (a, b, value) in colors {
            result[a] = value
            result[b] = value
        }
        return result
    }()

    /// An opaque colour.
    static func argb(_ r: Int32, _ g: Int32, _ b: Int32) -> Int32 {
        Int32(bitPattern: 0xFF00_0000) | (r << 16) | (g << 8) | b
    }

    /// A colour name as ColorResource.createColor reads it.
    public static func decode(_ name: String) -> Int32 {
        if isHexString(name) {
            // Long.decode, which fails above Long.MAX_VALUE, then the
            // int it is cast to; more than eight characters ("0x" and
            // six digits) means the colour has alpha.
            var value: UInt64 = 0
            for c in name.utf8.dropFirst(2) {
                let (shifted, overflow) = value.multipliedReportingOverflow(by: 16)
                guard !overflow else { return magenta }
                value = shifted + UInt64(hexValue(c))
            }
            guard value <= UInt64(Int64.max) else { return magenta }
            let rgba = Int32(truncatingIfNeeded: value)
            return name.utf16.count > 8 ? rgba : Int32(bitPattern: 0xFF00_0000) | rgba
        }
        return named[name] ?? magenta
    }

    private static func isHexString(_ s: String) -> Bool {
        guard s.hasPrefix("0x") || s.hasPrefix("0X"), s.utf8.count > 2 else { return false }
        return s.utf8.dropFirst(2).allSatisfy { hexValue($0) >= 0 }
    }

    private static func hexValue(_ c: UInt8) -> Int {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): Int(c - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f"): Int(c - UInt8(ascii: "a")) + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): Int(c - UInt8(ascii: "A")) + 10
        default: -1
        }
    }
}

/// A font by name, style and size, as java.awt.Font.decode reads
/// "name-style-size" or "name style size".
public struct FontDescriptor: Equatable, Sendable {

    public static let plain = 0
    public static let bold = 1
    public static let italic = 2

    public let name: String
    /// Plain, bold, italic, or bold and italic (3).
    public let style: Int
    public let size: Int

    public init(name: String, style: Int, size: Int) {
        self.name = name
        self.style = style
        self.size = size
    }

    /// Java's Font.decode.
    public static func decode(_ str: String) -> FontDescriptor {
        let s = Array(str.utf16)
        let strlen = s.count
        let hyphen = UInt16(UInt8(ascii: "-")), space = UInt16(UInt8(ascii: " "))
        func lastIndex(of c: UInt16, before end: Int) -> Int {
            var i = min(end, strlen - 1)
            while i >= 0 {
                if s[i] == c { return i }
                i -= 1
            }
            return -1
        }
        func text(_ from: Int, _ to: Int) -> String {
            String(decoding: s[from..<to], as: UTF16.self)
        }
        var fontSize = 12
        var fontStyle = plain
        let lastHyphen = lastIndex(of: hyphen, before: strlen - 1)
        let lastSpace = lastIndex(of: space, before: strlen - 1)
        let sepChar = lastHyphen > lastSpace ? hyphen : space
        var sizeIndex = lastIndex(of: sepChar, before: strlen - 1)
        var styleIndex = lastIndex(of: sepChar, before: sizeIndex - 1)

        if sizeIndex > 0 && sizeIndex + 1 < strlen {
            if let size = JavaString.parseInt(text(sizeIndex + 1, strlen)) {
                fontSize = Int(size)
                if fontSize <= 0 { fontSize = 12 }
            } else {
                // Not a size: perhaps the style.
                styleIndex = sizeIndex
                sizeIndex = strlen
                if s[sizeIndex - 1] == sepChar { sizeIndex -= 1 }
            }
        }

        let fontName: String
        if styleIndex >= 0 && styleIndex + 1 < strlen {
            let styleName = text(styleIndex + 1, sizeIndex).lowercased()
            switch styleName {
            case "bolditalic": fontStyle = bold | italic
            case "italic": fontStyle = italic
            case "bold": fontStyle = bold
            case "plain": fontStyle = plain
            default:
                // Not a style: part of the name.
                styleIndex = sizeIndex
                if s[styleIndex - 1] == sepChar { styleIndex -= 1 }
            }
            fontName = text(0, styleIndex)
        } else {
            var fontEnd = strlen
            if styleIndex > 0 {
                fontEnd = styleIndex
            } else if sizeIndex > 0 {
                fontEnd = sizeIndex
            }
            if fontEnd > 0 && s[fontEnd - 1] == sepChar { fontEnd -= 1 }
            fontName = text(0, fontEnd)
        }
        return FontDescriptor(name: fontName, style: fontStyle, size: fontSize)
    }
}

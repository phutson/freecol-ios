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

/// Java's String semantics, where Swift's differ.
///
/// Java strings are sequences of UTF-16 code units, and comparison,
/// hashing and indexing all work on those units.  Swift compares and
/// indexes by Unicode characters, which orders some strings
/// differently (U+FFFF sorts after U+1F600 in Swift, before it in Java).
public enum JavaString {

    /// Java's `String.hashCode()`.
    ///
    /// Java's HashMap iteration order follows this, so ported code that
    /// depends on that order needs the same values.
    public static func hashCode(_ s: String) -> Int32 {
        var h: Int32 = 0
        for unit in s.utf16 {
            h = 31 &* h &+ Int32(unit)
        }
        return h
    }

    /// Java's `String.compareTo`: negative, zero or positive by UTF-16
    /// code units, then by length.
    public static func compare(_ a: String, _ b: String) -> Int {
        var ia = a.utf16.makeIterator()
        var ib = b.utf16.makeIterator()
        while true {
            switch (ia.next(), ib.next()) {
            case let (x?, y?):
                if x != y { return Int(x) - Int(y) }
            case (nil, nil):
                return 0
            case (nil, _):
                return -(b.utf16.count - a.utf16.count)
            case (_, nil):
                return a.utf16.count - b.utf16.count
            }
        }
    }

    /// Java's `Integer.parseInt(s)`.
    ///
    /// Accepts an optional sign and any Unicode decimal digits (Java's
    /// Character.digit), not just ASCII ones.
    ///
    /// - Returns: The value, or nil where Java throws
    ///   NumberFormatException (no digits, bad characters, overflow).
    public static func parseInt(_ s: String) -> Int32? {
        let units = Array(s.utf16)
        guard !units.isEmpty else { return nil }
        var index = 0
        var negative = false
        if units[0] == UInt16(UInt8(ascii: "-")) || units[0] == UInt16(UInt8(ascii: "+")) {
            negative = units[0] == UInt16(UInt8(ascii: "-"))
            index = 1
            guard units.count > 1 else { return nil }
        }
        // Accumulate negatively, as Java does, so Int32.min fits.
        var result: Int64 = 0
        while index < units.count {
            guard let digit = decimalDigit(units[index]) else { return nil }
            result = result * 10 - Int64(digit)
            if result < Int64(Int32.min) { return nil }
            index += 1
        }
        if !negative {
            result = -result
            if result > Int64(Int32.max) { return nil }
        }
        return Int32(result)
    }

    /// Java's `Integer.decode(s)`: an optional sign, then "0x", "0X" or
    /// "#" for hex, a leading "0" for octal ("010" is 8), otherwise
    /// decimal.  No surrounding whitespace is allowed.
    ///
    /// - Returns: The value, or nil where Java throws.
    public static func decodeIntOrNil(_ s: String) -> Int32? {
        decode(s, min: Int64(Int32.min), max: Int64(Int32.max)).map { Int32($0) }
    }

    /// Java's `Long.decode(s)`, returning nil where Java throws.
    public static func decodeLongOrNil(_ s: String) -> Int64? {
        // Accumulate in Int64 negatively, so Int64.min fits.
        var units = Substring(s)
        guard !units.isEmpty else { return nil }
        var negative = false
        if units.first == "-" || units.first == "+" {
            negative = units.first == "-"
            units = units.dropFirst()
        }
        var radix: Int64 = 10
        if units.hasPrefix("0x") || units.hasPrefix("0X") {
            radix = 16
            units = units.dropFirst(2)
        } else if units.hasPrefix("#") {
            radix = 16
            units = units.dropFirst()
        } else if units.hasPrefix("0") && units.count > 1 {
            radix = 8
            units = units.dropFirst()
        }
        // Java rejects a second sign after the prefix.
        guard !units.isEmpty, units.first != "-", units.first != "+" else { return nil }
        var result: Int64 = 0
        for ch in units {
            guard let d = ch.hexDigitValue, Int64(d) < radix else { return nil }
            let (m, o1) = result.multipliedReportingOverflow(by: radix)
            let (r, o2) = m.subtractingReportingOverflow(Int64(d))
            if o1 || o2 { return nil }
            result = r
        }
        if negative { return result }
        let (r, o) = Int64(0).subtractingReportingOverflow(result)
        return o ? nil : r
    }

    private static func decode(_ s: String, min: Int64, max: Int64) -> Int64? {
        guard let v = decodeLongOrNil(s), v >= min, v <= max else { return nil }
        return v
    }

    /// Java's `Float.parseFloat(s)`, returning nil where Java throws.
    ///
    /// Java trims surrounding whitespace and control characters and
    /// accepts a trailing type letter ("1.5f").
    public static func parseFloat(_ s: String) -> Float? {
        guard var t = javaTrimmed(s).nilIfEmpty else { return nil }
        switch t {
        case "NaN", "+NaN", "-NaN": return .nan
        case "Infinity", "+Infinity": return .infinity
        case "-Infinity": return -.infinity
        default: break
        }
        let unsigned = t.drop { $0 == "+" || $0 == "-" }
        if unsigned.hasPrefix("0x") || unsigned.hasPrefix("0X") {
            // Hex floats need a binary exponent in Java ("0x1p3" is 8).
            if let last = t.last, "fFdD".contains(last), t.contains(where: { "pP".contains($0) }) {
                t = String(t.dropLast())
            }
            guard t.contains(where: { "pP".contains($0) }),
                  t.dropFirst(t.count - unsigned.count + 2)
                    .allSatisfy({ $0.isHexDigit || "pP.+-".contains($0) }) else { return nil }
            return Float(t)
        }
        if let last = t.last, "fFdD".contains(last) { t = String(t.dropLast()) }
        // Swift accepts forms Java does not ("inf", "nan"), so only
        // decimal characters are let through.
        guard t.allSatisfy({ "0123456789+-.eE".contains($0) }) else { return nil }
        return Float(t)
    }

    /// Java's `Boolean.parseBoolean(s)`: true only for "true" in any case.
    public static func parseBoolean(_ s: String?) -> Bool {
        s?.lowercased() == "true"
    }

    /// Java's `String.trim()`: removes leading and trailing characters
    /// up to and including the space.
    public static func javaTrimmed(_ s: String) -> String {
        let units = Array(s.utf16)
        var start = 0, end = units.count
        while start < end, units[start] <= 0x20 { start += 1 }
        while end > start, units[end - 1] <= 0x20 { end -= 1 }
        return String(decoding: units[start..<end], as: UTF16.self)
    }

    /// The decimal digit value of one UTF-16 unit, like Java's
    /// Character.digit(char, 10).  Surrogates are never digits.
    private static func decimalDigit(_ unit: UInt16) -> Int? {
        guard let scalar = Unicode.Scalar(unit),
              scalar.properties.numericType == .decimal,
              let value = scalar.properties.numericValue else { return nil }
        return Int(value)
    }

    /// FreeCol's `StringUtils.lastPart`: the part after the last
    /// delimiter, or the whole string if there is none.
    public static func lastPart(_ s: String, _ delimiter: String) -> String {
        let units = Array(s.utf16)
        let delim = Array(delimiter.utf16)
        guard !delim.isEmpty, units.count >= delim.count else {
            return delim.isEmpty ? "" : s
        }
        var start = units.count - delim.count
        while start >= 0 {
            if Array(units[start..<start + delim.count]) == delim {
                return String(decoding: units[(start + delim.count)...], as: UTF16.self)
            }
            start -= 1
        }
        return s
    }

    /// Java's `String.indexOf(ch)` for an ASCII character, as a UTF-16
    /// offset, or nil if absent.
    public static func indexOf(_ s: String, _ ch: Character) -> Int? {
        guard let target = ch.utf16.first, ch.utf16.count == 1 else { return nil }
        return s.utf16.firstIndex(of: target).map { s.utf16.distance(from: s.utf16.startIndex, to: $0) }
    }

    /// Java's `String.lastIndexOf(ch)` for an ASCII character, as a
    /// UTF-16 offset, or nil if absent.
    public static func lastIndexOf(_ s: String, _ ch: Character) -> Int? {
        guard let target = ch.utf16.first, ch.utf16.count == 1 else { return nil }
        var last: Int?
        for (i, unit) in s.utf16.enumerated() where unit == target {
            last = i
        }
        return last
    }

    /// Java's `String.startsWith`: compares UTF-16 units exactly, where
    /// Swift's hasPrefix treats canonically equivalent text as equal.
    public static func startsWith(_ s: String, _ prefix: String) -> Bool {
        s.utf16.starts(with: prefix.utf16)
    }

    /// Java's `String.substring(begin, end)` on UTF-16 offsets.
    public static func substring(_ s: String, _ begin: Int, _ end: Int? = nil) -> String {
        let units = Array(s.utf16)
        return String(decoding: units[begin..<(end ?? units.count)], as: UTF16.self)
    }
}

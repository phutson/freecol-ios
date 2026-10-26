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

/// Formats numbers the way Java's Float.toString and Double.toString do.
///
/// Both use the shortest digits that round-trip, then lay them out as
/// plain decimals when 10^-3 <= |x| < 10^7 ("0.001", "1234567.0") and
/// otherwise in computerized scientific notation ("1.0E7", "1.0E-4").
/// Swift's description finds the same shortest digits but lays them
/// out differently ("1e-04"), so only the digits are taken from it.
///
/// Java always prints at least two significant digits, and where the
/// shortest form has only one it picks the closest two-digit decimal
/// that still reads back as the same value.  That only differs from
/// appending ".0" for the smallest subnormals: Float.MIN_VALUE is
/// "1.4E-45", not "1.0E-45" (FreeCol uses it as the unknown modifier
/// value), and Double.MIN_VALUE is "4.9E-324".
///
/// JDK 18 and earlier do not always produce the shortest digits (the
/// fix landed in JDK 19), so values written by an older JDK can differ
/// in rare cases.  None occur in the current reference dumps.
public enum JavaNumberFormat {

    /// Format like Java's Double.toString.
    public static func string(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        return layout(description: d.description, isZero: d == 0,
                      isNegative: d.sign == .minus) { exponent in
            closestTwoDigits(Double(d.magnitude), exponent) { Double($0) == d.magnitude }
        }
    }

    /// Format like Java's Float.toString.
    public static func string(_ f: Float) -> String {
        if f.isNaN { return "NaN" }
        if f.isInfinite { return f < 0 ? "-Infinity" : "Infinity" }
        return layout(description: f.description, isZero: f == 0,
                      isNegative: f.sign == .minus) { exponent in
            closestTwoDigits(Double(f.magnitude), exponent) { Float($0) == f.magnitude }
        }
    }

    /// The closest two-digit decimal d.d * 10^exponent to a value, as
    /// its two digits, if it reads back as the value.
    private static func closestTwoDigits(_ magnitude: Double, _ exponent: Int,
                                         readsBack: (String) -> Bool) -> [Character]? {
        // Scale to [10, 100) in steps, since 10^325 is not a Double.
        var scaled = magnitude
        var k = 1 - exponent
        while k > 0 {
            let step = min(k, 22) // Powers of ten up to 10^22 are exact.
            var p = 1.0
            for _ in 0..<step { p *= 10 }
            scaled *= p
            k -= step
        }
        while k < 0 {
            let step = min(-k, 22)
            var p = 1.0
            for _ in 0..<step { p *= 10 }
            scaled /= p
            k += step
        }
        let candidate = Int(scaled.rounded())
        guard (10...99).contains(candidate),
              readsBack("\(candidate / 10).\(candidate % 10)e\(exponent)") else { return nil }
        return Array(String(candidate))
    }

    private static func layout(description: String, isZero: Bool, isNegative: Bool,
                               twoDigits: (Int) -> [Character]?) -> String {
        let sign = isNegative ? "-" : ""
        if isZero { return sign + "0.0" }

        // Split Swift's shortest form into digits and an exponent such
        // that the value is 0.<digits> * 10^pointPosition.
        var text = Substring(description)
        if text.hasPrefix("-") { text = text.dropFirst() }
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            exponent = Int(text[text.index(after: e)...])!
            text = text[..<e]
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = parts[0]
        let fracPart = parts.count > 1 ? parts[1] : ""
        var digits = Array(intPart + fracPart)
        var pointPosition = intPart.count + exponent
        while let first = digits.first, first == "0" {
            digits.removeFirst()
            pointPosition -= 1
        }
        while let last = digits.last, last == "0" {
            digits.removeLast()
        }
        let scientificExponent = pointPosition - 1
        if digits.count == 1, let refined = twoDigits(scientificExponent) {
            digits = refined
            while let last = digits.last, last == "0" { digits.removeLast() }
        }

        if (-3...6).contains(scientificExponent) {
            if pointPosition > 0 {
                let whole = digits.count >= pointPosition
                    ? String(digits[..<pointPosition])
                    : String(digits) + String(repeating: "0", count: pointPosition - digits.count)
                let fraction = digits.count > pointPosition
                    ? String(digits[pointPosition...]) : "0"
                return sign + whole + "." + fraction
            }
            return sign + "0." + String(repeating: "0", count: -pointPosition) + String(digits)
        }
        let rest = digits.count > 1 ? String(digits[1...]) : "0"
        return sign + String(digits[0]) + "." + rest + "E" + String(scientificExponent)
    }
}

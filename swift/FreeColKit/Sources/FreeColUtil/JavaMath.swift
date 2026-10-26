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

/// Java's numeric conversions, where Swift's differ.
///
/// - `Math.round` rounds halves up (-2.5 becomes -2), while Swift's
///   `rounded()` rounds them away from zero (-2.5 becomes -3).
/// - A Java `(int)` or `(long)` cast saturates at the type's limits and
///   turns NaN into 0, while Swift's `Int32(x)` traps.
///
/// Integer division, `%` and `Math.floor` already behave the same in
/// both languages.  Java's int arithmetic wraps on overflow, so ported
/// code that may overflow must use `&+`, `&-` and `&*`.
public enum JavaMath {

    /// Java's `Math.round(float)`: the closest int, halves rounded up.
    ///
    /// A port of the JDK's bit-level algorithm, which gives the exact
    /// result even where adding 0.5 would round (0.49999997 gives 0).
    public static func round(_ a: Float) -> Int32 {
        let bits = Int32(bitPattern: a.bitPattern)
        let biasedExponent = (bits & 0x7F80_0000) >> 23
        let shift = (24 - 2 + 127) - biasedExponent
        guard shift & -32 == 0 else {
            // NaN, infinite, or too large to have a fraction.
            return toInt(a)
        }
        var r = (bits & 0x007F_FFFF) | 0x0080_0000
        if bits < 0 { r = -r }
        return ((r >> shift) + 1) >> 1
    }

    /// Java's `Math.round(double)`: the closest long, halves rounded up.
    public static func round(_ a: Double) -> Int64 {
        let bits = Int64(bitPattern: a.bitPattern)
        let biasedExponent = (bits & 0x7FF0_0000_0000_0000) >> 52
        let shift = (53 - 2 + 1023) - biasedExponent
        guard shift & -64 == 0 else {
            return toLong(a)
        }
        var r = (bits & 0x000F_FFFF_FFFF_FFFF) | 0x0010_0000_0000_0000
        if bits < 0 { r = -r }
        return ((r >> shift) + 1) >> 1
    }

    /// Java's `Float.floatToIntBits`: the raw bits, with every NaN
    /// collapsed to the canonical 0x7FC00000.
    public static func floatToIntBits(_ f: Float) -> Int32 {
        f.isNaN ? 0x7FC0_0000 : Int32(bitPattern: f.bitPattern)
    }

    /// Java's `Float.compare`: numeric order, except that -0.0 sorts
    /// below 0.0 and NaN equals itself and sorts above everything.
    ///
    /// - Returns: -1, 0 or 1.
    public static func floatCompare(_ a: Float, _ b: Float) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        let x = floatToIntBits(a), y = floatToIntBits(b)
        return x == y ? 0 : x < y ? -1 : 1
    }

    /// Java's `(int)` cast of a float: truncate, saturate, NaN is 0.
    public static func toInt(_ f: Float) -> Int32 {
        if f.isNaN { return 0 }
        if f >= 2_147_483_648 { return .max }
        if f <= -2_147_483_648 { return .min }
        return Int32(f)
    }

    /// Java's `(int)` cast of a double: truncate, saturate, NaN is 0.
    public static func toInt(_ d: Double) -> Int32 {
        if d.isNaN { return 0 }
        if d >= 2_147_483_648 { return .max }
        if d <= -2_147_483_648 { return .min }
        return Int32(d)
    }

    /// Java's `(long)` cast of a float: truncate, saturate, NaN is 0.
    public static func toLong(_ f: Float) -> Int64 {
        if f.isNaN { return 0 }
        if f >= 9_223_372_036_854_775_808 { return .max }
        if f <= -9_223_372_036_854_775_808 { return .min }
        return Int64(f)
    }

    /// Java's `(long)` cast of a double: truncate, saturate, NaN is 0.
    public static func toLong(_ d: Double) -> Int64 {
        if d.isNaN { return 0 }
        if d >= 9_223_372_036_854_775_808 { return .max }
        if d <= -9_223_372_036_854_775_808 { return .min }
        return Int64(d)
    }

    /// Java's `DoubleStream.sum`: Kahan summation, falling back to the
    /// simple sum when the compensated one is NaN from infinities (JDK
    /// 18's Collectors.sumWithCompensation and computeFinalSum).
    public static func doubleStreamSum<S: Sequence>(_ values: S) -> Double where S.Element == Double {
        var sum = 0.0, compensation = 0.0, simpleSum = 0.0
        for value in values {
            let tmp = value - compensation
            let velvel = sum + tmp
            compensation = (velvel - sum) - tmp
            sum = velvel
            simpleSum += value
        }
        let total = sum - compensation
        return total.isNaN && simpleSum.isInfinite ? simpleSum : total
    }
}

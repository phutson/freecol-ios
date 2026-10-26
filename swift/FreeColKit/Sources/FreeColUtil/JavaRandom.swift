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

/// An exact port of `java.util.Random`, the generator behind every
/// random decision in the game.
///
/// The same seed gives the same sequence as Java, and the state can be
/// saved and restored in the form FreeCol writes into saved games, so
/// a Swift game can continue a Java game's random sequence.  Only the
/// methods FreeCol uses are ported.
///
/// This is a class because Java passes one generator around by
/// reference and every caller advances the same sequence.
public final class JavaRandom {

    private static let multiplier: Int64 = 0x5DEECE66D
    private static let addend: Int64 = 0xB
    private static let mask: Int64 = (1 << 48) - 1

    /// The 48-bit internal state (Java's scrambled seed).
    public private(set) var state: Int64

    /// Java's cached second Gaussian.  FreeCol never uses Gaussians,
    /// but the saved state includes these, so they are kept as read.
    private var nextNextGaussian: Double = 0
    private var haveNextNextGaussian = false

    /// An optional sink for random-number traces, in the same text as
    /// RandomUtils logs at Level.FINEST in Java, for finding where a
    /// Swift game's sequence first differs from a Java game's.
    public var trace: ((String) -> Void)?

    /// Create a generator, like `new Random(seed)`.
    ///
    /// - Parameter seed: The initial seed.
    public init(seed: Int64) {
        state = (seed ^ JavaRandom.multiplier) & JavaRandom.mask
    }

    /// Create a generator with an unpredictable seed, like `new Random()`.
    public convenience init() {
        var system = SystemRandomNumberGenerator()
        self.init(seed: Int64(bitPattern: system.next()))
    }

    /// Reset the seed, like `Random.setSeed`.
    public func setSeed(_ seed: Int64) {
        state = (seed ^ JavaRandom.multiplier) & JavaRandom.mask
        haveNextNextGaussian = false
    }

    /// Java's `next(bits)`: advance and return the top `bits` bits.
    private func next(_ bits: Int) -> Int32 {
        state = (state &* JavaRandom.multiplier &+ JavaRandom.addend) & JavaRandom.mask
        // Java casts the shifted long to int, keeping the low 32 bits.
        return Int32(truncatingIfNeeded: state >> (48 - bits))
    }

    /// Like `Random.nextInt()`.
    public func nextInt() -> Int32 {
        next(32)
    }

    /// Like `Random.nextInt(bound)`: uniform in 0..<bound.
    ///
    /// - Parameter bound: The exclusive upper bound, which must be positive.
    public func nextInt(_ bound: Int32) -> Int32 {
        precondition(bound > 0, "bound must be positive")
        var r = next(31)
        let m = bound &- 1
        if bound & m == 0 {
            // Power of two: take the high bits.
            return Int32(truncatingIfNeeded: (Int64(bound) &* Int64(r)) >> 31)
        }
        // Reject the over-represented values.  The test relies on
        // Java's wrapping int arithmetic.
        var u = r
        while true {
            r = u % bound
            if u &- r &+ m >= 0 { return r }
            u = next(31)
        }
    }

    /// Like `Random.nextFloat()`: uniform in [0, 1).
    public func nextFloat() -> Float {
        Float(next(24)) / Float(1 << 24)
    }

    /// Like `Random.nextDouble()`: uniform in [0, 1).
    public func nextDouble() -> Double {
        let high = Int64(next(26)) << 27
        return Double(high + Int64(next(27))) * 0x1.0p-53
    }

    /// Like `Random.ints(count, origin, bound)` on JDK 17 and later.
    ///
    /// This is not the same as calling nextInt(bound) repeatedly: since
    /// JDK 17 the stream uses RandomSupport.boundedNextInt, which starts
    /// from nextInt() rather than next(31).  JDK 11 used nextInt(bound),
    /// so a Java game gives different results for these on JDK 11.
    ///
    /// - Parameters:
    ///   - count: How many values to generate.
    ///   - origin: The inclusive lower bound.
    ///   - bound: The exclusive upper bound, which must exceed origin.
    public func ints(_ count: Int, origin: Int32, bound: Int32) -> [Int32] {
        precondition(origin < bound, "bound must be greater than origin")
        return (0..<count).map { _ in boundedNextInt(origin: origin, bound: bound) }
    }

    /// Port of JDK 17's RandomSupport.boundedNextInt.
    private func boundedNextInt(origin: Int32, bound: Int32) -> Int32 {
        var r = nextInt()
        let n = bound &- origin
        let m = n &- 1
        if n & m == 0 {
            // Power of two range.
            return (r & m) &+ origin
        } else if n > 0 {
            // Reject the over-represented values, as above.  Java's
            // u >>> 1 on an int is a logical shift.
            var u = Int32(bitPattern: UInt32(bitPattern: r) >> 1)
            while true {
                r = u % n
                if u &+ m &- r >= 0 { return r &+ origin }
                u = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            }
        } else {
            // The range does not fit in an int.
            while r < origin || r >= bound { r = nextInt() }
            return r
        }
    }

    /// Shuffle a list in place, like `Collections.shuffle(list, random)`.
    ///
    /// - Parameter list: The list to shuffle.
    public func shuffle<T>(_ list: inout [T]) {
        var i = list.count
        while i > 1 {
            list.swapAt(i - 1, Int(nextInt(Int32(i))))
            i -= 1
        }
    }
}

// MARK: - Saved state

extension JavaRandom {

    /// The Java serialization of a java.util.Random, as hex, up to the
    /// field values (copied from what JDK 18 writes).  Fields are written primitives first by name:
    /// haveNextNextGaussian (boolean), nextNextGaussian (double),
    /// seed (long).
    private static let serializedPrefix = Array(
        "ACED0005737200106A6176612E7574696C2E52616E646F6D363296344BF00A53"
        + "0300035A0014686176654E6578744E657874476175737369616E4400106E6578"
        + "744E657874476175737369616E4A0004736565647870")
    private static let serializedSuffix = "78"

    /// The state as FreeCol saves it (Utils.getRandomState): Java's
    /// serialization of the Random, in upper case hex.
    public var serializedState: String {
        var hex = String(JavaRandom.serializedPrefix)
        hex += haveNextNextGaussian ? "01" : "00"
        hex += JavaRandom.hex(UInt64(nextNextGaussian.bitPattern))
        hex += JavaRandom.hex(UInt64(bitPattern: state))
        hex += JavaRandom.serializedSuffix
        return hex
    }

    /// Restore a generator from FreeCol's saved form
    /// (Utils.restoreRandomState).
    ///
    /// - Parameter serializedState: The hex string from a saved game.
    /// - Returns: nil if the string is not a serialized java.util.Random
    ///   in the layout Java writes.
    public convenience init?(serializedState hex: String) {
        let chars = Array(hex.uppercased())
        let prefix = JavaRandom.serializedPrefix
        let valuesLength = 2 + 16 + 16
        guard chars.count == prefix.count + valuesLength + 2,
              chars.starts(with: prefix),
              String(chars.suffix(2)) == JavaRandom.serializedSuffix,
              let flag = UInt8(String(chars[prefix.count..<prefix.count + 2]), radix: 16),
              flag <= 1,
              let gaussian = UInt64(String(chars[prefix.count + 2..<prefix.count + 18]), radix: 16),
              let seed = UInt64(String(chars[prefix.count + 18..<prefix.count + 34]), radix: 16)
        else { return nil }
        self.init(seed: 0)
        state = Int64(bitPattern: seed) & JavaRandom.mask
        haveNextNextGaussian = flag == 1
        nextNextGaussian = Double(bitPattern: gaussian)
    }

    private static func hex(_ value: UInt64) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: 16 - digits.count) + digits
    }
}

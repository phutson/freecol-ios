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

/// Port of `net.sf.freecol.common.util.RandomUtils`: the helpers the
/// game uses for every random choice.
///
/// Java logs each result at Level.FINEST with a short description.
/// Here the same text goes to the generator's `trace`, if set, so a
/// Java log and a Swift trace can be compared line by line.
public enum RandomUtils {

    /// A random integer r, 0 <= r < range (Java's randomInt).
    public static func randomInt(_ logMe: String, _ random: JavaRandom,
                                 _ range: Int32) -> Int32 {
        let ret = random.nextInt(range)
        random.trace?("\(logMe) random(\(range)) = \(ret)")
        return ret
    }

    /// n random integers in 0..<range (Java's randomInts).
    public static func randomInts(_ logMe: String, _ random: JavaRandom,
                                  _ range: Int32, _ n: Int) -> [Int32] {
        let ret = random.ints(n, origin: 0, bound: range)
        traceArray(logMe, random, ret)
        return ret
    }

    /// A random float in [0, 1) (Java's randomFloat).
    public static func randomFloat(_ logMe: String, _ random: JavaRandom) -> Float {
        let ret = random.nextFloat()
        random.trace?("\(logMe) random(1.0f) = \(JavaNumberFormat.string(ret))")
        return ret
    }

    /// A random double in [0, 1) (Java's randomDouble).
    public static func randomDouble(_ logMe: String, _ random: JavaRandom) -> Double {
        let ret = random.nextDouble()
        random.trace?("\(logMe) random(1.0) = \(JavaNumberFormat.string(ret))")
        return ret
    }

    /// A random member of a list, or nil if it is empty.  Like Java, a
    /// list of one is returned without using the generator.
    public static func randomMember<T>(_ logMe: String, _ list: [T],
                                       _ random: JavaRandom) -> T? {
        switch list.count {
        case 0: return nil
        case 1: return list[0]
        default: return list[Int(randomInt(logMe, random, Int32(list.count)))]
        }
    }

    /// Shuffle a list (Java's randomShuffle).  Lists of one or fewer
    /// are left alone without using the generator.
    public static func randomShuffle<T>(_ logMe: String, _ list: inout [T],
                                        _ random: JavaRandom?) {
        guard list.count > 1, let random else { return }
        random.trace?("\(logMe) shuffle.")
        random.shuffle(&list)
    }

    private static func traceArray(_ logMe: String, _ random: JavaRandom,
                                   _ values: [Int32]) {
        guard let trace = random.trace else { return }
        trace("\(logMe) random = [" + values.map { " \($0)" }.joined() + " ]")
    }

    /// Port of RandomUtils.RandomIntCache: random integers drawn in
    /// batches with randomInts.
    public final class RandomIntCache {
        private let logMe: String
        private let random: JavaRandom
        private let range: Int32
        private let size: Int
        private var generation = 0
        private var cache: [Int32] = []
        private var index = 0

        public init(_ logMe: String, _ random: JavaRandom, range: Int32, size: Int) {
            self.logMe = logMe
            self.random = random
            self.range = range
            self.size = size
            refill()
        }

        private func refill() {
            cache = RandomUtils.randomInts("\(logMe)/\(generation)", random, range, size)
            index = 0
            generation += 1
        }

        /// The next cached value, in 0..<range.
        public func nextInt() -> Int32 {
            if index >= size { refill() }
            defer { index += 1 }
            return cache[index]
        }

        /// The next cached value reduced to 0..<tighterRange.
        public func nextInt(_ tighterRange: Int32) -> Int32 {
            nextInt() % tighterRange
        }
    }
}

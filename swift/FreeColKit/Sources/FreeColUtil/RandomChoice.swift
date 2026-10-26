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

/// An object with a weight for random selection
/// (common/util/RandomChoice).
public struct RandomChoice<T> {

    /// The weight.
    public var probability: Int
    /// The object chosen.
    public let object: T

    public init(_ object: T, _ probability: Int) {
        self.object = object
        self.probability = probability
    }

    /// The sum of the weights.
    public static func totalProbability(_ choices: [RandomChoice<T>]) -> Int {
        choices.reduce(0) { $0 + $1.probability }
    }

    /// Choose by weight, as Java does: none for no choices or no weight,
    /// the only one without using the generator, otherwise one random
    /// number below the total weight.
    public static func weightedRandom(_ logMe: String, _ choices: [RandomChoice<T>],
                                      _ random: JavaRandom) -> T? {
        let n = totalProbability(choices)
        guard !choices.isEmpty, n > 0 else { return nil }
        if choices.count == 1 { return choices[0].object }
        let probability = Int(RandomUtils.randomInt(logMe, random, Int32(n)))
        var total = 0
        for choice in choices {
            total += choice.probability
            if probability < total { return choice.object }
        }
        return choices[0].object
    }

    /// Scale the weights to add up to about a total, rounding as Java's
    /// Math.round does.
    public static func normalize(_ choices: inout [RandomChoice<T>], _ expectedTotal: Int) {
        let n = totalProbability(choices)
        guard !choices.isEmpty, n > 0 else { return }
        let mult = Double(expectedTotal) / Double(n)
        for i in choices.indices {
            choices[i].probability = Int(Int32(truncatingIfNeeded:
                JavaMath.round(mult * Double(choices[i].probability))))
        }
    }
}

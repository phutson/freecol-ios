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
import FreeColCore
import FreeColUtil
import Testing

/// RandomRangeTest.java.  Java's constructor throws on bad arguments;
/// the Swift one stops the program, so those checks are exit tests.
struct RandomRangeTest {

    @Test func randomRange() {
        let random = JavaRandom(seed: Int64(Date().timeIntervalSince1970 * 1000))
        let r = RandomRange(probability: 100, minimum: 1, maximum: 4, factor: 1000)
        for _ in 0..<25 {
            let vc = r.amount("test-c", random, continuous: true)
            let vd = r.amount("test-n", random, continuous: false)
            #expect(1000 <= vc && vc <= 5000, "Continuous range (\(vc))")
            #expect([1000, 2000, 3000, 4000].contains(vd), "Discrete range (\(vd))")
        }
    }

    @Test func negativeProbabilityFails() async {
        await #expect(processExitsWith: .failure) {
            _ = RandomRange(probability: -1, minimum: 1, maximum: 4, factor: 1000)
        }
    }

    @Test func minimumAboveMaximumFails() async {
        await #expect(processExitsWith: .failure) {
            _ = RandomRange(probability: 100, minimum: 1, maximum: 0, factor: 1000)
        }
    }
}

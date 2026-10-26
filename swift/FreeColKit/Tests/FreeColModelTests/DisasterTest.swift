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

import FreeColCore
import Testing

/// DisasterTest.java.
@Suite(.serialized)
struct DisasterTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()

    @Test(arguments: ["model.disaster.tornado", "model.disaster.flood",
                      "model.disaster.disease", "model.disaster.sandstorm"])
    func disastersPresent(_ id: String) throws {
        let disaster = try #require(Self.spec.getDisaster(id))
        #expect(!disaster.effects.isEmpty)
        for choice in disaster.effects {
            #expect(choice.object.id != nil)
            #expect(choice.probability > 0)
            #expect(choice.object.probability > 0)
            #expect(choice.probability == choice.object.probability)
        }
    }
}

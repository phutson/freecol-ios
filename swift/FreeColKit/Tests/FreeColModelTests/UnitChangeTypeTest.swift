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

/// UnitChangeTypeTest.java.
@Suite(.serialized)
struct UnitChangeTypeTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }
    var farmer: UnitType { spec.getUnitType("model.unit.expertFarmer")! }

    @Test func emptyScope() throws {
        let uct = try #require(spec.getUnitChangeType(UnitChangeType.education))
        #expect(uct.scopes.isEmpty, "Education has no scopes")
        // An empty scope applies to all players.
        for player in FreeColTestCase.standardGame(spec).players {
            #expect(uct.appliesTo(player), "Empty scopes apply to all players")
        }
    }

    @Test func abilityScope() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))

        let gardenerType = UnitType(id: "gardener", specification: spec)
        gardenerType.skill = 0
        #expect(gardenerType.teachingType(farmer) == nil)

        FreeColTestCase.addUnitTypeChange(spec, UnitChangeType.education, gardenerType, farmer, 100, -1)
        #expect(gardenerType.teachingType(farmer) === farmer)

        let education = try #require(spec.getUnitChangeType(UnitChangeType.education))
        let scope = Scope()
        scope.abilityId = Ability.native
        education.addScope(scope)

        #expect(gardenerType.teachingType(farmer) === farmer)
        let gardenerUnit = Unit(game: game, location: nil, owner: dutch, type: gardenerType)
        #expect(gardenerUnit.teachingType(farmer) == nil)

        scope.matchNegated = true
        #expect(gardenerUnit.teachingType(farmer) === farmer)

        education.removeScope(scope)
        education.deleteUnitChanges(gardenerType)
    }

    @Test func creation() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))

        let gardenerType = UnitType(id: "gardener", specification: spec)
        #expect(spec.unitChanges(UnitChangeType.creation, gardenerType).isEmpty)

        FreeColTestCase.addUnitTypeChange(spec, UnitChangeType.creation, gardenerType, farmer, 100, -1)
        #expect(spec.unitChanges(UnitChangeType.creation, gardenerType).count == 1)
        #expect(spec.unitChange(UnitChangeType.creation, gardenerType) != nil)
        #expect(spec.unitChange(UnitChangeType.creation, gardenerType, farmer) != nil)

        let gardenerUnit = Unit(game: game, location: nil, owner: dutch, type: gardenerType)
        #expect(gardenerUnit.type === farmer)

        spec.getUnitChangeType(UnitChangeType.creation)!.deleteUnitChanges(gardenerType)
    }
}

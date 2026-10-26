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

/// NationTypeTest.java.
@Suite(.serialized)
struct NationTypeTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    @Test func hasType() {
        // Make sure that each nation has a type
        for n in spec.nations {
            #expect(n.type != nil, "\(n)")
        }
    }

    static let european = ["trade", "default", "ref", "cooperation", "immigration", "conquest"]
    static let native = ["apache", "sioux", "tupi", "arawak", "cherokee", "iroquois", "inca", "aztec"]

    @Test func isEuropean() {
        for id in Self.european {
            #expect(spec.getNationType("model.nationType." + id)!.isEuropean, "\(id)")
        }
        for id in Self.native {
            #expect(!spec.getNationType("model.nationType." + id)!.isEuropean, "\(id)")
        }
    }

    @Test func isREF() {
        for id in Self.european + Self.native {
            #expect(spec.getNationType("model.nationType." + id)!.isREF == (id == "ref"), "\(id)")
        }
    }

    @Test func settlementType() throws {
        for nationType in spec.indianNationTypes {
            #expect(!nationType.settlementTypes.isEmpty)
            let settlement = try #require(nationType.settlementType(capital: false), "\(nationType.id ?? "")")
            let capital = try #require(nationType.settlementType(capital: true), "\(nationType.id ?? "")")
            #expect(capital !== settlement, "\(nationType.id ?? "")")
        }
    }

    @Test func startingUnits() {
        for (difficulty, og) in spec.difficultyLevels.enumerated() {
            spec.applyDifficultyLevel(og)
            for type in spec.europeanNationTypes {
                let startingUnits = type.startingUnits
                #expect(startingUnits.count == 3, "Wrong number of starting units: \(type)")
                for au in startingUnits {
                    let unitTypeId = au.id
                    if au.roleId == "model.role.soldier" {
                        if difficulty == 0 || difficulty == 1 || type.id == "model.nationType.conquest" {
                            #expect(unitTypeId == "model.unit.veteranSoldier", "Wrong type of soldier: \(type)")
                        } else {
                            #expect(unitTypeId != "model.unit.veteranSoldier", "Wrong type of soldier: \(type)")
                        }
                    } else if au.roleId == "model.role.pioneer" {
                        if type.id == "model.nationType.cooperation" {
                            #expect(unitTypeId == "model.unit.hardyPioneer", "Wrong type of pioneer: \(type)")
                        } else {
                            #expect(unitTypeId != "model.unit.hardyPioneer", "Wrong type of pioneer: \(type)")
                        }
                    } else if Role.isDefaultRoleId(au.roleId) {
                        #expect(spec.getUnitType(au.id)!.hasAbility(Ability.navalUnit),
                                "Ship is not naval: \(type)")
                        if type.id == "model.nationType.trade" || type.id == "model.nationType.naval" {
                            #expect(unitTypeId == "model.unit.merchantman", "Wrong type of ship: \(type)")
                        } else {
                            #expect(unitTypeId == "model.unit.caravel", "Wrong type of ship: \(type)")
                        }
                    }
                }
            }
        }
        spec.applyDifficultyLevel("model.difficulty.medium")
    }

    @Test func advantagesThatOnlyApplyToPersons() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))
        let colony = FreeColTestCase.standardColony(game)
        let owner = try #require(colony.owner)

        owner.changeNationType(spec.getNationType("model.nationType.building"))
        var modifiers = owner.modifiers("model.goods.hammers")
        try #require(modifiers.count == 1)
        #expect(!modifiers[0].appliesTo(spec.getBuildingType("model.building.carpenterHouse")),
                "Hammer production bonus should not apply to buildings")
        for unit in colony.unitList {
            #expect(modifiers[0].appliesTo(unit.type), "Hammer production bonus should apply to all persons")
        }

        owner.changeNationType(spec.getNationType("model.nationType.furTrapping"))
        modifiers = owner.modifiers("model.goods.coats")
        try #require(modifiers.count == 1)
        #expect(!modifiers[0].appliesTo(spec.getBuildingType("model.building.furTraderHouse")),
                "Coat production bonus should not apply to buildings")
        for unit in colony.unitList {
            #expect(modifiers[0].appliesTo(unit.type), "Coat production bonus should apply to all persons")
        }
    }
}

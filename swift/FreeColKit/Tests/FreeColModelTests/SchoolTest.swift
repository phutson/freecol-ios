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

/// SchoolTest.java.
@Suite(.serialized)
struct SchoolTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    enum SchoolLevel { case schoolhouse, college, university }

    var schoolType: BuildingType { spec.getBuildingType("model.building.schoolhouse")! }
    var collegeType: BuildingType { spec.getBuildingType("model.building.college")! }
    var universityType: BuildingType { spec.getBuildingType("model.building.university")! }
    var lumber: GoodsType { spec.getGoodsType("model.goods.lumber")! }
    var cotton: GoodsType { spec.getGoodsType("model.goods.cotton")! }
    var expertLumberJackType: UnitType { spec.getUnitType("model.unit.expertLumberJack")! }
    var freeColonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }
    var indenturedServantType: UnitType { spec.getUnitType("model.unit.indenturedServant")! }
    var pettyCriminalType: UnitType { spec.getUnitType("model.unit.pettyCriminal")! }
    var masterCarpenterType: UnitType { spec.getUnitType("model.unit.masterCarpenter")! }

    func addSchoolToColony(_ game: Game, _ colony: Colony, _ level: SchoolLevel) -> Building {
        let type = switch level {
        case .schoolhouse: schoolType
        case .college: collegeType
        case .university: universityType
        }
        colony.addBuilding(Building(game: game, colony: colony, type: type))
        return colony.building(type)!
    }

    /// Set whether students can be chosen, returning the old setting
    /// (FreeColTestUtils.setStudentSelection).
    @discardableResult
    func setStudentSelection(_ value: Bool) -> Bool {
        let ret = spec.getBoolean(GameOptions.allowStudentSelection)
        spec.setBoolean(GameOptions.allowStudentSelection, value)
        return ret
    }

    @Test func upgrades() {
        #expect(freeColonistType.teachingType(masterCarpenterType) === masterCarpenterType,
                "Colonist should upgrade to carpenter")
        #expect(indenturedServantType.teachingType(masterCarpenterType) === freeColonistType,
                "Servant should upgrade to colonist")
        #expect(pettyCriminalType.teachingType(masterCarpenterType) === indenturedServantType,
                "Criminal should upgrade to servant")
    }

    @Test func educationOption() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))
        let colony = FreeColTestCase.standardColony(game, 5)
        let units = colony.unitList
        let lumberJack = units[0], criminal1 = units[1], criminal2 = units[2]
        let colonist1 = units[3], colonist2 = units[4]
        lumberJack.setType(expertLumberJackType)
        criminal1.setType(pettyCriminalType)
        criminal2.setType(pettyCriminalType)
        colonist1.setType(freeColonistType)
        colonist2.setType(freeColonistType)

        let selection = setStudentSelection(true)

        colony.addBuilding(Building(game: game, colony: colony, type: schoolType))
        let school = try #require(colony.building(schoolType))
        #expect(school.canTeach)
        #expect(colony.canTrain(lumberJack))
        lumberJack.setLocation(school)

        colonist1.changeWorkType(cotton)
        colonist2.changeWorkType(lumber)
        #expect(colonist1.workType === cotton)
        #expect(colonist2.workType === expertLumberJackType.expertProduction)
        #expect(colony.findStudent(lumberJack) == nil)

        lumberJack.setStudent(nil)
        colonist2.setTeacher(nil)

        setStudentSelection(false)

        criminal1.changeWorkType(cotton)
        criminal2.changeWorkType(lumber)
        #expect(colony.findStudent(lumberJack) === criminal2)

        setStudentSelection(selection)
    }

    @Test func changeTeachers() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))

        let colony = ColonyBuilder(game).initialColonists(3)
            .addColonist(expertLumberJackType).addColonist(expertLumberJackType).build()
        let school = addSchoolToColony(game, colony, .college)

        let student = try #require(colony.unitList.first { $0.type === freeColonistType })
        let teacherList = colony.unitList.filter { $0.type === expertLumberJackType }
        try #require(teacherList.count == 2)
        let teacher1 = teacherList[0], teacher2 = teacherList[1]
        #expect(teacher1.student == nil, "Teacher1 should not have a student yet")
        #expect(teacher2.student == nil, "Teacher2 should not have a student yet")

        let selection = setStudentSelection(false)

        // Add the first teacher
        teacher1.setLocation(school)
        #expect(teacher1.student === student, "Teacher1 should now have a student")
        #expect(student.teacher === teacher1, "Student should have assigned teacher1")

        // Add a second teacher
        teacher2.setLocation(school)
        #expect(teacher1.student === student, "Teacher1 should still have a student")
        #expect(teacher2.student == nil, "Teacher2 should not have a student yet")
        #expect(student.teacher === teacher1, "Student should have assigned teacher1")

        // Change teacher
        student.setTeacher(teacher2)
        #expect(teacher1.student == nil, "Teacher1 should not have a student now")
        #expect(teacher2.student === student, "Teacher2 should now have a student")
        #expect(student.teacher === teacher2, "Student should have assigned teacher2")

        setStudentSelection(selection)
    }
}

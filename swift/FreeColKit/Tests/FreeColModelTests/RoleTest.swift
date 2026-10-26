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

/// RoleTest.java.
@Suite(.serialized)
struct RoleTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    var horses: GoodsType { spec.getGoodsType("model.goods.horses")! }
    var muskets: GoodsType { spec.getGoodsType("model.goods.muskets")! }
    var tools: GoodsType { spec.getGoodsType("model.goods.tools")! }

    var none: Role { spec.defaultRole! }
    var scout: Role { spec.getRole("model.role.scout")! }
    var soldier: Role { spec.getRole("model.role.soldier")! }
    var dragoon: Role { spec.getRole("model.role.dragoon")! }
    var pioneer: Role { spec.getRole("model.role.pioneer")! }
    var mission: Role { spec.getRole("model.role.missionary")! }
    var infantry: Role { spec.getRole("model.role.infantry")! }
    var cavalry: Role { spec.getRole("model.role.cavalry")! }
    var armedBrave: Role { spec.getRole("model.role.armedBrave")! }
    var mountedBrave: Role { spec.getRole("model.role.mountedBrave")! }
    var nativeDragoon: Role { spec.getRole("model.role.nativeDragoon")! }

    var braveType: UnitType { spec.getUnitType("model.unit.brave")! }
    var colonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }
    var kingsRegularType: UnitType { spec.getUnitType("model.unit.kingsRegular")! }

    @Test func roleComparator() {
        #expect(Role.compareMilitary(soldier, soldier) == 0)
        #expect(Role.compareMilitary(dragoon, dragoon) == 0)
        #expect(Role.compareMilitary(mission, mission) == 0)
        #expect(Role.compareMilitary(dragoon, soldier) == -1)
        #expect(Role.compareMilitary(soldier, dragoon) == 1)
        #expect(Role.compareMilitary(mission, soldier) == 1)
        #expect(Role.compareMilitary(dragoon, mission) == -1)
    }

    @Test func compatibleRoles() {
        #expect(!soldier.isCompatible(with: none))
        #expect(!soldier.isCompatible(with: pioneer))
        #expect(!soldier.isCompatible(with: mission))
        #expect(soldier.isCompatible(with: soldier))
        #expect(!soldier.isCompatible(with: scout))
        #expect(soldier.isCompatible(with: dragoon))

        #expect(!mission.isCompatible(with: none))
        #expect(!mission.isCompatible(with: pioneer))
        #expect(mission.isCompatible(with: mission))
        #expect(!mission.isCompatible(with: soldier))
        #expect(!mission.isCompatible(with: scout))
        #expect(!mission.isCompatible(with: dragoon))
    }

    @Test func goodsDifference() {
        #expect(Role.goodsDifference(from: nil, 1, to: none, 1).isEmpty)
        #expect(Role.goodsDifference(from: none, 1, to: none, 1).isEmpty)
        #expect(Role.goodsDifference(from: none, 1, to: mission, 1).isEmpty)
        #expect(Role.goodsDifference(from: mission, 1, to: none, 1).isEmpty)

        checkGoods("->soldier", Role.goodsDifference(from: none, 1, to: soldier, 1),
                   AbstractGoods(muskets, 50))
        checkGoods("soldier->dragoon", Role.goodsDifference(from: soldier, 1, to: dragoon, 1),
                   AbstractGoods(horses, 50))
        checkGoods("missionary->dragoon", Role.goodsDifference(from: mission, 1, to: dragoon, 1),
                   AbstractGoods(horses, 50), AbstractGoods(muskets, 50))
        checkGoods("soldier->", Role.goodsDifference(from: soldier, 1, to: none, 1),
                   AbstractGoods(muskets, -50))
        checkGoods("nativeDragoon->armedBrave", Role.goodsDifference(from: nativeDragoon, 1, to: armedBrave, 1),
                   AbstractGoods(horses, -25))
        checkGoods("soldier->pioneer(4)", Role.goodsDifference(from: soldier, 1, to: pioneer, 4),
                   AbstractGoods(muskets, -50), AbstractGoods(tools, 80))
    }

    @Test func militaryRoles() {
        let game = FreeColTestCase.standardGame(spec)
        let military = spec.militaryRolesList

        let colonialRoles = Role.availableRoles(game.player(byNationId: "model.nation.dutch"), colonistType, military)
        #expect(colonialRoles.elementsEqual([dragoon, soldier, scout], by: ===))

        let royalRoles = Role.availableRoles(game.player(byNationId: "model.nation.dutchREF"), kingsRegularType,
                                             military)
        #expect(royalRoles.elementsEqual([cavalry, infantry], by: ===))

        let nativeRoles = Role.availableRoles(game.player(byNationId: "model.nation.inca"), braveType, military)
        #expect(nativeRoles.elementsEqual([nativeDragoon, armedBrave, mountedBrave], by: ===))
    }

    @Test func getRoleWithAbility() {
        #expect(spec.roleWithAbility(Ability.improveTerrain)?.id == "model.role.pioneer")
        #expect(spec.roleWithAbility(Ability.speakWithChief)?.id == "model.role.scout")
        #expect(spec.roleWithAbility(Ability.inciteNatives)?.id == "model.role.missionary")
    }
}

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

/// SettlementTest.java.
@Suite(.serialized)
struct SettlementTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    var horsesType: GoodsType { spec.getGoodsType("model.goods.horses")! }
    var musketsType: GoodsType { spec.getGoodsType("model.goods.muskets")! }
    var dragoonRole: Role { spec.getRole("model.role.dragoon")! }
    var mountedBraveRole: Role { spec.getRole("model.role.mountedBrave")! }
    var nativeDragoonRole: Role { spec.getRole("model.role.nativeDragoon")! }
    var soldierRole: Role { spec.getRole("model.role.soldier")! }

    @Test func settlementRadius() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))

        let arawak = try #require(game.player(byNationId: "model.nation.arawak"))
        let builder = IndianSettlementBuilder(game).player(arawak)
        var settlement = builder.build()
        #expect(arawak.nationType?.settlementType(capital: false)?.claimableRadius == 1)
        #expect(settlement.type?.claimableRadius == 1)
        settlement.dispose()

        _ = builder.capital(true)
        settlement = builder.build()
        #expect(arawak.nationType?.settlementType(capital: true)?.claimableRadius == 2)
        #expect(settlement.type?.claimableRadius == 2)
        settlement.dispose()

        let inca = try #require(game.player(byNationId: "model.nation.inca"))
        _ = builder.player(inca).capital(false)
        settlement = builder.build()
        #expect(inca.nationType?.settlementType(capital: false)?.claimableRadius == 2)
        #expect(settlement.type?.claimableRadius == 2)
        settlement.dispose()

        _ = builder.capital(true)
        settlement = builder.build()
        #expect(inca.nationType?.settlementType(capital: true)?.claimableRadius == 3)
        #expect(settlement.type?.claimableRadius == 3)
        settlement.dispose()
    }

    @Test func colonyRadius() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let colony = FreeColTestCase.standardColony(game)
        #expect(colony.owner?.nationType?.settlementType(capital: false)?.claimableRadius == 1)
        #expect(colony.radius == 1)
        #expect(!colony.isCapital)
    }

    @Test func settlementDoesNotClaimWater() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)
        map.tile(4, 8)!.type = spec.getTileType("model.tile.ocean")
        #expect(!map.tile(4, 8)!.isLand)

        let settlement = IndianSettlementBuilder(game).build()
        for tile in settlement.tile!.surroundingTiles(1) {
            #expect((tile.owner === settlement.owner) == tile.isLand)
            #expect((tile.owningSettlement === settlement) == tile.isLand)
        }
    }

    @Test func colonyClaimsWater() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)
        map.tile(4, 8)!.type = spec.getTileType("model.tile.ocean")
        #expect(!map.tile(4, 8)!.isLand)

        let colony = FreeColTestCase.standardColony(game)
        for tile in colony.tile!.surroundingTiles(1) {
            #expect(tile.owner === colony.owner, "Tile \(tile) should be owned by \(colony.owner?.id ?? "")")
            #expect(tile.owningSettlement === colony, "Tile \(tile) should be owned by \(colony.id ?? "")")
        }
    }

    @Test func lineOfSight() {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let colony = FreeColTestCase.standardColony(game)
        #expect(colony.lineOfSight == 2)

        let towerType = BuildingType(id: "tower", specification: spec)
        towerType.addModifier(Modifier(Modifier.lineOfSightBonus, 2, .additive))
        colony.addBuilding(Building(game: game, colony: colony, type: towerType))
        #expect(colony.lineOfSight == 4)
    }

    @Test func canImproveUnitMilitaryRole() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let colony = FreeColTestCase.standardColony(game, 4)

        // The colony has no equipment for the unit
        let colonist = try #require(colony.unitList.first)
        #expect(colony.canImproveUnitMilitaryRole(colonist) == nil)

        // Some equipment, but not enough
        colony.addGoods(musketsType, 40)
        #expect(colony.canImproveUnitMilitaryRole(colonist) == nil)

        // Now enough equipment
        colony.addGoods(musketsType, 10)
        #expect(colony.canProvideGoods(soldierRole.requiredGoods))
        #expect(colony.canImproveUnitMilitaryRole(colonist) === soldierRole)

        // Equipping succeeds, and the colony can no longer improve
        #expect(colony.equipForRole(colonist, soldierRole, 1))
        #expect(colony.canImproveUnitMilitaryRole(colonist) == nil)

        // Adding more muskets does not help
        colony.addGoods(musketsType, 100)
        #expect(colony.canImproveUnitMilitaryRole(colonist) == nil)

        // But adding horses does
        colony.addGoods(horsesType, 100)
        #expect(colony.canImproveUnitMilitaryRole(colonist) === dragoonRole)

        // Unless now a dragoon
        #expect(colony.equipForRole(colonist, dragoonRole, 1))
        #expect(colony.canImproveUnitMilitaryRole(colonist) == nil)

        // Repeat for natives
        let arawak = try #require(game.player(byNationId: "model.nation.arawak"))
        let settlement = IndianSettlementBuilder(game).player(arawak).initialBravesInCamp(4).build()
        let brave = try #require(settlement.unitList.first)
        #expect(settlement.canImproveUnitMilitaryRole(brave) == nil)

        settlement.addGoods(horsesType, 20)
        #expect(settlement.canImproveUnitMilitaryRole(brave) == nil)

        settlement.addGoods(horsesType, 10) // avoid the breeding number
        #expect(settlement.canImproveUnitMilitaryRole(brave) === mountedBraveRole)

        #expect(settlement.equipForRole(brave, mountedBraveRole, 1))
        #expect(settlement.canImproveUnitMilitaryRole(brave) == nil)

        settlement.addGoods(horsesType, 100)
        #expect(settlement.canImproveUnitMilitaryRole(brave) == nil)

        settlement.addGoods(musketsType, 100)
        #expect(settlement.canImproveUnitMilitaryRole(brave) === nativeDragoonRole)

        #expect(settlement.equipForRole(brave, nativeDragoonRole, 1))
        #expect(settlement.canImproveUnitMilitaryRole(brave) == nil)
    }
}

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

/// IndividualFatherTest.java.
@Suite(.serialized)
struct IndividualFatherTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func father(_ id: String) -> FoundingFather { spec.getFoundingFather("model.foundingFather." + id)! }
    var customHouseType: BuildingType { spec.getBuildingType("model.building.customHouse")! }
    var townHallType: BuildingType { spec.getBuildingType("model.building.townHall")! }
    var bellsType: GoodsType { spec.getGoodsType("model.goods.bells")! }
    var horsesType: GoodsType { spec.getGoodsType("model.goods.horses")! }
    var musketsType: GoodsType { spec.getGoodsType("model.goods.muskets")! }
    var soldierRole: Role { spec.getRole("model.role.soldier")! }
    var missionaryRole: Role { spec.getRole("model.role.missionary")! }
    var colonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }
    var statesmanType: UnitType { spec.getUnitType("model.unit.elderStatesman")! }

    /// A standard game with an explored test map.
    func game(explored: Bool = true) -> Game {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: explored))
        return game
    }

    @Test func bolivar() throws {
        let game = game()
        let pop = 5
        let colony = FreeColTestCase.standardColony(game, pop)
        let player = try #require(colony.owner)

        // Zero to start
        #expect(colony.liberty == 0)
        #expect(colony.sonsOfLiberty == 0)

        // Enough to make 2 of 5 rebels: 40%
        let inc = 2 * Colony.libertyPerRebel
        colony.addLiberty(inc)
        #expect(colony.liberty == inc)
        #expect(colony.sonsOfLiberty == 100 * inc / (pop * Colony.libertyPerRebel))

        // Bolivar adds 20%
        player.addFather(father("simonBolivar"))
        colony.addLiberty(0) // provoke recalculation
        #expect(colony.liberty == inc)
        #expect(colony.sonsOfLiberty == 100 * inc / (pop * Colony.libertyPerRebel) + 20)

        // The modifier is there
        let bolivarModifier = try #require(player.modifiers(Modifier.sol).first)
        #expect(bolivarModifier.source === father("simonBolivar"))

        // SoL stops at 100%
        colony.addLiberty(pop * Colony.libertyPerRebel)
        #expect(player.liberty == inc + pop * Colony.libertyPerRebel)
        #expect(player.sonsOfLiberty == 100)
    }

    @Test func brebeuf() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let ability = Ability.expertMissionary
        #expect(father("fatherJeanDeBrebeuf").hasAbility(ability))
        #expect(!dutch.hasAbility(ability))

        let missionary = Unit(game: game, location: nil, owner: dutch, type: colonistType, role: missionaryRole)
        #expect(missionary.role === missionaryRole)
        #expect(missionary.hasAbility(Ability.establishMission))
        #expect(!missionary.hasAbility(ability))

        dutch.addFather(father("fatherJeanDeBrebeuf"))
        #expect(dutch.hasAbility(ability))
        #expect(missionary.hasAbility(ability))
    }

    @Test func brewster() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let ability = Ability.canRecruitUnit
        #expect(dutch.hasAbility(ability))
        for unitType in spec.unitTypeList where unitType.isRecruitable {
            #expect(dutch.hasAbility(ability, for: unitType), "Unable to recruit \(unitType)")
        }

        dutch.addFather(father("williamBrewster"))
        // The ability is no longer general, but limited to some unit types.
        #expect(!dutch.hasAbility(ability))
        for unitType in spec.unitTypeList where unitType.isRecruitable {
            if unitType.skill < 0 {
                #expect(!dutch.hasAbility(ability, for: unitType), "Able to recruit \(unitType)")
            } else {
                #expect(dutch.hasAbility(ability, for: unitType), "Unable to recruit \(unitType)")
            }
        }
    }

    @Test func cortes() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 4)
        let player = try #require(colony.owner)
        let unit = try #require(colony.unitList.first)
        let incaCity = try #require(spec.getNationType("model.nationType.inca")?
            .settlementType(id: "model.settlement.inca"))

        #expect(incaCity.plunderRange(unit)?.factor == 2100)
        player.addFather(father("hernanCortes"))
        #expect(incaCity.plunderRange(unit)?.factor == 3100)
    }

    @Test(.disabled("Needs ServerPlayer.csAddFoundingFather (Phase 3)"))
    func deLasCasas() {}

    @Test func deWitt() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let french = try #require(game.player(byNationId: "model.nation.french"))
        dutch.market!.setArrears(musketsType, 1)

        #expect(!dutch.canTrade(musketsType, .europe))
        #expect(!dutch.canTrade(musketsType, .customHouse))

        dutch.addFather(father("janDeWitt"))
        #expect(!dutch.canTrade(musketsType, .europe))
        #expect(!dutch.canTrade(musketsType, .customHouse))

        dutch.setStance(french, .war)
        #expect(!dutch.canTrade(musketsType, .europe))
        #expect(!dutch.canTrade(musketsType, .customHouse))

        dutch.setStance(french, .peace)
        #expect(!dutch.canTrade(musketsType, .europe))
        #expect(dutch.canTrade(musketsType, .customHouse))
    }

    @Test func jefferson() throws {
        let game = game()
        let jeffersonModifier = try #require(father("thomasJefferson").modifiers("model.goods.bells").first)
        #expect(jeffersonModifier.appliesTo(townHallType))

        let colony = FreeColTestCase.standardColony(game, 4)
        let player = try #require(colony.owner)
        let townHall = try #require(colony.building(townHallType))
        FreeColTestCase.clearWorkLocation(townHall)
        let unit = try #require(colony.firstUnit)
        townHall.add(unit)

        #expect(player.modifiers("model.goods.bells").isEmpty)
        #expect(colony.modifiers("model.goods.bells").isEmpty)
        var expected = 4
        #expect(townHall.totalProduction(of: bellsType) == expected)

        player.addFather(father("thomasJefferson"))
        expected += Int(Double(expected) * 0.5) // the Jefferson bonus
        #expect(player.modifiers("model.goods.bells").count == 1)
        #expect(colony.modifiers("model.goods.bells").isEmpty)
        #expect(townHall.productionModifiers(bellsType, nil).count == 1)
        #expect(townHall.totalProduction(of: bellsType) == expected)
    }

    @Test func minuit() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game)
        let unit = try #require(colony.unitList.first)
        let player = try #require(colony.owner)
        let iroquois = try #require(game.player(byNationId: "model.nation.iroquois"))
        let disputedTile = try #require(colony.tile?.neighbour(.n))
        let settlementTile = try #require(disputedTile.neighbour(.n))
        #expect(settlementTile.owner == nil)

        let indianSettlement = IndianSettlementBuilder(game).player(iroquois).settlementTile(settlementTile)
            .skillToTeach(nil).build()

        // Set up the disputed tile
        let colonyTile = try #require(colony.colonyTile(disputedTile))
        for u in colonyTile.unitList { u.setLocation(colony.tile) }
        disputedTile.changeOwnership(iroquois, indianSettlement)

        #expect(settlementTile.settlement != nil)
        #expect(player.landPrice(disputedTile) > 0)
        #expect(!colonyTile.canAdd(unit))

        player.addFather(father("peterMinuit"))
        #expect(player.landPrice(disputedTile) == 0, "Tile should be zero cost")
        #expect(colonyTile.noAddReason(unit) == .claimRequired, "Should still have to claim the tile")
    }

    @Test func paine() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 4)
        let player = try #require(colony.owner)
        let townHall = try #require(colony.building(townHallType))
        FreeColTestCase.clearWorkLocation(townHall)

        let units = colony.unitList
        for (i, statesman) in units.prefix(3).enumerated() {
            statesman.setType(statesmanType)
            statesman.setLocation(townHall)
            #expect(townHall.totalProduction(of: bellsType) == (i + 1) * 6 + 1)
        }

        player.setTax(20)
        #expect(townHall.totalProduction(of: bellsType) == 3 * 6 + 1)

        player.addFather(father("thomasPaine"))
        player.recalculateBellsBonus()

        #expect(player.hasAbility(Ability.addTaxToBells))
        let modifiers = player.modifiers("model.goods.bells")
        #expect(modifiers.count == 1)
        let paineModifier = try #require(modifiers.first)
        #expect(paineModifier.source === father("thomasPaine"))
        #expect(Int(paineModifier.value) == player.tax)

        var expected = Int(3 * 6 * Float(1.2) + 1)
        #expect(townHall.totalProduction(of: bellsType) == expected)

        player.setTax(30)
        player.recalculateBellsBonus()
        expected = Int(3 * 6 * Float(1.3) + 1)
        #expect(townHall.totalProduction(of: bellsType) == expected)
    }

    @Test func revere() throws {
        let game = game(explored: false)
        let colony = FreeColTestCase.standardColony(game)
        let player = try #require(colony.owner)
        let colonist = try #require(colony.unitList.first)

        #expect(colonist.automaticRole == nil, "No Revere, no auto-equip.")

        // Add Revere to congress
        player.addFather(father("paulRevere"))
        #expect(colonist.automaticRole == nil, "No muskets, no auto-equip")

        colony.addGoods(musketsType, 100)
        #expect(colonist.automaticRole === soldierRole, "Auto equip to soldier role.")

        // Add horses, but still expect soldier
        colony.addGoods(horsesType, 100)
        #expect(colonist.automaticRole === soldierRole, "Auto equip to soldier role despite horses.")
    }

    @Test func stuyvesant() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 4)
        let player = try #require(colony.owner)

        // The custom house can not be built at first
        #expect(!colony.canBuild(customHouseType))

        // but can once Peter Stuyvesant joins the continental congress.
        player.addFather(father("peterStuyvesant"))
        #expect(colony.canBuild(customHouseType))
    }
}

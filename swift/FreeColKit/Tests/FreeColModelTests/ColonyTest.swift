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

/// ColonyTest.java.
@Suite(.serialized)
struct ColonyTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func building(_ id: String) -> BuildingType { spec.getBuildingType("model.building." + id)! }
    func goods(_ id: String) -> GoodsType { spec.getGoodsType("model.goods." + id)! }
    func unitType(_ id: String) -> UnitType { spec.getUnitType("model.unit." + id)! }
    var churchType: BuildingType { building("church") }
    var townHallType: BuildingType { building("townHall") }
    var warehouseType: BuildingType { building("warehouse") }
    var bellsGoodsType: GoodsType { goods("bells") }
    var cottonGoodsType: GoodsType { goods("cotton") }
    var foodGoodsType: GoodsType { spec.primaryFoodType! }
    var grainGoodsType: GoodsType { goods("grain") }
    var plainsTileType: TileType { spec.getTileType("model.tile.plains")! }
    var freeColonistType: UnitType { unitType("freeColonist") }
    var cottonPlanterType: UnitType { unitType("masterCottonPlanter") }
    var elderStatesmanType: UnitType { unitType("elderStatesman") }
    var masterWeaverType: UnitType { unitType("masterWeaver") }

    func game(_ tileType: TileType? = nil) -> Game {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, tileType, explored: true))
        return game
    }

    @Test func currentlyBuilding() {
        let game = game()
        let colony = FreeColTestCase.standardColony(game)
        colony.setCurrentlyBuilding(warehouseType)
        #expect(colony.currentlyBuilding === warehouseType, "Colony should be building a warehouse")
        colony.setCurrentlyBuilding(churchType)
        #expect(colony.currentlyBuilding === churchType, "Colony should be building a church")
    }

    @Test func buildQueueDoesNotAcceptBuildingDoubles() {
        let game = game()
        let colony = FreeColTestCase.standardColony(game)
        colony.setCurrentlyBuilding(warehouseType)
        #expect(colony.buildQueue.count == 1, "Building queue should have 1 entry")
        colony.setCurrentlyBuilding(warehouseType)
        #expect(colony.buildQueue.count == 1, "Building queue should still have 1 entry")
        colony.setCurrentlyBuilding(churchType)
        #expect(colony.buildQueue.count == 2, "Building queue should have 2 entries")
        colony.setCurrentlyBuilding(warehouseType)
        #expect(colony.buildQueue.count == 2, "Building queue should still have 2 entries")
    }

    @Test func buildQueueAcceptsUnitDoubles() {
        let game = game()
        let colony = FreeColTestCase.standardColony(game)
        let wagonTrainType = unitType("wagonTrain")
        colony.setCurrentlyBuilding(wagonTrainType)
        // The default item is in a new colony's build queue
        #expect(colony.buildQueue.count == 2, "Building queue should have 2 entry")
        colony.setCurrentlyBuilding(wagonTrainType)
        #expect(colony.buildQueue.count == 3, "Building queue should have 3 entries")
    }

    @Test func occupationWithFood() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 1)
        #expect(colony.foodProduction > colony.foodConsumption + freeColonistType.consumption(of: grainGoodsType),
                "colony should produce enough food")

        // A colonist with no skill or experience produces food
        let colonist = Unit(game: game, location: colony.tile, owner: colony.owner!, type: freeColonistType)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        #expect(colonist.location is ColonyTile)
        #expect(colonist.workType === grainGoodsType)

        // A colonist with experience in producing farmed goods produces
        // those goods
        colonist.setLocation(colony.tile)
        colonist.changeWorkType(cottonGoodsType)
        colonist.modifyExperience(100)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        #expect(colonist.location is ColonyTile)
        #expect(colonist.workType === cottonGoodsType)

        // An expert produces the expert goods
        colonist.setLocation(colony.tile)
        colonist.setType(cottonPlanterType)
        colonist.changeWorkType(nil)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        #expect(colonist.location is ColonyTile)
        #expect(colonist.workType === cottonGoodsType)

        colonist.setLocation(colony.tile)
        colonist.setType(elderStatesmanType)
        colonist.changeWorkType(nil)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        let building = try #require(colonist.location as? Building)
        #expect(building.type === townHallType)
        #expect(colonist.workType === bellsGoodsType)
    }

    func countParties(_ colony: Colony) -> Int {
        colony.modifiers("model.goods.bells")
            .filter { $0.source?.id == Specification.SourceId.colonyGoodsParty }.count
    }

    /// The tea party modifier (ServerPlayer.makeTeaPartyModifier).
    func makeTeaPartyModifier(_ game: Game) -> Modifier? {
        guard let template = spec.modifiers(Modifier.colonyGoodsParty).first else { return nil }
        let modifier = Modifier.makeTimedModifier("model.goods.bells", template: template, start: game.turn)
        modifier.modifierIndex = Modifier.partyProductionIndex
        return modifier
    }

    @Test func teaParty() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 5)
        #expect(countParties(colony) == 0)
        colony.addModifier(makeTeaPartyModifier(game))
        #expect(countParties(colony) == 1)
        let m = try #require(makeTeaPartyModifier(game))
        m.firstTurn = Turn(game.turn.number + 1)
        colony.addModifier(m)
        #expect(countParties(colony) == 2)
    }

    @Test func addUnitToColony() throws {
        let game = game(spec.getTileType("model.tile.arctic")!)
        let colony = FreeColTestCase.standardColony(game, 1)
        #expect(colony.foodProduction < colony.foodConsumption + freeColonistType.consumption(of: foodGoodsType),
                "colony should produce less food than it consumes")
        #expect(freeColonistType.consumption(of: foodGoodsType) == 2)
        #expect(masterWeaverType.consumption(of: foodGoodsType) == 2)

        // The colonist produces bells, which the colony needs
        let colonist = try #require(colony.unitList.first)
        let townHall = try #require(colony.building(townHallType))
        #expect(colonist.location === townHall)
        #expect(colony.workLocation(for: colonist) === townHall)
        #expect(colonist.workType === bellsGoodsType)

        // The colonist might have experience, but the colony still
        // needs bells
        colonist.setLocation(colony.tile)
        colonist.changeWorkType(cottonGoodsType)
        colonist.modifyExperience(100)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        #expect(colony.workLocation(for: colonist) === townHall)
        #expect(colonist.location === townHall)
        #expect(colonist.workType === bellsGoodsType)

        // A statesman deals with the bells problem
        colonist.setLocation(colony.tile)
        let statesman = Unit(game: game, location: colony.tile, owner: colony.owner!, type: elderStatesmanType)
        FreeColTestCase.nonServerJoinColony(statesman, colony)
        #expect(statesman.location === townHall)
        #expect(statesman.workType === bellsGoodsType)

        // One plains tile
        let plainsTile = try #require(colony.tile?.neighbour(.s))
        plainsTile.type = plainsTileType
        let plainsColonyTile = try #require(colony.colonyTile(plainsTile))
        #expect(plainsColonyTile.isEmpty)

        // One prairie tile
        let prairieTile = try #require(colony.tile?.neighbour(.n))
        prairieTile.type = spec.getTileType("model.tile.prairie")
        prairieTile.addResource(Resource(game: game, tile: prairieTile,
                                         type: spec.getResourceType("model.resource.cotton")!))
        let prairieColonyTile = try #require(colony.colonyTile(prairieTile))
        #expect(prairieColonyTile.isEmpty)

        // The colonist's experience might be cotton, but the colony
        // needs food
        colonist.setLocation(colony.tile)
        colonist.changeWorkType(cottonGoodsType)
        colonist.modifyExperience(100)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        #expect(colonist.location === plainsColonyTile)
        #expect(colonist.workType === grainGoodsType)

        // Change the center tile to plowed plains for more food
        colony.tile!.changeType(plainsTileType)
        let tileImprovement = TileImprovement(game: game, tile: colony.tile!,
                                              type: spec.getTileImprovementType("model.improvement.plow")!,
                                              style: nil)
        tileImprovement.turnsToComplete = 0
        colony.tile!.add(tileImprovement)
        colony.invalidateCache()
        #expect(colony.foodProduction >= colony.foodConsumption + freeColonistType.consumption(of: foodGoodsType),
                "colony should produce more food than it consumes")

        // The colonist's experience now leads to cotton
        colonist.setLocation(colony.tile)
        colonist.changeWorkType(cottonGoodsType)
        colonist.modifyExperience(100)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        #expect(colonist.location === prairieColonyTile)
        #expect(colonist.workType === cottonGoodsType)

        // and the expert still makes cotton
        colonist.setLocation(colony.tile)
        colonist.changeWorkType(nil)
        colonist.setType(cottonPlanterType)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        #expect(colonist.location === prairieColonyTile)
        #expect(colonist.workType === cottonGoodsType)

        // A weaver makes cloth, as there is cotton now
        colonist.setLocation(colony.tile)
        colonist.changeWorkType(nil)
        colonist.setType(masterWeaverType)
        colony.addGoods(cottonGoodsType, 100)
        FreeColTestCase.nonServerJoinColony(colonist, colony)
        let weaversHouse = try #require(colony.building(building("weaverHouse")))
        #expect(colonist.location === weaversHouse)
        #expect(colonist.workType === goods("cloth"))
    }

    @Test func foundColony() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.coastTestMap(game, plainsTileType)
        game.changeMap(map)

        let colony = FreeColTestCase.standardColony(game, 3, 1, 8)
        let dutch = try #require(colony.owner)
        let colonyTile = try #require(colony.tile)
        #expect(colonyTile.type === plainsTileType)

        let colonist = try #require(colony.unitList.first)
        var workedTile: Tile?
        for ct in colony.colonyTiles where !ct.isColonyCenterTile {
            workedTile = ct.workTile
            if workedTile!.isInUse {
                break
            } else if workedTile!.type === plainsTileType {
                colonist.changeWorkType(spec.primaryFoodType)
                colonist.setLocation(ct)
                break
            }
        }
        let worked = try #require(workedTile)
        #expect(worked.isInUse)

        let camp = IndianSettlementBuilder(game).build()
        let indianPlayer = try #require(camp.owner)
        let campTile = try #require(camp.tile)
        #expect(campTile.type === plainsTileType)
        let nativeTile = try #require(campTile.surroundingTiles(1).first { $0.type === plainsTileType })
        #expect(nativeTile.owner === indianPlayer)

        let french = try #require(game.player(byNationId: "model.nation.french"))
        let frenchColony = FreeColTestCase.standardColony(game, 3, 9, 8)
        frenchColony.changeOwner(french)
        #expect(frenchColony.tile?.type === plainsTileType)
        let frenchTile = try #require(frenchColony.tile!.surroundingTiles(1).first { $0.type === plainsTileType })
        #expect(frenchTile.owner === french)

        let landTile = try #require(map.tile(1, 1))
        let lcrTile = try #require(map.tile(2, 2))
        lcrTile.add(LostCityRumour(game: game, tile: lcrTile, type: .noSuchRumour, name: "fake"))
        let waterTile = try #require(map.tile(12, 12))
        #expect(!waterTile.isLand)

        #expect(dutch.canOwnTile(landTile), "Can own empty tile")
        #expect(!dutch.canOwnTile(lcrTile), "Europeans can not own tile with an LCR on it")
        #expect(indianPlayer.canOwnTile(campTile), "Natives can own tile with an LCR on it")
        #expect(dutch.canOwnTile(waterTile), "Europeans can own water tile")
        #expect(!indianPlayer.canOwnTile(waterTile), "Natives can not own water tile")

        #expect(dutch.canClaimToFoundSettlementReason(landTile) == .none, "Can found on land")
        #expect(dutch.canClaimToFoundSettlementReason(waterTile) == .terrain, "Can found on unsettleable tile")
        #expect(dutch.canClaimToFoundSettlementReason(lcrTile) == .rumour, "Can not found on LCR")
        #expect(indianPlayer.canClaimToFoundSettlementReason(waterTile) == .terrain, "Can not found on water")
        #expect(dutch.canClaimToFoundSettlementReason(campTile) == .settlement, "Can not found on settlement")
        #expect(dutch.canClaimToFoundSettlementReason(worked) == .worked, "Can not found on tile in use")
        #expect(dutch.canClaimToFoundSettlementReason(frenchTile) == .europeans, "Can not found on European tile")
        #expect(dutch.canClaimToFoundSettlementReason(nativeTile) == .natives,
                "Might be able to found on native settlement tile")
        landTile.owner = indianPlayer
        #expect(dutch.canClaimToFoundSettlementReason(landTile) == .natives,
                "Might be able to found on loose native tile")
        landTile.owner = nil

        #expect(dutch.canClaimForSettlementReason(landTile) == .none, "Can use land")
        #expect(dutch.canClaimForSettlementReason(waterTile) == .none, "Can use unsettleable tile")
        #expect(dutch.canClaimForSettlementReason(lcrTile) == .rumour, "Europeans can not use LCR")
        #expect(indianPlayer.canClaimForSettlementReason(lcrTile) == .none, "Natives can use LCR")
        #expect(dutch.canClaimForSettlementReason(waterTile) == .none, "Europeans can use water")
        #expect(indianPlayer.canClaimForSettlementReason(waterTile) == .water, "Natives can not use water")
        #expect(dutch.canClaimForSettlementReason(campTile) == .settlement, "Can not use on settlement")
        #expect(dutch.canClaimForSettlementReason(worked) == .worked, "Can not use tile in use")
        #expect(dutch.canClaimForSettlementReason(frenchTile) == .europeans, "Can not use European tile")
        #expect(dutch.canClaimForSettlementReason(nativeTile) == .natives, "Can not use native tile")
    }

    @Test func underSiege() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 5)
        let tile = try #require(colony.tile?.neighbour(.n))
        let iroquois = try #require(game.player(byNationId: "model.nation.iroquois"))
        let braveType = unitType("brave")
        let owner = try #require(colony.owner)

        #expect(!colony.isUnderSiege, "No enemy units present.")
        _ = Unit(game: game, location: tile, owner: iroquois, type: braveType)
        #expect(!colony.isUnderSiege, "Not at war with the Iroquois.")

        // Declare war
        owner.setStance(iroquois, .war)
        iroquois.setStance(owner, .war)
        #expect(colony.isUnderSiege, "At war with the Iroquois.")

        let soldierRole = spec.getRole("model.role.soldier")!
        _ = Unit(game: game, location: colony.tile, owner: owner, type: freeColonistType, role: soldierRole)
        #expect(!colony.isUnderSiege, "Equal number of friendly and enemy combat units.")

        _ = Unit(game: game, location: tile, owner: iroquois, type: braveType)
        #expect(colony.isUnderSiege, "Enemy combat units outnumber friendly combat units.")

        let colonist = Unit(game: game, location: colony.tile, owner: owner, type: freeColonistType)
        #expect(colony.isUnderSiege, "Enemy combat units outnumber friendly combat units.")

        colonist.changeRole(soldierRole, 1)
        #expect(!colony.isUnderSiege, "Equal number of friendly and enemy combat units.")
    }

    @Test func upkeep() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 5)
        #expect(colony.upkeep == 0, "New colonies should not require upkeep.")

        let churchUpkeep = churchType.upkeep
        try #require(colony.building(churchType)).upgrade()
        #expect(colony.upkeep == churchUpkeep)

        let lumberMillUpkeep = building("lumberMill").upkeep
        try #require(colony.building(building("carpenterHouse"))).upgrade()
        #expect(colony.upkeep == churchUpkeep + lumberMillUpkeep)
    }

    @Test(.disabled("copyColony and getCorresponding are not ported yet (they copy by writing XML)"))
    func copyColony() {}
}

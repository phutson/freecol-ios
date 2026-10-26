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

/// ColonyProductionTest.java.
@Suite(.serialized)
struct ColonyProductionTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func goods(_ id: String) -> GoodsType { spec.getGoodsType("model.goods." + id)! }
    var countryType: BuildingType { spec.getBuildingType("model.building.country")! }
    var depotType: BuildingType { spec.getBuildingType("model.building.depot")! }
    var townHallType: BuildingType { spec.getBuildingType("model.building.townHall")! }
    var bellsType: GoodsType { goods("bells") }
    var cottonType: GoodsType { goods("cotton") }
    var foodType: GoodsType { goods("food") }
    var grainType: GoodsType { goods("grain") }
    var horsesType: GoodsType { goods("horses") }
    var plainsType: TileType { spec.getTileType("model.tile.plains")! }
    var freeColonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }

    /// A colony built by a unit on (6, 8), with a grain resource on
    /// (5, 8); the unit then works the best grain place.
    func checkBuiltColony(_ unitTypeId: String) throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let tile = try #require(map.tile(5, 8))
        tile.addResource(Resource(game: game, tile: tile, type: spec.getResourceType("model.resource.grain")!))

        let tileOfColony = try #require(map.tile(6, 8))
        let unit = Unit(game: game, location: tileOfColony, owner: dutch,
                        type: spec.getUnitType(unitTypeId)!)
        let colony = Colony(game: game, owner: dutch, name: "New Amsterdam", tile: tileOfColony)
        dutch.addSettlement(colony)
        FreeColTestCase.nonServerBuildColony(unit, colony)
        unit.setLocation(colony.workLocation(for: unit, grainType))

        // The colony
        #expect(colony.tile === map.tile(6, 8))
        #expect(colony.name == "New Amsterdam")
        #expect(colony.tile?.settlement === colony)
        #expect(colony.tile?.owner === dutch)

        // Java no longer checks the equipment, which the server
        // removes.  The unit works the field with the bonus.
        #expect(unit.workType === grainType)
        #expect(unit.tile === tileOfColony)
        #expect(unit.movesLeft == 0)
    }

    @Test func productionSoldier() throws {
        try checkBuiltColony("model.unit.veteranSoldier")
    }

    @Test func productionPioneer() throws {
        try checkBuiltColony("model.unit.hardyPioneer")
    }

    @Test func bellNetProduction() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))

        // A minimal colony, so the units that use no bells do not matter.
        let colony = FreeColTestCase.standardColony(game, 1)
        let player = try #require(colony.owner)
        let noBellUnits = try #require(spec.getInteger(GameOptions.unitsThatUseNoBells))

        // Clear the town hall
        let townHall = try #require(colony.building(townHallType))
        for u in townHall.unitList { u.setLocation(colony.workLocation(for: u, foodType)) }
        #expect(townHall.isEmpty)

        #expect(colony.goodsCount(bellsType) == 0, "Wrong initial bell count")

        // The consumption without the unit threshold
        var expectedBellUpkeep = max(colony.unitCount - noBellUnits, 0)
        #expect(colony.consumption(of: bellsType) == expectedBellUpkeep, "Wrong bell upkeep")

        // Enough units to pass the units that use no bells
        for _ in 0..<noBellUnits {
            let u = Unit(game: game, location: colony.tile, owner: player, type: freeColonistType)
            #expect(u.setLocation(colony.workLocation(for: u, foodType)))
        }
        #expect(townHall.isEmpty)
        colony.invalidateCache()

        expectedBellUpkeep = max(colony.unitCount - noBellUnits, 0)
        #expect(colony.consumption(of: bellsType) == expectedBellUpkeep, "Wrong bell upkeep (more units)")

        var expectedBellProd = townHallType.baseProduction(nil, bellsType, nil)
        #expect(colony.totalProduction(of: bellsType) == expectedBellProd, "Wrong unattended bell production")
        #expect(colony.netProduction(of: bellsType) == expectedBellProd - expectedBellUpkeep,
                "Wrong unattended bell net production")

        let unit = try #require(colony.firstUnit)
        #expect(unit.setLocation(townHall))
        colony.invalidateCache()

        expectedBellProd = townHallType.baseProduction(townHall.productionType, bellsType, unit.type)
            + townHallType.baseProduction(nil, bellsType, nil)
        #expect(colony.totalProduction(of: bellsType) == expectedBellProd, "Wrong attended bell production")
        #expect(colony.netProduction(of: bellsType) == expectedBellProd - expectedBellUpkeep,
                "Wrong attended bell net production")
    }

    /// No horses are over produced, so none are thrown out.  The horse
    /// production itself is checked in BuildingTest.
    @Test func noHorsesOverProduction() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let colony = FreeColTestCase.standardColony(game, 1)
        let pasture = try #require(colony.building(countryType))
        let unit = try #require(colony.firstUnit)
        unit.setLocation(colony.workLocation(for: unit, foodType))

        let outputs = pasture.outputs
        #expect(outputs.count == 1)
        #expect(outputs.first?.type === horsesType)
        #expect(colony.warehouseCapacity == GoodsContainer.cargoSize, "Wrong warehouse capacity in colony")

        // Still room for more
        colony.addGoods(horsesType, 99)
        colony.invalidateCache()
        #expect(colony.goodsCount(horsesType) == 99)
        #expect(colony.netProduction(of: foodType) > 1)
        #expect(pasture.totalProduction(of: horsesType) == 1, "Wrong horse production")
        #expect(pasture.maximumProduction(of: horsesType) == 1, "Wrong maximum horse production")
        #expect(colony.netProduction(of: horsesType) == 1, "Wrong net horse production")

        // No more room
        colony.addGoods(horsesType, 1)
        colony.invalidateCache()
        #expect(colony.goodsCount(horsesType) == colony.warehouseCapacity, "Wrong number of horses in colony")
        #expect(pasture.totalProduction(of: horsesType) == 0, "Wrong horse production")
        #expect(pasture.maximumProduction(of: horsesType) == 0, "Wrong maximum horse production")
        #expect(colony.netProduction(of: horsesType) == 0, "Wrong net horse production")
    }

    @Test func consumers() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let colony = FreeColTestCase.standardColony(game, 3)
        let units = colony.unitCount
        let buildings = colony.buildings.count

        var consumers = colony.consumers
        // Units first, then buildings, then the build and population queues
        for index in 0..<units { #expect(consumers[index] is Unit, "\(consumers[index])") }
        for index in units..<units + buildings { #expect(consumers[index] is Building, "\(consumers[index])") }
        for index in units + buildings..<units + buildings + 2 {
            #expect(consumers[index] is BuildQueue<BuildableType> || consumers[index] is BuildQueue<UnitType>,
                    "\(consumers[index])")
        }

        let country = try #require(colony.building(countryType))
        let depot = try #require(colony.building(depotType))
        let countryIndex = try #require(consumers.firstIndex { $0 === country })
        let depotIndex = try #require(consumers.firstIndex { $0 === depot })
        #expect(depotIndex < countryIndex, "Priority of depot should be higher than that of country")

        let armoryType = spec.getBuildingType("model.building.armory")!
        colony.addBuilding(Building(game: game, colony: colony, type: armoryType))
        consumers = colony.consumers

        for index in 0..<units { #expect(consumers[index] is Unit, "\(consumers[index])") }
        let offset = units + buildings
        for index in units..<offset { #expect(consumers[index] is Building, "\(consumers[index])") }
        // The build queue comes next
        #expect(consumers[offset] is BuildQueue<BuildableType>, "\(consumers[offset])")
        // The armory has a lower priority than the build queue
        #expect((consumers[offset + 1] as? Building)?.type === armoryType, "\(consumers[offset + 1])")
        // The population queue comes last
        #expect(consumers[offset + 2] is BuildQueue<UnitType>, "\(consumers[offset + 2])")
    }

    @Test func productionMap() {
        let pm = ProductionMap()
        pm.add(AbstractGoods(cottonType, 33))
        #expect(pm.get(cottonType).amount == 33)

        pm.add(AbstractGoods(grainType, 44))
        #expect(pm.get(grainType).amount == 44)
        #expect(pm.get(foodType).amount == 44)

        pm.remove(AbstractGoods(grainType, 22))
        #expect(pm.get(grainType).amount == 22)
        #expect(pm.get(foodType).amount == 22)

        pm.remove(AbstractGoods(foodType, 11))
        #expect(pm.get(grainType).amount == 11)
        #expect(pm.get(foodType).amount == 11)
    }

    @Test func production() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let colony = FreeColTestCase.standardColony(game, 3)
        let tile = try #require(colony.colonyTile(colony.tile))

        #expect(colony.goodsCount(foodType) == 0)
        let production = tile.production
        try #require(production.count >= 2)
        #expect(production[0].type === grainType)
        #expect(production[0].amount == 3)
        #expect(production[1].type === cottonType)
        #expect(production[1].amount == 2)

        for unit in colony.unitList {
            let unitInfo = try #require(colony.productionInfo(of: unit))
            #expect(unitInfo.consumption.count == 2)
            #expect(unitInfo.maximumConsumption.count == 2)
            let pi = try #require(colony.productionInfo(of: unit.location!))
            #expect(pi.production.count == 1)
            if unit.location is ColonyTile {
                // Grain for the food demand
                #expect(pi.production.first?.type === grainType)
                #expect(pi.production.first?.amount == 5)
            } else {
                // Bells for the bells demand
                #expect(pi.production.first?.type === bellsType)
                #expect(pi.production.first?.amount == 3)
            }
        }
    }

    @Test func getPotentialProduction() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let colony = FreeColTestCase.standardColony(game, 1)
        let colonyTile = try #require(colony.colonyTile(colony.tile))
        #expect(colony.tile?.type === plainsType)
        let townHall = try #require(colony.building(townHallType))
        #expect(townHall.isEmpty)
        let colonistType = try #require(spec.defaultUnitType(colony.owner?.nationType))

        #expect(townHall.potentialProduction(cottonType, nil) == 0,
                "Zero potential production of cotton in town hall")
        #expect(townHall.potentialProduction(bellsType, nil) == townHallType.baseProduction(nil, bellsType, nil),
                "Basic potential production of bells in town hall")
        #expect(townHall.potentialProduction(bellsType, colonistType)
                == townHallType.baseProduction(nil, bellsType, colonistType),
                "Unit potential production of bells in town hall")

        #expect(colonyTile.potentialProduction(bellsType, nil) == 0,
                "Zero potential production of bells on center tile")
        #expect(colonyTile.potentialProduction(cottonType, nil) == plainsType.baseProduction(nil, cottonType, nil),
                "Basic potential production of cotton on center tile")
        #expect(colonyTile.potentialProduction(cottonType, colonistType) == 0,
                "Zero unit potential production of cotton on center tile")
    }
}

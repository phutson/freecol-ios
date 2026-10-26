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

/// ProductionTypeTest.java, with the classic rules.
///
/// Each test is named after its tile or building type with
/// "Production" added, as the plain names are the types.
@Suite(.serialized)
struct ProductionTypeTest {

    nonisolated(unsafe) static let s = FreeColTestCase.loadSpecification("classic")

    var armory: BuildingType { Self.s.getBuildingType("model.building.armory")! }
    var arsenal: BuildingType { Self.s.getBuildingType("model.building.arsenal")! }
    var blacksmithHouse: BuildingType { Self.s.getBuildingType("model.building.blacksmithHouse")! }
    var blacksmithShop: BuildingType { Self.s.getBuildingType("model.building.blacksmithShop")! }
    var carpenterHouse: BuildingType { Self.s.getBuildingType("model.building.carpenterHouse")! }
    var cathedral: BuildingType { Self.s.getBuildingType("model.building.cathedral")! }
    var chapel: BuildingType { Self.s.getBuildingType("model.building.chapel")! }
    var church: BuildingType { Self.s.getBuildingType("model.building.church")! }
    var cigarFactory: BuildingType { Self.s.getBuildingType("model.building.cigarFactory")! }
    var college: BuildingType { Self.s.getBuildingType("model.building.college")! }
    var country: BuildingType { Self.s.getBuildingType("model.building.country")! }
    var customHouse: BuildingType { Self.s.getBuildingType("model.building.customHouse")! }
    var depot: BuildingType { Self.s.getBuildingType("model.building.depot")! }
    var distillerHouse: BuildingType { Self.s.getBuildingType("model.building.distillerHouse")! }
    var docks: BuildingType { Self.s.getBuildingType("model.building.docks")! }
    var drydock: BuildingType { Self.s.getBuildingType("model.building.drydock")! }
    var fort: BuildingType { Self.s.getBuildingType("model.building.fort")! }
    var fortress: BuildingType { Self.s.getBuildingType("model.building.fortress")! }
    var furFactory: BuildingType { Self.s.getBuildingType("model.building.furFactory")! }
    var furTraderHouse: BuildingType { Self.s.getBuildingType("model.building.furTraderHouse")! }
    var furTradingPost: BuildingType { Self.s.getBuildingType("model.building.furTradingPost")! }
    var ironWorks: BuildingType { Self.s.getBuildingType("model.building.ironWorks")! }
    var lumberMill: BuildingType { Self.s.getBuildingType("model.building.lumberMill")! }
    var magazine: BuildingType { Self.s.getBuildingType("model.building.magazine")! }
    var newspaper: BuildingType { Self.s.getBuildingType("model.building.newspaper")! }
    var printingPress: BuildingType { Self.s.getBuildingType("model.building.printingPress")! }
    var rumDistillery: BuildingType { Self.s.getBuildingType("model.building.rumDistillery")! }
    var rumFactory: BuildingType { Self.s.getBuildingType("model.building.rumFactory")! }
    var schoolhouse: BuildingType { Self.s.getBuildingType("model.building.schoolhouse")! }
    var shipyard: BuildingType { Self.s.getBuildingType("model.building.shipyard")! }
    var stables: BuildingType { Self.s.getBuildingType("model.building.stables")! }
    var stockade: BuildingType { Self.s.getBuildingType("model.building.stockade")! }
    var textileMill: BuildingType { Self.s.getBuildingType("model.building.textileMill")! }
    var tobacconistHouse: BuildingType { Self.s.getBuildingType("model.building.tobacconistHouse")! }
    var tobacconistShop: BuildingType { Self.s.getBuildingType("model.building.tobacconistShop")! }
    var townHall: BuildingType { Self.s.getBuildingType("model.building.townHall")! }
    var university: BuildingType { Self.s.getBuildingType("model.building.university")! }
    var warehouse: BuildingType { Self.s.getBuildingType("model.building.warehouse")! }
    var warehouseExpansion: BuildingType { Self.s.getBuildingType("model.building.warehouseExpansion")! }
    var weaverHouse: BuildingType { Self.s.getBuildingType("model.building.weaverHouse")! }
    var weaverShop: BuildingType { Self.s.getBuildingType("model.building.weaverShop")! }
    var bells: GoodsType { Self.s.getGoodsType("model.goods.bells")! }
    var cigars: GoodsType { Self.s.getGoodsType("model.goods.cigars")! }
    var cloth: GoodsType { Self.s.getGoodsType("model.goods.cloth")! }
    var coats: GoodsType { Self.s.getGoodsType("model.goods.coats")! }
    var cotton: GoodsType { Self.s.getGoodsType("model.goods.cotton")! }
    var crosses: GoodsType { Self.s.getGoodsType("model.goods.crosses")! }
    var fish: GoodsType { Self.s.getGoodsType("model.goods.fish")! }
    var food: GoodsType { Self.s.getGoodsType("model.goods.food")! }
    var furs: GoodsType { Self.s.getGoodsType("model.goods.furs")! }
    var grain: GoodsType { Self.s.getGoodsType("model.goods.grain")! }
    var hammers: GoodsType { Self.s.getGoodsType("model.goods.hammers")! }
    var horses: GoodsType { Self.s.getGoodsType("model.goods.horses")! }
    var lumber: GoodsType { Self.s.getGoodsType("model.goods.lumber")! }
    var muskets: GoodsType { Self.s.getGoodsType("model.goods.muskets")! }
    var ore: GoodsType { Self.s.getGoodsType("model.goods.ore")! }
    var rum: GoodsType { Self.s.getGoodsType("model.goods.rum")! }
    var tobacco: GoodsType { Self.s.getGoodsType("model.goods.tobacco")! }
    var tools: GoodsType { Self.s.getGoodsType("model.goods.tools")! }
    var silver: GoodsType { Self.s.getGoodsType("model.goods.silver")! }
    var sugar: GoodsType { Self.s.getGoodsType("model.goods.sugar")! }
    var arctic: TileType { Self.s.getTileType("model.tile.arctic")! }
    var borealForest: TileType { Self.s.getTileType("model.tile.borealForest")! }
    var broadleafForest: TileType { Self.s.getTileType("model.tile.broadleafForest")! }
    var coniferForest: TileType { Self.s.getTileType("model.tile.coniferForest")! }
    var desert: TileType { Self.s.getTileType("model.tile.desert")! }
    var grassland: TileType { Self.s.getTileType("model.tile.grassland")! }
    var greatRiver: TileType { Self.s.getTileType("model.tile.greatRiver")! }
    var highSeas: TileType { Self.s.getTileType("model.tile.highSeas")! }
    var hills: TileType { Self.s.getTileType("model.tile.hills")! }
    var lake: TileType { Self.s.getTileType("model.tile.lake")! }
    var marsh: TileType { Self.s.getTileType("model.tile.marsh")! }
    var mixedForest: TileType { Self.s.getTileType("model.tile.mixedForest")! }
    var mountains: TileType { Self.s.getTileType("model.tile.mountains")! }
    var ocean: TileType { Self.s.getTileType("model.tile.ocean")! }
    var plains: TileType { Self.s.getTileType("model.tile.plains")! }
    var prairie: TileType { Self.s.getTileType("model.tile.prairie")! }
    var rainForest: TileType { Self.s.getTileType("model.tile.rainForest")! }
    var savannah: TileType { Self.s.getTileType("model.tile.savannah")! }
    var scrubForest: TileType { Self.s.getTileType("model.tile.scrubForest")! }
    var swamp: TileType { Self.s.getTileType("model.tile.swamp")! }
    var tropicalForest: TileType { Self.s.getTileType("model.tile.tropicalForest")! }
    var tundra: TileType { Self.s.getTileType("model.tile.tundra")! }
    var wetlandForest: TileType { Self.s.getTileType("model.tile.wetlandForest")! }
    var colonistType: UnitType { Self.s.defaultUnitType! }

    /// The inputs and outputs still expected.
    final class Expected {
        var inputs: [GoodsType: Int] = [:]
        var outputs: [GoodsType: Int] = [:]

        /// Check the production types against the expected goods, which
        /// are used up (testProduction).
        func check(_ productionTypes: [ProductionType], sourceLocation: SourceLocation = #_sourceLocation) {
            for productionType in productionTypes {
                for ag in productionType.inputs {
                    let i = inputs[ag.type!]
                    #expect(i != nil, "Input expected for \(ag.type!)", sourceLocation: sourceLocation)
                    #expect(i == ag.amount, "Input amount mismatch for \(ag.type!)", sourceLocation: sourceLocation)
                    inputs[ag.type!] = nil
                }
                for ag in productionType.outputs {
                    let i = outputs[ag.type!]
                    #expect(i != nil, "Output expected for \(ag.type!)", sourceLocation: sourceLocation)
                    #expect(i == ag.amount, "Output amount mismatch for \(ag.type!)", sourceLocation: sourceLocation)
                    outputs[ag.type!] = nil
                }
            }
            #expect(inputs.isEmpty, "Input remaining", sourceLocation: sourceLocation)
            #expect(outputs.isEmpty, "Output remaining", sourceLocation: sourceLocation)
        }
    }

    func genericPotential(_ tileType: TileType, _ goodsType: GoodsType) -> Int {
        tileType.potentialProduction(goodsType, colonistType)
    }


    @Test func arcticProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.check(arctic.availableProductionTypes(unattended: true, level: "veryHigh"))
        e.check(arctic.availableProductionTypes(unattended: false, level: "veryHigh"))
        e.outputs[grain] = 1
        e.check(arctic.availableProductionTypes(unattended: true, level: "high"))
        e.check(arctic.availableProductionTypes(unattended: false, level: "high"))
        for level in ["medium", "low", "veryLow"] {
            e.check(arctic.availableProductionTypes(unattended: true, level: level))
            e.check(arctic.availableProductionTypes(unattended: false, level: level))
        }
        #expect(arctic.potentialProduction(grain, nil) == 0)
        #expect(genericPotential(arctic, grain) == 0)
    }

    @Test func borealForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[furs] = 3
        e.check(borealForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 2
        e.outputs[furs] = 3
        e.outputs[lumber] = 4
        e.outputs[ore] = 1
        e.check(borealForest.availableProductionTypes(unattended: false))
        #expect(borealForest.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(borealForest, grain) == 2)
    }

    @Test func broadleafForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[furs] = 2
        e.check(broadleafForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 2
        e.outputs[cotton] = 1
        e.outputs[furs] = 2
        e.outputs[lumber] = 4
        e.check(broadleafForest.availableProductionTypes(unattended: false))
        #expect(broadleafForest.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(broadleafForest, grain) == 2)
    }

    @Test func coniferForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[furs] = 2
        e.check(coniferForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 2
        e.outputs[tobacco] = 1
        e.outputs[furs] = 2
        e.outputs[lumber] = 6
        e.check(coniferForest.availableProductionTypes(unattended: false))
        #expect(coniferForest.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(coniferForest, grain) == 2)
    }

    @Test func desertProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[ore] = 2
        e.check(desert.availableProductionTypes(unattended: true, level: "veryHigh"))
        e.outputs[grain] = 1
        e.outputs[ore] = 2
        e.check(desert.availableProductionTypes(unattended: true))
        e.outputs[grain] = 1
        e.outputs[ore] = 2
        e.check(desert.availableProductionTypes(unattended: true, level: "veryLow"))
        e.outputs[grain] = 2
        e.outputs[cotton] = 1
        e.outputs[ore] = 2
        e.check(desert.availableProductionTypes(unattended: false))
        #expect(desert.potentialProduction(grain, nil) == 1)
        #expect(genericPotential(desert, grain) == 2)
    }

    @Test func grasslandProduction() {
        let e = Expected()
        e.outputs[grain] = 3
        e.outputs[tobacco] = 3
        e.check(grassland.availableProductionTypes(unattended: true))
        e.outputs[grain] = 3
        e.outputs[tobacco] = 3
        e.check(grassland.availableProductionTypes(unattended: false))
        #expect(grassland.potentialProduction(grain, nil) == 3)
        #expect(genericPotential(grassland, grain) == 3)
    }

    @Test func greatRiverProduction() {
        let e = Expected()
        e.check(greatRiver.availableProductionTypes(unattended: true))
        e.outputs[fish] = 2
        e.check(greatRiver.availableProductionTypes(unattended: false))
        #expect(greatRiver.potentialProduction(grain, nil) == 0)
        #expect(genericPotential(greatRiver, grain) == 0)
    }

    @Test func highSeasProduction() {
        let e = Expected()
        e.check(highSeas.availableProductionTypes(unattended: true))
        e.outputs[fish] = 2
        e.check(highSeas.availableProductionTypes(unattended: false))
        #expect(highSeas.potentialProduction(grain, nil) == 0)
        #expect(genericPotential(highSeas, grain) == 0)
    }

    @Test func hillsProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[ore] = 4
        e.check(hills.availableProductionTypes(unattended: true))
        e.outputs[grain] = 2
        e.outputs[ore] = 4
        e.check(hills.availableProductionTypes(unattended: false))
        #expect(hills.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(hills, grain) == 2)
    }

    @Test func lakeProduction() {
        let e = Expected()
        e.check(lake.availableProductionTypes(unattended: true))
        e.outputs[fish] = 2
        e.check(lake.availableProductionTypes(unattended: false))
        #expect(lake.potentialProduction(grain, nil) == 0)
        #expect(genericPotential(lake, grain) == 0)
    }

    @Test func marshProduction() {
        let e = Expected()
        e.outputs[grain] = 3
        e.outputs[tobacco] = 2
        e.check(marsh.availableProductionTypes(unattended: true))
        e.outputs[grain] = 3
        e.outputs[tobacco] = 2
        e.outputs[ore] = 2
        e.outputs[silver] = 0
        e.check(marsh.availableProductionTypes(unattended: false))
        #expect(marsh.potentialProduction(grain, nil) == 3)
        #expect(genericPotential(marsh, grain) == 3)
    }

    @Test func mixedForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[furs] = 3
        e.check(mixedForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 3
        e.outputs[cotton] = 1
        e.outputs[furs] = 3
        e.outputs[lumber] = 6
        e.check(mixedForest.availableProductionTypes(unattended: false))
        #expect(mixedForest.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(mixedForest, grain) == 3)
    }

    @Test func mountainsProduction() {
        let e = Expected()
        e.check(mountains.availableProductionTypes(unattended: true))
        e.outputs[ore] = 4
        e.outputs[silver] = 1
        e.check(mountains.availableProductionTypes(unattended: false))
        #expect(mountains.potentialProduction(grain, nil) == 0)
        #expect(genericPotential(mountains, grain) == 0)
    }

    @Test func oceanProduction() {
        let e = Expected()
        e.check(ocean.availableProductionTypes(unattended: true))
        e.outputs[fish] = 2
        e.check(ocean.availableProductionTypes(unattended: false))
        #expect(ocean.potentialProduction(grain, nil) == 0)
        #expect(genericPotential(ocean, grain) == 0)
    }

    @Test func plainsProduction() {
        let e = Expected()
        e.outputs[grain] = 3
        e.outputs[cotton] = 2
        e.check(plains.availableProductionTypes(unattended: true))
        e.outputs[grain] = 5
        e.outputs[cotton] = 2
        e.outputs[ore] = 1
        e.check(plains.availableProductionTypes(unattended: false))
        #expect(plains.potentialProduction(grain, nil) == 3)
        #expect(genericPotential(plains, grain) == 5)
    }

    @Test func prairieProduction() {
        let e = Expected()
        e.outputs[grain] = 3
        e.outputs[cotton] = 3
        e.check(prairie.availableProductionTypes(unattended: true))
        e.outputs[grain] = 3
        e.outputs[cotton] = 3
        e.check(prairie.availableProductionTypes(unattended: false))
        #expect(prairie.potentialProduction(grain, nil) == 3)
        #expect(genericPotential(prairie, grain) == 3)
    }

    @Test func rainForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[sugar] = 1
        e.check(rainForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 2
        e.outputs[sugar] = 1
        e.outputs[furs] = 1
        e.outputs[lumber] = 4
        e.outputs[ore] = 1
        e.outputs[silver] = 0
        e.check(rainForest.availableProductionTypes(unattended: false))
        #expect(rainForest.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(rainForest, grain) == 2)
    }

    @Test func savannahProduction() {
        let e = Expected()
        e.outputs[grain] = 3
        e.outputs[sugar] = 3
        e.check(savannah.availableProductionTypes(unattended: true))
        e.outputs[grain] = 4
        e.outputs[sugar] = 3
        e.check(savannah.availableProductionTypes(unattended: false))
        #expect(savannah.potentialProduction(grain, nil) == 3)
        #expect(genericPotential(savannah, grain) == 4)
    }

    @Test func scrubForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[furs] = 2
        e.check(scrubForest.availableProductionTypes(unattended: true, level: "veryHigh"))
        e.outputs[grain] = 1
        e.outputs[furs] = 2
        e.check(scrubForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 1
        e.outputs[furs] = 2
        e.check(scrubForest.availableProductionTypes(unattended: true, level: "veryLow"))
        e.outputs[grain] = 2
        e.outputs[cotton] = 1
        e.outputs[furs] = 2
        e.outputs[lumber] = 2
        e.outputs[ore] = 1
        e.check(scrubForest.availableProductionTypes(unattended: false))
        #expect(scrubForest.potentialProduction(grain, nil) == 1)
        #expect(genericPotential(scrubForest, grain) == 2)
    }

    @Test func swampProduction() {
        let e = Expected()
        e.outputs[grain] = 3
        e.outputs[sugar] = 2
        e.check(swamp.availableProductionTypes(unattended: true))
        e.outputs[grain] = 3
        e.outputs[sugar] = 2
        e.outputs[ore] = 2
        e.outputs[silver] = 0
        e.check(swamp.availableProductionTypes(unattended: false))
        #expect(swamp.potentialProduction(grain, nil) == 3)
        #expect(genericPotential(swamp, grain) == 3)
    }

    @Test func tropicalForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[furs] = 2
        e.check(tropicalForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 3
        e.outputs[sugar] = 1
        e.outputs[furs] = 2
        e.outputs[lumber] = 4
        e.check(tropicalForest.availableProductionTypes(unattended: false))
        #expect(tropicalForest.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(tropicalForest, grain) == 3)
    }

    @Test func tundraProduction() {
        let e = Expected()
        e.outputs[grain] = 3
        e.outputs[ore] = 2
        e.check(tundra.availableProductionTypes(unattended: true))
        e.outputs[grain] = 3
        e.outputs[ore] = 2
        e.outputs[silver] = 0
        e.check(tundra.availableProductionTypes(unattended: false))
        #expect(tundra.potentialProduction(grain, nil) == 3)
        #expect(genericPotential(tundra, grain) == 3)
    }

    @Test func wetlandForestProduction() {
        let e = Expected()
        e.outputs[grain] = 2
        e.outputs[furs] = 2
        e.check(wetlandForest.availableProductionTypes(unattended: true))
        e.outputs[grain] = 2
        e.outputs[tobacco] = 1
        e.outputs[furs] = 2
        e.outputs[lumber] = 4
        e.outputs[ore] = 1
        e.outputs[silver] = 0
        e.check(wetlandForest.availableProductionTypes(unattended: false))
        #expect(wetlandForest.potentialProduction(grain, nil) == 2)
        #expect(genericPotential(wetlandForest, grain) == 2)
    }

    @Test func bellProductionProduction() {
        let e = Expected()
        e.outputs[bells] = 1
        e.check(townHall.availableProductionTypes(unattended: true))
        e.outputs[bells] = 3
        e.check(townHall.availableProductionTypes(unattended: false))
    }

    @Test func hammerProductionProduction() {
        let e = Expected()
        e.check(carpenterHouse.availableProductionTypes(unattended: true))
        e.inputs[lumber] = 3
        e.outputs[hammers] = 3
        e.check(carpenterHouse.availableProductionTypes(unattended: false))
        e.check(lumberMill.availableProductionTypes(unattended: true))
        e.inputs[lumber] = 6
        e.outputs[hammers] = 6
        e.check(lumberMill.availableProductionTypes(unattended: false))
    }

    @Test func toolsProductionProduction() {
        let e = Expected()
        e.check(blacksmithHouse.availableProductionTypes(unattended: true))
        e.inputs[ore] = 3
        e.outputs[tools] = 3
        e.check(blacksmithHouse.availableProductionTypes(unattended: false))
        e.check(blacksmithShop.availableProductionTypes(unattended: true))
        e.inputs[ore] = 6
        e.outputs[tools] = 6
        e.check(blacksmithShop.availableProductionTypes(unattended: false))
        e.check(ironWorks.availableProductionTypes(unattended: true))
        e.inputs[ore] = 6
        e.outputs[tools] = 9
        e.check(ironWorks.availableProductionTypes(unattended: false))
    }

    @Test func cigarProductionProduction() {
        let e = Expected()
        e.check(tobacconistHouse.availableProductionTypes(unattended: true))
        e.inputs[tobacco] = 3
        e.outputs[cigars] = 3
        e.check(tobacconistHouse.availableProductionTypes(unattended: false))
        e.check(tobacconistShop.availableProductionTypes(unattended: true))
        e.inputs[tobacco] = 6
        e.outputs[cigars] = 6
        e.check(tobacconistShop.availableProductionTypes(unattended: false))
        e.check(cigarFactory.availableProductionTypes(unattended: true))
        e.inputs[tobacco] = 6
        e.outputs[cigars] = 9
        e.check(cigarFactory.availableProductionTypes(unattended: false))
    }

    @Test func clothProductionProduction() {
        let e = Expected()
        e.check(weaverHouse.availableProductionTypes(unattended: true))
        e.inputs[cotton] = 3
        e.outputs[cloth] = 3
        e.check(weaverHouse.availableProductionTypes(unattended: false))
        e.check(weaverShop.availableProductionTypes(unattended: true))
        e.inputs[cotton] = 6
        e.outputs[cloth] = 6
        e.check(weaverShop.availableProductionTypes(unattended: false))
        e.check(textileMill.availableProductionTypes(unattended: true))
        e.inputs[cotton] = 6
        e.outputs[cloth] = 9
        e.check(textileMill.availableProductionTypes(unattended: false))
    }

    @Test func rumProductionProduction() {
        let e = Expected()
        e.check(distillerHouse.availableProductionTypes(unattended: true))
        e.inputs[sugar] = 3
        e.outputs[rum] = 3
        e.check(distillerHouse.availableProductionTypes(unattended: false))
        e.check(rumDistillery.availableProductionTypes(unattended: true))
        e.inputs[sugar] = 6
        e.outputs[rum] = 6
        e.check(rumDistillery.availableProductionTypes(unattended: false))
        e.check(rumFactory.availableProductionTypes(unattended: true))
        e.inputs[sugar] = 6
        e.outputs[rum] = 9
        e.check(rumFactory.availableProductionTypes(unattended: false))
    }

    @Test func coatProductionProduction() {
        let e = Expected()
        e.check(furTraderHouse.availableProductionTypes(unattended: true))
        e.inputs[furs] = 3
        e.outputs[coats] = 3
        e.check(furTraderHouse.availableProductionTypes(unattended: false))
        e.check(furTradingPost.availableProductionTypes(unattended: true))
        e.inputs[furs] = 6
        e.outputs[coats] = 6
        e.check(furTradingPost.availableProductionTypes(unattended: false))
        e.check(furFactory.availableProductionTypes(unattended: true))
        e.inputs[furs] = 6
        e.outputs[coats] = 9
        e.check(furFactory.availableProductionTypes(unattended: false))
    }

    @Test func musketProductionProduction() {
        let e = Expected()
        e.check(armory.availableProductionTypes(unattended: true))
        e.inputs[tools] = 3
        e.outputs[muskets] = 3
        e.check(armory.availableProductionTypes(unattended: false))
        e.check(magazine.availableProductionTypes(unattended: true))
        e.inputs[tools] = 6
        e.outputs[muskets] = 6
        e.check(magazine.availableProductionTypes(unattended: false))
        e.check(arsenal.availableProductionTypes(unattended: true))
        e.inputs[tools] = 9
        e.outputs[muskets] = 9
        e.check(arsenal.availableProductionTypes(unattended: false))
    }

    @Test func crossProductionProduction() {
        let e = Expected()
        e.outputs[crosses] = 1
        e.check(chapel.availableProductionTypes(unattended: true))
        e.check(chapel.availableProductionTypes(unattended: false))
        e.outputs[crosses] = 2
        e.check(church.availableProductionTypes(unattended: true))
        e.outputs[crosses] = 3
        e.check(church.availableProductionTypes(unattended: false))
        e.outputs[crosses] = 3
        e.check(cathedral.availableProductionTypes(unattended: true))
        e.outputs[crosses] = 6
        e.check(cathedral.availableProductionTypes(unattended: false))
    }

    @Test func horseProduction() {
        let e = Expected()
        e.inputs[food] = 1
        e.outputs[horses] = 1
        e.check(country.availableProductionTypes(unattended: true))
        e.check(country.availableProductionTypes(unattended: false))
        e.inputs[food] = 1
        e.outputs[horses] = 1
        e.check(stables.availableProductionTypes(unattended: true))
        e.check(stables.availableProductionTypes(unattended: false))
    }

    @Test func otherBuildingsProduction() {
        let e = Expected()
        for b in [schoolhouse, college, university,
                  stockade, fort, fortress,
                  docks, drydock, shipyard,
                  depot, warehouse, warehouseExpansion,
                  printingPress, newspaper,
                  customHouse] {
            e.check(b.availableProductionTypes(unattended: true))
            e.check(b.availableProductionTypes(unattended: false))
        }
    }
}

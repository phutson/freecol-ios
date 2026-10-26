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

/// BuildingTest.java.
@Suite(.serialized)
struct BuildingTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func building(_ id: String) -> BuildingType { spec.getBuildingType("model.building." + id)! }
    func goods(_ id: String) -> GoodsType { spec.getGoodsType("model.goods." + id)! }
    func unitType(_ id: String) -> UnitType { spec.getUnitType("model.unit." + id)! }

    var chapelType: BuildingType { building("chapel") }
    var schoolType: BuildingType { building("schoolhouse") }
    var stockadeType: BuildingType { building("stockade") }
    var fortType: BuildingType { building("fort") }
    var fortressType: BuildingType { building("fortress") }
    var townHallType: BuildingType { building("townHall") }
    var bellsType: GoodsType { goods("bells") }
    var cottonType: GoodsType { goods("cotton") }
    var crossesType: GoodsType { goods("crosses") }
    var grainType: GoodsType { goods("grain") }
    var horsesType: GoodsType { goods("horses") }
    var musketsType: GoodsType { goods("muskets") }
    var toolsType: GoodsType { goods("tools") }
    var missionaryRole: Role { spec.getRole("model.role.missionary")! }
    var freeColonistType: UnitType { unitType("freeColonist") }
    var indenturedServantType: UnitType { unitType("indenturedServant") }
    var indianConvertType: UnitType { unitType("indianConvert") }
    var pettyCriminalType: UnitType { unitType("pettyCriminal") }
    var firebrandPreacherType: UnitType { unitType("firebrandPreacher") }

    static let bonusLevels = [-2, -1, 0, 1, 2]

    func game() -> Game {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game, explored: true))
        return game
    }

    /// Move a building's units to other work.
    func clearBuilding(_ b: Building, sourceLocation: SourceLocation = #_sourceLocation) {
        let colony = b.colony!
        for u in b.unitList {
            u.setLocation(colony.tile)
            u.workType = grainType
            colony.joinColony(u)
        }
        #expect(b.unitCount == 0, sourceLocation: sourceLocation)
    }

    /// The production of a building family's levels at each production
    /// bonus by each kind of worker: a petty criminal, servant, free
    /// colonist and expert (and an indian convert first).
    func productionTest(_ buildings: [BuildingType], _ values: [[[Int]]],
                        sourceLocation: SourceLocation = #_sourceLocation) throws {
        let game = game()
        // Enable factories
        let colony = FreeColTestCase.standardColony(game, 8) // big enough for a factory
        colony.owner!.addFather(spec.getFoundingFather("model.foundingFather.adamSmith")!)

        let building: Building
        if let b = colony.building(buildings[0]) {
            building = b
        } else {
            building = Building(game: game, colony: colony, type: buildings[0])
            colony.addBuilding(building)
        }
        while building.type !== buildings[0] { building.upgrade() }
        clearBuilding(building, sourceLocation: sourceLocation)
        // Add goods so production is viable
        let pt = try #require(building.bestProductionType(unattended: false, nil), sourceLocation: sourceLocation)
        for ag in pt.inputs { colony.addGoods(ag.type!, 50) }
        let outputType = try #require(pt.outputs.first?.type, sourceLocation: sourceLocation)
        let unitTypes = [indianConvertType, pettyCriminalType, indenturedServantType, freeColonistType,
                         building.expertUnitType!]
        for ut in unitTypes where !colony.unitList.contains(where: { $0.type === ut }) {
            colony.unitList.first { $0.type === freeColonistType }!.changeType(ut)
        }

        for (i, bt) in buildings.enumerated() {
            for (j, level) in Self.bonusLevels.enumerated() {
                for (k, ut) in unitTypes.enumerated() {
                    // Set up the conditions for bt, level, ut
                    while building.type !== bt { building.upgrade() }
                    #expect(building.type === bt, sourceLocation: sourceLocation)
                    clearBuilding(building, sourceLocation: sourceLocation)
                    colony.productionBonus = level
                    let worker = try #require(colony.unitList.first { $0.type === ut }, sourceLocation: sourceLocation)
                    worker.workType = outputType
                    worker.setLocation(building)
                    #expect(building.unitCount == 1, sourceLocation: sourceLocation)
                    #expect(building.unitList.first === worker, sourceLocation: sourceLocation)
                    #expect(worker.workType === outputType, sourceLocation: sourceLocation)
                    colony.invalidateCache()
                    #expect(colony.productionBonus == level, sourceLocation: sourceLocation)

                    // At last, the test.
                    let what = "\(outputType.suffix ?? "") produced in \(bt.suffix ?? "") at bonus \(level)"
                        + " with \(ut.suffix ?? "")"
                    let totalProductionInColony = building.totalProduction(of: outputType)
                    #expect(totalProductionInColony == values[i][j][k], "\(what)", sourceLocation: sourceLocation)
                    if level == 0 {
                        #expect(bt.potentialProduction(outputType, ut) == totalProductionInColony,
                                "BuildingType.getPotentialProduction does not match actual production. \(what)",
                                sourceLocation: sourceLocation)
                    }
                }
            }
        }
    }

    @Test func canBuildNext() throws {
        let game = game()
        // A building that a normal colony can build up fully
        let colony = FreeColTestCase.standardColony(game)
        let warehouse = Building(game: game, colony: colony, type: building("depot"))
        colony.addBuilding(warehouse)
        #expect(warehouse.canBuildNext)
        #expect(warehouse.upgrade() != nil)
        #expect(warehouse.canBuildNext)
        #expect(warehouse.upgrade() != nil)
        #expect(!warehouse.canBuildNext)
        #expect(warehouse.upgrade() == nil)
        #expect(!warehouse.canBuildNext)
    }

    @Test func stockadeRequiresMinimumPopulation() {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 2)
        #expect(colony.noBuildReason(stockadeType, nil) == .populationTooSmall)
        Unit(game: game, location: colony.tile, owner: colony.owner!, type: freeColonistType).setLocation(colony)
        #expect(colony.noBuildReason(stockadeType, nil) == .none)
    }

    @Test func fortRequiresMinimumPopulation() {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 2)
        #expect(colony.noBuildReason(fortType, nil) == .populationTooSmall)
        Unit(game: game, location: colony.tile, owner: colony.owner!, type: freeColonistType).setLocation(colony)
        colony.addBuilding(Building(game: game, colony: colony, type: stockadeType))
        #expect(colony.noBuildReason(fortType, nil) == .none)
    }

    @Test func fortressRequiresMinimumPopulation() {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 7)
        colony.addBuilding(Building(game: game, colony: colony, type: stockadeType))
        colony.addBuilding(Building(game: game, colony: colony, type: fortType))
        #expect(colony.noBuildReason(fortressType, nil) == .populationTooSmall)
        Unit(game: game, location: colony.tile, owner: colony.owner!, type: freeColonistType).setLocation(colony)
        #expect(colony.unitCount == 8)
        #expect(colony.noBuildReason(fortressType, nil) == .none)
    }

    @Test func initialColony() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game)
        // Built as a depot
        let warehouse = try #require(colony.building(building("warehouse")))
        #expect(warehouse.canBuildNext)
    }

    @Test func church() throws {
        let game = game()
        // A colony big enough for a cathedral, with enough liberty for
        // no production penalty.
        let colony = FreeColTestCase.standardColony(game, 10)
        while colony.productionBonus < 0 { colony.modifyLiberty(100) }
        let unit0 = colony.unitList[0], unit1 = colony.unitList[1], unit2 = colony.unitList[2]

        #expect(!chapelType.hasAbility(Ability.dressMissionary))
        #expect(!unit0.hasAbility(Ability.dressMissionary))
        #expect(!unit0.roleIsAvailable(missionaryRole))

        let church = try #require(colony.building(chapelType))
        #expect(!colony.hasAbility(Ability.dressMissionary))

        func check(_ name: String, _ base: Int, _ potential: Int, _ total: Int, _ unitType: UnitType?,
                   sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(church.baseProduction(unitType == nil ? nil : church.productionType, crossesType, unitType)
                    == base, "\(name) base cross production", sourceLocation: sourceLocation)
            #expect(church.potentialProduction(crossesType, unitType) == potential,
                    "\(name) potential cross production", sourceLocation: sourceLocation)
            #expect(church.totalProduction(of: crossesType) == total, "\(name) total cross production",
                    sourceLocation: sourceLocation)
        }
        func checkDress(sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(church.type!.hasAbility(Ability.dressMissionary), sourceLocation: sourceLocation)
            #expect(colony.hasAbility(Ability.dressMissionary), sourceLocation: sourceLocation)
            #expect(unit0.hasAbility(Ability.dressMissionary), sourceLocation: sourceLocation)
            #expect(unit0.roleIsAvailable(missionaryRole), sourceLocation: sourceLocation)
        }
        check("Chapel, no unit", 1, 1, 1, nil)

        church.upgrade()
        #expect(church.type?.id == "model.building.church")
        checkDress()
        check("Church, no unit", 2, 2, 2, nil)

        church.setWorkFor(unit0)
        check("Church, free colonist", 3, 3, 5, unit0.type)
        church.setWorkFor(unit1)
        check("Church, 2 x free colonist", 3, 3, 8, unit1.type)
        church.setWorkFor(unit2)
        check("Church, 3 x free colonist", 3, 3, 11, unit2.type)

        let smithy = try #require(colony.building(building("blacksmithHouse")))
        #expect(unit0.setLocation(smithy))
        #expect(unit1.setLocation(smithy))
        #expect(unit2.setLocation(smithy))
        unit0.setType(firebrandPreacherType)
        church.setWorkFor(unit0)
        check("Church, firebrand preacher", 3, 6, 8, unit0.type)

        unit0.setType(freeColonistType)
        #expect(unit0.setLocation(smithy))
        church.upgrade()
        #expect(church.type?.id == "model.building.cathedral")
        checkDress()
        check("Cathedral, no unit", 3, 3, 3, nil)

        church.setWorkFor(unit0)
        check("Cathedral, free colonist", 6, 6, 9, unit0.type)
        church.setWorkFor(unit1)
        check("Cathedral, 2 x free colonist", 6, 6, 15, unit1.type)
        church.setWorkFor(unit2)
        check("Cathedral, 3 x free colonist", 6, 6, 21, unit2.type)

        unit0.setLocation(smithy)
        unit1.setLocation(smithy)
        unit2.setLocation(smithy)
        unit0.setType(firebrandPreacherType)
        church.setWorkFor(unit0)
        check("Cathedral, firebrand preacher", 6, 12, 15, unit0.type)
    }

    @Test func canAddToBuilding() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 6)
        let tile = try #require(colony.tile)
        let units = colony.unitList

        // The standard colony tends to put units in the town hall
        for u in units where u.location is Building { u.setLocation(tile) }

        for building in colony.buildings {
            // The schoolhouse is special: see canAddToSchool
            if building.canTeach { continue }
            let maxUnits = building.unitCapacity
            #expect(building.unitCount == 0)
            for index in 0..<maxUnits {
                #expect(building.canAdd(units[index]), "unable to add unit \(index) to building type \(building.type!)")
                building.add(units[index])
            }
            #expect(!building.canAdd(units[maxUnits]),
                    "able to add unit \(maxUnits) to building type \(building.type!)")
            for _ in 0..<maxUnits { building.remove(building.unitList[0]) }
        }
    }

    /// Java warns that this makes assumptions about the schoolhouse
    /// that the rules could break.
    @Test func canAddToSchool() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 10)
        let units = colony.unitList
        let farmer = units[0], colonist = units[1], criminal = units[2], servant = units[3]
        let indian = units[4], distiller = units[5], elder = units[6], carpenter = units[7]
        farmer.setType(unitType("expertFarmer"))
        colonist.setType(freeColonistType)
        criminal.setType(pettyCriminalType)
        servant.setType(indenturedServantType)
        indian.setType(indianConvertType)
        distiller.setType(unitType("masterDistiller"))
        elder.setType(unitType("elderStatesman"))
        carpenter.setType(unitType("masterCarpenter"))

        #expect(colony.building(schoolType) == nil)
        colony.addBuilding(Building(game: game, colony: colony, type: schoolType))
        let school = try #require(colony.building(schoolType))

        // These can never teach
        for (unit, reason) in [(colonist, NoAddReason.minimumSkill), (criminal, .minimumSkill),
                               (servant, .minimumSkill), (indian, .minimumSkill),
                               (elder, .maximumSkill), (distiller, .maximumSkill)] {
            #expect(school.noAddReason(unit) == reason, "\(unit.type!)")
            #expect(!school.canAdd(unit), "able to add \(unit.type!) to Schoolhouse")
        }
        #expect(school.canAdd(farmer), "unable to add master farmer to Schoolhouse")
        farmer.setLocation(school)
        #expect(farmer.location === school)
        #expect(!school.canAdd(carpenter), "able to add master carpenter to Schoolhouse")

        school.upgrade()
        farmer.setLocation(colony.tile)
        for unit in [colonist, criminal, servant, indian, elder] {
            #expect(!school.canAdd(unit), "able to add \(unit.type!) to College")
        }
        #expect(school.canAdd(distiller), "unable to add master distiller to College")
        distiller.setLocation(school)
        #expect(school.canAdd(farmer), "unable to add master farmer to College")
        farmer.setLocation(school)
        #expect(!school.canAdd(carpenter), "able to add master carpenter to College")

        school.upgrade()
        #expect(school.type === building("university"))
        distiller.setLocation(colony.tile)
        farmer.setLocation(colony.tile)
        for unit in [colonist, criminal, servant, indian] {
            #expect(!school.canAdd(unit), "able to add \(unit.type!) to University")
        }
        #expect(school.canAdd(elder), "unable to add elder statesman to University")
        elder.setLocation(school)
        #expect(school.canAdd(distiller), "unable to add master distiller to University")
        distiller.setLocation(school)
        #expect(school.canAdd(farmer), "unable to add master farmer to University")
        farmer.setLocation(school)
        #expect(!school.canAdd(carpenter), "able to add master carpenter to University")
    }

    @Test(.disabled("Writing XML is not ported yet"))
    func serialize() {}

    @Test func stockade() throws {
        let game = game()
        let turn = game.turn
        let colony = FreeColTestCase.standardColony(game, 2)
        var modifiers = colony.modifiers(Modifier.defence)
        #expect(modifiers.count == 1)
        #expect(modifiers.first?.value == 50)
        #expect(modifiers.first?.type == .percentage)

        for (type, value) in [(stockadeType, Float(100)), (fortType, 150), (fortressType, 200)] {
            modifiers = type.modifiers(Modifier.defence)
            #expect(modifiers.count == 1, "\(type)")
            #expect(modifiers.first?.value == value, "\(type)")
            #expect(modifiers.first?.type == .percentage, "\(type)")
            // Java checks the stockade each time.
            #expect(stockadeType.apply(0, turn: turn, Modifier.minimumColonySize) == 0)
        }
    }

    @Test func cottonClothProduction() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 2)
        let colonist = colony.unitList[0], worker = colony.unitList[1]
        let weaver = try #require(colony.building(building("weaverHouse")))
        let plainsType = spec.getTileType("model.tile.plains")!

        #expect(colonist.location is ColonyTile)
        #expect(colonist.workTile?.type === plainsType)
        #expect(worker.location is ColonyTile)
        #expect(worker.workTile?.type === plainsType)

        #expect(weaver.add(worker))
        #expect(weaver.unitList.first === worker)

        colony.addGoods(cottonType, 2)
        colony.invalidateCache()
        let clothType = goods("cloth")
        #expect(colony.totalProduction(of: cottonType) == 2)
        #expect(weaver.totalProduction(of: clothType) == 3)
        #expect(colony.totalProduction(of: clothType) == 3)
        #expect(colony.netProduction(of: cottonType) == -1)
        #expect(colony.netProduction(of: clothType) == 3)

        colonist.changeWorkType(cottonType)
        colony.invalidateCache()
        #expect(colony.totalProduction(of: cottonType) == 4)
        colony.addGoods(cottonType, 4)
        #expect(colony.totalProduction(of: clothType) == 3)
        #expect(colony.netProduction(of: cottonType) == 1)
        #expect(colony.netProduction(of: clothType) == 3)
    }

    @Test func pasture() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 1)
        let country = try #require(colony.building(building("country")))
        #expect(country.productionType != nil)
        let unit = try #require(colony.firstUnit)
        #expect(unit.workType === grainType)
        let foodType = spec.primaryFoodType!

        func check(_ total: Int, _ maximum: Int, _ net: Int, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(country.totalProduction(of: horsesType) == total, sourceLocation: sourceLocation)
            #expect(country.maximumProduction(of: horsesType) == maximum, sourceLocation: sourceLocation)
            #expect(colony.netProduction(of: horsesType) == net, sourceLocation: sourceLocation)
        }
        // No horses yet
        #expect(colony.netProduction(of: foodType) == 6)
        check(0, 0, 0)

        colony.addGoods(horsesType, 50)
        colony.invalidateCache()
        check(2, 2, 2)

        colony.addGoods(horsesType, 1)
        colony.invalidateCache()
        check(3, 4, 3)

        country.upgrade()
        colony.removeGoods(horsesType)
        colony.addGoods(horsesType, 25)
        colony.invalidateCache()
        #expect(colony.goodsCount(horsesType) == 25)
        check(2, 2, 2)

        colony.addGoods(horsesType, 1)
        colony.invalidateCache()
        #expect(colony.goodsCount(horsesType) == 26)
        check(3, 4, 3)

        colony.addGoods(horsesType, 24)
        colony.invalidateCache()
        #expect(colony.goodsCount(horsesType) == 50)
        check(3, 4, 3)

        colony.addGoods(horsesType, 1)
        colony.invalidateCache()
        #expect(colony.goodsCount(horsesType) == 51)
        // No more than half the surplus production!
        #expect(country.totalProduction(of: horsesType) == 3)
        #expect(country.maximumProduction(of: horsesType) == 6)
        #expect(colony.netProduction(of: horsesType) == colony.netProduction(of: foodType),
                "Horse production should equal food surplus.")
    }

    @Test func townhallProduction() throws {
        let game = game()
        let turn = game.turn
        let colony = FreeColTestCase.standardColony(game, 6)
        let owner = try #require(colony.owner)
        let colonist = colony.unitList[0], statesman = colony.unitList[1]
        statesman.setType(unitType("elderStatesman"))

        let tile = try #require(colony.tile)
        let building = try #require(colony.building(townHallType))
        for u in building.unitList { u.setLocation(tile) }

        #expect(colony.modifiers("model.goods.bells").isEmpty, "No initial modifiers")
        #expect(building.totalProduction(of: bellsType) == 1, "Initial bell production")

        colonist.setLocation(building)
        // 3 from the colonist
        #expect(building.unitProduction(colonist, bellsType) == 3, "Production(Colonist)")
        // 3 (colonist) + 1 (unattended)
        #expect(building.totalProduction(of: bellsType) == 4, "Total production(Colonist)")

        // Add Jefferson.
        let jefferson = try #require(spec.getFoundingFather("model.foundingFather.thomasJefferson"))
        let modifiers = jefferson.modifiers("model.goods.bells")
        #expect(modifiers.count == 1, "Jefferson modifier size")
        let bellsModifier = try #require(modifiers.first)
        owner.addFather(jefferson)

        // Jefferson is a property of the player...
        #expect(owner.modifiers("model.goods.bells").contains { $0 === bellsModifier },
                "Jefferson should be present in player")
        #expect(owner.modifiers("model.goods.bells", for: townHallType, turn: turn).contains { $0 === bellsModifier },
                "Jefferson should be present in player in building scope")
        #expect(!owner.modifiers("model.goods.bells", for: freeColonistType, turn: turn)
                .contains { $0 === bellsModifier },
                "Jefferson should not be present in player in unit scope")
        // ...not the colony,
        #expect(!colony.modifiers("model.goods.bells").contains { $0 === bellsModifier },
                "Jefferson modifier should not be present in colony")
        // ...and the building modifiers do not have it.
        #expect(!building.modifiers("model.goods.bells").contains { $0 === bellsModifier },
                "Jefferson modifier should not be present in building modifiers")

        // 3 (colonist)
        #expect(building.unitProduction(colonist, bellsType) == 3, "Production(Colonist/Jefferson)")
        // 3 (colonist) + 1 + 50% (Jefferson) = 6
        #expect(building.totalProduction(of: bellsType) == 6, "Total production(Colonist/Jefferson)")

        // Add the statesman
        statesman.setLocation(building)
        // 3 * 2 (expert) = 6
        #expect(building.unitProduction(statesman, bellsType) == 6, "Production(Statesman/Jefferson)")
        // 3 + 6 + 1 + 50% (Jefferson) = 15
        #expect(building.totalProduction(of: bellsType) == 15, "Total production(Colonist/Statesman/Jefferson)")

        // Improve production
        colony.productionBonus = 2
        colony.invalidateCache()
        #expect(building.unitProduction(colonist, bellsType) == 5, "Production(Colonist/Jefferson/2)")
        #expect(building.unitProduction(statesman, bellsType) == 10, "Production(Statesman/Jefferson/2)")
        // 5 + 10 + 1 + 50% (Jefferson) = 24
        #expect(building.totalProduction(of: bellsType) == 24,
                "Total production(Colonist/Statesman/Jefferson/2)")

        // Add a newspaper
        colony.addBuilding(Building(game: game, colony: colony, type: self.building("newspaper")))
        colony.invalidateCache()
        #expect(building.unitProduction(colonist, bellsType) == 5, "Production(Colonist/Jefferson/2/Newspaper)")
        #expect(building.unitProduction(statesman, bellsType) == 10, "Production(Statesman/Jefferson/2/Newspaper)")
        // 5 + 10 + 1 + 50% (Jefferson) + 100% (Newspaper) = 48
        #expect(building.totalProduction(of: bellsType) == 48,
                "Total production(Colonist/Statesman/Jefferson/2/Newspaper)")
    }

    @Test func printingPressBonus() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 6)
        let unit = colony.unitList[0]
        let building = try #require(colony.building(townHallType))
        for u in building.unitList { u.setLocation(colony.tile) }

        #expect(building.totalProduction(of: bellsType) == 1, "Wrong initial bell production")
        colony.addBuilding(Building(game: game, colony: colony, type: self.building("printingPress")))
        #expect(building.totalProduction(of: bellsType) == 1, "Wrong bell production with printing press")
        unit.setLocation(building)
        // 1 initial, 3 from the colonist and 2 from the printing press
        #expect(building.totalProduction(of: bellsType) == 6, "Wrong final bell production")
    }

    @Test func newspaperBonus() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 6)
        let unit = colony.unitList[0]
        let building = try #require(colony.building(townHallType))
        FreeColTestCase.clearWorkLocation(building)

        #expect(building.totalProduction(of: bellsType) == 1, "Wrong initial bell production")
        colony.addBuilding(Building(game: game, colony: colony, type: self.building("newspaper")))
        colony.invalidateCache()
        #expect(building.totalProduction(of: bellsType) == 2, "Wrong bell production with newspaper")
        unit.setLocation(building)
        // 1 initial, 3 from the colonist and 4 from the newspaper
        #expect(building.totalProduction(of: bellsType) == 8, "Wrong final bell production")
    }

    @Test func unitProduction() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 4)
        let unit = colony.unitList[0]
        for building in colony.buildings {
            FreeColTestCase.clearWorkLocation(building)
            unit.setLocation(building)
            for output in building.outputs {
                let outputType = output.type!
                for type in spec.unitTypeList
                where building.type!.canAdd(type) && type.isAvailableTo([colony.owner]) {
                    unit.changeType(type)
                    let productivity = building.unitProduction(unit, outputType)
                    let expect = type === building.expertUnitType ? 6
                        : type === indenturedServantType ? 2
                        : type === indianConvertType ? 1
                        : type === pettyCriminalType ? 1
                        : output.amount
                    if expect != output.amount {
                        #expect(!type.modifiers(outputType.id).isEmpty, "Modifiers expected")
                    }
                    #expect(productivity == expect, "Wrong productivity for \(type) in \(building)")
                }
            }
        }
    }

    // Lumber and cross production data contributed by Lone_Wolf in
    // BR#2981.
    static let lumberProd = [
        [ // carpenterHouse
            [0, 0, 0, 1, 4], // -2
            [0, 0, 1, 2, 5], // -1
            [1, 1, 2, 3, 6], // 0
            [2, 2, 3, 4, 7], // +1
            [3, 3, 4, 5, 8], // +2
        ], [ // lumber mill
            [0, 0, 0, 2, 8], // -2
            [0, 0, 2, 4, 10], // -1
            [2, 2, 4, 6, 12], // 0
            [4, 4, 6, 8, 14], // +1
            [6, 6, 8, 10, 16], // +2
        ],
    ]

    @Test func lumberProduction() throws {
        try productionTest([building("carpenterHouse"), building("lumberMill")], Self.lumberProd)
    }

    // Cross production is very like lumber production, with the
    // unattended production added.
    static let crossProd = [
        [ // church
            [2, 2, 2, 3, 6], // -2
            [2, 2, 3, 4, 7], // -1
            [3, 3, 4, 5, 8], // 0
            [4, 4, 5, 6, 9], // +1
            [5, 5, 6, 7, 10], // +2
        ], [ // cathedral
            [3, 3, 3, 5, 11], // -2
            [3, 3, 5, 7, 13], // -1
            [5, 5, 7, 9, 15], // 0
            [7, 7, 9, 11, 17], // +1
            [9, 9, 11, 13, 19], // +2
        ],
    ]

    @Test func crossProduction() throws {
        try productionTest([building("church"), building("cathedral")], Self.crossProd)
    }

    // Factory production data contributed by Lone_Wolf in BR#2979.
    static let factoryProd = [
        [ // house
            [0, 0, 0, 1, 2], // -2
            [0, 0, 1, 2, 4], // -1
            [1, 1, 2, 3, 6], // 0
            [2, 2, 3, 4, 8], // 1
            [3, 3, 4, 5, 10], // 2
        ], [ // shop
            [0, 0, 2, 4, 8], // -2
            [1, 1, 3, 5, 10], // -1
            [2, 2, 4, 6, 12], // 0
            [3, 3, 5, 7, 14], // 1
            [4, 4, 6, 8, 16], // 2
        ], [ // factory
            [0, 0, 3, 6, 12], // -2
            [1, 1, 4, 7, 14], // -1
            [3, 3, 6, 9, 18], // 0
            [4, 4, 7, 10, 20], // 1
            [6, 6, 9, 12, 24], // 2
        ],
    ]

    /// Java tests the cloth buildings twice and leaves out the fur
    /// buildings, which it lists; that is kept.
    @Test func factoryProduction() throws {
        let cloth = ["weaverHouse", "weaverShop", "textileMill"]
        let sugar = ["distillerHouse", "rumDistillery", "rumFactory"]
        let tobacco = ["tobacconistHouse", "tobacconistShop", "cigarFactory"]
        let tools = ["blacksmithHouse", "blacksmithShop", "ironWorks"]
        let muskets = ["armory", "magazine", "arsenal"]
        for family in [cloth, cloth, sugar, tobacco, tools, muskets] {
            try productionTest(family.map(building), Self.factoryProd)
        }
    }

    /// The interaction between tools and muskets.
    @Test func toolsMusketProduction() throws {
        let game = game()
        let colony = FreeColTestCase.standardColony(game, 8)
        let tile = try #require(colony.tile)
        let units = colony.unitList
        #expect(units.count == 8)

        // Enough goods to get started, and enough bells and food made.
        colony.addGoods(bellsType, Colony.libertyPerRebel * 3)
        for i in 0..<4 { units[i].setLocation(tile) }
        #expect(colony.colonyTile(tile.neighbour(.n))!.setWorkFor(units[4]))
        #expect(colony.colonyTile(tile.neighbour(.e))!.setWorkFor(units[5]))
        #expect(colony.colonyTile(tile.neighbour(.s))!.setWorkFor(units[6]))
        #expect(colony.building(townHallType)!.setWorkFor(units[7]))

        let smithy = try #require(colony.building(building("blacksmithHouse")))
        #expect(!smithy.setWorkFor(units[0]))
        colony.addGoods(goods("ore"), 50) // ore makes the smithy viable
        #expect(smithy.setWorkFor(units[0]))
        #expect(smithy.setWorkFor(units[1]))

        let armory = Building(game: game, colony: colony, type: building("armory"))
        colony.addBuilding(armory)
        colony.invalidateCache()
        #expect(armory.setWorkFor(units[2]))
        #expect(armory.setWorkFor(units[3]))

        func check(_ amount: Int, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(units[0].workType === toolsType, sourceLocation: sourceLocation)
            #expect(units[1].workType === toolsType, sourceLocation: sourceLocation)
            #expect(units[2].workType === musketsType, sourceLocation: sourceLocation)
            #expect(units[3].workType === musketsType, sourceLocation: sourceLocation)
            #expect(smithy.totalProduction(of: toolsType) == amount, sourceLocation: sourceLocation)
            #expect(armory.totalProduction(of: musketsType) == amount, sourceLocation: sourceLocation)
        }
        check(6)

        // Upgrade the buildings
        smithy.upgrade()
        armory.upgrade()
        colony.invalidateCache()
        check(12)

        // Up to factory level.  (Java notes the arsenal once lost the
        // factory bonus, by bug report #3430371, since reverted.)
        colony.owner!.addFather(spec.getFoundingFather("model.foundingFather.adamSmith")!)
        smithy.upgrade()
        armory.upgrade()
        colony.invalidateCache()
        check(18)
    }
}

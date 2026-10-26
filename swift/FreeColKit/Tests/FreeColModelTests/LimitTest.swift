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

/// LimitTest.java.
@Suite(.serialized)
struct LimitTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    @Test func operand() {
        let carpenter = spec.getUnitType("model.unit.masterCarpenter")!
        let frigate = spec.getUnitType("model.unit.frigate")!
        let operand = Operand()
        #expect(operand.operandType == .none)
        #expect(operand.scopeLevel == .none)
        operand.type = "model.unit.frigate"
        #expect(operand.appliesTo(frigate))
        #expect(!operand.appliesTo(carpenter))
    }

    @Test func wagonTrainLimit() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let colony = FreeColTestCase.standardColony(game, 3)
        colony.addBuilding(Building(game: game, colony: colony, type: spec.getBuildingType("model.building.armory")!))

        let wagonTrain = spec.getUnitType("model.unit.wagonTrain")!
        let artillery = spec.getUnitType("model.unit.artillery")!
        let wagonTrainLimit = try #require(wagonTrain.limits.first)

        #expect(colony.canBuild(artillery))
        #expect(!wagonTrainLimit.leftHandSide.appliesTo(artillery))
        #expect(wagonTrainLimit.evaluate(colony))
        #expect(colony.canBuild(wagonTrain))

        _ = Unit(game: game, location: colony.tile, owner: dutch, type: wagonTrain)
        #expect(colony.noBuildReason(wagonTrain, nil) == .limitExceeded)
        #expect(!wagonTrainLimit.evaluate(colony))
        #expect(!colony.canBuild(wagonTrain))
        #expect(colony.canBuild(artillery))
    }

    @Test func independenceLimits() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let colony = FreeColTestCase.standardColony(game, 3)

        let event = try #require(spec.getEvent("model.event.declareIndependence"))
        #expect(!event.limitValues.isEmpty)
        #expect(spec.option(GameOptions.lastColonialYear, as: IntegerOption.self) != nil)

        let rebelLimit = try #require(event.limit("model.limit.independence.rebels"))
        let colonyLimit = try #require(event.limit("model.limit.independence.coastalColonies"))
        let yearLimit = try #require(event.limit("model.limit.independence.year"))

        #expect(rebelLimit.operator == .ge)
        #expect(rebelLimit.leftHandSide.operandType == .none)
        #expect(rebelLimit.leftHandSide.scopeLevel == .player)
        #expect(rebelLimit.leftHandSide.value(for: dutch) == 0)
        #expect(rebelLimit.rightHandSide.value(for: dutch) == 50)
        #expect(!rebelLimit.evaluate(dutch))

        #expect(colonyLimit.operator == .ge)
        #expect(colonyLimit.leftHandSide.operandType == .settlements)
        #expect(colonyLimit.leftHandSide.scopeLevel == .player)
        #expect(colonyLimit.leftHandSide.methodName == "isConnectedPort")
        #expect(!colony.isConnectedPort)
        #expect(colonyLimit.leftHandSide.value(for: dutch) == 0)
        #expect(colonyLimit.rightHandSide.value(for: dutch) == 1)
        #expect(!colonyLimit.evaluate(dutch))

        #expect(yearLimit.operator == .le)
        #expect(yearLimit.leftHandSide.operandType == .year)
        #expect(yearLimit.rightHandSide.operandType == .option)
        #expect(yearLimit.rightHandSide.type == GameOptions.lastColonialYear)
        #expect(yearLimit.leftHandSide.value(for: dutch) == 1492)
        #expect(yearLimit.rightHandSide.value(for: dutch) == 1800)
        #expect(yearLimit.evaluate(dutch))

        colony.modifyLiberty(10000)
        colony.updateSoL()
        #expect(rebelLimit.evaluate(dutch))

        let tile = try #require(colony.tile?.neighbour(.n))
        tile.type = spec.getTileType("model.tile.ocean")
        tile.highSeasCount = 5
        tile.setExplored(dutch, true)
        #expect(tile.isExploredBy(dutch))
        #expect(tile.isHighSeasConnected)
        #expect(!tile.isLand)
        #expect(colony.isConnectedPort)
        #expect(colonyLimit.leftHandSide.appliesTo(colony))
        #expect(colonyLimit.evaluate(dutch))

        // Set the minimum first or the value will not stick!
        spec.setIntegerMinimum(GameOptions.lastColonialYear, 1300)
        spec.setInteger(GameOptions.lastColonialYear, 1300)
        #expect(!yearLimit.evaluate(dutch))
    }

    @Test func successionLimits() throws {
        let game = FreeColTestCase.standardGame(spec)
        game.changeMap(FreeColTestCase.testMap(game))
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let colony = FreeColTestCase.standardColony(game, 3)

        let event = try #require(spec.getEvent("model.event.spanishSuccession"))
        #expect(!event.limitValues.isEmpty)

        let weakestPlayerLimit = try #require(event.limit("model.limit.spanishSuccession.weakestPlayer"))
        let strongestPlayerLimit = try #require(event.limit("model.limit.spanishSuccession.strongestPlayer"))
        let yearLimit = try #require(event.limit("model.limit.spanishSuccession.year"))

        #expect(strongestPlayerLimit.operator == .gt)
        #expect(strongestPlayerLimit.leftHandSide.operandType == .none)
        #expect(strongestPlayerLimit.leftHandSide.scopeLevel == .player)
        #expect(strongestPlayerLimit.leftHandSide.value(for: dutch) == 0)
        #expect(strongestPlayerLimit.rightHandSide.value(for: dutch) == 50)
        #expect(!strongestPlayerLimit.evaluate(dutch))

        #expect(weakestPlayerLimit.operator == .lt)
        #expect(weakestPlayerLimit.leftHandSide.operandType == .none)
        #expect(weakestPlayerLimit.leftHandSide.scopeLevel == .player)
        #expect(weakestPlayerLimit.leftHandSide.value(for: dutch) == 0)
        #expect(weakestPlayerLimit.rightHandSide.value(for: dutch) == 50)
        #expect(weakestPlayerLimit.evaluate(dutch))

        #expect(yearLimit.operator == .ge)
        #expect(yearLimit.leftHandSide.operandType == .year)
        #expect(yearLimit.leftHandSide.scopeLevel == .game)
        #expect(yearLimit.leftHandSide.value(in: game) == 1492)
        #expect(yearLimit.rightHandSide.value == 1600)
        #expect(!yearLimit.evaluate(game))

        colony.modifyLiberty(10000)
        colony.updateSoL()
        #expect(strongestPlayerLimit.evaluate(dutch))
        #expect(!weakestPlayerLimit.evaluate(dutch))
    }
}

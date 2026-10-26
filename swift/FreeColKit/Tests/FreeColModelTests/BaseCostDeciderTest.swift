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

/// BaseCostDeciderTest.java.
@Suite(.serialized)
struct BaseCostDeciderTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    var tradeGoodsType: GoodsType { spec.getGoodsType("model.goods.tradeGoods")! }
    var plainsType: TileType { spec.getTileType("model.tile.plains")! }
    var colonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }
    var galleonType: UnitType { spec.getUnitType("model.unit.galleon")! }
    var pioneerType: UnitType { spec.getUnitType("model.unit.hardyPioneer")! }

    let game: Game

    init() {
        game = FreeColTestCase.standardGame(Self.spec)
    }

    var french: Player { game.player(byNationId: "model.nation.french")! }

    /// The cost of a plains to plains move.
    @Test func getCostLandLand() throws {
        let map = FreeColTestCase.testMap(game, plainsType)
        game.changeMap(map)
        let decider = CostDeciders.avoidSettlements()
        let start = try #require(map.tile(5, 5))
        let unit = Unit(game: game, location: start, owner: french, type: pioneerType)
        for dir in Direction.allCases {
            #expect(start.neighbour(dir) != nil)
            let cost = decider.cost(unit, start, map.tile(5, 6), 100)
            #expect(cost == plainsType.basicMoveCost)
        }
    }

    /// The moves left and new turns after a move.
    @Test func getRemainingMovesAndNewTurn() {
        let map = FreeColTestCase.testMap(game, plainsType)
        game.changeMap(map)
        let decider = CostDeciders.avoidSettlements()
        let unit = Unit(game: game, location: map.tile(1, 1), owner: french, type: pioneerType)
        let cost = decider.cost(unit, map.tile(1, 1), map.tile(2, 2), 4)
        #expect(cost == plainsType.basicMoveCost)
        #expect(decider.movesLeft == 4 - plainsType.basicMoveCost)
        #expect(decider.newTurns == 0)
    }

    /// A land unit can not move to an ocean tile.
    @Test func invalidMoveOfLandUnitToAnOceanTile() throws {
        let map = FreeColTestCase.coastTestMap(game, plainsType)
        game.changeMap(map)
        let unitTile = try #require(map.tile(9, 9))
        #expect(unitTile.isLand, "Unit tile should be land")
        let unit = Unit(game: game, location: unitTile, owner: french, type: pioneerType)
        let seaTile = try #require(map.tile(10, 9))
        #expect(!seaTile.isLand, "Tile should be ocean")

        let cost = CostDeciders.avoidSettlements().cost(unit, unitTile, seaTile, 4)
        #expect(cost == CostDeciderConstants.illegalMove, "Move should be invalid")
    }

    /// A naval unit can not move to a land tile without a settlement.
    @Test func invalidMoveOfNavalUnitToALandTile() throws {
        let map = FreeColTestCase.coastTestMap(game, plainsType)
        game.changeMap(map)
        let unitTile = try #require(map.tile(10, 9))
        #expect(!unitTile.isLand, "Unit tile should be ocean")
        let unit = Unit(game: game, location: unitTile, owner: french, type: galleonType)
        let landTile = try #require(map.tile(9, 9))
        #expect(landTile.isLand, "Tile should be land")

        let cost = CostDeciders.avoidSettlements().cost(unit, unitTile, landTile, 4)
        #expect(cost == CostDeciderConstants.illegalMove, "Move should be invalid")
    }

    /// A unit can not move through a tile with a settlement.
    @Test func invalidMoveThroughTileWithSettlement() throws {
        let map = FreeColTestCase.testMap(game, plainsType)
        game.changeMap(map)
        let settlementTile = try #require(map.tile(2, 1))
        let settlement = IndianSettlementBuilder(game).settlementTile(settlementTile).build()
        settlementTile.settlement = settlement
        settlementTile.changeOwningSettlement(settlement)

        let unitTile = try #require(map.tile(1, 1))
        let unit = Unit(game: game, location: unitTile, owner: french, type: pioneerType)
        // The unit is going somewhere else.
        unit.destination = map.tile(3, 1)

        let cost = CostDeciders.avoidSettlements().cost(unit, unitTile, settlementTile, 4)
        #expect(cost == CostDeciderConstants.illegalMove, "Move should be invalid")
    }

    /// A naval unit moving to a tile with a settlement.
    @Test func navalUnitMoveToTileWithSettlement() throws {
        let map = FreeColTestCase.coastTestMap(game, plainsType)
        game.changeMap(map)
        let unitTile = try #require(map.tile(10, 9))
        #expect(!unitTile.isLand, "Unit tile should be ocean")
        let galleon = Unit(game: game, location: unitTile, owner: french, type: galleonType)
        let settlementTile = try #require(map.tile(9, 9))
        #expect(settlementTile.isLand, "Tile should be land")
        let settlement = IndianSettlementBuilder(game).settlementTile(settlementTile).build()

        // The galleon is trying to go to the settlement.
        galleon.destination = settlementTile

        let base = CostDeciders.avoidIllegal()
        var cost = base.cost(galleon, unitTile, settlementTile, 4)
        #expect(cost == CostDeciderConstants.illegalMove, "Move should be invalid, no contact or goods to trade")

        // Add contact, but disallow empty traders
        Player.makeContact(galleon.owner!, settlement.owner!)
        _ = settlement.setContacted(galleon.owner!)
        spec.setBoolean(GameOptions.emptyTraders, false)
        cost = base.cost(galleon, unitTile, settlementTile, 4)
        #expect(cost == CostDeciderConstants.illegalMove, "Move should be invalid, no goods to trade")

        // Empty traders
        spec.setBoolean(GameOptions.emptyTraders, true)
        cost = base.cost(galleon, unitTile, settlementTile, 4)
        #expect(cost != CostDeciderConstants.illegalMove, "Move should be valid, no goods to trade")
        spec.setBoolean(GameOptions.emptyTraders, false)

        // Add goods to trade
        galleon.add(Goods(game: game, location: nil, type: tradeGoodsType, amount: 50))
        cost = base.cost(galleon, unitTile, settlementTile, 4)
        #expect(cost != CostDeciderConstants.illegalMove, "Move should be valid, has contact and goods to trade")
        #expect(base.movesLeft == 0 && base.newTurns == 0, "Move should consume whole turn")

        // A colonist on the galleon
        let colonist = Unit(game: game, location: galleon, owner: french, type: colonistType)
        cost = base.cost(colonist, unitTile, settlementTile, 4)
        if spec.getBoolean(GameOptions.amphibiousMoves) {
            #expect(cost != CostDeciderConstants.illegalMove, "Move valid, direct from carrier to settlement")
        } else {
            #expect(cost == CostDeciderConstants.illegalMove, "Move invalid, direct from carrier to settlement")
        }
        #expect(colonist.findPath(unitTile, settlementTile, galleon, base) != nil,
                "Path should be valid from carrier to settlement")

        // Set the players at war
        let indianPlayer = settlement.owner!
        indianPlayer.setStance(galleon.owner!, .war)
        galleon.owner!.setStance(indianPlayer, .war)
        cost = base.cost(galleon, unitTile, settlementTile, 4)
        #expect(cost != CostDeciderConstants.illegalMove, "Move should be valid, war should not block gifts")
    }
}

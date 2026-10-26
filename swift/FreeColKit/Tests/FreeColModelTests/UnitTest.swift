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

/// UnitTest.java.
@Suite(.serialized)
struct UnitTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func unitType(_ id: String) -> UnitType { spec.getUnitType("model.unit." + id)! }
    func role(_ id: String) -> Role { spec.getRole("model.role." + id)! }
    var plains: TileType { spec.getTileType("model.tile.plains")! }
    var foodType: GoodsType { spec.primaryFoodType! }
    var colonistType: UnitType { unitType("freeColonist") }
    var braveType: UnitType { unitType("brave") }

    func game(_ tileType: TileType? = nil, explored: Bool = false) -> (Game, Map) {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, tileType, explored: explored)
        game.changeMap(map)
        return (game, map)
    }

    @Test func isColonist() throws {
        let (game, map) = game(plains, explored: true)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let sioux = try #require(game.player(byNationId: "model.nation.sioux"))
        let tile1 = map.tile(6, 8), tile2 = map.tile(6, 9)

        #expect(!Unit(game: game, location: tile1, owner: dutch, type: unitType("merchantman")).isColonist,
                "Merchantman is not a colonist")
        #expect(Unit(game: game, location: tile1, owner: dutch, type: unitType("veteranSoldier")).isColonist,
                "A soldier is a colonist")
        #expect(!Unit(game: game, location: tile2, owner: sioux, type: braveType).isColonist,
                "A brave is not a colonist")
    }

    @Test func canAdd() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let galleon = Unit(game: game, location: nil, owner: dutch, type: unitType("galleon"))
        let caravel = Unit(game: game, location: nil, owner: dutch, type: unitType("caravel"))
        let colonist = Unit(game: game, location: nil, owner: dutch, type: colonistType)
        let wagonTrain = Unit(game: game, location: nil, owner: dutch, type: unitType("wagonTrain"))
        let treasureTrain = Unit(game: game, location: nil, owner: dutch, type: unitType("treasureTrain"))

        // The standard rules
        #expect(galleon.canAdd(colonist))
        #expect(galleon.canAdd(treasureTrain))
        #expect(!galleon.canAdd(wagonTrain))
        #expect(!galleon.canAdd(caravel))
        #expect(!galleon.canAdd(galleon))
        #expect(caravel.canAdd(colonist))
        #expect(!caravel.canAdd(wagonTrain))
        #expect(!caravel.canAdd(treasureTrain))
        #expect(!caravel.canAdd(caravel))
        #expect(!caravel.canAdd(galleon))

        // Save the values to restore after the test.  (Java saves the
        // cargo capacity for all three, as here.)
        let wagonTrainOldSpace = wagonTrain.cargoCapacity
        let wagonTrainOldSpaceTaken = wagonTrain.cargoCapacity
        let caravelOldSpaceTaken = caravel.cargoCapacity

        // Other possible rules
        wagonTrain.type!.space = 1
        wagonTrain.type!.spaceTaken = 2
        caravel.type!.spaceTaken = 1

        #expect(galleon.canAdd(wagonTrain))
        #expect(caravel.canAdd(wagonTrain))
        // This may seem strange, but ships do carry smaller boats.
        #expect(galleon.canAdd(caravel))
        #expect(!caravel.canAdd(caravel))

        wagonTrain.type!.space = wagonTrainOldSpace
        wagonTrain.type!.spaceTaken = wagonTrainOldSpaceTaken
        caravel.type!.spaceTaken = caravelOldSpaceTaken
    }

    @Test func failedAddGoods() throws {
        let (game, _) = game()
        let colony = FreeColTestCase.standardColony(game)
        let foodInColony = 300
        colony.addGoods(foodType, foodInColony)
        #expect(colony.goodsCount(foodType) == foodInColony, "Setup error, colony does goods quantity wrong")

        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let wagonTrain = Unit(game: game, location: colony.tile, owner: dutch, type: unitType("wagonTrain"))
        #expect(wagonTrain.goodsSpaceTaken == 0, "Setup error, unit should not carry anything")
        #expect(wagonTrain.movesLeft == wagonTrain.initialMovesLeft, "Setup error, unit has wrong initial moves")

        let tooManyGoods = colony.goodsCount(foodType)
        #expect(!wagonTrain.add(Goods(game: game, location: nil, type: foodType, amount: tooManyGoods)),
                "Can not add too many goods")
        #expect(wagonTrain.goodsSpaceTaken == 0, "Unit should not carry anything")
        #expect(wagonTrain.movesLeft == wagonTrain.initialMovesLeft, "Unit moves should not have been modified")
    }

    @Test func missionary() throws {
        let (game, map) = game(plains, explored: true)
        let sioux = try #require(game.player(byNationId: "model.nation.sioux"))
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let tile = try #require(map.tile(6, 9))

        let colony = FreeColTestCase.standardColony(game, 3)
        try #require(colony.building(spec.getBuildingType("model.building.chapel")!)).upgrade()
        let jesuit = Unit(game: game, location: tile, owner: dutch, type: unitType("jesuitMissionary"))
        let colonist = Unit(game: game, location: colony, owner: dutch, type: colonistType)

        // The abilities
        #expect(!colonist.hasAbility(Ability.establishMission))
        colonist.setRole(role("missionary"))
        #expect(colonist.hasAbility(Ability.establishMission))
        #expect(jesuit.role === role("missionary"))
        #expect(jesuit.hasAbility(Ability.establishMission))

        // The mission
        let s = IndianSettlementBuilder(game).player(sioux).settlementTile(tile).capital(true).build()
        _ = s.setContacted(dutch)
        s.missionary = jesuit
        #expect(s.hasMissionary, "No missionary set")
        #expect(s.missionary === jesuit, "Wrong missionary set")
        s.missionary = nil
        #expect(!s.hasMissionary, "Missionary not removed")
    }

    @Test func getLineOfSight() throws {
        let (game, map) = game(plains, explored: true)
        let player = try #require(game.player(byNationId: "model.nation.dutch"))
        let tile = map.tile(6, 9)
        let frigate = Unit(game: game, location: tile, owner: player, type: unitType("frigate"))
        #expect(frigate.lineOfSight == 2)
        #expect(frigate.hasAbility(Ability.navalUnit))

        let revenger = Unit(game: game, location: tile, owner: player, type: unitType("revenger"))
        #expect(revenger.lineOfSight == 3)

        let colonist = Unit(game: game, location: tile, owner: player, type: colonistType)
        #expect(colonist.lineOfSight == 1)
        #expect(colonist.hasAbility(Ability.canBeEquipped))
        colonist.changeRole(role("scout"), 1)
        #expect(colonist.lineOfSight == 2)

        // With Hernando De Soto, land units see further.
        player.addFather(spec.getFoundingFather("model.foundingFather.hernandoDeSoto")!)
        #expect(frigate.lineOfSight == 2) // no increase
        #expect(revenger.lineOfSight == 4) // +1 bonus
        #expect(colonist.lineOfSight == 3) // +1 bonus
    }

    @Test func unitCanBuildColony() throws {
        let (game, map) = game(plains, explored: true)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let sioux = try #require(game.player(byNationId: "model.nation.sioux"))
        let tile1 = map.tile(10, 4)
        for (id, can) in [("expertFarmer", true), ("artillery", false), ("galleon", false),
                          ("treasureTrain", false), ("wagonTrain", false), ("indianConvert", false)] {
            #expect(Unit(game: game, location: tile1, owner: dutch, type: unitType(id)).canBuildColony == can, "\(id)")
        }
        #expect(Unit(game: game, location: tile1, owner: sioux, type: braveType).canBuildColony)
    }

    @Test func indianDies() throws {
        let (game, _) = game()
        let indianPlayer = try #require(game.player(byNationId: "model.nation.sioux"))
        let camp = IndianSettlementBuilder(game).player(indianPlayer).build()
        #expect(camp.owner === indianPlayer, "Indian player owns the camp")

        let brave = Unit(game: game, location: camp, owner: indianPlayer, type: braveType)
        camp.addOwnedUnit(brave)
        #expect(camp.unitCount == 2, "Brave should have been added to camp")
        #expect(indianPlayer.hasUnit(brave), "Brave should be on player unit list")

        // The unit dies
        brave.dispose()
        #expect(brave.isDisposed, "Brave was not disposed properly")
        #expect(camp.unitCount == 1, "Brave was not removed from camp")
        #expect(!indianPlayer.hasUnit(brave), "Brave was not removed from player unit list")
    }

    @Test func unitAvailability() throws {
        let game = FreeColTestCase.standardGame(spec)
        let indian = try #require(game.player(byNationId: "model.nation.sioux"))
        let european = try #require(game.player(byNationId: "model.nation.dutch"))
        let king = try #require(game.player(byNationId: "model.nation.dutchREF"))
        func available(_ id: String) -> [Bool] {
            [king, indian, european].map { unitType(id).isAvailableTo([$0]) }
        }
        #expect(available("kingsRegular") == [true, false, false])
        #expect(available("colonialRegular") == [false, false, false])
        #expect(available("brave") == [false, true, false])
        #expect(available("undead") == [false, false, false])

        european.addAbility(Ability(Ability.independenceDeclared))
        #expect(unitType("colonialRegular").isAvailableTo([european]))
    }

    @Test func unitLocationAfterBuildingColony() throws {
        let (game, map) = game()
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let colonyTile = try #require(map.tile(6, 8))
        let soldier = Unit(game: game, location: colonyTile, owner: dutch, type: unitType("veteranSoldier"))
        #expect(soldier.location === colonyTile, "Soldier location should be the colony tile")
        #expect(soldier.tile === colonyTile, "Soldier tile should be the colony tile")
        #expect(colonyTile.unitList.contains { $0 === soldier }, "Unit not found in tile")

        let colony = Colony(game: game, owner: dutch, name: "New Amsterdam", tile: colonyTile)
        dutch.addSettlement(colony)
        FreeColTestCase.nonServerBuildColony(soldier, colony)

        #expect(soldier.isInColony, "Soldier should be inside the colony")
        #expect(soldier.tile === colonyTile, "Soldier tile should be the colony tile")
        #expect(!colonyTile.unitList.contains { $0 === soldier }, "Unit building colony still in tile")
        #expect(colony.currentWorkLocations.contains { $0.contains(soldier) },
                "Soldier should be in a work location in the colony")
        let wl = try #require(soldier.workLocation, "Soldier should be in a work location in the colony")
        #expect(colony.colonyTile(colonyTile) !== wl, "Soldier should not be working in central tile")
    }

    @Test func unitLosesExperienceWithRoleChange() throws {
        let (game, map) = game()
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let colonist = Unit(game: game, location: map.tile(6, 8), owner: dutch, type: colonistType)
        colonist.modifyExperience(10)
        #expect(colonist.role === spec.defaultRole)
        #expect(colonist.experience > 0, "Colonist should some initial experience")

        colonist.changeRole(role("soldier"), 1)
        #expect(colonist.experience == 0, "Colonist should have lost all experience")

        colonist.modifyExperience(10)
        colonist.changeRole(role("dragoon"), 1)
        #expect(colonist.experience > 0, "Colonist should not have lost experience, compatible role")
    }

    @Test func ownerChange() throws {
        let (game, map) = game()
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let french = try #require(game.player(byNationId: "model.nation.french"))
        let colonist = Unit(game: game, location: map.tile(6, 8), owner: dutch, type: colonistType)
        #expect(colonist.owner === dutch, "Colonist should be dutch")
        #expect(dutch.unitCount == 1, "Dutch player should have 1 unit")
        #expect(french.unitCount == 0, "French player should have no units")

        colonist.changeOwner(french)
        #expect(colonist.owner === french, "Colonist should be french")
        #expect(dutch.unitCount == 0, "Dutch player should have no units")
        #expect(french.unitCount == 1, "French player should have 1 unit")
    }

    @Test func carrierOwnerChange() throws {
        let (game, map) = game(spec.getTileType("model.tile.ocean")!)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let french = try #require(game.player(byNationId: "model.nation.french"))
        let galleon = Unit(game: game, location: map.tile(6, 8), owner: dutch, type: unitType("galleon"))
        #expect(galleon.unitSpaceTaken == 0, "Galleon should be empty")
        #expect(galleon.canCarryUnits, "Galleon should be able to carry units")

        let colonist = Unit(game: game, location: galleon, owner: dutch, type: colonistType)
        #expect(colonist.location === galleon, "Colonist should be aboard the galleon")
        #expect(galleon.unitSpaceTaken == 1, "Galleon is carrying wrong number of units")
        #expect(galleon.owner === dutch)
        #expect(colonist.owner === dutch)
        #expect(dutch.unitCount == 2, "Dutch player should have 2 units")
        #expect(french.unitCount == 0, "French player should have no units")

        galleon.changeOwner(french)
        #expect(galleon.owner === french, "Galleon should be french")
        #expect(colonist.owner === french, "Colonist should be french")
        #expect(dutch.unitCount == 0, "Dutch player should have no units")
        #expect(french.unitCount == 2, "French player should have 2 units")
    }

    @Test func getMovesAsString() throws {
        let (game, _) = game()
        let colony = FreeColTestCase.standardColony(game, 1)
        let unit = try #require(colony.unitList.first)
        let initial = "/\(unit.initialMovesLeft / 3)"
        let expected = ["0", "(1/3) ", "(2/3) ", "1", "1(1/3) ", "1(2/3) ",
                        "2", "2(1/3) ", "2(2/3) ", "3", "3(1/3) ", "3(2/3) "]
        for (index, e) in expected.enumerated() {
            unit.setMovesLeft(index)
            #expect(unit.movesAsString == e + initial)
        }
    }

    @Test func treasureTransportFee() throws {
        let game = FreeColTestCase.standardGame(spec)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let treasureTrain = Unit(game: game, location: nil, owner: dutch, type: unitType("treasureTrain"))
        treasureTrain.treasureAmount = 6000

        let levels = ["veryEasy", "easy", "medium", "hard", "veryHard"]
        for (level, percent) in zip(levels, [50, 55, 60, 65, 70]) {
            spec.applyDifficultyLevel("model.difficulty." + level)
            #expect(treasureTrain.transportFee == percent * 60, "\(level)")
        }

        dutch.addFather(spec.getFoundingFather("model.foundingFather.hernanCortes")!)
        for level in levels {
            spec.applyDifficultyLevel("model.difficulty." + level)
            #expect(treasureTrain.transportFee == 0, "\(level)")
        }
        spec.applyDifficultyLevel("model.difficulty.medium")
    }

    @Test(.disabled("Unit.copy is not ported yet (it copies by writing XML)"))
    func copy() {}

    @Test func defaultRole() {
        for type in spec.unitTypeList {
            #expect(type.defaultRole != nil, "\(type)")
        }
    }

    @Test func attrition() {
        for type in spec.unitTypeList {
            #expect(type.hasMaximumAttrition == (type === unitType("indianConvert")), "\(type)")
        }
    }
}

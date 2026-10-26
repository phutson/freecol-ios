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

/// TileTest.java.
@Suite(.serialized)
struct TileTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func goods(_ id: String) -> GoodsType { spec.getGoodsType("model.goods." + id)! }
    func resource(_ id: String) -> ResourceType { spec.getResourceType("model.resource." + id)! }
    func improvement(_ id: String) -> TileImprovementType { spec.getTileImprovementType("model.improvement." + id)! }
    func tileType(_ id: String) -> TileType { spec.getTileType("model.tile." + id)! }

    var townHallType: BuildingType { spec.getBuildingType("model.building.townHall")! }
    var cotton: GoodsType { goods("cotton") }
    var food: GoodsType { spec.primaryFoodType! }
    var furs: GoodsType { goods("furs") }
    var grain: GoodsType { goods("grain") }
    var lumber: GoodsType { goods("lumber") }
    var ore: GoodsType { goods("ore") }
    var silver: GoodsType { goods("silver") }
    var sugar: GoodsType { goods("sugar") }
    var clearForest: TileImprovementType { improvement("clearForest") }
    var plow: TileImprovementType { improvement("plow") }
    var river: TileImprovementType { improvement("river") }
    var road: TileImprovementType { improvement("road") }
    var coniferForest: TileType { tileType("coniferForest") }
    var desertForest: TileType { tileType("scrubForest") }
    var hills: TileType { tileType("hills") }
    var marsh: TileType { tileType("marsh") }
    var mountains: TileType { tileType("mountains") }
    var plains: TileType { tileType("plains") }
    var plainsForest: TileType { tileType("mixedForest") }
    var savannah: TileType { tileType("savannah") }
    var tundra: TileType { tileType("tundra") }
    var tundraForest: TileType { tileType("borealForest") }
    var colonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }
    var expertFarmerType: UnitType { spec.getUnitType("model.unit.expertFarmer")! }
    var expertLumberJack: UnitType { spec.getUnitType("model.unit.expertLumberJack")! }

    func game(_ type: TileType? = nil, explored: Bool = false) -> (Game, Map) {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, type, explored: explored)
        game.changeMap(map)
        return (game, map)
    }

    @Test func getWorkAmount() {
        let game = FreeColTestCase.standardGame(spec)
        #expect(plow.addWorkTurns == 2)
        #expect(road.addWorkTurns == 0)
        #expect(clearForest.addWorkTurns == 2)

        // Java skips the arctic ("FIXME: fix test").
        for (id, plowTurns, roadTurns) in [("plains", 5, 3), ("desert", 5, 3), ("grassland", 5, 3),
                                           ("prairie", 5, 3), ("tundra", 6, 4), ("savannah", 5, 3),
                                           ("marsh", 7, 5), ("swamp", 9, 7)] {
            let tile = Tile(game: game, type: tileType(id), x: 0, y: 0)
            #expect(tile.isImprovementTypeAllowed(plow), "\(id)")
            #expect(tile.isImprovementTypeAllowed(road), "\(id)")
            #expect(!tile.isImprovementTypeAllowed(clearForest), "\(id)")
            #expect(tile.workAmount(plow) == plowTurns, "\(id)")
            #expect(tile.workAmount(road) == roadTurns, "\(id)")
        }

        // The forests
        for (id, clearTurns, roadTurns) in [("borealForest", 6, 4), ("coniferForest", 6, 4),
                                            ("scrubForest", 6, 4), ("broadleafForest", 6, 4),
                                            ("tropicalForest", 8, 6), ("wetlandForest", 8, 6),
                                            ("rainForest", 9, 7), ("mixedForest", 6, 4)] {
            let tile = Tile(game: game, type: tileType(id), x: 0, y: 0)
            #expect(!tile.isImprovementTypeAllowed(plow), "\(id)")
            #expect(tile.isImprovementTypeAllowed(road), "\(id)")
            #expect(tile.isImprovementTypeAllowed(clearForest), "\(id)")
            #expect(tile.workAmount(clearForest) == clearTurns, "\(id)")
            #expect(tile.workAmount(road) == roadTurns, "\(id)")
        }
    }

    @Test func tileTypeChangeProduction() {
        for tileType in spec.tileTypeList where tileType.isForested {
            let production = clearForest.production(from: tileType)
            #expect(production != nil, "\(tileType.id ?? "")")
            #expect(production?.amount == (tileType === desertForest ? 10 : 20), "\(tileType.id ?? "")")
        }
    }

    @Test func primarySecondaryGoods() throws {
        let (game, _) = game(explored: true)
        let colony = FreeColTestCase.standardColony(game)
        let tile = try #require(colony.tile)
        let center = try #require(colony.colonyTile(tile))

        func check(_ primary: GoodsType, _ primaryAmount: Int, _ secondary: GoodsType, _ secondaryAmount: Int,
                   sourceLocation: SourceLocation = #_sourceLocation) {
            let production = center.production
            #expect(production.count == 2, sourceLocation: sourceLocation)
            guard production.count == 2 else { return }
            #expect(production[0].type === primary, sourceLocation: sourceLocation)
            #expect(production[0].amount == primaryAmount, sourceLocation: sourceLocation)
            #expect(production[1].type === secondary, sourceLocation: sourceLocation)
            #expect(production[1].amount == secondaryAmount, sourceLocation: sourceLocation)
        }
        check(grain, 3, cotton, 2)

        let ti = TileImprovement(game: game, tile: tile, type: plow, style: nil)
        ti.turnsToComplete = 0
        tile.add(ti)
        colony.invalidateCache()
        check(grain, 4, cotton, 2)

        tile.changeType(plainsForest)
        colony.invalidateCache()
        check(grain, 2, furs, 3)
    }

    @Test func potential() {
        let game = FreeColTestCase.standardGame(spec)
        let tile = Tile(game: game, type: mountains, x: 0, y: 0)
        #expect(mountains.potentialProduction(silver, nil) == 0)
        #expect(tile.potentialProduction(food, nil) == 0)
        #expect(mountains.potentialProduction(silver, colonistType) == 1)
        #expect(tile.potentialProduction(silver, colonistType) == 1)
        tile.addResource(Resource(game: game, tile: tile, type: resource("silver")))
        #expect(tile.potentialProduction(food, colonistType) == 0)
        #expect(tile.potentialProduction(silver, colonistType) == 3)
    }

    @Test func maximumPotential() {
        let game = FreeColTestCase.standardGame(spec)

        let tile1 = Tile(game: game, type: mountains, x: 0, y: 0)
        #expect(tile1.potentialProduction(food, colonistType) == 0, "Mountain/food")
        #expect(tile1.maximumPotential(food, colonistType) == 0, "Mountain/food max")
        #expect(tile1.potentialProduction(silver, colonistType) == 1, "Mountain/silver")
        #expect(tile1.maximumPotential(silver, colonistType) == 2, "Mountain/silver max")
        tile1.addResource(Resource(game: game, tile: tile1, type: resource("silver")))
        #expect(tile1.potentialProduction(food, colonistType) == 0, "Mountain+Resource/food")
        #expect(tile1.potentialProduction(silver, colonistType) == 3, "Mountain+Resource/silver")
        #expect(tile1.maximumPotential(silver, colonistType) == 4, "Mountain+Resource/silver max")

        // The grain maximum is the grain potential + 1 (plowing)
        let tile2 = Tile(game: game, type: plains, x: 0, y: 1)
        #expect(tile2.potentialProduction(grain, nil) == 3, "Plains/grain")
        #expect(tile2.maximumPotential(grain, nil) == 4, "Plains/grain max")
        #expect(tile2.potentialProduction(grain, colonistType) == 5, "Plains/grain/colonist")
        #expect(tile2.maximumPotential(grain, colonistType) == 6, "Plains/grain/colonist max")
        #expect(tile2.potentialProduction(grain, expertFarmerType) == 7, "Plains/grain/expertFarmer")
        tile2.addResource(Resource(game: game, tile: tile2, type: resource("grain")))
        #expect(tile2.potentialProduction(grain, nil) == 5, "Plains+Resource/grain")
        #expect(tile2.maximumPotential(grain, nil) == 6, "Plains+Resource/grain max")
        #expect(tile2.potentialProduction(grain, colonistType) == 7, "Plains+Resource/grain/colonist")
        #expect(tile2.maximumPotential(grain, colonistType) == 8, "Plains+Resource/grain/colonist max")
        #expect(tile2.potentialProduction(grain, expertFarmerType) == 11, "Plains+Resource/grain/expertFarmer")
        #expect(tile2.maximumPotential(grain, expertFarmerType) == 12, "Plains+Resource/grain/expertFarmer max")

        let tile3 = Tile(game: game, type: plainsForest, x: 1, y: 1)
        #expect(tile3.potentialProduction(grain, nil) == 2, "Forest/grain")
        #expect(tile3.maximumPotential(grain, nil) == 4, "Forest/grain max")
        #expect(tile3.potentialProduction(lumber, colonistType) == 6, "Forest/lumber/colonist")
        #expect(tile3.maximumPotential(lumber, colonistType) == 8, "Forest/lumber/colonist max")
        #expect(tile3.potentialProduction(lumber, expertLumberJack) == 12, "Forest/lumber/expertLumberJack")
        #expect(tile3.maximumPotential(lumber, expertLumberJack) == 14, "Forest/lumber/expertLumberJack max")
    }

    @Test func isTileTypeAllowed() {
        let fishBonusLand = improvement("fishBonusLand"), fishBonusRiver = improvement("fishBonusRiver")
        for tileType in spec.tileTypeList {
            let id = tileType.id ?? ""
            if tileType.isWater {
                let highSeas = tileType === self.tileType("highSeas")
                #expect(fishBonusLand.isTileTypeAllowed(tileType) == !highSeas, "\(id)")
                #expect(fishBonusRiver.isTileTypeAllowed(tileType) == !highSeas, "\(id)")
                #expect(!river.isTileTypeAllowed(tileType), "\(id)")
                #expect(!road.isTileTypeAllowed(tileType), "\(id)")
                #expect(!plow.isTileTypeAllowed(tileType), "\(id)")
                #expect(!clearForest.isTileTypeAllowed(tileType), "\(id)")
            } else {
                #expect(clearForest.isTileTypeAllowed(tileType) == tileType.isForested, "\(id)")
                if tileType === self.tileType("arctic") || tileType === hills || tileType === mountains {
                    #expect(!river.isTileTypeAllowed(tileType), "\(id)")
                    #expect(!plow.isTileTypeAllowed(tileType), "\(id)")
                } else {
                    #expect(river.isTileTypeAllowed(tileType), "\(id)")
                    #expect(plow.isTileTypeAllowed(tileType) == !tileType.isForested, "\(id)")
                }
                #expect(road.isTileTypeAllowed(tileType), "\(id)")
            }
        }
    }

    @Test func improvements() throws {
        let (_, map) = game(plains)
        let tile1 = try #require(map.tile(5, 8))
        let tile2 = try #require(map.tile(4, 8))

        let road1 = try #require(tile1.addRoad())
        #expect(!road1.isComplete)
        road1.turnsToComplete = 0
        #expect(road1.isComplete)
        #expect(tile1.hasRoad)
        let river1 = try #require(tile1.addRiver(1, "0101"))
        #expect(river1.isComplete)
        #expect(tile1.hasRiver)

        let road2 = try #require(tile2.addRoad())
        road2.turnsToComplete = 0
        #expect(road2.isComplete)
        tile2.addRiver(1, "0101")
        #expect(tile2.hasRoad)
        #expect(tile2.hasRiver)

        tile1.changeType(savannah)
        #expect(tile1.hasRoad)
        #expect(tile1.hasRiver)

        tile2.changeType(hills)
        #expect(tile2.hasRoad)
        #expect(!tile2.hasRiver)
    }

    func hasBonusFrom(_ modifiers: [Modifier], _ source: FreeColSpecObjectType?) -> Bool {
        modifiers.contains { $0.source === source }
    }

    @Test func productionModifiers() throws {
        let (game, _) = game(explored: true)
        let colony = FreeColTestCase.standardColony(game)
        let unroaded = colony.colonyTiles.filter { !($0.workTile?.hasRoad ?? true) }
        try #require(unroaded.count >= 2)
        let tile1 = try #require(unroaded[0].workTile)
        let tile2 = try #require(unroaded[1].workTile)
        #expect(!tile1.hasRoad)
        #expect(!tile2.hasRoad)

        let road1 = try #require(tile1.addRoad())
        road1.turnsToComplete = 0
        #expect(road1.isComplete)
        let river1 = try #require(tile1.addRiver(1, "0101"))
        #expect(tile1.hasRoad)
        #expect(tile1.hasRiver)

        let road2 = try #require(tile2.addRoad())
        road2.turnsToComplete = 0
        #expect(road2.isComplete)
        tile2.addRiver(1, "0101")
        #expect(tile2.hasRoad)
        #expect(tile2.hasRiver)

        tile1.changeType(savannah)
        #expect(tile1.hasRoad)
        #expect(tile1.hasRiver)
        tile2.changeType(hills)
        #expect(tile2.hasRoad)
        #expect(!tile2.hasRiver)

        // Savannah can produce sugar, but not lumber, so the river
        // gives a bonus for sugar but not lumber.
        #expect(tile1.canProduce(sugar, nil))
        #expect(hasBonusFrom(tile1.productionModifiers(sugar, nil), river1.type))
        #expect(!tile1.canProduce(lumber, nil))
        #expect(!hasBonusFrom(tile1.productionModifiers(lumber, nil), river1.type))
        // Hills can not produce sugar, but can produce ore.  The road
        // only helps attended ore production.
        #expect(!tile2.canProduce(sugar, nil))
        #expect(!hasBonusFrom(tile2.productionModifiers(sugar, nil), road2.type))
        #expect(tile2.canProduce(ore, nil))
        #expect(!hasBonusFrom(tile2.productionModifiers(ore, nil), road2.type))
        #expect(hasBonusFrom(tile2.productionModifiers(ore, colonistType), road2.type))

        // A sugar resource: two sugar bonuses on tile1.
        let turn = game.turn
        #expect(tile1.canProduce(sugar, nil))
        var oldBase = tile1.baseProduction(nil, sugar, nil)
        let addedSugar = Resource(game: game, tile: tile1, type: resource("sugar"))
        tile1.addResource(addedSugar)
        var newBase = tile1.baseProduction(nil, sugar, nil)
        #expect(oldBase == newBase)
        #expect(Int(FeatureContainer.applyModifiers(Float(newBase), turn: turn, tile1.productionModifiers(sugar, nil)))
                == Int(FeatureContainer.applyModifiers(Float(oldBase), turn: turn,
                                                       addedSugar.productionModifiers(sugar, nil)))
                + Int(FeatureContainer.applyModifiers(0, turn: turn, river1.productionModifiers(sugar, nil))))
        #expect(hasBonusFrom(tile1.productionModifiers(sugar, nil), river1.type))
        #expect(hasBonusFrom(tile1.productionModifiers(sugar, nil), resource("sugar")))

        // A minerals resource: tile2 now produces silver.
        #expect(!tile2.canProduce(silver, nil))
        oldBase = tile2.baseProduction(nil, silver, nil)
        let addedSilver = Resource(game: game, tile: tile2, type: resource("minerals"))
        #expect(addedSilver.canProduce(silver, nil))
        #expect(addedSilver.canProduce(silver, colonistType))
        tile2.addResource(addedSilver)
        newBase = tile2.baseProduction(nil, silver, nil)
        #expect(tile2.canProduce(silver, nil))
        #expect(oldBase == newBase)
        #expect(Int(FeatureContainer.applyModifiers(Float(newBase), turn: turn, tile2.productionModifiers(silver, nil)))
                == Int(FeatureContainer.applyModifiers(Float(oldBase), turn: turn,
                                                       addedSilver.productionModifiers(silver, nil)))
                + Int(FeatureContainer.applyModifiers(0, turn: turn, road2.productionModifiers(silver, nil))))
        #expect(!hasBonusFrom(tile2.productionModifiers(silver, nil), road2.type))
        #expect(hasBonusFrom(tile2.productionModifiers(silver, colonistType), road2.type))
        #expect(hasBonusFrom(tile2.productionModifiers(silver, nil), resource("minerals")))
    }

    @Test func colonyImprovements() throws {
        let (game, _) = game(plains)
        let colony = ColonyBuilder(game).build()
        #expect(colony.tile?.hasRoad == true)
        colony.exciseSettlement()
        #expect(colony.tile?.hasRoad == false)
    }

    @Test func coniferForestProduction() throws {
        let (game, _) = game(coniferForest)
        let colony = FreeColTestCase.standardColony(game, 1)
        let tile = try #require(colony.tile)
        tile.addRiver(1, "1111") // allow rivers to join
        let tiles = Array(tile.surroundingTiles(1))
        for (i, t) in tiles.enumerated() {
            if i & 0b0001 != 0 { t.addRiver(1, "1111") } // must be first!
            if i & 0b0010 != 0 { t.addRoad()?.turnsToComplete = 0 }
            if i & 0b0100 != 0 { t.addResource(Resource(game: game, tile: t, type: resource("lumber"), quantity: 99)) }
        }
        let firstColonyTile = try #require(colony.colonyTile(tiles[0]))

        let unit = try #require(colony.unitList.first)
        #expect(unit.type === colonistType)
        unit.setLocation(firstColonyTile)
        unit.changeWorkType(lumber)
        #expect(unit.workType === lumber, "Added unit producing lumber")

        // production = (BASE + RESOURCE) x EXPERT + RIVER + ROAD
        let base = 6, riverBonus = 2, roadBonus = 2, resourceBonus = 4, expertBonus = 2
        #expect(coniferForest.baseProduction(nil, lumber, colonistType) == base, "Base lumber production")

        // All tiles with a colonist
        for (i, t) in tiles.enumerated() {
            let ct = try #require(colony.colonyTile(t))
            unit.setLocation(ct)
            unit.changeWorkType(lumber)
            var result = base
            if t.hasRiver { result += riverBonus }
            if t.hasRoad { result += roadBonus }
            if t.hasResource { result += resourceBonus }
            #expect(ct.totalProduction(of: lumber) == result, "FreeColonist lumber production at tile \(i)")
        }

        // Again with an expert
        #expect(firstColonyTile.expertUnitType === expertLumberJack, "Expert unit")
        unit.setType(expertLumberJack)
        colony.invalidateCache()
        for (i, t) in tiles.enumerated() {
            let ct = try #require(colony.colonyTile(t))
            unit.setLocation(ct)
            unit.changeWorkType(lumber)
            var result = base * expertBonus
            if t.hasRiver { result += riverBonus * expertBonus }
            if t.hasRoad { result += roadBonus * expertBonus }
            if t.hasResource { result += resourceBonus * expertBonus }
            #expect(ct.totalProduction(of: lumber) == result, "Expert lumber production at tile \(i)")
        }
    }

    @Test func minerals() throws {
        let (game, _) = game(tundra)
        let colony = FreeColTestCase.standardColony(game)
        let townHall = try #require(colony.building(townHallType))
        let tile = try #require(colony.tile?.neighbour(.n))
        let colonyTile = try #require(colony.colonyTile(tile))
        tile.addResource(Resource(game: game, tile: tile, type: resource("minerals")))
        for u in colonyTile.unitList { u.setLocation(townHall) }
        #expect(colonyTile.isEmpty)
        #expect(colonyTile.workTile?.owningSettlement === colony)

        let unit = try #require(colony.unitList.first)
        #expect(unit.type === colonistType)
        #expect(silver.isFarmed)
        #expect(tundra.potentialProduction(silver, colonistType) == 0)
        #expect(tile.potentialProduction(silver, colonistType) == 1)
        #expect(tile.productionModifiers(silver, colonistType).count == 1)
        #expect(colonyTile.potentialProduction(silver, unit.type) == 1)
        #expect(colonyTile.canBeWorked)
        #expect(colonyTile.canAdd(unit))
        #expect(colony.workLocation(for: unit, silver) === colonyTile)

        // However, minerals are *necessary* to produce silver
        let marshTile = try #require(colony.tile?.neighbour(.s))
        marshTile.type = marsh
        let marshColonyTile = try #require(colony.colonyTile(marshTile))
        for u in marshColonyTile.unitList { u.setLocation(townHall) }
        func check(_ expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
            #expect(marsh.potentialProduction(silver, colonistType) == 0, sourceLocation: sourceLocation)
            #expect(marshTile.potentialProduction(silver, colonistType) == expected, sourceLocation: sourceLocation)
            #expect(marshTile.productionModifiers(silver, colonistType).count == expected,
                    sourceLocation: sourceLocation)
            #expect(marshColonyTile.potentialProduction(silver, unit.type) == expected,
                    sourceLocation: sourceLocation)
        }
        // No production yet
        #expect(marshColonyTile.isEmpty)
        #expect(marshColonyTile.workTile?.owningSettlement === colony)
        check(0)
        // A road does not start production
        let road = try #require(marshTile.addRoad())
        road.turnsToComplete = 0
        #expect(road.isComplete)
        check(0)
        // Minerals do
        marshTile.addResource(Resource(game: game, tile: marshTile, type: resource("minerals")))
        check(2)
    }

    @Test func defenceModifiers() {
        for tileType in spec.tileTypeList {
            let present = tileType.isForested
                || ["model.tile.hills", "model.tile.marsh", "model.tile.mountains", "model.tile.swamp"]
                .contains(tileType.id)
            #expect(!tileType.defenceModifiers.isEmpty == present, "Defence for \(tileType.id ?? "")")
        }
    }

    @Test func zIndex() {
        #expect(Tile.overlayZIndex < Tile.forestZIndex)
        #expect(Tile.forestZIndex < Tile.resourceZIndex)
        #expect(Tile.resourceZIndex < Tile.rumourZIndex)
        #expect(plow.zIndex < river.zIndex)
        #expect(river.zIndex < road.zIndex)
        #expect(Tile.forestZIndex < road.zIndex)
        #expect(road.zIndex < Tile.resourceZIndex)
    }

    @Test(.disabled("Tile.copy is not ported yet (it copies by writing XML)"))
    func copy() {}

    @Test func getBestDisembarkTile() throws {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.coastTestMap(game, plains, explored: true)
        game.changeMap(map)
        let dutch = try #require(game.player(byNationId: "model.nation.dutch"))
        let settlementTile = try #require(map.tile(9, 2))
        _ = ColonyBuilder(game).player(dutch).colonyTile(settlementTile).build()
        let tileN = try #require(map.tile(9, 1))
        #expect(tileN.isLand)
        let tileS = try #require(map.tile(9, 3))
        #expect(tileS.isLand)
        let tileE = try #require(map.tile(8, 2))
        #expect(tileE.isLand)
        tileS.type = tundraForest
        tileE.type = mountains

        let tiles = settlementTile.safestSurroundingLandTiles(dutch)
        #expect(!tiles.isEmpty, "Surrounding tiles should be found")
        #expect(tiles.first === tileE, "Best tile is mountainous")
        #expect(settlementTile.bestDisembarkTile(dutch) === tileS, "Best landing tile is forest")

        tileN.type = hills
        #expect(settlementTile.bestDisembarkTile(dutch) === tileN, "Best landing tile is now hills")
    }
}

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
import FreeColUtil

/// Makes a new game's map (server/generator/SimpleMapGenerator): the
/// land and terrain, the native settlements, lost city rumours, and the
/// Europeans' starting units.  Importing a map is not ported.
public final class SimpleMapGenerator {

    private let random: JavaRandom
    private let cache: RandomUtils.RandomIntCache

    /// A generator drawing from a random source, which fills its cache at
    /// once, as Java's constructor does.
    public init(_ random: JavaRandom) {
        self.random = random
        cache = RandomUtils.RandomIntCache("simpleMap", random, range: 1 << 16, size: 512)
    }

    /// Make the map for a game, which takes it (generateMap).
    @discardableResult
    public func generateMap(_ game: Game, _ generateEuropeanPlayerUnits: Bool) -> Map {
        let landMap = LandMap(options: game.specification!, cache: cache)
        let map = TerrainGenerator(random).generateMap(game, landMap)
        makeNativeSettlements(map)
        makeLostCityRumours(map)
        if generateEuropeanPlayerUnits {
            EuropeanStartingPositionsGenerator(random).createEuropeanUnits(map, game.liveEuropeanPlayers)
        }
        return map
    }

    private func approximateLandCount(_ spec: Specification) -> Int {
        (spec.getInteger(MapGeneratorOptions.mapWidth) ?? 0) * (spec.getInteger(MapGeneratorOptions.mapHeight) ?? 0)
            * (spec.getInteger(MapGeneratorOptions.landMass) ?? 0) / 100
    }

    /// Lost city rumours on random land, off the poles; mounds where the
    /// natives own the land.
    private func makeLostCityRumours(_ map: Map) {
        let game = map.game!
        let spec = game.specification!
        let rumourNumber = spec.getRange(MapGeneratorOptions.rumourNumber) ?? 1
        let number = approximateLandCount(spec) / rumourNumber
        for _ in 0..<number {
            for _ in 0..<100 {
                guard let t = map.randomLandTile(random) else { continue }
                if t.isPolar { continue }
                if t.isLand && !t.hasLostCityRumour && !t.hasSettlement && t.unitCount == 0 {
                    let r = LostCityRumour(game: game, tile: t)
                    if r.chooseType(nil, random) == .mounds && t.owningSettlement != nil {
                        r.type = .mounds
                    }
                    t.addLostCityRumour(r)
                    break
                }
            }
        }
    }

    // MARK: Native settlements

    /// Settle the natives: a capital for each nation in its area, the
    /// rest of the good sites shared among the nations whose area holds
    /// them, the land round each grown, and the skills taught arranged
    /// so that every new world goods type has its expert somewhere
    /// (makeNativeSettlements).
    private func makeNativeSettlements(_ map: Map) {
        let game = map.game!
        let spec = game.specification!
        var settlements: [IndianSettlement] = []
        let nativePlayers = game.liveNativePlayers()
        if nativePlayers.isEmpty { return }

        // The sites, at least the settlement number apart.
        let allTiles = map.shuffledTiles(random)
        let minDistance = spec.getRange(GameOptions.settlementNumber) ?? 0
        var settlementTiles: [Tile] = []
        for tile in allTiles {
            if tile.isPolar || !suitableForNativeSettlement(tile) { continue }
            if settlementTiles.contains(where: { $0.distance(to: tile) < minDistance }) { continue }
            settlementTiles.append(tile)
        }

        // Each nation's sites: its starting area, or its regions.  Java
        // keeps these in a HashMap by player.
        var designatedArea = JavaHashMap<String, (player: Player, tiles: [Tile])>(javaHash: JavaString.hashCode)
        for player in nativePlayers {
            guard let nation = player.nation, let area = game.nationStartingArea(nation), !area.tiles.isEmpty
            else { continue }
            let forNation = area.tiles.filter { t in settlementTiles.contains { $0 === t } }
            designatedArea[player.id ?? ""] = (player, forNation)
        }
        for player in nativePlayers where designatedArea[player.id ?? ""] == nil {
            guard let nationType = player.nationType as? IndianNationType else { continue }
            let otherRegions = nationType.regions.compactMap { map.region(byKey: $0)?.bounds }.filter { !$0.isEmpty }
            if otherRegions.isEmpty { continue }
            let forNation = settlementTiles.filter { t in otherRegions.contains { $0.contains(t.x, t.y) } }
            designatedArea[player.id ?? ""] = (player, forNation)
        }

        // A capital for each.
        for player in nativePlayers {
            guard let allowed = designatedArea[player.id ?? ""]?.tiles else { continue }
            for settlementTile in settlementTiles where allowed.contains(where: { $0 === settlementTile }) {
                settlements.append(placeIndianSettlement(player, true, settlementTile, map))
                settlementTiles.removeAll { $0 === settlementTile }
                break
            }
        }
        // The rest, to a nation chosen at random among those allowed.
        for settlementTile in settlementTiles {
            var players = designatedArea.entries.map(\.value)
            random.shuffle(&players)
            guard let owner = players.first(where: { $0.tiles.contains { $0 === settlementTile } })?.player
            else { continue }
            settlements.append(placeIndianSettlement(owner, false, settlementTile, map))
        }

        // Grow the land, and collect the skills.  Java keeps the skills
        // in a HashMap by unit type.
        var skills = JavaHashMap<String?, [IndianSettlement]>(javaHash: { $0.map(JavaString.hashCode) ?? 0 })
        RandomUtils.randomShuffle("Settlements", &settlements, random)
        for settlement in settlements {
            var tiles = settlement.ownedTiles.filter { t in
                t.surroundingTiles(1, 1).contains { $0.owningSettlement == nil }
            }
            RandomUtils.randomShuffle("Settlement tiles", &tiles, random)
            let minGrow = settlement.type?.minimumGrowth ?? 0
            let maxGrow = settlement.type?.maximumGrowth ?? 0
            if maxGrow > minGrow {
                var i = Int(RandomUtils.randomInt("Gdiff", random, Int32(maxGrow - minGrow))) + minGrow
                while i > 0 {
                    guard let tile = findFreeNeighbouringTile(settlement, tiles) else { break }
                    tile.changeOwnership(settlement.owner, settlement)
                    tiles.append(tile)
                    i -= 1
                }
            }
            let key = settlement.learnableSkill?.id
            skills[key] = (skills[key] ?? []) + [settlement]
        }

        // Every new world goods type needs its expert taught somewhere:
        // take one from the most common skill.
        var expertsNeeded: [UnitType?] = []
        for goodsType in spec.newWorldGoodsTypeList {
            let expert = spec.expert(producing: goodsType)
            if !skills.keys.contains(where: { $0 == expert?.id }) { expertsNeeded.append(expert) }
        }
        var isList = skills.entries.map(\.value)
        while !expertsNeeded.isEmpty {
            let neededSkill = expertsNeeded.removeFirst()
            isList = isList.stableSorted { $0.count > $1.count }
            var extras = isList.removeFirst()
            var choices: [RandomChoice<IndianSettlement>] = []
            for settlement in extras {
                guard let nationType = settlement.owner?.nationType as? IndianNationType,
                      let tile = settlement.tile else { continue }
                let cm = settlement.isCapital ? 2 : 1
                let rc = nationType.generateSkillsForTile(tile).first { $0.object === neededSkill }
                choices.append(RandomChoice(settlement, rc.map { $0.probability * cm } ?? 1))
            }
            if !choices.isEmpty, let chose = RandomChoice.weightedRandom("expert", choices, random) {
                chose.learnableSkill = neededSkill
                extras.removeAll { $0 === chose }
                isList.insert(extras, at: 0)
                isList.append([chose])
            }
        }
    }

    /// Whether a tile and at least half of those round it can be settled.
    private func suitableForNativeSettlement(_ tile: Tile) -> Bool {
        guard tile.type?.canSettle ?? false else { return false }
        var good = 0, n = 0
        for t in tile.surroundingTiles(1) {
            if t.type?.canSettle ?? false { good += 1 }
            n += 1
        }
        return good >= n / 2
    }

    /// A free tile beside one of a settlement's, in random directions.
    private func findFreeNeighbouringTile(_ settlement: IndianSettlement, _ tiles: [Tile]) -> Tile? {
        guard let owner = settlement.owner else { return nil }
        let dirns = Direction.randomDirections("freeTile", random)
        for t in tiles {
            for d in dirns {
                if let n = t.neighbour(d), n.owningSettlement == nil, owner.canClaimForSettlement(n) { return n }
            }
        }
        return nil
    }

    private func placeIndianSettlement(_ player: Player, _ capital: Bool, _ tile: Tile, _ map: Map)
        -> IndianSettlement {
        let game = map.game as! ServerGame
        let name = capital ? game.nameCache.capitalName(player, random)
            : game.nameCache.settlementName(player, random)
        let skill = generateSkillForLocation(map, tile, player.nationType)
        let settlement = IndianSettlement(game: game, owner: player, name: name, tile: tile, isCapital: capital,
                                          learnableSkill: skill, missionary: nil)
        _ = player.addSettlement(settlement)
        settlement.placeSettlement(true)
        settlement.addRandomGoods(random)
        settlement.addUnits(random)
        return settlement
    }

    /// A skill for a site, weighted by what the land round it makes,
    /// or a scout.
    private func generateSkillForLocation(_ map: Map, _ tile: Tile, _ nationType: NationType?) -> UnitType? {
        let skills = (nationType as? IndianNationType)?.skills ?? []
        let skill = RandomChoice.weightedRandom("", IndianNationType.scaledSkills(skills, tile), random)
        if let skill { return skill }
        return RandomUtils.randomMember("Scout", map.specification?.unitTypes(withAnyAbility: Ability.expertScout) ?? [],
                                        random)
    }
}

extension IndianNationType {
    /// Skills weighted by what the land round a tile makes of their
    /// goods (as generateSkillsForTile, which Java also writes out in
    /// SimpleMapGenerator).
    static func scaledSkills(_ skills: [RandomChoice<UnitType>], _ tile: Tile) -> [RandomChoice<UnitType>] {
        // Java's map is keyed by goods type, and a skill producing
        // nothing (the scout) has the null key, which nothing adds to.
        func key(_ g: GoodsType?) -> ObjectIdentifier? { g.map(ObjectIdentifier.init) }
        var scale: [ObjectIdentifier?: Int] = [:]
        for rc in skills { scale[key(rc.object.expertProduction)] = 1 }
        for t in tile.surroundingTiles(1) {
            var seen = Set<ObjectIdentifier>()
            for rc in skills {
                guard let g = rc.object.expertProduction, seen.insert(ObjectIdentifier(g)).inserted else { continue }
                scale[key(g)]! += t.potentialProduction(g, nil)
            }
        }
        return skills.map { rc in
            RandomChoice(rc.object, rc.probability * (scale[key(rc.object.expertProduction)] ?? 0))
        }
    }

    /// The skills weighted for a tile (generateSkillsForTile).
    func generateSkillsForTile(_ tile: Tile) -> [RandomChoice<UnitType>] {
        IndianNationType.scaledSkills(skills, tile)
    }
}

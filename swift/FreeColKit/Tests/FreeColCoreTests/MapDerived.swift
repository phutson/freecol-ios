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
import FreeColTestSupport
import FreeColUtil

/// The Swift side of src/net/sf/freecol/tools/dump/MapOracle.java: the
/// same values, computed by the Swift model, in the same layout.
enum MapDerived {

    static let seeds: [Int64] = [1, 2, 3]
    static let highSeasDistanceToLand = 4
    static let highSeasMaximumDistanceToEdge = 12

    /// Everything recorded for a game.  This changes the game, so it
    /// must be the last thing done with it.
    static func of(_ game: Game) -> JSONValue {
        let map = game.map!
        var tiles: [String: JSONValue] = [:]
        map.forEachTile { tiles[key($0)] = tile(game, $0) }
        return .object([
            "game": self.game(game),
            "map": self.map(map),
            "regions": regions(map),
            "tiles": .object(tiles),
            "geometry": geometry(map),
            "random": random(map),
            "directions": directions(),
            "units": units(game),
            "unitLocations": unitLocations(game),
            "colonies": colonies(game),
            "players": players(game), // The monarch's random choices change forces
            "setup": setup(game),
            "indianSettlements": indianSettlements(game), // Changes wanted goods
            "goodsContainers": goodsContainers(game), // Changes them
            "contactMoves": contactMoves(game), // Changes stances
            "economy": economy(game), // Trades, routes, native trade
            "paths": paths(game),
            "combat": combat(game), // Changes combat modifier indexes
            "visibility": visibility(game), // Gives players views of tiles
            "reset": reset(map), // Last: changes the map
        ])
    }

    static func game(_ game: Game) -> JSONValue {
        .object([
            "turn": int(game.turn.number),
            "nextId": int(game.nextId),
            "spanishSuccession": .bool(game.spanishSuccession),
            "initialActiveUnitId": string(game.initialActiveUnitId),
            "specification": string(game.specification?.id),
            "players": .array(game.players.map(player)),
            "unknownEnemy": game.unknownEnemy.map(player) ?? .null,
        ])
    }

    static func player(_ p: Player) -> JSONValue {
        .object([
            "id": id(p),
            "name": string(p.name),
            "nationId": string(p.nationId),
            "playerType": .string(p.playerType.map { "\($0)" } ?? "null"),
            "nationType": id(p.nationType),
            "abilities": .array(p.sortedAbilities.map { "\($0)" }.sorted(by: javaOrder).map(JSONValue.string)),
            "modifiers": .array(p.sortedModifiers.map { "\($0)" }.sorted(by: javaOrder).map(JSONValue.string)),
            "europe": id(p.europe),
            "highSeas": id(p.highSeas),
            "units": int(p.units.count),
            "settlements": .array(p.settlements.map(id)),
            "gold": int(p.gold),
            "liberty": int(p.liberty),
            "immigration": int(p.immigration),
            "sonsOfLiberty": int(p.sonsOfLiberty),
            "others": others(p),
        ])
    }

    static func others(_ p: Player) -> JSONValue {
        var ret: [String: JSONValue] = [:]
        for o in p.game!.players where o !== p {
            ret[o.id!] = .string("\(p.stance(o)) \(p.tension(o).value) \(p.hasContacted(o))")
        }
        return .object(ret)
    }

    static func map(_ map: Map) -> JSONValue {
        var rows: [String: JSONValue] = [:]
        for lat in stride(from: -90, through: 90, by: 15) {
            rows[String(lat)] = int(map.row(lat))
        }
        return .object([
            "id": id(map),
            "width": int(map.width),
            "height": int(map.height),
            "layer": .string("\(map.layer)"),
            "minimumLatitude": int(map.minimumLatitude),
            "maximumLatitude": int(map.maximumLatitude),
            "latitudePerRow": float(map.latitudePerRow),
            "latitudes": .array((0..<map.height).map { int(map.latitude($0)) }),
            "rows": .object(rows),
            "tileOrder": .array(map.tiles.prefix(5).map { .string(key($0)) }),
            "fixedRegions": .array(map.fixedRegions.keys.sorted(by: javaOrder).map(JSONValue.string)),
        ])
    }

    static func regions(_ map: Map) -> JSONValue {
        var ret: [String: JSONValue] = [:]
        for r in map.regions {
            ret[r.id!] = .object([
                "name": string(r.name),
                "key": string(r.key),
                "type": .string(r.type.map { "\($0)" } ?? "null"),
                "parent": id(r.parent),
                "children": .array((r.children ?? []).map(id)),
                "claimable": .bool(r.claimable),
                "discoverable": .bool(r.discoverable),
                "discoveredIn": r.discoveredIn.map { int($0.number) } ?? .null,
                "discoveredBy": id(r.discoveredBy),
                "discoverer": string(r.discoverer),
                "scoreValue": int(r.scoreValue),
                "pacific": .bool(r.isPacific),
                "leaf": .bool(r.isLeaf),
                "hasName": .bool(r.hasName),
                "discoverableRegion": id(r.discoverableRegion),
            ])
        }
        ret["order"] = .array(map.regions.map(id))
        return .object(ret)
    }

    static func tile(_ game: Game, _ t: Tile) -> JSONValue {
        let spec = game.specification!
        let colonist = spec.defaultUnitType
        var m: [String: JSONValue] = [
            "id": id(t),
            "type": id(t.type),
            "style": int(t.style),
            "owner": id(t.owner),
            "owningSettlement": id(t.owningSettlement),
            "region": id(t.region),
            "discoverableRegion": id(t.discoverableRegion),
            "highSeasCount": int(t.highSeasCount),
            "moveToEurope": t.moveToEurope.map(JSONValue.bool) ?? .null,
            "contiguity": int(t.contiguity),
            "toString": .string(t.description),
            "toShortString": .string(t.shortDescription),
            "items": .array(items(t).map(JSONValue.string)),
        ]
        if let s = t.settlement {
            m["settlement"] = .string("\(type(of: s)) \(s.id ?? "null") \(s.name ?? "null")"
                + " \(s.owner?.id ?? "null")")
        }
        var flags: [String] = []
        func flag(_ name: String, _ value: Bool) {
            if value { flags.append(name) }
        }
        flag("explored", t.isExplored)
        flag("land", t.isLand)
        flag("forested", t.isForested)
        flag("coastland", t.isCoastland)
        flag("shore", t.isShore)
        flag("landLocked", t.isLandLocked)
        flag("polar", t.isPolar)
        flag("highSeasConnected", t.isHighSeasConnected)
        flag("directlyHighSeasConnected", t.isDirectlyHighSeasConnected)
        flag("riverCorner", t.isRiverCorner)
        flag("onRiver", t.isOnRiver)
        flag("unexploredAdjacent", t.hasUnexploredAdjacent)
        flag("river", t.hasRiver)
        flag("road", t.hasRoad)
        flag("resource", t.hasResource)
        flag("lostCityRumour", t.hasLostCityRumour)
        flag("settlement", t.hasSettlement)
        if t.type != nil {
            flag("goodHill", t.isGoodHillTile)
            flag("goodMountain", t.isGoodMountainTile)
            flag("goodRiver", t.isGoodRiverTile(spec.getTileImprovementType("model.improvement.river")!))
        }
        m["flags"] = .array(flags.map(JSONValue.string))
        m["availableAdjacent"] = int(t.availableAdjacentCount)
        m["riverStyle"] = string(t.riverStyle?.string)
        guard t.type != nil else { return .object(m) }

        m["defenceValue"] = .decimal(t.defenceValue)
        m["defenceBonus"] = int(t.defenceBonusPercentage)
        m["defenceModifiers"] = .array(t.defenceModifiers.map { "\($0)" }.sorted(by: javaOrder)
            .map(JSONValue.string))

        var potential: [String: JSONValue] = [:]
        for gt in spec.farmedGoodsTypeList {
            let expert = spec.expert(producing: gt)
            let p = [
                t.potentialProduction(gt, nil),
                t.potentialProduction(gt, colonist),
                t.maximumPotential(gt, colonist),
                expert.map { t.potentialProduction(gt, $0) } ?? 0,
                expert.map { t.maximumPotential(gt, $0) } ?? 0,
                t.canProduce(gt, nil) ? 1 : 0,
                t.canProduce(gt, colonist) ? 1 : 0,
            ]
            if p.contains(where: { $0 != 0 }) { potential[gt.id!] = .array(p.map(int)) }
        }
        m["potential"] = .object(potential)
        m["sortedPotential"] = goods(t.sortedPotential)
        m["sortedAutoPotential"] = goods(t.sortedAutoPotential)
        m["bestFood"] = goodsString(t.bestFoodProduction)
        m["maximumFoodWithExpert"] = goodsString(t.maximumPotentialFoodProductionWithExpert)

        var work: [String: JSONValue] = [:]
        var has: [JSONValue] = []
        for tit in spec.tileImprovementTypeList {
            if t.isImprovementTypeAllowed(tit) { work[tit.id!] = int(t.workAmount(tit)) }
            if t.hasTileImprovement(tit) { has.append(id(tit)) }
        }
        m["work"] = .object(work)
        m["hasImprovement"] = .array(has)
        m["disasters"] = .array(t.disasterChoices.map {
            .string("\($0.object.id ?? "null"):\($0.probability)")
        })
        if let tic = t.tileItemContainer {
            var costs: [String: JSONValue] = [:]
            for d in Direction.allDirections {
                if let from = t.neighbour(d) {
                    costs["\(d)"] = int(tic.moveCost(from: from, to: t, 3))
                }
            }
            m["moveCosts"] = .object(costs)
        }
        return .object(m)
    }

    static func items(_ t: Tile) -> [String] {
        (t.tileItemContainer?.items ?? []).map { item in
            var s = (item.id ?? "null") + " "
            if let ti = item as? TileImprovement {
                s += "\(ti) magnitude=\(ti.magnitude) turns=\(ti.turnsToComplete)"
                    + " virtual=\(ti.isVirtual) connections=\(ti.connectionsFromStyle)"
                if ti.connectionDirections != nil {
                    s += " connected=" + Direction.allDirections.map { ti.isConnected(to: $0) ? "1" : "0" }
                        .joined()
                }
                if ti.isRiver {
                    s += " river=" + Direction.longSides.map { String(ti.riverConnection($0)) }.joined()
                }
            } else if let r = item as? Resource {
                s += "\(r) best=\(r.bestGoodsType?.id ?? "null")"
                // A large production, so the quantity left limits it.
                if let best = r.bestGoodsType {
                    s += " bonus1000=\(r.applyBonus(best, nil, 1000))"
                    // And with one unit left, where the quantity is limited.
                    if !r.isUnlimited {
                        let q = r.quantity
                        r.quantity = 1
                        s += " bonusLast=\(r.applyBonus(best, nil, 1000))"
                        r.quantity = q
                    }
                }
            } else if let lcr = item as? LostCityRumour {
                s += "\(lcr.type.map { "\($0)" } ?? "null") \(lcr.name ?? "null")"
            }
            return s + " z=\(item.zIndex) layer=\(item.layer) natural=\(item.isNatural)"
                + " complete=\(item.isComplete)"
        }
    }

    /// Tiles to ask geometry questions about: corners, edges, middle.
    static func sampleTiles(_ map: Map) -> [Tile] {
        let w = map.width, h = map.height
        let points = [
            (0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
            (0, 1), (1, 1), (w - 1, 1), (w / 2, 0), (w / 2, 1),
            (0, h / 2), (w - 1, h / 2), (w / 2, h / 2), (w / 2, h / 2 + 1),
            (w / 3, h / 3), (2 * w / 3, 2 * h / 3), (w / 2, h - 1), (w / 2, h - 2),
        ]
        var ret: [Tile] = []
        for (x, y) in points {
            if let t = map.tile(x, y), !ret.contains(where: { $0 === t }) { ret.append(t) }
        }
        return ret
    }

    static func geometry(_ map: Map) -> JSONValue {
        let samples = sampleTiles(map)
        var tiles: [String: JSONValue] = [:]
        for t in samples {
            var m: [String: JSONValue] = [:]
            var nb: [String: JSONValue] = [:]
            for d in Direction.allDirections { nb["\(d)"] = keyOrNull(t.neighbour(d)) }
            m["neighbours"] = .object(nb)
            for r in 0...3 {
                m["filled\(r)"] = keys(map.circleTiles(t, filled: true, radius: r))
                m["ring\(r)"] = keys(map.circleTiles(t, filled: false, radius: r))
            }
            m["surrounding01"] = keys(t.surroundingTiles(0, 1))
            m["surrounding12"] = keys(t.surroundingTiles(1, 2))
            m["surrounding23"] = keys(t.surroundingTiles(2, 3))
            m["contiguityAdjacent"] = .array(t.contiguityAdjacent(t.contiguity).map(key)
                .sorted(by: javaOrder).map(JSONValue.string))
            m["landWithin3"] = keyOrNull(map.landWithinDistance(t.x, t.y, 3))
            m["closest"] = keyOrNull(map.closestTile(t, samples.filter { $0 !== t }))
            var pairs: [String: JSONValue] = [:]
            for o in samples {
                let direction = map.direction(t, o).map { "\($0)" } ?? "null"
                let rough = Map.roughDirection(t, o).map { "\($0)" } ?? "null"
                pairs[key(o)] = .string("\(map.distance(t, o)) \(direction) \(rough)"
                    + " \(t.isAdjacent(o)) \(t.isConnected(to: o))")
            }
            m["pairs"] = .object(pairs)
            tiles[key(t)] = .object(m)
        }
        let w = map.width, h = map.height
        let starting = map.collectStartingTiles()
        return .object([
            "samples": .object(tiles),
            "subMapTopLeft": keys(map.subMap(-2, -2, 5, 5)),
            "subMapBottomRight": keys(map.subMap(w - 3, h - 3, 10, 10)),
            "subMapMiddle": keys(map.subMap(w / 2, h / 2, 3, 2)),
            "startingEast": keys(starting.east),
            "startingWest": keys(starting.west),
        ])
    }

    static func random(_ map: Map) -> JSONValue {
        var ret: [String: JSONValue] = [:]
        for seed in seeds {
            let random = JavaRandom(seed: seed)
            let land = (0..<3).map { _ in keyOrNull(map.randomLandTile(random)) }
            let shuffled = map.shuffledTiles(random).prefix(10).map { JSONValue.string(key($0)) }
            let direction = Direction.randomDirection("test", random)
            let directions = Direction.randomDirections("test", random)
            let closest = Direction.allDirections.map {
                JSONValue.string(list($0.closestDirections("test", random)))
            }
            ret[String(seed)] = .object([
                "randomLandTiles": .array(land),
                "shuffledTiles": .array(Array(shuffled)),
                "randomDirection": .string("\(direction)"),
                "randomDirections": .string(list(directions)),
                "closestDirections": .array(closest),
                "next": int(Int(random.nextInt())),
            ])
        }
        return .object(ret)
    }

    static func directions() -> JSONValue {
        var ret: [String: JSONValue] = [:]
        for d in Direction.allDirections {
            ret["\(d)"] = .string("\(d.step(5, 4)) \(d.step(5, 5)) \(d.nextDirection)"
                + " \(d.previousDirection) \(d.reverseDirection) \(d.ewMirroredDirection)"
                + " \(d.rotate(3)) \(d.rotate(-3))")
        }
        return .object(ret)
    }

    /// The initialized objects of a class, in Java's identifier order.
    static func objects<T>(_ game: Game, _ type: T.Type) -> [T] {
        game.freeColGameObjects.filter { $0 is T && $0.isInitialized }
            .sorted { javaOrder($0.id ?? "", $1.id ?? "") }
            .map { $0 as! T }
    }

    static func locId(_ loc: (any Location)?) -> JSONValue { string(loc?.id) }

    static func units(_ game: Game) -> JSONValue {
        let spec = game.specification!
        var ret: [String: JSONValue] = [:]
        for u in objects(game, Unit.self) {
            var flags: [String] = []
            func flag(_ name: String, _ value: Bool) { if value { flags.append(name) } }
            flag("naval", u.isNaval)
            flag("carrier", u.isCarrier)
            flag("person", u.isPerson)
            flag("canCarryUnits", u.canCarryUnits)
            flag("canCarryGoods", u.canCarryGoods)
            flag("damaged", u.isDamaged)
            flag("forcedRepair", u.isDamagedAndUnderForcedRepair)
            flag("onCarrier", u.isOnCarrier)
            flag("onTile", u.isOnTile)
            flag("inEurope", u.isInEurope)
            flag("inColony", u.isInColony)
            flag("hasCargo", u.hasCargo)
            flag("hasGoodsCargo", u.hasGoodsCargo)
            flag("defaultRole", u.hasDefaultRole)
            flag("spaceLeft", u.hasSpaceLeft)
            flag("offensive", u.isOffensiveUnit)
            flag("defensive", u.isDefensiveUnit)
            flag("undead", u.isUndead)
            var m: [String: JSONValue] = [
                "name": string(u.name),
                "type": id(u.type),
                "owner": id(u.owner),
                "role": id(u.role),
                "roleCount": int(u.roleCount),
                "state": .string("\(u.state)"),
                "location": locId(u.location),
                "entryLocation": locId(u.entryLocation),
                "destination": locId(u.destination),
                "movesLeft": int(u.movesLeft),
                "workLeft": int(u.workLeft),
                "attrition": int(u.attrition),
                "turnsOfTraining": int(u.turnsOfTraining),
                "hitPoints": int(u.hitPoints),
                "home": id(u.homeIndianSettlement),
                "treasureAmount": int(u.treasureAmount),
                "experienceType": id(u.experienceType),
                "experience": int(u.experience),
                "workType": id(u.workType),
                "tile": keyOrNull(u.tile),
                "settlement": id(u.settlement),
                "carrier": id(u.carrier),
                "flags": .array(flags.map(JSONValue.string)),
                "cargoCapacity": int(u.cargoCapacity),
                "spaceTaken": int(u.spaceTaken),
                "spaceLeft": int(u.spaceLeft),
                "goodsSpaceTaken": int(u.goodsSpaceTaken),
                "unitSpaceTaken": int(u.unitSpaceTaken),
                "cargoSpaceTaken": int(u.cargoSpaceTaken),
                "visibleGoodsCount": int(u.visibleGoods),
                "maximumHitPoints": int(u.maximumHitPoints),
                "rank": int(u.rank),
                "up": locId(u.up()),
                "toShortString": .string(u.shortDescription),
                "workLocation": id(u.workLocation),
                "workTile": keyOrNull(u.workTile),
                "skillLevel": int(u.skillLevel),
                "teacher": id(u.teacher),
                "student": id(u.student),
                // All the abilities: the type's, role's, owner's and location's.
                "abilityCount": int(u.abilities(nil).count),
            ]
            if u.canCarryGoods {
                var loadable: [String: JSONValue] = [:]
                for gt in spec.storableGoodsTypeList { loadable[gt.id!] = int(u.loadableAmount(gt)) }
                m["loadable"] = .object(loadable)
                // With a part-filled hold, where there is a container.
                if let gc = u.goodsContainer {
                    let gt = spec.storableGoodsTypeList[0]
                    gc.addGoods(gt, 30)
                    m["partialLoad"] = .string("\(u.loadableAmount(gt))"
                        + " \(u.noAddReason(Goods(game: game, location: nil, type: gt, amount: 70)))"
                        + " \(u.noAddReason(Goods(game: game, location: nil, type: gt, amount: 71)))"
                        + " \(u.spaceLeft)")
                    gc.addGoods(gt, -30)
                }
            }
            m["rules"] = unitRules(game, u)
            ret[u.id!] = .object(m)
        }
        return .object(ret)
    }

    /// MapOracle.unitRules.
    static func unitRules(_ game: Game, _ u: Unit) -> JSONValue {
        let spec = game.specification!
        var flags: [String] = []
        func flag(_ name: String, _ value: Bool) { if value { flags.append(name) } }
        flag("tradingUnit", u.isTradingUnit)
        flag("colonist", u.isColonist)
        flag("atSea", u.isAtSea)
        flag("inMission", u.isInMission)
        flag("nativeEthnicity", u.hasNativeEthnicity)
        flag("armed", u.isArmed)
        flag("mounted", u.isMounted)
        flag("beached", u.isBeached)
        flag("carryTreasure", u.canCarryTreasure)
        flag("captureGoods", u.canCaptureGoods)
        flag("couldMove", u.couldMove)
        flag("candidate", u.isCandidateForNextActiveUnit)
        flag("toHighSeas", u.canMoveToHighSeas)
        flag("buildColony", u.canBuildColony)
        flag("killedByLoss", u.losingEquipmentKillsUnit)
        flag("demotedByLoss", u.losingEquipmentDemotesUnit)
        var m: [String: JSONValue] = [
            "flags": .array(flags.map(JSONValue.string)),
            "scoreValue": int(u.scoreValue),
            "initialMovesLeft": int(u.initialMovesLeft),
            "movesAsString": .string(u.movesAsString),
            "sailTurns": int(u.sailTurns),
            "lineOfSight": int(u.lineOfSight),
            "visibleTiles": .array(u.visibleTileSet.map(key).sorted().map(JSONValue.string)),
            "workTurnsLeft": int(u.workTurnsLeft),
            "turnsForRepair": int(u.turnsForRepair),
            "pioneerScore": int(u.pioneerScore),
            "scoutScore": int(u.scoutScore),
            "convertProbability": .string(JavaNumberFormat.string(u.convertProbability)),
            "burnProbability": .string(JavaNumberFormat.string(u.burnProbability)),
            "militaryRole": id(u.militaryRole),
            "sortedMilitaryRoles": .array(u.sortedMilitaryRoles.map(id)),
            "automaticRole": id(u.automaticRole),
            "atOwnLocation": .bool(u.isAtLocation(u.location)),
            "evaluateFor": int(u.evaluateFor(u.owner!)),
            "tradeRoute": .string("\(u.tradeRoute?.id ?? "null") \(u.currentStop) \(u.followingTradeRoute)"
                + " \(u.goingToDestination)"),
            "atEurope": .bool(u.isAtLocation(u.owner?.europe)),
        ]
        if u.canCarryTreasure {
            m["transportFee"] = int(u.transportFee)
            m["cashIn"] = .bool(u.canCashInTreasureTrain)
        }
        if u.student != nil { m["neededTurnsOfTraining"] = int(u.neededTurnsOfTraining) }
        if let tile = u.tile, u.type != nil { m["sortedPotential"] = goods(tile.sortedPotential(u)) }
        var capture: [String: JSONValue] = [:]
        for r in spec.militaryRolesList { capture[r.id!] = id(u.canCaptureEquipment(r)) }
        m["captureEquipment"] = .object(capture)
        var changes: [String: JSONValue] = [:]
        for uct in spec.unitChangeTypeList where !uct.ownerChange {
            changes[uct.id!] = u.unitChange(uct.id!).map { .string("\($0)") } ?? .null
        }
        m["unitChanges"] = .object(changes)
        if let tile = u.tile {
            var moves: [String: JSONValue] = [:]
            for d in Direction.allDirections {
                guard let t = tile.neighbour(d) else { continue }
                var mv: [String: JSONValue] = [
                    "simple": .string("\(u.simpleMoveType(d))"),
                    "move": .string("\(u.moveType(d))"),
                    "full": .string("\(u.moveType(tile, t, u.initialMovesLeft))"),
                    "cost": int(u.moveCost(t)),
                    "fullCost": int(u.moveCost(tile, t, u.initialMovesLeft)),
                    "oneCost": int(u.moveCost(tile, t, 1)),
                ]
                if let d0 = t.firstUnit {
                    mv["canAttack"] = .bool(u.canAttack(d0))
                    mv["canAmbush"] = .bool(u.canAmbush(d0))
                }
                moves["\(d)"] = .object(mv)
            }
            m["moves"] = .object(moves)
            m["targets"] = targets(game, u)
        }
        return .object(m)
    }

    static func targets(_ game: Game, _ u: Unit) -> JSONValue {
        let tile = u.tile
        var targets: [String: JSONValue] = [:]
        for t in targetTiles(game) where t !== tile {
            let water = Direction.allDirections.lazy.compactMap { t.neighbour($0) }.first { !$0.isLand }
            targets[key(t)] = .string("\(u.simpleMoveType(tile, t))|"
                + (water.map { "\(u.simpleMoveType($0, t))" } ?? "null") + "|"
                + "\(u.moveType(tile, t, 1))")
        }
        return .object(targets)
    }

    /// MapOracle.contactMoves: everyone has met.
    static func contactMoves(_ game: Game) -> JSONValue {
        let spec = game.specification!
        let europeans = game.livePlayers.filter(\.isEuropean)
        let natives = game.livePlayers.filter { !$0.isEuropean && $0.isIndian }
        for (i, e) in europeans.enumerated() {
            for n in natives {
                e.setStance(n, .peace)
                n.setStance(e, .peace)
                for settlement in n.indianSettlementList { _ = settlement.setContacted(e) }
            }
            for (k, o) in europeans.enumerated() where o !== e {
                e.setStance(o, i < 2 && k < 2 ? .war : .peace)
            }
        }
        var ret: [String: JSONValue] = [:]
        var loaded = false
        for u in objects(game, Unit.self) where u.tile != nil && (u.owner?.isEuropean ?? false) {
            if !loaded && u.isTradingUnit, let gc = u.goodsContainer {
                gc.addGoods(spec.storableGoodsTypeList[0], 50)
                loaded = true
            }
            ret[u.id!] = targets(game, u)
        }
        return .object(ret)
    }

    /// The settlement tiles, and the tiles with units on them.
    // MARK: Players (MapOracle.players and the rest)

    static func players(_ game: Game) -> JSONValue {
        let spec = game.specification!
        let all = game.players
        var ret: [String: JSONValue] = [:]
        for p in all {
            var flags: [String] = []
            func flag(_ name: String, _ value: Bool) { if value { flags.append(name) } }
            flag("workForREF", p.isWorkForREF)
            flag("canBuildColonies", p.canBuildColonies)
            flag("canHaveFoundingFathers", p.canHaveFoundingFathers)
            flag("checkEmigrate", p.checkEmigrate)
            flag("atWar", p.isAtWar)
            flag("contactedEuropeans", p.hasContactedEuropeans)
            flag("contactedIndians", p.hasContactedIndians)
            flag("canMoveToEurope", p.canMoveToEurope)
            flag("hasSettlements", p.hasSettlements)
            flag("undead", p.isUndead)
            var m: [String: JSONValue] = [
                "admin": .bool(p.isAdmin),
                "ai": .bool(p.isAI),
                "ready": .bool(p.ready),
                "dead": .bool(p.isDead),
                "bankrupt": .bool(p.bankrupt),
                "attackedByPrivateers": .bool(p.attackedByPrivateers),
                "score": int(p.score),
                "tax": int(p.tax),
                "immigrationRequired": int(p.immigrationRequired),
                "oldSoL": int(p.oldSoL),
                "interventionBells": int(p.interventionBells),
                "currentFather": id(p.currentFather),
                "offeredFathers": .array(p.offeredFathers.map(id)),
                "foundingFathers": .array(p.foundingFathers.compactMap(\.id).sorted(by: javaOrder)
                    .map(JSONValue.string)),
                "independentNationName": string(p.independentNationName),
                "newLandName": string(p.newLandName),
                "entryTile": keyOrNull(p.entryTile),
                "rank": int(p.rank),
                "flags": .array(flags.map(JSONValue.string)),
                "rebels": .array(p.rebels.map(id)),
                "refPlayer": id(p.refPlayer),
                "totalImmigrationProduction": int(p.totalImmigrationProduction),
                "libertyProductionNextTurn": int(p.libertyProductionNextTurn),
                "fatherCost": .string("\(p.totalFoundingFatherCost) \(p.remainingFoundingFatherCost)"),
                "checkDeclareIndependence": string(p.checkDeclareIndependenceKey),
                "maximumFoodConsumption": int(p.maximumFoodConsumption),
                "unitSet": .array(p.units.map(id)),
                "unitCounts": .string("\(p.unitCount) \(p.unitCount(naval: true)) \(p.unitCount(naval: false))"
                    + " \(p.numberOfKingLandUnits) \(p.hasUnitType("model.unit.freeColonist"))"),
                "militaryUnits": strings(p.militaryUnits),
                "refUnits": p.refUnits.map { strings($0) } ?? .null,
            ]
            p.resetIterators()
            let candidates = p.units.filter(\.isCandidateForNextActiveUnit).count
            m["nextActiveUnits"] = .array((0..<(candidates + 2)).map { _ in id(p.nextActiveUnit()) })
            m["tradeRoutes"] = strings(p.tradeRoutes)

            var trade: [String: JSONValue] = [:]
            for gt in spec.storableGoodsTypeList {
                trade[gt.id!] = .string("\(p.arrears(gt)) \(p.canTrade(gt)) \(p.canTrade(gt, .customHouse))"
                    + " \(p.sales(gt)) \(p.hasTraded(gt)) \(p.incomeBeforeTaxes(gt)) \(p.incomeAfterTaxes(gt))")
            }
            m["trade"] = .object(trade)
            m["mostValuableGoods"] = string(p.mostValuableGoods.map(goodsDescription))

            var relations: [String: JSONValue] = [:]
            for o in all where o !== p {
                relations[o.id!] = .string("\(p.isPotentialEnemy(o)) \(p.isPotentialFriend(o))"
                    + " \(p.missionsBanned(o)) \(idList(p.indianSettlementsWithMissionary(o)))")
            }
            m["relations"] = .object(relations)

            m["ports"] = .string("\(p.numberOfPorts) \(idList(p.connectedPortList)) \(p.coloniesPopulation)")
            m["closestPortForEurope"] = id(p.closestPortForEurope)
            m["fallbackTile"] = keyOrNull(p.fallbackTile)

            if p.isEuropean {
                var sites: [String: JSONValue] = [:]
                for t in game.map!.tiles where t.isLand && (t.x + t.y) % 3 == 0 {
                    sites[key(t)] = .string("\(p.canClaimToFoundSettlementReason(t)) \(p.colonyValue(t))"
                        + " " + javaList(p.allColonyValues(t).map(JavaNumberFormat.string)))
                }
                m["colonySites"] = .object(sites)
                var claimable: [String: JSONValue] = [:]
                for t in sampleTiles(game.map!) { claimable[key(t)] = keys(p.claimableTiles(t, 2)) }
                m["claimableTiles"] = .object(claimable)
            }

            if let europe = p.europe {
                var prices: [String: JSONValue] = [:]
                for ut in spec.unitTypeList {
                    let au = AbstractUnit(id: ut.id, roleId: Specification.defaultRoleId, number: 2)
                    prices[ut.id!] = .string("\(p.europeanPurchasePrice(au)) \(p.mercenaryHirePrice(au))")
                }
                for r in spec.rolesList {
                    let au = AbstractUnit(id: spec.defaultUnitType?.id, roleId: r.id, number: 1)
                    prices[r.id!] = int(p.europeanPurchasePrice(au))
                }
                m["prices"] = .object(prices)
                m["recruitPrice"] = int(p.europeanRecruitPrice)
                m["europe"] = self.europe(game, europe)
            }

            if let market = p.market {
                var md: [String: JSONValue] = [:]
                for d in market.marketDataValues { md[d.id!] = .string("\(d)") }
                m["marketData"] = .object(md)
                m["marketOrder"] = .array(market.marketDataValues.map(id))
                var mp: [String: JSONValue] = [:]
                for gt in spec.goodsTypeList {
                    mp[gt.id!] = .string("\(market.costToBuy(gt)) \(market.paidForSale(gt))"
                        + " \(market.bidPrice(gt, 37)) \(market.salePrice(gt, 37))"
                        + " \(market.amountInMarket(gt)) \(market.hasPriceChanged(gt)) \(market.hasBeenTraded(gt))")
                }
                m["marketPrices"] = .object(mp)
            }

            if let monarch = p.monarch {
                // The tax limits, around both ends.
                let tax = p.tax
                var limits: [JSONValue] = []
                for t in [29, 30, 31, 69, 70, 71] {
                    p.setTax(t)
                    limits.append(.string("\(t) \(monarch.actionIsValid(.lowerTaxWar))"
                        + " \(monarch.actionIsValid(.raiseTaxAct))"))
                }
                p.setTax(tax)
                m["taxLimits"] = .array(limits)
                m["monarch"] = self.monarch(monarch)
            }
            ret[p.id!] = .object(m)
        }
        return .object(ret)
    }

    static func europe(_ game: Game, _ eu: Europe) -> JSONValue {
        let spec = game.specification!
        var up: [String: JSONValue] = [:]
        for ut in spec.unitTypeList { up[ut.id!] = int(eu.unitPrice(ut)) }
        var goods: [String: JSONValue] = [:]
        for gt in spec.storableGoodsTypeList {
            var v: String
            do {
                v = "\(try eu.priceGoods([AbstractGoods(gt, 100)])) \(try eu.priceGoods([AbstractGoods(gt, -100)]))"
            } catch {
                v = "refused"
            }
            goods[gt.id!] = .string(v + " \(eu.exportAmount(gt, 1)) \(eu.importAmount(gt, 1))"
                + " \(eu.availableGoodsCount(gt))")
        }
        return .object([
            "recruitables": .string(javaList(eu.recruitables)),
            "expanded": .string("\(javaList(eu.expandedRecruitables(full: false)))"
                + " \(javaList(eu.expandedRecruitables(full: true)))"),
            "recruit": .string("\(eu.baseRecruitPrice) \(eu.recruitLowerCap) \(eu.currentRecruitPrice)"),
            "immigration": .string("\(eu.immigration(0)) \(eu.immigration(-5)) \(eu.immigration(7))"),
            "unitPrices": .object(up),
            "goods": .object(goods),
            "nameKey": string(eu.nameKey),
        ])
    }

    static func monarch(_ mo: Monarch) -> JSONValue {
        let ef = mo.expeditionaryForce
        var m: [String: JSONValue] = [
            "supportSea": .bool(mo.supportSea),
            "displeasure": .bool(mo.displeasure),
            "expeditionaryForce": .string("\(ef) \(JavaNumberFormat.string(ef.calculateStrength(true)))"
                + " \(JavaNumberFormat.string(ef.calculateStrength(false)))"),
            "interventionForce": .string("\(mo.interventionForce)"),
            "mercenaryForce": .string("\(mo.mercenaryForce)"),
            "warSupportForce": .string("\(mo.warSupportForce)"),
        ]
        var valid: [String: JSONValue] = [:]
        for a in Monarch.MonarchAction.allCases { valid[a.javaName] = .bool(mo.actionIsValid(a)) }
        m["valid"] = .object(valid)
        m["choices"] = .array(mo.actionChoices().map { .string("\($0.object):\($0.probability)") })
        m["enemies"] = .array(mo.collectPotentialEnemies().map(id))
        m["friends"] = .array(mo.collectPotentialFriends().map(id))
        m["navalREFUnitType"] = id(mo.navalREFUnitType)
        m["shouldAddNavalUnit"] = .bool(mo.shouldAddNavalUnit)
        let r = JavaRandom(seed: 7)
        m["taxes"] = .string("\(mo.raiseTax(r)) \(mo.raiseTax(r)) \(mo.lowerTax(r)) \(mo.lowerTax(r))")
        var mercs: [AbstractUnit] = []
        var price = mo.loadMercenaries(JavaRandom(seed: 11), &mercs)
        m["mercenaries"] = .string("\(price) \(javaList(mercs))")
        price = mo.loadMercenaryForce(JavaRandom(seed: 13), &mercs)
        m["mercenaryForceOffer"] = .string("\(price) \(javaList(mercs))")
        let land = mo.support(JavaRandom(seed: 17), naval: false)
        let naval = mo.support(JavaRandom(seed: 19), naval: true)
        m["support"] = .string("\(javaList(land)) \(javaList(naval)) \(mo.supportSea)")
        let ar = JavaRandom(seed: 23)
        let added = (0..<4).map { _ in mo.addToREF(ar).map { "\($0)" } ?? "null" }
        m["addToREF"] = .string("\(javaList(added)) \(mo.expeditionaryForce)")
        mo.updateInterventionForce()
        m["updatedInterventionForce"] = .string("\(mo.interventionForce)")
        return .object(m)
    }

    static func setup(_ game: Game) -> JSONValue {
        var m: [String: JSONValue] = [:]
        if let no = game.nationOptions {
            m["nationalAdvantages"] = .string("\(no.nationalAdvantages)")
            var states: [String: JSONValue] = [:]
            for (nation, state) in no.nationStates { states[nation.id!] = .string("\(state)") }
            m["nations"] = .object(states)
            m["nationOrder"] = .array(no.nationStates.map { id($0.nation) })
        }
        var areas: [String: JSONValue] = [:]
        for a in game.areaList {
            areas[a.id!] = .string("\(a.nameKey ?? "null") \(a.name ?? "null")"
                + " \(javaList(a.tiles.map(key))) \(a.rgb.map { "\($0)" } ?? "null")")
        }
        m["areas"] = .object(areas)
        return .object(m)
    }

    static func economy(_ game: Game) -> JSONValue {
        let spec = game.specification!
        var ret: [String: JSONValue] = [:]
        var routeId = 0
        for p in game.liveEuropeanPlayers {
            var m: [String: JSONValue] = [:]
            if let market = p.market {
                var steps: [JSONValue] = []
                for gt in spec.storableGoodsTypeList {
                    let up = market.addGoodsToMarket(gt, 300)
                    let a = "\(market.marketData(gt)!)"
                    let down = market.addGoodsToMarket(gt, -2000)
                    let b = "\(market.marketData(gt)!)"
                    market.modifySales(gt, 5)
                    market.modifyIncomeBeforeTaxes(gt, 11)
                    market.modifyIncomeAfterTaxes(gt, 7)
                    let changed = market.hasPriceChanged(gt)
                    market.flushPriceChange(gt)
                    market.update(gt)
                    steps.append(.string("\(up) \(a) \(down) \(b) \(changed) \(market.marketData(gt)!)"))
                }
                m["market"] = .array(steps)
                p.setTax(p.tax + 10)
                m["tax"] = .string("\(p.tax) \(sortedFeatureStrings(p))")
            }
            let colonies = p.colonyList
            if colonies.count >= 2 {
                let tr = TradeRoute(game: game, id: "tradeRoute:oracle\(routeId)", name: nil, owner: nil)
                routeId += 1
                tr.name = "route \(routeId)"
                tr.owner = p
                var steps: [String] = []
                steps.append(tr.verifyKey ?? "null")
                let storable = spec.storableGoodsTypeList
                let s0 = TradeRouteStop(game: game, location: colonies[0])
                s0.addCargo(storable[1])
                s0.addCargo(storable[1])
                s0.addCargo(storable[3])
                let s1 = TradeRouteStop(game: game, location: colonies[1])
                tr.addStop(s0)
                tr.addStop(s1)
                steps.append(tr.verifyKey ?? "null")
                if let europe = p.europe { tr.addStop(TradeRouteStop(game: game, location: europe)) }
                steps.append(tr.verifyKey ?? "null")
                p.addTradeRoute(tr)
                p.addTradeRoute(tr) // Already there
                steps.append("\(p.tradeRouteCount) \(p.newestTradeRoute?.id ?? "null")"
                    + " \(p.tradeRoute(byName: tr.name, excluding: nil) === tr) \(tr.verifyUniqueNameKey ?? "null")")
                for stop in tr.stopList {
                    steps.append("\(stop.location?.id ?? "null") \(goodsList(stop.compactCargo))"
                        + " \(stop.isValid(p)) \(TradeRoute.isStopValid(p, stop))")
                }
                steps.append("\(tr.stopSublist(s1, s0)!.count) \(tr.stopSublist(s0, s1)!.count)")
                if let ship = objects(game, Unit.self).first(where: { $0.owner === p && $0.isNaval }) {
                    steps.append("before \(ship.couldMove) \(ship.followingTradeRoute)")
                    ship.tradeRoute = tr
                    ship.currentStop = 7
                    let stop = ship.stop!
                    steps.append("assigned \(ship.currentStop) \(stop.location?.id ?? "null")"
                        + " \(ship.couldMove) \(ship.followingTradeRoute) \(ship.goingToDestination)"
                        + " \(ship.atStop(stop)) \(idList(tr.assignedUnits))")
                    ship.currentStop = 2
                    let current = ship.currentStops!.map {
                        "\($0.location?.id ?? "null") \($0.hasWork(ship, 0)) \($0.hasWork(ship, 3))"
                    }
                    steps.append("stops \(javaList(current))")
                    steps.append("tradeLocation \((ship.tradeLocation as? FreeColObject)?.id ?? "null")")
                }
                tr.removeMatchingStops(colonies[1].tile)
                steps.append("removed \(tr.stopCount)")
                steps.append("dropped \(idList(p.removeTradeRoute(tr))) \(p.tradeRouteCount)")
                m["tradeRoute"] = .array(steps.map(JSONValue.string))
            }
            ret[p.id!] = .object(m)
        }

        // Native trade with the first loaded trading unit.
        let trader = objects(game, Unit.self).first {
            $0.tile != nil && ($0.owner?.isEuropean ?? false) && $0.isTradingUnit && $0.hasGoodsCargo
        }
        var sessions: [String: JSONValue] = [:]
        if let trader {
            for settlement in objects(game, IndianSettlement.self) {
                let nt = NativeTrade(unit: trader, indianSettlement: settlement)
                var steps: [String] = []
                steps.append("\(nt.key) \(nt.canBuy) \(nt.canSell) \(nt.canGift) \(nt.isDone) \(nt.hasNotTraded)")
                nt.initialize()
                for (i, nti) in nt.settlementToUnit.enumerated() {
                    nti.price = i * 7 - 3
                    nti.haggleCount = i % 2
                }
                for (i, nti) in nt.unitToSettlement.enumerated() { nti.price = i * 5 }
                steps.append("\(nt.canBuy) \(nt.canSell) \(nt.canGift) \(nt.isDone)")
                steps.append("toUnit \(javaList(tradeItems(nt.settlementToUnit, trader.owner!)))")
                steps.append("toSettlement \(javaList(tradeItems(nt.unitToSettlement, trader.owner!)))")
                nt.limitSettlementToUnit(1)
                steps.append("limited \(javaList(tradeItems(nt.settlementToUnit, settlement.owner!)))")
                nt.buy = false
                nt.sell = false
                steps.append("\(nt.canBuy) \(nt.canSell) \(nt.isDone) \(nt.hasNotTraded)"
                    + " \(NativeTrade.haggleUp(97)) \(NativeTrade.haggleDown(97))")
                sessions[settlement.id!] = .array(steps.map(JSONValue.string))
            }
        }
        ret["nativeTrade"] = .object(sessions)
        return .object(ret)
    }

    // MARK: Paths and combat (MapOracle.paths, combat, visibility)

    static func keyString(_ t: Tile?) -> String { t.map(key) ?? "null" }

    static func path(_ p: PathNode?) -> JSONValue {
        guard let p else { return .null }
        return .string(pathString(p))
    }

    static func pathString(_ p: PathNode?) -> String {
        guard let p else { return "null" }
        var s = ""
        var n: PathNode? = p
        while let node = n {
            s += "\(node.location?.id ?? "null"),\(node.movesLeft),\(node.turns),\(node.isOnCarrier ? 1 : 0);"
            n = node.next
        }
        return s + " total=\(p.totalTurns) length=\(p.length) carrier=\(p.usesCarrier)"
            + " drop=\(p.transportDropTurns) cost=\(p.lastNode.cost)"
    }

    static func paths(_ game: Game) -> JSONValue {
        let map = game.map!
        var circles: [String: JSONValue] = [:]
        for t in sampleTiles(map) {
            let middle = map.tile(map.width / 2, map.height / 2)!
            circles[key(t)] = .string("\(keyString(map.searchCircle(t, GoalDeciders.simpleHighSeas(), 5)))"
                + " \(keyString(map.searchCircle(t, GoalDeciders.corner(), 6)))"
                + " \(keyString(map.searchCircle(t, GoalDeciders.adjacentLocation(middle), 8)))")
        }
        var units: [String: JSONValue] = [:]
        var natives = 0
        // The searches to each neighbour are slow, so only for a few
        // land units of each player.
        var neighbourSearches: [ObjectIdentifier: Int] = [:]
        let allUnits = objects(game, Unit.self)
        for u in allUnits {
            guard let owner = u.owner, let location = u.location, !u.isDisposed else { continue }
            if !owner.isEuropean {
                if natives >= 12 || u.tile == nil { continue }
                natives += 1
                var m: [String: JSONValue] = [:]
                if let home = u.homeIndianSettlement { m["home"] = path(u.findPath(home)) }
                m["nearest"] = path(u.findOurNearestSettlement())
                if let colony = game.allColonies(excluding: nil).first {
                    m["colony"] = .string("\(pathString(u.findPath(colony))) \(u.turnsToReach(colony))")
                }
                units[u.id!] = .object(m)
                continue
            }
            var m: [String: JSONValue] = [:]
            m["start"] = locId(u.pathStartLocation)
            for c in owner.colonyList {
                m["to " + c.id!] = .string("\(pathString(u.findPath(c))) \(u.turnsToReach(c))")
            }
            if let europe = owner.europe { m["toEurope"] = path(u.findPath(europe)) }
            if let entry = owner.entryTile { m["toEntry"] = path(u.findPath(entry)) }
            m["nearestSettlement"] = path(u.findOurNearestSettlement())
            m["nearestOther"] = path(u.findOurNearestOtherSettlement())
            m["trivial"] = path(u.trivialPath)
            if u.isNaval {
                m["nearestPort"] = path(u.findOurNearestPort())
                if u.hasTile { m["repair"] = locId(u.repairLocation) }
                m["entries"] = .array(owner.colonyList.map { .string(keyString(u.bestEntryTile($0.tile!))) })
            } else if u.hasTile {
                if let carrier = allUnits.first(where: {
                    $0.owner === owner && $0.isNaval && $0.hasTile && $0.couldCarry(u)
                }) {
                    for c in owner.colonyList {
                        m["carried " + c.id!] = path(u.findPath(location, c, carrier))
                    }
                    m["takeTransport"] = .bool(u.shouldTakeTransport(to: owner.europe))
                }
                let searches = neighbourSearches[ObjectIdentifier(owner)] ?? 0
                if let far = owner.colonyList.first(where: { $0.tile !== u.tile }), searches < 4 {
                    neighbourSearches[ObjectIdentifier(owner)] = searches + 1
                    m["intermediate"] = path(u.findIntermediatePort(far))
                    m["neighbour"] = path(u.findPathToNeighbour(location, far.tile!, nil, nil))
                }
            }
            if u.isOnCarrier && u.hasTile, let carrier = u.carrier {
                for c in owner.colonyList { m["aboard " + c.id!] = path(u.findPath(location, c, carrier)) }
            }
            if u.isAtSea { m["resolve"] = locId(u.resolveDestination()) }
            if u.hasTile { m["danger"] = path(u.searchForDanger(3, 0.3)) }
            units[u.id!] = .object(m)
        }
        return .object(["circles": .object(circles), "units": .object(units)])
    }

    static func modifierList(_ mods: [Modifier]) -> String {
        javaList(Modifier.sortedForApplication(mods))
    }

    static func range(_ r: RandomRange?) -> String {
        r.map { "\($0.probability)/\($0.minimum)/\($0.maximum)/\($0.factor)" } ?? "null"
    }

    static func double(_ d: Double) -> String { JavaNumberFormat.string(d) }

    static func combat(_ game: Game) -> JSONValue {
        let cm = game.combatModel
        let hp = HitpointsCombatModel()
        let allUnits = objects(game, Unit.self)
        var measures: [String: JSONValue] = [:]
        for u in allUnits where u.location != nil {
            measures[u.id!] = .string("\(double(cm.offencePower(u, nil))) \(double(cm.defencePower(nil, u)))"
                + " \(modifierList(cm.offensiveModifiers(u, nil)))"
                + " \(modifierList(cm.defensiveModifiers(nil, u)))")
        }

        var attacks: [String: JSONValue] = [:]
        var seed: Int64 = 0
        for a in allUnits where a.hasTile && a.isOffensiveUnit {
            var m: [String: JSONValue] = [:]
            for t in a.tile!.surroundingTiles(1, 3) {
                var v: [String] = []
                if let d = t.defendingUnit(a), d.owner !== a.owner {
                    v.append("\(d.id!) \(double(cm.calculateCombatOdds(a, d).win))"
                        + " \(double(cm.offencePower(a, d))) \(double(cm.defencePower(a, d)))"
                        + " \(a.canAttack(d)) \(cm.combatIsAmphibious(a, d))")
                    v.append(modifierList(cm.offensiveModifiers(a, d)))
                    v.append(modifierList(cm.defensiveModifiers(a, d)))
                    for _ in 0..<3 {
                        v.append(javaList(cm.generateAttackResult(JavaRandom(seed: seed), a, d).effects))
                        seed += 1
                    }
                    let r = hp.generateAttackResult(JavaRandom(seed: seed), a, d)
                    seed += 1
                    v.append("\(javaList(r.effects)) \(r.attackerHitpointsAfter) \(r.defenderHitpointsAfter)")
                }
                if let s = t.settlement, s.owner !== a.owner {
                    v.append("settlement \(double(cm.calculateCombatOdds(a, s).win))"
                        + " \(double(cm.offencePower(a, s))) \(double(cm.defencePower(a, s)))"
                        + " \(modifierList(cm.defensiveModifiers(a, s)))")
                }
                if !v.isEmpty {
                    v.append("ranged \(a.canAttackRanged(t))")
                    m[key(t)] = .array(v.map(JSONValue.string))
                }
            }
            if !m.isEmpty { attacks[a.id!] = .object(m) }
        }

        var bombards: [String: JSONValue] = [:]
        for s in objects(game, Settlement.self) {
            var v: [String] = []
            for t in s.tile!.surroundingTiles(1, 1) {
                for u in t.unitList where u.isNaval && u.owner !== s.owner {
                    let effects = cm.generateAttackResult(JavaRandom(seed: seed), s, u).effects
                    seed += 1
                    v.append("\(u.id!) \(double(cm.calculateCombatOdds(s, u).win))"
                        + " \(double(cm.offencePower(s, u))) \(double(cm.defencePower(s, u)))"
                        + " \(javaList(effects)) \(t.isDangerousToShip(u))")
                }
            }
            if !v.isEmpty { bombards[s.id!] = .array(v.map(JSONValue.string)) }
        }

        // Duels: one unit of each owner, type and role against every
        // other player's, with a few seeds each.
        var repsByKey: [String: Unit] = [:]
        for u in allUnits where u.hasTile {
            let k = "\(u.owner?.id ?? "null") \(u.type?.id ?? "null") \(u.role?.id ?? "null")"
            if repsByKey[k] == nil { repsByKey[k] = u }
        }
        let reps = repsByKey.keys.sorted(by: javaOrder).map { repsByKey[$0]! }
        var duels: [String: JSONValue] = [:]
        for a in reps where a.isOffensiveUnit {
            var v: [String] = []
            for d in reps where d.owner !== a.owner {
                var s = d.id!
                for _ in 0..<4 {
                    s += " " + javaList(cm.generateAttackResult(JavaRandom(seed: seed), a, d).effects)
                    seed += 1
                }
                v.append(s)
            }
            duels[a.id!] = .array(v.map(JSONValue.string))
        }
        var shots: [String: JSONValue] = [:]
        for st in objects(game, Settlement.self) {
            var v: [String] = []
            for d in reps where d.isNaval && d.owner !== st.owner {
                let r1 = cm.generateAttackResult(JavaRandom(seed: seed), st, d).effects
                seed += 1
                let r2 = hp.generateAttackResult(JavaRandom(seed: seed), st, d).effects
                seed += 1
                v.append("\(d.id!) \(double(cm.offencePower(st, d))) \(javaList(r1)) \(javaList(r2))")
            }
            if !v.isEmpty { shots[st.id!] = .array(v.map(JSONValue.string)) }
        }

        let brave = allUnits.first { $0.hasTile && $0.isOffensiveUnit && ($0.owner?.isIndian ?? false) }
        let soldier = allUnits.first { $0.hasTile && $0.isOffensiveUnit && ($0.owner?.isEuropean ?? false) }
        var defence: [String: JSONValue] = [:]
        for c in objects(game, Colony.self) {
            var v: [String] = []
            v.append("\(double(c.totalDefencePower)) \(double(c.defenceRatio)) \(c.isBadlyDefended)"
                + " \(c.isVeryWellDefended)")
            v.append("\(c.defendingUnit(nil)?.id ?? "null") \(c.tile!.defendingUnit(nil)?.id ?? "null")")
            if let brave {
                v.append("\(c.tile!.defendingUnit(brave)?.id ?? "null") \(c.canBePillaged(brave))"
                    + " \(range(c.plunderRange(brave))) \(c.plunder(brave, JavaRandom(seed: 9)))")
            }
            defence[c.id!] = .array(v.map(JSONValue.string))
        }
        if let soldier {
            for s in objects(game, IndianSettlement.self) {
                defence[s.id!] = .string("\(s.defendingUnit(soldier)?.id ?? "null")"
                    + " \(s.tile!.defendingUnit(soldier)?.id ?? "null") \(double(s.defenceRatio))"
                    + " \(s.isBadlyDefended) \(range(s.plunderRange(soldier)))"
                    + " \(s.plunder(soldier, JavaRandom(seed: 11)))")
            }
        }

        var players: [String: JSONValue] = [:]
        for p in game.livePlayers {
            var v: [String] = []
            v.append("\(p.calculateStrength(naval: true)) \(p.calculateStrength(naval: false))"
                + " \(double(p.rebelStrengthRatio(naval: true))) \(double(p.rebelStrengthRatio(naval: false)))")
            if let monarch = p.monarch {
                var i: Int64 = 0
                for o in game.liveEuropeanPlayers where o !== p {
                    v.append("\(o.id!) \(javaList(monarch.warSupport(o, JavaRandom(seed: 31 + i))))")
                    i += 1
                }
            }
            if p.isEuropean {
                for t in sampleTiles(game.map!) {
                    v.append("\(key(t)) \(javaList(t.safestSurroundingLandTiles(p).map(key)))"
                        + " \(keyString(t.bestDisembarkTile(p))) \(keyString(t.safeTile(p, JavaRandom(seed: 5))))")
                }
            }
            players[p.id!] = .array(v.map(JSONValue.string))
        }
        return .object(["measures": .object(measures), "attacks": .object(attacks), "bombards": .object(bombards),
                        "duels": .object(duels), "shots": .object(shots),
                        "defence": .object(defence), "players": .object(players)])
    }

    static func visibility(_ game: Game) -> JSONValue {
        let tiles = game.map!.tiles
        var ret: [String: JSONValue] = [:]
        for p in game.liveEuropeanPlayers {
            var v: [String] = []
            v.append("explored \(tiles.filter { $0.isExploredBy(p) }.count)")
            v.append("visible \(p.visibleTileSet.count)")
            v.append(javaList(sampleTiles(game.map!).map { "\(key($0))=\(p.canSee($0))" }))
            v.append("explored after \(tiles.filter { $0.isExploredBy(p) }.count)")
            v.append("units \(objects(game, Unit.self).filter { p.canSeeUnit($0) }.count)")
            ret[p.id!] = .array(v.map(JSONValue.string))
        }
        return .object(ret)
    }

    static func tradeItems(_ items: [NativeTradeItem], _ player: Player) -> [String] {
        items.map { nti in
            let g = nti.goods!
            return "\(nti.id ?? "null") \(g.amount) \(g.type?.id ?? "null") \(nti.price) \(nti.haggleCount)"
                + " \(nti.priceIsSet) \(nti.priceIsValid) \(nti.source?.id ?? "null")"
                + " \(nti.destination?.id ?? "null") \(nti.isValid) \(nti.evaluateFor(player))"
        }
    }

    static func targetTiles(_ game: Game) -> [Tile] {
        game.map!.tiles.filter { $0.hasSettlement || $0.firstUnit != nil }
    }

    static func unitLocations(_ game: Game) -> JSONValue {
        let spec = game.specification!
        var ret: [String: JSONValue] = [:]
        let allUnits = objects(game, Unit.self)
        for ul in objects(game, UnitLocation.self) where !(ul is Tile) || ul.unitCount > 0 {
            let own = ul is Tile || ul is Unit || ul is HighSeas
            var m: [String: JSONValue] = [
                "units": .array(ul.unitList.map(id)),
                "unitCount": int(ul.unitCount),
                "totalUnitCount": int(ul.totalUnitCount),
                "firstUnit": id(ul.firstUnit),
                "lastUnit": id(ul.lastUnit),
                "navalUnits": .array(ul.navalUnits.map(id)),
                "carrierWithSpace": .string("\(ul.hasCarrierWithSpace(1)) \(ul.hasCarrierWithSpace(2))"
                    + " \(ul.hasCarrierWithSpace(6))"),
                "tile": keyOrNull(ul.tile),
                "settlement": id(ul.settlement),
                "colony": id(ul.colony),
                "indianSettlement": id(ul.indianSettlement),
                "goodsContainer": id(ul.goodsContainer),
            ]
            if let gl = ul as? GoodsLocation {
                m["goods"] = .array(gl.goodsList.map { .string(goodsDescription($0)) })
                m["compactGoods"] = .array(gl.compactGoodsList.map { .string(goodsDescription($0)) })
            }
            if own {
                m["spaceTaken"] = int(ul.spaceTaken)
                m["unitCapacity"] = int(ul.unitCapacity)
                m["empty"] = .bool(ul.isEmpty)
                m["full"] = .bool(ul.isFull)
                m["rank"] = int(ul.rank)
                m["up"] = locId(ul.up())
                m["toShortString"] = .string(ul.shortDescription)
                var noAdd: [String: JSONValue] = [:]
                // And the first unit of another owner, if any.
                if let here = ul.firstUnit?.owner,
                   let u = allUnits.first(where: { $0.owner !== here }) {
                    noAdd["stranger"] = .string("\(u.id!) \(ul.noAddReason(u)) \(ul.canAdd(u))")
                }
                for u in ul.tile?.unitList ?? ul.unitList {
                    noAdd[u.id!] = .string("\(ul.noAddReason(u)) \(ul.canAdd(u))")
                    for v in u.unitList {
                        noAdd[v.id!] = .string("\(ul.noAddReason(v)) \(ul.canAdd(v))")
                    }
                }
                if let unit = ul as? Unit, unit.canCarryGoods {
                    for gt in spec.storableGoodsTypeList {
                        for n in [1, 100, 250, 1000] {
                            let g = Goods(game: game, location: nil, type: gt, amount: n)
                            noAdd["\(gt.id!):\(n)"] = .string("\(ul.noAddReason(g)) \(ul.canAdd(g))")
                        }
                    }
                }
                m["noAdd"] = .object(noAdd)
            }
            if let hs = ul as? HighSeas {
                m["destinations"] = .string(hs.destinationsDescription)
            }
            ret[ul.id!] = .object(m)
        }
        return .object(ret)
    }

    /// Java's List.toString of goods strings.
    static func goodsList(_ list: [AbstractGoods]) -> String {
        "[" + list.map { "\($0.type?.id ?? "null"):\($0.amount)" }.joined(separator: ", ") + "]"
    }

    static func productionTypeString(_ pt: ProductionType?) -> JSONValue {
        guard let pt else { return .null }
        return .string((pt.unattended ? "unattended" : "worked") + " \(pt.productionLevel ?? "null")"
            + " in=\(goodsList(pt.inputs)) out=\(goodsList(pt.outputs))")
    }

    static func productionInfo(_ pi: ProductionInfo?) -> JSONValue {
        guard let pi else { return .null }
        return .object([
            "production": goods(pi.production),
            "consumption": goods(pi.consumption),
            "maximumProduction": goods(pi.maximumProduction),
            "maximumConsumption": goods(pi.maximumConsumption),
        ])
    }

    static func occupation(_ o: Occupation?) -> String {
        guard let o else { return "null" }
        let pt = productionTypeString(o.productionType).stringValue ?? "null"
        return "\(o.workLocation?.id ?? "null") \(pt) \(o.workType?.id ?? "null")"
    }

    static func consumer(_ c: Consumer) -> JSONValue {
        if let o = c as? FreeColObject { return id(o) }
        return .string("BuildQueue:\(c.consumerPriority)")
    }

    static func sortedFeatures(_ items: [CustomStringConvertible]) -> JSONValue {
        .array(items.map { "\($0)" }.sorted(by: javaOrder).map(JSONValue.string))
    }

    static func colonies(_ game: Game) -> JSONValue {
        let spec = game.specification!
        let colonist = spec.defaultUnitType
        var ret: [String: JSONValue] = [:]
        for c in objects(game, Colony.self) {
            let owner = c.owner!
            var flags: [String] = []
            func flag(_ name: String, _ value: Bool) { if value { flags.append(name) } }
            flag("canReducePopulation", c.canReducePopulation)
            flag("undead", c.isUndead)
            flag("underSiege", c.isUnderSiege)
            flag("connectedPort", c.isConnectedPort)
            flag("capital", c.isCapital)
            flag("landLocked", c.isLandLocked)
            flag("canBombardEnemyShip", c.canBombardEnemyShip)
            flag("stockade", c.hasStockade)
            flag("canBePlundered", c.canBePlundered)
            flag("canBuild", c.canBuild)
            var m: [String: JSONValue] = [
                "name": string(c.name),
                "owner": id(owner),
                "tile": keyOrNull(c.tile),
                "settlementType": id(c.type),
                "established": int(c.established.number),
                "sonsOfLiberty": int(c.sonsOfLiberty),
                "liberty": int(c.liberty),
                "immigration": int(c.immigration),
                "productionBonus": int(c.productionBonus),
                "displayUnitCount": int(c.displayUnitCount),
                "apparentUnitCount": int(c.apparentUnitCount),
                "unitCount": int(c.unitCount),
                "units": .array(c.unitList.map(id)),
                "buildings": .array(c.buildings.map(id)),
                "colonyTiles": .array(c.colonyTiles.map(id)),
                "allWorkLocations": .array(c.allWorkLocations.map(id)),
                "availableWorkLocations": .array(c.availableWorkLocations.map(id)),
                "currentWorkLocations": .array(c.currentWorkLocations.map(id)),
                "ownedTiles": .array(c.ownedTiles.map(key).sorted(by: javaOrder).map(JSONValue.string)),
                "buildQueue": .array(c.buildQueue.values.map(id)),
                "populationQueue": .array(c.populationQueue.values.map(id)),
                "currentlyBuilding": id(c.currentlyBuilding),
                "warehouseCapacity": int(c.warehouseCapacity),
                "upkeep": int(c.upkeep),
                "foodProduction": int(c.foodProduction),
                "foodConsumption": int(c.foodConsumption),
                "starvationTurns": int(c.starvationTurns),
                "newColonistTurns": int(c.newColonistTurns),
                "preferredSizeChange": int(c.preferredSizeChange),
                "unitsToAdd": int(c.unitsToAdd),
                "unitsToRemove": int(c.unitsToRemove),
                "rebelHelper": .string("[" + c.rebelHelper(5).map(String.init).joined(separator: ", ") + "] ["
                    + c.rebelHelper(37).map(String.init).joined(separator: ", ") + "]"),
                "governmentChange": .array((1...12).map { int(c.governmentChange($0)) }),
                "flags": .array(flags.map(JSONValue.string)),
                "highSeasCount": int(c.highSeasCount),
                "radius": int(c.radius),
                "lineOfSight": int(c.lineOfSight),
                "stockadeKey": string(c.stockadeKey),
                "warehouse": id(c.warehouse),
                "bestDefenderType": id(c.bestDefenderType),
                "burnableBuildings": .array(c.burnableBuildings.map(id)),
                "lootableGoods": .array(c.lootableGoodsList.map { .string(goodsDescription($0)) }),
                "teachers": .array(c.teachers.map(id)),
                "consumers": .array(c.consumers.map(consumer)),
                "abilities": sortedFeatures(c.sortedAbilities),
                "modifiers": sortedFeatures(c.sortedModifiers),
                "disasters": .array(c.disasterChoices.map { .string("\($0.object.id ?? "null"):\($0.probability)") }),
                "buildableUnits": .array(c.buildableUnits.map(id)),
                "tileImprovementSuggestions": .array(c.tileImprovementSuggestions.map {
                    .string("\(key($0.tile)) \($0.tileImprovementType?.id ?? "null") \($0.amount)")
                }),
            ]
            var goodsValues: [String: JSONValue] = [:]
            for gt in spec.goodsTypeList {
                goodsValues[gt.id!] = .array([
                    c.goodsCount(gt), c.netProduction(of: gt), c.adjustedNetProduction(of: gt),
                    c.totalProduction(of: gt), c.consumption(of: gt),
                    c.isProducing(gt) ? 1 : 0, c.isConsuming(gt) ? 1 : 0, c.canProduce(gt) ? 1 : 0,
                    c.canBreed(gt) ? 1 : 0, c.goodsUseful(gt) ? 1 : 0,
                ].map(int))
            }
            m["goods"] = .object(goodsValues)
            var exports: [String: JSONValue] = [:]
            for gt in spec.goodsTypeList {
                let ed = c.exportData(gt)
                exports[gt.id!] = .string("\(ed.exported) \(ed.highLevel) \(ed.lowLevel) \(ed.importLevel)"
                    + " \(ed.exportLevel) \(c.exportAmount(gt, 1)) \(c.importAmount(gt, 1))")
            }
            m["exports"] = .object(exports)

            let buildables: [BuildableType] = spec.buildingTypeList + spec.unitTypeList + spec.rolesList
            var build: [String: JSONValue] = [:]
            for bt in buildables {
                var v = "\(c.noBuildReason(bt, nil))"
                if bt.needsGoodsToBuild {
                    let needed = AbstractGoods(nil, 0)
                    let turns = c.turnsToComplete(bt, needed: needed)
                    let neededString = needed.type == nil ? "null" : "\(needed.type!.id!):\(needed.amount)"
                    v += " \(turns) \(neededString) \(goodsList(c.requiredGoods(bt)))"
                        + " \(goodsList(c.fullRequiredGoods(bt)))"
                }
                if let b = bt as? BuildingType { v += " auto=\(c.isAutomaticBuild(b))" }
                build[bt.id!] = .string(v)
            }
            m["build"] = .object(build)

            var work: [String: JSONValue] = [:]
            for u in c.unitList {
                let choices: [JSONValue] = [false, true].map { user in
                    .array(c.workTypeChoices(u, userMode: user).map { .array($0.map(id)) })
                }
                work[u.id!] = .object([
                    "choices": .array(choices),
                    "workLocationFor": id(c.workLocation(for: u)),
                    "workLocationForFood": id(c.workLocation(for: u, spec.primaryFoodType)),
                    "betterExpert": id(c.betterExpert(u)),
                    "findTeacher": id(c.findTeacher(u)),
                    "findStudent": id(c.findStudent(u)),
                    "canTrain": .bool(c.canTrain(u)),
                    "consumption": productionInfo(c.productionInfo(of: u)),
                ])
            }
            m["work"] = .object(work)
            m["buildQueueInfo"] = productionInfo(c.productionInfo(of: c.buildQueue))

            var claims: [String: JSONValue] = [:]
            for ct in c.colonyTiles {
                guard let t = ct.workTile else { continue }
                claims[key(t)] = .string("\(owner.canClaimForSettlementReason(t)) \(owner.landPrice(t))"
                    + " \(owner.canClaimForImprovement(t)) \(t.isInUse) \(t.isOccupied)")
            }
            m["claims"] = .object(claims)
            let other = game.liveEuropeanPlayers.first { $0 !== owner }
            m["value"] = .string("\(c.priceForBuilding) \(c.canPayToFinishBuilding) \(c.evaluateFor(owner))"
                + " \(other.map { "\(c.evaluateFor($0))" } ?? "null")")

            var wls: [String: JSONValue] = [:]
            for wl in c.allWorkLocations { wls[wl.id!] = workLocation(game, c, wl, colonist) }
            m["workLocations"] = .object(wls)
            ret[c.id!] = .object(m)
        }
        return .object(ret)
    }

    static func indianSettlements(_ game: Game) -> JSONValue {
        let spec = game.specification!
        var ret: [String: JSONValue] = [:]
        for s in objects(game, IndianSettlement.self) {
            var contact: [String: JSONValue] = [:]
            for p in game.players {
                let t = s.alarm(p)
                contact[p.id!] = .string("\(s.contactLevel(p)) \(s.hasContacted(p)) \(s.hasVisited(p))"
                    + " \(s.hasScouted(p)) \(s.worthScouting(p)) \(s.hasMissionary(p)) "
                    + (t.map { "\($0.value) \($0.level) \($0.key)" } ?? "null"))
            }
            var goodsValues: [String: JSONValue] = [:]
            for gt in spec.goodsTypeList {
                goodsValues[gt.id!] = .array([
                    s.goodsCount(gt), s.totalProduction(of: gt), s.maximumProduction(gt),
                    s.wantedGoodsAmount(gt), s.priceToBuy(gt, 100), s.priceToBuy(gt, 37),
                    s.priceToSell(gt, 100), s.willSell(gt) ? 1 : 0, s.exportAmount(gt, 1),
                    s.importAmount(gt, 1),
                ].map(int))
            }
            var m: [String: JSONValue] = [
                "name": string(s.name),
                "owner": id(s.owner),
                "settlementType": id(s.type),
                "learnableSkill": id(s.learnableSkill),
                "wantedGoods": .array(s.wantedGoods.map(id)),
                "wantedGoodsCount": int(s.wantedGoodsCount),
                "missionary": id(s.missionary),
                "convertProgress": int(s.convertProgress),
                "lastTribute": int(s.lastTribute),
                "mostHated": id(s.mostHated),
                "ownedUnits": .array(s.ownedUnitList.map(id)),
                "units": .array(s.unitList.map(id)),
                "ownedTiles": .array(s.ownedTiles.map(key).sorted(by: javaOrder).map(JSONValue.string)),
                "missionaryLineOfSight": int(s.missionaryLineOfSight),
                "missionaryVisibleTiles": int(s.missionaryVisibleTiles.count),
                "requiredDefenders": int(s.requiredDefenders),
                "defenceRatio": .decimal(s.defenceRatio),
                "badlyDefended": .bool(s.isBadlyDefended),
                "capital": .bool(s.isCapital),
                "radius": int(s.radius),
                "lineOfSight": int(s.lineOfSight),
                "goodsCapacity": int(s.goodsCapacity),
                "hasAnyScouted": .bool(s.hasAnyScouted),
                "abilities": sortedFeatures(s.sortedAbilities),
                "modifiers": sortedFeatures(s.sortedModifiers),
                "toString": .string(s.description),
                "contact": .object(contact),
                "goods": .object(goodsValues),
                "sellGoods": .array(s.sellGoods(nil).map { .string(goodsDescription($0)) }),
            ]
            if let trader = s.missionary ?? s.unitList.first {
                m["sellGoodsTo"] = .array(s.sellGoods(trader).map { .string(goodsDescription($0)) })
            }
            m["randomGift"] = s.randomGift(JavaRandom(seed: 7)).map { .string(goodsDescription($0)) } ?? .null
            s.updateWantedGoods()
            m["updatedWantedGoods"] = .array(s.wantedGoods.map(id))
            ret[s.id!] = .object(m)
        }
        return .object(ret)
    }

    static func workLocation(_ game: Game, _ c: Colony, _ wl: WorkLocation, _ colonist: UnitType?) -> JSONValue {
        let spec = game.specification!
        var flags: [String] = []
        func flag(_ name: String, _ value: Bool) { if value { flags.append(name) } }
        flag("available", wl.isAvailable)
        flag("current", wl.isCurrent)
        flag("canBeWorked", wl.canBeWorked)
        flag("canTeach", wl.canTeach)
        flag("canAutoProduce", wl.canAutoProduce)
        flag("hasInputs", wl.hasInputs)
        flag("hasOutputs", wl.hasOutputs)
        flag("empty", wl.isEmpty)
        flag("full", wl.isFull)
        flag("productive", c.isProductive(wl))
        var m: [String: JSONValue] = [
            "class": .string(wl is Building ? "Building" : "ColonyTile"),
            "toString": .string(wl.description),
            "units": .array(wl.unitList.map(id)),
            "unitCapacity": int(wl.unitCapacity),
            "evaluateFor": int(wl.evaluateFor(c.owner!)),
            "level": int(wl.level),
            "productionType": productionTypeString(wl.productionType),
            "bestProductionType": productionTypeString(wl.bestProductionType(unattended: wl.isEmpty,
                                                                                 wl.currentWorkType)),
            "availableProductionTypes": .array(wl.availableProductionTypes(unattended: false)
                .map(productionTypeString)),
            "currentWorkType": id(wl.currentWorkType),
            "noWorkReason": .string("\(wl.noWorkReason)"),
            "workTile": keyOrNull(wl.workTile),
            "expertUnitType": id(wl.expertUnitType),
            "competenceFactor": float(wl.competenceFactor),
            "rebelFactor": float(wl.rebelFactor),
            "rank": int(wl.rank),
            "up": locId(wl.up()),
            "toShortString": .string(wl.shortDescription),
            "flags": .array(flags.map(JSONValue.string)),
            "productionInfo": productionInfo(wl.productionInfo),
        ]
        var potential: [String: JSONValue] = [:]
        for gt in spec.goodsTypeList {
            var p = [
                wl.potentialProduction(gt, nil), wl.potentialProduction(gt, colonist),
                wl.genericPotential(gt), wl.totalProduction(of: gt), wl.maximumProduction(of: gt),
                wl.produces(gt) ? 1 : 0, wl.productionDeficit(gt)?.amount ?? -1,
            ]
            for u in wl.unitList {
                p.append(wl.unitProduction(u, gt))
                p.append(wl.production(of: u, gt))
            }
            if p.contains(where: { $0 != 0 && $0 != -1 }) { potential[gt.id!] = .array(p.map(int)) }
        }
        m["potential"] = .object(potential)
        var noAdd: [String: JSONValue] = [:]
        for u in c.unitList + (c.tile?.unitList ?? []) { noAdd[u.id!] = .string("\(wl.noAddReason(u))") }
        m["noAdd"] = .object(noAdd)
        let colonistOccupation = wl.occupation(for: nil as UnitType?)
        m["occupationForColonist"] = colonistOccupation == nil ? .null : .string(occupation(colonistOccupation))
        var occupations: [String: JSONValue] = [:]
        for u in c.unitList {
            occupations[u.id!] = .string(occupation(wl.occupation(for: u, userMode: false)) + " | "
                + occupation(wl.occupation(for: u, userMode: true)))
        }
        m["occupations"] = .object(occupations)
        m["suggestions"] = .array(wl.suggestions.map { e in
            let sg = e.suggestion
            return "\(e.unit?.id ?? "null") \(sg.oldType?.id ?? "null") \(sg.newType?.id ?? "null")"
                + " \(sg.goodsType?.id ?? "null") \(sg.amount)"
        }.sorted(by: javaOrder).map(JSONValue.string))
        if let b = wl as? Building {
            m["type"] = id(b.type)
            m["canBuildNext"] = .bool(b.canBuildNext)
            m["canBeDamaged"] = .bool(b.canBeDamaged)
            m["canAddType"] = .array(spec.unitTypeList.filter { b.canAddType($0) }.map(id))
            m["consumedGoods"] = goods(b.consumedGoods)
            m["priority"] = int(b.consumerPriority)
        } else if let ct = wl as? ColonyTile {
            m["centerTile"] = .bool(ct.isColonyCenterTile)
            m["occupyingUnit"] = id(ct.occupyingUnit)
            m["basicProductionInfo"] = productionInfo(ct.basicProductionInfo)
            var improved: [String: JSONValue] = [:]
            for ti in spec.tileImprovementTypeList {
                let n = ct.improvedBy(ti)
                if n != 0 { improved[ti.id!] = int(n) }
            }
            m["improvedBy"] = .object(improved)
        }
        return .object(m)
    }

    static func goodsDescription(_ g: Goods) -> String {
        "\(g) \(g.type?.id ?? "null") \(g.location?.id ?? "null") \(g.owner?.id ?? "null")"
            + " \(g.spaceTaken) \(g.tile.map(key) ?? "null") \(g.isInEurope)"
    }

    /// Java's List.toString of the stored goods.
    static func stored(_ entries: [(type: GoodsType, amount: Int)]) -> String {
        "[" + entries.map { "\($0.type.id ?? "null")=\($0.amount)" }.joined(separator: ", ") + "]"
    }

    static func goodsContainers(_ game: Game) -> JSONValue {
        let spec = game.specification!
        let food = spec.primaryFoodType!
        var ret: [String: JSONValue] = [:]
        let all = objects(game, GoodsContainer.self)
        for gc in all {
            var counts: [String: JSONValue] = [:]
            for gt in spec.goodsTypeList {
                let n = gc.goodsCount(gt), o = gc.oldGoodsCount(gt)
                if n != 0 || o != 0 { counts[gt.id!] = .string("\(n) \(o)") }
            }
            var m: [String: JSONValue] = [
                "stored": .array(gc.storedEntries.map { .string("\($0.type.id ?? "null")=\($0.amount)") }),
                "oldStored": .array(gc.oldStoredEntries.map { .string("\($0.type.id ?? "null")=\($0.amount)") }),
                "toString": .string(gc.description),
                "owner": id(gc.owner),
                "spaceTaken": int(gc.spaceTaken),
                "reachedCapacity": .string("\(gc.hasReachedCapacity(100)) \(gc.hasReachedCapacity(0))"),
                "changed": .bool(gc.hasChanged),
                "goods": .array(gc.goodsList.map { .string(goodsDescription($0)) }),
                "compactGoods": .array(gc.compactGoodsList.map { .string(goodsDescription($0)) }),
                "counts": .object(counts),
            ]
            var steps: [String] = []
            gc.saveState()
            gc.removeAbove(100)
            steps.append("removeAbove \(stored(gc.storedEntries)) \(gc.hasChanged)")
            gc.restoreState()
            steps.append("restore \(stored(gc.storedEntries)) \(gc.hasChanged)")
            let removed = gc.removeGoods(food, 7)
            steps.append("remove \(removed.map(goodsDescription) ?? "null") \(stored(gc.storedEntries))")
            gc.addGoods(food, 250)
            gc.addGoods(spec.getGoodsType("model.goods.horses")!, 30)
            steps.append("add \(stored(gc.storedEntries)) \(gc.spaceTaken)")
            for gt in spec.goodsTypeList where gc.goodsCount(gt) > 0 {
                let r = gc.removeGoods(gt)!
                steps.append("removeAll \(gt.id!) \(goodsDescription(r))")
                break
            }
            gc.setAmount(food, 0)
            steps.append("set \(stored(gc.storedEntries))")
            m["steps"] = .array(steps.map(JSONValue.string))
            ret[gc.id!] = .object(m)
        }
        // Moving goods between the first two containers.
        if all.count >= 2 {
            let a = all[0], b = all[1]
            a.addGoods(food, 120)
            GoodsContainer.moveGoods(a, food, 70, b)
            ret["move"] = .string("\(stored(a.storedEntries)) \(stored(a.oldStoredEntries))"
                + " \(stored(b.storedEntries)) \(stored(b.oldStoredEntries))")
        }
        return .object(ret)
    }

    static func reset(_ map: Map) -> JSONValue {
        map.resetContiguity()
        map.resetHighSeasCount()
        map.resetLayers()
        let state = map.tiles.map {
            JSONValue.string("\($0.contiguity) \($0.highSeasCount)"
                + " \($0.moveToEurope.map { "\($0)" } ?? "null")")
        }
        let layer = "\(map.layer)"
        // High seas placement changes tile types, so record the changes.
        let before = map.tiles.map { $0.type?.id }
        map.resetHighSeas(highSeasDistanceToLand, highSeasMaximumDistanceToEdge)
        var changed: [JSONValue] = []
        for (t, old) in zip(map.tiles, before) where t.type?.id != old {
            changed.append(.string("\(key(t)) \(t.type?.id ?? "null")"))
        }
        // High seas far from land leave ocean on the edges, which
        // counting marks as leading to Europe.
        map.resetHighSeas(20, 1)
        map.resetHighSeasCount()
        let after = map.tiles.map {
            JSONValue.string("\($0.highSeasCount) \($0.moveToEurope.map { "\($0)" } ?? "null")")
        }
        return .object([
            "layer": .string(layer),
            "tiles": .array(state),
            "highSeasChanges": .array(changed),
            "tilesAfterHighSeas": .array(after),
        ])
    }

    // MARK: Helpers

    static func key(_ t: Tile) -> String { "\(t.x),\(t.y)" }
    static func keyOrNull(_ t: Tile?) -> JSONValue { t.map { .string(key($0)) } ?? .null }
    static func keys<S: Sequence>(_ tiles: S) -> JSONValue where S.Element == Tile {
        .array(tiles.map { .string(key($0)) })
    }
    static func id(_ o: FreeColObject?) -> JSONValue { o?.id.map(JSONValue.string) ?? .null }
    static func string(_ s: String?) -> JSONValue { s.map(JSONValue.string) ?? .null }
    static func int(_ i: Int) -> JSONValue { .integer(Int64(i)) }
    static func float(_ f: Float) -> JSONValue { .decimal(Double(JavaNumberFormat.string(f))!) }
    static func javaOrder(_ a: String, _ b: String) -> Bool { JavaString.compare(a, b) < 0 }
    /// Java's List.toString.
    static func list(_ items: [Direction]) -> String {
        "[" + items.map { "\($0)" }.joined(separator: ", ") + "]"
    }
    /// Java's List.toString.
    static func javaList<S: Sequence>(_ items: S) -> String {
        "[" + items.map { "\($0)" }.joined(separator: ", ") + "]"
    }
    static func idList(_ items: [FreeColObject]) -> String {
        javaList(items.map { $0.id ?? "null" })
    }
    static func strings<S: Sequence>(_ items: S) -> JSONValue {
        .array(items.map { .string("\($0)") })
    }
    static func sortedFeatureStrings(_ o: FreeColObject) -> String {
        javaList(o.sortedModifiers.map { "\($0)" }.sorted(by: javaOrder))
    }

    static func goodsString(_ ag: AbstractGoods?) -> JSONValue {
        ag.map { .string("\($0.type?.id ?? "null"):\($0.amount)") } ?? .null
    }
    static func goods(_ list: [AbstractGoods]) -> JSONValue {
        .array(list.map(goodsString))
    }
}

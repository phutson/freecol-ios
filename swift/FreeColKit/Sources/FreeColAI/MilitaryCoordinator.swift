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
import FreeColServer
import FreeColUtil
import FreeColXML

extension AIUnit {
    /// Java's AIUnit.hashCode: the identifier, value, transport and
    /// unit, and the mission, whose hash is always 31 as missions have
    /// no identifier.
    var javaHash: Int32 {
        var hash = id.map(JavaString.hashCode) ?? 31
        hash = 37 &* hash &+ Int32(truncatingIfNeeded: value)
        hash = 37 &* hash &+ (transport?.javaHash ?? 31)
        hash = 37 &* hash &+ unit.javaGameObjectHash
        return 37 &* hash &+ 31
    }
}

/// An object with its Java hash when it was added, compared by identity.
private struct Hashed<T: AnyObject>: Hashable {
    let object: T
    let hash: Int32

    static func == (a: Hashed, b: Hashed) -> Bool { a.object === b.object }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(object)) }
}

/// The order of a Java HashSet the elements are added to in order:
/// one made empty (Collectors.toSet), or copied from a collection of
/// that size (new HashSet<>(c)).
func javaHashSetOrder<T: AnyObject>(_ elements: [T], copied: Bool = false, _ javaHash: (T) -> Int32) -> [T] {
    var set = copied
        ? JavaHashMap<Hashed<T>, Bool>(initialCapacity: max(Int(Float(elements.count) / 0.75) + 1, 16),
                                       javaHash: { $0.hash })
        : JavaHashMap<Hashed<T>, Bool>(javaHash: { $0.hash })
    for e in elements {
        let key = Hashed(object: e, hash: javaHash(e))
        if set[key] == nil { _ = set.put(key, true) }
    }
    return set.keys.map(\.object)
}

/// An insertion-ordered set compared by identity: Java's identity sets
/// in MilitaryCoordinator, whose IdentityHashMap order differs from run
/// to run, as the AI oracle's patch keeps them.
private struct IdentitySet<T: AnyObject> {
    private(set) var elements: [T] = []

    init(_ elements: [T]) {
        for e in elements { insert(e) }
    }

    var isEmpty: Bool { elements.isEmpty }

    func contains(_ e: T) -> Bool { elements.contains { $0 === e } }

    mutating func insert(_ e: T) {
        if !contains(e) { elements.append(e) }
    }

    mutating func remove(_ e: T) {
        elements.removeAll { $0 === e }
    }
}

/// A colony's defensive zone (server/ai/military/DefensiveZone): the
/// land within three tiles, the potential enemies there, and its
/// neighbouring zones.
final class DefensiveZone {
    let aiColony: AIColony
    /// In Java's HashSet order.
    private var potentialEnemies: [Unit] = []
    private var potentialEnemySettlements: [Settlement] = []
    var exposedLand = false
    var exposedWater = false
    private(set) var neighbours: [DefensiveZone] = []
    var enemiesInNeighbour = false

    init(_ aiColony: AIColony) {
        self.aiColony = aiColony
    }

    /// Java's hashCode (Objects.hash of the AI colony).
    var javaHash: Int32 { 31 &+ (aiColony.id.map(JavaString.hashCode) ?? 31) }

    func addAllPotentialEnemies(_ units: [Unit]) {
        potentialEnemies = javaHashSetOrder(potentialEnemies + units) { $0.javaGameObjectHash }
    }

    func addPotentialEnemySettlement(_ settlement: Settlement) {
        potentialEnemySettlements = javaHashSetOrder(potentialEnemySettlements + [settlement]) {
            $0.javaGameObjectHash
        }
    }

    func addNeighbour(_ zone: DefensiveZone) {
        neighbours = javaHashSetOrder(neighbours + [zone]) { $0.javaHash }
    }

    var isExposed: Bool { exposedLand || exposedWater }

    private var player: Player? { aiColony.colony.owner }

    private func isEnemy(_ owner: Player?) -> Bool { player?.atWar(with: owner) ?? false }

    /// The potential enemies at war with us.
    var enemies: [Unit] {
        javaHashSetOrder(potentialEnemies.filter { isEnemy($0.owner) }) { $0.javaGameObjectHash }
    }

    var numberOfMilitaryEnemies: Int {
        let units = potentialEnemies.filter {
            isEnemy($0.owner) && $0.isOffensiveUnit && !($0.owner?.isIndian ?? false)
        }.count
        let settlements = potentialEnemySettlements.filter { isEnemy($0.owner) && !($0 is IndianSettlement) }.count
        return units + settlements
    }

    /// Java does not check the stance here, so our own colonies count.
    var numberOfPotentialMilitaryEnemies: Int {
        let units = potentialEnemies.filter { $0.isOffensiveUnit && !($0.owner?.isIndian ?? false) }.count
        let settlements = potentialEnemySettlements.filter { !($0 is IndianSettlement) }.count
        return units + settlements
    }
}

/// The defensive zones of a player's colonies
/// (server/ai/military/DefensiveMap), found by spreading out from the
/// colonies over land, nearest first.
final class DefensiveMap {

    private static let zoneSizeTurns = 3

    /// By AI colony, in Java's HashMap order.
    private let zones: [DefensiveZone]

    private init(_ zones: [DefensiveZone]) {
        self.zones = zones
    }

    var defensiveZones: [DefensiveZone] { zones }

    var attackedColonies: [AIColony] { zones.filter { $0.numberOfMilitaryEnemies > 0 }.map(\.aiColony) }

    var threatenedColonies: [AIColony] {
        zones.filter { $0.enemiesInNeighbour || $0.numberOfPotentialMilitaryEnemies > 0 }.map(\.aiColony)
    }

    var coloniesExposedLand: [AIColony] { zones.filter(\.exposedLand).map(\.aiColony) }

    var coloniesExposedWater: [AIColony] { zones.filter(\.exposedWater).map(\.aiColony) }

    private final class SearchNode {
        let tile: Tile
        let previous: SearchNode?
        let turns: Int
        let movesLeft: Int
        let zone: DefensiveZone
        let cost: Int

        init(_ tile: Tile, _ previous: SearchNode?, _ movesLeft: Int, _ turns: Int, _ zone: DefensiveZone,
             _ cost: Int) {
            self.tile = tile
            self.previous = previous
            self.turns = turns
            self.movesLeft = movesLeft
            self.zone = zone
            self.cost = cost
        }
    }

    static func create(_ aiPlayer: EuropeanAIPlayer) -> DefensiveMap {
        let colonies = aiPlayer.aiColonies()
        if colonies.isEmpty { return DefensiveMap([]) }
        let player = aiPlayer.player
        var zonesByColony = JavaHashMap<Hashed<AIColony>, DefensiveZone>(javaHash: { $0.hash })
        var queue = JavaPriorityQueue<SearchNode> { a, b in a.cost < b.cost ? -1 : a.cost > b.cost ? 1 : 0 }
        var openMap: [String: SearchNode] = [:]
        var closedMap: [String: SearchNode] = [:]
        for ac in colonies {
            let zone = DefensiveZone(ac)
            _ = zonesByColony.put(Hashed(object: ac, hash: ac.id.map(JavaString.hashCode) ?? 31), zone)
            if let tile = ac.colony.tile { queue.offer(SearchNode(tile, nil, 1, 0, zone, 0)) }
        }
        let costDecider = CostDeciders.numberOfTiles()
        while let node = queue.poll() {
            let id = node.tile.id ?? ""
            closedMap[id] = node
            if let settlement = node.tile.settlement {
                if player.stance(settlement.owner) != .alliance { node.zone.addPotentialEnemySettlement(settlement) }
            } else {
                let enemyUnits = node.tile.unitList.filter { u in
                    u.owner !== player && player.stance(u.owner) != .alliance
                }
                node.zone.addAllPotentialEnemies(javaHashSetOrder(enemyUnits) { $0.javaGameObjectHash })
            }
            for tile in node.tile.surroundingTiles(1) {
                if !tile.isLand {
                    node.previous?.zone.exposedWater = true
                    continue
                }
                let tid = tile.id ?? ""
                if let closed = closedMap[tid] {
                    if node.zone !== closed.zone { closed.zone.addNeighbour(node.zone) }
                    continue
                }
                let cost = costDecider.cost(nil, node.tile, tile, node.movesLeft)
                let newNode = SearchNode(tile, node, costDecider.movesLeft, node.turns + costDecider.newTurns,
                                         node.zone, node.cost + cost)
                if openMap[tid] != nil { continue }
                if newNode.cost > zoneSizeTurns {
                    node.zone.exposedLand = true
                    continue
                }
                queue.offer(newNode)
                openMap[tid] = newNode
            }
        }
        let zones = zonesByColony.values
        for zone in zones where zone.neighbours.contains(where: { $0.numberOfMilitaryEnemies > 0 }) {
            zone.enemiesInNeighbour = true
        }
        return DefensiveMap(zones)
    }
}

/// Missions for a European player's military units
/// (server/ai/military/MilitaryCoordinator): defenders for the colonies,
/// counterattacks, attacks on enemy settlements with escorts, and the
/// rest defending or wandering.
final class MilitaryCoordinator {

    private let player: EuropeanAIPlayer
    private var unusedUnits: IdentitySet<AIUnit>
    private let ourColonies: [AIColony]
    private var defenders: [ObjectIdentifier: [AIUnit]] = [:]
    private let defensiveMap: DefensiveMap
    private var targetedEnemies = IdentitySet<Unit>([])
    private var targetedEnemySettlements: [ObjectIdentifier: [AIUnit]] = [:]
    private var turnsToReachCache: [String: Int] = [:]

    /// - Parameter militaryUnits: In the order of Java's HashSet of them.
    init(_ player: EuropeanAIPlayer, _ militaryUnits: [AIUnit]) {
        self.player = player
        // Units waiting in Europe with a mission are left to accumulate
        // transport priority.
        unusedUnits = IdentitySet(militaryUnits.filter { !$0.unit.isInEurope || !$0.hasMission })
        ourColonies = player.aiColonies().stableSorted { $0.colony.unitCount > $1.colony.unitCount }
        for c in ourColonies { defenders[ObjectIdentifier(c)] = [] }
        defensiveMap = DefensiveMap.create(player)
    }

    /// Whether the coordinator handles a unit: armed land units, not
    /// scouts.
    static func isUnitHandled(_ u: AIUnit) -> Bool {
        !u.unit.isNaval && u.unit.isOffensiveUnit && !u.unit.hasAbility(Ability.speakWithChief)
    }

    private static func toSet(_ units: [AIUnit]) -> [AIUnit] {
        javaHashSetOrder(units) { $0.javaHash }
    }

    private static func copy(_ units: [AIUnit]) -> [AIUnit] {
        javaHashSetOrder(units, copied: true) { $0.javaHash }
    }

    private static func isArtillery(_ u: Unit) -> Bool { u.hasAbility(Ability.bombard) }

    private static func isDragoon(_ u: Unit) -> Bool { u.isMounted }

    func determineMissions() {
        let units = unusedUnits.elements
        var artilleryUnits = IdentitySet(Self.toSet(units.filter { Self.isArtillery($0.unit) }))
        var dragoonUnits = IdentitySet(Self.toSet(units.filter { Self.isDragoon($0.unit) }))
        var otherMilitaryUnits = IdentitySet(Self.toSet(units.filter {
            !$0.unit.hasAbility(Ability.bombard) && !$0.unit.isMounted
        }))

        // Keep artillery where attacked.
        keepUnitsInColonies(defensiveMap.attackedColonies, &artilleryUnits, Self.always)
        keepUnitsInColonies(defensiveMap.attackedColonies, &dragoonUnits, Self.maxDefenders(1))
        if player.isAggressive {
            let importantWaterColonies = defensiveMap.coloniesExposedWater.filter { $0.colony.unitCount > 3 }
            keepUnitsInColonies(importantWaterColonies, &artilleryUnits, Self.maxArtilleries(1))
            placeUnitsInColonies(importantWaterColonies, &artilleryUnits, Self.maxArtilleries(1))
            placeUnitsInColonies(defensiveMap.attackedColonies, &dragoonUnits, Self.maxDefenders(1))
            placeUnitsInColonies(defensiveMap.attackedColonies, &dragoonUnits, Self.maxDefenders(1))
            keepUnitsInColonies(defensiveMap.threatenedColonies, &dragoonUnits, Self.maxDefenders(1))
            placeUnitsInColonies(defensiveMap.threatenedColonies, &dragoonUnits, Self.maxDefenders(1))
            keepUnitsInColonies(defensiveMap.coloniesExposedWater, &dragoonUnits, Self.maxDefenders(1))
            placeUnitsInColonies(defensiveMap.coloniesExposedWater, &dragoonUnits, Self.maxDefenders(1))
            keepUnitsInColonies(defensiveMap.coloniesExposedLand, &dragoonUnits, Self.maxDefenders(1))
            placeUnitsInColonies(defensiveMap.coloniesExposedLand, &dragoonUnits, Self.maxDefenders(1))
            keepUnitsInColonies(ourColonies, &otherMilitaryUnits, Self.always)
        } else {
            keepUnitsInColonies(ourColonies, &artilleryUnits, Self.maxDefenders(1))
            placeUnitsInColonies(ourColonies, &artilleryUnits, Self.maxDefenders(1))
            keepUnitsInColonies(ourColonies, &dragoonUnits, Self.maxDefenders(1))
            placeUnitsInColonies(ourColonies, &dragoonUnits, Self.maxDefenders(1))
            keepUnitsInColonies(ourColonies, &otherMilitaryUnits, Self.always)
            keepUnitsInColonies(defensiveMap.threatenedColonies, &artilleryUnits, Self.maxArtilleries(3))
            keepUnitsInColonies(defensiveMap.coloniesExposedWater, &artilleryUnits, Self.maxArtilleries(2))
            placeUnitsInColonies(defensiveMap.threatenedColonies, &artilleryUnits, Self.maxArtilleries(2))
        }

        counterattackEnemyValuableUnitsReachableInTurns(&dragoonUnits, 0)
        counterattackEnemyValuableUnitsReachableInTurns(&dragoonUnits, 1)
        counterattackAllEnemyUnitsReachableInTurns(&dragoonUnits, 1)
        counterattackAllEnemyUnitsReachableInTurns(&dragoonUnits, 2)

        attackEnemySettlements(&artilleryUnits, &dragoonUnits)

        keepUnitsInColonies(defensiveMap.attackedColonies, &dragoonUnits, Self.always)
        keepUnitsInColonies(defensiveMap.threatenedColonies, &artilleryUnits, Self.always)
        if player.isAggressive {
            placeUnitsInColonies(defensiveMap.coloniesExposedWater, &artilleryUnits, Self.maxArtilleries(1))
        }
        placeUnitsInColonies(defensiveMap.coloniesExposedWater, &artilleryUnits, Self.maxArtilleries(2))
        keepUnitsInColonies(defensiveMap.threatenedColonies, &dragoonUnits, Self.always)
        keepUnitsInColonies(defensiveMap.coloniesExposedLand, &artilleryUnits, Self.maxArtilleries(2))
        placeUnitsInColonies(defensiveMap.coloniesExposedLand, &dragoonUnits, Self.maxDragoons(2))

        assignDefendClosestColony()
        if let first = ourColonies.first { transportMilitaryUnitsFromEurope(first) }
        assignWanderHostile()
    }

    private func attackEnemySettlements(_ artilleryUnits: inout IdentitySet<AIUnit>,
                                        _ dragoonUnits: inout IdentitySet<AIUnit>) {
        for artillery in Self.copy(artilleryUnits.elements) {
            if dragoonUnits.isEmpty { continue }
            guard let escortTargetTile = artillery.unit.tile else { continue } // No direct transport.
            guard let possibleTarget = UnitSeekAndDestroyMission.findMissionTarget(artillery, 10, true,
                    !player.likesAttackingNatives) as? Settlement else { continue }
            let key = ObjectIdentifier(possibleTarget)
            let attackers = targetedEnemySettlements[key] ?? []
            targetedEnemySettlements[key] = attackers
            if attackers.count > possibleTarget.unitCount { continue } // Enough attackers.
            var escort: AIUnit?
            var escortTurns = Int.max
            for d in dragoonUnits.elements {
                let turns = turnsToReach(d.unit, escortTargetTile)
                if escort == nil || turns < escortTurns {
                    escort = d
                    escortTurns = turns
                }
            }
            guard let escort, escortTurns <= 8 else { continue }
            _ = UnitSeekAndDestroyMission(aiMain, artillery, possibleTarget)
            artilleryUnits.remove(artillery)
            unusedUnits.remove(artillery)
            _ = EscortUnitMission(aiMain, escort, artillery.unit)
            dragoonUnits.remove(escort)
            unusedUnits.remove(escort)
            targetedEnemySettlements[key, default: []].append(artillery)
        }
    }

    private var aiMain: AIMain { player.aiMain }

    private func turnsToReach(_ unit: Unit, _ location: any Location) -> Int {
        let key = (unit.id ?? "") + "," + ((location as? FreeColGameObject)?.id ?? "")
        if let cached = turnsToReachCache[key] { return cached }
        let result = unit.turnsToReach(location)
        turnsToReachCache[key] = result
        return result
    }

    /// Attack an enemy with the first dragoon that reaches it in time.
    /// Java checks the turns of the path's first node, which is always
    /// zero.
    private func counterattack(_ enemy: Unit, _ dragoonUnits: inout IdentitySet<AIUnit>, _ turns: Int) {
        guard let enemyTile = enemy.tile else { return }
        for dragoon in Self.copy(dragoonUnits.elements) {
            guard let tile = dragoon.unit.tile, tile.contiguity == enemyTile.contiguity else { continue }
            if let path = dragoon.unit.findPath(enemyTile), path.turns <= turns {
                _ = UnitSeekAndDestroyMission(aiMain, dragoon, enemy)
                unusedUnits.remove(dragoon)
                dragoonUnits.remove(dragoon)
                targetedEnemies.insert(enemy)
                break
            }
        }
    }

    private func counterattackEnemyValuableUnitsReachableInTurns(_ dragoonUnits: inout IdentitySet<AIUnit>,
                                                                 _ turns: Int) {
        for zone in defensiveMap.defensiveZones {
            let enemies = zone.enemies
            let unprotected = javaHashSetOrder(enemies.filter { u in
                !u.isArmed && u.sortedMilitaryRoles.contains { $0.expertUnit === u.type }
                    && !enemies.contains { $0.tile === u.tile && $0.isOffensiveUnit }
            }) { $0.javaGameObjectHash }
            let enemyArtillery = javaHashSetOrder(enemies.filter(Self.isArtillery)) { $0.javaGameObjectHash }
            for enemy in unprotected { counterattack(enemy, &dragoonUnits, turns) }
            for _ in 0..<2 {
                for enemy in enemyArtillery { counterattack(enemy, &dragoonUnits, turns) }
            }
        }
    }

    private func counterattackAllEnemyUnitsReachableInTurns(_ dragoonUnits: inout IdentitySet<AIUnit>,
                                                            _ turns: Int) {
        for zone in defensiveMap.defensiveZones {
            for enemy in zone.enemies where !targetedEnemies.contains(enemy) {
                counterattack(enemy, &dragoonUnits, turns)
            }
        }
    }

    private func assignDefendClosestColony() {
        for unit in Self.copy(unusedUnits.elements) {
            if player.defendSettlementMission(unit, true, true) != nil { unusedUnits.remove(unit) }
        }
    }

    private func transportMilitaryUnitsFromEurope(_ destination: AIColony) {
        for unit in Self.copy(unusedUnits.elements) where unit.unit.tile == nil {
            _ = DefendSettlementMission(aiMain, unit, destination.colony)
            unusedUnits.remove(unit)
        }
    }

    private func placeUnit(_ aiColonies: [AIColony], _ units: inout IdentitySet<AIUnit>,
                           _ check: ([AIUnit]) -> Bool, _ onlySameTile: Bool) {
        for colony in aiColonies {
            if !check(defenders[ObjectIdentifier(colony)] ?? []) { continue }
            guard let unit = onlySameTile ? findUnitInColony(colony, units) : findUnitClosestToColony(colony, units)
            else { break }
            placeDefender(unit, colony)
            units.remove(unit)
        }
    }

    private func keepUnitsInColonies(_ aiColonies: [AIColony], _ units: inout IdentitySet<AIUnit>,
                                     _ check: ([AIUnit]) -> Bool) {
        placeUnit(aiColonies, &units, check, true)
    }

    private func placeUnitsInColonies(_ aiColonies: [AIColony], _ units: inout IdentitySet<AIUnit>,
                                      _ check: ([AIUnit]) -> Bool) {
        placeUnit(aiColonies, &units, check, false)
    }

    private func assignWanderHostile() {
        for unit in Self.copy(unusedUnits.elements) {
            _ = UnitWanderHostileMission(aiMain, unit)
            unusedUnits.remove(unit)
        }
    }

    private func placeDefender(_ unit: AIUnit, _ colony: AIColony) {
        _ = DefendSettlementMission(aiMain, unit, colony.colony)
        defenders[ObjectIdentifier(colony), default: []].append(unit)
        unusedUnits.remove(unit)
    }

    private func findUnitClosestToColony(_ colony: AIColony, _ units: IdentitySet<AIUnit>) -> AIUnit? {
        for au in units.elements {
            if let m = au.mission as? DefendSettlementMission, m.target === colony.colony { return au }
        }
        guard let tile = colony.colony.tile else { return nil }
        var best: AIUnit?
        var bestTurns = Int.max
        for au in units.elements {
            let turns = turnsToReach(au.unit, tile)
            if best == nil || turns < bestTurns {
                best = au
                bestTurns = turns
            }
        }
        return best
    }

    private func findUnitInColony(_ ac: AIColony, _ units: IdentitySet<AIUnit>) -> AIUnit? {
        units.elements.first { $0.unit.tile != nil && $0.unit.tile === ac.colony.tile }
    }

    private static func maxDefenders(_ count: Int) -> ([AIUnit]) -> Bool { { $0.count < count } }

    private static func maxArtilleries(_ count: Int) -> ([AIUnit]) -> Bool {
        { units in units.filter { isArtillery($0.unit) }.count < count }
    }

    private static func maxDragoons(_ count: Int) -> ([AIUnit]) -> Bool {
        { units in units.filter { isDragoon($0.unit) }.count < count }
    }

    private static var always: ([AIUnit]) -> Bool { { _ in true } }
}

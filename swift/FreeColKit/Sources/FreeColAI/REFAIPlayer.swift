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

/// The REF's computer player (server/ai/REFAIPlayer): the European AI,
/// with a landing chosen before it arrives, its own missions for its
/// units, and a few tweaks.
final class REFAIPlayer: EuropeanAIPlayer {

    /// The most REF units to chase one rebel unit.
    private static let unitUSADThreshold = 5

    private static let seekAndDestroyRange = 12

    /// A target colony, how to get there, and where to land (TargetTuple).
    private final class TargetTuple {
        let colony: Colony
        let path: PathNode?
        var score: Double
        var disembarkTile: Tile?
        var entry: Tile?

        init(_ colony: Colony, _ path: PathNode?, _ score: Double) {
            self.colony = colony
            self.path = path
            self.score = score
            var p = path
            while let node = p {
                if let t = node.tile {
                    entry = t
                    break
                }
                p = node.next
            }
        }
    }

    /// Collects the rebel ships on the sea tiles a search reaches
    /// (REFNavyGoalDecider), in Java's HashSet order.
    private final class NavyGoalDecider: GoalDecider {
        let rebel: Player
        var rebelNavy = JavaHashSet<Unit>(javaHash: { $0.javaGameObjectHash })

        init(_ rebel: Player) {
            self.rebel = rebel
        }

        var goal: PathNode? { nil }
        var hasSubGoals: Bool { true }

        func check(_ unit: Unit?, _ pathNode: PathNode) -> Bool {
            guard let tile = pathNode.tile, !tile.isEmpty, !tile.isLand,
                  rebel.owns(tile.firstUnit) else { return false }
            for u in tile.unitList where u.isOffensiveUnit && u.isNaval && !rebelNavy.contains(u) {
                rebelNavy.insert(u)
            }
            return true
        }
    }

    /// How many REF units are after each target.
    private var targetMap: [ObjectIdentifier: Int] = [:]
    /// Whether the army has landed.
    private var landed = false

    private func incrementTarget(_ loc: (any Location)?) {
        guard let loc else { return }
        targetMap[ObjectIdentifier(loc), default: 0] += 1
    }

    // MARK: Targets

    /// The rebels' colonies (ports, if asked) that a unit can reach by
    /// a carrier, scored, a little at random, and sorted: lowest first,
    /// as Java's natural order of the scores puts them
    /// (findColonyTargets).
    private func findColonyTargets(_ aiu: AIUnit, _ port: Bool, _ aiCarrier: AIUnit) -> [TargetTuple] {
        let unit = aiu.unit, carrier = aiCarrier.unit
        var targets: [TargetTuple] = []
        for rebel in player.rebels {
            for c in port ? rebel.connectedPortList : rebel.colonyList {
                guard let path = unit.findPath(carrier, c, carrier) else { continue }
                targets.append(TargetTuple(c, path,
                                           Double(UnitSeekAndDestroyMission.scorePath(aiu, path, false, false))))
            }
        }
        if targets.isEmpty { return targets }

        // More for drydocks and makers of muskets and tools, less for
        // fortifications.
        let percentTwiddle = 20
        let twiddle = RandomUtils.randomInts("REF target twiddle", aiRandom, Int32(2 * percentTwiddle + 1),
                                             targets.count)
        for (i, t) in targets.enumerated() {
            var buildings = 1.0
            for b in t.colony.buildings where b.level > 1 {
                var outputs = 1.0
                for ag in b.outputs {
                    guard let type = ag.type else { continue }
                    outputs *= type.isMilitary ? 2.0 : type.isBuildingMaterial && type.isRefined ? 1.5 : 1.0
                }
                buildings *= (b.hasAbility(Ability.repairUnits) ? 1.5 : 1.0) * outputs
            }
            let stockade = t.colony.hasStockade ? (t.colony.stockade?.level ?? 0) : 0
            t.score *= 0.01 * Double(101 - min(100, t.colony.sonsOfLiberty))
                * buildings
                * (Double(6 - stockade) / 6.0)
                * (1.0 + 0.01 * Double(Int(twiddle[i]) - percentTwiddle))
        }
        return targets.stableSorted { $0.score < $1.score }
    }

    /// The rebels' ports, or else any of their colonies.
    private func findColonyTargets(_ aiu: AIUnit, _ aiCarrier: AIUnit) -> [TargetTuple] {
        let targets = findColonyTargets(aiu, true, aiCarrier)
        return targets.isEmpty ? findColonyTargets(aiu, false, aiCarrier) : targets
    }

    // MARK: Arriving

    /// Before the REF's first turn, choose where it lands, and give its
    /// units their missions: the army to attack the targets, roughly two
    /// thirds at the best, and the empty ships to attack the rebels'
    /// ships near the landings, or to patrol (initialize).
    ///
    /// - Parameter teleport: Whether the navy appears where it lands,
    ///   rather than sailing in.
    /// - Returns: Whether it could.
    func initialize(_ teleport: Bool) -> Bool {
        // A representative unit of the army to plan with.
        guard let aiUnit = aiUnits().first(where: { !$0.unit.isNaval && $0.unit.isOffensiveUnit }) else {
            return false
        }
        let unit = aiUnit.unit
        guard let carrier = unit.carrier, let aiCarrier = aiMain.aiUnit(carrier) else { return false }

        var targets = findColonyTargets(aiUnit, aiCarrier)
        if targets.isEmpty { return false }

        let rebel = targets[0].colony.owner
        // Java's own strength against the rebel's, from the nation
        // summary it has, which on the REF's first turn is none.
        let ratio: Double
        if let ns = rebel.flatMap({ nationSummaries[$0.id ?? ""] }) {
            ratio = Player.strengthRatio(Double(player.calculateStrength(naval: false)),
                                         Double(ns.militaryStrength))
        } else {
            ratio = -1
        }
        var n = targets.count

        // Where to land for each target: where a search from the
        // target's entry first gets off the carrier.
        var fail = 0
        for t in targets {
            if let entry = t.entry,
               let path = unit.search(entry, GoalDeciders.disembark(t.colony.tile!), nil, 10, carrier) {
                t.disembarkTile = path.transportDropNode.previous?.tile
            } else {
                t.disembarkTile = nil
                fail += 1
            }
        }
        if fail > 0 {
            if fail < n {
                // Drop the targets with no landing.
                targets.removeAll { $0.disembarkTile == nil }
            } else {
                // None had one; land where the plain path does.
                for t in targets { t.disembarkTile = t.path?.transportDropNode.previous?.tile }
            }
        }
        n = ratio < 1.0 ? 1 : ratio < 2.0 ? min(2, targets.count) : min(3, targets.count)

        if !teleport, let rebel {
            // Arrive unseen if possible, at worst a turn slower.
            let stealth = GoalDeciders.composed(all: true, GoalDeciders.highSeas(), GoalDeciders.stealthy(rebel))
            for t in targets.prefix(n) {
                guard let entry = t.entry, rebel.canSee(entry), let dt = t.disembarkTile else { continue }
                if let path = carrier.search(dt, stealth, CostDeciders.avoidSettlementsAndBlockingUnits(),
                                             (t.path?.totalTurns ?? 0) + 1, nil) {
                    t.entry = path.lastNode.tile
                    t.score *= 1.5 // Unseen is better.
                }
            }
            targets = targets.stableSorted { $0.score < $1.score }
        }

        // The army: each loaded ship takes its units to a target, about
        // two thirds of the army to the first.
        var navy: [AIUnit] = []
        let units = aiUnits()
        var next = 0
        var land = player.numberOfKingLandUnits
        for i in 0..<n {
            if next >= units.count { break }
            let t = targets[i]
            while next < units.count {
                let aiu = units[next]
                next += 1
                if !aiu.unit.isNaval { continue }
                let ship = aiu.unit
                if ship.isEmpty {
                    navy.append(aiu)
                    continue
                }
                ship.entryLocation = teleport ? t.disembarkTile : t.entry
                var used = 0
                for u in ship.unitList {
                    _ = aiMain.aiUnit(u).flatMap { seekAndDestroyMission($0, t.colony) }
                    used += 1
                }
                _ = transportMission(aiu)
                if i < n - 1 && used >= Int((Double(land) * 0.66).rounded(.down)) {
                    land -= used
                    break
                }
            }
        }

        // The rebels' ships near the landings.
        guard let rebel else { return true }
        let navyGD = NavyGoalDecider(rebel)
        for t in targets.prefix(n) {
            guard let entry = t.entry else { continue }
            _ = carrier.search(entry, navyGD, nil, carrier.initialMovesLeft * 2, nil)
        }

        // Attack them, the weakest first (by Java's comparator of
        // combat odds).
        guard let cm = game.combatModel as CombatModel? else { return true }
        var rebelTargets = navyGD.rebelNavy.elements.stableSorted {
            cm.calculateCombatOdds($0, $1).win < cm.calculateCombatOdds($1, $0).win
        }
        var entries: [Tile?] = [rebel.entryTile]
        while !navy.isEmpty {
            let aiu = navy.removeFirst()
            let u = aiu.unit
            let enemy = rebelTargets.isEmpty ? nil : rebelTargets.removeFirst()
            if let enemy {
                if seekAndDestroyMission(aiu, enemy) != nil {
                    let start = enemy.tile.flatMap { u.bestEntryTile($0) }
                    u.entryLocation = start
                    entries.append(start)
                }
            } else if wanderHostileMission(aiu) != nil {
                u.entryLocation = RandomUtils.randomMember("REF patrol entry", entries, aiRandom) ?? nil
            }
        }
        return true
    }

    // MARK: Missions

    /// Give privateers transport missions until there are enough
    /// carriers: first those not chasing a ship on the map, then those
    /// chasing one farthest off (requireTransports).
    @discardableResult
    private func requireTransports(_ nt: Int, _ transports: inout [AIUnit],
                                   _ privateers: inout [AIUnit]) -> [AIUnit] {
        var naval: [AIUnit] = []
        var result: [AIUnit] = []
        if transports.count < nt {
            for aiu in privateers {
                if let target = aiu.mission?.target as? Unit, !target.isDisposed, target.tile != nil,
                   aiu.unit.hasTile {
                    naval.append(aiu)
                } else if transportMission(aiu) != nil {
                    result.append(aiu)
                }
            }
        }
        if transports.count < nt {
            func distance(_ aiu: AIUnit) -> Int {
                guard let tile = aiu.unit.tile, let target = (aiu.mission?.target as? Unit)?.tile else { return 0 }
                return tile.distance(to: target)
            }
            let distances = Dictionary(uniqueKeysWithValues: naval.map { (ObjectIdentifier($0), distance($0)) })
            for aiu in naval.stableSorted(by: { distances[ObjectIdentifier($0)]! < distances[ObjectIdentifier($1)]! }) {
                if transportMission(aiu) != nil {
                    result.append(aiu)
                    if result.count + transports.count >= nt { break }
                }
            }
        }
        privateers.removeAll { p in result.contains { $0 === p } }
        transports.append(contentsOf: result)
        return result
    }

    /// The REF's units' missions, before the European AI's for the rest
    /// (giveNormalMissions): enough transports, the free army to attack
    /// nearby targets, defend, or wait at a port, and those waiting
    /// loaded on carriers there for new attacks.  As in Java, the
    /// European AI's then goes over all the REF's units, leaving the
    /// list it was given alone.
    override func giveMissions(_ aiUnits: inout [AIUnit]) throws {
        var idlers = JavaHashMap<LocationKey, [AIUnit]>(javaHash: { $0.javaHash })
        var privateers: [AIUnit] = []
        var transports: [AIUnit] = []
        var todo: [AIUnit] = []
        var land: [AIUnit] = []

        // The REF's units: privateers, transports, the free navy and
        // the free army.
        targetMap.removeAll()
        for aiu in self.aiUnits() {
            let u = aiu.unit
            if u.isDisposed || !u.hasAbility(Ability.refUnit) { continue }
            let mission = aiu.mission
            if u.isNaval {
                if mission == nil || !(mission?.isValid ?? false) {
                    todo.append(aiu)
                } else if mission is TransportMission {
                    transports.append(aiu)
                } else if mission is PrivateerMission {
                    privateers.append(aiu)
                    incrementTarget(mission?.target)
                } else {
                    todo.append(aiu)
                }
            } else if let mission {
                if mission is DefendSettlementMission {
                    if mission.isValid, let colony = mission.target as? Colony {
                        // Let some go from colonies with defenders enough.
                        if u.isAtLocation(colony) && !colony.isBadlyDefended
                            && RandomUtils.randomInt("REF defend \(colony.name ?? "")", aiRandom, 3) == 0 {
                            land.append(aiu)
                        } else {
                            incrementTarget(mission.target)
                        }
                    } else {
                        land.append(aiu)
                    }
                } else if mission is UnitSeekAndDestroyMission {
                    if mission.isValid {
                        incrementTarget(mission.target)
                        continue
                    }
                    land.append(aiu)
                } else {
                    land.append(aiu)
                }
            } else {
                land.append(aiu)
            }
        }

        // The free navy carries.
        for aiu in todo where transportMission(aiu) != nil { transports.append(aiu) }
        todo.removeAll()

        // At least some carriers.
        var nt = max(3, privateers.count / 10)
        requireTransports(nt, &transports, &privateers)

        // The free army: attack nearby (not all after one wagon), wait
        // at a port, defend the nearest colony needing it, or the
        // nearest port, or just wait somewhere.
        for aiu in land {
            if let target = UnitSeekAndDestroyMission.findMissionTarget(aiu, REFAIPlayer.seekAndDestroyRange,
                                                                       false, false) {
                let count = targetMap[ObjectIdentifier(target)] ?? 0
                if target is Unit && count < REFAIPlayer.unitUSADThreshold
                    && seekAndDestroyMission(aiu, target) != nil {
                    incrementTarget(target)
                    continue
                } else if target is Settlement && seekAndDestroyMission(aiu, target) != nil {
                    incrementTarget(target)
                    continue
                } else {
                    // Java throws, ending the REF's turn.
                    throw REFFailure(description: "Bogus target: \(target)")
                }
            }

            let u = aiu.unit
            if u.isInEurope, let europe = player.europe {
                let key = LocationKey(location: europe)
                idlers[key] = (idlers[key] ?? []) + [aiu]
                continue
            } else if let colony = u.colony, colony.isConnectedPort {
                let key = LocationKey(location: colony)
                idlers[key] = (idlers[key] ?? []) + [aiu]
                continue
            }

            if let best = u.closestColony(badlyDefended.map(\.colony)),
               defendSettlementMission(aiu, best) != nil {
                incrementTarget(best)
                continue
            }

            if let colony = u.findOurNearestPort()?.lastNode.tile?.colony,
               defendSettlementMission(aiu, colony) != nil {
                incrementTarget(colony)
                continue
            }

            _ = idleAtSettlementMission(aiu)
        }

        // New attacks for those waiting at ports.
        if !idlers.isEmpty {
            requireTransports(0, &transports, &privateers)
            todo.removeAll()
            // The empty carriers at those ports.
            var ready: [ObjectIdentifier: [AIUnit]] = [:]
            for aiu in transports {
                guard let tm = aiu.mission as? TransportMission, tm.isEmpty else { continue }
                let u = aiu.unit
                if u.isInEurope, let europe = player.europe, idlers[LocationKey(location: europe)] != nil {
                    ready[ObjectIdentifier(europe), default: []].append(aiu)
                } else if let colony = u.colony, idlers[LocationKey(location: colony)] != nil {
                    ready[ObjectIdentifier(colony), default: []].append(aiu)
                } else {
                    todo.append(aiu)
                }
            }

            // Load the waiting units on carriers there, and send them
            // to attack.  Note the ports still with units waiting, and
            // the space they need.
            var idlePorts: [LocationKey] = []
            var space = 0
            for (key, waiting) in idlers.entries {
                guard let here = ready[ObjectIdentifier(key.location)], !here.isEmpty else { continue }
                var aiCarriers: [AIUnit] = []
                landUnit: for aiu in waiting {
                    for aiCarrier in here {
                        let carrier = aiCarrier.unit
                        if carrier.canAdd(aiu.unit) && aiu.joinTransport(carrier, nil) {
                            if !aiCarriers.contains(where: { $0 === aiCarrier }) { aiCarriers.append(aiCarrier) }
                            continue landUnit
                        }
                    }
                }
                if aiCarriers.isEmpty { continue }

                // A target: one a loaded unit has already, or the best.
                var found: AIUnit?
                var target: Colony?
                for aiCarrier in aiCarriers {
                    found = aiCarrier.unit.unitList.filter { $0.hasAbility(Ability.refUnit) }
                        .compactMap { aiUnit($0) }.first
                    if let m = found?.mission, m.isValid, m is UnitSeekAndDestroyMission,
                       let c = m.target as? Colony {
                        target = c
                        break
                    }
                }
                if target == nil, let found, let carrier = aiUnit(found.unit.carrier) {
                    target = findColonyTargets(found, carrier).first?.colony
                }
                guard let target else { continue }

                var remaining = waiting
                for aiCarrier in aiCarriers {
                    guard let tm = aiCarrier.mission as? TransportMission else { continue }
                    for u in aiCarrier.unit.unitList where u.hasAbility(Ability.refUnit) {
                        if let aiu = aiUnit(u), seekAndDestroyMission(aiu, target) != nil {
                            _ = tm.queueTransportable(aiu, false)
                            if let i = remaining.firstIndex(where: { $0 === aiu }) { remaining.remove(at: i) }
                        }
                    }
                }
                idlers[key] = remaining
                if !remaining.isEmpty {
                    idlePorts.append(key)
                    space += remaining.reduce(0) { $0 + $1.unit.spaceTaken }
                }
            }

            if !idlePorts.isEmpty {
                // More carriers, from the privateers, if short of space.
                for aiu in todo { space -= aiu.unit.cargoCapacity - aiu.unit.cargoSpaceTaken }
                nt = todo.count
                if space < 0 {
                    nt += -space / 5 + 1
                    requireTransports(nt, &todo, &privateers)
                }

                // Send the carriers to the ports, those with fewest
                // waiting first.
                idlePorts = idlePorts.stableSorted { (idlers[$0]?.count ?? 0) < (idlers[$1]?.count ?? 0) }
                var bad = false
                while !bad && !todo.isEmpty {
                    for l in idlePorts {
                        var bestValue = Unit.manyTurns
                        var best: AIUnit?
                        for aiu in todo {
                            let value = aiu.unit.turnsToReach(l.location)
                            if bestValue > value {
                                bestValue = value
                                best = aiu
                            }
                        }
                        guard let best else {
                            bad = true
                            continue
                        }
                        todo.removeAll { $0 === best }
                        best.mission?.target = l.location
                    }
                }
            }
        }

        // The European AI for the rest.
        var all = self.aiUnits()
        try super.giveMissions(&all)
    }

    // MARK: The turn

    /// The REF's turn, if it has work (startWorking): the European AI's,
    /// then carriers for the army still in Europe.
    override func startWorking() {
        if !player.isWorkForREF { return }
        super.startWorking()
        var transport: [TransportMission] = []
        var land: [TransportableAIObject] = []
        for aiu in aiUnits() {
            let u = aiu.unit
            if u.isNaval {
                if let tm = aiu.mission as? TransportMission { transport.append(tm) }
            } else if u.isInEurope {
                land.append(aiu)
            } else if u.isOnTile {
                landed = true
            }
        }
        if !land.isEmpty && !transport.isEmpty { allocateTransportables(land, transport) }
    }

    /// The REF garrisons thinly, values ports highly, and leaves the
    /// rebels' units alone until it holds a colony, and then chases
    /// each with only one unit, and less keenly than colonies
    /// (adjustMission).  Unlike the European AI, it does not count the
    /// defenders already there.
    override func adjustMission(_ aiUnit: AIUnit, _ path: PathNode, _ type: Mission.Type, _ value: Int) -> Int {
        guard value > 0 else { return value }
        var value = value
        if type == DefendSettlementMission.self {
            if let colony = DefendSettlementMission.extractTarget(aiUnit, path) as? Colony,
               !colony.isBadlyDefended {
                return Int(Int32.min)
            }
        } else if type == UnitSeekAndDestroyMission.self {
            let target = UnitSeekAndDestroyMission.extractTarget(aiUnit, path)
            if let settlement = target as? Settlement {
                if settlement.isConnectedPort {
                    value = Int(Int32(truncatingIfNeeded: value) &+ 500)
                } else if !player.hasSettlements {
                    return Int(Int32.min)
                }
            } else if let unit = target as? Unit {
                if !player.hasSettlements { return Int(Int32.min) }
                if aiUnits().contains(where: {
                    $0 !== aiUnit && ($0.mission as? UnitSeekAndDestroyMission)?.target as? Unit === unit
                }) {
                    return Int(Int32.min)
                }
                value /= 2
            }
        }
        return value
    }

    /// At war with its own rebels, at peace with its colonists, at war
    /// with whoever is at war with it, and otherwise at peace while it
    /// has rebels to fight (determineStance).
    override func determineStance(_ other: Player) -> Player.Stance {
        if other.refPlayer === player { return other.isRebel ? .war : .peace }
        if other.atWar(with: player) { return .war }
        if !player.rebels.isEmpty { return .peace }
        return super.determineStance(other)
    }
}

/// What Java's REF throws when its army finds a target it should not
/// (giveNormalMissions), ending its turn.
struct REFFailure: Error, CustomStringConvertible {
    let description: String
}

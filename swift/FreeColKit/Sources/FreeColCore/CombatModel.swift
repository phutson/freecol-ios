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

import FreeColUtil

/// How combat is decided (common/model/CombatModel): the odds and power
/// of attackers and defenders, the modifiers that apply, and the
/// result of an attack.
///
/// The combatants are game objects: units, and settlements (attacked,
/// or bombarding ships).  A nil attacker or defender asks for a
/// measurement of the other's power.
open class CombatModel {

    /// What a combat can lead to (CombatModel.CombatEffectType).
    public enum CombatEffectType: JavaEnum, CustomStringConvertible {
        // Special results that set the sense of the result.
        case noResult, lose, win
        // Specific actions
        case autoequipUnit, burnMissions, captureAutoequip, captureColony, captureConvert
        case captureEquip, captureUnit, damageColonyShips, damageShipAttack, damageShipBombard
        case demoteUnit, destroyColony, destroySettlement, evadeAttack, evadeBombard, lootShip
        case loseAutoequip, loseEquip, pillageColony, promoteUnit, sinkColonyShips
        case sinkShipAttack, sinkShipBombard, slaughterUnit

        public var javaName: String {
            switch self {
            case .noResult: "NO_RESULT"
            case .lose: "LOSE"
            case .win: "WIN"
            case .autoequipUnit: "AUTOEQUIP_UNIT"
            case .burnMissions: "BURN_MISSIONS"
            case .captureAutoequip: "CAPTURE_AUTOEQUIP"
            case .captureColony: "CAPTURE_COLONY"
            case .captureConvert: "CAPTURE_CONVERT"
            case .captureEquip: "CAPTURE_EQUIP"
            case .captureUnit: "CAPTURE_UNIT"
            case .damageColonyShips: "DAMAGE_COLONY_SHIPS"
            case .damageShipAttack: "DAMAGE_SHIP_ATTACK"
            case .damageShipBombard: "DAMAGE_SHIP_BOMBARD"
            case .demoteUnit: "DEMOTE_UNIT"
            case .destroyColony: "DESTROY_COLONY"
            case .destroySettlement: "DESTROY_SETTLEMENT"
            case .evadeAttack: "EVADE_ATTACK"
            case .evadeBombard: "EVADE_BOMBARD"
            case .lootShip: "LOOT_SHIP"
            case .loseAutoequip: "LOSE_AUTOEQUIP"
            case .loseEquip: "LOSE_EQUIP"
            case .pillageColony: "PILLAGE_COLONY"
            case .promoteUnit: "PROMOTE_UNIT"
            case .sinkColonyShips: "SINK_COLONY_SHIPS"
            case .sinkShipAttack: "SINK_SHIP_ATTACK"
            case .sinkShipBombard: "SINK_SHIP_BOMBARD"
            case .slaughterUnit: "SLAUGHTER_UNIT"
            }
        }

        public var description: String {
            javaName
        }
    }

    /// The effects of a combat, and the hit points after it where the
    /// combat model counts them (-1 where it does not).
    public struct CombatResult {
        public let effects: [CombatEffectType]
        public let attackerHitpointsAfter: Int
        public let defenderHitpointsAfter: Int

        public init(_ effects: [CombatEffectType], _ attackerHitpointsAfter: Int = -1,
                    _ defenderHitpointsAfter: Int = -1) {
            self.effects = effects
            self.attackerHitpointsAfter = attackerHitpointsAfter
            self.defenderHitpointsAfter = defenderHitpointsAfter
        }

        public var isAttackerHitpointsAffected: Bool { attackerHitpointsAfter >= 0 }
        public var isDefenderHitpointsAffected: Bool { defenderHitpointsAfter >= 0 }
    }

    /// The chance of an attack succeeding.
    public struct CombatOdds {
        public static let unknownOdds = -1.0
        public let win: Double

        public init(_ win: Double) {
            self.win = win
        }
    }

    public init() {}

    // MARK: Kinds of combat

    /// Measuring an attacker's power, with no defender.
    public final func combatIsAttackMeasurement(_ attacker: FreeColGameObject?,
                                                _ defender: FreeColGameObject?) -> Bool {
        attacker is Unit && defender == nil
    }

    /// Measuring a defender's power, with no attacker.
    public final func combatIsDefenceMeasurement(_ attacker: FreeColGameObject?,
                                                 _ defender: FreeColGameObject?) -> Bool {
        attacker == nil && defender is Unit
    }

    public func combatIsAttack(_ attacker: FreeColGameObject?, _ defender: FreeColGameObject?) -> Bool {
        attacker is Unit && defender is Unit
    }

    public func combatIsSettlementAttack(_ attacker: FreeColGameObject?,
                                         _ defender: FreeColGameObject?) -> Bool {
        attacker is Unit && defender is Settlement
    }

    /// A settlement firing on a ship.
    public func combatIsBombard(_ attacker: FreeColGameObject?, _ defender: FreeColGameObject?) -> Bool {
        attacker is Settlement && ((defender as? Unit)?.isNaval ?? false)
    }

    /// A unit attacking from the water onto land.
    public func combatIsAmphibious(_ attacker: FreeColGameObject?,
                                   _ defender: FreeColGameObject?) -> Bool {
        guard let unit = attacker as? Unit, unit.hasTile, let tile = unit.tile, !tile.isLand,
              let defenderTile = (defender as? any Location)?.tile else { return false }
        return defenderTile.isLand
    }

    /// Rebels fighting their REF.
    public final func combatIsWarOfIndependence(_ attacker: FreeColGameObject?,
                                                _ defender: FreeColGameObject?) -> Bool {
        guard let unit = attacker as? Unit, let ownable = defender as? Ownable,
              let aPlayer = unit.owner, let dPlayer = ownable.owner else { return false }
        return (aPlayer.isRebel && aPlayer.refPlayer === dPlayer)
            || (dPlayer.isRebel && dPlayer.refPlayer === aPlayer)
    }

    /// Java's getMilitaryStrengthComparator, as a three-way comparison:
    /// by each unit's odds of beating the other.
    public final func compareMilitaryStrength(_ u1: Unit, _ u2: Unit) -> Int {
        let a = calculateCombatOdds(u1, u2).win, b = calculateCombatOdds(u2, u1).win
        return a < b ? -1 : a > b ? 1 : 0
    }

    // MARK: For subclasses (abstract in Java)

    open func calculateCombatOdds(_ attacker: FreeColGameObject?,
                                  _ defender: FreeColGameObject?) -> CombatOdds {
        fatalError("abstract")
    }

    open func offencePower(_ attacker: FreeColGameObject?, _ defender: FreeColGameObject?) -> Double {
        fatalError("abstract")
    }

    open func defencePower(_ attacker: FreeColGameObject?, _ defender: FreeColGameObject?) -> Double {
        fatalError("abstract")
    }

    open func offensiveModifiers(_ attacker: FreeColGameObject?,
                                 _ defender: FreeColGameObject?) -> [Modifier] {
        fatalError("abstract")
    }

    open func defensiveModifiers(_ attacker: FreeColGameObject?,
                                 _ defender: FreeColGameObject?) -> [Modifier] {
        fatalError("abstract")
    }

    open func generateAttackResult(_ random: JavaRandom, _ attacker: FreeColGameObject?,
                                   _ defender: FreeColGameObject?) -> CombatResult {
        fatalError("abstract")
    }
}

/// A set of modifiers with Java's HashSet semantics: equal modifiers
/// (Modifier.equals) are kept once.  The order does not matter, as
/// modifiers are sorted before they are applied.
struct ModifierSet {
    private(set) var members: [Modifier] = []
    private var seen = Set<Modifier>()

    mutating func add(_ m: Modifier) {
        if seen.insert(m).inserted { members.append(m) }
    }

    mutating func add<S: Sequence>(contentsOf ms: S) where S.Element == Modifier {
        for m in ms { add(m) }
    }
}

/// The standard combat model (common/model/SimpleCombatModel): power is
/// the sum of modifiers starting from zero, and the odds of winning are
/// the attacker's share of the combined power.
open class SimpleCombatModel: CombatModel {

    /// The most a settlement's guns can bombard with.
    public static let maximumBombardPower = 48.0

    /// A percentage defence bonus this large stops fortification
    /// helping.
    public static let strongDefenceThreshold: Float = 150

    /// Hides a settlement's defence before the attack (Java shares one
    /// static instance, whose index the compatibility fix changes on
    /// first use).
    nonisolated(unsafe) public static let unknownDefenceModifier
        = Modifier("bogus", Modifier.unknown, .additive)

    public override init() {
        super.init()
    }

    // MARK: Odds and power

    open override func calculateCombatOdds(_ attacker: FreeColGameObject?,
                                           _ defender: FreeColGameObject?) -> CombatOdds {
        guard attacker != nil, defender != nil else { return CombatOdds(CombatOdds.unknownOdds) }
        let attackPower = offencePower(attacker, defender)
        let defencePower = defencePower(attacker, defender)
        if attackPower == 0.0 && defencePower == 0.0 { return CombatOdds(CombatOdds.unknownOdds) }
        return CombatOdds(attackPower / (attackPower + defencePower))
    }

    open override func offencePower(_ attacker: FreeColGameObject?,
                                    _ defender: FreeColGameObject?) -> Double {
        guard let attacker else { preconditionFailure("Null attacker: \(self)") }
        if combatIsAttackMeasurement(attacker, defender) || combatIsAttack(attacker, defender)
            || combatIsSettlementAttack(attacker, defender) {
            let mods = offensiveModifiers(attacker, defender)
            return Double(FeatureContainer.applyModifiers(0, turn: attacker.game?.turn, mods))
        }
        if combatIsBombard(attacker, defender) {
            let settlement = attacker as! Settlement
            var result = 0.0
            if settlement.hasAbility(Ability.bombardShips) {
                result += JavaMath.doubleStreamSum((settlement.tile?.unitList ?? [])
                    .filter { $0.hasAbility(Ability.bombard) }.map { $0.type?.offence ?? 0 })
            }
            return min(result, SimpleCombatModel.maximumBombardPower)
        }
        preconditionFailure("Bogus combat: \(attacker) v \(String(describing: defender))")
    }

    open override func defencePower(_ attacker: FreeColGameObject?,
                                    _ defender: FreeColGameObject?) -> Double {
        guard combatIsDefenceMeasurement(attacker, defender) || combatIsAttack(attacker, defender)
            || combatIsSettlementAttack(attacker, defender) || combatIsBombard(attacker, defender)
        else { preconditionFailure("Bogus combat") }
        let mods = defensiveModifiers(attacker, defender)
        return Double(FeatureContainer.applyModifiers(0, turn: defender?.game?.turn, mods))
    }

    // MARK: Modifiers

    /// The modifiers an attacker gets: base offence, its own (type,
    /// owner, role), bonuses against the defender's nation, and the
    /// land or naval ones.
    open override func offensiveModifiers(_ attacker: FreeColGameObject?,
                                          _ defender: FreeColGameObject?) -> [Modifier] {
        guard let attacker else { preconditionFailure("Null attacker: \(self)") }
        var result = ModifierSet()
        if combatIsAttackMeasurement(attacker, defender) || combatIsAttack(attacker, defender)
            || combatIsSettlementAttack(attacker, defender) {
            let attackerUnit = attacker as! Unit
            let spec = attackerUnit.specification
            let turn = attackerUnit.game?.turn
            // Base offence
            result.add(Modifier(Modifier.offence, Float(attackerUnit.type?.baseOffence ?? 0), .additive,
                                source: spec?.source(Specification.SourceId.baseOffence),
                                index: Modifier.baseCombatIndex))
            // The unit's own, including its role, qualified by unit
            // type so that scopes work (@compat 0.11.0)
            result.add(contentsOf: attackerUnit.combatModifiers(Modifier.offence, attackerUnit.type, turn))
            // Special bonuses against certain nation types
            if let owner = (defender as? Ownable)?.owner {
                result.add(contentsOf: attackerUnit.modifiers(Modifier.offenceAgainst, for: owner.nationType))
            }
            // Land or naval
            if attackerUnit.isNaval {
                addNavalOffensiveModifiers(attackerUnit, &result)
            } else {
                addLandOffensiveModifiers(attackerUnit, defender, &result)
            }
        } else if combatIsBombard(attacker, defender) {
            // Bombard strength is handled by offencePower
        } else {
            preconditionFailure("Bogus combat: \(attacker) v \(String(describing: defender))")
        }
        return SimpleCombatModel.fixIndexes(result.members)
    }

    /// @compat 0.11.0: a modifier with the default index applies with
    /// the general combat index.  As in Java, the modifier itself is
    /// changed, even one belonging to the rules.
    static func fixIndexes(_ mods: [Modifier]) -> [Modifier] {
        for m in mods where m.modifierIndex == Modifier.defaultModifierIndex {
            m.modifierIndex = Modifier.generalCombatIndex
        }
        return mods
    }

    private func addNavalOffensiveModifiers(_ attacker: Unit, _ result: inout ModifierSet) {
        guard let spec = attacker.specification else { return }
        // Attack bonus
        result.add(contentsOf: spec.modifiers(Modifier.attackBonus))
        // Goods penalty always applies
        let goodsCount = attacker.goodsSpaceTaken
        if goodsCount > 0 {
            for m in spec.modifiers(Modifier.cargoPenalty) {
                let mod = Modifier(copying: m)
                mod.value = m.value * Float(goodsCount)
                result.add(mod)
            }
        }
    }

    private func addPopularSupportBonus(_ colony: Colony, _ attacker: Unit, _ result: inout ModifierSet) {
        var bonus = colony.sonsOfLiberty
        if bonus >= 0 {
            if attacker.owner?.isREF ?? false { bonus = 100 - bonus }
            if bonus > 0 {
                result.add(Modifier(Modifier.popularSupport, Float(bonus), .percentage, source: colony,
                                    index: Modifier.generalCombatIndex))
            }
        }
    }

    private func addLandOffensiveModifiers(_ attacker: Unit, _ defender: FreeColGameObject?,
                                           _ result: inout ModifierSet) {
        guard let spec = attacker.specification else { return }
        // Attack bonus
        result.add(contentsOf: spec.modifiers(Modifier.attackBonus))
        // Movement penalty
        switch attacker.movesLeft {
        case 1: result.add(contentsOf: spec.modifiers(Modifier.bigMovementPenalty))
        case 2: result.add(contentsOf: spec.modifiers(Modifier.smallMovementPenalty))
        default: break
        }
        // Amphibious attack?
        if combatIsAmphibious(attacker, defender) {
            result.add(contentsOf: spec.modifiers(Modifier.amphibiousAttack))
        }
        if combatIsAttackMeasurement(attacker, defender) {
            // No defender information available
        } else if combatIsSettlementAttack(attacker, defender) {
            // Settlement present, apply bombardment bonus
            result.add(contentsOf: attacker.modifiers(Modifier.bombardBonus))
            // Popular support bonus
            if combatIsWarOfIndependence(attacker, defender) {
                addPopularSupportBonus(defender as! Colony, attacker, &result)
            }
        } else if combatIsAttack(attacker, defender) {
            let defenderUnit = defender as! Unit
            if let tile = defenderUnit.tile {
                if tile.hasSettlement {
                    // Bombard bonus applies to settlement defence
                    result.add(contentsOf: attacker.modifiers(Modifier.bombardBonus))
                    // Popular support bonus
                    if combatIsWarOfIndependence(attacker, defender) {
                        addPopularSupportBonus(tile.settlement as! Colony, attacker, &result)
                    }
                } else if isAmbush(attacker, defender) {
                    // Ambush bonus in the open: the defender's defence
                    // bonus, if the defender is REF or the attacker is
                    // native.
                    for m in tile.defenceModifiers {
                        let mod = Modifier(copying: m)
                        mod.id = Modifier.offence
                        mod.source = spec.source(Specification.SourceId.ambushBonus)
                        result.add(mod)
                    }
                }
            }
            // Artillery in the open penalty: the attacker on a tile, and
            // neither unit in a settlement.
            if attacker.hasAbility(Ability.bombard) && attacker.isOnTile && attacker.settlement == nil
                && attacker.state != .fortified && defenderUnit.settlement == nil {
                result.add(contentsOf: spec.modifiers(Modifier.artilleryInTheOpen))
            }
        } else {
            preconditionFailure("Bogus combat: \(attacker) v \(String(describing: defender))")
        }
    }

    /// The modifiers a defender gets: base defence, its own, and the
    /// land or naval ones; or for a settlement, the tile's and the
    /// settlement's, kept unknown.
    open override func defensiveModifiers(_ attacker: FreeColGameObject?,
                                          _ defender: FreeColGameObject?) -> [Modifier] {
        var result = ModifierSet()
        if combatIsDefenceMeasurement(attacker, defender) || combatIsAttack(attacker, defender)
            || combatIsBombard(attacker, defender) {
            let defenderUnit = defender as! Unit
            let turn = defenderUnit.game?.turn
            // Base defence
            result.add(Modifier(Modifier.defence, Float(defenderUnit.type?.baseDefence ?? 0), .additive,
                                source: defenderUnit.specification?.source(Specification.SourceId.baseDefence),
                                index: Modifier.baseCombatIndex))
            // The unit's own (@compat 0.11.0)
            result.add(contentsOf: defenderUnit.combatModifiers(Modifier.defence, defenderUnit.type, turn))
            // Land or naval
            if defenderUnit.isNaval {
                addNavalDefensiveModifiers(defenderUnit, &result)
            } else {
                addLandDefensiveModifiers(attacker, defenderUnit, &result)
            }
        } else if combatIsSettlementAttack(attacker, defender) {
            let settlement = defender as! Settlement
            // Tile defence bonus
            result.add(contentsOf: settlement.tile?.type?.defenceModifiers ?? [])
            // Settlement defence bonus
            result.add(contentsOf: settlement.defenceModifiers)
            // The settlement can not be seen inside.  This only applies
            // before combat: the actual attack is on the chosen defender.
            result.add(SimpleCombatModel.unknownDefenceModifier)
        } else {
            preconditionFailure("Bogus combat: \(String(describing: attacker)) v \(String(describing: defender))")
        }
        return SimpleCombatModel.fixIndexes(result.members)
    }

    private func addNavalDefensiveModifiers(_ defender: Unit, _ result: inout ModifierSet) {
        guard let spec = defender.specification else { return }
        // Cargo penalty always applies
        let goodsCount = defender.visibleGoods
        if goodsCount > 0 {
            for m in spec.modifiers(Modifier.cargoPenalty) {
                let mod = Modifier(copying: m)
                mod.value = m.value * Float(goodsCount)
                result.add(mod)
            }
        }
    }

    private func hasStrongDefenceModifier(_ fco: FreeColObject?) -> Bool {
        (fco?.defenceModifiers ?? []).contains {
            $0.type == .percentage && $0.value >= SimpleCombatModel.strongDefenceThreshold
        }
    }

    private func addLandDefensiveModifiers(_ attacker: FreeColGameObject?, _ defender: Unit,
                                           _ result: inout ModifierSet) {
        guard let spec = defender.specification, let tile = defender.tile else { return }
        var disableFortified = hasStrongDefenceModifier(tile.type)
        if let settlement = tile.settlement {
            // Settlement defence bonus
            result.add(contentsOf: settlement.defenceModifiers)
            // Artillery defence bonus against a native raid
            if let attackerUnit = attacker as? Unit, attackerUnit.owner?.isIndian ?? false,
               defender.hasAbility(Ability.bombard) {
                result.add(contentsOf: spec.modifiers(Modifier.artilleryAgainstRaid))
            }
            // Automatic defensive role (e.g. Revere)
            if let autoRole = defender.automaticRole {
                result.add(contentsOf: autoRole.defenceModifiers)
            }
            if let stockade = (settlement as? Colony)?.stockade {
                disableFortified = disableFortified || hasStrongDefenceModifier(stockade.type)
            }
        } else {
            // PF#73 showed that tile modifiers do not apply in colonies.
            result.add(contentsOf: tile.type?.defenceModifiers ?? [])
            // Artillery in the open penalty
            if defender.hasAbility(Ability.bombard) && defender.state != .fortified {
                result.add(contentsOf: spec.modifiers(Modifier.artilleryInTheOpen))
            }
        }
        // Fortify bonus
        if !disableFortified && defender.state == .fortified {
            result.add(contentsOf: spec.modifiers(Modifier.fortified))
        }
    }

    // MARK: Results

    open override func generateAttackResult(_ random: JavaRandom, _ attacker: FreeColGameObject?,
                                            _ defender: FreeColGameObject?) -> CombatResult {
        var crs: [CombatEffectType] = []
        let odds = calculateCombatOdds(attacker, defender)
        let r = RandomUtils.randomDouble("AttackResult", random)
        if combatIsAttack(attacker, defender) {
            let attackerUnit = attacker as! Unit, defenderUnit = defender as! Unit
            // Below odds.win is a win, the first tenth of it great.
            // Above, the first fifth is an evasion (with the ability),
            // the next seven tenths a loss, the rest a great loss.
            // Beached ships always lose.
            if r < odds.win || defenderUnit.isBeached {
                let great = r < 0.1 * odds.win // Great win
                crs.append(.win)
                resolveAttack(attackerUnit, defenderUnit, great, r / (0.1 * odds.win), &crs)
            } else if r < 0.8 * odds.win + 0.2 && defenderUnit.hasAbility(Ability.evadeAttack) {
                crs.append(.noResult)
                crs.append(.evadeAttack)
            } else {
                let great = r >= 0.1 * odds.win + 0.9 // Great loss
                crs.append(.lose)
                resolveAttack(defenderUnit, attackerUnit, great,
                              (1.25 * r - 0.25 - odds.win) / (1.0 - odds.win), &crs)
            }
        } else if combatIsBombard(attacker, defender) {
            let defenderUnit = defender as! Unit
            precondition(defenderUnit.isNaval, "Bombard of non-naval")
            if r <= odds.win {
                crs.append(.win)
                // Great wins are at most one in three successful
                // bombards, fewer against good defences.
                let offencePower = offencePower(attacker, defender)
                let defencePower = defencePower(attacker, defender)
                let diff = max(3.0, defencePower * 2.0 - offencePower)
                let great = r < odds.win / diff
                // Sink on great wins or without a repair location,
                // otherwise just damage.
                crs.append(great || defenderUnit.repairLocation == nil ? .sinkShipBombard : .damageShipBombard)
            } else {
                // The bombard fails, but the defender only evades: it
                // has no chance to return fire.
                crs.append(.noResult)
                crs.append(.evadeBombard)
            }
        } else {
            preconditionFailure("Bogus combat: \(String(describing: attacker)) v \(String(describing: defender))")
        }
        return CombatResult(crs)
    }

    /// Add what happens to the winner and loser of an attack.
    ///
    /// - Parameter r: The random number rescaled to [0, 1).
    func resolveAttack(_ winner: Unit, _ loser: Unit, _ great: Bool, _ r: Double,
                       _ crs: inout [CombatEffectType]) {
        let loserPlayer = loser.owner
        let tile = loser.tile
        let winnerPlayer = winner.owner
        let attackerWon = crs[0] == .win
        var loserMustDie = loser.hasAbility(Ability.disposeOnCombatLoss)
        if loser.isNaval {
            // Naval victors loot the hold.  Sink the loser on a great
            // win or loss, without a repair location, or beached.
            if winner.isNaval && winner.canCaptureGoods && !loser.goodsList.isEmpty {
                crs.append(.lootShip)
            }
            crs.append(great || loserMustDie || loser.repairLocation == nil || loser.isBeached
                       ? .sinkShipAttack : .damageShipAttack)
        } else { // A land unit lost
            // Autoequip the defender?
            let autoRole = attackerWon ? loser.automaticRole : nil
            if autoRole != nil { crs.append(.autoequipUnit) }
            // Settlements are special
            var done = false
            let settlement = tile?.settlement
            if let colony = settlement as? Colony {
                // A colony falls to Europeans when the last defender is
                // unarmed.  Natives pillage if they can, otherwise kill
                // colonists until it falls.  Ships in a falling colony
                // are damaged, or sunk without a repair location.
                if autoRole == nil && !loser.isDefensiveUnit {
                    let ships = colony.tile?.navalUnits ?? []
                    let shipResult: CombatEffectType? = ships.isEmpty ? nil
                        : ships[0].repairLocation == nil ? .sinkColonyShips : .damageColonyShips
                    if (winnerPlayer?.isEuropean ?? false) || (winnerPlayer?.isUndead ?? false) {
                        if loserMustDie { crs.append(.slaughterUnit) }
                        if let shipResult { crs.append(shipResult) }
                        crs.append(.captureColony)
                        done = true
                    } else if !great && colony.canBePillaged(winner) {
                        crs.append(.pillageColony)
                        done = true
                    } else if colony.unitCount > 1 || loser.location === tile {
                        loserMustDie = true
                        done = false // Treat as ordinary combat
                    } else {
                        crs.append(.slaughterUnit)
                        if let shipResult { crs.append(shipResult) }
                        crs.append(.destroyColony)
                        done = true
                    }
                }
            } else if let settlement = settlement as? IndianSettlement {
                // Beating the defender of a settlement with a mission may
                // bring converts, or the burning of the missions.  The
                // settlement falls when no units are in it or on its tile.
                var lose = 0
                if loserMustDie {
                    // Kill the loser before any convert is captured, or
                    // the convert might be the unit then killed.
                    crs.append(.slaughterUnit)
                    lose += 1
                    done = true
                }
                if attackerWon {
                    if r < Double(winner.convertProbability) {
                        if settlement.unitCount + (tile?.unitCount ?? 0) > lose
                            && settlement.hasMissionary(winnerPlayer)
                            && !combatIsAmphibious(winner, loser) {
                            crs.append(.captureConvert)
                            lose += 1
                        }
                    } else if r >= 1.0 - Double(winner.burnProbability) {
                        if loserPlayer?.indianSettlementList.contains(where: { $0.hasMissionary(winnerPlayer) })
                            ?? false {
                            crs.append(.burnMissions)
                        }
                    }
                }
                if settlement.unitCount + (tile?.unitCount ?? 0) <= lose {
                    crs.append(.destroySettlement)
                    done = true
                }
            }
            if !done {
                // An automatically armed loser: the winner may capture
                // the equipment, which may kill or demote the loser.
                if let autoRole {
                    crs.append(winner.canCaptureEquipment(autoRole) != nil ? .captureAutoequip : .loseAutoequip)
                    if loserMustDie {
                        crs.append(.slaughterUnit)
                    } else if loser.hasAbility(Ability.demoteOnAllEquipmentLost) {
                        crs.append(.demoteUnit)
                    }
                } else if loserMustDie {
                    // Some losers are just doomed (seasoned scouts).
                    crs.append(.slaughterUnit)
                } else if let loserRole = loser.role, loserRole.isOffensive {
                    // Other offensive equipment, captured or lost, which
                    // may kill or demote the loser.
                    crs.append(winner.canCaptureEquipment(loserRole) != nil ? .captureEquip : .loseEquip)
                    if loser.losingEquipmentKillsUnit {
                        crs.append(.slaughterUnit)
                    } else if loser.losingEquipmentDemotesUnit {
                        crs.append(.demoteUnit)
                    }
                } else if loser.hasAbility(Ability.canBeCaptured) && winner.hasAbility(Ability.captureUnits)
                            && !combatIsAmphibious(winner, loser) {
                    // Capture; any demotion is part of capturing.
                    crs.append(.captureUnit)
                } else if loser.unitChange(UnitChangeType.demotion) != nil {
                    crs.append(.demoteUnit)
                } else if winner.isUndead && !loser.isUndead
                            && loser.unitChange(UnitChangeType.undead, nil, winner.owner) != nil {
                    crs.append(.captureUnit)
                } else {
                    // The default is to kill them.
                    crs.append(.slaughterUnit)
                }
            }
        }
        // Promote great winners, or with automatic promotion, if possible.
        if let uc = winner.unitChange(UnitChangeType.promotion),
           winner.hasAbility(Ability.automaticPromotion)
            || (great && 100 * (r - r.rounded(.down)) <= Double(uc.probability)) {
            crs.append(.promoteUnit)
        }
    }

    private func isAmbush(_ attacker: FreeColGameObject?, _ defender: FreeColGameObject?) -> Bool {
        guard let a = attacker as? Unit, let d = defender as? Unit else { return false }
        return a.canAmbush(d)
    }
}

/// The combat model of the hit points mod (common/model/HitpointsCombatModel):
/// each side does random damage up to its power, and a unit is beaten
/// when its hit points run out.
public final class HitpointsCombatModel: SimpleCombatModel {

    public override init() {
        super.init()
    }

    public override func generateAttackResult(_ random: JavaRandom, _ attacker: FreeColGameObject?,
                                              _ defender: FreeColGameObject?) -> CombatResult {
        var crs: [CombatEffectType] = []
        let odds = calculateCombatOdds(attacker, defender)
        let r = RandomUtils.randomDouble("AttackResult", random)
        if combatIsAttack(attacker, defender) {
            let attackerUnit = attacker as! Unit, defenderUnit = defender as! Unit
            let defenderDamage = Int(random.nextInt(Int32(JavaMath.toInt(
                offencePower(attacker, defender).rounded(.up))) + 1))
            let newDefenderHitpoints = defenderUnit.hitPoints - defenderDamage
            if newDefenderHitpoints > 0 {
                var newAttackerHitpoints = -1
                let attackerRange = attackerUnit.type?.attackRange ?? 0
                let defenderRange = defenderUnit.type?.attackRange ?? 0
                if attackerRange <= defenderRange
                    || (attackerUnit.tile.map { defenderUnit.tile?.distance(to: $0) ?? 0 } ?? 0) <= defenderRange {
                    let attackerDamage = Int(random.nextInt(Int32(JavaMath.toInt(
                        defencePower(attacker, defender).rounded(.up))) + 1))
                    newAttackerHitpoints = attackerUnit.hitPoints - attackerDamage
                    if newAttackerHitpoints <= 0 {
                        crs.append(.lose)
                        resolveAttack(defenderUnit, attackerUnit, true,
                                      (1.25 * r - 0.25 - odds.win) / (1.0 - odds.win), &crs)
                        return CombatResult(crs, 1, newDefenderHitpoints)
                    }
                }
                crs.append(.win)
                return CombatResult(crs, newAttackerHitpoints, newDefenderHitpoints)
            }
            crs.append(.win)
            resolveAttack(attackerUnit, defenderUnit, true, r / (0.1 * odds.win), &crs)
            return CombatResult(crs, -1, 1)
        } else if combatIsBombard(attacker, defender) {
            let defenderUnit = defender as! Unit
            precondition(defenderUnit.isNaval, "Bombard of non-naval")
            let defenderDamage = Int(random.nextInt(Int32(JavaMath.toInt(
                offencePower(attacker, defender).rounded(.up))) + 1))
            if defenderDamage == 0 {
                return CombatResult([.noResult, .evadeBombard], -1, -1)
            }
            let newDefenderHitpoints = defenderUnit.hitPoints - defenderDamage
            if newDefenderHitpoints > 0 { return CombatResult([.win], -1, newDefenderHitpoints) }
            return CombatResult([.win, .sinkShipBombard], -1, -1)
        }
        preconditionFailure("Bogus combat: \(String(describing: attacker)) v \(String(describing: defender))")
    }
}

extension Game {
    /// The combat model the rules ask for.
    public var combatModel: CombatModel {
        (specification?.hasAbility(Ability.hitpointsCombatModel) ?? false)
            ? HitpointsCombatModel() : SimpleCombatModel()
    }
}

extension Specification {
    /// A built-in modifier source (Java's static Specification.Source).
    public func source(_ id: String) -> Source? {
        getType(id) as? Source
    }
}

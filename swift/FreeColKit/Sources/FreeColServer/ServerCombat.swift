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
import FreeColXML

/// Combat (ServerPlayer.csCombat and its results): attacks between
/// units and on settlements, and forts bombarding ships.
extension Player {

    public typealias CombatEffectType = CombatModel.CombatEffectType

    /// A combat that is not valid, as Java's IllegalStateException.
    public struct CombatFailed: Error, CustomStringConvertible {
        public let description: String
    }

    /// Fight: a unit attacking a unit, or a settlement bombarding a ship.
    /// The results come from the combat model unless given (csCombat).
    public func csCombat(_ attacker: FreeColGameObject, _ defender: FreeColGameObject,
                         _ results: [CombatEffectType]?, _ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game else { return }
        let combatModel = game.combatModel
        let isAttack = combatModel.combatIsAttack(attacker, defender)
        let isBombard = combatModel.combatIsBombard(attacker, defender)
        var attackerUnit: Unit?
        var attackerSettlement: Settlement?
        let attackerTile: Tile?
        let defenderUnit = defender as! Unit
        let defenderPlayer = defenderUnit.owner!
        let defenderTile = defenderUnit.tile!
        if isAttack {
            let au = attacker as! Unit
            attackerUnit = au
            attackerTile = au.tile
            let bombard = au.hasAbility(Ability.bombard)
            cs.addAttribute(.only(self), "sound", au.isNaval ? "sound.attack.naval"
                                : bombard ? "sound.attack.artillery"
                                : au.isMounted ? "sound.attack.mounted" : "sound.attack.foot")
            if au.owner?.isIndian ?? false, defenderPlayer.isEuropean,
               let colony = defenderUnit.location?.colony, !defenderPlayer.atWar(with: au.owner) {
                cs.addMessage(defenderPlayer, ModelMessage(.combatResult, "combat.raid.ours", colony)
                    .addName("%colony%", colony.name)
                    .addStringTemplate("%nation%", au.apparentOwnerName))
            }
        } else if isBombard {
            let s = attacker as! Settlement
            attackerSettlement = s
            attackerTile = s.tile
            cs.addAttribute(.only(self), "sound", "sound.attack.bombard")
        } else {
            preconditionFailure("Bogus combat: \(attacker) v \(defender)")
        }

        // The results, from the combat model unless given.
        var combatResult: CombatModel.CombatResult?
        var crs: [CombatEffectType]
        if let results {
            crs = results
        } else {
            let r = combatModel.generateAttackResult(random, attacker, defender)
            combatResult = r
            crs = r.effects
        }
        precondition(!crs.isEmpty, "empty attack result")

        // The main result, with the animation; the loser always sees.
        let vis: ChangeSet.See
        let result = crs.removeFirst()
        switch result {
        case .noResult:
            vis = .perhaps()
        case .win, .lose:
            vis = result == .win ? .perhaps().always(defenderPlayer) : .perhaps().always(self)
            if isAttack, let attackerTile, attackerTile !== defenderTile, attackerTile.isAdjacent(defenderTile) {
                try cs.addAttack(vis, attackerUnit!, defenderUnit, result == .win)
            }
        default:
            preconditionFailure("generateAttackResult returned: \(result)")
        }

        // The details.
        var attackerTileDirty = false, defenderTileDirty = false
        var moveAttacker = false, burnedNativeCapital = false
        let settlement = defenderTile.settlement
        let colony = defenderTile.colony
        let natives = settlement as? IndianSettlement
        var attackerTension = 0, defenderTension = 0

        if let combatResult, combatResult.isAttackerHitpointsAffected {
            attackerUnit?.hitPoints = combatResult.attackerHitpointsAfter
            attackerTileDirty = true
        }
        if let combatResult, combatResult.isDefenderHitpointsAffected {
            defenderUnit.hitPoints = combatResult.defenderHitpointsAfter
            defenderTileDirty = true
        }

        for cr in crs {
            var ok: Bool
            switch cr {
            case .autoequipUnit:
                ok = isAttack && settlement != nil
                if ok { csAutoequipUnit(defenderUnit, settlement!, cs) }
            case .burnMissions:
                ok = isAttack && result == .win && natives != nil && isEuropean && defenderPlayer.isIndian
                if ok {
                    if natives!.hasMissionary(self) { defenderTileDirty = true }
                    try csBurnMissions(attackerUnit!, natives!, cs)
                }
            case .captureAutoequip:
                ok = isAttack && result == .win && settlement != nil
                if ok {
                    csCaptureAutoEquip(attackerUnit!, defenderUnit, cs)
                    attackerTileDirty = true
                    defenderTileDirty = true
                }
            case .captureColony:
                ok = isAttack && result == .win && colony != nil && (isEuropean || isUndead)
                    && (defenderPlayer.isEuropean || defenderPlayer.isUndead)
                if ok {
                    try csCaptureColony(attackerUnit!, colony!, random, cs)
                    attackerTileDirty = false
                    defenderTileDirty = false
                    moveAttacker = true
                    defenderTension += Tension.tensionAddMajor
                }
            case .captureConvert:
                ok = isAttack && result == .win && natives != nil && isEuropean && defenderPlayer.isIndian
                if ok {
                    try csCaptureConvert(attackerUnit!, natives!, random, cs)
                    attackerTileDirty = true
                }
            case .captureEquip:
                ok = isAttack && result != .noResult
                if ok {
                    if result == .win {
                        csCaptureEquip(attackerUnit!, defenderUnit, cs)
                    } else {
                        csCaptureEquip(defenderUnit, attackerUnit!, cs)
                    }
                    attackerTileDirty = true
                    defenderTileDirty = true
                }
            case .captureUnit:
                ok = isAttack && result != .noResult
                if ok {
                    if result == .win {
                        try csCaptureUnit(attackerUnit!, defenderUnit, cs)
                    } else {
                        try csCaptureUnit(defenderUnit, attackerUnit!, cs)
                    }
                    attackerTileDirty = true
                    defenderTileDirty = false // Added in csCaptureUnit.
                }
            case .damageColonyShips:
                ok = isAttack && result == .win && colony != nil
                if ok {
                    try csDamageColonyShips(attackerUnit!, colony!, cs)
                    defenderTileDirty = true
                }
            case .damageShipAttack:
                ok = isAttack && result != .noResult && (result == .win ? defenderUnit : attackerUnit!).isNaval
                if ok {
                    if result == .win {
                        try csDamageShipAttack(attackerUnit!, defenderUnit, cs)
                        defenderTileDirty = true
                    } else {
                        try csDamageShipAttack(defenderUnit, attackerUnit!, cs)
                        attackerTileDirty = true
                    }
                }
            case .damageShipBombard:
                ok = isBombard && result == .win && defenderUnit.isNaval
                if ok {
                    try csDamageShipBombard(attackerSettlement!, defenderUnit, cs)
                    defenderTileDirty = true
                }
            case .demoteUnit:
                ok = isAttack && result != .noResult
                if ok {
                    if result == .win {
                        csDemoteUnit(attackerUnit!, defenderUnit, cs)
                        defenderTileDirty = true
                    } else {
                        csDemoteUnit(defenderUnit, attackerUnit!, cs)
                        attackerTileDirty = true
                    }
                }
            case .destroyColony:
                ok = isAttack && result == .win && colony != nil && isIndian && defenderPlayer.isEuropean
                if ok {
                    try csDestroyColony(attackerUnit!, colony!, random, cs)
                    attackerTileDirty = true
                    defenderTileDirty = true
                    moveAttacker = true
                    attackerTension -= Tension.tensionAddNormal
                    defenderTension += Tension.tensionAddMajor
                }
            case .destroySettlement:
                ok = isAttack && result == .win && natives != nil && defenderPlayer.isIndian
                if ok {
                    burnedNativeCapital = settlement!.isCapital
                    try csDestroySettlement(attackerUnit!, natives!, random, cs)
                    attackerTileDirty = true
                    defenderTileDirty = true
                    moveAttacker = true
                    attackerTension -= Tension.tensionAddNormal
                    if !burnedNativeCapital { defenderTension += Tension.tensionAddMajor }
                }
            case .evadeAttack:
                ok = isAttack && result == .noResult && defenderUnit.isNaval
                if ok { csEvadeAttack(attackerUnit!, defenderUnit, cs) }
            case .evadeBombard:
                ok = isBombard && result == .noResult && defenderUnit.isNaval
                if ok { csEvadeBombard(attackerSettlement!, defenderUnit, cs) }
            case .lootShip:
                ok = isAttack && result != .noResult && attackerUnit!.isNaval && defenderUnit.isNaval
                if ok {
                    if result == .win {
                        csLootShip(attackerUnit!, defenderUnit, cs)
                    } else {
                        csLootShip(defenderUnit, attackerUnit!, cs)
                    }
                }
            case .loseAutoequip:
                ok = isAttack && result == .win && settlement != nil
                if ok {
                    csLoseAutoEquip(attackerUnit!, defenderUnit, cs)
                    defenderTileDirty = true
                }
            case .loseEquip:
                ok = isAttack && result != .noResult
                if ok {
                    if result == .win {
                        csLoseEquip(attackerUnit!, defenderUnit, cs)
                        defenderTileDirty = true
                    } else {
                        csLoseEquip(defenderUnit, attackerUnit!, cs)
                        attackerTileDirty = true
                    }
                }
            case .pillageColony:
                ok = isAttack && result == .win && colony != nil && isIndian && defenderPlayer.isEuropean
                if ok {
                    try csPillageColony(attackerUnit!, colony!, random, cs)
                    defenderTileDirty = true
                    attackerTension -= Tension.tensionAddNormal
                }
            case .promoteUnit:
                ok = isAttack && result != .noResult
                if ok {
                    if result == .win {
                        csPromoteUnit(attackerUnit!, cs)
                        attackerTileDirty = true
                    } else {
                        csPromoteUnit(defenderUnit, cs)
                        defenderTileDirty = true
                    }
                }
            case .sinkColonyShips:
                ok = isAttack && result == .win && colony != nil
                if ok {
                    try csSinkColonyShips(attackerUnit!, colony!, cs)
                    defenderTileDirty = true
                }
            case .sinkShipAttack:
                ok = isAttack && result != .noResult && (result == .win ? defenderUnit : attackerUnit!).isNaval
                if ok {
                    if result == .win {
                        try csSinkShipAttack(attackerUnit!, defenderUnit, cs)
                        defenderTileDirty = true
                    } else {
                        try csSinkShipAttack(defenderUnit, attackerUnit!, cs)
                        attackerTileDirty = true
                    }
                }
            case .sinkShipBombard:
                ok = isBombard && result == .win && defenderUnit.isNaval
                if ok {
                    try csSinkShipBombard(attackerSettlement!, defenderUnit, cs)
                    defenderTileDirty = true
                }
            case .slaughterUnit:
                ok = isAttack && result != .noResult
                if ok {
                    if result == .win {
                        try csSlaughterUnit(attackerUnit!, defenderUnit, cs)
                        defenderTileDirty = true
                        attackerTension -= Tension.tensionAddNormal
                        defenderTension += slaughterTension(defenderUnit)
                    } else {
                        try csSlaughterUnit(defenderUnit, attackerUnit!, cs)
                        attackerTileDirty = true
                        attackerTension += slaughterTension(attackerUnit!)
                        defenderTension -= Tension.tensionAddNormal
                    }
                }
            default:
                ok = false
            }
            if !ok { throw CombatFailed(description: "Attack (result=\(result)) has bogus subresult: \(cr)") }
        }

        // Stance and tension: privateers only mark their victims,
        // Europeans fighting means war, burning a native capital means
        // surrender, and otherwise natives' tension changes.
        if attacker.hasAbility(Ability.piracy) {
            if !defenderPlayer.attackedByPrivateers {
                defenderPlayer.attackedByPrivateers = true
                cs.addPartial(.only(defenderPlayer), defenderPlayer, ("attackedByPrivateers", "true"))
            }
        } else if defender.hasAbility(Ability.piracy) {
            // Nothing.
        } else if burnedNativeCapital {
            var t = defenderPlayer.tension(self)
            t.setValue(Tension.surrendered)
            defenderPlayer.setTension(self, t)
            cs.add(.perhaps().always(self), defenderPlayer)
            try csChangeStance(.peace, defenderPlayer, true, cs)
            for s in defenderPlayer.indianSettlementList where s.hasContacted(self) {
                if var a = s.alarm(self) {
                    a.setValue(Tension.surrendered)
                    s.storeAlarm(self, a) // Java sets it in place.
                }
                // The attacker sees only the settlements it has seen.
                if let st = s.tile, hasExplored(st) {
                    cs.add(.perhaps().always(self), s)
                } else {
                    cs.add(.only(defenderPlayer), s)
                }
            }
        } else if isEuropean && defenderPlayer.isEuropean {
            try csChangeStance(.war, defenderPlayer, true, cs)
        } else {
            if isEuropean {
                try csChangeStance(.war, defenderPlayer, true, cs)
            } else if isIndian {
                if result == .win { attackerTension -= Tension.tensionAddMinor }
                else if result == .lose { attackerTension += Tension.tensionAddMinor }
            }
            if defenderPlayer.isEuropean {
                try defenderPlayer.csChangeStance(.war, self, true, cs)
            } else if defenderPlayer.isIndian {
                if result == .win { defenderTension += Tension.tensionAddMinor }
                else if result == .lose { defenderTension -= Tension.tensionAddMinor }
            }
            if attackerTension != 0 { try csModifyTension(defenderPlayer, attackerTension, nil, cs) }
            if defenderTension != 0 { try defenderPlayer.csModifyTension(self, defenderTension, nil, cs) }
        }

        // Move the attacker in, if it won the place.
        if moveAttacker, let au = attackerUnit {
            au.movesLeft = au.initialMovesLeft
            try au.csMove(defenderTile, random, cs)
            au.movesLeft = 0
            // The move updates the tiles, as perhaps seen; the defender
            // may not see that, its settlement gone, so tell it too.
            attackerTileDirty = false
            defenderTileDirty = false
            cs.add(.only(defenderPlayer), defenderTile)
        } else if isAttack, let au = attackerUnit {
            // Units that attack again spend the cost of the move; others
            // spend everything.
            if attacker.hasAbility(Ability.multipleAttacks) {
                au.movesLeft -= au.moveCost(defenderTile)
            } else {
                au.movesLeft = 0
            }
            if !attackerTileDirty {
                cs.addPartial(.only(self), attacker, ("movesLeft", String(au.movesLeft)))
            }
        }

        if attackerTileDirty {
            if let attackerSettlement { cs.remove(attackerSettlement) }
            cs.add(vis, attackerTile)
        }
        if defenderTileDirty {
            if let settlement { cs.remove(settlement) }
            cs.add(vis, defenderTile)
        }
    }

    /// How much tension rises when a unit dies (getSlaughterTension).
    private func slaughterTension(_ loser: Unit) -> Int {
        if let settlement = loser.settlement {
            if settlement is IndianSettlement {
                return settlement.isCapital ? Tension.tensionAddCapitalAttacked : Tension.tensionAddSettlementAttacked
            }
            return Tension.tensionAddNormal
        }
        return loser.homeIndianSettlement != nil ? Tension.tensionAddUnitDestroyed : Tension.tensionAddMinor
    }

    // MARK: Results

    private func csAutoequipUnit(_ unit: Unit, _ settlement: Settlement, _ cs: ChangeSet) {
        guard let owner = unit.owner else { return }
        cs.addMessage(owner, ModelMessage(.combatResult, "combat.automaticDefence", unit)
            .addStringTemplate("%unit%", unit.label)
            .addName("%colony%", settlement.name))
    }

    private func csBurnMissions(_ attacker: Unit, _ settlement: IndianSettlement, _ cs: ChangeSet) throws {
        guard let attackerPlayer = attacker.owner, let nativePlayer = settlement.owner else { return }
        cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.burnMissions", attacker, settlement)
            .addStringTemplate("%nation%", attackerPlayer.nationLabel)
            .addStringTemplate("%enemyNation%", nativePlayer.nationLabel))
        let here = settlement.hasMissionary(attackerPlayer)
        for s in nativePlayer.indianSettlementsWithMissionary(attackerPlayer) { try s.csKillMissionary(nil, cs) }
        // Do not update this tile twice.
        if here, let tile = settlement.tile { cs.remove(tile) }
    }

    private func csCaptureAutoEquip(_ attacker: Unit, _ defender: Unit, _ cs: ChangeSet) {
        let role = defender.automaticRole
        csLoseAutoEquip(attacker, defender, cs)
        if let role { csCaptureEquipment(attacker, defender, role, cs) }
    }

    private func csCaptureColony(_ attacker: Unit, _ colony: Colony, _ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game, let attackerPlayer = attacker.owner, let colonyPlayer = colony.owner,
              let tile = colony.tile else { return }
        let attackerNation = attacker.apparentOwnerName
        let colonyNation = colonyPlayer.nationLabel
        let plunder = colony.plunder(attacker, random)
        cs.addHistory(attackerPlayer, HistoryEvent(game.turn, .conquerColony, attackerPlayer)
            .addStringTemplate("%nation%", colonyNation)
            .addName("%colony%", colony.name))
        cs.addHistory(colonyPlayer, HistoryEvent(game.turn, .colonyConquered, attackerPlayer)
            .addStringTemplate("%nation%", attackerNation)
            .addName("%colony%", colony.name))
        cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.colonyCaptured.enemy", colony)
            .addName("%colony%", colony.name)
            .addStringTemplate("%unit%", attacker.label)
            .addStringTemplate("%enemyNation%", colonyNation)
            .addAmount("%amount%", plunder))
        cs.addMessage(colonyPlayer, ModelMessage(.combatResult, "combat.colonyCaptured.ours", tile)
            .addName("%colony%", colony.name)
            .addStringTemplate("%enemyUnit%", attacker.label)
            .addStringTemplate("%enemyNation%", attackerNation)
            .addAmount("%amount%", plunder))
        colonyPlayer.csLoseLocation(colony, cs)
        if plunder > 0 {
            _ = attackerPlayer.modifyGold(plunder)
            _ = colonyPlayer.modifyGold(-plunder)
            cs.addPartial(.only(attackerPlayer), attackerPlayer, ("gold", String(attackerPlayer.gold)))
            cs.addPartial(.only(colonyPlayer), colonyPlayer, ("gold", String(colonyPlayer.gold)))
        }
        // Goods parties were for the other monarch.
        for m in colony.allModifiers where m.source?.id == Specification.SourceId.colonyGoodsParty {
            colony.removeModifier(m)
        }
        try colony.csChangeOwner(attackerPlayer, true, UnitChangeType.capture, cs)
        cs.addAttribute(.only(attackerPlayer), "sound", "sound.event.captureColony")
        attackerPlayer.invalidateCanSeeTiles()
        colonyPlayer.invalidateCanSeeTiles()
    }

    private func csCaptureConvert(_ attacker: Unit, _ settlement: IndianSettlement, _ random: JavaRandom,
                                  _ cs: ChangeSet) throws {
        guard let spec = specification, let attackerPlayer = attacker.owner, let nativePlayer = settlement.owner,
              let convert = RandomUtils.randomMember("Choose convert", settlement.allUnitsList, random) else { return }
        if try nativePlayer.csChangeOwner(convert, attackerPlayer, UnitChangeType.conversion, attacker.tile, cs) {
            if let role = spec.defaultRole { convert.changeRole(role, 0) }
            for g in convert.compactGoodsList { _ = convert.remove(g) }
            convert.movesLeft = 0
            convert.setState(.active)
            cs.add(.only(nativePlayer), settlement.tile)
            cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.newConvertFromAttack", convert)
                .addStringTemplate("%unit%", attacker.label)
                .addStringTemplate("%enemyNation%", nativePlayer.nationLabel)
                .addStringTemplate("%enemyUnit%", convert.label))
            attackerPlayer.invalidateCanSeeTiles()
        }
    }

    private func csCaptureEquip(_ winner: Unit, _ loser: Unit, _ cs: ChangeSet) {
        let role = loser.role
        csLoseEquip(winner, loser, cs)
        if let role { csCaptureEquipment(winner, loser, role, cs) }
    }

    private func csCaptureEquipment(_ winner: Unit, _ loser: Unit, _ role: Role, _ cs: ChangeSet) {
        guard let winnerPlayer = winner.owner, let loserPlayer = loser.owner,
              let newRole = winner.canCaptureEquipment(role) else { return }
        let newGoods = winner.goodsDifference(newRole, 1)
        let goodsType = newGoods.first?.type
        winner.changeRole(newRole, 1)
        // Only natives capture equipment, so the message is theirs.
        guard winnerPlayer.isIndian else { return }
        if let goodsType {
            cs.addMessage(loserPlayer, ModelMessage(.combatResult, "combat.equipmentCaptured", winnerPlayer)
                .addStringTemplate("%nation%", winner.apparentOwnerName)
                .addNamed("%equipment%", goodsType))
        }
        // As in Col1, the goods go straight home.
        if let home = winner.homeIndianSettlement {
            for ag in newGoods {
                if let t = ag.type { _ = home.addGoods(t, ag.amount) }
            }
            cs.add(.only(winnerPlayer), home)
        }
    }

    private func csCaptureUnit(_ winner: Unit, _ loser: Unit, _ cs: ChangeSet) throws {
        guard let loserPlayer = loser.owner, let winnerPlayer = winner.owner, let loserType = loser.type else { return }
        let loserNation = loserPlayer.nationLabel
        let loserLocation = locationLabel(loser.location, for: loserPlayer)
        let loserLabel = loser.label
        let winnerNation = winner.apparentOwnerName
        let winnerLocation = locationLabel(winner.location, for: winnerPlayer)
        let oldTile = loser.tile
        if try loserPlayer.csChangeOwner(loser, winnerPlayer, UnitChangeType.capture, winner.tile, cs) {
            loser.movesLeft = 0
            loser.setState(.active)
            cs.add(.perhaps().always(loserPlayer), oldTile)
            cs.addMessage(winnerPlayer, ModelMessage(.combatResult, "combat.unitCaptured.enemy." + (loserType.suffix ?? ""),
                                                     loser)
                .addDefaultId("combat.unitCaptured.enemy")
                .addStringTemplate("%location%", winnerLocation)
                .addStringTemplate("%unit%", winner.label)
                .addStringTemplate("%enemyNation%", loserNation)
                .addStringTemplate("%enemyUnit%", loserLabel))
        }
        cs.addMessage(loserPlayer, ModelMessage(.combatResult, "combat.unitCaptured.ours." + (loserType.suffix ?? ""),
                                                oldTile!)
            .addDefaultId("combat.unitCaptured.ours")
            .addStringTemplate("%location%", loserLocation)
            .addStringTemplate("%unit%", loserLabel)
            .addStringTemplate("%enemyNation%", winnerNation)
            .addStringTemplate("%enemyUnit%", winner.label))
        winnerPlayer.invalidateCanSeeTiles()
        loserPlayer.invalidateCanSeeTiles()
    }

    /// The colony's ships that a win reaches, leaving those being
    /// repaired if the rules let them be captured.
    private func colonyShips(_ colony: Colony) -> [Unit] {
        let captureRepairing = specification?.getBoolean(GameOptions.captureUnitsUnderRepair) ?? false
        return (colony.tile?.unitList ?? []).filter { $0.isNaval && !(captureRepairing && $0.isDamaged) }
    }

    private func csDamageColonyShips(_ attacker: Unit, _ colony: Colony, _ cs: ChangeSet) throws {
        let units = colonyShips(colony)
        guard let ship = units.first, let shipPlayer = colony.owner else { return }
        let repair = ship.repairLocation
        var t = StringTemplate.label(", ")
        for u in units {
            if let repair { csDamageShip(u, repair, cs) }
            t = t.addStringTemplate(u.label)
        }
        cs.addMessage(shipPlayer, ModelMessage(.combatResult, "combat.shipsDamaged", shipPlayer)
            .addStringTemplate("%ships%", t)
            .addAmount("%number%", units.count)
            .addStringTemplate("%repairLocation%", locationLabel(repair, for: shipPlayer)))
    }

    private func csDamageShipAttack(_ attacker: Unit, _ ship: Unit, _ cs: ChangeSet) throws {
        guard let attackerPlayer = attacker.owner, let shipPlayer = ship.owner else { return }
        let shipLocation = ship.location
        let repair = ship.repairLocation
        cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.shipDamaged.enemy", attacker)
            .addStringTemplate("%location%", locationLabel(shipLocation, for: attackerPlayer))
            .addStringTemplate("%unit%", attacker.label)
            .addStringTemplate("%enemyNation%", ship.apparentOwnerName)
            .addStringTemplate("%enemyUnit%", ship.label))
        cs.addMessage(shipPlayer, ModelMessage(.combatResult, "combat.shipDamaged.ours", ship)
            .addStringTemplate("%location%", locationLabel(shipLocation, for: shipPlayer))
            .addStringTemplate("%unit%", ship.label)
            .addStringTemplate("%enemyUnit%", attacker.label)
            .addStringTemplate("%enemyNation%", attacker.apparentOwnerName)
            .addStringTemplate("%repairLocation%", locationLabel(repair, for: shipPlayer)))
        if let repair { csDamageShip(ship, repair, cs) }
    }

    private func csDamageShipBombard(_ settlement: Settlement, _ ship: Unit, _ cs: ChangeSet) throws {
        guard let attackerPlayer = settlement.owner, let shipPlayer = ship.owner else { return }
        let building = (settlement as? Colony)?.stockade
        let repair = ship.repairLocation
        var enemy = ModelMessage(.combatResult, "combat.shipDamagedByBombardment.enemy", settlement)
            .addStringTemplate("%location%", locationLabel(settlement, for: attackerPlayer))
        if let building { enemy = enemy.addNamed("%building%", building) }
        cs.addMessage(attackerPlayer, enemy
            .addStringTemplate("%enemyNation%", ship.apparentOwnerName)
            .addStringTemplate("%enemyUnit%", ship.label))
        var ours = ModelMessage(.combatResult, "combat.shipDamagedByBombardment.ours", ship)
            .addStringTemplate("%location%", locationLabel(settlement, for: shipPlayer))
            .addStringTemplate("%unit%", ship.label)
        if let building { ours = ours.addNamed("%building%", building) }
        cs.addMessage(shipPlayer, ours
            .addStringTemplate("%enemyNation%", attackerPlayer.nationLabel)
            .addStringTemplate("%repairLocation%", locationLabel(repair, for: shipPlayer)))
        if let repair { csDamageShip(ship, repair, cs) }
    }

    private func csDemoteUnit(_ winner: Unit, _ loser: Unit, _ cs: ChangeSet) {
        guard let loserPlayer = loser.owner, let winnerPlayer = winner.owner else { return }
        let loserNation = loser.apparentOwnerName
        let loserLocation = locationLabel(loser.location, for: loserPlayer)
        let loserLabel = loser.label
        let winnerNation = winner.apparentOwnerName
        let winnerLocation = locationLabel(winner.location, for: winnerPlayer)
        let suffix = loser.type?.suffix ?? "" // Before the demotion.
        guard let uc = loser.unitChange(UnitChangeType.demotion), let to = uc.to, to !== loser.type else { return }
        _ = loser.changeType(to)
        loserPlayer.invalidateCanSeeTiles()
        cs.addMessage(winnerPlayer, ModelMessage(.combatResult, "combat.unitDemoted.enemy." + suffix, winner)
            .addDefaultId("combat.unitDemoted.enemy")
            .addStringTemplate("%location%", winnerLocation)
            .addStringTemplate("%unit%", winner.label)
            .addStringTemplate("%enemyNation%", loserNation)
            .addStringTemplate("%oldName%", loserLabel)
            .addStringTemplate("%enemyUnit%", loser.label))
        cs.addMessage(loserPlayer, ModelMessage(.combatResult, "combat.unitDemoted.ours." + suffix, loser)
            .addDefaultId("combat.unitDemoted.ours")
            .addStringTemplate("%location%", loserLocation)
            .addStringTemplate("%oldName%", loserLabel)
            .addStringTemplate("%unit%", loser.label)
            .addStringTemplate("%enemyNation%", winnerNation)
            .addStringTemplate("%enemyUnit%", winner.label))
    }

    private func csDestroyColony(_ attacker: Unit, _ colony: Colony, _ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game, let attackerPlayer = attacker.owner, let colonyPlayer = colony.owner else { return }
        let attackerNation = attacker.apparentOwnerName
        let colonyNation = colonyPlayer.nationLabel
        let plunder = colony.plunder(attacker, random)
        cs.addHistory(colonyPlayer, HistoryEvent(game.turn, .colonyDestroyed, attackerPlayer)
            .addStringTemplate("%nation%", attackerNation)
            .addName("%colony%", colony.name))
        cs.addMessage(colonyPlayer, ModelMessage(.combatResult, "combat.colonyBurned.ours", colony.tile!)
            .addName("%colony%", colony.name)
            .addStringTemplate("%enemyNation%", attackerNation)
            .addStringTemplate("%enemyUnit%", attacker.label)
            .addAmount("%amount%", plunder))
        cs.addGlobalMessage(game, colonyPlayer, ModelMessage(.combatResult, "combat.colonyBurned.other", colonyPlayer)
            .addName("%colony%", colony.name)
            .addStringTemplate("%nation%", colonyNation)
            .addStringTemplate("%attackerNation%", attackerNation))
        colonyPlayer.csLoseLocation(colony, cs)
        if plunder > 0 {
            _ = attackerPlayer.modifyGold(plunder)
            _ = colonyPlayer.modifyGold(-plunder)
            cs.addPartial(.only(attackerPlayer), attackerPlayer, ("gold", String(attackerPlayer.gold)))
            cs.addPartial(.only(colonyPlayer), colonyPlayer, ("gold", String(colonyPlayer.gold)))
        }
        try csDisposeSettlement(colony, cs)
    }

    private func csDestroySettlement(_ attacker: Unit, _ settlement: IndianSettlement, _ random: JavaRandom,
                                     _ cs: ChangeSet) throws {
        guard let game, let spec = specification, let tile = settlement.tile, let attackerPlayer = attacker.owner,
              let nativePlayer = settlement.owner else { return }
        let attackerNation = attackerPlayer.nationLabel
        let nativeNation = nativePlayer.nationLabel
        let settlementName = settlement.name
        let capital = settlement.isCapital
        let plunder = settlement.plunder(attacker, random)
        // The settlement's units lose their home.
        for u in settlement.ownedUnitList {
            u.changeHomeIndianSettlement(nil)
            cs.add(.only(nativePlayer), u)
        }
        try csDisposeSettlement(settlement, cs)
        if plunder > 0,
           let type = RandomUtils.randomMember("Choose train", spec.unitTypes(withAnyAbility: Ability.carryTreasure),
                                               random) {
            let train = Unit(game: game, location: tile, owner: attackerPlayer, type: type)
            train.treasureAmount = plunder
        }
        // An atrocity.
        let h = HistoryEvent(game.turn, .destroySettlement, self)
            .addStringTemplate("%nation%", nativeNation)
            .addName("%settlement%", settlementName)
        h.score = spec.getInteger(GameOptions.destroySettlementScore) ?? 0
        cs.addHistory(attackerPlayer, h)
        cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.destroySettlement.enemy", attacker)
            .addName("%settlement%", settlementName)
            .addStringTemplate("%unit%", attacker.label)
            .addStringTemplate("%nativeNation%", nativeNation)
            .addAmount("%amount%", plunder))
        if capital {
            cs.addMessage(attackerPlayer, ModelMessage(.foreignDiplomacy, "combat.destroySettlement.enemy.capital",
                                                       attacker)
                .addStringTemplate("%nation%", nativeNation))
        }
        if nativePlayer.checkForDeath() == .isDead {
            let dh = HistoryEvent(game.turn, .destroyNation, self)
                .addStringTemplate("%nation%", attackerNation)
                .addStringTemplate("%nativeNation%", nativeNation)
            dh.score = Player.scoreNationDestroyed
            cs.addGlobalHistory(game, dh)
        }
        cs.addAttribute(.only(attackerPlayer), "sound", "sound.event.destroySettlement")
    }

    static let scoreNationDestroyed = -50

    private func csEvadeAttack(_ attacker: Unit, _ defender: Unit, _ cs: ChangeSet) {
        guard let attackerPlayer = attacker.owner, let defenderPlayer = defender.owner else { return }
        cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.shipEvaded.enemy", attacker)
            .addStringTemplate("%location%", locationLabel(attacker.location, for: attackerPlayer))
            .addStringTemplate("%unit%", attacker.label)
            .addStringTemplate("%enemyNation%", defender.apparentOwnerName)
            .addStringTemplate("%enemyUnit%", defender.label))
        cs.addMessage(defenderPlayer, ModelMessage(.combatResult, "combat.shipEvaded.ours", defender)
            .addStringTemplate("%location%", locationLabel(defender.location, for: defenderPlayer))
            .addStringTemplate("%unit%", defender.label)
            .addStringTemplate("%enemyNation%", attacker.apparentOwnerName)
            .addStringTemplate("%enemyUnit%", attacker.label))
    }

    private func csEvadeBombard(_ settlement: Settlement, _ defender: Unit, _ cs: ChangeSet) {
        guard let attackerPlayer = settlement.owner, let defenderPlayer = defender.owner else { return }
        let building = (settlement as? Colony)?.stockade
        var enemy = ModelMessage(.combatResult, "combat.shipEvadedBombardment.enemy", settlement)
            .addStringTemplate("%location%", locationLabel(settlement, for: attackerPlayer))
        if let building { enemy = enemy.addNamed("%building%", building) }
        cs.addMessage(attackerPlayer, enemy
            .addStringTemplate("%enemyNation%", defender.apparentOwnerName)
            .addStringTemplate("%enemyUnit%", defender.label))
        var ours = ModelMessage(.combatResult, "combat.shipEvadedBombardment.ours", defender)
            .addStringTemplate("%location%", locationLabel(settlement, for: defenderPlayer))
            .addStringTemplate("%unit%", defender.label)
        if let building { ours = ours.addNamed("%building%", building) }
        cs.addMessage(defenderPlayer, ours.addStringTemplate("%enemyNation%", attackerPlayer.nationLabel))
    }

    private func csLootShip(_ winner: Unit, _ loser: Unit, _ cs: ChangeSet) {
        guard let winnerPlayer = winner.owner, let game = game as? ServerGame else { return }
        let capture = loser.goodsList
        if !capture.isEmpty && winner.hasSpaceLeft {
            for g in capture { _ = g.setLocation(nil) }
            LootSession.register(winner, loser, capture, in: game.sessions)
            cs.add(.only(winnerPlayer), message: LootCargoMessage(winner, loser.id ?? "", capture))
        }
        loser.goodsContainer?.removeAll()
        loser.setState(.active)
    }

    private func csLoseAutoEquip(_ attacker: Unit, _ defender: Unit, _ cs: ChangeSet) {
        guard let defenderPlayer = defender.owner, let attackerPlayer = attacker.owner,
              let settlement = defender.settlement, let role = defender.automaticRole else { return }
        let defenderLabel = Messages.unitLabel(nil, defender.type?.id, 1, defenderPlayer.nation?.id, role.id, nil)
        // The equipment is the settlement's.
        for ag in role.requiredGoods {
            if let t = ag.type { _ = settlement.removeGoods(t, ag.amount) }
        }
        cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.unitDemotedToUnarmed.enemy", attacker)
            .addStringTemplate("%location%", locationLabel(settlement, for: attackerPlayer))
            .addStringTemplate("%unit%", attacker.label)
            .addStringTemplate("%oldName%", defenderLabel)
            .addStringTemplate("%enemyNation%", defenderPlayer.nationLabel)
            .addStringTemplate("%enemyUnit%", defender.label))
        cs.addMessage(defenderPlayer, ModelMessage(.combatResult, "combat.unitLoseAutoEquip", defender)
            .addStringTemplate("%location%", locationLabel(settlement, for: defenderPlayer))
            .addStringTemplate("%unit%", defender.label)
            .addStringTemplate("%enemyNation%", attacker.apparentOwnerName)
            .addStringTemplate("%enemyUnit%", attacker.label))
    }

    private func csLoseEquip(_ winner: Unit, _ loser: Unit, _ cs: ChangeSet) {
        guard let spec = specification, let loserPlayer = loser.owner, let winnerPlayer = winner.owner else { return }
        let loserNation = loserPlayer.nationLabel
        let loserLocation = locationLabel(loser.location, for: loserPlayer)
        let loserLabel = loser.label
        let winnerNation = winner.apparentOwnerName
        let winnerLocation = locationLabel(winner.location, for: winnerPlayer)
        if let downgrade = loser.role?.downgrade {
            loser.changeRole(downgrade, 1)
        } else if let role = spec.defaultRole {
            loser.changeRole(role, 0)
        }
        // Horses may have gone.
        loser.movesLeft = min(loser.movesLeft, loser.initialMovesLeft)
        if !loser.isArmed {
            cs.addMessage(winnerPlayer, ModelMessage(.combatResult, "combat.unitDemotedToUnarmed.enemy", winner)
                .addStringTemplate("%location%", winnerLocation)
                .addStringTemplate("%unit%", winner.label)
                .addStringTemplate("%oldName%", loserLabel)
                .addStringTemplate("%enemyNation%", loserNation)
                .addStringTemplate("%enemyUnit%", loser.label))
            cs.addMessage(loserPlayer, ModelMessage(.combatResult, "combat.unitDemotedToUnarmed.ours", loser)
                .addStringTemplate("%location%", loserLocation)
                .addStringTemplate("%oldName%", loserLabel)
                .addStringTemplate("%unit%", loser.label)
                .addStringTemplate("%enemyNation%", winnerNation)
                .addStringTemplate("%enemyUnit%", winner.label))
            loser.setState(.active)
        } else {
            let suffix = loser.type?.suffix ?? ""
            cs.addMessage(winnerPlayer, ModelMessage(.combatResult, "combat.unitDemoted.enemy." + suffix, winner)
                .addDefaultId("combat.unitDemoted.enemy")
                .addStringTemplate("%location%", winnerLocation)
                .addStringTemplate("%unit%", winner.label)
                .addStringTemplate("%oldName%", loserLabel)
                .addStringTemplate("%enemyNation%", loserNation)
                .addStringTemplate("%enemyUnit%", loser.label))
            cs.addMessage(loserPlayer, ModelMessage(.combatResult, "combat.unitDemoted.ours." + suffix, loser)
                .addDefaultId("combat.unitDemoted.ours")
                .addStringTemplate("%location%", loserLocation)
                .addStringTemplate("%oldName%", loserLabel)
                .addStringTemplate("%unit%", loser.label)
                .addStringTemplate("%enemyNation%", winnerNation)
                .addStringTemplate("%enemyUnit%", winner.label))
        }
    }

    private func csPillageColony(_ attacker: Unit, _ colony: Colony, _ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game, let attackerPlayer = attacker.owner, let colonyPlayer = colony.owner else { return }
        let attackerNation = attacker.apparentOwnerName
        let colonyNation = colonyPlayer.nationLabel
        let buildingList = colony.burnableBuildings
        let shipList = colony.tile?.navalUnits ?? []
        let goodsList = colony.lootableGoodsList
        // One more choice, to steal gold.
        let pillage = Int(RandomUtils.randomInt("Pillage choice", random,
                                                Int32(buildingList.count + shipList.count + goodsList.count
                                                      + (colony.canBePlundered ? 1 : 0))))
        if pillage < buildingList.count {
            let building = buildingList[pillage]
            try csDamageBuilding(building, cs)
            var m = ModelMessage(.combatResult, "combat.raid.building", colony).addName("%colony%", colony.name)
            if let bt = building.type { m = m.addNamed("%building%", bt) }
            cs.addMessage(colonyPlayer, m
                .addStringTemplate("%enemyNation%", attackerNation)
                .addStringTemplate("%enemyUnit%", attacker.label))
        } else if pillage < buildingList.count + shipList.count {
            let ship = shipList[pillage - buildingList.count]
            if ship.repairLocation == nil {
                try csSinkShipAttack(attacker, ship, cs)
            } else {
                try csDamageShipAttack(attacker, ship, cs)
            }
        } else if pillage < buildingList.count + shipList.count + goodsList.count {
            let goods = goodsList[pillage - buildingList.count - shipList.count]
            goods.amount = min(goods.amount / 2, 50)
            _ = colony.removeGoods(goods)
            if attacker.canAdd(goods) { _ = attacker.add(goods) }
            var m = ModelMessage(.combatResult, "combat.raid.goods", colony, goods)
                .addName("%colony%", colony.name)
                .addAmount("%amount%", goods.amount)
            if let gt = goods.type { m = m.addNamed("%goods%", gt) }
            cs.addMessage(colonyPlayer, m
                .addStringTemplate("%enemyNation%", attackerNation)
                .addStringTemplate("%enemyUnit%", attacker.label))
        } else {
            let plunder = max(1, colony.plunder(attacker, random) / 5)
            _ = colonyPlayer.modifyGold(-plunder)
            _ = attackerPlayer.modifyGold(plunder)
            cs.addPartial(.only(colonyPlayer), colonyPlayer, ("gold", String(colonyPlayer.gold)))
            cs.addMessage(colonyPlayer, ModelMessage(.combatResult, "combat.raid.plunder", colony)
                .addAmount("%amount%", plunder)
                .addName("%colony%", colony.name)
                .addStringTemplate("%enemyNation%", attackerNation)
                .addStringTemplate("%enemyUnit%", attacker.label))
        }
        cs.addGlobalMessage(game, colonyPlayer, ModelMessage(.combatResult, "combat.raid.other", colonyPlayer)
            .addName("%colony%", colony.name)
            .addStringTemplate("%colonyNation%", colonyNation)
            .addStringTemplate("%nation%", attackerNation))
    }

    private func csPromoteUnit(_ winner: Unit, _ cs: ChangeSet) {
        guard let winnerPlayer = winner.owner else { return }
        let winnerLabel = winner.label
        guard let uc = winner.unitChange(UnitChangeType.promotion), let to = uc.to, to !== winner.type else { return }
        _ = winner.changeType(to)
        winnerPlayer.invalidateCanSeeTiles()
        cs.addMessage(winnerPlayer, ModelMessage(.combatResult, "combat.unitPromoted", winner)
            .addStringTemplate("%oldName%", winnerLabel)
            .addStringTemplate("%unit%", winner.label))
    }

    private func csSinkColonyShips(_ attacker: Unit, _ colony: Colony, _ cs: ChangeSet) throws {
        let units = colonyShips(colony)
        guard !units.isEmpty, let shipPlayer = colony.owner else { return }
        var t = StringTemplate.label(", ")
        for u in units {
            try csSinkShip(u, attacker.owner, cs)
            t = t.addStringTemplate(u.label)
        }
        cs.addMessage(shipPlayer, ModelMessage(.combatResult, "combat.shipsSunk", shipPlayer)
            .addStringTemplate("%ships%", t)
            .addAmount("%number%", units.count))
    }

    private func csSinkShipAttack(_ attacker: Unit, _ ship: Unit, _ cs: ChangeSet) throws {
        guard let shipPlayer = ship.owner, let attackerPlayer = attacker.owner else { return }
        let shipLocation = ship.location
        cs.addMessage(attackerPlayer, ModelMessage(.combatResult, "combat.shipSunk.enemy", attacker)
            .addStringTemplate("%location%", locationLabel(shipLocation, for: attackerPlayer))
            .addStringTemplate("%unit%", attacker.label)
            .addStringTemplate("%enemyUnit%", ship.label)
            .addStringTemplate("%enemyNation%", ship.apparentOwnerName))
        cs.addMessage(shipPlayer, ModelMessage(.combatResult, "combat.shipSunk.ours", ship.tile!)
            .addStringTemplate("%location%", locationLabel(shipLocation, for: shipPlayer))
            .addStringTemplate("%unit%", ship.label)
            .addStringTemplate("%enemyUnit%", attacker.label)
            .addStringTemplate("%enemyNation%", attacker.apparentOwnerName))
        try csSinkShip(ship, attackerPlayer, cs)
    }

    private func csSinkShipBombard(_ settlement: Settlement, _ ship: Unit, _ cs: ChangeSet) throws {
        guard let attackerPlayer = settlement.owner, let shipPlayer = ship.owner else { return }
        let building = (settlement as? Colony)?.stockade
        var enemy = ModelMessage(.combatResult, "combat.shipSunkByBombardment.enemy", settlement)
            .addStringTemplate("%location%", locationLabel(settlement, for: attackerPlayer))
        if let building { enemy = enemy.addNamed("%building%", building) }
        cs.addMessage(attackerPlayer, enemy
            .addStringTemplate("%enemyUnit%", ship.label)
            .addStringTemplate("%enemyNation%", ship.apparentOwnerName))
        var ours = ModelMessage(.combatResult, "combat.shipSunkByBombardment", ship.tile!)
            .addStringTemplate("%location%", locationLabel(settlement, for: shipPlayer))
            .addStringTemplate("%unit%", ship.label)
        if let building { ours = ours.addNamed("%building%", building) }
        cs.addMessage(shipPlayer, ours.addStringTemplate("%enemyNation%", attackerPlayer.nationLabel))
        try csSinkShip(ship, attackerPlayer, cs)
    }

    private func csSlaughterUnit(_ winner: Unit, _ loser: Unit, _ cs: ChangeSet) throws {
        guard let game, let winnerPlayer = winner.owner, let loserPlayer = loser.owner else { return }
        let winnerNation = winner.apparentOwnerName
        let winnerLoc: (any Location)? = winner.isInColony ? winner.colony : winner.location
        let winnerLocation = locationLabel(winnerLoc, for: winnerPlayer)
        let loserNation = loser.apparentOwnerName
        let loserLoc: (any Location)? = loser.isInColony ? loser.colony : loser.location
        let loserLocation = locationLabel(loserLoc, for: loserPlayer)
        let suffix = loser.type?.suffix ?? ""
        cs.addMessage(winnerPlayer, ModelMessage(.combatResult, "combat.unitSlaughtered.enemy." + suffix, winner)
            .addDefaultId("combat.unitSlaughtered.enemy")
            .addStringTemplate("%location%", winnerLocation)
            .addStringTemplate("%unit%", winner.label)
            .addStringTemplate("%enemyNation%", loserNation)
            .addStringTemplate("%enemyUnit%", loser.label))
        cs.addMessage(loserPlayer, ModelMessage(.combatResult, "combat.unitSlaughtered.ours." + suffix, loser.tile!)
            .addDefaultId("combat.unitSlaughtered.ours")
            .addStringTemplate("%location%", loserLocation)
            .addStringTemplate("%unit%", loser.label)
            .addStringTemplate("%enemyNation%", winnerNation)
            .addStringTemplate("%enemyUnit%", winner.label))
        if loserPlayer.isIndian && loserPlayer.checkForDeath() == .isDead {
            cs.addGlobalHistory(game, HistoryEvent(game.turn, .destroyNation, winnerPlayer)
                .addStringTemplate("%nation%", winnerPlayer.nationLabel)
                .addStringTemplate("%nativeNation%", loserPlayer.nationLabel))
        }
        // Only the loser, if it was the last in a settlement, which may
        // be gone when perhaps is worked out.
        try loser.csRemove(loserLoc?.settlement != nil ? .only(loserPlayer) : .perhaps().always(loserPlayer),
                           loserLoc, cs)
        loserPlayer.invalidateCanSeeTiles()
    }
}

extension Colony {
    /// Give the colony to another player, with its units, and its land
    /// perhaps to its neighbours (ServerColony.csChangeOwner).
    public func csChangeOwner(_ newOwner: Player, _ reassign: Bool, _ change: String?, _ cs: ChangeSet) throws {
        guard let oldOwner = owner, let tile else { return }
        let owned = ownedTiles
        var unseen = JavaTileSet(newOwner.collectNewTiles(javaVisibleTileSet))
        for t in owned { try t.cacheUnseen(except: newOwner) }
        changeOwner(newOwner)
        let units = allUnitsList
        for u in units { try oldOwner.csChangeOwner(u, newOwner, change, nil, cs) }
        cs.addRemoves(.only(oldOwner), self, units)
        for ed in exportDataValues { ed.exported = false }
        buildQueue.clear()
        updateSoL()
        _ = updateProductionBonus()
        if reassign {
            // The neighbours may claim the land, but not the center.
            oldOwner.reassignTiles(owned.filter { $0 !== tile }, avoid: self)
            for t in owned where t.owningSettlement !== self {
                if let ct = colonyTile(t) { _ = ejectUnits(ct, ct.unitList) }
            }
        }
        unseen.insert(contentsOf: owned)
        cs.add(.only(newOwner), unseen.tiles)
        cs.add(.perhaps().always(oldOwner).except(newOwner), owned)
    }
}

// MARK: Looting

/// Cargo a winning ship may take from a beaten one
/// (server/model/LootSession).
public final class LootSession: Session {
    public let capture: [Goods]
    private var available: [Goods]

    private init(_ winner: Unit, _ loser: Unit, _ capture: [Goods], in sessions: Sessions) {
        self.capture = capture
        available = capture
        super.init(key: LootSession.key(winner.id ?? "", loser.id ?? ""), in: sessions)
    }

    static func key(_ winnerId: String, _ loserId: String) -> String {
        Session.makeKey("LootSession", winnerId, loserId)
    }

    @discardableResult
    static func register(_ winner: Unit, _ loser: Unit, _ capture: [Goods], in sessions: Sessions) -> LootSession {
        let s = LootSession(winner, loser, capture, in: sessions)
        sessions.register(s)
        return s
    }

    /// Take goods from what is still to loot.
    ///
    /// - Returns: Whether they were there.
    func take(_ goods: Goods) -> Bool {
        guard let i = available.firstIndex(where: { Goods.javaEquals($0, goods) }) else { return false }
        available.remove(at: i)
        return true
    }

    var remaining: [Goods] { available }
}

/// The cargo a ship may loot (LootCargoMessage).
public final class LootCargoMessage: ServerMessage {
    public unowned let winner: Unit
    public let loserId: String
    public let goods: [Goods]

    public init(_ winner: Unit, _ loserId: String, _ goods: [Goods]) {
        self.winner = winner
        self.loserId = loserId
        self.goods = goods
    }

    public var tag: String { "lootCargo" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("winner", winner.id ?? ""), ("loser", loserId)] }
    public func writeChildren(_ xw: FreeColXMLWriter) {
        for g in goods { g.toXML(xw) }
    }
}

extension InGameController {

    func performCombat(_ command: PlayerCommand, by player: Player) throws -> ChangeSet? {
        switch command {
        case let .attack(unitId, direction):
            let unit = try ours(player, unitId, Unit.self)
            if unit.movesLeft <= 0 { throw CommandRefused("No moves left.") }
            let tile = try neighbourTile(unit, direction)
            let moveType = unit.moveType(tile)
            if !(moveType == .enterIndianSettlementWithScout || moveType == .enterForeignColonyWithScout
                 || moveType.isAttack) {
                throw CommandRefused("Illegal attack move for: \(unitId ?? "null") type: \(moveType)")
            }
            guard let defender = tile.defendingUnit(unit) else {
                throw CommandRefused("Could not find defender in tile: \(tile.id ?? "null")")
            }
            let cs = ChangeSet()
            do {
                try player.csCombat(unit, defender, nil, random, cs)
            } catch let e as Player.CombatFailed {
                throw CommandRefused(e.description)
            }
            try sendToOthers(player, cs)
            return cs

        case let .lootCargo(winnerId, loserId, goodsElements):
            guard let winner = game.getFreeColGameObject(winnerId) as? Unit else {
                throw CommandRefused("Not a unit: \(winnerId ?? "null")")
            }
            guard let session = game.sessions.lookup(LootSession.key(winner.id ?? "", loserId ?? "")) as? LootSession
            else {
                throw CommandRefused("Bogus looting!")
            }
            if !winner.hasSpaceLeft { throw CommandRefused("No space to loot to: \(winner.id ?? "null")") }
            let cs = ChangeSet()
            for element in goodsElements {
                let xr = try FreeColXMLReader(string: element.xml)
                try xr.nextTag()
                let g = try Goods(game: game, reading: xr)
                if !session.take(g) { throw CommandRefused("Invalid loot") }
                if !winner.canAdd(g) { throw CommandRefused("Loot failed") }
                _ = winner.add(g)
            }
            // Others can see the cargo space change.
            try session.complete(cs)
            cs.add(.perhaps(), winner)
            try sendToOthers(player, cs)
            return cs

        default:
            preconditionFailure("Not a combat command: \(command)")
        }
    }
}

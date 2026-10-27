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

/// A player's new turn (ServerPlayer.csNewTurn), with emigration,
/// upkeep and natural disasters.
extension Player {

    /// The player's new turn: its settlements, units and Europe, then
    /// for Europeans emigration, upkeep, disasters and the colony
    /// warnings, and the stance changes others hear of.
    ///
    /// - Throws: NotYetPorted when the intervention force would arrive.
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game, let spec = specification else { return }
        let oldImmigration = immigration, oldLiberty = liberty
        var newSoL = 0

        // Settlements.
        let settlements = self.settlements
        for settlement in settlements {
            if let colony = settlement as? Colony {
                try colony.csNewTurn(random, cs)
            } else if let native = settlement as? IndianSettlement {
                try native.csNewTurn(random, cs)
            }
            newSoL += settlement.sonsOfLiberty
        }
        if !settlements.isEmpty {
            newSoL /= settlements.count
            if oldSoL / 10 != newSoL / 10 {
                cs.addMessage(self, ModelMessage(.sonsOfLiberty, newSoL > oldSoL
                                                     ? "model.player.soLIncrease" : "model.player.soLDecrease", self)
                    .addAmount("%oldSoL%", oldSoL)
                    .addAmount("%newSoL%", newSoL))
            }
            oldSoL = newSoL // To check for changes next turn.
        }
        var newImmigration = immigration - oldImmigration
        let newLiberty = liberty - oldLiberty

        // Units.
        for unit in units { try unit.csNewTurn(random, cs) }

        // Europe.
        if let europe {
            europe.csNewTurn(random, cs)
            modifyImmigration(europe.immigration(newImmigration))
            newImmigration = immigration - oldImmigration
        }

        if isEuropean {
            // Emigrate by themselves when recruits can not be chosen.
            if !hasAbility(Ability.selectRecruit) {
                while checkEmigrate {
                    try csEmigrate(Europe.MigrationType.unspecificSlot, .normal, random, cs)
                }
            }
            if newImmigration != 0 {
                cs.addPartial(.only(self), self, ("immigration", String(immigration)))
            }
            if newLiberty != 0 {
                cs.addPartial(.only(self), self, ("liberty", String(liberty)))
            }
            if spec.getBoolean(GameOptions.enableUpkeep) == true {
                try csPayUpkeep(random, cs)
            }
            let disaster = spec.getInteger(GameOptions.naturalDisasters) ?? 0
            if disaster > 0 {
                try csNaturalDisasters(random, cs, disaster)
            }
            if isRebel && interventionBells >= (spec.getInteger(GameOptions.interventionBells) ?? Int(Int32.max)) {
                throw NotYetPorted("the intervention force arriving")
            }
            // The warnings, once everything has settled.
            for colony in colonyList { colony.csNewTurnWarnings(random, cs) }
        }

        // Tell others of stance changes.
        while !stanceDirty.isEmpty {
            let s = stanceDirty.removeFirst()
            let sta = stance(s)
            let war = sta == .war
            if sta == .uncontacted { continue }
            for p in game.liveEuropeanPlayers(excluding: self) {
                if p === s || !p.hasContacted(self) || !p.hasContacted(s) { continue }
                if p.hasAbility(Ability.betterForeignAffairsReport) || war {
                    cs.addStance(.only(p), self, sta, s)
                    cs.addMessage(p, ModelMessage(.foreignDiplomacy, sta.otherStanceChangeKey, self)
                        .addStringTemplate("%attacker%", nationLabel)
                        .addStringTemplate("%defender%", s.nationLabel))
                }
            }
        }
    }

    /// Whether a new colonist should emigrate (checkEmigrate).
    public var checkEmigrate: Bool {
        isColonial && immigrationRequired <= immigration
    }

    // MARK: Emigration

    /// A recruit leaves for the docks in Europe (csEmigrate).
    public func csEmigrate(_ slot: Int, _ type: Europe.MigrationType, _ random: JavaRandom,
                           _ cs: ChangeSet) throws {
        guard let game, let spec = specification, let europe else { return }
        let recruit = europe.extractRecruitable(slot, random)
        let role = spec.getBoolean(GameOptions.equipEuropeanRecruits) == true
            ? recruit.role(spec) : spec.defaultRole
        let unit = Unit(game: game, location: europe, owner: self, type: recruit.type(spec)!, role: role)

        switch type {
        case .fountain:
            remainingEmigrants -= 1
        case .recruit, .normal:
            if type == .recruit {
                _ = modifyGold(-europe.currentRecruitPrice)
                cs.addPartial(.only(self), self, ("gold", String(gold)))
                europe.increaseRecruitmentDifficulty()
            }
            reduceImmigration()
            updateImmigrationRequired()
            cs.addPartial(.only(self), self, ("immigration", String(immigration)),
                          ("immigrationRequired", String(immigrationRequired)))
            if !Europe.MigrationType.specificMigrantSlot(slot) {
                cs.addMessage(self, emigrationMessage(unit))
            }
        case .survival:
            cs.addMessage(self, ModelMessage(.unitAdded, "model.player.autoRecruit", self, unit)
                .add("%europe%", europe.nameKey)
                .addStringTemplate("%unit%", unit.label))
        }
        cs.add(.only(self), europe)
    }

    // MARK: Upkeep

    /// Pay for the upkeep of buildings, going bankrupt if it can not
    /// be paid and recovering when it can (csPayUpkeep).
    private func csPayUpkeep(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let spec = specification, let bankruptcy = spec.getDisaster(Disaster.bankruptcy) else { return }
        var changed = false
        let upkeep = settlements.reduce(0) { $0 + $1.upkeep }
        if checkGold(upkeep) {
            _ = modifyGold(-upkeep)
            if bankrupt {
                bankrupt = false
                changed = true
                // The modifiers are the only effects that can be undone.
                for choice in bankruptcy.effects {
                    for m in choice.object.allModifiers { cs.addModifier(self, self, m, false) }
                }
                cs.addMessage(self, ModelMessage(.governmentEfficiency, "model.player.disaster.bankruptcy.stop", self))
            }
        } else {
            _ = modifyGold(-gold)
            if !bankrupt {
                bankrupt = true
                changed = true
                _ = try csApplyDisaster(random, nil, bankruptcy, cs)
                cs.addMessage(self, ModelMessage(.governmentEfficiency, "model.player.disaster.bankruptcy.start", self))
            }
        }
        if upkeep > 0 { cs.addPartial(.only(self), self, ("gold", String(gold))) }
        if changed { cs.addPartial(.only(self), self, ("bankrupt", String(bankrupt))) }
    }

    // MARK: Disasters

    /// Perhaps strike a colony with a natural disaster: from a colony
    /// chosen at random, the first one a disaster affects
    /// (csNaturalDisasters).
    private func csNaturalDisasters(_ random: JavaRandom, _ cs: ChangeSet, _ probability: Int) throws {
        guard Int(RandomUtils.randomInt("Natural disaster", random, 100)) < probability else { return }
        let colonies = colonyList
        let size = colonies.count
        if size <= 0 { return }
        let start = Int(RandomUtils.randomInt("select colony", random, Int32(size)))
        for i in 0..<size {
            let colony = colonies[(start + i) % size]
            guard let disaster = RandomChoice.weightedRandom("select disaster", colony.disasterChoices, random)
            else { continue }
            let messages = try csApplyDisaster(random, colony, disaster, cs)
            if !messages.isEmpty {
                cs.addMessage(self, ModelMessage(.disasters, "model.player.disaster.strikes", colony)
                    .addName("%colony%", colony.name)
                    .addName("%disaster%", disaster))
                for message in messages { cs.addMessage(self, message) }
                return
            }
        }
    }

    /// Apply a disaster's effects to a colony, or to the player if
    /// there is none (csApplyDisaster).
    ///
    /// - Returns: The messages saying what happened; none if the
    ///   disaster had no effect.
    @discardableResult
    public func csApplyDisaster(_ random: JavaRandom, _ colony: Colony?, _ disaster: Disaster,
                                _ cs: ChangeSet) throws -> [ModelMessage] {
        guard let game else { return [] }
        var effects: [Effect] = []
        switch disaster.numberOfEffects {
        case .one:
            if let effect = RandomChoice.weightedRandom("Get effect of disaster", disaster.effects, random) {
                effects.append(effect)
            }
        case .several:
            for choice in disaster.effects
            where Int(RandomUtils.randomInt("Get effects of disaster", random, 100)) < choice.probability {
                effects.append(choice.object)
            }
        case .all:
            effects = disaster.effects.map(\.object)
        }

        var colonyDirty = false
        var messages: [ModelMessage] = []
        outer: for effect in effects {
            var mm: ModelMessage?
            guard let colony else {
                for modifier in effect.allModifiers {
                    if modifier.duration > 0 {
                        let timed = Modifier.makeTimedModifier(modifier.id ?? "", template: modifier, start: game.turn)
                        // As in Java, the index goes on the template.
                        modifier.modifierIndex = Modifier.disasterProductionIndex
                        cs.addModifier(self, self, timed, true)
                    } else {
                        cs.addModifier(self, self, modifier, true)
                    }
                }
                continue
            }
            switch effect.id {
            case Effect.lossOfMoney:
                let range = colony.plunderRange(nil)
                let plunder = max(1, (range?.amount("Plunder \(colony.name ?? "null")", random, continuous: false) ?? 0) / 5)
                _ = modifyGold(-plunder)
                cs.addPartial(.only(self), self, ("gold", String(gold)))
                mm = ModelMessage(.disasters, effect.id, self).addAmount("%amount%", plunder)
            case Effect.lossOfBuilding:
                if let building = RandomUtils.randomMember("Select building for effect", colony.burnableBuildings, random) {
                    // The message before the damage.
                    mm = ModelMessage(.disasters, effect.id, colony).addNamed("%building%", building.type!)
                    try csDamageBuilding(building, cs)
                    colonyDirty = true
                }
            case Effect.lossOfGoods:
                if let goods = RandomUtils.randomMember("select goods", colony.lootableGoodsList, random) {
                    goods.amount = min(goods.amount / 2, 50)
                    _ = colony.removeGoods(goods)
                    mm = ModelMessage(.disasters, effect.id, colony)
                        .addStringTemplate("%goods%", goods.label(sellable: true))
                    colonyDirty = true
                }
            case Effect.lossOfUnit:
                if let unit = unitForEffect(colony, effect, random) {
                    if colony.unitCount == 1 {
                        messages = [ModelMessage(.disasters, "model.player.disaster.effect.colonyDestroyed", self)
                            .addName("%colony%", colony.name)]
                        try csDisposeSettlement(colony, cs)
                        colonyDirty = false
                        break outer // No point going on.
                    }
                    mm = ModelMessage(.disasters, effect.id, colony).addStringTemplate("%unit%", unit.label)
                    try unit.csRemove(.only(self), nil, cs)
                    colonyDirty = true
                }
            case Effect.damagedUnit:
                if let unit = unitForEffect(colony, effect, random), unit.isNaval {
                    mm = ModelMessage(.disasters, effect.id, colony).addStringTemplate("%unit%", unit.label)
                    if let repair = unit.repairLocation {
                        csDamageShip(unit, repair, cs)
                    } else {
                        try csSinkShip(unit, nil, cs)
                    }
                    colonyDirty = true
                }
            default:
                mm = ModelMessage(.disasters, effect.id, colony)
                for m in effect.allModifiers {
                    if m.duration > 0 {
                        let timed = Modifier.makeTimedModifier(m.id ?? "", template: m, start: game.turn)
                        timed.modifierIndex = Modifier.disasterProductionIndex
                        cs.addModifier(self, colony, timed, true)
                    } else {
                        cs.addModifier(self, colony, m, true)
                    }
                }
                if !effect.allModifiers.isEmpty { colonyDirty = true }
            }
            if let mm { messages.append(mm) }
        }
        if colonyDirty { cs.add(.perhaps(), colony) }
        return messages
    }

    /// A unit of the colony a disaster's effect applies to, at random.
    private func unitForEffect(_ colony: Colony, _ effect: Effect, _ random: JavaRandom) -> Unit? {
        let units = colony.allUnitsList.filter { effect.appliesTo($0.type) }
        return RandomUtils.randomMember("Select unit for effect", units, random)
    }

    /// Destroy or downgrade a building (csDamageBuilding).
    func csDamageBuilding(_ building: Building, _ cs: ChangeSet) throws {
        guard let colony = building.colony, let tile = colony.tile, let type = building.type else { return }
        let copied = try tile.tileToCache()
        var changed: Bool
        if type.upgradesFrom == nil {
            changed = colony.ejectUnits(building, building.unitList)
            try colony.destroyBuilding(building)
            changed = changed || type.isDefenceType
            cs.addRemove(.only(colony.owner), colony, building)
            building.dispose()
            // Losing a building can stop other work, such as fishing
            // without docks.
            for wl in colony.allWorkLocations where !wl.isEmpty && !wl.canBeWorked {
                changed = colony.ejectUnits(wl, wl.unitList) || changed
            }
        } else if building.canBeDamaged {
            changed = colony.ejectUnits(building, building.downgrade() ?? [])
            changed = changed || (building.type?.isDefenceType ?? false)
        } else {
            return
        }
        if changed { try tile.cacheUnseen(copied: copied) }
        colony.requestRearrange()
    }

    /// Sink a ship (csSinkShip).
    func csSinkShip(_ ship: Unit, _ attacker: Player?, _ cs: ChangeSet) throws {
        guard let shipPlayer = ship.owner else { return }
        try ship.csRemove(.perhaps().always(shipPlayer), ship.location, cs)
        shipPlayer.invalidateCanSeeTiles()
        if let attacker { cs.addAttribute(.only(attacker), "sound", "sound.event.shipSunk") }
    }

    /// Damage a ship, losing what it carries, and send it for repair
    /// (csDamageShip).
    func csDamageShip(_ ship: Unit, _ repair: any Location, _ cs: ChangeSet) {
        guard let owner = ship.owner else { return }
        for g in ship.compactGoodsList { _ = ship.remove(g) }
        for u in ship.unitList {
            _ = ship.remove(u)
            try? u.csRemove(.only(owner), nil, cs)
        }
        let shipLoc: any Location = repair is Colony ? repair.tile! : repair
        ship.damageShip(shipLoc)
        cs.add(.only(owner), shipLoc as? FreeColGameObject)
        owner.invalidateCanSeeTiles()
    }
}

extension Colony {
    /// Remove a building, updating the players' views if it changes the
    /// colony's defences (ServerColony.destroyBuilding).
    @discardableResult
    public func destroyBuilding(_ building: Building) throws -> Bool {
        let copied = (building.type?.isDefenceType ?? false) ? try tile?.tileToCache() : nil
        if !removeBuilding(building) { return false }
        try tile?.cacheUnseen(copied: copied)
        invalidateCache()
        checkBuildQueueIntegrity()
        return true
    }
}

extension Settlement {
    /// What a settlement could lose, for no attacker in particular (a
    /// colony's is the same for every attacker).
    func plunderRange(_ attacker: Unit?) -> RandomRange? {
        if let attacker { return plunderRange(attacker) }
        return (self as? Colony)?.colonyPlunderRange
    }
}

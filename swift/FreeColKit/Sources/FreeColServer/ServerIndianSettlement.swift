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

/// A native settlement's new turn (server/model/ServerIndianSettlement).
extension IndianSettlement {

    /// Horses bred in a turn, at most.
    static let maxHorsesPerTurn = 2

    /// Use up goods, as many as there are.
    private func consumeGoods(_ type: GoodsType?, _ amount: Int) {
        guard let type, goodsCount(type) > 0 else { return }
        _ = removeGoods(type, min(amount, goodsCount(type)))
    }

    /// The settlement's new turn: production and consumption, a new
    /// resident if there is food (and rum) to spare, horses bred, and
    /// what the settlement wants.  As in Java, natives do not starve
    /// (BR#3354).
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let spec = specification, let game, let owner, let tile else { return }

        // Produce, then consume.
        let goodsList = spec.goodsTypeList
        for g in goodsList { _ = addGoods(g.storedAs, totalProduction(of: g)) }
        for g in goodsList { consumeGoods(g, consumption(of: g)) }

        if unitCount <= 0 {
            if tile.isEmpty {
                try owner.csDisposeSettlement(self, cs)
                return
            }
            _ = tile.firstUnit?.setLocation(self)
        }

        // A new resident; alcohol helps too.
        let foodType = spec.primaryFoodType
        let rumType = spec.getGoodsType("model.goods.rum")
        let unitTypes = spec.types(UnitType.self, withAnyAbility: [Ability.bornInIndianSettlement])
        if !unitTypes.isEmpty
            && goodsCount(foodType) + 4 * goodsCount(rumType)
                > Settlement.foodPerColonist + IndianSettlement.keepRawMaterial {
            // One more brave than were first made is plenty; discuss
            // any increase on the developers' list first.
            if ownedUnitList.count <= (type?.maximumSize ?? 0),
               let type = RandomUtils.randomMember("Choose birth", unitTypes, random) {
                let unit = Unit(game: game, location: tile, owner: owner, type: type)
                consumeGoods(rumType, Settlement.foodPerColonist / 4)
                // New units soon leave and go annoying.
                addOwnedUnit(unit)
                _ = unit.changeHomeIndianSettlement(self)
            }
            // The food goes anyway.
            consumeGoods(foodType, Settlement.foodPerColonist)
        }

        // Breed horses.
        if let horses = spec.getGoodsType("model.goods.horses"),
           let grain = spec.getGoodsType("model.goods.grain") {
            let foodProdAvail = totalProduction(of: grain) - foodConsumption
            if foodProdAvail > 0 && goodsCount(horses) >= horses.breedingNumber {
                _ = addGoods(horses, min(IndianSettlement.maxHorsesPerTurn, foodProdAvail))
            }
        }

        goodsContainer?.removeAbove(warehouseCapacity)
        updateWantedGoods()
        cs.add(.only(owner), self)
    }
}

/// A native settlement's alarm, missionary and conversions
/// (server/model/ServerIndianSettlement).
extension IndianSettlement {

    static let alarmNewMissionary = -100
    static let maxConvertDistance = 10

    /// The start of the owner's turn: the missionary may convert a
    /// resident, who goes to the missionary owner's nearest colony on
    /// the same land (csStartTurn).
    public func csStartTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let missionary, let other = missionary.owner, let tile, let game,
              let missionaryType = missionary.type else { return }
        let turn = game.turn
        var convert = Float(convertProgress)
        let cMiss = missionary.apply(Float(missionaryType.skill), turn: turn, Modifier.conversionSkill)
        // The rate rises by a percentage of the alarm.
        let alarm = min(self.alarm(other)?.value ?? 0, Tension.tensionMax)
        let cAlarm = missionary.apply(Float(alarm), turn: turn, Modifier.conversionAlarmRate)
        convert += cMiss + (cAlarm - Float(alarm))
        let colony = tile.nearestSettlement(other, IndianSettlement.maxConvertDistance, same: true) as? Colony
        if convert < Float(type?.convertThreshold ?? 0) || unitCount + tile.unitCount <= 2 || colony == nil {
            convertProgress = Int(JavaMath.toInt(convert.rounded(.down)))
        } else {
            convertProgress = 0
            if let brave = RandomUtils.randomMember("Convert", allUnitsList, random) {
                try colony!.csAddConvert(brave, cs)
            }
        }
    }

    /// Change the alarm towards a player, starting it if there is none.
    ///
    /// - Returns: Whether its level, or the most hated player, changed.
    private func changeAlarm(_ player: Player, _ amount: Int) -> Bool {
        if alarm(player) == nil { initializeAlarm(player) }
        var a = alarm(player)!
        let oldLevel = a.level
        a.modify(amount)
        setAlarm(player, a)
        let change = updateMostHated()
        return change || oldLevel != a.level
    }

    /// Change the alarm, and the owner's tension too if propagating
    /// (the capital's in full, others' by half) (csChangeAlarm).
    @discardableResult
    private func csChangeAlarm(_ player: Player, _ add: Int, _ propagate: Bool, _ cs: ChangeSet) throws -> Bool {
        let change = changeAlarm(player, add)
        if propagate { try owner?.csModifyTension(player, isCapital ? add : add / 2, self, cs) }
        return change
    }

    /// Change the alarm towards a player, updating the settlement for
    /// those who see it if that shows (csModifyAlarm).
    @discardableResult
    public func csModifyAlarm(_ player: Player, _ add: Int, _ propagate: Bool, _ cs: ChangeSet) throws -> Bool {
        let copied = try tile?.tileToCache()
        let change = try csChangeAlarm(player, add, propagate, cs)
        if change {
            try tile?.cacheUnseen(copied: copied)
            cs.add(.perhaps(), self)
        }
        return change
    }

    /// Tell a player the alarm towards it has changed, with a message
    /// if it rose to a level that has one (csCheckTension).
    public func csCheckTension(_ enemy: Player, _ oldLevel: Tension.Level?, _ cs: ChangeSet) throws {
        let newLevel = alarm(enemy)?.level
        guard let oldLevel, oldLevel != newLevel, hasContacted(enemy), let tile, enemy.hasExplored(tile)
        else { return }
        cs.add(ChangeSet.See.only(nil).perhapsOnly(enemy), self)
        guard let newLevel, oldLevel.limit <= newLevel.limit, let a = alarm(enemy) else { return }
        let key = "model.player.alarmIncrease." + a.key
        if !Messages.containsKey(key) { return }
        cs.addMessage(enemy, ModelMessage(.foreignDiplomacy, key, self)
            .addStringTemplate("%nation%", owner?.nationLabel)
            .addStringTemplate("%enemy%", enemy.nationLabel)
            .addName("%settlement%", name))
    }

    /// Change the missionary, removing the old one, and bringing the new
    /// one's owner to see the settlement (csChangeMissionary).
    public func csChangeMissionary(_ newMissionary: Unit?, _ cs: ChangeSet) throws {
        let old = missionary
        if newMissionary === old { return }
        guard let tile else { return }
        let newOwner = newMissionary?.owner
        try tile.cacheUnseen(except: newOwner)

        if let old, let oldOwner = old.owner {
            missionary = nil
            tile.updateIndianSettlement(oldOwner)
            try old.csRemove(.only(oldOwner), nil, cs)
            cs.add(.only(oldOwner), tile)
            oldOwner.invalidateCanSeeTiles()
        }

        if let newMissionary, let newOwner {
            missionary = newMissionary
            // Off the map, with a place at the settlement that skips
            // the usual checks.
            _ = newMissionary.setLocation(nil)
            newMissionary.setLocationNoUpdate(self)
            newMissionary.movesLeft = 0
            cs.add(.only(newOwner), newMissionary)
            convertProgress = 0
            try csChangeAlarm(newOwner, IndianSettlement.alarmNewMissionary, true, cs)
            tile.updateIndianSettlement(newOwner)
            cs.add(.only(newOwner), newOwner.collectNewTiles(missionaryVisibleTiles))
            cs.add(.perhaps().always(newOwner), tile)
            newOwner.invalidateCanSeeTiles()
        }
    }

    /// Remove the missionary, telling its owner that the mission was
    /// destroyed (true) or denounced (false), or nothing (nil)
    /// (csKillMissionary).
    public func csKillMissionary(_ destroy: Bool?, _ cs: ChangeSet) throws {
        guard let missionary else { return }
        try csChangeMissionary(nil, cs)
        guard let destroy, let missionaryOwner = missionary.owner else { return }
        cs.addMessage(missionaryOwner, ModelMessage(destroy ? .unitLost : .foreignDiplomacy,
                                                    destroy ? "model.indianSettlement.mission.destroyed"
                                                        : "model.indianSettlement.mission.denounced", self)
            .addStringTemplate("%settlement%", locationLabel(self, for: missionaryOwner)))
    }
}

extension Tile {
    /// The nearest settlement of a player (or anyone's), within a
    /// radius (none for unlimited), and on the same land or water if
    /// asked (getNearestSettlement).
    public func nearestSettlement(_ owner: Player?, _ radius: Int, same: Bool) -> Settlement? {
        guard let map else { return nil }
        let radius = radius <= 0 ? Constants.infinity : radius
        for t in map.circleTiles(self, filled: true, radius: radius) {
            if t === self || (same && !isConnected(to: t)) { continue }
            if let settlement = t.settlement, owner == nil || owner!.owns(settlement) { return settlement }
        }
        return nil
    }
}

extension IndianSettlement {
    /// Equip a unit from the settlement's goods (csEquipForRole).
    public func csEquipForRole(_ unit: Unit, _ role: Role, _ roleCount: Int, _ random: JavaRandom,
                               _ cs: ChangeSet) -> Bool {
        let ret = equipForRole(unit, role, roleCount)
        if ret { cs.add(.only(owner), tile) }
        return ret
    }
}

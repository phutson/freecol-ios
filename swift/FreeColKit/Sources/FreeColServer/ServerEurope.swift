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

/// Europe's new turn and recruits (server/model/ServerEurope).
extension Europe {

    /// Europe's new turn: repairing the ships at the docks.
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) {
        for unit in unitList where unit.isNaval && unit.isDamaged { unit.csRepairUnit(cs) }
    }

    /// The unit types that may be recruited, with their weights
    /// (generateRecruitablesList).
    func recruitablesList() -> [RandomChoice<UnitType>] {
        guard let owner, let spec = specification else { return [] }
        return spec.unitTypeList
            .filter { $0.isRecruitable && owner.hasAbility(Ability.canRecruitUnit, for: $0) && $0.isAvailableTo([owner]) }
            .map { RandomChoice($0, $0.recruitProbability) }
    }

    /// Fill the recruits up to three, at random (fillRecruitables).
    func fillRecruitables(_ random: JavaRandom) {
        let recruits = recruitablesList()
        while let unitType = RandomChoice.weightedRandom("Recruits", recruits, random),
              addRecruitable(unitType, force: false) {}
    }

    /// Recruiting costs more each time (increaseRecruitmentDifficulty).
    public func increaseRecruitmentDifficulty() {
        guard let spec = specification else { return }
        baseRecruitPrice += spec.getInteger(GameOptions.recruitPriceIncrease) ?? 0
        recruitLowerCap += spec.getInteger(GameOptions.lowerCapIncrease) ?? 0
    }

    /// Take a recruit, from a slot or at random, and refill
    /// (extractRecruitable).
    public func extractRecruitable(_ slot: Int, _ random: JavaRandom) -> AbstractUnit {
        let index = Europe.MigrationType.specificMigrantSlot(slot)
            ? Europe.MigrationType.migrantSlotToIndex(slot)
            : Int(RandomUtils.randomInt("Choose emigrant", random, Int32(Europe.MigrationType.migrantCount)))
        var expanded = expandedRecruitables(full: true)
        let result = expanded.remove(at: index)
        var top = expanded.removeFirst()
        var recruits = [top]
        for au in expanded {
            if au.id == top.id && au.roleId == top.roleId {
                top.addToNumber(au.number)
            } else {
                recruits.append(au)
                top = au
            }
        }
        setRecruitables(recruits)
        fillRecruitables(random)
        return result
    }
}

/// Equipping and training in Europe (server/model/ServerEurope).
extension Europe {

    /// Training a unit makes the next cost more, by type if the rules
    /// say (increasePrice).
    public func increasePrice(_ unitType: UnitType, _ price: Int) {
        guard let spec = specification else { return }
        let option = spec.getBoolean(GameOptions.priceIncreasePerType)
            ? "model.option.priceIncrease." + (unitType.suffix ?? "") : GameOptions.priceIncrease
        let increase = spec.hasOption(option, IntegerOption.self) ? (spec.getInteger(option) ?? 0) : 0
        if increase != 0 { setUnitPrice(unitType, price + increase) }
    }

    /// Equip a unit for a role, selling what it no longer needs and
    /// buying what it does (the server's Europe.equipForRole).
    ///
    /// - Returns: Whether it was equipped.
    func serverEquipForRole(_ unit: Unit, _ role: Role, _ roleCount: Int) -> Bool {
        guard unit.roleIsAvailable(role), let owner else { return false }
        let req = unit.goodsDifference(role, roleCount)
        // The price, and whether the goods can be traded at all.
        guard let price = try? priceGoods(req) else { return false }
        if price > 0 && !owner.checkGold(price) { return false }
        for ag in req where ag.amount < 0 {
            guard let type = ag.type else { continue }
            let rm = owner.sellInEurope(nil, nil, type, -ag.amount)
            if rm > 0 { owner.extraTrades.append(AbstractGoods(type, rm)) }
        }
        for ag in req where ag.amount > 0 {
            guard let type = ag.type else { continue }
            let m = owner.buyInEurope(nil, nil, type, ag.amount)
            if m > 0 { owner.extraTrades.append(AbstractGoods(type, -m)) }
        }
        unit.changeRole(role, roleCount)
        return true
    }

    /// Equip a unit here, telling the owner (csEquipForRole).
    public func csEquipForRole(_ unit: Unit, _ role: Role, _ roleCount: Int, _ random: JavaRandom,
                               _ cs: ChangeSet) -> Bool {
        let ret = serverEquipForRole(unit, role, roleCount)
        if ret, let owner {
            cs.addPartial(.only(owner), owner, ("gold", String(owner.gold)))
            cs.add(.only(owner), unit)
            owner.flushExtraTrades(random)
            owner.csFlushMarket(cs)
        }
        return ret
    }
}

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

/// Something the engine does not do yet: a part of Java's server still
/// to be ported.
public struct NotYetPorted: Error, CustomStringConvertible {
    public let what: String

    public init(_ what: String) {
        self.what = what
    }

    public var description: String {
        "Not yet ported: \(what)"
    }
}

/// A colony's new turn (server/model/ServerColony).
///
/// Java's server makes ServerColony objects; here the server's
/// behaviour is added to the model's colony.  Java's log builder is not
/// kept.
extension Colony {

    /// Whether a goods type is needed for something the colony could
    /// build.
    private func neededForBuildableType(_ goodsType: GoodsType) -> Bool {
        guard let spec = specification else { return false }
        let buildables: [BuildableType] = spec.buildingTypeList
            + spec.unitTypeList.filter { !$0.hasAbility(Ability.person) }
        return buildables.contains { bt in
            canBuild(bt) && bt.requiredGoods.contains { $0.type === goodsType }
        }
    }

    /// Build the unit a queue is building.
    private func csBuildUnit<T>(_ queue: BuildQueue<T>, _ random: JavaRandom, _ cs: ChangeSet) throws -> Unit {
        guard let game, let owner, let type = queue.currentlyBuilding as? UnitType else {
            preconditionFailure("Not building a unit: \(self)")
        }
        let unit = Unit(game: game, location: tile, owner: owner, type: type)
        unit.name = owner.nameForUnit(type, random)
        if unit.hasAbility(Ability.bornInColony) {
            cs.addMessage(owner, ModelMessage(.unitAdded, "model.colony.newColonist", self, unit)
                .addName("%colony%", name))
        } else {
            unit.name = owner.nameForUnit(type, random)
            cs.addMessage(owner, ModelMessage(.unitAdded, "model.colony.unitReady", self, unit)
                .addName("%colony%", name)
                .addStringTemplate("%unit%", unit.label))
        }
        return unit
    }

    /// Put units in other work locations, or on the colony's tile if
    /// there is no room (ejectUnits).
    ///
    /// - Returns: Whether there were units to move.
    @discardableResult
    public func ejectUnits(_ workLocation: WorkLocation?, _ units: [Unit]) -> Bool {
        if units.isEmpty { return false }
        unit: for u in units {
            for wl in availableWorkLocations where wl !== workLocation && wl.canAdd(u) {
                _ = u.setLocation(wl)
                continue unit
            }
            _ = u.setLocation(tile)
        }
        requestRearrange()
        return true
    }

    /// Build the building a queue is building, or upgrade one.
    private func csBuildBuilding<T>(_ queue: BuildQueue<T>, _ cs: ChangeSet) throws -> Bool {
        guard let game, let owner, let tile, let type = queue.currentlyBuilding as? BuildingType else {
            preconditionFailure("Not building a building: \(self)")
        }
        let copied = try tile.tileToCache()
        let success: Bool
        if let from = type.upgradesFrom {
            let building = self.building(from)
            let eject = building?.upgrade()
            success = eject != nil
            if let eject {
                ejectUnits(building, eject)
                if !eject.isEmpty { try tile.cacheUnseen(copied: copied) }
            } else {
                cs.addMessage(owner, unbuildableMessage(type))
            }
        } else {
            success = try buildBuilding(Building(game: game, colony: self, type: type))
        }
        if success {
            cs.addMessage(owner, ModelMessage(.buildingCompleted, "model.colony.buildingReady", self)
                .addName("%colony%", name)
                .addNamed("%building%", type))
            requestRearrange()
        }
        return success
    }

    /// The warning that something can not be built here
    /// (getUnbuildableMessage).
    public func unbuildableMessage(_ buildable: BuildableType) -> ModelMessage {
        ModelMessage(.warning, "model.colony.unbuildable", self, buildable)
            .addName("%colony%", name)
            .addNamed("%object%", buildable)
    }

    /// Drop what can not be built from the front of a queue, warning the
    /// owner.
    ///
    /// - Returns: What can now be built, or nil.
    @discardableResult
    private func csNextBuildable<T>(_ queue: BuildQueue<T>, _ cs: ChangeSet) -> BuildableType? {
        guard let spec = specification, let owner else { return nil }
        var invalidate = false
        while let buildable = queue.currentlyBuilding {
            switch noBuildReason(buildable, nil) {
            case .limitExceeded:
                // Expected when the last wagon available is built.
                break
            case .none:
                return buildable
            case .notBuilding:
                if spec.goodsTypeList.contains(where: {
                    $0.isBuildingMaterial && !$0.isStorable && totalProduction(of: $0) > 0
                }) {
                    cs.addMessage(owner, ModelMessage(.warning, "model.colony.cannotBuild", self)
                        .addName("%colony%", name))
                }
                return nil
            case .populationTooSmall:
                cs.addMessage(owner, ModelMessage(.warning, "model.colony.buildNeedPop", self)
                    .addName("%colony%", name)
                    .addNamed("%building%", buildable))
            default:
                cs.addMessage(owner, unbuildableMessage(buildable))
            }
            queue.remove(at: 0)
            invalidate = true
        }
        if invalidate { invalidateCache() }
        return nil
    }

    /// Add a building, updating the players' views if it changes the
    /// colony's defences.
    @discardableResult
    func buildBuilding(_ building: Building) throws -> Bool {
        let copied = (building.type?.isDefenceType ?? false) ? try tile?.tileToCache() : nil
        if !addBuilding(building) { return false }
        try tile?.cacheUnseen(copied: copied)
        invalidateCache()
        return true
    }

    /// Drop what can no longer be built from the queues
    /// (checkBuildQueueIntegrity with fixing).  As in Java, the item
    /// after one dropped is not checked.
    public func checkBuildQueueIntegrity() {
        var assumeBuilt: [BuildableType] = []
        var i = 0
        while i < buildQueue.count {
            let bt = buildQueue.values[i]
            if noBuildReason(bt, assumeBuilt) == .none {
                assumeBuilt.append(bt)
            } else {
                buildQueue.remove(at: i)
            }
            i += 1
        }
        assumeBuilt = []
        i = 0
        while i < populationQueue.count {
            let ut = populationQueue.values[i]
            if noBuildReason(ut, assumeBuilt) == .none {
                assumeBuilt.append(ut)
            } else {
                populationQueue.remove(at: i)
            }
            i += 1
        }
    }

    // MARK: Warnings

    /// The warnings that wait until everything else in the turn is done
    /// (csNewTurnWarnings): missing inputs, what can not be finished,
    /// warehouse levels (throwing away what does not fit) and an empty
    /// build queue.
    public func csNewTurnWarnings(_ random: JavaRandom, _ cs: ChangeSet) {
        guard let spec = specification, let owner, let container = goodsContainer else { return }

        for case let building as Building in currentWorkLocations {
            if let info = productionInfo(of: building) { building.csCheckMissingInput(info, cs) }
        }

        func warnUnfinishable<T>(_ queue: BuildQueue<T>) {
            guard let info = productionInfo(of: queue), info.consumption.isEmpty,
                  let build = queue.currentlyBuilding else { return }
            let needed = AbstractGoods(nil, 0)
            let complete = turnsToComplete(build, needed: needed)
            // Warn if about to fail, or no useful progress is possible.
            if complete == -2 || complete == -1 {
                let message = ModelMessage(.missingGoods, "model.colony.buildableNeedsGoods", self, build)
                    .addName("%colony%", name)
                    .addNamed("%buildable%", build)
                    .addAmount("%amount%", needed.amount)
                if let type = needed.type { _ = message.addNamed("%goodsType%", type) }
                cs.addMessage(owner, message)
            }
        }
        warnUnfinishable(buildQueue)
        warnUnfinishable(populationQueue)

        // Throw away goods there is no room for, and warn about levels
        // that will be exceeded next turn.
        let limit = warehouseCapacity
        let adjustment = limit / GoodsContainer.cargoSize
        for goods in compactGoodsList where goods.type?.isStorable ?? false {
            guard let type = goods.type else { continue }
            let data = exportData(type)
            let low = data.lowLevel * adjustment
            let high = data.highLevel * adjustment
            let amount = goods.amount
            let oldAmount = container.oldGoodsCount(type)

            if amount < low && oldAmount >= low && type !== spec.primaryFoodType {
                cs.addMessage(owner, ModelMessage(.warehouseCapacity, "model.colony.warehouseEmpty", self, type)
                    .addNamed("%goods%", type)
                    .addAmount("%level%", low)
                    .addName("%colony%", name))
                continue
            }
            if type.limitIgnored { continue }
            var messageId: String?
            var waste = 0
            if amount > limit {
                waste = amount - limit
                _ = container.removeGoods(type, waste)
                messageId = "model.colony.warehouseWaste"
            } else if amount == limit && oldAmount < limit {
                messageId = "model.colony.warehouseOverfull"
            } else if amount > high && oldAmount <= high {
                messageId = "model.colony.warehouseFull"
            }
            if let messageId {
                cs.addMessage(owner, ModelMessage(.warehouseCapacity, messageId, self, type)
                    .addNamed("%goods%", type)
                    .addAmount("%waste%", waste)
                    .addAmount("%level%", high)
                    .addName("%colony%", name))
            }

            // No problem this turn, but what about the next?
            if !(data.exported && hasAbility(Ability.export) && owner.canTrade(type, .customHouse))
                && amount <= limit {
                let loss = amount + netProduction(of: type) - limit
                if loss > 0 {
                    cs.addMessage(owner, ModelMessage(.warehouseCapacity, "model.colony.warehouseSoonFull",
                                                      self, type)
                        .addNamed("%goods%", goods)
                        .addName("%colony%", name)
                        .addAmount("%amount%", loss))
                }
            }
        }

        // Producing building materials with nothing to build probably
        // means the build queue was forgotten.
        if (buildQueue.isEmpty || populationQueue.isEmpty)
            && spec.goodsTypeList.contains(where: { g in
                g.isBuildingMaterial && !g.isRawMaterial && !g.isBreedable
                    && adjustedNetProduction(of: g) > 0 && neededForBuildableType(g)
            }) {
            cs.addMessage(owner, ModelMessage(.buildingCompleted, "model.colony.notBuildingAnything", self)
                .addName("%colony%", name))
        }
    }

    // MARK: The new turn

    /// The colony's new turn (csNewTurn): experience, building, the
    /// turn's production with starvation, exports through a custom
    /// house, free buildings, rebels, teaching and repairs.
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let spec = specification, let owner, let tile, let container = goodsContainer else { return }

        // The AI is prone to removing all units from a colony; clean up
        // the nonsensical empty colony.
        if unitCount <= 0 {
            try owner.csDisposeSettlement(self, cs)
            return
        }

        var tileDirty = false
        var newUnitBorn = false
        container.saveState()
        invalidateCache()

        // Learning by experience.
        for wl in currentWorkLocations {
            if let building = wl as? Building {
                building.csNewTurn(random, cs)
            } else if let colonyTile = wl as? ColonyTile {
                try colonyTile.csNewTurn(random, cs)
            }
            guard let info = productionInfo(of: wl) else { continue }
            if wl.isEmpty { continue }
            for goods in info.production {
                guard let type = goods.type else { continue }
                let expert = spec.expert(producing: type)
                let experience = goods.amount / wl.unitCount
                for unit in wl.unitList where unit.unitChange(UnitChangeType.experience, expert) != nil {
                    unit.changeExperienceType(type)
                    unit.experience += experience
                    cs.addPartial(.only(owner), unit, ("experience", String(unit.experience)))
                }
            }
        }

        // Production is applied from the map as it was before anything
        // is built, as a new building can change it (BR#3261).
        let productionMap = self.productionMap

        // Build, remembering the queues that built something, which are
        // advanced after the production.
        var builtBuildings = false, builtPopulation = false
        func build<T>(_ queue: BuildQueue<T>) throws -> Bool {
            guard let info = productionInfo(of: queue), !info.consumption.isEmpty else { return false }
            guard let buildable = csNextBuildable(queue, cs) else { return false }
            if buildable is UnitType {
                let unit = try csBuildUnit(queue, random, cs)
                if unit.hasAbility(Ability.bornInColony) { newUnitBorn = true }
                return true
            }
            if let buildingType = buildable as? BuildingType {
                let count = unitCount
                if try csBuildBuilding(queue, cs) {
                    // A visible change if the stockade changed or units
                    // were ejected.
                    tileDirty = buildingType.isDefenceType || count != unitCount
                    return true
                }
                return false
            }
            preconditionFailure("Bogus buildable: \(buildable)")
        }
        builtBuildings = try build(buildQueue)
        builtPopulation = try build(populationQueue)

        // Apply the production.
        for goodsType in productionMap.types {
            let net = productionMap.count(goodsType)
            let stored = goodsCount(goodsType)
            if net + stored <= 0 {
                _ = removeGoods(goodsType, stored)
            } else {
                _ = addGoods(goodsType, net)
            }

            // Starvation, at once.
            guard goodsType === spec.primaryFoodType else { continue }
            if net + stored < 0 {
                if unitCount > 1 {
                    let victim = RandomUtils.randomMember("Starver", unitList, random)!
                    try victim.csRemove(.only(owner), nil, cs)
                    cs.addMessage(owner, ModelMessage(.unitLost, "model.colony.colonistStarved", self)
                        .addName("%colony%", name))
                } else {
                    cs.addMessage(owner, ModelMessage(.unitLost, "model.colony.colonyStarved", self)
                        .addName("%colony%", name))
                    try owner.csDisposeSettlement(self, cs)
                    return
                }
            } else if net < 0 {
                let turns = stored / -net
                if turns <= Colony.famineTurns && !newUnitBorn {
                    cs.addMessage(owner, ModelMessage(.warning, "model.colony.famineFeared", self)
                        .addName("%colony%", name)
                        .addAmount("%number%", turns))
                }
            }
        }
        invalidateCache()

        // Now the goods are in, take what was built off its queue.
        func advance<T>(_ queue: BuildQueue<T>) {
            switch queue.completionAction {
            case .shuffle:
                if queue.count > 1 {
                    var values = queue.values
                    RandomUtils.randomShuffle("Build queue", &values, random)
                    queue.setValues(values)
                }
            case .removeExceptLast where queue.count == 1 && queue.currentlyBuilding is UnitType:
                // Repeat the last unit.
                break
            default:
                queue.remove(at: 0)
            }
            csNextBuildable(queue, cs)
        }
        if builtBuildings { advance(buildQueue) }
        if builtPopulation { advance(populationQueue) }
        if builtBuildings || builtPopulation { tileDirty = true }

        // Export through a custom house.  Price changes are not flushed
        // yet, as they may change again in csYearlyGoodsAdjust.
        if hasAbility(Ability.export) {
            var sales: [String] = []
            for goods in compactGoodsList {
                guard let type = goods.type else { continue }
                let data = exportData(type)
                guard data.exported, owner.canTrade(type, .customHouse) else { continue }
                let amount = goods.amount - data.exportLevel
                if amount <= 0 { continue }
                let oldGold = owner.gold
                let marketAmount = owner.sellInEurope(random, container, type, amount)
                if marketAmount > 0 { owner.extraTrades.append(AbstractGoods(type, marketAmount)) }
                let st = StringTemplate.template("model.colony.customs.saleData")
                    .addAmount("%amount%", amount)
                    .addNamed("%goods%", type)
                    .addAmount("%gold%", owner.gold - oldGold)
                sales.append(Messages.message(st) ?? "")
            }
            if !sales.isEmpty {
                cs.addMessage(owner, ModelMessage(.goodsMovement, "model.colony.customs.sale", self)
                    .addName("%colony%", name)
                    // Java's log builder starts with a space.
                    .addName("%data%", " " + sales.joined(separator: ", ")))
                cs.addPartial(.only(owner), owner, ("gold", String(owner.gold)))
            }
        }

        // Free buildings.
        if let game {
            for buildingType in spec.buildingTypeList where isAutomaticBuild(buildingType) {
                try buildBuilding(Building(game: game, colony: self, type: buildingType))
            }
        }
        checkBuildQueueIntegrity()

        // The rebels.
        updateSoL()
        if sonsOfLiberty / 10 != oldSonsOfLiberty / 10 {
            cs.addMessage(owner, ModelMessage(.sonsOfLiberty,
                                              sonsOfLiberty > oldSonsOfLiberty
                                                  ? "model.colony.soLIncrease" : "model.colony.soLDecrease",
                                              self, spec.getGoodsType("model.goods.bells"))
                .addAmount("%oldSoL%", oldSonsOfLiberty)
                .addAmount("%newSoL%", sonsOfLiberty)
                .addName("%colony%", name))
            if let message = checkForGovMgtChangeMessage() { cs.addMessage(owner, message) }
        }
        _ = updateProductionBonus()

        // Training finishes once the production bonus is settled.
        for case let building as Building in currentWorkLocations where building.canTeach {
            for teacher in building.unitList { building.csCheckTeach(teacher, cs) }
        }

        // Repair land units (only used if they have hit points).
        for unit in tile.unitList where !unit.isNaval && unit.isDamaged {
            unit.csRepairUnit(cs)
        }

        // Tell as little as will do.
        if tileDirty {
            cs.add(.perhaps(), tile)
        } else {
            cs.add(.only(owner), self)
        }
    }
}

/// A building's new turn: teaching and repairs (ServerBuilding).
extension Building {

    /// Teachers carry on teaching (or find a student); training is
    /// finished later, in csCheckTeach.
    private func csTeach(_ cs: ChangeSet) {
        guard let owner = colony?.owner else { return }
        for teacher in unitList {
            var student = teacher.student
            if let s = student, s.teacher !== teacher {
                // Make sure the teacher and student agree.
                teacher.setStudent(nil)
                student = nil
            }
            if student == nil && csAssignStudent(teacher, cs) {
                student = teacher.student
            }
            teacher.turnsOfTraining = student == nil ? 0 : teacher.turnsOfTraining + 1
            cs.add(.only(owner), teacher)
        }
    }

    /// Finish a teacher's training of its student, if it is time.
    ///
    /// - Returns: Whether the training was finished.
    @discardableResult
    public func csCheckTeach(_ teacher: Unit, _ cs: ChangeSet) -> Bool {
        guard let owner = colony?.owner, let student = teacher.student,
              teacher.turnsOfTraining >= teacher.neededTurnsOfTraining else { return false }
        csTrainStudent(teacher, student, cs)
        // The teacher was already added in csTeach.
        cs.add(.only(owner), student)
        if teacher.student == nil { csAssignStudent(teacher, cs) }
        return true
    }

    @discardableResult
    private func csTrainStudent(_ teacher: Unit, _ student: Unit, _ cs: ChangeSet) -> Bool {
        guard let colony, let owner = colony.owner else { return false }
        let oldName = student.label
        let skill = teacher.type.flatMap { student.teachingType($0) }
        if let skill {
            _ = student.changeType(skill)
            cs.addMessage(owner, ModelMessage(.unitImproved, "model.building.unitEducated", colony, self)
                .addStringTemplate("%oldName%", oldName)
                .addStringTemplate("%unit%", student.label)
                .addName("%colony%", colony.name))
        }
        student.turnsOfTraining = 0
        student.movesLeft = 0
        teacher.turnsOfTraining = 0
        teacher.movesLeft = 0
        if !student.canBeStudent(teacher) {
            student.setTeacher(nil)
            teacher.setStudent(nil)
        }
        return skill != nil
    }

    /// Find a student for a teacher, or warn that there is none.
    @discardableResult
    private func csAssignStudent(_ teacher: Unit, _ cs: ChangeSet) -> Bool {
        guard let colony, let owner = colony.owner else { return false }
        guard let student = colony.findStudent(teacher) else {
            cs.addMessage(owner, ModelMessage(.warning, "model.building.noStudent", colony, teacher)
                .addStringTemplate("%teacher%", teacher.label)
                .addName("%colony%", colony.name))
            return false
        }
        teacher.setStudent(student)
        teacher.changeWorkType(nil)
        student.setTeacher(teacher)
        cs.add(.only(owner), student)
        return true
    }

    /// Repair the damaged units on the colony's tile that this building
    /// can repair.
    private func csRepairUnits(_ cs: ChangeSet) {
        for unit in tile?.unitList ?? [] where unit.isDamaged
            && (type?.hasAbility(Ability.repairUnits, for: unit.type) ?? false) {
            unit.csRepairUnit(cs)
        }
    }

    /// Warn about production short of inputs (csCheckMissingInput).
    public func csCheckMissingInput(_ info: ProductionInfo, _ cs: ChangeSet) {
        guard !canAutoProduce, let colony, let owner else { return }
        let production = info.production
        guard !production.isEmpty else { return }
        if production.allSatisfy({ $0.amount == 0 }) {
            for gt in inputs.filter({ $0.amount > 0 }).compactMap(\.type) {
                cs.addMessage(owner, ModelMessage(.missingGoods, "model.building.noInput", self, gt)
                    .addNamed("%inputGoods%", gt)
                    .addNamed("%building%", self)
                    .addName("%colony%", colony.name))
            }
        } else {
            for ag in info.consumptionDeficit {
                guard let type = ag.type else { continue }
                cs.addMessage(owner, ModelMessage(.missingGoods, "model.building.notEnoughInput", self, type)
                    .addNamed("%building%", self)
                    .addName("%colony%", colony.name)
                    .addAmount("%number%", ag.amount)
                    .addNamed("%goodsType%", type))
            }
        }
    }

    /// The building's new turn.
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) {
        if canTeach { csTeach(cs) }
        if type?.hasAbility(Ability.repairUnits) ?? false { csRepairUnits(cs) }
    }
}

/// A colony tile's new turn: using up resources (ServerColonyTile).
extension ColonyTile {

    /// Use up some of a limited resource, removing it when it runs out.
    ///
    /// - Returns: The resource if it ran out.
    private func expendResource(_ tile: Tile, _ goodsType: GoodsType?, _ unitType: UnitType?) throws -> Resource? {
        guard let resource = tile.resource, !resource.isUnlimited, let goodsType else { return nil }
        if resource.useQuantity(goodsType, unitType, tile.potentialProduction(goodsType, unitType)) == 0 {
            try tile.cacheUnseen()
            _ = tile.removeResource()
            return resource
        }
        return nil
    }

    /// The tile's new turn.
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let colony, let owner = colony.owner, let workTile,
              !isColonyCenterTile, !isEmpty, canBeWorked else { return }
        for unit in unitList {
            if let resource = try expendResource(workTile, unit.workType, unit.type) {
                cs.addMessage(owner, ModelMessage(.warning, "model.colonyTile.resourceExhausted", colony)
                    .addNamed("%resource%", resource)
                    .addName("%colony%", colony.name))
                cs.add(.perhaps(), workTile)
                break
            }
        }
    }
}

extension Colony {
    /// Add a building a founding father gives, in place of the one it
    /// upgrades, moving its workers in (csFreeBuilding).
    public func csFreeBuilding(_ type: BuildingType, _ cs: ChangeSet) throws {
        guard canBuild(type), let game else { return }
        let present = building(type)?.unitList ?? []
        let build = Building(game: game, colony: self, type: type)
        try buildBuilding(build)
        checkBuildQueueIntegrity()
        cs.add(.only(owner), self)
        requestRearrange()
        for u in present { _ = u.setLocation(build) }
    }

    /// A native converted by a missionary joins the colony's tile
    /// (csAddConvert).
    public func csAddConvert(_ brave: Unit, _ cs: ChangeSet) throws {
        guard let newOwner = owner, let oldOwner = brave.owner, let tile, let spec = specification else { return }
        guard try oldOwner.csChangeOwner(brave, newOwner, UnitChangeType.conversion, tile, cs) else { return }
        if let role = spec.defaultRole { brave.changeRole(role, 0) }
        for g in brave.compactGoodsList { _ = brave.remove(g) }
        brave.movesLeft = 0
        brave.setState(.active)
        cs.addDisappear(newOwner, tile, brave)
        cs.add(.only(newOwner), tile)
        cs.addMessage(newOwner, ModelMessage(.unitAdded, "model.colony.newConvert", brave)
            .addStringTemplate("%nation%", oldOwner.nationLabel)
            .addName("%colony%", name))
        newOwner.invalidateCanSeeTiles()
    }
}

/// Equipping and eviction (server/model/ServerColony).
extension Colony {

    /// Equip a unit from the colony's goods, putting it on the colony's
    /// tile (csEquipForRole).
    public func csEquipForRole(_ unit: Unit, _ role: Role, _ roleCount: Int, _ random: JavaRandom,
                               _ cs: ChangeSet) throws -> Bool {
        let ret = equipForRole(unit, role, roleCount)
        if ret, let tile {
            if unit.isOnCarrier { unit.movesLeft = 0 }
            try tile.cacheUnseen()
            _ = unit.setLocation(tile)
            cs.add(.perhaps(), tile)
        }
        return ret
    }

    /// Move the colony's workers off a tile an enemy unit is fortifying
    /// on (csEvictUsers).
    public func csEvictUsers(_ enemyUnit: Unit, _ cs: ChangeSet) throws {
        guard let player = owner, let tile = enemyUnit.tile, let ct = colonyTile(tile),
              let colonyTile = ct.colony?.tile else { return }
        let copied = try colonyTile.tileToCache()
        if !ejectUnits(ct, ct.unitList) { return }
        try colonyTile.cacheUnseen(copied: copied)
        cs.addMessage(player, ModelMessage(.warning, "model.colony.workersEvicted", self, self)
            .addName("%colony%", name)
            .addStringTemplate("%location%", locationLabel(tile))
            .addStringTemplate("%enemyUnit%", enemyUnit.label))
        cs.add(.only(player), ct)
        cs.add(.perhaps(), self.tile)
    }
}

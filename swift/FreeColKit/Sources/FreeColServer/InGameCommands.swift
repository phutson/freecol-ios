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

/// The players' commands: each is checked as Java's message handler
/// checks it (the messages' serverHandler), then carried out as
/// InGameController does.
extension InGameController {

    /// Carry out a player's command.  Others are sent what they can
    /// see of it as it happens.
    ///
    /// - Returns: The changes for the player, or nil if there are none.
    /// - Throws: CommandRefused if the command is not valid, as Java's
    ///   clientError; NotYetPorted for what is not ported yet.
    public func perform(_ command: PlayerCommand, by player: Player) throws -> ChangeSet? {
        switch command {
        case .askSkill, .demandTribute, .deliverGift, .incite, .indianDemand, .learnSkill, .missionary,
             .nationSummary, .nativeGift, .nativeTrade, .scoutIndianSettlement, .scoutSpeakToChief:
            return try performNative(command, by: player)

        case .attack, .lootCargo:
            return try performCombat(command, by: player)

        case .declareIndependence, .diplomacy, .firstContact, .monarchAction, .spySettlement:
            return try performDiplomacy(command, by: player)

        case .endTurn:
            return try endTurn(player)

        case let .abandonColony(colonyId):
            let colony = try ours(player, colonyId, Colony.self)
            let count = colony.unitCount
            if count != 0 {
                throw CommandRefused("Attempt to abandon colony \(colonyId ?? "null") with non-zero unit count \(count)")
            }
            return try abandonSettlement(player, colony)

        case let .assignTeacher(studentId, teacherId):
            let student = try ours(player, studentId, Unit.self)
            let teacher = try ours(player, teacherId, Unit.self)
            guard let sc = student.colony else { throw CommandRefused("Student not in colony: \(studentId ?? "null")") }
            if !student.isInColony { throw CommandRefused("Student not working colony: \(studentId ?? "null")") }
            guard let tc = teacher.colony else { throw CommandRefused("Teacher not in colony: \(teacherId ?? "null")") }
            if !tc.canTrain(teacher) { throw CommandRefused("Teacher can not teach: \(teacherId ?? "null")") }
            if sc !== tc { throw CommandRefused("Student and teacher not in same colony: \(studentId ?? "null")") }
            if !student.canBeStudent(teacher) {
                throw CommandRefused("Student can not be taught by teacher: \(studentId ?? "null")")
            }
            return assignTeacher(player, student, teacher)

        case let .buildColony(name, unitId):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.canBuildColony { throw CommandRefused("Unit \(unitId ?? "null") can not build colony.") }
            guard let name else { throw CommandRefused("Null colony name") }
            if !name.isEmpty && game.settlement(byName: name) != nil {
                throw CommandRefused("Non-unique colony name \(name)")
            }
            guard let tile = unit.tile, player.canClaimToFoundSettlementReason(tile) == .none else {
                throw CommandRefused("Can not build colony on tile")
            }
            return try buildSettlement(player, unit, name)

        case let .cashInTreasureTrain(unitId):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.canCarryTreasure {
                throw CommandRefused("Can not cash in unit \(unitId ?? "null"), can not carry treasure.")
            }
            if !unit.canCashInTreasureTrain(unit.location) {
                throw CommandRefused("Can not cash in unit \(unitId ?? "null"), unsuitable location.")
            }
            return try cashInTreasureTrain(player, unit)

        case let .changeState(unitId, stateName):
            let unit = try ours(player, unitId, Unit.self)
            guard let state = Unit.UnitState.allCases.first(where: { $0.javaName == stateName }) else {
                throw CommandRefused("No unit state \(stateName ?? "null")")
            }
            if !unit.checkSetState(state) {
                throw CommandRefused("Unit \(unitId ?? "null") can not change state: \(unit.state) -> \(state)")
            }
            return try changeState(player, unit, state)

        case let .changeWorkImprovementType(unitId, typeId):
            let unit = try ours(player, unitId, Unit.self)
            guard let tile = unit.tile else { throw CommandRefused("Unit is not on the map: \(unitId ?? "null")") }
            if !unit.hasAbility(Ability.improveTerrain) {
                throw CommandRefused("Unit can not improve tiles: \(unitId ?? "null")")
            }
            guard let type = game.specification?.getTileImprovementType(typeId) else {
                throw CommandRefused("Not a tile improvement type: \(typeId ?? "null")")
            }
            if type.isNatural { throw CommandRefused("ImprovementType must not be natural: \(typeId ?? "")") }
            if !(tile.type.map(type.isTileTypeAllowed) ?? false) {
                throw CommandRefused("ImprovementType not allowed on tile: \(typeId ?? "")")
            }
            if let improvement = tile.tileImprovement(type) {
                if !improvement.isWorkerAllowed(unit) {
                    throw CommandRefused("Unit can not work on improvement: \(typeId ?? "")")
                }
            } else if !type.isWorkerAllowed(unit) {
                throw CommandRefused("Unit can not create improvement: \(typeId ?? "")")
            }
            return changeWorkImprovementType(player, unit, type)

        case let .changeWorkType(unitId, typeId):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.hasTile { throw CommandRefused("Unit is not on the map: \(unitId ?? "null")") }
            guard let type = game.specification?.getGoodsType(typeId) else {
                throw CommandRefused("Not a goods type: \(typeId ?? "null")")
            }
            return changeWorkType(player, unit, type)

        case let .chooseFoundingFather(fatherId):
            guard let father = game.specification?.getFoundingFather(fatherId) else {
                throw CommandRefused("No founding father selected")
            }
            if !player.canRecruitFoundingFather {
                throw CommandRefused("Player can not recruit fathers: \(player.id ?? "null")")
            }
            if !player.offeredFathers.contains(where: { $0 === father }) {
                throw CommandRefused("Founding father not offered: \(father.id ?? "null")")
            }
            player.updateCurrentFather(father)
            return nil

        case let .claimLand(tileId, claimantId, priceString):
            return try claimLandCommand(player, tileId, claimantId, priceString)

        case let .clearSpeciality(unitId):
            let unit = try ours(player, unitId, Unit.self)
            return try clearSpeciality(player, unit)

        case let .declineMounds(unitId, direction):
            let unit = try ours(player, unitId, Unit.self)
            let tile = try neighbourTile(unit, direction)
            guard tile.lostCityRumour?.type == .mounds else {
                throw CommandRefused("No mounds rumour on tile: \(tile.id ?? "null")")
            }
            try tile.cacheUnseen()
            _ = tile.removeLostCityRumour()
            let cs = ChangeSet().add(.perhaps(), tile)
            try sendToOthers(player, cs)
            return cs

        case let .disbandUnit(unitId):
            let unit = try ours(player, unitId, Unit.self)
            return try disbandUnit(player, unit)

        case let .disembark(unitId):
            let unit = try ours(player, unitId, Unit.self)
            return try disembarkUnit(player, unit)

        case let .embark(unitId, carrierId, directionName):
            let unit = try ours(player, unitId, Unit.self)
            let carrier = try ours(player, carrierId, Unit.self)
            if let directionName {
                if unit.movesLeft <= 0 { throw CommandRefused("Unit has no moves left: \(unitId ?? "null")") }
                guard let direction = Direction.allCases.first(where: { $0.javaName == directionName }) else {
                    throw CommandRefused("No direction \(directionName)")
                }
                guard let destination = unit.tile?.neighbour(direction), carrier.tile === destination else {
                    throw CommandRefused("Carrier: \(carrierId ?? "null") is not at destination tile")
                }
            } else if !carrier.isAtLocation(unit.location) {
                throw CommandRefused("Unit \(unitId ?? "null") and carrier \(carrierId ?? "null") are not co-located.")
            }
            return try embarkUnit(player, unit, carrier)

        case let .emigrateUnit(slotString):
            guard let europe = player.europe else { throw CommandRefused("No Europe to migrate from.") }
            guard let slot = slotString.flatMap({ Int($0) }) else {
                throw CommandRefused("Bad slot: \(slotString ?? "null")")
            }
            if !Europe.MigrationType.validMigrantSlot(slot) {
                throw CommandRefused("Invalid slot for recruitment: \(slot)")
            }
            let type: Europe.MigrationType
            if player.remainingEmigrants > 0 {
                if Europe.MigrationType.unspecificMigrantSlot(slot) {
                    throw CommandRefused("Specific slot expected for FoY migration")
                }
                type = .fountain
            } else if player.checkEmigrate {
                if Europe.MigrationType.specificMigrantSlot(slot) && !player.hasAbility(Ability.selectRecruit) {
                    throw CommandRefused("selectRecruit ability absent")
                }
                type = .normal
            } else {
                let cost = europe.currentRecruitPrice
                if !player.checkGold(cost) {
                    throw CommandRefused("No migrants available at cost \(cost) for player with \(player.gold) gold")
                }
                type = .recruit
            }
            let cs = ChangeSet()
            try player.csEmigrate(slot, type, random, cs)
            return cs

        case let .equipForRole(unitId, roleId, countString):
            let unit = try ours(player, unitId, Unit.self)
            if unit.isInEurope {
                // Always OK.
            } else if !unit.hasTile {
                throw CommandRefused("Unit is not on the map: \(unitId ?? "null")")
            } else if unit.settlement == nil {
                throw CommandRefused("Unit is not in a settlement: \(unitId ?? "null")")
            }
            guard let role = game.specification?.getRole(roleId) else {
                throw CommandRefused("Not a role: \(roleId ?? "null")")
            }
            guard let count = countString.flatMap({ JavaString.parseInt($0) }).map(Int.init) else {
                throw CommandRefused("Role count is not an integer: \(countString ?? "null")")
            }
            if count < 0 || count > role.maximumCount { throw CommandRefused("Invalid role count: \(count)") }
            return try equipForRole(player, unit, role, count)

        case let .joinColony(colonyId, unitId):
            let unit = try ours(player, unitId, Unit.self)
            let colony = try ours(player, colonyId, Colony.self)
            return try joinColony(player, unit, colony)

        case let .loadGoods(locationId, typeId, amountString, carrierId):
            guard let location = game.getFreeColGameObject(locationId) as? any Location else {
                throw CommandRefused("Not a location: \(locationId ?? "null")")
            }
            let carrier = try ours(player, carrierId, Unit.self)
            if !carrier.canCarryGoods { throw CommandRefused("Not a goods carrier: \(carrierId ?? "null")") }
            if carrier.tradeLocation == nil { throw CommandRefused("Not at a trade location: \(carrierId ?? "null")") }
            guard let type = game.specification?.getGoodsType(typeId) else {
                throw CommandRefused("Not a goods type: \(typeId ?? "null")")
            }
            guard let amount = amountString.flatMap({ JavaString.parseInt($0) }).map(Int.init) else {
                throw CommandRefused("Bad amount: \(amountString ?? "null")")
            }
            if amount <= 0 { throw CommandRefused("Amount must be positive: \(amount)") }
            return try loadGoods(player, location, type, amount, carrier)

        case let .move(unitId, direction):
            let unit = try ours(player, unitId, Unit.self)
            let tile = try neighbourTile(unit, direction)
            let moveType = unit.moveType(tile)
            if !moveType.isProgress {
                throw CommandRefused("Illegal move for: \(unitId ?? "null") type: \(moveType) to: \(tile.id ?? "null")")
            }
            let cs = ChangeSet()
            try unit.csMove(tile, random, cs)
            try sendToOthers(player, cs)
            return cs

        case let .moveTo(unitId, destinationId):
            let unit = try ours(player, unitId, Unit.self)
            guard let destination = game.findFreeColLocation(destinationId) else {
                throw CommandRefused("Not a location: \(destinationId ?? "null")")
            }
            return try moveTo(player, unit, destination)

        case let .newRegionName(regionId, tileId, unitId, name):
            guard let tile = game.getFreeColGameObject(tileId) as? Tile, player.hasExplored(tile) else {
                throw CommandRefused("Can not claim discovery in unexplored tile: \(tileId ?? "null")")
            }
            let unit = try ours(player, unitId, Unit.self)
            guard let region = tile.discoverableRegion else {
                throw CommandRefused("No discoverable region in: \(tile.id ?? "null")")
            }
            if region.id != regionId {
                throw CommandRefused("Region mismatch, \(region.id ?? "null") != \(regionId ?? "null")")
            }
            // The discoverer is set when the unit moves in.
            if region.discoverer != unit.id {
                throw CommandRefused("Discoverer mismatch, \(region.discoverer ?? "null") expected, \(unit.id ?? "null") provided.")
            }
            let cs = ChangeSet()
            region.csDiscover(player, unit, game.turn, name, cs)
            try sendToOthers(player, cs)
            return cs

        case let .newLandName(unitId, name):
            let unit = try ours(player, unitId, Unit.self)
            guard let tile = unit.tile else { throw CommandRefused("Unit is not on the map: \(unitId ?? "null")") }
            if !tile.isLand { throw CommandRefused("Unit is not in the new world: \(unitId ?? "null")") }
            guard let name, !name.isEmpty else { throw CommandRefused("Empty new land name") }
            return setNewLandName(player, unit, name)

        case let .payArrears(typeId):
            guard let type = game.specification?.getGoodsType(typeId) else {
                throw CommandRefused("Not a goods type: \(typeId ?? "null")")
            }
            return try payArrears(player, type)

        case let .payForBuilding(colonyId):
            let colony = try ours(player, colonyId, Colony.self)
            return try payForBuilding(player, colony)

        case let .putOutsideColony(unitId):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.hasTile { throw CommandRefused("Unit is not on the map: \(unitId ?? "null")") }
            if unit.colony == nil { throw CommandRefused("Unit is not in a colony: \(unitId ?? "null")") }
            return try putOutsideColony(player, unit)

        case let .rearrangeColony(colonyId, arrangements):
            let spec = game.specification
            // As Java reads them: no checks of who owns what.
            let resolved = arrangements.map { a in
                (unit: game.getFreeColGameObject(a.unit) as? Unit,
                 location: game.findFreeColLocation(a.location),
                 work: (a.work ?? "").isEmpty ? nil : spec?.getGoodsType(a.work),
                 role: spec?.getRole(a.role),
                 roleCount: Int(a.roleCount ?? "") ?? 0)
            }
            let colony = try ours(player, colonyId, Colony.self)
            if resolved.isEmpty { throw CommandRefused("Empty rearrangement list.") }
            var ready: [(unit: Unit, location: any Location, work: GoodsType?, role: Role, roleCount: Int)] = []
            for a in resolved {
                // Java's message reports every problem as at index 0.
                guard let unit = a.unit else { throw CommandRefused("Invalid unit 0") }
                guard let location = a.location else { throw CommandRefused("Invalid location 0") }
                guard let role = a.role else { throw CommandRefused("Invalid role 0") }
                if a.roleCount < 0 { throw CommandRefused("Invalid role count 0") }
                ready.append((unit, location, a.work, role, a.roleCount))
            }
            return try rearrangeColony(player, colony, ready)

        case let .rename(nameableId, name):
            let object = try ours(player, nameableId, FreeColGameObject.self)
            guard object is Unit || object is Settlement else {
                throw CommandRefused("Not a nameable: \(nameableId ?? "null")")
            }
            return try renameObject(player, object, name)

        case let .setBuildQueue(colonyId, queue):
            let colony = try ours(player, colonyId, Colony.self)
            // Unknown types are dropped, as in Java.
            let buildables = queue.compactMap { game.specification?.getType($0) as? BuildableType }
            return setBuildQueue(player, colony, buildables)

        case let .setGoodsLevels(colonyId, attributes):
            let colony = try ours(player, colonyId, Colony.self)
            guard let attributes, let type = game.specification?.getGoodsType(attributes["id"]) else {
                throw CommandRefused("No export data present.")
            }
            let data = ExportData(type, importLevel: Int(attributes["importLevel"] ?? "") ?? -1)
            if let v = attributes["highLevel"].flatMap({ Int($0) }) { data.highLevel = v }
            if let v = attributes["lowLevel"].flatMap({ Int($0) }) { data.lowLevel = v }
            if let v = attributes["exportLevel"].flatMap({ Int($0) }) { data.exportLevel = v }
            data.exported = attributes["exported"] == "true"
            colony.setExportData(data)
            return ChangeSet().add(.only(player), colony)

        case let .setDestination(unitId, destinationId):
            let unit = try ours(player, unitId, Unit.self)
            let destination = destinationId.flatMap { game.findFreeColLocation($0) }
            return setDestination(player, unit, destination)

        case let .trainUnitInEurope(typeId):
            guard let type = game.specification?.getUnitType(typeId) else {
                throw CommandRefused("Not a unit type: \(typeId ?? "null")")
            }
            return try trainUnitInEurope(player, type)

        case let .unloadGoods(typeId, amountString, carrierId):
            let amount = amountString.flatMap { JavaString.parseInt($0) }.map(Int.init) ?? -1
            let carrier = try ours(player, carrierId, Unit.self)
            if !carrier.canCarryGoods { throw CommandRefused("Not a goods carrier: \(carrierId ?? "null")") }
            guard let type = game.specification?.getGoodsType(typeId) else {
                throw CommandRefused("Not a goods type: \(typeId ?? "null")")
            }
            if amount <= 0 { throw CommandRefused("Invalid amount: \(amount)") }
            let present = carrier.goodsCount(type)
            if present < amount {
                throw CommandRefused("Attempt to unload \(amount) \(type.id ?? "") but only \(present) present")
            }
            return try unloadGoods(player, type, amount, carrier)

        case let .work(unitId, workLocationId):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.hasTile { throw CommandRefused("Unit is not on the map: \(unitId ?? "null")") }
            guard let colony = unit.tile?.colony else {
                throw CommandRefused("Unit is not at a colony: \(unitId ?? "null")")
            }
            guard let workLocation = game.getFreeColGameObject(workLocationId) as? WorkLocation else {
                throw CommandRefused("Not a work location: \(workLocationId ?? "null")")
            }
            if workLocation.colony !== colony {
                throw CommandRefused("Work location is not in colony: \(workLocationId ?? "null")")
            }
            if !workLocation.canAdd(unit) {
                throw CommandRefused("Can not add \(unitId ?? "null") to \(workLocationId ?? "null")")
            }
            return try work(player, unit, workLocation)
        }
    }

    /// One of the player's own objects (getOurFreeColGameObject).
    func ours<T: FreeColGameObject>(_ player: Player, _ id: String?, _ type: T.Type) throws -> T {
        guard let object = game.getFreeColGameObject(id) as? T else {
            throw CommandRefused("Not a \(T.self): \(id ?? "null")")
        }
        guard let ownable = object as? Ownable else { throw CommandRefused("Not ownable: \(id ?? "null")") }
        if !player.owns(ownable) { throw CommandRefused("\(T.self) not owned by \(player.id ?? "null"): \(id ?? "null")") }
        return object
    }

    /// The tile beside a unit in a direction (Unit.getNeighbourTile).
    func neighbourTile(_ unit: Unit, _ directionName: String?) throws -> Tile {
        guard let direction = Direction.allCases.first(where: { $0.javaName == directionName }) else {
            throw CommandRefused("No direction \(directionName ?? "null")")
        }
        guard let tile = unit.tile else { throw CommandRefused("Unit is not on the map: \(unit.id ?? "null")") }
        guard let neighbour = tile.neighbour(direction) else {
            throw CommandRefused("Could not find tile in direction: \(direction) from: \(tile.id ?? "null")")
        }
        return neighbour
    }

    // MARK: Moving

    /// Sail across the high seas, to Europe, the map or a settlement,
    /// turning round if already at sea (moveTo).
    private func moveTo(_ player: Player, _ unit: Unit, _ destination: any Location) throws -> ChangeSet {
        let cs = ChangeSet()
        guard let highSeas = player.highSeas else { throw CommandRefused("No high seas") }
        let current = unit.destination
        func connects(_ l: (any Location)?) -> Bool {
            highSeas.destinations.contains { $0 === l }
        }
        var others = false
        var invalid = false
        if !(unit.type?.canMoveToHighSeas ?? false) {
            invalid = true
        } else if let europe = destination as? Europe {
            if !connects(europe) {
                throw CommandRefused("HighSeas does not connect to: \(europe.id ?? "null")")
            } else if unit.location === highSeas {
                if !(current is Europe) {
                    // Turned round.
                    unit.workLeft = unit.sailTurns - unit.workLeft + 1
                }
                unit.destination = europe
                cs.add(.only(player), unit, highSeas)
            } else if let tile = unit.tile {
                unit.setEntryLocation(tile)
                unit.workLeft = unit.sailTurns
                unit.destination = europe
                unit.movesLeft = 0
                _ = unit.setLocation(highSeas)
                player.invalidateCanSeeTiles()
                cs.addDisappear(player, tile, unit)
                cs.add(.only(player), tile, highSeas)
                others = true
            } else {
                invalid = true
            }
            // The way back to the map, if there was none.
            if !highSeas.destinations.contains(where: { $0 is Map }), let map = game.map {
                highSeas.addDestination(map)
            }
        } else if let map = destination as? Map {
            if !connects(map) {
                throw CommandRefused("HighSeas does not connect to: \(map.id ?? "null")")
            } else if unit.location === highSeas {
                if current !== map && (current == nil || current?.tile == nil || current?.tile?.map !== map) {
                    unit.workLeft = unit.sailTurns - unit.workLeft + 1
                }
                unit.destination = map
                cs.add(.only(player), highSeas)
            } else if let europe = unit.location as? Europe {
                unit.workLeft = unit.sailTurns
                unit.destination = map
                unit.movesLeft = 0
                _ = unit.setLocation(highSeas)
                cs.add(.only(player), europe, highSeas)
            } else {
                invalid = true
            }
        } else if let settlement = destination as? Settlement {
            if !connects(settlement.tile?.map) {
                throw CommandRefused("HighSeas does not connect to: \(settlement.id ?? "null")")
            } else if unit.location === highSeas {
                // Direction hardly matters, so start again.
                unit.workLeft = unit.sailTurns
                unit.destination = settlement
                cs.add(.only(player), highSeas)
            } else if let europe = unit.location as? Europe {
                unit.workLeft = unit.sailTurns
                unit.destination = settlement
                unit.movesLeft = 0
                _ = unit.setLocation(highSeas)
                cs.add(.only(player), europe, highSeas)
            } else {
                invalid = true
            }
        } else {
            throw CommandRefused("Bogus moveTo destination")
        }
        if invalid {
            throw CommandRefused("Invalid moveTo: unit=\(unit.id ?? "null")")
        }
        if others { try sendToOthers(player, cs) }
        return cs
    }

    // MARK: Units

    private func assignTeacher(_ player: Player, _ student: Unit, _ teacher: Unit) -> ChangeSet {
        let oldStudent = teacher.student
        let oldTeacher = student.teacher
        let cs = ChangeSet()
        if let oldTeacher {
            oldTeacher.student = nil
            cs.add(.only(player), oldTeacher)
        }
        if let oldStudent {
            oldStudent.teacher = nil
            cs.add(.only(player), oldStudent)
        }
        teacher.student = student
        teacher.changeWorkType(nil)
        student.teacher = teacher
        cs.add(.only(player), student, teacher)
        return cs
    }

    private func changeState(_ player: Player, _ unit: Unit, _ state: Unit.UnitState) throws -> ChangeSet {
        let cs = ChangeSet()
        let tile = unit.tile
        var tileDirty = tile?.indianSettlement != nil
        if state == .fortifying, let tile, let colony = tile.owningSettlement as? Colony,
           let owner = colony.owner, owner !== unit.owner,
           player.stance(owner) != .alliance, player.stance(owner) != .peace {
            if colony.isTileInUse(tile) { try colony.csEvictUsers(unit, cs) }
            if player.stance(owner) == .war {
                tile.changeOwnership(nil, nil) // Clear the owner if at war.
                tileDirty = true
            }
        }
        unit.setState(state)
        if tileDirty {
            cs.add(.perhaps(), tile)
        } else {
            cs.add(.perhaps(), unit.location as? FreeColGameObject)
        }
        try sendToOthers(player, cs)
        return cs
    }

    private func changeWorkImprovementType(_ player: Player, _ unit: Unit, _ type: TileImprovementType) -> ChangeSet {
        let tile = unit.tile!
        var improvement = tile.tileImprovement(type)
        if improvement == nil {
            let ti = TileImprovement(game: game, tile: tile, type: type, style: nil)
            _ = tile.add(ti)
            improvement = ti
        }
        unit.workImprovement = improvement
        unit.setState(.improving)
        return ChangeSet().add(.only(player), tile)
    }

    private func changeWorkType(_ player: Player, _ unit: Unit, _ type: GoodsType) -> ChangeSet {
        if unit.workType !== type {
            unit.experience = 0
            unit.changeWorkType(type)
        }
        return ChangeSet().add(.only(player), unit.colony)
    }

    private func clearSpeciality(_ player: Player, _ unit: Unit) throws -> ChangeSet {
        guard let uc = unit.unitChange(UnitChangeType.clearSkill), let to = uc.to else {
            throw CommandRefused("Can not clear unit speciality: \(unit.id ?? "null")")
        }
        if unit.student != nil { throw CommandRefused("Can not clear speciality of a teacher.") }
        _ = unit.changeType(to)
        return ChangeSet().add(.only(player), unit)
    }

    private func disbandUnit(_ player: Player, _ unit: Unit) throws -> ChangeSet {
        let cs = ChangeSet()
        let location = unit.location
        cs.add(.perhaps().always(player), location as? FreeColGameObject)
        try unit.csRemove(.perhaps().always(player), location, cs)
        player.invalidateCanSeeTiles()
        try sendToOthers(player, cs)
        return cs
    }

    private func disembarkUnit(_ player: Player, _ unit: Unit) throws -> ChangeSet {
        if unit.isNaval { throw CommandRefused("Naval unit \(unit.id ?? "null") can not disembark.") }
        guard let carrier = unit.carrier, let newLocation = carrier.location else {
            throw CommandRefused("Unit \(unit.id ?? "null") is not embarked.")
        }
        let cs = ChangeSet()
        let newTiles = newLocation.tile.map { player.collectNewTiles($0.surroundingTiles(0, unit.lineOfSight)) }
        _ = unit.setLocation(newLocation)
        player.invalidateCanSeeTiles()
        unit.movesLeft = 0 // As in Col1, disembarking takes the whole move.
        cs.add(.perhaps(), newLocation as? FreeColGameObject)
        if let newTiles { player.csSeeNewTiles(newTiles, cs) }
        try sendToOthers(player, cs)
        return cs
    }

    private func embarkUnit(_ player: Player, _ unit: Unit, _ carrier: Unit) throws -> ChangeSet {
        if unit.isNaval { throw CommandRefused("Naval unit \(unit.id ?? "null") can not embark.") }
        let reason = carrier.noAddReason(unit)
        if reason != .none {
            throw CommandRefused("Carrier: \(carrier.id ?? "null") can not carry \(unit.id ?? "null"): \(reason)")
        }
        let cs = ChangeSet()
        try unit.csEmbark(carrier, cs)
        try sendToOthers(player, cs)
        return cs
    }

    private func equipForRole(_ player: Player, _ unit: Unit, _ role: Role, _ count: Int) throws -> ChangeSet? {
        let cs = ChangeSet()
        let ret: Bool
        if unit.isInEurope, let europe = player.europe {
            ret = europe.csEquipForRole(unit, role, count, random, cs)
        } else if let colony = unit.colony {
            ret = try colony.csEquipForRole(unit, role, count, random, cs)
        } else if let settlement = unit.indianSettlement {
            ret = settlement.csEquipForRole(unit, role, count, random, cs)
        } else {
            throw CommandRefused("Unsuitable equip location for: \(unit.id ?? "null")")
        }
        if !ret { return nil }
        if unit.initialMovesLeft != unit.movesLeft { unit.movesLeft = 0 }
        if let carrier = unit.carrier, carrier.initialMovesLeft != carrier.movesLeft, carrier.movesLeft != 0 {
            carrier.movesLeft = 0
        }
        return cs
    }

    private func putOutsideColony(_ player: Player, _ unit: Unit) throws -> ChangeSet {
        let tile = unit.tile!
        let colony = unit.colony
        if unit.isInColony { try tile.cacheUnseen() }
        _ = unit.setLocation(tile)
        let cs = ChangeSet()
        cs.add(.only(player), tile)
        cs.add(.perhaps().except(player), colony)
        return cs
    }

    private func renameObject(_ player: Player, _ object: FreeColGameObject, _ name: String?) throws -> ChangeSet {
        let cs = ChangeSet()
        if let settlement = object as? Settlement {
            try settlement.tile?.cacheUnseen()
            settlement.name = name
        } else if let unit = object as? Unit {
            unit.name = name
        }
        cs.addPartial(.all(), object, ("name", name ?? ""))
        try sendToOthers(player, cs)
        return cs
    }

    private func setDestination(_ player: Player, _ unit: Unit, _ destination: (any Location)?) -> ChangeSet {
        var destination = destination
        if unit.tradeRoute != nil {
            // Bring the unit to port.
            if destination == nil && unit.isAtSea { destination = unit.stop?.location }
            unit.tradeRoute = nil
        }
        unit.destination = destination
        return ChangeSet().add(.only(player), unit)
    }

    private func setNewLandName(_ player: Player, _ unit: Unit, _ name: String) -> ChangeSet {
        let cs = ChangeSet()
        player.newLandName = name
        cs.addPartial(.only(player), player, ("newLandName", name))
        cs.addHistory(player, HistoryEvent(game.turn, .discoverNewWorld, player).addName("%name%", name))
        return cs
    }

    private func work(_ player: Player, _ unit: Unit, _ workLocation: WorkLocation) throws -> ChangeSet {
        guard let spec = game.specification, let colony = workLocation.colony else { return ChangeSet() }
        colony.goodsContainer?.saveState()
        let cs = ChangeSet()
        if let tile = workLocation.workTile, tile.owningSettlement !== colony {
            // Claim the free land (canAdd succeeded).
            try player.csClaimLand(tile, colony, 0, cs)
        }
        if let role = spec.defaultRole { colony.equipForRole(unit, role, 0) }
        if let uc = unit.unitChange(UnitChangeType.enterColony), uc.appliesTo(unit), let to = uc.to {
            _ = unit.changeType(to)
        }
        if !unit.isInColony { try unit.colony?.tile?.cacheUnseen() }
        _ = unit.setLocation(workLocation)
        cs.add(.perhaps(), colony.tile)
        try sendToOthers(player, cs)
        return cs
    }

    // MARK: Colonies

    private func abandonSettlement(_ player: Player, _ settlement: Settlement) throws -> ChangeSet {
        let cs = ChangeSet()
        if settlement is Colony {
            player.csLoseLocation(settlement, cs)
            cs.addHistory(player, HistoryEvent(game.turn, .abandonColony, player)
                .addName("%colony%", settlement.name))
        }
        try player.csDisposeSettlement(settlement, cs)
        try sendToOthers(player, cs)
        return cs
    }

    private func buildSettlement(_ player: Player, _ unit: Unit, _ name: String) throws -> ChangeSet {
        guard let spec = game.specification, let tile = unit.tile else { return ChangeSet() }
        let cs = ChangeSet()
        let name = name.isEmpty ? game.nameCache.settlementName(player, random) : name
        guard player.isEuropean else { throw NotYetPorted("natives building a settlement") }
        let nation = player.nationLabel
        let colony = Colony(game: game, owner: player, name: name, tile: tile)
        for t in tile.surroundingTiles(colony.radius) { try t.cacheUnseen() }
        // New sightings before placing the colony.
        cs.add(.only(player), player.collectNewTiles(colony.javaVisibleTileSet))
        // Coronado.
        for sp in connectedPlayers(excluding: player) where sp.hasAbility(Ability.seeAllColonies) {
            cs.add(.only(sp), sp.exploreForSettlement(colony))
            sp.invalidateCanSeeTiles()
            cs.addMessage(sp, ModelMessage(.foreignDiplomacy, "buildColony.others", colony)
                .addStringTemplate("%nation%", nation)
                .addStringTemplate("%colony%", locationLabel(colony, for: sp))
                .addStringTemplate("%region%", tile.region?.label))
        }
        _ = player.addSettlement(colony)
        colony.placeSettlement(spec.getBoolean(GameOptions.claimAllTiles))
        cs.addHistory(player, HistoryEvent(game.turn, .foundColony, player).addName("%colony%", colony.name))
        // Take away the founder's equipment, which could confuse placing it.
        if let role = spec.defaultRole { colony.equipForRole(unit, role, 0) }

        _ = unit.setLocation(colony)
        unit.movesLeft = 0
        cs.add(.perhaps(), colony.ownedTiles)
        player.invalidateCanSeeTiles()
        try sendToOthers(player, cs)
        return cs
    }

    private func claimLandCommand(_ player: Player, _ tileId: String?, _ claimantId: String?,
                                  _ priceString: String?) throws -> ChangeSet {
        guard let tile = game.getFreeColGameObject(tileId) as? Tile else {
            throw CommandRefused("Not a file: \(tileId ?? "null")")
        }
        var settlement: Settlement?
        let claimant = game.getFreeColGameObject(claimantId)
        if claimant is Unit {
            let unit = try ours(player, claimantId, Unit.self)
            if unit.tile !== tile { throw CommandRefused("Unit not at tile: \(tileId ?? "null")") }
            // An implicit claim by a settlement beside it.
            if tile.owningSettlement == nil {
                for t in tile.surroundingTiles(1) {
                    if let colony = t.colony, player.owns(colony) {
                        settlement = colony
                        break
                    }
                }
            }
        } else if claimant is Settlement {
            let s = try ours(player, claimantId, Settlement.self)
            if s.owner?.isEuropean ?? false, !(s.tile?.isAdjacent(tile) ?? false) {
                throw CommandRefused("Settlement can not claim tile: \(tileId ?? "null")")
            }
            settlement = s
        } else {
            throw CommandRefused("Not a unit or settlement: \(claimantId ?? "null")")
        }
        guard var price = priceString.flatMap({ JavaString.parseInt($0) }).map(Int.init) else {
            throw CommandRefused("Bad price: \(priceString ?? "null")")
        }
        let value = player.landPrice(tile)
        let owner = tile.owner
        if owner == nil {
            price = 0
        } else if owner === player {
            if settlement != nil && tile.owningSettlement != nil && tile.isInUse {
                throw CommandRefused("Can not claim tile \(tile.id ?? ""): already owned.")
            }
            price = 0
        } else if owner!.isEuropean {
            if tile.owningSettlement == nil || tile.owningSettlement === settlement {
                price = 0
            } else {
                throw CommandRefused("Can not claim tile \(tile.id ?? ""): European owners will not sell.")
            }
        } else {
            switch player.canClaimForSettlementReason(tile) {
            case .none:
                break
            case .natives:
                if price >= 0 {
                    if price < value { throw CommandRefused("Can not claim tile \(tile.id ?? ""): insufficient offer.") }
                    if !player.checkGold(price) {
                        throw CommandRefused("Can not pay for tile: \(tile.id ?? ""): insufficient funds.")
                    }
                }
            case let why:
                throw CommandRefused("Can not claim tile \(tile.id ?? ""): \(why)")
            }
        }

        let cs = ChangeSet()
        try player.csClaimLand(tile, settlement, price, cs)
        if settlement != nil && player.isEuropean {
            // Coronado sees every colony's land.
            for sp in connectedPlayers(excluding: player) where sp.hasAbility(Ability.seeAllColonies) {
                sp.exploreTile(tile)
                cs.add(.only(sp), tile)
                sp.invalidateCanSeeTiles()
            }
        }
        try sendToOthers(player, cs)
        return cs
    }

    private func joinColony(_ player: Player, _ unit: Unit, _ colony: Colony) throws -> ChangeSet {
        let cs = ChangeSet()
        let ownedTiles = colony.ownedTiles
        guard let tile = colony.tile else { return cs }
        try tile.cacheUnseen()
        _ = unit.setLocation(colony)
        unit.movesLeft = 0
        if let role = game.specification?.defaultRole { colony.equipForRole(unit, role, 0) }
        cs.add(.only(player), tile)
        for t in tile.surroundingTiles(1, colony.radius)
        where t.owningSettlement === colony && !ownedTiles.contains(where: { $0 === t }) {
            cs.add(.perhaps(), t)
        }
        try sendToOthers(player, cs)
        return cs
    }

    private func payForBuilding(_ player: Player, _ colony: Colony) throws -> ChangeSet {
        guard let spec = game.specification, spec.getBoolean(GameOptions.payForBuilding) else {
            throw CommandRefused("Pay for building is disabled")
        }
        guard let build = colony.currentlyBuilding else {
            throw CommandRefused("Colony \(colony.id ?? "null") is not building anything!")
        }
        let required = colony.requiredGoods(build)
        let price = colony.priceGoodsForBuilding(required)
        if !player.checkGold(price) { throw CommandRefused("Insufficient funds to pay for build.") }
        // Keep the right gold, as buying deducts the usual prices.
        let savedGold = player.modifyGold(-price)
        _ = player.modifyGold(price)

        let cs = ChangeSet()
        guard let container = colony.goodsContainer else { return cs }
        container.saveState()
        for ag in required {
            guard let type = ag.type else { continue }
            if type.isStorable {
                if player.buyInEurope(random, container, type, ag.amount) < 0 {
                    throw CommandRefused("Can not buy \(ag.amount) \(type.id ?? "") for \(build.id ?? "")")
                }
                player.csFlushMarket(type, cs)
            } else {
                _ = container.addGoods(type, ag.amount)
            }
        }
        colony.invalidateCache()
        player.gold = savedGold
        cs.addPartial(.only(player), player, ("gold", String(player.gold)))
        cs.add(.only(player), container)
        return cs
    }

    /// Rearrange a colony's units (rearrangeColony): everyone moved out
    /// of the way with their equipment stockpiled, then put in place,
    /// retrying those waiting for room, then equipped, simplest role
    /// first.
    private func rearrangeColony(_ player: Player, _ colony: Colony,
                                 _ arrangements: [(unit: Unit, location: any Location, work: GoodsType?,
                                                   role: Role, roleCount: Int)]) throws -> ChangeSet {
        guard let tile = colony.tile, let defaultRole = game.specification?.defaultRole else {
            throw CommandRefused("Colony not on the map")
        }
        try tile.cacheUnseen()
        for a in arrangements {
            a.unit.setLocation(tile)
            if !a.unit.hasDefaultRole { _ = colony.equipForRole(a.unit, defaultRole, 0) }
        }
        var todo = arrangements
        while !todo.isEmpty {
            let a = todo.removeFirst()
            if a.location === tile { continue }
            guard let wl = a.location as? WorkLocation else { continue } // Java's cast would throw
            switch wl.noAddReason(a.unit) {
            case .none:
                a.unit.setLocation(wl)
                if a.unit.workType !== a.work { a.unit.changeWorkType(a.work) }
            case .alreadyPresent:
                if a.unit.workType !== a.work { a.unit.changeWorkType(a.work) }
            case .capacityExceeded:
                todo.append(a)
            default:
                break // Java logs a bad move
            }
        }
        let roles = arrangements.filter { $0.role !== defaultRole && $0.role !== $0.unit.role }
            .stableSorted { a, b in
                let cmp = a.role.compareTo(b.role)
                return cmp != 0 ? cmp < 0 : a.roleCount < b.roleCount
            }
        for a in roles where !colony.equipForRole(a.unit, a.role, a.roleCount) {
            throw CommandRefused("Failed to equip \(a.unit.id ?? "") for role \(a.role.id ?? "") at \(colony)")
        }
        return ChangeSet().add(.perhaps(), tile)
    }

    private func setBuildQueue(_ player: Player, _ colony: Colony, _ queue: [BuildableType]) -> ChangeSet {
        let current = colony.currentlyBuilding
        colony.setBuildQueue(queue)
        if game.specification?.getBoolean(GameOptions.clearHammersOnConstructionSwitch) ?? false,
           let current, current !== colony.currentlyBuilding {
            for ag in current.requiredGoods {
                if let type = ag.type, !type.isStorable { _ = colony.removeGoods(type) }
            }
        }
        colony.invalidateCache()
        return ChangeSet().add(.only(player), colony)
    }

    // MARK: Goods

    private func loadGoods(_ player: Player, _ location: any Location, _ type: GoodsType, _ amount: Int,
                           _ carrier: Unit) throws -> ChangeSet {
        if carrier.loadableAmount(type) < amount { throw CommandRefused("Too much goods") }
        if location is Europe {
            if !carrier.isInEurope { throw CommandRefused("Carrier not in Europe") }
            return try buyGoods(player, type, amount, carrier)
        }
        guard let gl = location as? GoodsLocation else {
            throw CommandRefused("Not a goods location")
        }
        if !carrier.isAtLocation(location) { throw CommandRefused("Carrier not at location") }
        if gl.goodsCount(type) < amount { throw CommandRefused("Not enough goods") }

        let cs = ChangeSet()
        GoodsLocation.moveGoods(gl, type, amount, carrier)
        cs.add(.only(player), gl.goodsContainer)
        cs.add(.only(player), carrier.goodsContainer)
        if carrier.initialMovesLeft != carrier.movesLeft {
            carrier.movesLeft = 0
            cs.addPartial(.only(player), carrier, ("movesLeft", String(carrier.movesLeft)))
        }
        if let dst = gl as? Unit, dst.initialMovesLeft != dst.movesLeft {
            dst.movesLeft = 0
            cs.addPartial(.only(player), dst, ("movesLeft", String(dst.movesLeft)))
        }
        return cs
    }

    private func buyGoods(_ player: Player, _ type: GoodsType, _ amount: Int, _ carrier: Unit) throws -> ChangeSet {
        if !player.canTrade(type, .europe) { throw CommandRefused("Can not trade boycotted goods") }
        let cs = ChangeSet()
        let container = carrier.goodsContainer
        container?.saveState()
        let buyAmount = player.buyInEurope(random, container, type, amount)
        if buyAmount < 0 { throw CommandRefused("Player tried to buy \(amount) \(type.suffix ?? "")") }
        player.propagateToEuropeanMarkets(type, -buyAmount, random)
        player.csFlushMarket(type, cs)
        carrier.movesLeft = 0
        cs.addPartial(.only(player), player, ("gold", String(player.gold)))
        cs.add(.only(player), carrier)
        return cs
    }

    private func unloadGoods(_ player: Player, _ type: GoodsType, _ amount: Int, _ carrier: Unit) throws -> ChangeSet {
        if carrier.goodsCount(type) < amount { throw CommandRefused("Too few goods") }
        if carrier.isInEurope { return try sellGoods(player, type, amount, carrier) }
        let cs = ChangeSet()
        if let settlement = carrier.settlement {
            GoodsLocation.moveGoods(carrier, type, amount, settlement)
            cs.add(.only(player), settlement.goodsContainer)
            cs.add(.only(player), carrier.goodsContainer)
            if carrier.initialMovesLeft != carrier.movesLeft {
                carrier.movesLeft = 0
                cs.addPartial(.only(player), carrier, ("movesLeft", String(carrier.movesLeft)))
            }
        } else {
            // Dumped onto the tile.
            GoodsLocation.moveGoods(carrier, type, amount, nil)
            cs.add(.perhaps(), carrier.location as? FreeColGameObject)
            try sendToOthers(player, cs)
        }
        return cs
    }

    private func sellGoods(_ player: Player, _ type: GoodsType, _ amount: Int, _ carrier: Unit) throws -> ChangeSet {
        let cs = ChangeSet()
        let container = carrier.goodsContainer
        container?.saveState()
        if player.canTrade(type, .europe) {
            if player.sellInEurope(random, container, type, amount) < 0 {
                throw CommandRefused("Player tried to sell \(amount) \(type.suffix ?? "")")
            }
            player.csFlushMarket(type, cs)
            cs.addPartial(.only(player), player, ("gold", String(player.gold)))
        } else {
            // Dumped in Europe.
            GoodsLocation.moveGoods(carrier, type, amount, nil)
        }
        carrier.movesLeft = 0
        cs.add(.only(player), carrier)
        return cs
    }

    private func payArrears(_ player: Player, _ type: GoodsType) throws -> ChangeSet {
        let arrears = player.arrears(type)
        if arrears <= 0 { throw CommandRefused("No arrears for pay for: \(type.id ?? "")") }
        if !player.checkGold(arrears) { throw CommandRefused("Not enough gold to pay arrears for: \(type.id ?? "")") }
        let cs = ChangeSet()
        guard let market = player.market else { return cs }
        _ = player.modifyGold(-arrears)
        market.setArrears(type, 0)
        cs.addPartial(.only(player), player, ("gold", String(player.gold)))
        cs.add(.only(player), market.marketData(type))
        return cs
    }

    // MARK: Europe and treasure

    private func trainUnitInEurope(_ player: Player, _ type: UnitType) throws -> ChangeSet {
        guard let europe = player.europe else { throw CommandRefused("No Europe to train in.") }
        let price = europe.unitPrice(type)
        if price <= 0 { throw CommandRefused("Bogus price: \(price)") }
        if !player.checkGold(price) {
            throw CommandRefused("Not enough gold (\(player.gold) < \(price)) to train \(type.id ?? "")")
        }
        if !type.isAvailableTo([player]) { throw CommandRefused("Unit type is not available for the player.") }
        guard let spec = game.specification else { return ChangeSet() }
        let role = spec.getBoolean(GameOptions.equipEuropeanRecruits) ? type.defaultRole : spec.defaultRole
        let unit = Unit(game: game, location: europe, owner: player, type: type, role: role)
        unit.name = player.nameForUnit(type, random)
        _ = player.modifyGold(-price)
        europe.increasePrice(type, price)
        let cs = ChangeSet()
        cs.addPartial(.only(player), player, ("gold", String(player.gold)))
        cs.add(.only(player), europe)
        return cs
    }

    private func cashInTreasureTrain(_ player: Player, _ unit: Unit) throws -> ChangeSet {
        let cs = ChangeSet()
        let fullAmount = unit.treasureAmount
        let cashInAmount: Int
        var messageId: String
        if player.playerType == .colonial {
            // The transport fee, and the tax.
            cashInAmount = (fullAmount - unit.transportFee) * (100 - player.tax) / 100
            messageId = "cashInTreasureTrain.colonial"
        } else {
            cashInAmount = fullAmount
            messageId = "cashInTreasureTrain.independent"
        }
        _ = player.modifyGold(cashInAmount)
        cs.addPartial(.only(player), player, ("gold", String(player.gold)), ("score", String(player.score)))
        cs.addMessage(player, ModelMessage(.foreignDiplomacy, messageId, player, unit)
            .addAmount("%amount%", fullAmount)
            .addAmount("%cashInAmount%", cashInAmount))
        messageId = (player.isRebel || player.playerType == .independent)
            ? "cashInTreasureTrain.otherIndependent" : "cashInTreasureTrain.otherColonial"
        cs.addGlobalMessage(game, player, ModelMessage(.foreignDiplomacy, messageId, player)
            .addAmount("%amount%", fullAmount)
            .addStringTemplate("%nation%", player.nationLabel))
        // The unit goes, which only the owner sees.
        cs.add(.only(player), unit.location as? FreeColGameObject)
        try unit.csRemove(.only(player), nil, cs)
        try sendToOthers(player, cs)
        return cs
    }
}

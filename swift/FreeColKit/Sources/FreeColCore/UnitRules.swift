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

/// The rules of a unit: what kind of unit it is, its type and owner
/// changes, roles and equipment, experience and teaching, and what
/// moving onto a tile would do (the rest of common/model/Unit).
extension Unit {

    /// What a move would do, or why it can not be made
    /// (Unit.MoveType).  The legal moves have no reason.
    public enum MoveType: JavaEnum, CustomStringConvertible {
        case move, moveHighSeas, exploreLostCityRumour, attackUnit, attackSettlement, embark
        case enterIndianSettlementWithFreeColonist, enterIndianSettlementWithScout
        case enterIndianSettlementWithMissionary, enterForeignColonyWithScout
        case enterSettlementWithCarrierAndGoods
        case moveNoMoves, moveNoAccessLand, moveNoAccessBeached, moveNoAccessEmbark
        case moveNoAccessFull, moveNoAccessGoods, moveNoAccessContact, moveNoAccessMissionBan
        case moveNoAccessSettlement, moveNoAccessSkill, moveNoAccessTrade, moveNoAccessWar
        case moveNoAccessWater, moveNoAttackCivilian, moveNoAttackMarine, moveNoEurope
        case moveNoRepair, moveNoTile, moveIllegal

        public var javaName: String {
            switch self {
            case .move: "MOVE"
            case .moveHighSeas: "MOVE_HIGH_SEAS"
            case .exploreLostCityRumour: "EXPLORE_LOST_CITY_RUMOUR"
            case .attackUnit: "ATTACK_UNIT"
            case .attackSettlement: "ATTACK_SETTLEMENT"
            case .embark: "EMBARK"
            case .enterIndianSettlementWithFreeColonist: "ENTER_INDIAN_SETTLEMENT_WITH_FREE_COLONIST"
            case .enterIndianSettlementWithScout: "ENTER_INDIAN_SETTLEMENT_WITH_SCOUT"
            case .enterIndianSettlementWithMissionary: "ENTER_INDIAN_SETTLEMENT_WITH_MISSIONARY"
            case .enterForeignColonyWithScout: "ENTER_FOREIGN_COLONY_WITH_SCOUT"
            case .enterSettlementWithCarrierAndGoods: "ENTER_SETTLEMENT_WITH_CARRIER_AND_GOODS"
            case .moveNoMoves: "MOVE_NO_MOVES"
            case .moveNoAccessLand: "MOVE_NO_ACCESS_LAND"
            case .moveNoAccessBeached: "MOVE_NO_ACCESS_BEACHED"
            case .moveNoAccessEmbark: "MOVE_NO_ACCESS_EMBARK"
            case .moveNoAccessFull: "MOVE_NO_ACCESS_FULL"
            case .moveNoAccessGoods: "MOVE_NO_ACCESS_GOODS"
            case .moveNoAccessContact: "MOVE_NO_ACCESS_CONTACT"
            case .moveNoAccessMissionBan: "MOVE_NO_ACCESS_MISSION_BAN"
            case .moveNoAccessSettlement: "MOVE_NO_ACCESS_SETTLEMENT"
            case .moveNoAccessSkill: "MOVE_NO_ACCESS_SKILL"
            case .moveNoAccessTrade: "MOVE_NO_ACCESS_TRADE"
            case .moveNoAccessWar: "MOVE_NO_ACCESS_WAR"
            case .moveNoAccessWater: "MOVE_NO_ACCESS_WATER"
            case .moveNoAttackCivilian: "MOVE_NO_ATTACK_CIVILIAN"
            case .moveNoAttackMarine: "MOVE_NO_ATTACK_MARINE"
            case .moveNoEurope: "MOVE_NO_EUROPE"
            case .moveNoRepair: "MOVE_NO_REPAIR"
            case .moveNoTile: "MOVE_NO_TILE"
            case .moveIllegal: "MOVE_ILLEGAL"
            }
        }

        /// Why the move is illegal, or nil for a legal move.
        public var reason: String? {
            switch self {
            case .move, .moveHighSeas, .exploreLostCityRumour, .attackUnit, .attackSettlement,
                 .embark, .enterIndianSettlementWithFreeColonist, .enterIndianSettlementWithScout,
                 .enterIndianSettlementWithMissionary, .enterForeignColonyWithScout,
                 .enterSettlementWithCarrierAndGoods:
                nil
            case .moveNoMoves: "Attempt to move without moves left"
            case .moveNoAccessLand: "Attempt to move a naval unit onto land"
            case .moveNoAccessBeached: "Attempt to move onto foreign beached ship"
            case .moveNoAccessEmbark: "Attempt to embark onto absent or foreign carrier"
            case .moveNoAccessFull: "Attempt to embark onto full carrier"
            case .moveNoAccessGoods: "Attempt to trade without goods"
            case .moveNoAccessContact: "Attempt to interact with natives before contact"
            case .moveNoAccessMissionBan: "Attempt to use missionary at banned settlement"
            case .moveNoAccessSettlement: "Attempt to move into foreign settlement"
            case .moveNoAccessSkill: "Attempt to learn skill with incapable unit"
            case .moveNoAccessTrade: "Attempt to trade without authority"
            case .moveNoAccessWar: "Attempt to trade while at war"
            case .moveNoAccessWater: "Attempt to move into a settlement by water"
            case .moveNoAttackCivilian: "Attempt to attack with civilian unit"
            case .moveNoAttackMarine: "Attempt to attack from on board ship"
            case .moveNoEurope: "Attempt to move to Europe by incapable unit"
            case .moveNoRepair: "Attempt to move a unit that is under repair"
            case .moveNoTile: "Attempt to move when not on a tile"
            case .moveIllegal: "Unspecified illegal move"
            }
        }

        public var isLegal: Bool { reason == nil }

        public var whyIllegal: String { reason ?? "(none)" }

        /// Whether the move gets the unit somewhere.
        public var isProgress: Bool {
            self == .move || self == .moveHighSeas || self == .exploreLostCityRumour
        }

        public var isAttack: Bool {
            self == .attackUnit || self == .attackSettlement
        }

        public var description: String {
            javaName
        }
    }

    // MARK: Kinds

    public var scoreValue: Int {
        type?.scoreValue ?? 0
    }

    public var canCarryTreasure: Bool {
        hasAbility(Ability.carryTreasure)
    }

    public var canCaptureGoods: Bool {
        hasAbility(Ability.captureGoods)
    }

    /// Whether this is a European unit that can carry goods to trade.
    public var isTradingUnit: Bool {
        canCarryGoods && (owner?.isEuropean ?? false)
    }

    /// Whether this unit could found colonies for its owner.
    public var isColonist: Bool {
        (type?.hasAbility(Ability.foundColony) ?? false) && (owner?.hasAbility(Ability.foundsColonies) ?? false)
    }

    public var isAtSea: Bool {
        if let carrier { return carrier.isAtSea }
        return location is HighSeas
    }

    public var isInMission: Bool {
        hasAbility(Ability.establishMission) && location is IndianSettlement
    }

    public var hasNativeEthnicity: Bool {
        specification?.getNation(ethnicity)?.type?.isIndian ?? false
    }

    public var isArmed: Bool { hasAbility(Ability.armed) }
    public var isMounted: Bool { hasAbility(Ability.mounted) }

    public var isBeached: Bool {
        isBeached(tile)
    }

    /// Whether a ship is on land other than a settlement (left behind
    /// when a colony was abandoned).
    public func isBeached(_ tile: Tile?) -> Bool {
        guard let tile else { return false }
        return tile.isLand && !tile.hasSettlement && isNaval
    }

    public var turnsForRepair: Int {
        maximumHitPoints - hitPoints
    }

    // MARK: Type and owner

    /// Change to a type the owner may have, keeping the share of hit
    /// points and dropping teaching that no longer applies.
    @discardableResult
    public func changeType(_ unitType: UnitType) -> Bool {
        guard unitType.isAvailableTo([owner]) else { return false }
        let health = Double(hitPoints) / Double(maximumHitPoints)
        type = unitType
        if movesLeft > initialMovesLeft { setMovesLeft(initialMovesLeft) }
        hitPoints = Int(JavaMath.toInt(Double(unitType.hitPoints) * health))
        if let teacher {
            if !canBeStudent(teacher) {
                teacher.setStudent(nil)
                setTeacher(nil)
            }
        } else if let student, !student.canBeStudent(self) {
            student.setTeacher(nil)
            setStudent(nil)
        }
        return true
    }

    /// Change owner, with the units on board, dropping teaching, orders
    /// and home settlement.  Java tells the AI first; that comes in
    /// Phase 4.
    public func changeOwner(_ newOwner: Player) {
        let oldOwner = owner
        if oldOwner === newOwner { return }
        owner = newOwner
        for u in unitList { u.changeOwner(newOwner) }
        if let teacher, !canBeStudent(teacher) {
            teacher.setStudent(nil)
            setTeacher(nil)
        }
        destination = nil
        changeHomeIndianSettlement(nil)
        oldOwner?.removeUnit(self)
        newOwner.addUnit(self)
    }

    // MARK: Roles and equipment

    public func setRole(_ role: Role?) {
        self.role = role
    }

    /// Change role, losing experience for an incompatible one.
    public func changeRole(_ role: Role, _ roleCount: Int) {
        if !role.isCompatible(with: self.role) { setExperience(0) }
        setRole(role)
        self.roleCount = role.isDefaultRole ? 0 : roleCount
    }

    /// Change the role count, reverting to the default role at zero.
    ///
    /// - Returns: Whether the unit reverted to the default role.
    @discardableResult
    public func changeRoleCount(_ delta: Int) -> Bool {
        roleCount = max(0, roleCount + delta)
        if roleCount != 0 { return false }
        role = specification?.defaultRole
        return true
    }

    /// The available military roles, strongest attack first, without
    /// scouts.
    public var sortedMilitaryRoles: [Role] {
        (specification?.militaryRolesList ?? [])
            .filter { roleIsAvailable($0) && !$0.hasAbility(Ability.speakWithChief) }
            .stableSorted { $0.offence > $1.offence }
    }

    public var militaryRole: Role? {
        sortedMilitaryRoles.first
    }

    /// The role a unit in a settlement takes up automatically when
    /// attacked, if the settlement has the goods.
    public var automaticRole: Role? {
        guard hasDefaultRole, let spec = specification else { return nil }
        let settlement: Settlement? = isInColony ? colony : location as? IndianSettlement
        guard let settlement else { return nil }
        for ability in abilities(Ability.automaticEquipment) {
            for scope in ability.scopes {
                if let r = spec.getRole(scope.type), settlement.containsGoods(goodsDifference(r, 1)) {
                    return r
                }
            }
        }
        return nil
    }

    /// The military role this unit would take capturing another's
    /// equipment, or nil.
    public func canCaptureEquipment(_ role: Role) -> Role? {
        guard hasAbility(Ability.captureEquipment), let spec = specification else { return nil }
        let oldRole = self.role
        return availableRoles(spec.militaryRolesList).first { r in
            r.roleChanges.contains { $0.from(spec) === oldRole && $0.capture(spec) === role }
        }
    }

    public var losingEquipmentKillsUnit: Bool {
        hasAbility(Ability.disposeOnAllEquipmentLost) && role?.downgrade == nil
    }

    public var losingEquipmentDemotesUnit: Bool {
        hasAbility(Ability.demoteOnAllEquipmentLost) && role?.downgrade == nil
    }

    // MARK: Moves

    public func setMovesLeft(_ moves: Int) {
        movesLeft = max(0, moves)
    }

    /// Spend the moves left, in a colony.
    func spendAllMoves() {
        if colony != nil && movesLeft < initialMovesLeft { setMovesLeft(0) }
    }

    /// The moves a unit starts each turn with.
    public var initialMovesLeft: Int {
        guard let type else { return 0 }
        // A path search asks this for every move it tries, and nothing
        // it depends on changes during a search.
        if let cached = SearchCache.current?.initialMoves[ObjectIdentifier(self)] { return cached }
        let moves = Int(JavaMath.toInt(apply(Float(type.movement), turn: game?.turn, Modifier.movementBonus, for: type)))
        SearchCache.current?.initialMoves[ObjectIdentifier(self)] = moves
        return moves
    }

    /// The moves as "1(2/3) /1".
    public var movesAsString: String {
        let quotient = movesLeft / 3, remainder = movesLeft % 3
        var s = ""
        if quotient > 0 || remainder == 0 { s += String(quotient) }
        if remainder > 0 { s += "(\(remainder)/3) " }
        return s + "/\(initialMovesLeft / 3)"
    }

    /// The turns to sail between Europe and the map.
    public var sailTurns: Int {
        let base = Float(specification?.getInteger(GameOptions.turnsToSail) ?? 0)
        return Int(JavaMath.toInt(owner?.apply(base, turn: game?.turn, Modifier.sailHighSeas, for: type) ?? base))
    }

    /// The cost of moving onto a tile with the moves left.
    public func moveCost(_ target: Tile) -> Int {
        moveCost(tile, target, movesLeft)
    }

    /// The cost of moving onto a tile: its type's, lowered by roads and
    /// rivers for land units.  A move that costs more than is left takes
    /// all that is left when nearly a full turn's moves remain, it is
    /// close, or it enters a settlement.
    public func moveCost(_ from: Tile?, _ target: Tile, _ ml: Int) -> Int {
        var cost = target.type?.basicMoveCost ?? 0
        if target.isLand && !isNaval, let container = target.tileItemContainer, let from {
            cost = container.moveCost(from: from, to: target, cost)
        }
        if isBeached(from) {
            // A ship on land after its colony was abandoned.
            cost = ml
        } else if cost > ml {
            // 1/3 and 2/3 of a move count as a whole one.
            if (ml + 2 >= initialMovesLeft || cost <= ml + 2 || target.hasSettlement) && ml != 0 {
                cost = ml
            }
        }
        return cost
    }

    public func moveType(_ direction: Direction) -> MoveType {
        guard let tile else { return .moveNoTile }
        guard let target = tile.neighbour(direction) else { return .moveIllegal }
        return moveType(target)
    }

    public func moveType(_ target: Tile?) -> MoveType {
        guard let tile else { return .moveNoTile }
        return moveType(tile, target, movesLeft)
    }

    /// What moving from one tile to another would do with some moves
    /// left.  Attacks need only one move.
    public func moveType(_ from: Tile?, _ target: Tile?, _ ml: Int) -> MoveType {
        var move = simpleMoveType(from, target)
        if move.isLegal {
            if move.isAttack {
                if ml <= 0 { move = .moveNoMoves }
            } else if ml <= 0 || (from != nil && target != nil && moveCost(from, target!, ml) > ml) {
                move = .moveNoMoves
            }
        }
        return move
    }

    /// What a move would do, regardless of moves left.
    public func simpleMoveType(_ from: Tile?, _ target: Tile?) -> MoveType {
        isNaval ? navalMoveType(from, target) : landMoveType(from, target)
    }

    public func simpleMoveType(_ target: Tile?) -> MoveType {
        guard let tile else { return .moveNoTile }
        return simpleMoveType(tile, target)
    }

    public func simpleMoveType(_ direction: Direction) -> MoveType {
        guard let tile else { return .moveNoTile }
        guard let target = tile.neighbour(direction) else { return .moveIllegal }
        return simpleMoveType(tile, target)
    }

    private func navalMoveType(_ from: Tile?, _ target: Tile?) -> MoveType {
        guard let target else { return (owner?.canMoveToEurope ?? false) ? .moveHighSeas : .moveNoEurope }
        if isDamagedAndUnderForcedRepair { return .moveNoRepair }
        if target.isLand {
            guard let settlement = target.settlement else { return .moveNoAccessLand }
            if settlement.owner === owner { return .move }
            return isTradingUnit ? tradeMoveType(settlement) : .moveNoAccessSettlement
        }
        // At sea
        if let defender = target.firstUnit, !(owner?.owns(defender) ?? false) {
            return isOffensiveUnit ? .attackUnit : .moveNoAttackCivilian
        }
        return target.isDirectlyHighSeasConnected ? .moveHighSeas : .move
    }

    private func landMoveType(_ from: Tile?, _ target: Tile?) -> MoveType {
        guard let target else { return .moveIllegal }
        let defender = target.firstUnit
        guard target.isLand else {
            // Moving to sea: boarding a carrier.
            guard let defender, owner?.owns(defender) ?? false else { return .moveNoAccessEmbark }
            return target.unitList.contains { $0.canAdd(self) } ? .embark : .moveNoAccessFull
        }
        guard let settlement = target.settlement else {
            if let defender, owner !== defender.owner {
                if defender.isNaval { return .attackUnit }
                if !isOffensiveUnit { return .moveNoAttackCivilian }
                return allowMove(from: from) ? .attackUnit : .moveNoAttackMarine
            }
            // Natives do not explore rumours.
            if target.hasLostCityRumour && (owner?.isEuropean ?? false) { return .exploreLostCityRumour }
            return .move
        }
        if owner === settlement.owner { return .move }
        if isTradingUnit { return tradeMoveType(settlement) }
        if isColonist {
            if settlement is Colony && hasAbility(Ability.negotiate) {
                return allowMove(from: from) ? .enterForeignColonyWithScout : .moveNoAccessWater
            }
            if let isettlement = settlement as? IndianSettlement, hasAbility(Ability.speakWithChief) {
                if !(from?.isLand ?? false) && isettlement.contactLevel(owner) == .uncontacted {
                    return .moveNoAccessContact
                }
                return allowMove(from: from) ? .enterIndianSettlementWithScout : .moveNoAccessWater
            }
            if isOffensiveUnit { return allowMove(from: from) ? .attackSettlement : .moveNoAttackMarine }
            if hasAbility(Ability.establishMission) { return missionaryMoveType(from, settlement) }
            return learnMoveType(from, settlement)
        }
        if isOffensiveUnit { return allowMove(from: from) ? .attackSettlement : .moveNoAttackMarine }
        return .moveNoAccessSettlement
    }

    private func tradeMoveType(_ settlement: Settlement) -> MoveType {
        if settlement is Colony {
            if owner?.atWar(with: settlement.owner) ?? false { return .moveNoAccessWar }
            return hasAbility(Ability.tradeWithForeignColonies) ? .enterSettlementWithCarrierAndGoods
                : .moveNoAccessTrade
        }
        if let isettlement = settlement as? IndianSettlement {
            // Contact is needed, and settlement contact for ships; war
            // does not block, as gifts are allowed.
            if !allowContact(settlement) || (isNaval && isettlement.contactLevel(owner) == .uncontacted) {
                return .moveNoAccessContact
            }
            return hasGoodsCargo || (specification?.getBoolean(GameOptions.emptyTraders) ?? false)
                ? .enterSettlementWithCarrierAndGoods : .moveNoAccessGoods
        }
        return .moveIllegal
    }

    private func learnMoveType(_ from: Tile?, _ settlement: Settlement) -> MoveType {
        if settlement is Colony { return .moveNoAccessSettlement }
        guard settlement is IndianSettlement else { return .moveIllegal }
        if !allowContact(settlement) { return .moveNoAccessContact }
        if !allowMove(from: from) { return .moveNoAccessWater }
        return unitChange(UnitChangeType.natives) == nil ? .moveNoAccessSkill
            : .enterIndianSettlementWithFreeColonist
    }

    private func missionaryMoveType(_ from: Tile?, _ settlement: Settlement) -> MoveType {
        if settlement is Colony { return .moveNoAccessSettlement }
        guard settlement is IndianSettlement else { return .moveIllegal }
        if !allowContact(settlement) { return .moveNoAccessContact }
        if !allowMove(from: from) { return .moveNoAccessWater }
        if let owner, settlement.owner?.missionsBanned(owner) ?? false { return .moveNoAccessMissionBan }
        return .enterIndianSettlementWithMissionary
    }

    /// Moves from water onto land are amphibious, which the rules may
    /// allow (but not for the REF).
    private func allowMove(from: Tile?) -> Bool {
        (from?.isLand ?? false)
            || (!(owner?.isREF ?? false) && (specification?.getBoolean(GameOptions.amphibiousMoves) ?? false))
    }

    private func allowContact(_ settlement: Settlement) -> Bool {
        owner?.hasContacted(settlement.owner) ?? false
    }

    /// Whether the unit could sail to the high seas: at sea already, in
    /// Europe, or next to (or on) high seas it could move to.
    public var canMoveToHighSeas: Bool {
        if isAtSea { return true }
        guard let type else { return false }
        if isInEurope { return type.canMoveToHighSeas }
        guard let tile else { return false }
        return type.canMoveToHighSeas && (owner?.canMoveToEurope ?? false)
            && (tile.isDirectlyHighSeasConnected
                || tile.surroundingTiles(1, 1).contains {
                    $0.isDirectlyHighSeasConnected && moveType($0) == .moveHighSeas
                })
    }

    public var canBuildColony: Bool {
        guard hasTile, type?.canBuildColony ?? false, movesLeft > 0 else { return false }
        return !(owner?.isRebel ?? false)
            || (specification?.getBoolean(GameOptions.foundColonyDuringRebellion) ?? false)
    }

    /// Whether the unit is at a location (or with a unit there).
    public func isAtLocation(_ loc: (any Location)?) -> Bool {
        var ourLoc = location
        let otherLoc = (loc as? Unit)?.location ?? loc
        if let carrier = ourLoc as? Unit { ourLoc = carrier.location }
        return Map.isSameLocation(ourLoc, otherLoc)
    }

    /// Whether the unit is free to act: not under repair, at sea, on a
    /// carrier or at work, active, with moves.
    private var readyAndAble: Bool {
        !isDisposed && !isDamagedAndUnderForcedRepair && !isAtSea && !isOnCarrier && !isInColony
            && state == .active && movesLeft > 0
    }

    /// Whether the unit could take orders.
    public var couldMove: Bool {
        readyAndAble && destination == nil && tradeRoute == nil
    }

    /// Whether the unit can go on to its destination.
    public var goingToDestination: Bool {
        readyAndAble && tradeRoute == nil && destination != nil
    }

    /// Whether the unit can follow its trade route.
    public var followingTradeRoute: Bool {
        readyAndAble && tradeRoute != nil
    }

    // MARK: Trade routes

    /// The current stop, made valid first (Java's validateCurrentStop):
    /// -1 without a route or stops, otherwise wrapped back to the first.
    private func validateCurrentStop() -> Int {
        if let tradeRoute {
            let stopCount = tradeRoute.stopCount
            if stopCount <= 0 {
                currentStop = -1
            } else if currentStop < 0 || currentStop >= stopCount {
                // The current stop can be out of range if the route was
                // changed.
                currentStop = 0
            }
        } else {
            currentStop = -1
        }
        return currentStop
    }

    /// The stop the unit is going to.
    public var stop: TradeRouteStop? {
        validateCurrentStop() < 0 ? nil : tradeRoute?.stop(currentStop)
    }

    /// The route's stops, starting from the current one.
    public var currentStops: [TradeRouteStop]? {
        guard validateCurrentStop() >= 0, let stops = tradeRoute?.stopList else { return nil }
        return Array(stops[currentStop...] + stops[..<currentStop])
    }

    public func atStop(_ stop: TradeRouteStop) -> Bool {
        Map.isSameLocation(location, stop.location)
    }

    /// Where the unit could trade: its colony or native settlement, or
    /// Europe.
    public var tradeLocation: TradeLocation? {
        if let colony { return colony }
        if let settlement = indianSettlement { return settlement }
        return isInEurope ? owner?.europe : nil
    }

    // MARK: Value

    /// A unit's value for trade: its price in Europe, or 500.
    public func evaluateFor(_ player: Player) -> Int {
        guard let europe = player.europe, let type else { return Unit.defaultUnitValue }
        let price = europe.unitPrice(type)
        return price == Constants.undefined ? Unit.defaultUnitValue : price
    }

    public var isCandidateForNextActiveUnit: Bool {
        couldMove && !isInEurope
    }

    // MARK: Combat queries

    /// Whether the unit could attack another: an offensive unit, at sea
    /// against ships not in a settlement, on land against land units or
    /// beached ships.
    public func canAttack(_ defender: Unit?) -> Bool {
        guard let defender, let tile = defender.tile, isOffensiveUnit else { return false }
        return isNaval ? !tile.hasSettlement && defender.isNaval : !defender.isNaval || defender.isBeached
    }

    /// Whether an ambush applies: both on open tiles, the defender not
    /// fortified, an ambusher (or a vulnerable defender), and ambush
    /// terrain on either tile.
    public func canAmbush(_ defender: Unit) -> Bool {
        isOnTile && settlement == nil && defender.isOnTile && defender.settlement == nil
            && defender.state != .fortified
            && (hasAbility(Ability.ambushBonus) || defender.hasAbility(Ability.ambushPenalty))
            && ((tile?.hasAbility(Ability.ambushTerrain) ?? false)
                || (defender.tile?.hasAbility(Ability.ambushTerrain) ?? false))
    }

    /// Whether another unit is a better defender: armed people before
    /// unarmed, defensive units before others, then by power.
    public static func betterDefender(_ defender: Unit?, _ defenderPower: Double,
                                      _ other: Unit, _ otherPower: Double) -> Bool {
        guard let defender else { return true }
        if defender.isPerson && other.isPerson && !defender.isArmed && other.isArmed { return true }
        if defender.isPerson && other.isPerson && defender.isArmed && !other.isArmed { return false }
        if !defender.isDefensiveUnit && other.isDefensiveUnit { return true }
        if defender.isDefensiveUnit && !other.isDefensiveUnit { return false }
        return defenderPower < otherPower
    }

    /// Send a damaged ship for repair.
    public func damageShip(_ repair: (any Location)?) {
        hitPoints = 1
        destination = nil
        setLocation(repair)
        setState(.active)
        setMovesLeft(0)
    }

    /// How far the unit sees: its type's sight, with the type's bonuses
    /// and those of the tile it is on.
    public var lineOfSight: Int {
        guard let type else { return 0 }
        let turn = game?.turn
        var mods = modifiers(Modifier.lineOfSightBonus, for: type, turn: turn)
        if let tile, tile.isExplored, let tileType = tile.type {
            mods += tileType.modifiers(Modifier.lineOfSightBonus, for: type, turn: turn)
        }
        return Int(JavaMath.toInt(FeatureContainer.applyModifiers(Float(type.lineOfSight), turn: turn, mods)))
    }

    public var visibleTileSet: Set<Tile> {
        guard let tile else { return [] }
        return Set(tile.surroundingTiles(0, lineOfSight))
    }

    // MARK: Experience, work and teaching

    public func changeExperienceType(_ type: GoodsType?) {
        if experienceType !== type {
            experience = 0
            experienceType = type
        }
    }

    /// Set the experience, up to the type's maximum.
    public func setExperience(_ experience: Int) {
        self.experience = min(experience, type?.maximumExperience ?? 0)
    }

    public func modifyExperience(_ value: Int) {
        experience += value
    }

    /// The turns of work left; expert pioneers work twice as fast.
    public var workTurnsLeft: Int {
        state == .improving && (type?.hasAbility(Ability.expertPioneer) ?? false)
            ? (workLeft + 1) / 2 : workLeft
    }

    /// Set the student, and the student's teacher.  The student must
    /// be in the same colony and able to learn from this unit.
    public func setStudent(_ newStudent: Unit?) {
        let oldStudent = student
        if oldStudent === newStudent { return }
        guard let newStudent else {
            student = nil
            if let oldStudent, oldStudent.teacher === self { oldStudent.setTeacher(nil) }
            return
        }
        precondition(newStudent.colony != nil && newStudent.colony === colony && newStudent.canBeStudent(self),
                     "Unit can not be student: \(newStudent)")
        if let oldStudent, oldStudent.teacher === self { oldStudent.setTeacher(nil) }
        student = newStudent
        newStudent.setTeacher(self)
    }

    /// Set the teacher, and the teacher's student.  The teacher must be
    /// in the same colony, which must be able to train its skill.
    public func setTeacher(_ newTeacher: Unit?) {
        let oldTeacher = teacher
        if newTeacher === oldTeacher { return }
        guard let newTeacher else {
            teacher = nil
            if let oldTeacher, oldTeacher.student === self { oldTeacher.setStudent(nil) }
            return
        }
        let skillTaught = newTeacher.type?.skillTaught
        precondition(newTeacher.colony != nil && newTeacher.colony === colony
                     && (colony?.canTrain(skillTaught) ?? false),
                     "Unit can not be teacher: \(newTeacher)")
        if let oldTeacher, oldTeacher.student === self { oldTeacher.setStudent(nil) }
        teacher = newTeacher
        newTeacher.setStudent(self)
    }

    /// The turns this teacher needs to teach its student, less the
    /// colony's production bonus.
    public var neededTurnsOfTraining: Int {
        guard let student, let spec = specification, let type, let studentType = student.type else { return 0 }
        var result = spec.neededTurnsOfTraining(type, studentType) ?? 0
        if let colony { result -= colony.productionBonus }
        return result
    }

    /// A change of type this unit could make, to its owner (or another
    /// player, for changes that change owner).
    public func unitChange(_ change: String, _ toType: UnitType? = nil, _ player: Player? = nil) -> UnitTypeChange? {
        guard let spec = specification, let player = player ?? owner else { return nil }
        let uct = spec.getUnitChangeType(change)
        if let uct {
            precondition(uct.ownerChange == (player !== owner),
                         "getUnitChange of \(self) change=\(change) owner change mismatch")
        }
        guard let uct, uct.appliesTo(self), let uc = uct.unitChange(type, toType) else { return nil }
        return uc.isAvailableTo(player) && uc.appliesTo(self) ? uc : nil
    }

    /// Swap work with a unit doing this unit's expert job badly.
    ///
    /// - Returns: The unit swapped with, or nil.
    @discardableResult
    public func trySwapExpert(_ others: [Unit]) -> Unit? {
        guard let work = type?.expertProduction,
              let other = others.first(where: { $0.nonExpertWorker(work) }) else { return nil }
        swapWork(other)
        return other
    }

    private func nonExpertWorker(_ work: GoodsType) -> Bool {
        isPerson && workType === work && type?.expertProduction !== work
    }

    /// Swap work locations, work and roles with another unit in the
    /// colony, taking up this unit's expert work.
    public func swapWork(_ other: Unit) {
        guard let colony else { return }
        let oldRole = role, oldRoleCount = roleCount
        let work = type?.expertProduction
        let oldWork = workType
        let l1 = location, l2 = other.location
        other.setLocation(colony.tile)
        setLocation(l2)
        changeWorkType(work)
        other.setLocation(l1)
        if let oldWork { other.changeWorkType(oldWork) }
        let tmpRole = other.role, tmpRoleCount = other.roleCount
        if let oldRole { other.changeRole(oldRole, oldRoleCount) }
        if let tmpRole { changeRole(tmpRole, tmpRoleCount) }
    }

    // MARK: Treasure, missions and scoring

    /// The chance a native converts at a mission.
    public var convertProbability: Float {
        let opt = Float(specification?.getInteger(GameOptions.nativeConvertProbability) ?? 0)
        return 0.01 * apply(opt, turn: game?.turn, Modifier.nativeConvertBonus)
    }

    public var burnProbability: Float {
        0.01 * Float(specification?.getInteger(GameOptions.burnProbability) ?? 0)
    }

    /// Whether a treasure could be cashed in at a location: any colony
    /// after independence, a port colony when there is no free ship
    /// home, or Europe.
    public func canCashInTreasureTrain(_ loc: (any Location)?) -> Bool {
        precondition(canCarryTreasure, "Can't carry treasure: \(self)")
        guard let loc, let owner else { return false }
        if owner.europe == nil { return loc.colony != nil }
        if let colony = loc.colony {
            return colony.isConnectedPort && (owner.carriers(for: self).isEmpty || transportFee == 0)
        }
        return loc is Europe || ((loc as? Unit)?.isInEurope ?? false)
    }

    public var canCashInTreasureTrain: Bool {
        canCashInTreasureTrain(location)
    }

    /// The fee to ship a treasure to Europe.
    public var transportFee: Int {
        guard !isInEurope, let owner, owner.europe != nil else { return 0 }
        let fee = Float((specification?.getInteger(GameOptions.treasureTransportFee) ?? 0) * treasureAmount) / 100
        return Int(JavaMath.toInt(owner.apply(fee, turn: game?.turn, Modifier.treasureTransportFee, for: type)))
    }

    /// The missionary's trade modifiers, reversed for the other side.
    public func missionaryTradeModifiers(_ sense: Bool) -> [Modifier] {
        modifiers(Modifier.missionaryTradeBonus).filter { $0.value != 0 }.map { m in
            let mod = Modifier(copying: m)
            if !sense { mod.value = -m.value }
            return mod
        }
    }

    /// How good a pioneer the unit would make, for the AI.
    public var pioneerScore: Int {
        let ht = hasTile ? 100 : 0
        if location == nil || !isColonist { return -1000 }
        if hasAbility(Ability.improveTerrain) { return 900 + ht }
        if hasAbility(Ability.expertPioneer) { return 700 }
        if !hasDefaultRole { return 0 }
        if skillLevel > 0 { return 0 }
        return 200 + skillLevel * 50
    }

    /// How good a scout the unit would make, for the AI.
    public var scoutScore: Int {
        let ht = hasTile ? 100 : 0
        if location == nil || !isColonist { return -1000 }
        if hasAbility(Ability.speakWithChief) { return 900 + ht }
        if hasAbility(Ability.expertScout) { return 700 }
        if !hasDefaultRole { return 0 }
        if skillLevel <= 0 { return -200 * skillLevel }
        return 0
    }

    /// The unit with an id on board, or nil.
    public func carriedUnit(byId id: String?) -> Unit? {
        guard let id else { return nil }
        return unitList.first { $0.id == id }
    }

    /// Set the state of the units on board.
    public func setStateToAllChildren(_ state: UnitState) {
        if canCarryUnits {
            for u in unitList { u.setState(state) }
        }
    }

    /// Set where the unit arrives from Europe, which the owner then uses
    /// by default.
    public func setEntryLocation(_ entryLocation: (any Location)?) {
        self.entryLocation = entryLocation
        if let tile = entryLocation?.tile { owner?.entryTile = tile }
    }

    /// Where the unit arrives from Europe: its own entry location, or
    /// its owner's.
    public var fullEntryLocation: Tile? {
        entryLocation?.tile ?? owner?.entryTile
    }
}

extension Map {

    /// Whether two locations are both present and either the same or
    /// on the same tile.
    public static func isSameLocation(_ l1: (any Location)?, _ l2: (any Location)?) -> Bool {
        guard let l1, let l2 else { return false }
        if l1 === l2 { return true }
        guard let t1 = l1.tile else { return false }
        return t1 === l2.tile
    }
}

extension UnitTypeChange {
    /// Whether a player may have the type changed to.
    public func isAvailableTo(_ player: Player?) -> Bool {
        to?.isAvailableTo([player]) ?? false
    }
}

extension Unit {
    /// The settlement with an identifier, if it is beside this unit,
    /// another's and of a player the owner has met (getAdjacentSettlement).
    ///
    /// - Returns: The settlement, or why not as Java's exception says.
    public func adjacentSettlement<T: Settlement>(_ id: String?, _ type: T.Type) -> Result<T, AdjacentSettlementError> {
        guard let s = game?.getFreeColGameObject(id) as? T else { return .failure(.init("Not a settlement: \(id ?? "null")")) }
        guard let st = s.tile else { return .failure(.init("Settlement is not on the map: \(id ?? "null")")) }
        guard owner?.hasContacted(s.owner) ?? false else {
            return .failure(.init("Player \(owner?.id ?? "null") has not contacted: \(s.owner?.id ?? "null")"))
        }
        guard let tile else { return .failure(.init("Unit is not on the map: \(self.id ?? "null")")) }
        if tile.distance(to: st) > 1 {
            return .failure(.init("Unit \(self.id ?? "null") is not adjacent to settlement: \(id ?? "null")"))
        }
        if owner === s.owner { return .failure(.init("Unit and settlement are both owned by the player")) }
        return .success(s)
    }

    public struct AdjacentSettlementError: Error, CustomStringConvertible {
        public let description: String
        init(_ description: String) { self.description = description }
    }
}


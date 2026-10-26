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
import FreeColXML

/// A unit: a colonist, soldier, ship, wagon train, brave or treasure
/// (common/model/Unit, 5k lines in Java).
///
/// The movement rules, roles, work and teaching are in UnitRules.swift.
///
/// Paths, searches and the combat parts are in UnitPaths.swift.
///
/// The labels are in Labels.swift.  Not yet ported: copyIn and the
/// integrity check.
///
/// The location holding a unit holds it; the unit's references to its
/// location, owner, destination, entry location, teacher, student and
/// home settlement are weak.
public final class Unit: GoodsLocation, GameObjectReadable, Locatable, Ownable, Consumer {

    public static let tag = "unit"

    /// The trade value of a unit without a price.
    public static let defaultUnitValue = 500

    /// What a unit is doing (Unit.UnitState).
    public enum UnitState: JavaEnum, CustomStringConvertible {
        case active, fortified, sentry, inColony, improving, fortifying, skipped

        public var javaName: String {
            switch self {
            case .active: "ACTIVE"
            case .fortified: "FORTIFIED"
            case .sentry: "SENTRY"
            case .inColony: "IN_COLONY"
            case .improving: "IMPROVING"
            case .fortifying: "FORTIFYING"
            case .skipped: "SKIPPED"
            }
        }

        public var description: String {
            javaName
        }
    }

    public var name: String?
    public weak var owner: Player?
    public internal(set) var type: UnitType?
    /// What the unit is doing.  Set it with setState, which checks the
    /// change and does what it entails.
    public private(set) var state: UnitState = .active
    public internal(set) var role: Role?
    public var roleCount = 0
    public private(set) weak var location: (any Location)?
    public weak var entryLocation: (any Location)?
    public weak var destination: (any Location)?
    public var movesLeft = 0
    public var workLeft = 0
    public var attrition = 0
    public private(set) var nationality: String?
    public private(set) var ethnicity: String?
    public var turnsOfTraining = 0
    public var hitPoints = 0
    /// Set with setTeacher and setStudent, which keep both sides right.
    public weak var teacher: Unit?
    public weak var student: Unit?
    public weak var homeIndianSettlement: IndianSettlement?
    public var treasureAmount = 0
    /// The trade route followed, held by its owner.
    public weak var tradeRoute: TradeRoute?
    /// The trade route's stop, or -1.
    public var currentStop = -1
    public var experienceType: GoodsType?
    public var experience = 0
    /// The goods count others see, or -1 for the real count.
    public private(set) var visibleGoodsCount = -1
    public var workType: GoodsType?
    /// The improvement a pioneer is making.
    public var workImprovement: TileImprovement?

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// Create a unit (the model side of Java's ServerUnit constructor):
    /// apply any creation change to its type, give persons their
    /// owner's nationality, equip it for its role, put it in its
    /// location and give it to its owner.
    ///
    /// - Parameters:
    ///   - game: The game, which issues the identifier.
    ///   - location: Where to put the unit.
    ///   - owner: The owner.
    ///   - type: The unit type, before any creation change.
    ///   - role: The role, by default the type's default role.
    public init(game: Game, location: (any Location)?, owner: Player, type: UnitType,
                role: Role? = nil) {
        super.init(game: game)
        self.owner = owner
        self.type = type
        state = .active // placeholder
        self.role = specification?.defaultRole // placeholder
        workLeft = -1
        movesLeft = initialMovesLeft
        currentStop = -1

        // Check for a creation change
        if let uc = unitChange(UnitChangeType.creation) { self.type = uc.to }
        if self.type!.hasAbility(Ability.person) {
            nationality = owner.nationId
            ethnicity = nationality
        }
        hitPoints = self.type!.hitPoints

        // Fix up the role, state and location now the rest is there.
        if let role = role ?? type.defaultRole { changeRole(role, role.maximumCount) }
        setStateUnchecked(state)
        setLocation(location)
        if self.type!.canCarryGoods { setGoodsContainer(GoodsContainer(game: game, parent: self)) }
        owner.addUnit(self)
    }

    public override var xmlTagName: String {
        Unit.tag
    }

    /// Set the type without the consequences changeType deals with.
    public func setType(_ type: UnitType?) {
        self.type = type
    }

    // MARK: Disposal

    /// Leave the location (which is kept, as units slaughtered in
    /// battle stay valid during the animation), the teacher or student,
    /// the home settlement and the owner.
    public override func disposeResources() {
        location?.remove(self)
        if let teacher {
            teacher.setStudent(nil)
            self.teacher = nil
        }
        if let student {
            student.setTeacher(nil)
            self.student = nil
        }
        changeHomeIndianSettlement(nil)
        owner?.removeUnit(self)
        super.disposeResources()
    }

    // MARK: Kinds

    public var isNaval: Bool {
        type?.isNaval ?? false
    }

    /// Whether the owner is hidden, as for privateers.
    public var isOwnerHidden: Bool {
        type?.hasAbility(Ability.piracy) ?? false
    }

    public var isCarrier: Bool {
        type!.canCarryGoods || type!.canCarryUnits
    }

    public var isPerson: Bool {
        type?.hasAbility(Ability.person) ?? false
    }

    public var isUndead: Bool {
        hasAbility(Ability.undead)
    }

    public var isOffensiveUnit: Bool {
        (type?.isOffensive ?? false) || (role?.isOffensive ?? false)
    }

    /// Whether the unit defends; carriers (wagons, ships) do not.
    public var isDefensiveUnit: Bool {
        ((type?.isDefensive ?? false) || (role?.isDefensive ?? false)) && !isCarrier
    }

    /// The unit's skill, or 0 for unskilled types.
    public var skillLevel: Int {
        Unit.unitSkillLevel(type)
    }

    public static func unitSkillLevel(_ unitType: UnitType?) -> Int {
        guard let unitType, unitType.hasSkill else { return 0 }
        return unitType.skill
    }

    /// The type a teacher of a type could teach this unit, if education
    /// applies to it and the owner may have that type.
    public func teachingType(_ teacherType: UnitType) -> UnitType? {
        guard let spec = specification,
              spec.getUnitChangeType(UnitChangeType.education)?.appliesTo(self) ?? false,
              let ret = type?.teachingType(teacherType), ret.isAvailableTo([owner]) else { return nil }
        return ret
    }

    public func canBeStudent(_ teacher: Unit?) -> Bool {
        guard let teacher, let teacherType = teacher.type, teacher !== self else { return false }
        return teachingType(teacherType) != nil
    }

    // MARK: Roles

    /// Whether the unit's type and owner allow a role.
    public func roleIsAvailable(_ role: Role) -> Bool {
        role.isAvailableTo([self])
    }

    /// The roles in a list (or all roles) the unit can have.
    public func availableRoles(_ roles: [Role]?) -> [Role] {
        (roles ?? specification?.rolesList ?? []).filter(roleIsAvailable)
    }

    /// The goods gained (positive) or given up (negative) changing to a
    /// role.
    public func goodsDifference(_ role: Role, _ roleCount: Int) -> [AbstractGoods] {
        Role.goodsDifference(from: self.role, self.roleCount, to: role, roleCount)
    }

    /// Change the native settlement this unit belongs to.
    ///
    /// - Returns: The old home.
    @discardableResult
    public func changeHomeIndianSettlement(_ settlement: IndianSettlement?) -> IndianSettlement? {
        let ret = homeIndianSettlement
        ret?.removeOwnedUnit(self)
        homeIndianSettlement = settlement
        settlement?.addOwnedUnit(self)
        return ret
    }

    // MARK: State

    /// Whether the unit can change to a state.
    public func checkSetState(_ s: UnitState) -> Bool {
        if state == s { return false }
        switch s {
        case .active, .sentry: return true
        case .fortified: return state == .fortifying
        case .fortifying: return movesLeft > 0
        case .improving:
            guard movesLeft > 0, isOnTile, let tile = location?.tile else { return false }
            return owner?.canAcquireForImprovement(tile) ?? false
        case .inColony: return !isNaval
        case .skipped: return state == .active
        }
    }

    /// Change state.  It is an error to change to a state the unit can
    /// not be in.
    public func setState(_ s: UnitState) {
        if state == s { return }
        precondition(checkSetState(s), "Illegal UnitState transition: \(state) -> \(s)")
        setStateUnchecked(s)
    }

    /// Change state without checking, cleaning up the old state and
    /// starting the new one.
    public func setStateUnchecked(_ s: UnitState) {
        // Leaving an improvement: remove it if unfinished and no one
        // else is working on it.
        if state == .improving, let workImprovement, workLeft > 0 {
            if !workImprovement.isComplete, let tile = workImprovement.tile,
               let container = tile.tileItemContainer,
               !tile.unitList.contains(where: {
                   $0 !== self && $0.state == .improving && $0.workImprovement === workImprovement
               }) {
                container.removeTileItem(workImprovement)
            }
            self.workImprovement = nil
        }
        switch s {
        case .active, .fortifying, .sentry:
            workLeft = -1
        case .fortified:
            workLeft = -1
            movesLeft = 0
        case .improving:
            workLeft = workImprovement.map { $0.turnsToComplete + (movesLeft > 0 ? 0 : 1) } ?? -1
            movesLeft = 0
        case .skipped:
            break
        case .inColony:
            workLeft = -1
        }
        state = s
    }

    public var hasDefaultRole: Bool {
        role?.isDefaultRole ?? false
    }

    public var roleSuffix: String? {
        role?.suffix
    }

    // MARK: Where

    /// Set the location without telling either location (Java's
    /// setLocationNoUpdate, used by the locations themselves).
    public func setLocationNoUpdate(_ newLocation: (any Location)?) {
        location = newLocation
    }

    public var isOnCarrier: Bool {
        location is Unit
    }

    public var isOnTile: Bool {
        location is Tile
    }

    public var carrier: Unit? {
        location as? Unit
    }

    /// Whether the unit works in a colony building or tile.
    public var isInColony: Bool {
        location is WorkLocation
    }

    public var workLocation: WorkLocation? {
        location as? WorkLocation
    }

    /// The tile the unit works, if it works a colony tile.
    public var workTile: Tile? {
        (location as? WorkLocation)?.workTile
    }

    /// Change what the unit works at, and update its work location.
    public func changeWorkType(_ type: GoodsType?) {
        workType = type
        workLocation?.updateProductionType()
    }

    public var hasTile: Bool {
        tile != nil
    }

    public var maximumHitPoints: Int {
        type?.hitPoints ?? 0
    }

    public var isDamaged: Bool {
        hitPoints < maximumHitPoints
    }

    /// Whether a damaged unit must sit out repairs (it can not with the
    /// hit points combat model).
    public var isDamagedAndUnderForcedRepair: Bool {
        isDamaged && !(specification?.hasAbility(Ability.hitpointsCombatModel) ?? false)
    }

    /// The goods count others see.
    public var visibleGoods: Int {
        visibleGoodsCount >= 0 ? visibleGoodsCount : goodsSpaceTaken
    }

    /// Whether a naval unit could enter a tile (water, or a settlement
    /// it owns), or a land unit (land).
    public func isTileAccessible(_ tile: Tile) -> Bool {
        isNaval ? (!tile.isLand || (tile.settlement.map { owner?.owns($0) ?? false } ?? false))
            : tile.isLand
    }

    // MARK: Cargo

    public var canCarryUnits: Bool {
        hasAbility(Ability.carryUnits)
    }

    public var canCarryGoods: Bool {
        hasAbility(Ability.carryGoods)
    }

    public func couldCarry(_ u: Unit) -> Bool {
        canCarryUnits && cargoCapacity >= u.spaceTaken
    }

    public func couldCarry(_ g: Goods) -> Bool {
        canCarryGoods && cargoCapacity >= g.spaceTaken
    }

    public var cargoCapacity: Int {
        type?.space ?? 0
    }

    public var spaceLeft: Int {
        cargoCapacity - cargoSpaceTaken
    }

    public var hasSpaceLeft: Bool {
        spaceLeft > 0
    }

    public var goodsSpaceTaken: Int {
        canCarryGoods ? (goodsContainer?.spaceTaken ?? 0) : 0
    }

    public var unitSpaceTaken: Int {
        canCarryUnits ? unitList.reduce(0) { $0 + $1.spaceTaken } : 0
    }

    public var cargoSpaceTaken: Int {
        goodsSpaceTaken + unitSpaceTaken
    }

    public var hasGoodsCargo: Bool {
        goodsSpaceTaken > 0
    }

    public var hasCargo: Bool {
        cargoSpaceTaken > 0
    }

    /// How much of a goods type could be loaded: the free holds, and
    /// the rest of a part-filled hold of that type.
    public func loadableAmount(_ type: GoodsType) -> Int {
        guard canCarryGoods else { return 0 }
        var result = spaceLeft * GoodsContainer.cargoSize
        let count = goodsCount(type) % GoodsContainer.cargoSize
        if count != 0 { result += GoodsContainer.cargoSize - count }
        return result
    }

    // MARK: Locatable

    /// Move to a location, telling both locations, and update teaching
    /// and the population of any colonies involved.  Moving to a colony
    /// joins its best work.
    @discardableResult
    public func setLocation(_ newLocation: (any Location)?) -> Bool {
        if let colony = newLocation as? Colony { return colony.joinColony(self) }
        if newLocation === location { return true }
        if let newLocation, !newLocation.canAdd(self) { return false } // Java logs a warning
        // Teaching survives a move within a colony between work
        // locations that both teach, or both do not.
        let oldColony = isInColony ? location?.colony : nil
        let newColony = (newLocation as? WorkLocation)?.colony
        let withinColony = newColony != nil && newColony === oldColony
        let preserveEducation = withinColony
            && (location as? WorkLocation)?.canTeach == (newLocation as? WorkLocation)?.canTeach
        if let oldColony, !preserveEducation { oldColony.updateEducation(self, enable: false) }
        if let location {
            precondition(location.remove(self), "Failed to remove \(self) from \(location.id ?? "")")
        }
        if let newLocation {
            precondition(newLocation.add(self), "Failed to add \(self) to \(newLocation.id ?? "")")
        } else {
            setLocationNoUpdate(nil)
        }
        if let newColony, !preserveEducation { newColony.updateEducation(self, enable: true) }
        if !withinColony {
            oldColony?.updatePopulation()
            newColony?.updatePopulation()
        }
        return true
    }

    public var isInEurope: Bool {
        if let carrier { return carrier.isInEurope }
        return location is Europe
    }

    // MARK: Location

    public override var tile: Tile? {
        location?.tile
    }

    @discardableResult
    public override func add(_ locatable: any Locatable) -> Bool {
        guard canAdd(locatable) else { return false }
        if let unit = locatable as? Unit {
            guard super.add(unit) else { return false }
            // Java notes units boarding from an adjacent tile and in a
            // colony are handled differently; the ship's moves are only
            // spent in a colony.
            spendAllMoves()
            unit.setState(.sentry)
            return true
        } else if let goods = locatable as? Goods {
            guard addGoods(goods) else { return false }
            spendAllMoves()
            return true
        }
        preconditionFailure("Can not be added to unit: \(locatable)")
    }

    @discardableResult
    public override func remove(_ locatable: any Locatable) -> Bool {
        if locatable is Unit && canCarryUnits {
            if super.remove(locatable) {
                spendAllMoves()
                return true
            }
        } else if let goods = locatable as? Goods, canCarryGoods {
            if removeGoods(goods) != nil {
                spendAllMoves()
                return true
            }
        }
        // Java logs a warning.
        return false
    }

    public override var settlement: Settlement? {
        location?.settlement
    }

    public override func up() -> any Location {
        if isInEurope, let location { return location.up() }
        if isInColony, let colony { return colony }
        if let tile { return tile.up() }
        return self
    }

    public override var rank: Int {
        LocationRank.of(location)
    }

    /// "unit:12-freeColonist", with the role and count if not the
    /// default role.
    public override var shortDescription: String {
        var s = "\(id ?? "null")-\(type?.suffix ?? "null")"
        if !hasDefaultRole {
            s += "-\(roleSuffix ?? "null")"
            if roleCount > 1 { s += ".\(roleCount)" }
        }
        return s
    }

    // MARK: UnitLocation

    /// A unit takes its type's space (carriers can not be carried, so
    /// their cargo does not count).
    public override var spaceTaken: Int {
        type!.spaceTaken
    }

    public override func noAddReason(_ locatable: any Locatable) -> NoAddReason {
        if locatable === self { return .alreadyPresent }
        if locatable is Unit {
            if !canCarryUnits { return .wrongType }
            if locatable.spaceTaken > spaceLeft { return .capacityExceeded }
            return super.noAddReason(locatable)
        }
        if let goods = locatable as? Goods {
            // Not GoodsLocation's test, which ignores part-filled holds.
            if !canCarryGoods { return .wrongType }
            guard let type = goods.type else { return .wrongType }
            return goods.amount > loadableAmount(type) ? .capacityExceeded : .none
        }
        return super.noAddReason(locatable)
    }

    // MARK: GoodsLocation

    public override func invalidateCache() {}

    public override var goodsCapacity: Int {
        cargoCapacity
    }

    // MARK: Consumer

    public var consumedGoods: [AbstractGoods] {
        type?.consumedGoods ?? []
    }

    public var consumerPriority: Int {
        type?.priority ?? ConsumerPriority.unit
    }

    public func consumptionModifiers(_ id: String) -> [Modifier] {
        modifiers(id)
    }

    /// A unit consumes what its type does, whatever is available.
    public func productionInfo(_ input: [AbstractGoods]) -> ProductionInfo {
        var result = ProductionInfo()
        result.consumption = consumedGoods
        result.maximumConsumption = consumedGoods
        return result
    }

    // MARK: Features

    /// Scopes naming a type match the unit type.
    public override var scopeType: FreeColSpecObjectType? {
        type
    }

    /// The type's abilities, the role's, the owner's and the location's
    /// (a settlement's, or Europe's).
    public override func abilities(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                                   turn: Turn? = nil) -> [Ability] {
        var ret = type?.abilities(id) ?? []
        ret += role?.abilities(id, for: target, turn: turn) ?? []
        ret += owner?.abilities(id, for: target, turn: turn) ?? []
        if let settlement {
            ret += settlement.abilities(id, for: type, turn: turn)
        } else if isInEurope, let europe = owner?.europe {
            ret += europe.abilities(id, for: type, turn: turn)
        }
        return ret
    }

    /// The type's modifiers, the owner's and the role's.
    public override func modifiers(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                                   turn: Turn? = nil) -> [Modifier] {
        (type?.modifiers(id, for: target, turn: turn) ?? [])
            + (owner?.modifiers(id, for: target, turn: turn) ?? [])
            + (role?.modifiers(id, for: target, turn: turn) ?? [])
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let game = game!
        let spec = specification!
        name = xr.attribute("name", default: nil as String?)
        let oldWorkLocation = workLocation
        let oldOwner = owner
        owner = try xr.findFreeColGameObject(game, "owner", Player.self, required: true)
        type = try xr.getType(spec, "unitType", UnitType.self)
        state = xr.attribute("state", UnitState.self, default: .active) ?? .active
        role = try xr.getType(spec, "role", Role.self) ?? spec.defaultRole
        roleCount = xr.attribute("roleCount", default: role?.maximumCount ?? 0)
        setLocationNoUpdate(try xr.getLocationAttribute(game, "location", make: true) as? any Location)
        entryLocation = try xr.getLocationAttribute(game, "entryLocation", make: true) as? any Location
        movesLeft = xr.attribute("movesLeft", default: 0)
        workLeft = xr.attribute("workLeft", default: 0)
        attrition = xr.attribute("attrition", default: 0)
        nationality = xr.attribute("nationality", default: nil as String?)
        ethnicity = xr.attribute("ethnicity", default: nil as String?)
        turnsOfTraining = xr.attribute("turnsOfTraining", default: 0)
        hitPoints = xr.attribute("hitPoints", default: -1)
        teacher = try xr.makeFreeColObject(game, "teacher", Unit.self, required: false)
        student = try xr.makeFreeColObject(game, "student", Unit.self, required: false)
        homeIndianSettlement = try xr.makeFreeColObject(game, "indianSettlement",
                                                        IndianSettlement.self, required: false)
        treasureAmount = xr.attribute("treasureAmount", default: 0)
        destination = try xr.getLocationAttribute(game, "destination", make: true) as? any Location
        // Java does not make the route if it is not read yet.
        tradeRoute = try xr.findFreeColGameObject(game, "tradeRoute", TradeRoute.self, required: false)
        currentStop = tradeRoute == nil ? -1 : xr.attribute("currentStop", default: 0)
        experienceType = try xr.getType(spec, "experienceType", GoodsType.self)
        if experienceType == nil && workType != nil { experienceType = workType }
        experience = xr.attribute("experience", default: 0)
        visibleGoodsCount = xr.attribute("visibleGoodsCount", default: -1)
        workType = try xr.getType(spec, "workType", GoodsType.self)
        // Fix the production of a new work location.
        if let wl = workLocation, wl !== oldWorkLocation { wl.updateProductionType() }
        if xr.shouldIntern { game.checkOwners(self, oldOwner: oldOwner) }
    }

    // MARK: Copies

    /// A copy of this unit as another player sees it on a tile: on a
    /// copy of its carrier there if it is aboard one, otherwise active
    /// and not working (reduceVisibility).
    public func reduceVisibility(_ tile: Tile?, _ player: Player) throws -> Unit {
        let ret = try copy(for: player)
        if isOnCarrier, let carrier {
            let ship = try carrier.copy(for: player)
            ship.removeAllGoods()
            ship.add(ret)
            ship.setLocationNoUpdate(tile)
            ret.setLocationNoUpdate(ship)
        } else {
            ret.setLocationNoUpdate(tile)
            ret.workType = nil
            ret.setState(.active)
        }
        return ret
    }

    // MARK: Writing XML

    /// Another player's units show less, and a hidden owner (a
    /// privateer) is written as the unknown enemy.
    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        let full = xw.validFor(owner)
        xw.writeAttribute("name", id: name)
        xw.writeAttribute("unitType", type)
        xw.writeAttribute("movesLeft", movesLeft)
        xw.writeAttribute("state", state)
        xw.writeAttribute("role", role)
        xw.writeAttribute("roleCount", roleCount)
        xw.writeAttribute("hitPoints", hitPoints)
        if !full && isOwnerHidden {
            xw.writeAttribute("owner", game?.unknownEnemy)
        } else {
            xw.writeAttribute("owner", owner)
            xw.writeAttribute("nationality", id: nationality)
            xw.writeAttribute("ethnicity", id: ethnicity)
        }
        xw.writeLocationAttribute("location", location)
        xw.writeAttribute("treasureAmount", treasureAmount)
        if full {
            xw.writeLocationAttribute("entryLocation", entryLocation)
            xw.writeAttribute("turnsOfTraining", turnsOfTraining)
            xw.writeAttribute("workType", workType)
            xw.writeAttribute("experienceType", experienceType)
            xw.writeAttribute("experience", experience)
            xw.writeAttribute("indianSettlement", homeIndianSettlement)
            xw.writeAttribute("workLeft", workLeft)
            xw.writeAttribute("attrition", attrition)
            xw.writeAttribute("student", student)
            xw.writeAttribute("teacher", teacher)
            xw.writeLocationAttribute("destination", destination)
            if let tradeRoute {
                xw.writeAttribute("tradeRoute", tradeRoute)
                xw.writeAttribute("currentStop", currentStop)
            }
        } else if type?.canCarryGoods ?? false {
            xw.writeAttribute("visibleGoodsCount", visibleGoods)
        }
    }

    /// The cargo and work, only for the owner.
    public override func writeChildren(_ xw: FreeColXMLWriter) {
        guard xw.validFor(owner) else { return }
        super.writeChildren(xw)
        workImprovement?.toXML(xw)
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        goodsContainer?.removeAll()
        workImprovement = nil
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "equipment": // @compat 0.11.0
            try xr.swallowTag("equipment")
        case TileImprovement.tag, TileImprovement.oldTag:
            workImprovement = try xr.readFreeColObject(game!, TileImprovement.self)
        default:
            try super.readChild(xr)
        }
    }
}

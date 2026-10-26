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

extension AbstractUnit {

    public func addToNumber(_ diff: Int) {
        number += diff
    }

    /// The sum of the units' offence, as Java's DoubleStream sums it.
    public static func calculateStrength(_ spec: Specification, _ units: [AbstractUnit]) -> Double {
        JavaMath.doubleStreamSum(units.lazy.map { $0.offence(spec) })
    }

    public static func deepCopy(_ units: [AbstractUnit]) -> [AbstractUnit] {
        units.map { AbstractUnit(id: $0.id, roleId: $0.roleId, number: $0.number) }
    }

    /// Whether another has the same type and role.
    public func matches(_ other: AbstractUnit) -> Bool {
        id == other.id && roleId == other.roleId
    }

    /// Whether two lists hold units matching in type, role and number.
    public static func matchUnits(_ l1: [AbstractUnit], _ l2: [AbstractUnit]) -> Bool {
        l1.count == l2.count && l1.allSatisfy { au in l2.contains { $0.matchAll(au) } }
    }
}

/// A group of land and naval units, such as the Royal Expeditionary
/// Force (common/model/Force).
///
/// Units added are kept as given, not copied, so units from a list
/// option are shared with the specification, as in Java.
public final class Force: FreeColSpecObject {

    public static let tag = "force"

    private var landUnits: [AbstractUnit] = []
    private var navalUnits: [AbstractUnit] = []
    /// The space the land units take.
    public private(set) var spaceRequired = 0
    /// The space the naval units have for land units.
    public private(set) var capacity = 0

    public init(_ specification: Specification?) {
        super.init(specification: specification)
    }

    /// A force of units, those lacking an ability (if given) left out.
    public convenience init(_ spec: Specification, _ units: [AbstractUnit], ability: String? = nil) {
        self.init(spec)
        for au in units where ability == nil || (au.type(spec)?.hasAbility(ability!) ?? false) {
            add(au)
        }
    }

    public override var xmlTagName: String {
        Force.tag
    }

    /// The land units, then the naval units.
    public var unitList: [AbstractUnit] {
        landUnits + navalUnits
    }

    public func clearLandUnits() {
        landUnits = []
        spaceRequired = 0
    }

    public func clearNavalUnits() {
        navalUnits = []
        capacity = 0
    }

    public var landUnitsList: [AbstractUnit] {
        AbstractUnit.deepCopy(landUnits)
    }

    public var navalUnitsList: [AbstractUnit] {
        AbstractUnit.deepCopy(navalUnits)
    }

    public var isEmpty: Bool {
        landUnits.isEmpty && navalUnits.isEmpty
    }

    /// Add units, joining a matching group if there is one.
    public func add(_ au: AbstractUnit) {
        guard let spec = specification, let unitType = au.type(spec) else { return }
        let n = au.number
        if unitType.hasAbility(Ability.navalUnit) {
            if let refUnit = navalUnits.first(where: { $0.matches(au) }) {
                refUnit.addToNumber(n)
            } else {
                navalUnits.append(au)
            }
            if unitType.canCarryUnits { capacity += unitType.space * n }
        } else {
            if let refUnit = landUnits.first(where: { $0.matches(au) }) {
                refUnit.addToNumber(n)
            } else {
                landUnits.append(au)
            }
            spaceRequired += unitType.spaceTaken * n
        }
    }

    /// The offence of the naval or the land units.
    public func calculateStrength(_ naval: Bool) -> Double {
        guard let spec = specification else { return 0 }
        return AbstractUnit.calculateStrength(spec, naval ? navalUnits : landUnits)
    }

    /// Add enough ships of a type (or of the first naval type that can
    /// carry units) to carry the land units.
    ///
    /// - Returns: The space left over, negative if short.
    @discardableResult
    public func prepareToBoard(_ shipType: UnitType?) -> Int {
        if spaceRequired > capacity {
            var shipType = shipType
            if shipType == nil {
                guard let spec = specification,
                      let ship0 = navalUnits.first(where: { ($0.type(spec)?.space ?? 0) > 0 }) else {
                    return capacity - spaceRequired
                }
                shipType = ship0.type(spec)
            }
            let sp = shipType!.space
            let more = (spaceRequired - capacity) / sp + 1
            if more > 0 {
                add(AbstractUnit(id: shipType!.id, roleId: Specification.defaultRoleId, number: more))
            }
        }
        return capacity - spaceRequired
    }

    public func matchAll(_ other: Force) -> Bool {
        AbstractUnit.matchUnits(landUnits, other.landUnits)
            && AbstractUnit.matchUnits(navalUnits, other.navalUnits)
    }

    // MARK: Reading XML

    /// Read the force from the element the reader is on, whatever its
    /// tag (the monarch's forces are saved under their own names).
    public override func readFromXML(_ xr: FreeColXMLReader) throws {
        clearLandUnits()
        clearNavalUnits()
        while try xr.moreTags() {
            let child = xr.localName
            if child == "landUnits" || child == "navalUnits" {
                while try xr.moreTags() {
                    add(try AbstractUnit(xr))
                }
            } else {
                xr.warn("Bogus Force tag: \(child)")
                try xr.swallowTag(child)
            }
        }
    }

    /// Write the force under a tag: its naval units, then its land
    /// units, without attributes.
    public override func toXML(_ xw: FreeColXMLWriter, tag: String) {
        xw.writeStartElement(tag)
        xw.writeStartElement("navalUnits")
        for unit in navalUnits { unit.toXML(xw) }
        xw.writeEndElement()
        xw.writeStartElement("landUnits")
        for unit in landUnits { unit.toXML(xw) }
        xw.writeEndElement()
        xw.writeEndElement()
    }

    public override var description: String {
        "<Force \(spaceRequired)/\(capacity)" + landUnits.map { " \($0)" }.joined()
            + navalUnits.map { " \($0)" }.joined() + ">"
    }
}

/// The player's monarch, who raises taxes, declares wars and sends the
/// Royal Expeditionary Force (common/model/Monarch).
///
/// The player holds its monarch; the reference back is weak.  Not yet
/// ported: the name (i18n) and copyIn.  War support, which
/// weighs strength with the combat model, is in Defence.swift.
public final class Monarch: FreeColGameObject, GameObjectReadable {

    public static let tag = "monarch"

    /// What the monarch might do (Monarch.MonarchAction).
    public enum MonarchAction: JavaEnum, CustomStringConvertible {
        case noAction, raiseTaxAct, raiseTaxWar, forceTax, lowerTaxWar, lowerTaxOther, waiveTax
        case addToREF, declarePeace, declareWar, supportLand, supportSea
        case monarchMercenaries, hessianMercenaries, displeasure

        public var javaName: String {
            switch self {
            case .noAction: "NO_ACTION"
            case .raiseTaxAct: "RAISE_TAX_ACT"
            case .raiseTaxWar: "RAISE_TAX_WAR"
            case .forceTax: "FORCE_TAX"
            case .lowerTaxWar: "LOWER_TAX_WAR"
            case .lowerTaxOther: "LOWER_TAX_OTHER"
            case .waiveTax: "WAIVE_TAX"
            case .addToREF: "ADD_TO_REF"
            case .declarePeace: "DECLARE_PEACE"
            case .declareWar: "DECLARE_WAR"
            case .supportLand: "SUPPORT_LAND"
            case .supportSea: "SUPPORT_SEA"
            case .monarchMercenaries: "MONARCH_MERCENARIES"
            case .hessianMercenaries: "HESSIAN_MERCENARIES"
            case .displeasure: "DISPLEASURE"
            }
        }

        public var description: String {
            javaName
        }
    }

    public static let monarchMinimumPrice = 200
    public static let hessianMinimumPrice = 5000
    public static let minimumTaxRate = 20

    public private(set) weak var player: Player?
    public var supportSea = false
    public var displeasure = false
    private var expeditionaryForceValue: Force?
    private var interventionForceValue: Force?

    // Caches, made on first use.
    private var navalTypes: [UnitType] = []
    private var bombardTypes: [UnitType] = []
    private var landTypes: [UnitType] = []
    private var mercenaryTypes: [UnitType] = []
    private var navalREFUnitTypes: [UnitType] = []
    private var landREFUnitTypes: [UnitType] = []
    private var mountedRole: Role?, armedRole: Role?, refMountedRole: Role?, refArmedRole: Role?
    private var cachesInitialized = false

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    public init(game: Game, player: Player) {
        self.player = player
        super.init(game: game)
    }

    public override var xmlTagName: String {
        Monarch.tag
    }

    // MARK: Forces

    /// The Royal Expeditionary Force, from the rules unless read.
    public var expeditionaryForce: Force {
        if expeditionaryForceValue == nil, let spec = specification {
            expeditionaryForceValue = Force(spec, spec.getUnitList(GameOptions.refForce))
        }
        return expeditionaryForceValue!
    }

    /// The force a foreign power sends to help the rebels.
    public var interventionForce: Force {
        if interventionForceValue == nil, let spec = specification {
            interventionForceValue = Force(spec, spec.getUnitList(GameOptions.interventionForce))
        }
        return interventionForceValue!
    }

    public var mercenaryForce: Force {
        Force(specification!, specification!.getUnitList(GameOptions.mercenaryForce))
    }

    public var warSupportForce: Force {
        Force(specification!, specification!.getUnitList(GameOptions.warSupportForce))
    }

    private var taxMaximum: Int {
        specification?.getInteger(GameOptions.maximumTax) ?? 0
    }

    private func initializeCaches() {
        guard !cachesInitialized, let spec = specification else { return }
        cachesInitialized = true
        navalREFUnitTypes = spec.refUnitTypes(naval: true)
        landREFUnitTypes = spec.refUnitTypes(naval: false)
        for unitType in spec.unitTypeList {
            if unitType.hasAbility(Ability.supportUnit) {
                if unitType.hasAbility(Ability.navalUnit) {
                    navalTypes.append(unitType)
                } else if unitType.hasAbility(Ability.bombard) {
                    bombardTypes.append(unitType)
                } else if unitType.hasAbility(Ability.canBeEquipped) {
                    landTypes.append(unitType)
                }
            }
            if unitType.hasAbility(Ability.mercenaryUnit) { mercenaryTypes.append(unitType) }
        }
        for r in spec.militaryRolesList {
            let ok = r.isAvailableTo([player, landTypes.first])
            let armed = r.hasAbility(Ability.armed)
            let mounted = r.hasAbility(Ability.mounted)
            let ref = r.requiresAbility(Ability.refUnit)
            if armed && mounted {
                if ok && !ref && mountedRole == nil {
                    mountedRole = r
                } else if !ok && ref && refMountedRole == nil {
                    refMountedRole = r
                }
            } else if armed && !mounted {
                if ok && !ref && armedRole == nil {
                    armedRole = r
                } else if !ok && ref && refArmedRole == nil {
                    refArmedRole = r
                }
            }
        }
    }

    // MARK: Actions

    /// The other Europeans the monarch could declare war on (none once
    /// the player ignores European wars).
    public func collectPotentialEnemies() -> [Player] {
        guard let player, let game else { return [] }
        if player.hasAbility(Ability.ignoreEuropeanWars) { return [] }
        return game.liveEuropeanPlayers(excluding: player).filter { $0.isPotentialEnemy(player) }
    }

    public func collectPotentialFriends() -> [Player] {
        guard let player, let game else { return [] }
        return game.liveEuropeanPlayers(excluding: player).filter { $0.isPotentialFriend(player) }
    }

    public func actionIsValid(_ action: MonarchAction) -> Bool {
        initializeCaches()
        guard let player else { return false }
        switch action {
        case .noAction: return true
        case .raiseTaxAct, .raiseTaxWar: return player.tax < taxMaximum
        case .forceTax: return false
        case .lowerTaxWar, .lowerTaxOther: return player.tax > Monarch.minimumTaxRate + 10
        case .waiveTax: return true
        case .addToREF: return !navalREFUnitTypes.isEmpty && !landREFUnitTypes.isEmpty
        case .declarePeace: return !collectPotentialFriends().isEmpty
        case .declareWar: return !collectPotentialEnemies().isEmpty
        case .supportSea: return player.attackedByPrivateers && !supportSea && !displeasure
        case .supportLand, .monarchMercenaries:
            return player.isAtWar && !displeasure && player.hasSettlements
        case .hessianMercenaries:
            return player.checkGold(Monarch.hessianMinimumPrice) && player.hasSettlements
        case .displeasure: return false
        }
    }

    /// The actions the monarch might take this turn, with weights.
    public func actionChoices() -> [RandomChoice<MonarchAction>] {
        guard let spec = specification, let player, let game else { return [] }
        var choices: [RandomChoice<MonarchAction>] = []
        let dx = 1 + (spec.getInteger(GameOptions.monarchMeddling) ?? 0)
        let turn = game.turn.number
        let grace = (6 - dx) * 10 // 10-50

        // Nothing happens during the first few turns, if there are no
        // colonies, or after the revolution begins.
        if turn < grace || !player.hasSettlements || player.playerType != .colonial {
            return choices
        }

        func addIfValid(_ action: MonarchAction, _ weight: Int) {
            if actionIsValid(action) { choices.append(RandomChoice(action, weight)) }
        }
        // The more time has passed, the less likely the monarch will do
        // nothing.
        addIfValid(.noAction, max(200 - turn, 100))
        addIfValid(.raiseTaxAct, 5 + dx)
        addIfValid(.raiseTaxWar, 5 + dx)
        addIfValid(.lowerTaxWar, 5 - dx)
        addIfValid(.lowerTaxOther, 5 - dx)
        addIfValid(.addToREF, 10 + dx)
        addIfValid(.declarePeace, 6 - dx)
        addIfValid(.declareWar, 5 + dx)
        if player.checkGold(Monarch.monarchMinimumPrice) {
            addIfValid(.monarchMercenaries, 6 - dx)
        } else if dx < 3 {
            addIfValid(.supportLand, 3 - dx)
        }
        addIfValid(.supportSea, 6 - dx)
        addIfValid(.hessianMercenaries, 6 - dx)
        return choices
    }

    /// A new, higher tax rate.
    public func raiseTax(_ random: JavaRandom) -> Int {
        let taxAdjustment = specification?.getInteger(GameOptions.taxAdjustment) ?? 0
        let turn = game?.turn.number ?? 0
        let oldTax = player?.tax ?? 0
        var adjust = max(1, (6 - taxAdjustment) * 10) // 20-60
        adjust = 1 + Int(RandomUtils.randomInt("Tax rise", random, Int32(3 + turn / adjust)))
        return min(oldTax + adjust, taxMaximum)
    }

    /// A new, lower tax rate.
    public func lowerTax(_ random: JavaRandom) -> Int {
        let taxAdjustment = specification?.getInteger(GameOptions.taxAdjustment) ?? 0
        let oldTax = player?.tax ?? 0
        var adjust = max(1, 10 - taxAdjustment) // 5-10
        adjust = 1 + Int(RandomUtils.randomInt("Tax reduction", random, Int32(adjust)))
        return max(oldTax - adjust, Monarch.minimumTaxRate)
    }

    public var navalREFUnitType: UnitType? {
        initializeCaches()
        return navalREFUnitTypes.first
    }

    /// Whether the REF needs more ships to carry its land units.
    public var shouldAddNavalUnit: Bool {
        let ref = expeditionaryForce
        return Double(ref.capacity) < Double(ref.spaceRequired) * 1.1
    }

    /// Add units to the REF: a ship if more space is needed, otherwise
    /// one to three land units.
    public func addToREF(_ random: JavaRandom) -> AbstractUnit? {
        initializeCaches()
        guard let spec = specification else { return nil }
        let result: AbstractUnit
        if shouldAddNavalUnit {
            guard let type = RandomUtils.randomMember("Naval REF unit", navalREFUnitTypes, random) else {
                return nil
            }
            result = AbstractUnit(id: type.id, roleId: Specification.defaultRoleId, number: 1)
        } else {
            guard let unitType = RandomUtils.randomMember("Land REF unit", landREFUnitTypes, random) else {
                return nil
            }
            let role = !unitType.hasAbility(Ability.canBeEquipped) ? spec.defaultRole
                : RandomUtils.randomInt("Choose land role", random, 3) == 0 ? refMountedRole
                : refArmedRole
            let number = Int(RandomUtils.randomInt("Choose land#", random, 3)) + 1
            result = AbstractUnit(id: unitType.id, roleId: role?.id, number: number)
        }
        expeditionaryForce.add(result)
        return result
    }

    /// Grow the intervention force with the turns passed.
    public func updateInterventionForce() {
        guard let spec = specification, let game else { return }
        let interventionTurns = spec.getInteger(GameOptions.interventionTurns) ?? 0
        let updates = game.turn.number / interventionTurns
        let ivf = interventionForce
        if interventionTurns > 0 && updates > 0 {
            for au in ivf.landUnitsList {
                ivf.add(AbstractUnit(id: au.id, roleId: au.roleId, number: updates))
            }
            ivf.prepareToBoard(nil)
        }
    }

    /// Units the monarch sends to help in a war: a ship, or land units
    /// by difficulty.
    public func support(_ random: JavaRandom, naval: Bool) -> [AbstractUnit] {
        initializeCaches()
        guard let spec = specification else { return [] }
        var support: [AbstractUnit] = []
        func pick(_ logMe: String, _ types: [UnitType], _ role: Role?, _ n: Int) {
            let t = RandomUtils.randomMember(logMe, types, random)
            support.append(AbstractUnit(id: t?.id, roleId: role?.id ?? Specification.defaultRoleId, number: n))
        }
        if naval {
            pick("Choose naval support", navalTypes, nil, 1)
            supportSea = true
            return support
        }
        switch spec.getInteger(GameOptions.monarchSupport) ?? 0 {
        case 4:
            pick("Choose bombard", bombardTypes, nil, 1)
            pick("Choose mounted", landTypes, mountedRole, 2)
        case 3:
            pick("Choose mounted", landTypes, mountedRole, 2)
            pick("Choose soldier", landTypes, armedRole, 1)
        case 2:
            pick("Choose mounted", landTypes, mountedRole, 2)
        case 1:
            pick("Choose mounted", landTypes, mountedRole, 1)
            pick("Choose soldier", landTypes, armedRole, 1)
        case 0:
            pick("Choose soldier", landTypes, armedRole, 1)
        default:
            break
        }
        return support
    }

    /// Mercenaries to offer: two to four units the player could afford.
    ///
    /// - Returns: The price.
    public func loadMercenaries(_ random: JavaRandom, _ mercs: inout [AbstractUnit]) -> Int {
        initializeCaches()
        mercs.removeAll()
        guard let spec = specification, let player else { return 0 }
        let defaultRole = spec.defaultRole
        let mercPrice = spec.getInteger(GameOptions.mercenaryPrice) ?? 0
        let landRoles = [armedRole, mountedRole]
        var count = Int(RandomUtils.randomInt("Mercenary count", random, 2)) + 2
        var price = 0
        var unitTypes = mercenaryTypes
        while count > 0 && !unitTypes.isEmpty {
            let unitType = RandomUtils.randomMember("Merc unit", unitTypes, random)!
            unitTypes.removeAll { $0 === unitType }
            let role = unitType.hasAbility(Ability.canBeEquipped)
                ? RandomUtils.randomMember("Merc role", landRoles, random)! : defaultRole
            var n = Int(RandomUtils.randomInt("Merc count \(unitType.id ?? "null")", random,
                                              Int32(min(count, 2)))) + 1
            let au = AbstractUnit(id: unitType.id, roleId: role?.id, number: 1)
            var newPrice = player.europeanPurchasePrice(au)
            if newPrice <= 0 || newPrice == Constants.infinity { break }
            newPrice *= mercPrice / 100
            while n > 0 && !player.checkGold(price + newPrice * n) { n -= 1 }
            if n > 0 {
                au.number = n
                mercs.append(au)
                price += newPrice * n
                count -= n
            } else {
                unitTypes.removeAll { $0 === unitType }
            }
        }
        return price
    }

    /// The mercenary force from the rules, cut down at random until the
    /// player can afford it.
    ///
    /// - Returns: The price, or -1 if nothing is affordable.
    public func loadMercenaryForce(_ random: JavaRandom, _ mercs: inout [AbstractUnit]) -> Int {
        initializeCaches()
        mercs.removeAll()
        guard let player else { return -1 }
        mercs += mercenaryForce.unitList
        var prices = mercs.map { player.mercenaryHirePrice($0) / $0.number }
        var i = 0, mercPrice = 0
        while i < mercs.count {
            let price = prices[i]
            if price <= 0 || price == Constants.infinity {
                prices.remove(at: i)
                mercs.remove(at: i)
            } else {
                mercPrice += price * mercs[i].number
                i += 1
            }
        }
        while !mercs.isEmpty {
            if player.checkGold(mercPrice) { return mercPrice }
            let r = Int(RandomUtils.randomInt("merc downsize", random, Int32(mercs.count)))
            mercPrice -= prices[r]
            let au = mercs[r]
            if au.number > 1 {
                au.addToNumber(-1)
            } else {
                prices.remove(at: r)
                mercs.remove(at: r)
            }
        }
        return -1
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        player = try xr.findFreeColGameObject(game!, "player", Player.self, required: true)
        supportSea = xr.attribute("supportSea", default: false)
        displeasure = xr.attribute("displeasure", default: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("player", player)
        if xw.validFor(player) {
            xw.writeAttribute("supportSea", supportSea)
            xw.writeAttribute("displeasure", displeasure)
        }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if xw.validFor(player) {
            expeditionaryForce.toXML(xw, tag: "expeditionaryForce")
            interventionForce.toXML(xw, tag: "interventionForce")
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        // Provide empty forces to read into.
        if expeditionaryForceValue == nil { expeditionaryForceValue = Force(specification) }
        if interventionForceValue == nil { interventionForceValue = Force(specification) }
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "expeditionaryForce":
            try expeditionaryForceValue!.readFromXML(xr)
        case "interventionForce":
            try interventionForceValue!.readFromXML(xr)
        case "mercenaryForce":
            // @compat 0.11.5: the mercenary force lives in the rules now.
            try Force(specification).readFromXML(xr)
        default:
            try super.readChild(xr)
        }
    }
}

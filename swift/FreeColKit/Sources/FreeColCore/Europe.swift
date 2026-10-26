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

/// Europe, where a player buys, sells, recruits and trains
/// (common/model/Europe).
///
/// The player holds its Europe, and Europe the units in it; the owner
/// is weak.  Not yet ported: copyIn.
public final class Europe: UnitLocation, GameObjectReadable, Ownable, TradeLocation {

    public static let tag = "europe"

    static let recruitPriceInitial = 200
    static let lowerCapInitial = 80

    /// How a unit comes to migrate (Europe.MigrationType), and the
    /// numbering of the recruit slots: slot 0 lets the player choose,
    /// slots 1 to 3 are the three recruits (indexes 0 to 2).
    public enum MigrationType: JavaEnum, CustomStringConvertible {
        /// The unit decided to migrate.
        case normal
        /// The player is paying.
        case recruit
        /// A Fountain of Youth discovery.
        case fountain
        /// The server's emergency recruit.
        case survival

        public static let migrantCount = 3
        public static let unspecificSlot = 0
        public static let defaultSlot = 1

        public static func validMigrantIndex(_ x: Int) -> Bool { 0 <= x && x < migrantCount }
        public static func migrantIndexToSlot(_ x: Int) -> Int { x + 1 }
        public static func migrantSlotToIndex(_ x: Int) -> Int { x - 1 }
        public static func validMigrantSlot(_ x: Int) -> Bool { 0 <= x && x <= migrantCount }
        public static func specificMigrantSlot(_ x: Int) -> Bool { 1 <= x && x <= migrantCount }
        public static func unspecificMigrantSlot(_ x: Int) -> Bool { x == unspecificSlot }

        public static func convertToMigrantSlot(_ i: Int?) -> Int {
            guard let i, validMigrantSlot(i) else { return unspecificSlot }
            return i
        }

        public var javaName: String {
            switch self {
            case .normal: "NORMAL"
            case .recruit: "RECRUIT"
            case .fountain: "FOUNTAIN"
            case .survival: "SURVIVAL"
            }
        }

        public var description: String {
            javaName
        }
    }

    /// Europe can always dress a missionary.  It is not stored, but
    /// added to the abilities whenever they are asked for.  (Java shares
    /// one static Ability; Swift 6 does not allow a shared mutable one.)
    private let abilityDressMissionary = Ability(Ability.dressMissionary)

    private let features = FeatureContainer()

    /// The units waiting to migrate.
    public internal(set) var recruitables: [AbstractUnit] = []
    /// Prices that differ from the unit types' own, in Java's HashMap
    /// order.
    private var unitPrices = JavaHashMap<UnitType, Int>(javaHash: { $0.javaHashCode })
    public var baseRecruitPrice = Europe.recruitPriceInitial
    public var recruitLowerCap = Europe.lowerCapInitial
    public private(set) weak var owner: Player?

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    public init(game: Game, owner: Player) {
        self.owner = owner
        super.init(game: game)
    }

    public override var xmlTagName: String {
        Europe.tag
    }

    // MARK: Recruits and prices

    /// The recruits one at a time: the first three, or all of them.
    public func expandedRecruitables(full: Bool) -> [AbstractUnit] {
        var ret: [AbstractUnit] = []
        var c = 0
        outer: for au in recruitables {
            var n = au.number
            while n > 0 {
                if !full && c >= MigrationType.migrantCount { break outer }
                ret.append(AbstractUnit(id: au.id, roleId: au.roleId, number: 1))
                c += 1
                n -= 1
            }
        }
        return ret
    }

    /// Replace the recruits.
    public func setRecruitables(_ recruits: [AbstractUnit]) {
        recruitables = recruits
    }

    /// Add a recruit, if there is room or it is forced.
    @discardableResult
    public func addRecruitable(_ au: AbstractUnit, force: Bool) -> Bool {
        guard force || recruitables.count < MigrationType.migrantCount else { return false }
        recruitables.append(au)
        return true
    }

    @discardableResult
    public func addRecruitable(_ unitType: UnitType, force: Bool) -> Bool {
        let role = unitType.defaultRole ?? specification?.defaultRole
        return addRecruitable(AbstractUnit(id: unitType.id, roleId: role?.id, number: 1), force: force)
    }

    /// The price of a unit type here.
    public func unitPrice(_ unitType: UnitType) -> Int {
        unitPrices[unitType] ?? unitType.price
    }

    /// The price to recruit now, lower as immigration nears the target,
    /// or -1 if the owner is not colonial.
    /// Set what a unit type costs here.
    public func setUnitPrice(_ unitType: UnitType, _ price: Int) {
        _ = unitPrices.put(unitType, price)
    }

    public var currentRecruitPrice: Int {
        guard let owner, owner.isColonial else { return -1 }
        let required = owner.immigrationRequired
        let difference = max(required - owner.immigration, 0)
        return max((baseRecruitPrice * difference) / required, recruitLowerCap)
    }

    /// The immigration Europe adds to some production: a bonus, less a
    /// penalty for each person here, but never making the total
    /// negative.
    public func immigration(_ production: Int) -> Int {
        guard let spec = specification else { return 0 }
        var n = unitList.filter(\.isPerson).count
        n *= spec.getInteger(GameOptions.europeanUnitImmigrationPenalty) ?? 0
        n += spec.getInteger(GameOptions.playerImmigrationBonus) ?? 0
        if n + production < 0 { n = -production }
        return n
    }

    // MARK: Location

    /// Ships in Europe are active, other units wait.
    @discardableResult
    public override func add(_ locatable: any Locatable) -> Bool {
        let result = super.add(locatable)
        if result, let unit = locatable as? Unit {
            unit.setState(unit.canCarryUnits ? .active : .sentry)
        }
        return result
    }

    /// Goods can always be landed.
    public override func canAdd(_ locatable: any Locatable) -> Bool {
        if locatable is Goods { return true }
        return super.canAdd(locatable)
    }

    public override func up() -> any Location {
        self
    }

    public override var rank: Int {
        LocationRank.europe
    }

    public override var shortDescription: String {
        "Europe"
    }

    /// The market price of goods: what buying costs, or (for negative
    /// amounts) what selling pays.
    ///
    /// - Throws: FreeColException for boycotted goods.
    public override func priceGoods(_ goods: [AbstractGoods]) throws -> Int {
        guard let player = owner, let market = player.market else { return 0 }
        var price = 0
        for ag in goods {
            guard let goodsType = ag.type else { continue }
            // Refuse to trade in boycotted goods
            if !player.canTrade(goodsType) { throw FreeColException("Can not trade \(goodsType)") }
            price += ag.amount > 0 ? market.bidPrice(goodsType, ag.amount)
                : market.salePrice(goodsType, ag.amount)
        }
        return price
    }

    /// Only the server equips units in Europe.
    public override func equipForRole(_ unit: Unit, _ role: Role, _ roleCount: Int) -> Bool {
        preconditionFailure("Only valid in the server: \(self)")
    }

    // MARK: Trade location

    public func availableGoodsCount(_ goodsType: GoodsType) -> Int {
        GoodsContainer.hugeCargoSize
    }

    public func exportAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        (owner?.canTrade(goodsType) ?? false) ? GoodsContainer.hugeCargoSize : 0
    }

    public func importAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        (owner?.canTrade(goodsType) ?? false) ? GoodsContainer.hugeCargoSize : 0
    }

    /// The name key of the owner's Europe.
    public func locationName(_ tradeLocation: TradeLocation) -> String? {
        (tradeLocation as! Europe).nameKey
    }

    public var canBeInput: Bool { true }

    /// The message key for the owner's name for Europe.
    public var nameKey: String? {
        owner?.europeNameKey
    }

    // MARK: Features

    public override var featureContainer: FeatureContainer? {
        features
    }

    public override func abilities(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                                   turn: Turn? = nil) -> [Ability] {
        super.abilities(id, for: target, turn: turn)
            + (id == nil || id == Ability.dressMissionary ? [abilityDressMissionary] : [])
    }

    // MARK: Disposal

    public override func disposeResources() {
        if let owner {
            owner.europe = nil
            owner.highSeas?.removeDestination(self)
        }
        super.disposeResources()
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        owner = try xr.findFreeColGameObject(game!, "owner", Player.self, required: true)
        baseRecruitPrice = xr.attribute("recruitPrice", default: Europe.recruitPriceInitial)
        recruitLowerCap = xr.attribute("recruitLowerCap", default: Europe.lowerCapInitial)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if xw.validFor(owner) {
            xw.writeAttribute("recruitPrice", baseRecruitPrice)
            xw.writeAttribute("recruitLowerCap", recruitLowerCap)
            xw.writeAttribute("owner", owner)
        }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if xw.validFor(owner) {
            for ability in features.abilityValues.sorted(by: FreeColObject.idOrder) { ability.toXML(xw) }
            for modifier in sortedModifiers { modifier.toXML(xw) }
            for unitType in sortedById(unitPrices.keys) {
                xw.writeStartElement("unitPrice")
                xw.writeAttribute("unitType", unitType)
                xw.writeAttribute("price", unitPrices[unitType] ?? 0)
                xw.writeEndElement()
            }
            for au in recruitables {
                xw.writeStartElement("recruit")
                xw.writeAttribute("id", id: au.id)
                xw.writeAttribute("role", id: au.roleId)
                xw.writeAttribute("number", au.number)
                xw.writeEndElement()
            }
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        unitPrices.removeAll()
        features.clear()
        recruitables = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let spec = specification
        switch xr.localName {
        case Unit.tag:
            try super.readChild(xr)
        case Ability.tag:
            let ability = try Ability(xr, specification: spec)
            // @compat 1.1.0: older saves stored the implicit ability, one
            // more copy each time they were saved.
            if ability.id != Ability.dressMissionary { addAbility(ability) }
        case Modifier.tag:
            addModifier(try Modifier(xr, specification: spec))
        case "recruit":
            var unitType = try spec.flatMap { try xr.getType($0, "type", UnitType.self) }
            // @compat 0.11.x
            if unitType == nil { unitType = try spec.flatMap { try xr.getType($0, "id", UnitType.self) } }
            if let unitType {
                let role = try spec.flatMap { try xr.getType($0, "role", Role.self) } ?? unitType.defaultRole
                let n = xr.attribute("number", default: 1)
                addRecruitable(AbstractUnit(id: unitType.id, roleId: role?.id, number: n), force: true)
            }
            try xr.closeTag("recruit")
        case "unitPrice":
            if let unitType = try spec.flatMap({ try xr.getType($0, "unitType", UnitType.self) }) {
                _ = unitPrices.put(unitType, xr.attribute("price", default: -1))
            }
            try xr.closeTag("unitPrice")
        default:
            try xr.swallowTag(xr.localName)
        }
    }

    public override var description: String {
        "Europe"
    }
}

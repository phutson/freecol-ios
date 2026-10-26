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

/// A role a unit can take with equipment, such as soldier or pioneer
/// (common/model/Role).
///
/// Not yet ported: the roles available to a player.
public final class Role: BuildableType {

    public static let tag = "role"

    /// A role change on capture: a unit in role `from` captures as
    /// `capture`.
    public struct RoleChange {
        public let from: String?
        public let capture: String?

        public func from(_ spec: Specification) -> Role? { spec.getRole(from) }
        public func capture(_ spec: Specification) -> Role? { spec.getRole(capture) }
    }

    /// The role lost to when defeated.
    public var downgrade: Role?
    /// How many times the role's equipment can be held.
    public var maximumCount = 1
    /// The unit type that is expert in this role.
    public var expertUnit: UnitType?
    private var roleChangeList: [RoleChange]?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        Role.tag
    }

    /// Whether a role id is the default (no equipment) role.
    /// The last part of a role id ("soldier").
    public static func roleIdSuffix(_ roleId: String?) -> String {
        JavaString.lastPart(roleId ?? "null", ".")
    }

    public static func isDefaultRoleId(_ roleId: String?) -> Bool {
        roleId == Specification.defaultRoleId
    }

    public var isDefaultRole: Bool {
        Role.isDefaultRoleId(id)
    }

    /// The last part of the id ("soldier").
    public var roleSuffix: String? {
        id.map { JavaString.lastPart($0, ".") }
    }

    /// What the goods for the most equipment cost in a market.
    public func requiredGoodsPrice(_ market: Market) -> Int {
        requiredGoods.reduce(0) { sum, ag in
            sum + (ag.type.map { market.bidPrice($0, ag.amount * maximumCount) } ?? 0)
        }
    }

    /// The goods needed for a number of the role's equipment.
    public func requiredGoods(count roleCount: Int) -> [AbstractGoods] {
        let result = requiredGoods
        if roleCount > 1 {
            for ag in result { ag.amount = roleCount * ag.amount }
        }
        return result
    }

    /// The role changes, in the order read.
    public var roleChanges: [RoleChange] {
        roleChangeList ?? []
    }

    /// The offence the role adds, from nothing.
    public var offence: Double {
        Double(apply(0, turn: nil, Modifier.offence))
    }

    public var isOffensive: Bool {
        hasModifier(Modifier.offence)
    }

    /// The defence the role adds, from nothing.
    public var defence: Double {
        Double(apply(0, turn: nil, Modifier.defence))
    }

    public var isDefensive: Bool {
        hasModifier(Modifier.defence)
    }

    /// Whether a unit can switch between the roles directly.
    public func isCompatible(with other: Role?) -> Bool {
        Role.rolesCompatible(self, other)
    }

    /// Whether two roles are the same, or one downgrades to the other.
    public static func rolesCompatible(_ a: Role?, _ b: Role?) -> Bool {
        guard let a else { return b == nil }
        guard let b else { return false }
        return a === b || a.downgrade === b || b.downgrade === a
    }

    /// The goods gained (positive) or given up (negative) changing role.
    public static func goodsDifference(from: Role?, _ fromCount: Int,
                                       to: Role, _ toCount: Int) -> [AbstractGoods] {
        var result: [AbstractGoods] = []
        guard from !== to, !(from == nil && to.isDefaultRole) else { return result }
        let fromGoods = from?.requiredGoods(count: fromCount) ?? []
        let toGoods = to.requiredGoods(count: toCount)
        for ag in toGoods {
            let amount = ag.amount - AbstractGoods.count(of: ag.type, in: fromGoods)
            if amount != 0 { result.append(AbstractGoods(ag.type, amount)) }
        }
        for ag in fromGoods where !toGoods.contains(where: { $0.type === ag.type }) {
            result.append(AbstractGoods(ag.type, -ag.amount))
        }
        return result
    }

    /// The ordering index Java uses: native, REF and other roles in
    /// bands, fewer required goods first.
    public var roleIndex: Int {
        let base = requiresAbility(Ability.native) ? 30
            : requiresAbility(Ability.refUnit) ? 20
            : 10
        return base - requiredGoods.count
    }

    /// Java's militaryComparator: by offence plus defence, highest first,
    /// as -1, 0 or 1.
    /// The roles available to a player's units of a type.
    public static func availableRoles(_ player: Player?, _ type: UnitType?, _ roles: [Role]) -> [Role] {
        roles.filter { $0.isAvailableTo([player, type]) }
    }

    public static func compareMilitary(_ a: Role, _ b: Role) -> Int {
        let x = a.offence + a.defence, y = b.offence + b.defence
        return x > y ? -1 : x < y ? 1 : 0
    }

    /// Roles have no colony rules of their own.
    public override func canBeBuiltInColony(_ colony: Colony, _ assumeBuilt: [BuildableType]) -> Colony.NoBuildReason {
        .none
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        downgrade = try spec.flatMap { try xr.getType($0, "downgrade", Role.self) }
        let expertTag = xr.hasAttribute("expertUnit") ? "expertUnit" : "expert-unit"
        expertUnit = try spec.flatMap { try xr.getType($0, expertTag, UnitType.self) }
        maximumCount = xr.attribute(xr.hasAttribute("maximumCount") ? "maximumCount" : "maximum-count",
                                    default: 1)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("downgrade", downgrade)
        xw.writeAttribute("expert-unit", expertUnit)
        if maximumCount > 1 { xw.writeAttribute("maximum-count", maximumCount) }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for rc in roleChangeList ?? [] {
            xw.writeStartElement("role-change")
            xw.writeAttribute("from", id: rc.from)
            xw.writeAttribute("capture", id: rc.capture)
            xw.writeEndElement()
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        roleChangeList = nil
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "role-change" {
            if roleChangeList == nil { roleChangeList = [] }
            roleChangeList!.append(RoleChange(from: xr.attribute("from", default: nil as String?),
                                              capture: xr.attribute("capture", default: nil as String?)))
            try xr.closeTag("role-change")
        } else {
            try super.readChild(xr)
        }
    }
}

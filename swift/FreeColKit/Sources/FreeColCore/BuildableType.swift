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

/// The priorities of goods consumers (common/model/Consumer).
public enum ConsumerPriority {
    public static let population = 300
    public static let colony = 500
    public static let building = 800
    public static let unit = 1000
}

/// Something that can be built in a colony: a building, unit or role
/// (common/model/BuildableType).
///
/// Not yet ported: the build queue index methods (for the UI).
open class BuildableType: FreeColSpecObjectType {

    private static let defaultRequiredPopulation = 1

    /// The colony size needed to build this.
    public var requiredPopulation = BuildableType.defaultRequiredPopulation
    /// In Java's HashMap order, which is the order written.
    private var requiredAbilityMap: JavaHashMap<String, Bool>?
    private var requiredGoodsList: [AbstractGoods]?
    private var limitList: [Limit]?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    /// The abilities required (true) or forbidden (false).
    public var requiredAbilities: [String: Bool] {
        Dictionary(uniqueKeysWithValues: (requiredAbilityMap?.entries ?? []).map { ($0.key, $0.value) })
    }

    /// Whether an ability is required.
    public func requiresAbility(_ key: String) -> Bool {
        requiredAbilityMap?[key] ?? false
    }

    /// Require or forbid an ability.
    public func addRequiredAbility(_ key: String, _ value: Bool) {
        if requiredAbilityMap == nil { requiredAbilityMap = JavaHashMap(javaHash: JavaString.hashCode) }
        _ = requiredAbilityMap!.put(key, value)
    }

    /// Drop an ability requirement.
    public func removeRequiredAbility(_ key: String) {
        _ = requiredAbilityMap?.removeValue(forKey: key)
    }

    /// Whether some objects together meet the ability requirements: for
    /// each, any of them having it must match the requirement.
    public func isAvailableTo(_ objects: [FreeColObject?]) -> Bool {
        guard let requiredAbilityMap else { return true }
        return requiredAbilityMap.entries.allSatisfy { key, value in
            value == objects.contains { $0?.hasAbility(key) ?? false }
        }
    }

    /// Copies of the goods required, in order.
    public var requiredGoods: [AbstractGoods] {
        (requiredGoodsList ?? []).map { AbstractGoods($0.type, $0.amount) }
    }

    /// The amount of a goods type required.
    public func requiredAmount(of type: GoodsType?) -> Int {
        AbstractGoods.count(of: type, in: requiredGoods)
    }

    /// Whether any goods are required.
    public var needsGoodsToBuild: Bool {
        !(requiredGoodsList?.isEmpty ?? true)
    }

    /// The limits on building this.
    public var limits: [Limit] {
        get { limitList ?? [] }
        set { limitList = newValue }
    }

    /// Why a colony can not build this, beyond the general rules
    /// Colony.getNoBuildReason checks, assuming some things are built.
    open func canBeBuiltInColony(_ colony: Colony, _ assumeBuilt: [BuildableType]) -> Colony.NoBuildReason {
        fatalError("abstract")
    }

    // MARK: Reading XML

    open override func setPartialAttribute(_ name: String, _ value: String) -> Bool {
        if name == "required-population", let v = JavaString.parseInt(value) {
            requiredPopulation = Int(v)
            return true
        }
        return super.setPartialAttribute(name, value)
    }

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        requiredPopulation = xr.attribute("required-population",
                                          default: BuildableType.defaultRequiredPopulation)
    }

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if requiredPopulation > 1 { xw.writeAttribute("required-population", requiredPopulation) }
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for e in requiredAbilityMap?.entries ?? [] {
            xw.writeStartElement("required-ability")
            xw.writeAttribute(FreeColObject.idTag, e.key)
            xw.writeAttribute("value", e.value)
            xw.writeEndElement()
        }
        for goods in requiredGoods {
            xw.writeStartElement("required-goods")
            xw.writeAttribute(FreeColObject.idTag, goods.type)
            xw.writeAttribute("value", goods.amount)
            xw.writeEndElement()
        }
        for limit in limits { limit.toXML(xw) }
    }

    open override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        requiredAbilityMap = nil
        requiredGoodsList = nil
        limitList = nil
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        let spec = specification
        switch xr.localName {
        case "required-ability":
            let id = xr.readId()
            if let id {
                addRequiredAbility(id, xr.attribute("value", default: true))
                spec?.addAbility(id)
            }
            try xr.closeTag("required-ability")
        case "required-goods":
            let type = try spec.flatMap { try xr.getType($0, "id", GoodsType.self) }
            if requiredGoodsList == nil { requiredGoodsList = [] }
            requiredGoodsList!.append(AbstractGoods(type, xr.attribute("value", default: 0)))
            try xr.closeTag("required-goods")
        case Limit.tag:
            let limit = try Limit(xr, specification: spec)
            if limit.leftHandSide.type == nil { limit.leftHandSide.type = id }
            if limitList == nil { limitList = [] }
            limitList!.append(limit)
        default:
            try super.readChild(xr)
        }
    }
}

/// A kind of building (common/model/BuildingType).
///
/// Not yet ported: the build queue index methods (for the UI).
public final class BuildingType: BuildableType, BaseProduction {

    public static let tag = "building-type"

    public private(set) var level = 1
    public private(set) var workPlaces = 3
    public private(set) var minimumSkill = Constants.undefined
    public private(set) var maximumSkill = Constants.infinity
    public private(set) var upkeep = 0
    public private(set) var priority = ConsumerPriority.building
    public private(set) var expertConnectionProduction = 0
    public private(set) var competenceFactor: Float = 1
    public private(set) var rebelFactor: Float = 1
    public private(set) var upgradesFrom: BuildingType?
    public fileprivate(set) var upgradesTo: BuildingType?
    /// The production types, in the order read.
    public private(set) var productionTypes: [ProductionType] = []

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        BuildingType.tag
    }

    /// Why a unit type cannot work here, or .none.
    public func noAddReason(_ unitType: UnitType) -> NoAddReason {
        if workPlaces == 0 { return .capacityExceeded }
        if !unitType.hasSkill { return .missingSkill }
        if unitType.skill < minimumSkill { return .minimumSkill }
        if unitType.skill > maximumSkill { return .maximumSkill }
        return .none
    }

    /// Whether a unit type can work here.
    public func canAdd(_ unitType: UnitType) -> Bool {
        noAddReason(unitType) == .none
    }

    /// The first building in this one's upgrade chain.
    public var firstLevel: BuildingType {
        var b = self
        while let from = b.upgradesFrom { b = from }
        return b
    }

    /// Whether colonies get this building without building it.
    public var isAutomaticBuild: Bool {
        !needsGoodsToBuild && upgradesFrom == nil
    }

    /// Add a production type.
    public func addProductionType(_ pt: ProductionType?) {
        if let pt { productionTypes.append(pt) }
    }

    public func availableProductionTypes(unattended: Bool) -> [ProductionType] {
        availableProductionTypes(unattended: unattended, level: nil)
    }

    /// The production types for attended or unattended work at a level.
    public func availableProductionTypes(unattended: Bool, level: String?) -> [ProductionType] {
        productionTypes.filter { $0.unattended == unattended && $0.appliesTo(level: level) }
    }

    /// The goods type of the first output of the first production type.
    public var producedGoodsType: GoodsType? {
        productionTypes.first?.outputs.first?.type
    }

    /// Whether this building adds defence.
    public var isDefenceType: Bool {
        containsModifierKey(Modifier.defence)
    }

    /// Whether goods can be produced here, by a unit or unattended.
    public func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        goodsType != nil && ProductionType.canProduce(
            goodsType, in: availableProductionTypes(unattended: unitType == nil))
    }

    /// A unit type's modifiers here, with additive ones scaled by the
    /// building's competence factor.
    public func competenceModifiers(_ id: String?, _ unitType: UnitType, turn: Turn?) -> [Modifier] {
        let mods = unitType.modifiers(id, for: self, turn: turn)
        guard competenceFactor != 1 else { return mods }
        return mods.map { m in
            guard m.type == .additive else { return m }
            let scaled = Modifier(copying: m)
            scaled.value = m.value * competenceFactor
            return scaled
        }
    }

    /// A building needs the level below it, built or assumed built.
    public override func canBeBuiltInColony(_ colony: Colony, _ assumeBuilt: [BuildableType]) -> Colony.NoBuildReason {
        if let colonyBuilding = colony.building(self) {
            // The family is there: this must be its next level.
            let next = colonyBuilding.type?.upgradesTo
            if next !== self && !assumeBuilt.contains(where: { $0 === next }) { return .wrongUpgrade }
        } else if let from = upgradesFrom, !assumeBuilt.contains(where: { $0 === from }) {
            // Build the lower level first.
            return .wrongUpgrade
        }
        return .none
    }

    /// Java's ordering of building types: by list index, then id.
    public static func compare(_ a: BuildingType, _ b: BuildingType) -> Int {
        let c = a.index - b.index
        return c != 0 ? (c < 0 ? -1 : 1) : FreeColObject.compareIds(a, b)
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        let parent = try spec.flatMap { try xr.getAlreadyInitializedType($0, "extends", BuildingType.self) } ?? self
        let fromTag = xr.hasAttribute("upgradesFrom") ? "upgradesFrom" : "upgrades-from"
        upgradesFrom = try spec.flatMap { try xr.getType($0, fromTag, BuildingType.self) }
        if let upgradesFrom {
            upgradesFrom.upgradesTo = self
            level = upgradesFrom.level + 1
        } else {
            level = 1
        }
        workPlaces = xr.attribute("workplaces", default: parent.workPlaces)
        minimumSkill = xr.attribute(xr.hasAttribute("minSkill") ? "minSkill" : "minimum-skill",
                                    default: parent.minimumSkill)
        maximumSkill = xr.attribute(xr.hasAttribute("maxSkill") ? "maxSkill" : "maximum-skill",
                                    default: parent.maximumSkill)
        upkeep = xr.attribute("upkeep", default: parent.upkeep)
        priority = xr.attribute("priority", default: parent.priority)
        expertConnectionProduction = xr.attribute("experts-with-connections-production",
                                                  default: parent.expertConnectionProduction)
        competenceFactor = xr.attribute("competence-factor", default: parent.competenceFactor)
        rebelFactor = xr.attribute("rebel-factor", default: parent.rebelFactor)
        if parent !== self {
            if !xr.hasAttribute("required-population") {
                requiredPopulation = parent.requiredPopulation
            }
            addFeatures(of: parent)
            if parent.isAbstractType {
                featureContainer?.replaceSource(parent, self)
            }
        }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("upgrades-from", upgradesFrom)
        xw.writeAttribute("workplaces", workPlaces)
        if minimumSkill != Constants.undefined { xw.writeAttribute("minimum-skill", minimumSkill) }
        if maximumSkill < Constants.infinity { xw.writeAttribute("maximum-skill", maximumSkill) }
        if upkeep > 0 { xw.writeAttribute("upkeep", upkeep) }
        if priority != ConsumerPriority.building { xw.writeAttribute("priority", priority) }
        xw.writeAttribute("experts-with-connections-production", expertConnectionProduction)
        xw.writeAttribute("competence-factor", competenceFactor)
        xw.writeAttribute("rebel-factor", rebelFactor)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for productionType in productionTypes { productionType.toXML(xw) }
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == ProductionType.tag {
            if xr.attribute("delete", default: false) {
                productionTypes = []
                try xr.closeTag(ProductionType.tag)
            } else {
                addProductionType(try ProductionType(xr, specification: specification))
            }
        } else {
            try super.readChild(xr)
        }
        if expertConnectionProduction == 0 && hasAbility(Ability.expertsUseConnections) {
            expertConnectionProduction = 4
        }
    }
}

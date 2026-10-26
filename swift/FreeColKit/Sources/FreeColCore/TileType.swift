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

/// Something that produces goods from production types
/// (common/model/BaseProduction).
public protocol BaseProduction: AnyObject {
    /// The production types that apply, attended or unattended.
    func availableProductionTypes(unattended: Bool) -> [ProductionType]
}

extension BaseProduction {
    /// The basic amount of goods produced by a production type, or by the
    /// best available one.
    public func baseProduction(_ productionType: ProductionType?, _ goodsType: GoodsType?,
                               _ unitType: UnitType?) -> Int {
        guard let goodsType else { return 0 }
        let pt = productionType ?? ProductionType.bestProductionType(
            goodsType, in: availableProductionTypes(unattended: unitType == nil))
        return pt?.output(of: goodsType)?.amount ?? 0
    }
}

/// A kind of terrain (common/model/TileType).
///
/// Not yet ported: the WATER and LAND marker types the map generator
/// uses, which come with the map.
public final class TileType: FreeColSpecObjectType, BaseProduction {

    public static let tag = "tile-type"

    /// The kinds of map generator range.
    public enum RangeType: JavaEnum {
        case humidity, temperature, altitude
        public var javaName: String {
            switch self {
            case .humidity: "HUMIDITY"
            case .temperature: "TEMPERATURE"
            case .altitude: "ALTITUDE"
            }
        }
    }

    public static let hillsAltitude = 15
    public static let mountainsAltitude = 25

    public private(set) var isForested = false
    public private(set) var isWater = false
    public private(set) var canSettle = false
    public private(set) var isHighSeasConnected = false
    public private(set) var isElevation = false
    public private(set) var basicMoveCost = 1
    public private(set) var basicWorkTurns = 1
    private var humidity = [0, 0]
    private var temperature = [0, 0]
    private var altitude = [0, 0]
    private var resourceChoices: [RandomChoice<ResourceType>]?
    private var disasterChoices: [RandomChoice<Disaster>]?
    /// The production types, in the order read.
    public private(set) var productionTypes: [ProductionType] = []

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        TileType.tag
    }

    /// Whether ships can sail to Europe from here.
    public var isDirectlyHighSeasConnected: Bool {
        hasAbility(Ability.moveToEurope)
    }

    /// Whether the altitude range includes hills.
    public var isHills: Bool {
        altitude[0] <= TileType.hillsAltitude && altitude[1] >= TileType.hillsAltitude
    }

    /// Whether the altitude range includes mountains.
    public var isMountains: Bool {
        altitude[0] <= TileType.mountainsAltitude && altitude[1] >= TileType.mountainsAltitude
    }

    /// The tile type methods scopes can name.  The rules use isWater
    /// and isForested.
    public override func scopeMethodValue(_ methodName: String) -> String? {
        switch methodName {
        case "isWater": "\(isWater)"
        case "isForested": "\(isForested)"
        case "isElevation": "\(isElevation)"
        case "canSettle": "\(canSettle)"
        case "isHighSeasConnected": "\(isHighSeasConnected)"
        case "isDirectlyHighSeasConnected": "\(isDirectlyHighSeasConnected)"
        case "isHills": "\(isHills)"
        case "isMountains": "\(isMountains)"
        case "getBasicMoveCost": "\(basicMoveCost)"
        case "getBasicWorkTurns": "\(basicWorkTurns)"
        default: super.scopeMethodValue(methodName)
        }
    }

    /// Whether a value is within one of the map generator ranges.
    public func withinRange(_ rangeType: RangeType, _ value: Int) -> Bool {
        let range: [Int]
        switch rangeType {
        case .humidity: range = humidity
        case .temperature: range = temperature
        case .altitude: range = altitude
        }
        return range[0] <= value && value <= range[1]
    }

    /// The possible resources, with their weights.
    public var resourceTypes: [RandomChoice<ResourceType>] {
        resourceChoices ?? []
    }

    /// The possible resource types.
    public var resourceTypeValues: [ResourceType] {
        resourceTypes.map(\.object)
    }

    /// Whether a resource can occur here.
    public func canHaveResourceType(_ type: ResourceType) -> Bool {
        resourceTypeValues.contains { $0 === type }
    }

    /// The possible disasters, with their weights.
    public var disasters: [RandomChoice<Disaster>] {
        disasterChoices ?? []
    }

    /// The production types for attended or unattended work at the
    /// production level the game options set.
    public func availableProductionTypes(unattended: Bool) -> [ProductionType] {
        availableProductionTypes(unattended: unattended,
                                 level: specification?.getString("model.option.tileProduction"))
    }

    /// The production types for attended or unattended work at a level:
    /// those for exactly that level if there are any, otherwise those
    /// that apply to it.
    public func availableProductionTypes(unattended: Bool, level: String?) -> [ProductionType] {
        var good: [ProductionType] = [], better: [ProductionType] = []
        for pt in productionTypes where pt.unattended == unattended {
            if pt.appliesExactly(level: level) {
                better.append(pt)
            } else if pt.appliesTo(level: level) {
                good.append(pt)
            }
        }
        return better.isEmpty ? good : better
    }

    /// Whether goods can be produced here, by a unit or unattended.
    public func canProduce(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Bool {
        goodsType != nil && ProductionType.canProduce(
            goodsType, in: availableProductionTypes(unattended: unitType == nil))
    }

    /// The production of goods here by a unit (or unattended, for nil),
    /// with the unit's modifiers, never negative.
    public func potentialProduction(_ goodsType: GoodsType?, _ unitType: UnitType?) -> Int {
        guard let goodsType else { return 0 }
        var amount = baseProduction(nil, goodsType, unitType)
        if let unitType {
            amount = Int(JavaMath.toInt(unitType.apply(Float(amount), turn: nil,
                                                       goodsType.id, for: unitType)))
        } else {
            // Java notes that a tile type's own modifiers are always
            // empty here.
            amount = Int(JavaMath.toInt(apply(Float(amount), turn: nil, goodsType.id)))
        }
        return max(amount, 0)
    }

    /// All goods that can be produced here.
    public func possibleProduction(unattended: Bool) -> [AbstractGoods] {
        availableProductionTypes(unattended: unattended).flatMap(\.outputs)
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        basicMoveCost = xr.attribute("basic-move-cost", default: 1)
        basicWorkTurns = xr.attribute("basic-work-turns", default: 1)
        isForested = xr.attribute("is-forest", default: false)
        isWater = xr.attribute("is-water", default: false)
        isElevation = xr.attribute("is-elevation", default: false)
        canSettle = xr.attribute("can-settle", default: !isWater)
        isHighSeasConnected = xr.attribute("is-connected", default: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("basic-move-cost", basicMoveCost)
        xw.writeAttribute("basic-work-turns", basicWorkTurns)
        xw.writeAttribute("is-forest", isForested)
        xw.writeAttribute("is-water", isWater)
        xw.writeAttribute("is-elevation", isElevation)
        xw.writeAttribute("is-connected", isHighSeasConnected)
        xw.writeAttribute("can-settle", canSettle)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        xw.writeStartElement("gen")
        xw.writeAttribute("humidity-minimum", humidity[0])
        xw.writeAttribute("humidity-maximum", humidity[1])
        xw.writeAttribute("temperature-minimum", temperature[0])
        xw.writeAttribute("temperature-maximum", temperature[1])
        xw.writeAttribute("altitude-minimum", altitude[0])
        xw.writeAttribute("altitude-maximum", altitude[1])
        xw.writeEndElement()
        for productionType in productionTypes { productionType.toXML(xw) }
        for choice in resourceChoices ?? [] {
            xw.writeStartElement("resource")
            xw.writeAttribute("type", choice.object)
            xw.writeAttribute("probability", choice.probability)
            xw.writeEndElement()
        }
        for choice in disasters {
            xw.writeStartElement("disaster")
            xw.writeAttribute(FreeColObject.idTag, choice.object)
            xw.writeAttribute("probability", choice.probability)
            xw.writeEndElement()
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        disasterChoices = nil
        resourceChoices = nil
        productionTypes = []
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let spec = specification
        let tag = xr.localName
        switch tag {
        case "disaster":
            if let spec, let d = try xr.getType(spec, "id", Disaster.self) {
                if disasterChoices == nil { disasterChoices = [] }
                disasterChoices!.append(RandomChoice(d, xr.attribute("probability", default: 100)))
            }
            try xr.closeTag(tag)
        case "gen":
            // @compat 0.11.3: the camelCase names win where present.
            func pick(_ old: String, _ new: String, _ def: Int) -> Int {
                xr.hasAttribute(old) ? xr.attribute(old, default: def) : xr.attribute(new, default: def)
            }
            humidity = [pick("humidityMin", "humidity-minimum", 0),
                        pick("humidityMax", "humidity-maximum", 100)]
            temperature = [pick("temperatureMin", "temperature-minimum", -20),
                           pick("temperatureMax", "temperature-maximum", 40)]
            altitude = [pick("altitudeMin", "altitude-minimum", 0),
                        pick("altitudeMax", "altitude-maximum", 0)]
            try xr.closeTag(tag)
        case ProductionType.tag where xr.attribute("delete", default: false):
            productionTypes = []
            try xr.closeTag(tag)
        case ProductionType.tag:
            productionTypes.append(try ProductionType(xr, specification: spec))
        case "resource":
            // Java adds the choice even when the type is missing.
            if let spec, let type = try xr.getType(spec, "type", ResourceType.self) {
                if resourceChoices == nil { resourceChoices = [] }
                resourceChoices!.append(RandomChoice(type, xr.attribute("probability", default: 100)))
            }
            try xr.closeTag(tag)
        case "primary-production", "secondary-production":
            // @compat 0.10.x: production written as two attributes.
            let type = try spec.flatMap { try xr.getType($0, "goods-type", GoodsType.self) }
            let pt = ProductionType(input: nil, output: type, amount: xr.attribute("value", default: 0))
            pt.unattended = true
            productionTypes.append(pt)
            try xr.closeTag(tag)
        default:
            try super.readChild(xr)
        }
    }
}

/// A change of terrain that an improvement makes, such as clearing
/// forest, and what it produces (common/model/TileTypeChange).
///
/// These have no identifiers, and Java compares them by identifier, so
/// any two compare equal; that is kept.
public final class TileTypeChange: FreeColSpecObjectType {

    public static let tag = "tile-type-change"

    public private(set) var from: TileType?
    public private(set) var to: TileType?
    /// The goods produced by the change (lumber for clearing forest).
    public private(set) var production: AbstractGoods?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    /// Read a change from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader, specification: Specification?) throws {
        self.init(id: nil, specification: specification)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        TileTypeChange.tag
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        guard let spec = specification else { return }
        from = try xr.getType(spec, "from", TileType.self)
        to = try xr.getType(spec, "to", TileType.self)
    }

    /// No identifier is written.
    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        xw.writeAttribute("from", from)
        xw.writeAttribute("to", to)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if let production {
            xw.writeStartElement("production")
            xw.writeAttribute("goods-type", production.type)
            xw.writeAttribute("value", production.amount)
            xw.writeEndElement()
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        production = nil
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        while try xr.moreTags() {
            guard xr.localName == "production" else {
                throw FreeColXMLError("Bogus TileTypeChange tag: \(xr.localName)")
            }
            let type = try specification.flatMap { try xr.getType($0, "goods-type", GoodsType.self) }
            production = AbstractGoods(type, xr.attribute("value", default: 0))
            try xr.closeTag("production")
        }
    }
}

/// An improvement to a tile, such as a road, plowing or a river
/// (common/model/TileImprovementType).
///
/// Not yet ported: getImprovementValue for a tile.
public final class TileImprovementType: FreeColSpecObjectType {

    public static let tag = "tile-improvement-type"

    public private(set) var isNatural = false
    public private(set) var magnitude = 1
    public private(set) var addWorkTurns = 0
    public private(set) var requiredImprovementType: TileImprovementType?
    public private(set) var requiredRole: Role?
    public private(set) var expendedAmount = 0
    /// The movement cost along the improvement, or 0 for no change.
    public private(set) var moveCost = -1
    public private(set) var exposeResourcePercent = 0
    public var zIndex = 0
    /// The unit types allowed to build this, as Java's HashSet.
    private var allowedWorkers: JavaHashMap<String, Bool>?
    private var changes: [TileTypeChange]?
    private var disasterChoices: [RandomChoice<Disaster>]?

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        TileImprovementType.tag
    }

    /// The movement cost with this improvement, where it is lower.
    public func moveCost(_ originalCost: Int) -> Int {
        (moveCost > 0 && moveCost < originalCost) ? moveCost : originalCost
    }

    /// Whether a unit type may build this improvement.
    public func isWorkerTypeAllowed(_ unitType: UnitType) -> Bool {
        guard let allowedWorkers, !allowedWorkers.isEmpty else { return true }
        return unitType.id.map { allowedWorkers[$0] != nil } ?? false
    }

    /// Whether a unit may build this improvement: its type, and the
    /// role needed, if any.
    public func isWorkerAllowed(_ unit: Unit) -> Bool {
        guard let type = unit.type, isWorkerTypeAllowed(type) else { return false }
        return requiredRole == nil || unit.role === requiredRole
    }

    /// Whether every scope allows a tile type.
    public func isTileTypeAllowed(_ tileType: TileType) -> Bool {
        scopes.allSatisfy { $0.appliesTo(tileType) }
    }

    /// The production bonus for goods, truncated to an int.
    public func bonus(_ goodsType: GoodsType) -> Int {
        productionModifier(goodsType).map { Int(JavaMath.toInt($0.value)) } ?? 0
    }

    /// The first production modifier for goods.
    public func productionModifier(_ goodsType: GoodsType) -> Modifier? {
        modifiers(goodsType.id).first
    }

    /// Whether this improvement changes the tile type.
    public var isChangeType: Bool {
        !(changes?.isEmpty ?? true)
    }

    private func change(from tileType: TileType?) -> TileTypeChange? {
        changes?.first { $0.from === tileType }
    }

    /// The goods produced by changing a tile type.
    public func production(from tileType: TileType?) -> AbstractGoods? {
        change(from: tileType)?.production
    }

    /// The tile type a tile type changes into.
    public func change(_ tileType: TileType?) -> TileType? {
        change(from: tileType)?.to
    }

    /// Whether any change produces a tile type.
    public func changeContainsTarget(_ tileType: TileType?) -> Bool {
        changes?.contains { $0.to === tileType } ?? false
    }

    /// The possible disasters, with their weights.
    public var disasters: [RandomChoice<Disaster>] {
        disasterChoices ?? []
    }

    /// The farmed production gained on a tile type by this improvement.
    public func improvementValue(_ tileType: TileType, _ goodsType: GoodsType,
                                 _ unitType: UnitType?) -> Int {
        guard goodsType.isFarmed else { return 0 }
        let oldProduction = tileType.potentialProduction(goodsType, unitType)
        guard let changed = change(tileType) else {
            let production = tileType.potentialProduction(goodsType, unitType)
            guard production > 0 else { return 0 }
            let chg = apply(Float(production), turn: nil, goodsType.id)
            return Int(JavaMath.toInt(chg - Float(production)))
        }
        return changed.potentialProduction(goodsType, unitType) - oldProduction
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        isNatural = xr.attribute("natural", default: false)
        magnitude = xr.attribute("magnitude", default: 1)
        addWorkTurns = xr.attribute("add-work-turns", default: 0)
        requiredImprovementType = try spec.flatMap {
            try xr.getType($0, "required-improvement", TileImprovementType.self)
        }
        requiredRole = try spec.flatMap { try xr.getType($0, "required-role", Role.self) }
        // @compat 0.10.x
        if xr.hasAttribute("expended-equipment-type") {
            requiredRole = spec?.getRole("model.role.pioneer")
        }
        expendedAmount = xr.attribute("expended-amount", default: 0)
        moveCost = xr.attribute("movement-cost", default: 0)
        zIndex = xr.attribute("zIndex", default: 0)
        exposeResourcePercent = xr.hasAttribute("exposeResourcePercent")
            ? xr.attribute("exposeResourcePercent", default: 0)
            : xr.attribute("expose-resource-percent", default: 0)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("natural", isNatural)
        xw.writeAttribute("magnitude", magnitude)
        xw.writeAttribute("add-work-turns", addWorkTurns)
        xw.writeAttribute("required-improvement", requiredImprovementType)
        xw.writeAttribute("required-role", requiredRole)
        if expendedAmount != 0 { xw.writeAttribute("expended-amount", expendedAmount) }
        xw.writeAttribute("movement-cost", moveCost)
        xw.writeAttribute("zIndex", zIndex)
        xw.writeAttribute("expose-resource-percent", exposeResourcePercent)
    }

    /// The changes are written in Java's HashMap order by the type
    /// changed from (sorting them by value keeps that order, as they
    /// all compare equal).
    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for id in allowedWorkers?.keys ?? [] { xw.writeIdElement("worker", id) }
        if let changes {
            var byFrom = JavaHashMap<TileType?, TileTypeChange>(javaHash: { $0?.javaHashCode ?? 0 })
            for c in changes { _ = byFrom.put(c.from, c) }
            for c in byFrom.values { c.toXML(xw) }
        }
        for choice in disasters {
            xw.writeStartElement("disaster")
            xw.writeAttribute(FreeColObject.idTag, choice.object)
            xw.writeAttribute("probability", choice.probability)
            xw.writeEndElement()
        }
    }

    public override func clearContainers(_ xr: FreeColXMLReader) throws {
        try super.clearContainers(xr)
        allowedWorkers = nil
        changes = nil
        disasterChoices = nil
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let spec = specification
        switch xr.localName {
        case TileTypeChange.tag, "change":
            let c = try TileTypeChange(xr, specification: spec)
            if changes == nil { changes = [] }
            changes!.removeAll { $0.from === c.from }
            changes!.append(c)
        case "disaster":
            if let spec, let d = try xr.getType(spec, "id", Disaster.self) {
                if disasterChoices == nil { disasterChoices = [] }
                disasterChoices!.append(RandomChoice(d, xr.attribute("probability", default: 100)))
            }
            try xr.closeTag("disaster")
        case "worker":
            if let id = xr.readId() {
                if allowedWorkers == nil { allowedWorkers = JavaHashMap(javaHash: JavaString.hashCode) }
                _ = allowedWorkers!.put(id, true)
            }
            try xr.closeTag("worker")
        default:
            try super.readChild(xr)
        }
    }
}

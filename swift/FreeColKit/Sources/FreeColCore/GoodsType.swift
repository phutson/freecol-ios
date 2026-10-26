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

import FreeColXML

/// A kind of goods, such as food, furs or muskets
/// (common/model/GoodsType).
///
/// Some properties are derived from other types after the whole
/// specification is read: whether goods are a building material, and
/// what they are refined into (see `setDerivedAttributes`).
public final class GoodsType: FreeColSpecObjectType {

    public static let tag = "goods-type"

    private static let defaultProductionWeight: Float = 1
    private static let defaultLowProductionThreshold: Float = 0
    private static let defaultZeroProductionFactor: Float = 1

    public private(set) var isFarmed = false
    public private(set) var isFoodType = false
    public private(set) var limitIgnored = false
    public private(set) var isNewWorldGoodsType = false
    /// Whether the goods are military (Java's getMilitary).
    public private(set) var isMilitary = false
    public private(set) var isBuildingMaterial = false
    public private(set) var isTradeGoods = false
    public private(set) var isStorable = true
    private var storedAsType: GoodsType?
    private var madeFrom: GoodsType?
    private var makes: GoodsType?
    public private(set) var initialAmount = 0
    /// The initial sell price in Europe.
    public private(set) var initialSellPrice = 0
    /// The difference between buying and selling prices in Europe.
    public private(set) var priceDifference = 0
    public private(set) var breedingNumber = Constants.infinity
    public var price = Constants.infinity
    public private(set) var productionWeight = GoodsType.defaultProductionWeight
    public private(set) var lowProductionThreshold = GoodsType.defaultLowProductionThreshold
    public private(set) var zeroProductionFactor = GoodsType.defaultZeroProductionFactor

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        GoodsType.tag
    }

    /// Make the goods military (Java's setMilitary).
    public func setMilitary() {
        isMilitary = true
    }

    /// Whether these are luxury goods made from New World goods.
    public var isNewWorldLuxuryType: Bool {
        madeFrom?.isNewWorldGoodsType ?? false
    }

    /// Whether producing these goods adds liberty.
    public var isLibertyType: Bool {
        containsModifierKey(Modifier.liberty)
    }

    /// Whether producing these goods adds immigration.
    public var isImmigrationType: Bool {
        containsModifierKey(Modifier.immigration)
    }

    /// Whether these goods are stored as another type.
    public var isStoredAs: Bool {
        storedAsType != nil
    }

    /// The type these goods are stored as: another type, or this one.
    public var storedAs: GoodsType {
        storedAsType ?? self
    }

    /// Whether other goods are made from these.
    public var isRawMaterial: Bool {
        makes != nil
    }

    /// Whether these goods are made from other goods.
    public var isRefined: Bool {
        madeFrom != nil
    }

    /// What these goods are refined into, if anything.
    public var outputType: GoodsType? {
        makes
    }

    /// What these goods are made from, if anything.
    public var inputType: GoodsType? {
        madeFrom
    }

    /// The initial buying price in Europe.
    public var initialBuyPrice: Int {
        initialSellPrice + priceDifference
    }

    /// Whether the goods breed (horses).
    public var isBreedable: Bool {
        breedingNumber != Constants.infinity
    }

    /// The message key for a unit working on these goods.
    public var workingAsKey: String {
        "\(id ?? "null").workingAs"
    }

    /// These goods and what they are made from, raw materials first.
    public var productionChain: [GoodsType] {
        var result: [GoodsType] = []
        var current: GoodsType? = self
        while let goods = current {
            result.insert(goods, at: 0)
            current = goods.madeFrom
        }
        return result
    }

    /// Whether these are raw goods that are eventually refined into a
    /// building material.
    public var isRawBuildingMaterial: Bool {
        if madeFrom != nil { return false }
        var refined = makes
        while let r = refined {
            if r.isBuildingMaterial { return true }
            refined = r.makes
        }
        return false
    }

    /// Whether these are raw goods eventually refined into a building
    /// material that cannot be stored (hammers).
    public var isRawMaterialForUnstorableBuildingMaterial: Bool {
        if madeFrom != nil { return false }
        var refined = makes
        while let r = refined {
            if r.isBuildingMaterial && !r.isStorable { return true }
            refined = r.makes
        }
        return false
    }

    /// These goods and any stored as them.
    public var equivalentTypes: [GoodsType] {
        (specification?.goodsTypeList ?? []).filter { $0 === self || $0.storedAs === self }
    }

    /// Work out the derived properties of every goods type: building
    /// materials are those required to build anything, and each type
    /// made from another becomes that type's output.
    public static func setDerivedAttributes(_ spec: Specification) {
        for g in spec.goodsTypeList {
            g.isBuildingMaterial = false
            g.makes = nil
        }
        var buildables: [BuildableType] = spec.buildingTypeList
        buildables += spec.unitTypeList as [BuildableType]
        buildables += spec.rolesList as [BuildableType]
        for b in buildables {
            for ag in b.requiredGoods { ag.type?.isBuildingMaterial = true }
        }
        for g in spec.goodsTypeList {
            g.madeFrom?.makes = g
        }
    }

    /// Java's goods ordering rank: food, New World goods, farmed, raw
    /// materials, luxuries, refined; others last.
    private var rank: Int {
        if !isStorable || isTradeGoods { return -1 }
        if isFoodType { return 1 }
        if isNewWorldGoodsType { return 2 }
        if isFarmed { return 3 }
        if isRawMaterial { return 4 }
        if isNewWorldLuxuryType { return 5 }
        if isRefined { return 6 }
        return -1
    }

    /// Order goods types by rank, then id (Java's goodsTypeComparator),
    /// as -1, 0 or 1.
    public static func compare(_ a: GoodsType?, _ b: GoodsType?) -> Int {
        let ra = a?.rank ?? Int.min, rb = b?.rank ?? Int.min
        if ra != rb { return ra < rb ? -1 : 1 }
        return FreeColObject.compareIds(a, b)
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        isFarmed = xr.attribute("is-farmed", default: false)
        isFoodType = xr.attribute("is-food", default: false)
        isMilitary = xr.attribute("is-military", default: false)
        limitIgnored = xr.attribute("ignore-limit", default: false)
        isNewWorldGoodsType = xr.attribute("new-world-goods", default: false)
        isTradeGoods = xr.attribute("trade-goods", default: false)
        breedingNumber = xr.attribute("breeding-number", default: Constants.infinity)
        price = xr.attribute("price", default: Constants.infinity)
        madeFrom = try spec.flatMap { try xr.getType($0, "made-from", GoodsType.self) }
        isStorable = xr.attribute("storable", default: true)
        storedAsType = try spec.flatMap { try xr.getType($0, "stored-as", GoodsType.self) }
        productionWeight = xr.attribute("production-weight", default: GoodsType.defaultProductionWeight)
        lowProductionThreshold = xr.attribute("low-production-threshold",
                                              default: GoodsType.defaultLowProductionThreshold)
        zeroProductionFactor = xr.attribute("zero-production-factor",
                                            default: GoodsType.defaultZeroProductionFactor)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("is-farmed", isFarmed)
        xw.writeAttribute("is-food", isFoodType)
        xw.writeAttribute("is-military", isMilitary)
        xw.writeAttribute("ignore-limit", limitIgnored)
        xw.writeAttribute("new-world-goods", isNewWorldGoodsType)
        xw.writeAttribute("trade-goods", isTradeGoods)
        xw.writeAttribute("storable", isStorable)
        if breedingNumber != Constants.infinity { xw.writeAttribute("breeding-number", breedingNumber) }
        if price != Constants.infinity { xw.writeAttribute("price", price) }
        xw.writeAttribute("made-from", madeFrom)
        xw.writeAttribute("stored-as", storedAsType)
        xw.writeAttribute("production-weight", productionWeight)
        if lowProductionThreshold > GoodsType.defaultLowProductionThreshold {
            xw.writeAttribute("low-production-threshold", lowProductionThreshold)
        }
        if 0 <= zeroProductionFactor && zeroProductionFactor < GoodsType.defaultZeroProductionFactor {
            xw.writeAttribute("zero-production-factor", zeroProductionFactor)
        }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if initialAmount > 0 {
            xw.writeStartElement("market")
            xw.writeAttribute("initial-amount", initialAmount)
            xw.writeAttribute("initial-price", initialSellPrice)
            xw.writeAttribute("price-difference", priceDifference)
            xw.writeEndElement()
        }
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "market" {
            initialAmount = xr.attribute("initial-amount", default: 0)
            initialSellPrice = xr.attribute("initial-price", default: 1)
            priceDifference = xr.attribute("price-difference", default: 1)
            try xr.closeTag("market")
        } else {
            try super.readChild(xr)
        }
    }
}

/// An improvement-like bonus found on a tile, such as game or ore
/// (common/model/ResourceType).
public final class ResourceType: FreeColSpecObjectType {

    public static let tag = "resource-type"

    /// The largest and smallest quantity, or -1 for unlimited.
    public private(set) var maxValue = -1
    public private(set) var minValue = -1

    public required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        ResourceType.tag
    }

    /// The goods type this resource helps most, by initial price times
    /// the bonus on 100 (the first of equal ones).
    public var bestGoodsType: GoodsType? {
        guard let spec = specification else { return nil }
        func value(_ m: Modifier) -> Double {
            Double(spec.getInitialPrice(spec.getGoodsType(m.id))) * Double(m.applyTo(100))
        }
        let best = allModifiers.max { value($0) < value($1) }
        return best.flatMap { spec.getGoodsType($0.id) }
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        maxValue = xr.attribute("maximum-value", default: -1)
        minValue = xr.attribute("minimum-value", default: -1)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if maxValue > -1 {
            xw.writeAttribute("maximum-value", maxValue)
            xw.writeAttribute("minimum-value", minValue)
        }
    }
}

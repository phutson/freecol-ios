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

/// One way a tile or building can produce: some outputs from some
/// inputs, possibly only unattended or at a production level
/// (common/model/ProductionType).
///
/// Inputs and outputs are kept in the order read, as in Java, since
/// choosing the best output keeps the first of equal ones.
public final class ProductionType: FreeColSpecObject {

    public static let tag = "production"

    /// Whether this production happens with nobody working.
    public var unattended = false
    /// The production level this applies at, or nil for all.
    public private(set) var productionLevel: String?
    private var outputList: [AbstractGoods]?
    private var inputList: [AbstractGoods]?

    public override init(specification: Specification?) {
        super.init(specification: specification)
    }

    /// Production from inputs to outputs.
    public init(inputs: [AbstractGoods]?, outputs: [AbstractGoods]?) {
        super.init(specification: nil)
        inputList = inputs
        outputList = outputs
    }

    /// Production of one output.
    public init(output: AbstractGoods, unattended: Bool, level: String?) {
        super.init(specification: nil)
        outputList = [output]
        self.unattended = unattended
        productionLevel = level
    }

    /// Conversion of an amount of one goods type into another.
    public init(input: GoodsType?, output: GoodsType?, amount: Int) {
        super.init(specification: nil)
        if let input { inputList = [AbstractGoods(input, amount)] }
        if let output { outputList = [AbstractGoods(output, amount)] }
    }

    /// Read a production type from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader, specification: Specification?) throws {
        self.init(specification: specification)
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        ProductionType.tag
    }

    /// Whether this applies at a production level: always for no level
    /// on either side, otherwise for the same level.
    public func appliesTo(level: String?) -> Bool {
        level == nil || productionLevel == nil || level == productionLevel
    }

    /// Whether this is specifically for a production level.
    public func appliesExactly(level: String?) -> Bool {
        level != nil && level == productionLevel
    }

    /// The inputs, in order.
    public var inputs: [AbstractGoods] {
        get { inputList ?? [] }
        set { inputList = newValue }
    }

    /// The outputs, in order.
    public var outputs: [AbstractGoods] {
        get { outputList ?? [] }
        set { outputList = newValue }
    }

    /// Add an output.
    public func addOutput(_ goods: AbstractGoods) {
        if outputList == nil { outputList = [] }
        outputList!.append(goods)
    }

    /// The output of a goods type, if any.
    public func output(of type: GoodsType?) -> AbstractGoods? {
        outputList?.first { $0.type === type }
    }

    /// The goods type of the largest output (the first of equal ones).
    public var bestOutputType: GoodsType? {
        outputList?.max { AbstractGoods.compareAscendingAmount($0, $1) < 0 }?.type
    }

    /// Whether any of the production types produce a positive amount of
    /// a goods type.
    public static func canProduce<S: Sequence>(_ type: GoodsType?, in types: S) -> Bool
        where S.Element == ProductionType {
        types.contains { pt in pt.outputs.contains { $0.type === type && $0.amount > 0 } }
    }

    /// The production type with the largest output of a goods type (or
    /// of anything, for nil): the first of equal ones, as Java's maxBy.
    public static func bestProductionType<S: Sequence>(_ type: GoodsType?, in types: S)
        -> ProductionType? where S.Element == ProductionType {
        func amount(_ pt: ProductionType) -> Int {
            pt.bestOutput(for: type)?.amount ?? Int(Int32.min)
        }
        return types.max { amount($0) < amount($1) }
    }

    private func bestOutput(for type: GoodsType?) -> AbstractGoods? {
        outputs.filter { type == nil || $0.type === type }
            .max { AbstractGoods.compareAscendingAmount($0, $1) < 0 }
    }

    // MARK: Reading XML

    /// Production types have no identifiers: unlike other objects, no
    /// id is read.
    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        unattended = xr.attribute("unattended", default: false)
        productionLevel = xr.attribute("production-level", default: nil as String?)
            ?? xr.attribute("productionLevel", default: nil as String?)
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        if inputList != nil { inputList = [] }
        if outputList != nil { outputList = [] }
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        switch tag {
        case "input", "output":
            // Java warns and skips goods it cannot find.
            if let spec = specification,
               let type = try xr.getType(spec, "goods-type", GoodsType.self) {
                let goods = AbstractGoods(type, xr.attribute("value", default: -1))
                if tag == "input" {
                    if inputList == nil { inputList = [] }
                    inputList!.append(goods)
                } else {
                    addOutput(goods)
                }
            }
            try xr.closeTag(tag)
        default:
            try super.readChild(xr)
        }
    }

    /// Production types write no identifier.
    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        if unattended { xw.writeAttribute("unattended", unattended) }
        xw.writeAttribute("production-level", id: productionLevel)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for (tag, list) in [("input", inputs), ("output", outputs)] {
            for goods in list {
                xw.writeStartElement(tag)
                xw.writeAttribute("goods-type", goods.type)
                xw.writeAttribute("value", goods.amount)
                xw.writeEndElement()
            }
        }
    }

    // MARK: FreeColObject

    public override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? ProductionType else { return false }
        return unattended == other.unattended
            && ProductionType.listEquals(outputList, other.outputList)
            && ProductionType.listEquals(inputList, other.inputList)
            && productionLevel == other.productionLevel
            && super.isEqual(to: other)
    }

    /// Java's CollectionUtils.listEquals: both null, or equal elements
    /// in order.
    private static func listEquals(_ a: [AbstractGoods]?, _ b: [AbstractGoods]?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.count == b.count && zip(a, b).allSatisfy { $0 == $1 }
    }

    public override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(unattended)
        hasher.combine(productionLevel)
        for g in outputs { hasher.combine(g) }
        for g in inputs { hasher.combine(g) }
    }

    /// Java's toString.
    public override var description: String {
        var s = "[\(id ?? "null"):"
        if let productionLevel { s += " \(productionLevel)" }
        if unattended { s += " unattended" }
        if !inputs.isEmpty { s += " [inputs: " + inputs.map(\.description).joined(separator: ", ") + "]" }
        if !outputs.isEmpty { s += " [outputs: " + outputs.map(\.description).joined(separator: ", ") + "]" }
        return s + "]"
    }
}

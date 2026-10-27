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
import FreeColServer
import FreeColUtil
import FreeColXML

extension Array where Element: ValuedAIObject {
    /// Sorted by descending value, keeping the order of equals
    /// (ValuedAIObject.descendingValueComparator, with Java's stable
    /// List.sort).
    func sortedByDescendingValue() -> [Element] {
        stableSorted { $0.value > $1.value }
    }
}

/// A plan to produce a goods type at a work location
/// (server/ai/WorkLocationPlan).
final class WorkLocationPlan: AIObject {

    let workLocation: WorkLocation
    var goodsType: GoodsType

    init(_ aiMain: AIMain, _ workLocation: WorkLocation, _ goodsType: GoodsType) {
        self.workLocation = workLocation
        self.goodsType = goodsType
        super.init(aiMain)
        initialized = true
    }

    var isFoodPlan: Bool { goodsType.isFoodType }
}

/// A plan to improve a tile (server/ai/TileImprovementPlan).
final class TileImprovementPlan: ValuedAIObject {

    static let tag = "tileImprovementPlan"

    var type: TileImprovementType?
    private(set) var target: Tile?
    var pioneer: AIUnit?

    init(_ aiMain: AIMain, _ target: Tile, _ type: TileImprovementType, _ value: Int) {
        self.target = target
        self.type = type
        super.init(aiMain, TileImprovementPlan.tag + ":" + aiMain.nextId())
        self.value = value
        initialized = true
    }

    /// A plan referred to in a saved game before it is read.
    init(_ aiMain: AIMain, placeholder id: String) {
        super.init(aiMain, id)
    }

    // MARK: Saving

    override var xmlTag: String { TileImprovementPlan.tag }

    override func setInitialized() {
        initialized = type != nil && target != nil
    }

    override func checkIntegrity(_ fix: Bool) -> Integrity {
        var result = super.checkIntegrity(fix)
        if let pioneer { result = result.combine(pioneer.checkIntegrity(fix)) }
        return type == nil || target == nil ? .fail : result
    }

    /// Only a sound plan is saved.
    override func toXML(_ xw: FreeColXMLWriter) {
        if validate() { super.toXML(xw) }
    }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let type { xw.writeAttribute("type", type) }
        xw.writeAttribute("target", target)
        if let pioneer, pioneer.checkIntegrity(false) == .good { xw.writeAttribute("pioneer", pioneer.unit) }
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        type = xr.attribute("type", default: nil as String?).flatMap { specification?.getTileImprovementType($0) }
        pioneer = xr.hasAttribute("pioneer")
            ? aiMain.reference(xr.attribute("pioneer", default: nil as String?), AIUnit.self) : nil
        target = xr.attribute("target", default: nil as String?).flatMap { game.getFreeColGameObject($0) as? Tile }
    }

    /// The improvement that most raises a goods type's production on a
    /// tile, if any does (getBestTileImprovementType).
    static func bestTileImprovementType(_ tile: Tile, _ goodsType: GoodsType) -> TileImprovementType? {
        guard let spec = tile.specification, let tileType = tile.type else { return nil }
        var best: TileImprovementType?
        var bestValue = Int.min
        for it in spec.tileImprovementTypeList
        where !it.isNatural && it.isTileTypeAllowed(tileType) && it.expendedAmount <= 1
            && tile.tileImprovement(it) == nil {
            // CollectionUtils.maximize keeps the first of equals.
            let v = it.improvementValue(tile, goodsType)
            if best == nil || v > bestValue {
                best = it
                bestValue = v
            }
        }
        guard let best, best.improvementValue(tile, goodsType) > 0 else { return nil }
        return best
    }

    /// Choose the best improvement again for a goods type
    /// (update).
    ///
    /// - Returns: False if no improvement helps.
    func update(_ goodsType: GoodsType) -> Bool {
        guard let target, let type = TileImprovementPlan.bestTileImprovementType(target, goodsType) else {
            return false
        }
        self.type = type
        value = type.improvementValue(target, goodsType)
        return true
    }

    var isComplete: Bool {
        guard let target, let type else { return false }
        return target.hasTileImprovement(type)
    }

    /// Drop a broken plan, or a broken pioneer (validate).
    func validate() -> Bool {
        if type == nil || target == nil {
            dispose()
            return false
        }
        if let pioneer, pioneer.unit.isDisposed { self.pioneer = nil }
        return true
    }

    override func dispose() {
        pioneer = nil
        super.dispose()
    }
}

/// Something a colony wishes for (server/ai/Wish).
class Wish: ValuedAIObject {

    var destination: (any Location)?
    var transportable: TransportableAIObject?

    /// Whether the wish is kept in a saved game.
    var shouldBeStored: Bool { transportable != nil }

    override func checkIntegrity(_ fix: Bool) -> Integrity {
        var result = super.checkIntegrity(fix)
        if let transportable { result = result.combine(transportable.checkIntegrity(fix)) }
        guard let d = destination as? FreeColGameObject, !d.isDisposed else { return .fail }
        return result
    }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let destination {
            xw.writeLocationAttribute("destination", destination)
            if let transportable { xw.writeAttribute("transportable", id: transportable.id) }
        }
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        destination = aiMain.location(xr, "destination")
    }

    var destinationAIColony: AIColony? {
        (destination as? Colony).flatMap { aiMain.aiColony($0) }
    }

    func satisfiedBy(_ unit: Unit) -> Bool { false }
    func satisfiedBy(_ goods: AbstractGoods) -> Bool { false }

    override func dispose() {
        destination = nil
        transportable = nil
        super.dispose()
    }
}

/// A wish for goods (server/ai/GoodsWish).
final class GoodsWish: Wish {

    static let tag = "goodsWish"

    private(set) var goodsType: GoodsType!
    var goodsAmount: Int

    init(_ aiMain: AIMain, _ destination: any Location, _ value: Int, _ amount: Int, _ goodsType: GoodsType) {
        self.goodsType = goodsType
        self.goodsAmount = amount
        super.init(aiMain, GoodsWish.tag + ":" + aiMain.nextId())
        self.destination = destination
        self.value = value
        initialized = amount > 0
    }

    /// A wish referred to in a saved game before it is read.
    init(_ aiMain: AIMain, placeholder id: String) {
        goodsAmount = -1
        super.init(aiMain, id)
    }

    // MARK: Saving

    override var xmlTag: String { GoodsWish.tag }

    override func setInitialized() {
        initialized = goodsType != nil && goodsAmount > 0
    }

    override func checkIntegrity(_ fix: Bool) -> Integrity {
        let result = super.checkIntegrity(fix)
        return goodsType == nil || goodsAmount <= 0 ? .fail : result
    }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("goodsType", goodsType)
        xw.writeAttribute("amountRequested", goodsAmount)
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        transportable = xr.hasAttribute("transportable")
            ? aiMain.reference(xr.attribute("transportable", default: nil as String?), AIGoods.self) : nil
        goodsType = xr.attribute("goodsType", default: nil as String?).flatMap { specification?.getGoodsType($0) }
        goodsAmount = xr.attribute("amountRequested", default: GoodsContainer.cargoSize)
    }

    func update(_ goodsType: GoodsType, _ amount: Int, _ value: Int) {
        self.goodsType = goodsType
        goodsAmount = amount
        self.value = value
        if let transportable { transportable.value += 1 }
    }

    override var shouldBeStored: Bool { true }

    override func satisfiedBy(_ goods: AbstractGoods) -> Bool {
        goods.type === goodsType && goods.amount >= goodsAmount
    }
}

/// A wish for a worker (server/ai/WorkerWish).
final class WorkerWish: Wish {

    static let tag = "workerWish"

    private(set) var unitType: UnitType!
    private(set) var expertNeeded: Bool

    init(_ aiMain: AIMain, _ destination: any Location, _ value: Int, _ unitType: UnitType,
         _ expertNeeded: Bool) {
        self.unitType = unitType
        self.expertNeeded = expertNeeded
        super.init(aiMain, WorkerWish.tag + ":" + aiMain.nextId())
        self.destination = destination
        self.value = value
        initialized = true
    }

    /// A wish referred to in a saved game before it is read.
    init(_ aiMain: AIMain, placeholder id: String) {
        expertNeeded = false
        super.init(aiMain, id)
    }

    // MARK: Saving

    override var xmlTag: String { WorkerWish.tag }

    override func setInitialized() {
        initialized = destination != nil && unitType != nil
    }

    override func checkIntegrity(_ fix: Bool) -> Integrity {
        let result = super.checkIntegrity(fix)
        return unitType == nil ? .fail : result
    }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("unitType", unitType)
        xw.writeAttribute("expertNeeded", expertNeeded)
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        transportable = xr.hasAttribute("transportable")
            ? aiMain.reference(xr.attribute("transportable", default: nil as String?), AIUnit.self) : nil
        unitType = xr.attribute("unitType", default: nil as String?).flatMap { specification?.getUnitType($0) }
        expertNeeded = xr.attribute("expertNeeded", default: false)
    }

    func update(_ unitType: UnitType, _ expertNeeded: Bool, _ value: Int) {
        self.value = value
        self.unitType = unitType
        self.expertNeeded = expertNeeded
        if let transportable { transportable.transportPriority = value }
    }

    override func satisfiedBy(_ unit: Unit) -> Bool {
        expertNeeded ? unit.type === unitType : unit.type?.isNaval == unitType.isNaval
    }
}

/// Goods for the AI to carry somewhere (server/ai/AIGoods).
final class AIGoods: TransportableAIObject {

    static let tag = "aiGoods"

    private(set) var goods: Goods?
    private var destination: (any Location)?

    init(_ aiMain: AIMain, _ location: any Location, _ type: GoodsType, _ amount: Int,
         _ destination: (any Location)?) {
        goods = Goods(game: aiMain.game, location: location, type: type, amount: amount)
        self.destination = destination
        super.init(aiMain, AIGoods.tag + ":" + aiMain.nextId())
        initialized = true
    }

    /// Goods referred to in a saved game before they are read.
    init(_ aiMain: AIMain, placeholder id: String) {
        super.init(aiMain, id)
    }

    // MARK: Saving

    override var xmlTag: String { AIGoods.tag }

    override func setInitialized() {
        initialized = goods != nil
    }

    override func checkIntegrity(_ fix: Bool) -> Integrity {
        var result = super.checkIntegrity(fix)
        var fail = !result.isSafe || goods == nil || goods?.type == nil || (goods?.amount ?? 0) <= 0
            || goods?.location == nil || ((goods?.location as? FreeColGameObject)?.isDisposed ?? false)
        if let d = destination as? FreeColGameObject, d.isDisposed {
            if fix {
                destination = nil
                result = result.fixed()
            } else {
                fail = true
            }
        }
        return fail ? .fail : result
    }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let destination { xw.writeLocationAttribute("destination", destination) }
    }

    override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        goods?.toXML(xw)
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        destination = aiMain.location(xr, "destination")
    }

    override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "goods" {
            if let goods {
                try goods.readFromXML(xr)
            } else {
                goods = try Goods(game: game, reading: xr)
            }
        } else {
            try super.readChild(xr)
        }
    }

    var goodsType: GoodsType? { goods?.type }

    override var transportLocatable: (any Locatable)? { goods }

    override var transportSource: (any Location)? { goods?.location }

    override var transportDestination: (any Location)? {
        get { destination }
        set { destination = newValue }
    }

    /// Whether the goods are fit to keep (checkIntegrity without fixing).
    var isSafe: Bool {
        guard let goods, goods.type != nil, goods.amount > 0, let loc = goods.location,
              !((loc as? FreeColGameObject)?.isDisposed ?? false) else { return false }
        if let d = destination as? FreeColGameObject, d.isDisposed { return false }
        return true
    }

    /// The path for a carrier to take the goods to a destination
    /// (getDeliveryPath).
    override func deliveryPath(_ carrier: Unit, _ dst: (any Location)?) -> PathNode? {
        guard let goods, let dst = dst ?? upLoc(transportDestination) else { return nil }
        let path: PathNode?
        if goods.location === carrier {
            path = carrier.findPath(dst)
        } else if goods.location is Unit {
            path = nil
        } else if let loc = goods.location {
            path = carrier.findPath(loc, dst)
        } else {
            path = nil
        }
        path?.convertToGoodsDeliveryPath()
        return path
    }

    override func carriableBy(_ carrier: Unit) -> Bool {
        guard let goods else { return false }
        return carrier.couldCarry(goods)
    }

    override var canMove: Bool { false }

    override func leaveTransport(_ direction: Direction?) -> Bool {
        direction == nil ? leaveTransport() : false
    }

    /// Load the goods, as many as fit (joinTransport).
    override func joinTransport(_ carrier: Unit, _ direction: Direction?) -> Bool {
        if direction != nil { return false }
        guard let aiCarrier = aiMain.aiUnit(carrier), let goods, let type = goods.type else { return false }
        let amount = min(goods.amount, carrier.loadableAmount(type))
        if aiCarrier.aiOwner?.ask(.loadGoods(location: (goods.location as? FreeColGameObject)?.id, type: type.id,
                                            amount: String(amount), carrier: carrier.id)) == true {
            self.goods = Goods(game: aiMain.game, location: carrier, type: type, amount: amount)
            if let colony = carrier.colony { aiMain.aiColony(colony)?.removeExportGoods(self) }
        }
        return true
    }

    override func invalidReason() -> String? {
        if let reason = Mission.invalidTransportableReason(self) { return reason }
        if let carrier = goods?.location as? Unit, let s = destination as? Settlement,
           !(carrier.owner?.owns(s) ?? false) {
            return "transportableDestination-captured"
        }
        return nil
    }

    /// Unload the goods from their carrier (leaveTransport), all or
    /// nothing.
    override func leaveTransport() -> Bool {
        guard let goods, let carrier = goods.location as? Unit, let type = goods.type else { return false }
        let amount = goods.amount
        let oldAmount = carrier.goodsCount(type)
        if oldAmount < amount { return false }
        guard let aiCarrier = aiMain.aiUnit(carrier),
              aiCarrier.aiOwner?.ask(.unloadGoods(type: type.id, amount: String(amount), carrier: carrier.id)) == true
        else { return false }
        return oldAmount - carrier.goodsCount(type) == amount // Java does not accept partial unloads
    }

    override func dispose() {
        dropTransport()
        if let destination {
            if let c = destination as? Colony { aiMain.aiColony(c)?.removeExportGoods(self) }
            self.destination = nil
        }
        goods = nil
        super.dispose()
    }
}

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

/// The price and trade record of one goods type in a market
/// (common/model/MarketData).
public final class MarketData: FreeColGameObject, GameObjectReadable {

    public static let tag = "marketData"

    public static let minimumPrice = 1
    public static let maximumPrice = 19

    public private(set) var goodsType: GoodsType?
    public var costToBuy = 0
    public var paidForSale = 0
    public var amountInMarket = 0
    public var initialPrice = 0
    public var arrears = 0
    public var sales = 0
    public var incomeBeforeTaxes = 0
    public var incomeAfterTaxes = 0
    public var oldPrice = 0
    public var traded = false

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    /// New market data for a goods type at its initial prices.
    public init(game: Game, goodsType: GoodsType) {
        self.goodsType = goodsType
        paidForSale = goodsType.initialSellPrice
        costToBuy = goodsType.initialBuyPrice
        amountInMarket = goodsType.initialAmount
        initialPrice = goodsType.initialSellPrice
        oldPrice = costToBuy
        super.init(game: game)
    }

    public override var xmlTagName: String {
        MarketData.tag
    }

    /// Set the prices from the amount in the market, limiting how far
    /// they can move at once.
    ///
    /// - Returns: Whether a price changed.
    @discardableResult
    public func price() -> Bool {
        guard let goodsType, goodsType.isStorable else { return false }
        let diff = goodsType.priceDifference
        var amountPrice = Float(initialPrice) * (Float(goodsType.initialAmount) / Float(amountInMarket))
        var newSalePrice = Int(JavaMath.round(amountPrice))
        var newPrice = newSalePrice + diff

        // Work-around to limit prices of new world goods and related
        // manufactured goods.
        if newSalePrice > initialPrice + 2
            && ((goodsType.inputType?.isNewWorldGoodsType ?? false) || goodsType.isNewWorldGoodsType) {
            newSalePrice = initialPrice + 2
            newPrice = newSalePrice + diff
        }

        // Another hack to prevent the price changing too fast in one
        // hit, pushing the amount in the market back as well to keep it
        // stable.
        if costToBuy > 0 {
            if newPrice > costToBuy + diff {
                amountPrice -= Float(newPrice - (costToBuy + diff))
                amountInMarket = Int(JavaMath.round(Float(goodsType.initialAmount)
                    * (Float(initialPrice) / amountPrice)))
                newPrice = costToBuy + diff
            } else if newPrice < costToBuy - diff {
                amountPrice += Float((costToBuy - diff) - newPrice)
                amountInMarket = Int(JavaMath.round(Float(goodsType.initialAmount)
                    * (Float(initialPrice) / amountPrice)))
                newPrice = costToBuy - diff
            }
            newSalePrice = newPrice - diff
        }

        // Clamp extremes.
        if newPrice > MarketData.maximumPrice {
            newPrice = MarketData.maximumPrice
            newSalePrice = newPrice - diff
        } else if newSalePrice < MarketData.minimumPrice {
            newSalePrice = MarketData.minimumPrice
            newPrice = newSalePrice + diff
        }

        let oldCostToBuy = costToBuy, oldPaidForSale = paidForSale
        costToBuy = newPrice
        paidForSale = newSalePrice
        return costToBuy != oldCostToBuy || paidForSale != oldPaidForSale
    }

    /// Set the prices without limiting the change.
    public func update() {
        costToBuy = -1 // Disable price change clamping
        price()
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        goodsType = try specification.flatMap { try xr.getType($0, "goods-type", GoodsType.self) }
        amountInMarket = xr.attribute("amount", default: 0)
        initialPrice = xr.attribute("initialPrice", default: -1)
        arrears = xr.attribute("arrears", default: 0)
        sales = xr.attribute("sales", default: 0)
        incomeBeforeTaxes = xr.attribute("incomeBeforeTaxes", default: 0)
        incomeAfterTaxes = xr.attribute("incomeAfterTaxes", default: 0)
        traded = xr.attribute("traded", default: sales != 0)
        update()
        oldPrice = costToBuy
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("goods-type", goodsType)
        xw.writeAttribute("amount", amountInMarket)
        xw.writeAttribute("initialPrice", initialPrice)
        xw.writeAttribute("arrears", arrears)
        xw.writeAttribute("sales", sales)
        xw.writeAttribute("incomeAfterTaxes", incomeAfterTaxes)
        xw.writeAttribute("incomeBeforeTaxes", incomeBeforeTaxes)
        xw.writeAttribute("traded", traded)
    }

    public override var description: String {
        "[\(id ?? "null") \(goodsType?.id ?? "null") costToBuy=\(costToBuy) paidForSale=\(paidForSale)"
            + " amountInMarket=\(amountInMarket) initialPrice=\(initialPrice) arrears=\(arrears)"
            + " sales=\(sales) incomeBeforeTaxes=\(incomeBeforeTaxes) incomeAfterTaxes=\(incomeAfterTaxes)"
            + " oldPrice=\(oldPrice) traded=\(traded)]"
    }
}

/// A player's market in Europe (common/model/Market).
///
/// The player holds its market, and the market its data; the owner is
/// weak.  Not yet ported: transaction listeners (the user interface)
/// and copyIn.
public final class Market: FreeColGameObject, GameObjectReadable, Ownable {

    public static let tag = "market"

    /// Markets are bottomless: the amount never goes below this.
    public static let minimumAmount = 100

    /// Where goods are traded.
    public enum Access {
        case europe, customHouse
    }

    /// The data for each goods type, in Java's HashMap order.
    private var marketData = JavaHashMap<GoodsType, MarketData>(javaHash: { $0.javaHashCode })

    public weak var owner: Player?

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    /// A new market seeded with the initial amount of each storable
    /// goods type.
    public init(game: Game, owner: Player) {
        self.owner = owner
        super.init(game: game)
        for gt in specification?.storableGoodsTypeList ?? [] {
            marketData.put(gt, MarketData(game: game, goodsType: gt))
        }
    }

    public override var xmlTagName: String {
        Market.tag
    }

    /// All the market data, in Java's HashMap order.
    public var marketDataValues: [MarketData] {
        marketData.values
    }

    public func marketData(_ goodsType: GoodsType) -> MarketData? {
        marketData[goodsType]
    }

    private func requireMarketData(_ goodsType: GoodsType) -> MarketData {
        if let data = marketData[goodsType] { return data }
        let data = MarketData(game: game!, goodsType: goodsType)
        marketData.put(goodsType, data)
        return data
    }

    public func hasBeenTraded(_ type: GoodsType) -> Bool {
        marketData[type]?.traded ?? false
    }

    public func costToBuy(_ type: GoodsType) -> Int {
        marketData[type]?.costToBuy ?? 0
    }

    public func paidForSale(_ type: GoodsType) -> Int {
        marketData[type]?.paidForSale ?? 0
    }

    /// Add goods to the market (or remove them, with a negative amount)
    /// and reprice.
    ///
    /// - Returns: Whether the price changed.
    @discardableResult
    public func addGoodsToMarket(_ goodsType: GoodsType, _ amount: Int) -> Bool {
        let data = requireMarketData(goodsType)
        data.amountInMarket = max(Market.minimumAmount, data.amountInMarket + amount)
        data.traded = true
        return data.price()
    }

    public func initialPrice(_ goodsType: GoodsType) -> Int {
        requireMarketData(goodsType).initialPrice
    }

    public func setInitialPrice(_ goodsType: GoodsType, _ amount: Int) {
        requireMarketData(goodsType).initialPrice = amount
    }

    /// The price to buy an amount of goods.
    public func bidPrice(_ type: GoodsType, _ amount: Int) -> Int {
        guard let data = marketData[type] else { return 0 }
        return amount * data.costToBuy
    }

    /// The price paid for selling an amount of goods.
    public func salePrice(_ type: GoodsType, _ amount: Int) -> Int {
        guard let data = marketData[type] else { return 0 }
        return amount * data.paidForSale
    }

    public func salePrice(_ goods: AbstractGoods) -> Int {
        goods.type.map { salePrice($0, goods.amount) } ?? 0
    }

    public func arrears(_ goodsType: GoodsType) -> Int {
        marketData[goodsType]?.arrears ?? 0
    }

    public func setArrears(_ goodsType: GoodsType, _ value: Int) {
        requireMarketData(goodsType).arrears = value
    }

    public func sales(_ goodsType: GoodsType) -> Int {
        marketData[goodsType]?.sales ?? 0
    }

    public func modifySales(_ goodsType: GoodsType, _ amount: Int) {
        guard amount != 0 else { return }
        let data = requireMarketData(goodsType)
        data.sales += amount
        data.traded = true
    }

    public func incomeBeforeTaxes(_ goodsType: GoodsType) -> Int {
        marketData[goodsType]?.incomeBeforeTaxes ?? 0
    }

    public func modifyIncomeBeforeTaxes(_ goodsType: GoodsType, _ amount: Int) {
        requireMarketData(goodsType).incomeBeforeTaxes += amount
    }

    public func incomeAfterTaxes(_ goodsType: GoodsType) -> Int {
        marketData[goodsType]?.incomeAfterTaxes ?? 0
    }

    public func modifyIncomeAfterTaxes(_ goodsType: GoodsType, _ amount: Int) {
        requireMarketData(goodsType).incomeAfterTaxes += amount
    }

    public func amountInMarket(_ goodsType: GoodsType) -> Int {
        marketData[goodsType]?.amountInMarket ?? 0
    }

    /// Whether the buying price has changed since it was last flushed.
    public func hasPriceChanged(_ goodsType: GoodsType) -> Bool {
        guard let data = marketData[goodsType] else { return false }
        return data.oldPrice != 0 && data.oldPrice != data.costToBuy
    }

    public func flushPriceChange(_ goodsType: GoodsType) {
        if let data = marketData[goodsType] { data.oldPrice = data.costToBuy }
    }

    /// The message that a price has changed, or nil if it has not.
    public func priceChangeMessage(_ goodsType: GoodsType) -> ModelMessage? {
        guard let data = marketData(goodsType), data.oldPrice != data.costToBuy, let owner else { return nil }
        let newPrice = data.costToBuy
        return ModelMessage(.marketPrices, newPrice > data.oldPrice ? "model.market.priceIncrease"
                                : "model.market.priceDecrease", self, goodsType)
            .addStringTemplate("%market%", owner.marketName).addNamed("%goods%", goodsType)
            .addAmount("%buy%", newPrice).addAmount("%sell%", data.paidForSale)
    }

    /// Reprice without limiting the change.
    public func update(_ goodsType: GoodsType) {
        requireMarketData(goodsType).update()
    }

    /// Java's getSalePriceComparator: by sale price, highest first, as
    /// a three-way comparison.
    public func compareSalePrice(_ a: AbstractGoods, _ b: AbstractGoods) -> Int {
        let pa = salePrice(a), pb = salePrice(b)
        return pa > pb ? -1 : pa < pb ? 1 : 0
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        owner = try xr.findFreeColGameObject(game!, "owner", Player.self, required: true)
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        marketData.removeAll()
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == MarketData.tag {
            if let data = try xr.readFreeColObject(game!, MarketData.self), let gt = data.goodsType {
                marketData.put(gt, data)
            }
        } else {
            try super.readChild(xr)
        }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("owner", owner)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if xw.validFor(owner) {
            for data in sortedById(marketData.values) { data.toXML(xw) }
        }
    }

    /// Java's toString, with the data in identifier order.
    public override var description: String {
        "[\(id ?? "null") owner=\(owner?.id ?? "null")"
            + marketData.values.sorted { JavaString.compare($0.id ?? "", $1.id ?? "") < 0 }
                .map { " \($0)" }.joined() + "]"
    }
}

/// The price goods last sold for somewhere (common/model/LastSale).
/// Its identifier is "<goods type id>-<location id>".
public final class LastSale: FreeColObject {

    public static let tag = "lastSale"

    public private(set) var when: Turn?
    public private(set) var price = 0

    public init(id: String, when: Turn, price: Int) {
        super.init()
        self.id = id
        self.when = when
        self.price = price
    }

    public convenience init(_ location: any Location, _ what: GoodsType, when: Turn, price: Int) {
        self.init(id: LastSale.makeKey(location, what), when: when, price: price)
    }

    /// Read a sale from the element the reader is on.
    public init(_ xr: FreeColXMLReader) throws {
        super.init()
        try readFromXML(xr)
    }

    public static func makeKey(_ location: any Location, _ what: GoodsType) -> String {
        "\(what.id ?? "null")-\(location.id ?? "null")"
    }

    public override var xmlTagName: String {
        LastSale.tag
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        when = Turn(xr.attribute("when", default: 0))
        price = xr.attribute("price", default: 0)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("when", when?.number ?? 0)
        xw.writeAttribute("price", price)
    }

    public override var description: String {
        "[\(id ?? "null") when=\(when.map { "\($0)" } ?? "null") price=\(price)]"
    }
}

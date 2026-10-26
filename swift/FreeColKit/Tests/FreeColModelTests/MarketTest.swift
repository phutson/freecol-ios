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
import Testing

/// MarketTest.java.  Java's serialization and transaction listener
/// tests are empty.
@Suite(.serialized)
struct MarketTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    /// The initial prices come from the specification.
    @Test func initialMarket() throws {
        let g = FreeColTestCase.standardGame(spec)
        let p = try #require(g.player(byNationId: "model.nation.dutch"))
        let dm = try #require(p.market)
        for good in spec.storableGoodsTypeList {
            #expect(dm.costToBuy(good) == good.initialBuyPrice, "\(good)")
            #expect(dm.paidForSale(good) == good.initialSellPrice, "\(good)")
        }
    }

    @Test func europeMarketPricing() throws {
        let g = FreeColTestCase.standardGame(spec)
        let p = try #require(g.player(byNationId: "model.nation.dutch"))
        let eu = try #require(p.europe)
        let market = try #require(p.market)
        for good in spec.goodsTypeList {
            #expect(eu.owner?.market?.salePrice(good, 1) == market.salePrice(good, 1))
            let bidPrice = market.bidPrice(good, 1)
            let buyCost = market.costToBuy(good)
            #expect(bidPrice == buyCost)
            #expect(try eu.priceGoods([AbstractGoods(good, 1)]) == buyCost)
        }
    }
}

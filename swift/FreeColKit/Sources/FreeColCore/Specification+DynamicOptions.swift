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

extension Specification {
    /// The options made for a new game (generateDynamicOptions): each
    /// goods type's range of starting prices, or its fixed price, in a
    /// new game options group.
    public func generateDynamicOptions() {
        let prices = OptionGroup(id: GameOptions.gameoptionsPrices, specification: self)
        allOptionGroups.put(prices.id ?? "", prices)
        func add(_ id: String, _ value: Int) {
            let option = IntegerOption(id: id, specification: self)
            option.setValue(value)
            option.minimumValue = 1
            option.maximumValue = 100
            prices.add(option)
            addAbstractOption(option)
        }
        for goodsType in goodsTypeList {
            let name = goodsType.suffix(afterPrefix: "model.goods.") ?? goodsType.id ?? ""
            let base = "model.option." + name + "."
            if goodsType.initialSellPrice > 0 {
                let diff = goodsType.isNewWorldGoodsType || goodsType.isNewWorldLuxuryType ? 3 : 0
                add(base + "minimumPrice", goodsType.initialSellPrice)
                add(base + "maximumPrice", goodsType.initialSellPrice + diff)
                add(base + "spread", goodsType.priceDifference)
            } else if goodsType.price < Constants.infinity {
                add(base + "price", goodsType.price)
            }
        }
        gameOptions?.add(prices)
    }
}

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

// The prices and trade values that need a player's market: the
// evaluateFor methods of AbstractGoods, WorkLocation, Building,
// ColonyTile and Colony, and the price of finishing a build.

/// Java's Integer.MIN_VALUE, which evaluateFor uses for "never".
private let minValue = Int(Int32.min)

extension AbstractGoods {
    /// What the goods would sell for in the player's market (or twice
    /// the amount without one).
    public func evaluateFor(_ player: Player) -> Int {
        guard let market = player.market else { return amount * 2 }
        return type.map { market.salePrice($0, amount) } ?? 0
    }
}

extension WorkLocation {
    /// The value of the units here, plus a building's own goods or a
    /// colony tile's production.
    public func evaluateFor(_ player: Player) -> Int {
        var result = 0
        for u in unitList {
            let v = u.evaluateFor(player)
            if v == minValue { result = minValue; break }
            result += v
        }
        if let building = self as? Building {
            return result + (building.type?.requiredGoods ?? []).reduce(0) { $0 + $1.evaluateFor(player) }
        }
        if self is ColonyTile {
            return result + production.reduce(0) { $0 + $1.evaluateFor(player) }
        }
        return result
    }
}

extension Colony {

    /// The price of the goods still needed for what is being built.
    public var priceForBuilding: Int {
        currentlyBuilding.map(priceForBuilding) ?? 0
    }

    public func priceForBuilding(_ type: BuildableType) -> Int {
        priceGoodsForBuilding(requiredGoods(type))
    }

    /// The price of goods to finish a build: storable goods at 110% of
    /// the market's price, others at their own price.
    public func priceGoodsForBuilding(_ required: [AbstractGoods]) -> Int {
        let market = owner?.market
        return required.reduce(0) { sum, ag in
            guard let type = ag.type else { return sum }
            return sum + (type.isStorable
                ? ((market?.bidPrice(type, ag.amount) ?? 0) * 110) / 100
                : type.price * ag.amount)
        }
    }

    public var canPayToFinishBuilding: Bool {
        canPayToFinishBuilding(currentlyBuilding)
    }

    public func canPayToFinishBuilding(_ buildableType: BuildableType?) -> Bool {
        guard let buildableType, let owner else { return false }
        return owner.checkGold(priceForBuilding(buildableType))
    }

    /// The colony's value to a player: its work, units and goods if
    /// ours, otherwise a guess from its size, land and stockade.
    public func evaluateFor(_ player: Player) -> Int {
        if player.isAI && player.owns(self) && player.settlementCount < Colony.tradeMargin {
            return minValue
        }
        var result = 0
        if player.owns(self) {
            for wl in availableWorkLocations {
                let v = wl.evaluateFor(player)
                if v == minValue { return minValue }
                result += v
            }
            for u in tile?.unitList ?? [] {
                let v = u.evaluateFor(player)
                if v == minValue { return minValue }
                result += v
            }
            for g in compactGoodsList {
                let v = g.evaluateFor(player)
                if v == minValue { return minValue }
                result += v
            }
        } else { // Much guesswork
            result = apparentUnitCount * 1000
                + 500 // Some useful goods?
                + 200 * (tile?.surroundingTiles(0, 1).filter { $0.owningSettlement === self }.count ?? 0)
            if let stockade { result *= stockade.level }
        }
        return result
    }
}

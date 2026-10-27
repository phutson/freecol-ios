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

extension Array {
    /// A stable sort, as Java's List.sort is.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            areInIncreasingOrder(a.element, b.element) ? true
                : areInIncreasingOrder(b.element, a.element) ? false : a.offset < b.offset
        }.map(\.element)
    }
}

extension Settlement {
    /// Java's Settlement.getDefenceRatio, which each kind answers.
    var settlementDefenceRatio: Double {
        if let c = self as? Colony { return c.defenceRatio }
        if let s = self as? IndianSettlement { return s.defenceRatio }
        return 0
    }

    /// Java's Settlement.isBadlyDefended, which each kind answers.
    var settlementIsBadlyDefended: Bool {
        if let c = self as? Colony { return c.isBadlyDefended }
        if let s = self as? IndianSettlement { return s.isBadlyDefended }
        return false
    }

    /// Java's Settlement.calculateSettlementValue, which each kind
    /// answers.
    func settlementValue(_ value: Int, _ unit: Unit) -> Int {
        if let c = self as? Colony { return c.calculateSettlementValue(value, unit) }
        if let s = self as? IndianSettlement { return s.calculateSettlementValue(value, unit) }
        return value
    }
}

extension NativeTradeItem {
    /// Whether the goods are Java-equal to another item's (goodsMatcher).
    func goodsMatches(_ other: NativeTradeItem) -> Bool {
        Goods.javaEquals(goods, other.goods)
    }
}

/// A set in Java's HashSet order (a HashMap's keys).
struct JavaHashSet<T: Hashable> {
    private var map: JavaHashMap<T, Bool>

    init(javaHash: @escaping (T) -> Int32) {
        map = JavaHashMap(javaHash: javaHash)
    }

    mutating func insert(_ element: T) {
        if map[element] == nil { _ = map.put(element, true) }
    }

    @discardableResult
    mutating func remove(_ element: T) -> Bool {
        map.removeValue(forKey: element) != nil
    }

    func contains(_ element: T) -> Bool {
        map[element] != nil
    }

    mutating func removeAll() {
        map.removeAll()
    }

    /// The elements in Java's iteration order.
    var elements: [T] { map.keys }
}

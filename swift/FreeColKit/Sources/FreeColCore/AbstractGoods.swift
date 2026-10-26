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

/// An amount of a goods type, not belonging to anything
/// (common/model/AbstractGoods).  Its id is the goods type's id.
///
/// The label and evaluateFor are in Labels.swift and Valuation.swift.
open class AbstractGoods: FreeColObject, Named {

    /// The goods type.
    public var type: GoodsType?
    /// The amount.
    public var amount: Int

    public init(_ type: GoodsType?, _ amount: Int) {
        self.type = type
        self.amount = amount
        super.init()
        id = type?.id
    }

    /// A copy of another amount of goods.
    public convenience init(copying other: AbstractGoods) {
        self.init(other.type, other.amount)
    }

    open override var xmlTagName: String {
        "abstractGoods"
    }

    /// Whether the goods are food.
    public final var isFoodType: Bool {
        type?.isFoodType ?? false
    }

    /// Whether there is a positive amount.
    public final var isPositive: Bool {
        amount > 0
    }

    /// Whether the goods can be stored.
    open var isStorable: Bool {
        type?.isStorable ?? false
    }

    /// The amount of a goods type in a list, or 0.
    public static func count<S: Sequence>(of type: GoodsType?, in goods: S) -> Int
        where S.Element: AbstractGoods {
        goods.first { $0.type === type }?.amount ?? 0
    }

    /// Order by amount, then by goods type order (Java's
    /// ascendingAmountComparator), as -1, 0 or 1.
    public static func compareAscendingAmount(_ a: AbstractGoods, _ b: AbstractGoods) -> Int {
        if a.amount != b.amount { return a.amount < b.amount ? -1 : 1 }
        return GoodsType.compare(a.type, b.type)
    }

    /// Order by amount, most first, then by goods type order (Java's
    /// descendingAmountComparator), as -1, 0 or 1.
    public static func compareDescendingAmount(_ a: AbstractGoods, _ b: AbstractGoods) -> Int {
        if a.amount != b.amount { return a.amount > b.amount ? -1 : 1 }
        return GoodsType.compare(a.type, b.type)
    }

    // MARK: Named

    public var nameKey: String {
        type?.nameKey ?? "null.name"
    }

    // MARK: FreeColObject

    /// Equal amounts of the same goods type object, with the same id.
    open override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? AbstractGoods else { return false }
        return type === other.type && amount == other.amount && super.isEqual(to: other)
    }

    open override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(type.map(ObjectIdentifier.init))
        hasher.combine(amount)
    }

    /// Java's toString: "<amount> <goods suffix>".
    open override var description: String {
        AbstractGoods.fullString(type, amount)
    }

    /// Java's toFullString.
    public static func fullString(_ type: GoodsType?, _ amount: Int) -> String {
        "\(amount) \(type.flatMap { $0.suffix } ?? "(null)")"
    }
}

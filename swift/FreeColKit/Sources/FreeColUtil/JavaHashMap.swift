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

/// A map that iterates in the same order as `java.util.HashMap`.
///
/// Java code often loops over a HashMap, and where that order affects
/// a result (a list written out, random numbers drawn in turn), a port
/// must loop in the same order.  Java's order follows from the keys'
/// hashCode values, the table size and the order of insertion, so it
/// is reproduced here from a Java hash code supplied for each key.
///
/// Emulated, as in JDK 18: the default table of 16 created on first
/// insertion (or the requested initial capacity), the hash spreading
/// (h ^ h >>> 16), doubling when the size passes 0.75 of the capacity
/// (keeping order within split buckets), presizing for putAll and copies
/// (which can give a table smaller than 16), and resizing a small table
/// instead of turning a long bucket into a tree.  Not emulated: tree
/// bins, which Java only builds for 9 or more colliding keys in a table
/// of at least 64; that case traps.  JDK 19 changed the presizing
/// arithmetic, so maps filled by putAll can iterate differently there.
public struct JavaHashMap<Key: Hashable, Value> {

    private struct Entry {
        let key: Key
        let hash: Int32
        var value: Value
    }

    private let javaHash: (Key) -> Int32
    private var table: [[Entry]] = []
    /// The same entries by key, for lookups without computing Java's
    /// hash code, which is slow for Swift strings.
    private var index: [Key: Value] = [:]
    private var threshold = 0
    public private(set) var count = 0

    /// Create an empty map, like `new HashMap<>()`.
    ///
    /// - Parameter javaHash: The key's Java hashCode().
    public init(javaHash: @escaping (Key) -> Int32) {
        self.javaHash = javaHash
    }

    /// Create an empty map, like `new HashMap<>(initialCapacity)`.
    public init(initialCapacity: Int, javaHash: @escaping (Key) -> Int32) {
        self.javaHash = javaHash
        threshold = JavaHashMap.tableSizeFor(initialCapacity)
    }

    /// A copy, like `new HashMap<>(other)`, which presizes the table.
    public init(copying other: JavaHashMap<Key, Value>) {
        self.javaHash = other.javaHash
        putAll(other)
    }

    /// Java's HashMap.tableSizeFor: the power of two at or above c.
    private static func tableSizeFor(_ c: Int) -> Int {
        var n = 1
        while n < c { n <<= 1 }
        return min(n, 1 << 30)
    }

    private static func spread(_ h: Int32) -> Int32 {
        h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16)
    }

    private func bucket(_ hash: Int32, _ capacity: Int) -> Int {
        Int(UInt32(bitPattern: hash) & UInt32(capacity - 1))
    }

    /// Whether the map is empty.
    public var isEmpty: Bool {
        count == 0
    }

    /// The value for a key.
    public subscript(key: Key) -> Value? {
        get {
            index[key]
        }
        set {
            if let newValue { put(key, newValue) } else { removeValue(forKey: key) }
        }
    }

    /// Put a value, returning the old one (Java's put).
    @discardableResult
    public mutating func put(_ key: Key, _ value: Value) -> Value? {
        if table.isEmpty { resize() }
        index[key] = value
        let h = JavaHashMap.spread(javaHash(key))
        let i = bucket(h, table.count)
        if let j = table[i].firstIndex(where: { $0.hash == h && $0.key == key }) {
            let old = table[i][j].value
            table[i][j].value = value
            return old
        }
        table[i].append(Entry(key: key, hash: h, value: value))
        if table[i].count >= 9 {
            // Java's treeifyBin: resize small tables instead.
            precondition(table.count < 64, "Java would build a tree bin here; not emulated")
            resize()
        }
        count += 1
        if count > threshold { resize() }
        return nil
    }

    /// Put every entry of another map, in its order (Java's putAll),
    /// presizing the table first as Java does.
    public mutating func putAll(_ other: JavaHashMap<Key, Value>) {
        let s = other.count
        guard s > 0 else { return }
        if table.isEmpty {
            // JDK 18: float ft = s / loadFactor + 1.0f
            let ft = Float(s) / 0.75 + 1
            let t = ft < Float(1 << 30) ? Int(ft) : 1 << 30
            if t > threshold { threshold = JavaHashMap.tableSizeFor(t) }
        } else {
            while s > threshold && table.count < (1 << 30) { resize() }
        }
        for e in other.entries { put(e.key, e.value) }
    }

    /// Remove a key, returning its value.
    @discardableResult
    public mutating func removeValue(forKey key: Key) -> Value? {
        guard !table.isEmpty else { return nil }
        let h = JavaHashMap.spread(javaHash(key))
        let i = bucket(h, table.count)
        guard let j = table[i].firstIndex(where: { $0.hash == h && $0.key == key }) else { return nil }
        index[key] = nil
        count -= 1
        return table[i].remove(at: j).value
    }

    /// Remove everything, keeping the table size as Java does.
    public mutating func removeAll() {
        for i in table.indices { table[i] = [] }
        index = [:]
        count = 0
    }

    private mutating func resize() {
        let oldCapacity = table.count
        // A first table uses a requested capacity held in the threshold.
        let newCapacity = oldCapacity > 0 ? oldCapacity * 2 : (threshold > 0 ? threshold : 16)
        threshold = Int(Float(newCapacity) * 0.75)
        var newTable = [[Entry]](repeating: [], count: newCapacity)
        // Entries keep their relative order, as Java's lo/hi split does.
        for b in table {
            for e in b { newTable[bucket(e.hash, newCapacity)].append(e) }
        }
        table = newTable
    }

    /// The entries in Java's iteration order.
    public var entries: [(key: Key, value: Value)] {
        table.flatMap { $0.map { (key: $0.key, value: $0.value) } }
    }

    /// The keys in Java's iteration order.
    public var keys: [Key] {
        table.flatMap { $0.map(\.key) }
    }

    /// The values in Java's iteration order.
    public var values: [Value] {
        table.flatMap { $0.map(\.value) }
    }
}

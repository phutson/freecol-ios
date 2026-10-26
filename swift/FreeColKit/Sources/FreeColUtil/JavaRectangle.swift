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

/// Java's `java.awt.Rectangle`, as far as the map generator uses it,
/// with its int arithmetic: regions are given widths of
/// Integer.MAX_VALUE, and `contains` relies on the sums overflowing.
public struct JavaRectangle: Equatable, Sendable, CustomStringConvertible {
    public var x: Int32 = 0
    public var y: Int32 = 0
    public var width: Int32 = 0
    public var height: Int32 = 0

    public init() {}

    public init(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(_ x: Int, _ y: Int, _ width: Int, _ height: Int) {
        self.init(Int32(x), Int32(y), Int32(width), Int32(height))
    }

    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }

    public mutating func setBounds(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public mutating func setBounds(_ r: JavaRectangle) {
        self = r
    }

    /// Whether a point is inside (Rectangle.contains(int, int)).
    public func contains(_ px: Int, _ py: Int) -> Bool {
        let px = Int32(truncatingIfNeeded: px), py = Int32(truncatingIfNeeded: py)
        var w = width, h = height
        if (w | h) < 0 { return false }
        if px < x || py < y { return false }
        w = w &+ x
        h = h &+ y
        return (w < x || w > px) && (h < y || h > py)
    }

    /// Grow to include a point (Rectangle.add(int, int)).
    public mutating func add(_ newx: Int, _ newy: Int) {
        var tx2 = Int64(width), ty2 = Int64(height)
        if (tx2 | ty2) < 0 { setBounds(Int32(newx), Int32(newy), 0, 0) }
        var tx1 = Int64(x), ty1 = Int64(y)
        tx2 += tx1
        ty2 += ty1
        let nx = Int64(newx), ny = Int64(newy)
        if tx1 > nx { tx1 = nx }
        if ty1 > ny { ty1 = ny }
        if tx2 < nx { tx2 = nx }
        if ty2 < ny { ty2 = ny }
        tx2 -= tx1
        ty2 -= ty1
        let maxInt = Int64(Int32.max)
        if tx2 > maxInt { tx2 = maxInt }
        if ty2 > maxInt { ty2 = maxInt }
        setBounds(Int32(tx1), Int32(ty1), Int32(tx2), Int32(ty2))
    }

    public var description: String {
        "java.awt.Rectangle[x=\(x),y=\(y),width=\(width),height=\(height)]"
    }
}

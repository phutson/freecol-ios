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

import Foundation
import FreeColUtil

/// The eight directions on the isometric map (common/model/Direction).
///
/// Rows are staggered, so a step depends on whether the row is odd or
/// even.  Moving N or S changes the row by two.
///
/// The name key is in Labels.swift.
public enum Direction: JavaEnum, CustomStringConvertible {
    case n, ne, e, se, s, sw, w, nw

    public var javaName: String {
        switch self {
        case .n: "N"
        case .ne: "NE"
        case .e: "E"
        case .se: "SE"
        case .s: "S"
        case .sw: "SW"
        case .w: "W"
        case .nw: "NW"
        }
    }

    public static let numberOfDirections = 8

    /// All the directions, clockwise from N.
    public static let allDirections: [Direction] = [.n, .ne, .e, .se, .s, .sw, .w, .nw]

    /// The directions across the long sides of a tile, where rivers flow.
    public static let longSides: [Direction] = [.ne, .se, .sw, .nw]

    /// The directions to the corners of a tile.
    public static let corners: [Direction] = [.n, .e, .s, .w]

    /// The step on odd rows and on even rows.
    private var deltas: (oddDX: Int, oddDY: Int, evenDX: Int, evenDY: Int) {
        switch self {
        case .n: (0, -2, 0, -2)
        case .ne: (1, -1, 0, -1)
        case .e: (1, 0, 1, 0)
        case .se: (1, 1, 0, 1)
        case .s: (0, 2, 0, 2)
        case .sw: (0, 1, -1, 1)
        case .w: (-1, 0, -1, 0)
        case .nw: (0, -1, -1, -1)
        }
    }

    /// The position one step this way from a position.
    public func step(_ x: Int, _ y: Int) -> Map.Position {
        let d = deltas
        return (y & 1) != 0
            ? Map.Position(x + d.oddDX, y + d.oddDY)
            : Map.Position(x + d.evenDX, y + d.evenDY)
    }

    /// The direction n steps clockwise (negative for anticlockwise).
    public func rotate(_ n: Int) -> Direction {
        let count = Direction.numberOfDirections
        return Direction.allDirections[(((ordinal + n) % count) + count) % count]
    }

    public var nextDirection: Direction { rotate(1) }

    public var previousDirection: Direction { rotate(-1) }

    public var reverseDirection: Direction { rotate(Direction.numberOfDirections / 2) }

    /// The direction mirrored east to west.
    public var ewMirroredDirection: Direction {
        switch self {
        case .nw: .ne
        case .w: .e
        case .sw: .se
        case .ne: .nw
        case .e: .w
        case .se: .sw
        default: self
        }
    }

    /// A random direction.
    public static func randomDirection(_ logMe: String, _ random: JavaRandom) -> Direction {
        allDirections[Int(RandomUtils.randomInt(logMe, random, Int32(numberOfDirections)))]
    }

    /// All the directions in random order.
    public static func randomDirections(_ logMe: String, _ random: JavaRandom) -> [Direction] {
        var directions = allDirections
        RandomUtils.randomShuffle(logMe, &directions, random)
        return directions
    }

    /// All the directions, closest to this one first: this one, then
    /// the pairs either side in random order, then the reverse.
    public func closestDirections(_ logMe: String, _ random: JavaRandom) -> [Direction] {
        let count = Direction.numberOfDirections
        // Three bits of randomness, one to order each pair.
        let nbits = (count - 2) / 2
        let r = Int(RandomUtils.randomInt(logMe, random, Int32(1 << nbits)))
        var ret = [self]
        var step = 1, mask = 1
        while ret.count < count - 1 {
            let dr = rotate(step)
            let dl = rotate(count - step)
            ret += (r & mask) == 0 ? [dr, dl] : [dl, dr]
            step += 1
            mask *= 2
        }
        ret.append(reverseDirection)
        return ret
    }

    /// The direction for an angle in radians, clockwise from N.
    public static func angleToDirection(_ angle: Double) -> Direction {
        allDirections[Int((angle / (Double.pi / 4)).rounded(.down))]
    }

    /// The message key ("direction.N"; the case is kept).
    public var key: String {
        "direction." + javaName
    }

    public var description: String {
        javaName
    }
}

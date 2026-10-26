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

/// Every difference between two JSON values, by path, going into
/// arrays element by element.
public func elementDifferences(_ a: JSONValue, _ b: JSONValue, _ path: String = "") -> [String] {
    switch (a, b) {
    case let (.object(x), .object(y)):
        var out: [String] = []
        for key in Set(x.keys).union(y.keys).sorted() {
            switch (x[key], y[key]) {
            case let (u?, v?): out += elementDifferences(u, v, "\(path)/\(key)")
            case (nil, _): out.append("\(path)/\(key): missing in Swift")
            case (_, nil): out.append("\(path)/\(key): only in Swift")
            }
        }
        return out
    case let (.array(x), .array(y)) where x.count == y.count:
        return zip(x, y).enumerated().flatMap { elementDifferences($1.0, $1.1, "\(path)[\($0)]") }
    default:
        return a == b ? [] : ["\(path): Swift \(a) vs Java \(b)"]
    }
}

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

/// Writes JSON in exactly the canonical form of the Java dump tools
/// (net.sf.freecol.tools.dump.Json), so Swift and Java dumps can be
/// compared with a plain text diff.
///
/// The rules: object keys sorted by UTF-16 code units (Java's
/// String.compareTo), two-space indentation, one member or element per
/// line, "{}" and "[]" for empty containers, decimals formatted like
/// Java's Double.toString, and a final newline.
public enum CanonicalJSON {

    /// Write a value as a complete canonical document.
    ///
    /// - Parameter value: The value to write.
    /// - Returns: The document text, ending with a newline.
    public static func document(_ value: JSONValue) -> String {
        var out = ""
        append(value, depth: 0, to: &out)
        out.append("\n")
        return out
    }

    private static func append(_ value: JSONValue, depth: Int, to out: inout String) {
        switch value {
        case .null:
            out.append("null")
        case .bool(let b):
            out.append(b ? "true" : "false")
        case .integer(let i):
            out.append(String(i))
        case .decimal(let d):
            if d.isNaN || d.isInfinite {
                appendString(JavaNumberFormat.string(d), to: &out)
            } else {
                out.append(JavaNumberFormat.string(d))
            }
        case .string(let s):
            appendString(s, to: &out)
        case .array(let elements):
            if elements.isEmpty {
                out.append("[]")
                return
            }
            out.append("[\n")
            for (i, element) in elements.enumerated() {
                if i > 0 { out.append(",\n") }
                indent(depth + 1, to: &out)
                append(element, depth: depth + 1, to: &out)
            }
            out.append("\n")
            indent(depth, to: &out)
            out.append("]")
        case .object(let members):
            if members.isEmpty {
                out.append("{}")
                return
            }
            out.append("{\n")
            let keys = members.keys.sorted { $0.utf16.lexicographicallyPrecedes($1.utf16) }
            for (i, key) in keys.enumerated() {
                if i > 0 { out.append(",\n") }
                indent(depth + 1, to: &out)
                appendString(key, to: &out)
                out.append(": ")
                append(members[key]!, depth: depth + 1, to: &out)
            }
            out.append("\n")
            indent(depth, to: &out)
            out.append("}")
        }
    }

    private static func appendString(_ s: String, to out: inout String) {
        out.append("\"")
        for unit in s.unicodeScalars {
            switch unit {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            default:
                if unit.value < 0x20 {
                    let hex = String(unit.value, radix: 16)
                    out.append("\\u" + String(repeating: "0", count: 4 - hex.count) + hex)
                } else {
                    out.unicodeScalars.append(unit)
                }
            }
        }
        out.append("\"")
    }

    private static func indent(_ depth: Int, to out: inout String) {
        out.append(String(repeating: "  ", count: depth))
    }
}

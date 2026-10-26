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

/// A parsed JSON value.
///
/// Unlike Foundation's JSONSerialization this keeps integers and
/// decimals apart by how they were written ("2" versus "2.0"), which
/// the canonical dump format depends on.
public enum JSONValue: Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case integer(Int64)
    case decimal(Double)
    case bool(Bool)
    case null

    /// Look up a key in an object, or nil for any other value.
    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    /// The string value, or nil if this is not a string.
    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    /// The object members, or nil if this is not an object.
    public var objectValue: [String: JSONValue]? {
        if case .object(let members) = self { return members }
        return nil
    }

    /// The array elements, or nil if this is not an array.
    public var arrayValue: [JSONValue]? {
        if case .array(let elements) = self { return elements }
        return nil
    }
}

/// An error found while parsing JSON.
public struct JSONParseError: Error, CustomStringConvertible {
    public let offset: Int
    public let message: String

    public var description: String {
        "JSON parse error at byte \(offset): \(message)"
    }
}

extension JSONValue {

    /// Parse a complete JSON document.
    ///
    /// - Parameter bytes: The UTF-8 encoded document.
    /// - Returns: The parsed value.
    /// - Throws: `JSONParseError` if the document is not valid JSON.
    public static func parse<Bytes: Collection>(_ bytes: Bytes) throws -> JSONValue
        where Bytes.Element == UInt8 {
        var parser = Parser(bytes: Array(bytes))
        parser.skipWhitespace()
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.atEnd else { throw parser.error("trailing content") }
        return value
    }
}

private struct Parser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var atEnd: Bool { index >= bytes.count }

    func error(_ message: String) -> JSONParseError {
        JSONParseError(offset: index, message: message)
    }

    mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    mutating func expect(_ byte: UInt8) throws {
        guard index < bytes.count, bytes[index] == byte else {
            throw error("expected '\(Character(Unicode.Scalar(byte)))'")
        }
        index += 1
    }

    mutating func parseValue() throws -> JSONValue {
        guard index < bytes.count else { throw error("unexpected end") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try parseLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try parseLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try parseLiteral("null"); return .null
        default: return try parseNumber()
        }
    }

    mutating func parseLiteral(_ literal: String) throws {
        for byte in literal.utf8 {
            try expect(byte)
        }
    }

    mutating func parseObject() throws -> JSONValue {
        try expect(UInt8(ascii: "{"))
        var members: [String: JSONValue] = [:]
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            try expect(UInt8(ascii: ":"))
            skipWhitespace()
            guard members.updateValue(try parseValue(), forKey: key) == nil else {
                throw error("duplicate key \"\(key)\"")
            }
            skipWhitespace()
            guard index < bytes.count else { throw error("unexpected end") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else {
                try expect(UInt8(ascii: "}"))
                return .object(members)
            }
        }
    }

    mutating func parseArray() throws -> JSONValue {
        try expect(UInt8(ascii: "["))
        var elements: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            elements.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw error("unexpected end") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
            } else {
                try expect(UInt8(ascii: "]"))
                return .array(elements)
            }
        }
    }

    mutating func parseString() throws -> String {
        try expect(UInt8(ascii: "\""))
        var utf8: [UInt8] = []
        while true {
            guard index < bytes.count else { throw error("unterminated string") }
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                return String(decoding: utf8, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard index < bytes.count else { throw error("bad escape") }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): utf8.append(UInt8(ascii: "\""))
                case UInt8(ascii: "\\"): utf8.append(UInt8(ascii: "\\"))
                case UInt8(ascii: "/"): utf8.append(UInt8(ascii: "/"))
                case UInt8(ascii: "b"): utf8.append(0x08)
                case UInt8(ascii: "f"): utf8.append(0x0C)
                case UInt8(ascii: "n"): utf8.append(0x0A)
                case UInt8(ascii: "r"): utf8.append(0x0D)
                case UInt8(ascii: "t"): utf8.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try parseHex4()
                    if (0xD800...0xDBFF).contains(scalar) {
                        try parseLiteral("\\u")
                        let low = try parseHex4()
                        guard (0xDC00...0xDFFF).contains(low) else {
                            throw error("bad surrogate pair")
                        }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let s = Unicode.Scalar(scalar) else {
                        throw error("bad unicode escape")
                    }
                    utf8.append(contentsOf: Array(String(Character(s)).utf8))
                default:
                    throw error("bad escape")
                }
            default:
                utf8.append(byte)
            }
        }
    }

    mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw error("bad unicode escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A") + 10)
            default: throw error("bad hex digit")
            }
            value = value * 16 + digit
        }
        return value
    }

    mutating func parseNumber() throws -> JSONValue {
        let start = index
        var isDecimal = false
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "+"):
                index += 1
            case UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E"):
                isDecimal = true
                index += 1
            default:
                break
            }
            if index < bytes.count, !Parser.isNumberByte(bytes[index]) { break }
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if isDecimal {
            guard let d = Double(text) else { throw error("bad number \(text)") }
            return .decimal(d)
        }
        guard let i = Int64(text) else { throw error("bad number \(text)") }
        return .integer(i)
    }

    static func isNumberByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "+"),
             UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E"):
            return true
        default:
            return false
        }
    }
}

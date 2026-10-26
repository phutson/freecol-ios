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
import FreeColXML

/// Chooses one of several forms for a selector value: the key of a
/// "{{tag:selector|key=value|...}}" choice (common/i18n/Selector).
public protocol Selector: AnyObject {
    /// The key for a selector value; the template is for warnings.
    func key(_ selector: String, _ template: String) -> String
}

/// A language's plural rule: the CLDR plural category of a number
/// (common/i18n/Number and its subclasses).
open class NumberRule: Selector {

    /// The CLDR plural categories (Number.Category), in Java's order.
    public enum Category: String, CaseIterable, Sendable {
        case zero, one, two, few, many, other
    }

    public init() {}

    open func category(_ number: Double) -> Category {
        .other
    }

    /// The category of a selector parsed as Java's Double.parseDouble
    /// does, or "other" if it is not a number.
    public func key(_ selector: String, _ template: String) -> String {
        guard let number = JavaDouble.parse(selector) else { return Category.other.rawValue }
        return category(number).rawValue
    }
}

/// Languages without plurals (OtherNumberRule).
public final class OtherNumberRule: NumberRule {
    public override func category(_ number: Double) -> Category { .other }
}

/// One, and the rest (PluralNumberRule).
public final class PluralNumberRule: NumberRule {
    public override func category(_ number: Double) -> Category { number == 1 ? .one : .other }
}

/// Zero or one, and the rest (ZeroOneNumberRule).
public final class ZeroOneNumberRule: NumberRule {
    public override func category(_ number: Double) -> Category {
        number == 0 || number == 1 ? .one : .other
    }
}

/// One, two, and the rest (DualNumberRule).
public final class DualNumberRule: NumberRule {
    public override func category(_ number: Double) -> Category {
        number == 1 ? .one : number == 2 ? .two : .other
    }
}

/// A rule set from the CLDR data: the first category whose rule
/// matches, or "other" (DefaultNumberRule).
public final class DefaultNumberRule: NumberRule {
    private var rules: [Category: PluralRule] = [:]

    public func addRule(_ category: Category, _ rule: PluralRule) {
        rules[category] = rule
    }

    public var countRules: Int { rules.count }

    public func rule(_ category: Category) -> PluralRule? { rules[category] }

    public override func category(_ number: Double) -> Category {
        Category.allCases.first { rules[$0]?.matches(number) ?? false } ?? .other
    }
}

/// A CLDR plural rule: relations joined by "and", alternatives by "or"
/// (common/i18n/Rule).
public final class PluralRule: CustomStringConvertible {
    private var conditions: [[Relation]] = []

    /// Parse a rule such as "n mod 10 in 2..4 and n mod 100 not in 12..14".
    public init(_ input: String) throws {
        // Java's StringTokenizer on space and full stop.
        let tokens = input.lowercased().split(whereSeparator: { $0 == " " || $0 == "." }).map(String.init)
        var current: [String] = []
        for token in tokens {
            if token == "or" {
                conditions.append(try PluralRule.parseCondition(current))
                current = []
            } else {
                current.append(token)
            }
        }
        conditions.append(try PluralRule.parseCondition(current))
    }

    private static func parseCondition(_ input: [String]) throws -> [Relation] {
        var tokens: [String] = []
        var result: [Relation] = []
        for token in input {
            if token == "and" {
                result.append(try Relation(tokens))
                tokens = []
            } else {
                tokens.append(token)
            }
        }
        result.append(try Relation(tokens))
        return result
    }

    public func matches(_ number: Double) -> Bool {
        conditions.contains { $0.allSatisfy { $0.matches(number) } }
    }

    /// Java's toString, used to recognise the simple rules.  Java's
    /// loop puts " or " in front of what it has so far after each
    /// condition and finally drops the first, which runs the conditions
    /// together; mirrored, as only single conditions are compared.
    public var description: String {
        var sb = ""
        for andCondition in conditions {
            for relation in andCondition { sb += relation.description + " and " }
            sb.removeLast(" and ".count)
            sb = " or " + sb
        }
        sb.removeFirst(" or ".count)
        return sb
    }
}

/// One relation of a plural rule, such as "n mod 10 is 1"
/// (common/i18n/Relation).
public struct Relation: CustomStringConvertible {
    var low = 0, high = 0, mod = 1
    var negated = false
    var integer = true

    init(_ input: [String]) throws {
        var tokens = input
        func next() throws -> String {
            guard !tokens.isEmpty else { throw FreeColXMLError("Short plural relation: \(input)") }
            return tokens.removeFirst()
        }
        func int(_ s: String) throws -> Int {
            guard let v = JavaString.parseInt(s) else { throw FreeColXMLError("Bad number in plural rule: \(s)") }
            return Int(v)
        }
        var token = try next()
        guard token == "n" else { throw FreeColXMLError("Relation must start with 'n': \(token)") }
        token = try next()
        if token == "mod" {
            mod = try int(try next())
            token = try next()
        }
        if token == "not" {
            negated = true
            token = try next()
        }
        if token == "is" {
            token = try next()
            if token == "not" {
                negated = true
                token = try next()
            }
            low = try int(token)
            high = low
        } else {
            if token == "within" { integer = false }
            low = try int(try next())
            high = try int(try next())
        }
    }

    func matches(_ number: Double) -> Bool {
        let value = mod == 1 ? number : number.truncatingRemainder(dividingBy: Double(mod))
        if integer && JavaDouble.compare(value, value.rounded(.toNearestOrEven)) != 0 { return false }
        return (Double(low) <= value && value <= Double(high)) != negated
    }

    public var description: String {
        var s = "n "
        if mod != 1 { s += "mod \(mod) " }
        if low == high {
            s += "is " + (negated ? "not " : "") + "\(low)"
        } else {
            s += (negated ? "not " : "") + (integer ? "" : "with") + "in \(low)..\(high)"
        }
        return s
    }
}

/// The plural rules of each language, read from the CLDR data
/// (data/strings/plurals.xml, common/i18n/NumberRules).
public final class NumberRules {

    nonisolated(unsafe) public static let otherNumberRule = OtherNumberRule()
    nonisolated(unsafe) public static let dualNumberRule = DualNumberRule()
    nonisolated(unsafe) public static let pluralNumberRule = PluralNumberRule()
    nonisolated(unsafe) public static let zeroOneNumberRule = ZeroOneNumberRule()

    private var numberMap: [String: NumberRule] = [:]

    /// Read the rules from the CLDR plurals document.
    public init(data: Data) throws {
        let xr = try FreeColXMLReader(data: data)
        try xr.nextTag() // supplementalData
        while try xr.moreTags() {
            switch xr.localName {
            case "version", "generation":
                try xr.nextTag()
            case "plurals":
                while try xr.moreTags() {
                    if xr.localName == "pluralRules" {
                        try readRules(xr)
                    } else {
                        try xr.swallowTag(xr.localName)
                    }
                }
            default:
                try xr.swallowTag(xr.localName)
            }
        }
    }

    public var isInitialized: Bool { !numberMap.isEmpty }

    /// The rule for a language, or no plurals for one not listed.
    public func number(forLanguage lang: String) -> NumberRule {
        numberMap[lang] ?? NumberRules.otherNumberRule
    }

    private func readRules(_ xr: FreeColXMLReader) throws {
        guard let loc = xr.attribute("locales", default: nil as String?) else {
            try xr.swallowTag("pluralRules")
            return
        }
        let locales = loc.components(separatedBy: " ")
        let numberRule = DefaultNumberRule()
        while try xr.moreTags() {
            if xr.localName == "pluralRule" {
                let plu = xr.attribute("count", default: nil as String?) ?? ""
                guard let category = NumberRule.Category(rawValue: plu) else {
                    throw FreeColXMLError("Bad plural category: \(plu)")
                }
                numberRule.addRule(category, try PluralRule(try xr.elementText()))
            } else {
                try xr.swallowTag(xr.localName)
            }
        }
        // The simple rules have their own classes.
        var number: NumberRule?
        switch numberRule.countRules {
        case 0:
            number = NumberRules.otherNumberRule
        case 1:
            switch numberRule.rule(.one)?.description {
            case "n is 1": number = NumberRules.pluralNumberRule
            case "n in 0..1": number = NumberRules.zeroOneNumberRule
            default: break
            }
        case 2:
            if numberRule.rule(.one)?.description == "n is 1" && numberRule.rule(.two)?.description == "n is 2" {
                number = NumberRules.dualNumberRule
            }
        default:
            number = numberRule
        }
        // Java stores null for an unrecognised simple rule, which then
        // reads as no plurals.
        for locale in locales {
            if let number { numberMap[locale] = number } else { numberMap[locale] = nil }
        }
    }
}

/// Java's Double.parseDouble and Double.compare.
public enum JavaDouble {

    /// Parse as Java does: surrounding control characters and spaces
    /// trimmed, an optional sign, "NaN", "Infinity", or a decimal number
    /// with an optional exponent and an optional f, F, d or D suffix
    /// (hexadecimal floats are not supported).  Nil where Java throws.
    public static func parse(_ s: String) -> Double? {
        let t = JavaString.javaTrimmed(s)
        var chars = Array(t.utf8)
        guard !chars.isEmpty else { return nil }
        var sign = 1.0
        var start = 0
        if chars[0] == UInt8(ascii: "+") || chars[0] == UInt8(ascii: "-") {
            if chars[0] == UInt8(ascii: "-") { sign = -1 }
            start = 1
        }
        let body = String(decoding: chars[start...], as: UTF8.self)
        if body == "NaN" { return Double.nan }
        if body == "Infinity" { return sign * Double.infinity }
        if let last = chars.last, "fFdD".utf8.contains(last), chars.count > start + 1 {
            chars.removeLast()
        }
        let number = String(decoding: chars[start...], as: UTF8.self)
        // Digits, at most one point, at least one digit, then an
        // optional exponent with digits.
        var sawDigit = false, sawPoint = false, i = number.utf8.startIndex
        let u = number.utf8
        while i < u.endIndex, u[i] != UInt8(ascii: "e"), u[i] != UInt8(ascii: "E") {
            if u[i] == UInt8(ascii: ".") {
                if sawPoint { return nil }
                sawPoint = true
            } else if u[i] >= UInt8(ascii: "0") && u[i] <= UInt8(ascii: "9") {
                sawDigit = true
            } else {
                return nil
            }
            i = u.index(after: i)
        }
        guard sawDigit else { return nil }
        if i < u.endIndex {
            var j = u.index(after: i)
            if j < u.endIndex, u[j] == UInt8(ascii: "+") || u[j] == UInt8(ascii: "-") { j = u.index(after: j) }
            guard j < u.endIndex else { return nil }
            while j < u.endIndex {
                guard u[j] >= UInt8(ascii: "0") && u[j] <= UInt8(ascii: "9") else { return nil }
                j = u.index(after: j)
            }
        }
        return Double(number).map { sign * $0 }
    }

    /// Java's Double.compare: numeric order, but -0.0 below 0.0, and NaN
    /// equal to itself and above everything.
    public static func compare(_ a: Double, _ b: Double) -> Int {
        if a < b { return -1 }
        if a > b { return 1 }
        let x = a.isNaN ? Int64(0x7FF8_0000_0000_0000) : Int64(bitPattern: a.bitPattern)
        let y = b.isNaN ? Int64(0x7FF8_0000_0000_0000) : Int64(bitPattern: b.bitPattern)
        return x == y ? 0 : x < y ? -1 : 1
    }
}

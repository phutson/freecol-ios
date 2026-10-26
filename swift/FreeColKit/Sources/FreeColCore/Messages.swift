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

/// The translated messages of a language, and the selectors for its
/// choice formats (the bundle of common/i18n/Messages).
///
/// Messages are loaded from FreeColMessages files in order (the default
/// first, then the language, the country and the variant), later files
/// replacing earlier keys.
public final class MessageBundle: @unchecked Sendable {

    /// The messages by key.
    public private(set) var messages: [String: String] = [:]
    /// The selectors by tag; "plural" chooses by the language's number
    /// rule.
    private var tagMap: [String: Selector] = [:]

    public init() {}

    public var count: Int { messages.count }

    public func setGrammaticalNumber(_ number: NumberRule) {
        tagMap["plural"] = number
    }

    func selector(_ tag: String) -> Selector? {
        tagMap[tag.lowercased()]
    }

    public func value(_ key: String) -> String? {
        messages[key]
    }

    /// Add one message (as Java's message bundle put does).
    public func put(_ key: String, _ value: String) {
        messages[key] = value
    }

    /// Load messages as Java's Messages.loadMessages does: line by line,
    /// skipping lines that start with "#", taking the trimmed text
    /// before the first "=" as the key and the trimmed rest as the
    /// value, with "\n" and "\t" turned into a newline and a tab.  (Not
    /// java.util.Properties: there are no other escapes, and no
    /// continued lines.)
    public func load(_ data: Data) {
        let text = String(decoding: data, as: UTF8.self)
        for rawLine in MessageBundle.javaLines(text) {
            let line = JavaString.javaTrimmed(rawLine)
            if line.hasPrefix("#") { continue }
            let u = Array(line.utf16)
            guard let index = u.firstIndex(of: UInt16(UInt8(ascii: "="))), index > 0 else { continue }
            let key = JavaString.javaTrimmed(String(decoding: u[..<index], as: UTF16.self))
            var value = Array(JavaString.javaTrimmed(String(decoding: u[(index + 1)...], as: UTF16.self)).utf16)
            value = JavaUTF16.replace(value, Array("\\n".utf16), [10])
            value = JavaUTF16.replace(value, Array("\\t".utf16), [9])
            messages[key] = String(decoding: value, as: UTF16.self)
        }
    }

    /// The lines of a text as BufferedReader.readLine splits them: at
    /// "\n", "\r" or "\r\n", with no empty last line.
    static func javaLines(_ text: String) -> [String] {
        var lines: [String] = []
        var current: [UInt16] = []
        var pendingCR = false
        for c in text.utf16 {
            if pendingCR {
                pendingCR = false
                if c == 10 { continue }
            }
            if c == 10 || c == 13 {
                lines.append(String(decoding: current, as: UTF16.self))
                current = []
                pendingCR = c == 13
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { lines.append(String(decoding: current, as: UTF16.self)) }
        return lines
    }

    /// The file names to load for a language id ("de", "pt_BR"), in
    /// order (FreeColDirectories.getLocaleFileNames).
    public static func fileNames(prefix: String = "FreeColMessages", suffix: String = ".properties",
                                 languageId: String) -> [String] {
        let (language, country, variant) = Messages.localeParts(languageId)
        let l = language.isEmpty ? "" : "_" + language
        let c = country.isEmpty ? "" : "_" + country
        let v = variant.isEmpty ? "" : "_" + variant
        var result = [prefix + suffix]
        for name in [prefix + l + suffix, prefix + l + c + suffix, prefix + l + c + v + suffix]
            where !result.contains(name) {
            result.append(name)
        }
        return result
    }

    /// Load a language's messages from a directory of message files,
    /// then from each rule set's directory, with the plural rules for
    /// the language (Messages.loadMessageBundle).  Java takes the rule
    /// sets that have a mod descriptor and a specification, by name.
    public static func load(directory: URL, languageId: String, numberRules: NumberRules,
                            rulesDirectories: [URL] = []) -> MessageBundle {
        let bundle = MessageBundle()
        bundle.setGrammaticalNumber(numberRules.number(forLanguage: Messages.localeParts(languageId).language))
        for dir in [directory] + rulesDirectories {
            for name in fileNames(languageId: languageId) {
                if let data = try? Data(contentsOf: dir.appendingPathComponent(name)) { bundle.load(data) }
            }
        }
        return bundle
    }
}

/// Translating keys and templates into text (common/i18n/Messages).
///
/// As in Java, there is one current bundle, which the model's labels
/// also consult.  The engine runs in one actor.
///
/// Not yet ported: loading the messages of mods and rule sets (only
/// the bundled strings are loaded), and the FileChooser keys Java gives
/// Swing.
public enum Messages {

    public static let descriptionSuffix = ".description"
    public static let shortDescriptionSuffix = ".shortDescription"
    public static let nameSuffix = ".name"
    public static let rulerSuffix = ".ruler"

    /// The messages in use: those of the current task, if it has set
    /// some (scopedBundle), otherwise the global ones, which setting
    /// this changes.
    public static var bundle: MessageBundle {
        get { scopedBundle ?? globalBundle }
        set { globalBundle = newValue }
    }

    nonisolated(unsafe) private static var globalBundle = MessageBundle()

    /// Messages for one task and the tasks it starts, in place of the
    /// global ones, so (for example) tests in different languages can
    /// run at once.  A bundle is filled in when loaded and only read
    /// after, so it may be shared between tasks.
    @TaskLocal public static var scopedBundle: MessageBundle?

    /// A language id's language, country and variant (Messages.getLocale
    /// and java.util.Locale, which lower-cases the language and
    /// upper-cases the country).
    public static func localeParts(_ languageId: String) -> (language: String, country: String, variant: String) {
        let parts = languageId.components(separatedBy: "_")
        let language = parts[0].lowercased()
        let country = parts.count > 1 ? parts[1].uppercased() : ""
        let variant = parts.count > 2 ? parts[2...].joined(separator: "_") : ""
        return (language, country, variant)
    }

    // MARK: Keys

    public static func nameKey(_ id: String?) -> String { (id ?? "null") + nameSuffix }
    public static func descriptionKey(_ id: String?) -> String { (id ?? "null") + descriptionSuffix }
    public static func shortDescriptionKey(_ id: String?) -> String { (id ?? "null") + shortDescriptionSuffix }
    public static func rulerKey(_ id: String?) -> String { (id ?? "null") + rulerSuffix }

    public static func name(_ id: String?) -> String { message(nameKey(id)) }
    public static func name(_ named: Named) -> String { message(named.nameKey) }
    public static func description(_ id: String?) -> String { message(descriptionKey(id)) }
    public static func shortDescription(_ id: String?) -> String { message(shortDescriptionKey(id)) }
    public static func rulerName(_ id: String?) -> String { message(rulerKey(id)) }

    public static func containsKey(_ key: String) -> Bool {
        bundle.value(key) != nil
    }

    public static func key(_ preferredKey: String, _ defaultKey: String) -> String {
        containsKey(preferredKey) ? preferredKey : defaultKey
    }

    /// The description, short description or name of an id, whichever
    /// is found first, or the id.
    public static func bestDescription(_ id: String) -> String {
        let key = [descriptionSuffix, shortDescriptionSuffix, nameSuffix].map { id + $0 }.first(where: containsKey)
        return key.map(message) ?? id
    }

    /// A name and description for a name key or id.
    public static func bestNameAndDescription(_ key: String) -> (name: String, description: String?) {
        var id = key
        if id.hasSuffix(nameSuffix) { id.removeLast(nameSuffix.count) } // Java's temporary hack
        if containsKey(nameKey(id)) {
            let desc = bestDescription(id)
            return (name(id), desc == id ? nil : desc)
        }
        return (containsKey(id) ? message(id) : id, nil)
    }

    /// Java's StringUtils.getEnumKey: the constant name in lower camel
    /// case ("BUILDING_COMPLETED" gives "buildingCompleted").
    public static func enumKey(_ javaName: String) -> String {
        let base = Array(javaName.lowercased())
        var sb = ""
        var from = 0
        while true {
            guard let idx = base[from...].firstIndex(of: "_") else {
                sb += String(base[from...])
                break
            }
            sb += String(base[from..<idx])
            from = idx + 1
            if from >= base.count { break }
            if base[from].isLetter {
                sb += base[from].uppercased()
                from += 1
            }
        }
        return sb
    }

    // MARK: Translation

    /// The text for a key, with its choices made, or the key itself if
    /// there is none.
    public static func message(_ messageId: String) -> String {
        guard let message = bundle.value(messageId) else { return messageId }
        let u = replaceChoices(Array(message.utf16), nil)
        return JavaString.javaTrimmed(String(decoding: u, as: UTF16.self))
    }

    /// The text for a template.
    public static func message(_ template: StringTemplate?) -> String? {
        guard let template else { return nil }
        let id = template.id ?? "null"
        switch template.templateType {
        case .label:
            if template.isEmpty { return message(id) }
            // The parts joined by the id (Java builds id+part... and drops
            // the first id).
            var sb = ""
            for e in template.entryList {
                sb += id + (message(e.value) ?? "null")
            }
            let idLength = id.utf16.count
            if sb.utf16.count >= idLength {
                return String(decoding: Array(sb.utf16)[idLength...], as: UTF16.self)
            }
            return ""
        case .template:
            // Empty without a message or default; Java would fail on a
            // default without a message.
            var result: [UInt16] = []
            if let value = bundle.value(id) {
                result = Array(value.utf16)
            } else if let defaultId = template.defaultId {
                result = Array((bundle.value(defaultId) ?? "").utf16)
            }
            var r = replaceChoices(result, template)
            for e in template.entryList {
                guard let key = e.key else { continue }
                r = JavaUTF16.replace(r, Array(key.utf16), Array((message(e.value) ?? "null").utf16))
            }
            return String(decoding: r, as: UTF16.self)
        case .key:
            guard let value = bundle.value(id) else { return id }
            return String(decoding: replaceChoices(Array(value.utf16), nil), as: UTF16.self)
        case .name:
            return id
        }
    }

    /// Make the choices in a text: "{{tag:selector|key1=val1|key2=val2}}"
    /// is replaced by the value chosen (Messages.replaceChoices).  Ported
    /// on UTF-16 code units, as Java's indexes count them.
    static func replaceChoices(_ input: [UInt16], _ template: StringTemplate?) -> [UInt16] {
        typealias J = JavaUTF16
        let open = Array("{{".utf16), colon = UInt16(UInt8(ascii: ":")), pipe = UInt16(UInt8(ascii: "|"))
        let percent = UInt16(UInt8(ascii: "%"))
        var result: [UInt16] = []
        var highWaterMark = 0
        while let openChoice = J.indexOf(input, open, highWaterMark) {
            result += input[highWaterMark..<openChoice]
            let closeChoice = findMatchingBracket(input, openChoice + 2)
            if closeChoice < 0 {
                // No closing brackets: Java returns what it has.
                return result
            }
            highWaterMark = closeChoice + 2
            guard let colonIndex = J.indexOf(input, colon, openChoice + 2), colonIndex <= closeChoice else {
                continue // No tag found
            }
            let tag = String(decoding: input[(openChoice + 2)..<colonIndex], as: UTF16.self)
            guard let pipeIndex = J.indexOf(input, pipe, colonIndex + 1), pipeIndex <= closeChoice else {
                continue // No choices found
            }
            var selector = Array(input[(colonIndex + 1)..<pipeIndex])
            if selector.isEmpty {
                selector = Array("default".utf16)
            } else if selector.first == percent && selector.last == percent {
                if let template {
                    guard let replacement = template.replacement(String(decoding: selector, as: UTF16.self)) else {
                        continue // No replacement for the selector
                    }
                    selector = Array((message(replacement) ?? "null").utf16)
                    if let tagged = bundle.selector(tag) {
                        selector = Array(tagged.key(String(decoding: selector, as: UTF16.self),
                                                    String(decoding: input, as: UTF16.self)).utf16)
                    }
                } else {
                    selector = Array("default".utf16)
                }
            } else if let tagged = bundle.selector(tag) {
                selector = Array(tagged.key(String(decoding: selector, as: UTF16.self),
                                            String(decoding: input, as: UTF16.self)).utf16)
            }
            let keyIndex = J.indexOf(input, selector, pipeIndex + 1)
            if keyIndex == nil || keyIndex! > closeChoice {
                // The key is not there: the choice might be a key itself.
                var otherKey = Array(input[(pipeIndex + 1)..<closeChoice])
                if let template, otherKey.first == percent, otherKey.last == percent {
                    guard let replacement = template.replacement(String(decoding: otherKey, as: UTF16.self)) else {
                        continue
                    }
                    guard replacement.templateType == .key else { continue }
                    // Java fails if the key has no message.
                    otherKey = Array((bundle.value(replacement.id ?? "") ?? "").utf16)
                    if let k = J.indexOf(otherKey, open, 0) {
                        guard J.indexOf(otherKey, selector, k) != nil else { continue }
                        result += choice(otherKey, selector) ?? Array("null".utf16)
                    } else {
                        result += otherKey // Not a choice format
                    }
                } else if let value = bundle.value(String(decoding: otherKey, as: UTF16.self)) {
                    result += choice(Array(value.utf16), selector) ?? Array("null".utf16)
                } else {
                    // An unknown key or untagged choice: try "default".
                    let defaultTag = Array("default=".utf16)
                    guard var defaultStart = J.indexOf(otherKey, defaultTag, 0) else { continue }
                    defaultStart += defaultTag.count
                    let defaultEnd = J.indexOf(otherKey, pipe, defaultStart) ?? otherKey.count
                    result += otherKey[defaultStart..<defaultEnd]
                }
            } else {
                let start = keyIndex! + selector.count + 1
                var replacementIndex = J.indexOf(input, pipe, start)
                // A nested choice before the next pipe: the pipe after it.
                if let r = replacementIndex, let nextOpen = J.indexOf(input, open, start), nextOpen < r {
                    replacementIndex = J.indexOf(input, pipe, findMatchingBracket(input, nextOpen + 2) + 2)
                }
                let end = (replacementIndex == nil || replacementIndex! > closeChoice) ? closeChoice
                    : replacementIndex!
                let replacement = Array(input[min(start, end)..<end])
                if J.indexOf(replacement, open, 0) == nil {
                    result += replacement
                } else {
                    result += replaceChoices(replacement, template)
                }
            }
        }
        result += input[highWaterMark...]
        return result
    }

    /// The value for a key in a choice format, up to the next "|" or
    /// "}}" (Messages.getChoice).
    private static func choice(_ input: [UInt16], _ key: [UInt16]) -> [UInt16]? {
        guard let keyIndex = JavaUTF16.indexOf(input, key, 0) else { return nil }
        let start = keyIndex + key.count + 1
        let end = JavaUTF16.indexOf(input, UInt16(UInt8(ascii: "|")), start)
            ?? JavaUTF16.indexOf(input, Array("}}".utf16), start)
        guard let end, start <= end else { return nil }
        return Array(input[start..<end])
    }

    /// The index of the "}}" closing a "{{" whose contents start at an
    /// index, or -1.
    private static func findMatchingBracket(_ input: [UInt16], _ start: Int) -> Int {
        var last: UInt16 = 0
        var level = 0
        let openBrace = UInt16(UInt8(ascii: "{")), closeBrace = UInt16(UInt8(ascii: "}"))
        var index = start
        while index < input.count {
            switch input[index] {
            case openBrace:
                if last == openBrace {
                    last = 0
                    level += 1
                } else {
                    last = openBrace
                }
            case closeBrace:
                if last == closeBrace {
                    if level == 0 { return index - 1 }
                    last = 0
                    level -= 1
                } else {
                    last = closeBrace
                }
            default:
                break
            }
            index += 1
        }
        return -1
    }

    // MARK: Unit labels

    /// A unit's label from its parts (Messages.getUnitLabel): its name,
    /// nation, role, type and number, and anything extra.  A
    /// role-specific type key avoids naming the role twice ("Seasoned
    /// Scout Scout").
    public static func unitLabel(_ name: String?, _ typeId: String?, _ number: Int, _ nationId: String?,
                                 _ roleId: String?, _ extra: StringTemplate?) -> StringTemplate {
        let type: StringTemplate
        let roleKey: String?
        let baseKey = "\(typeId ?? "null").\(Role.roleIdSuffix(roleId))"
        if containsKey(baseKey) {
            type = StringTemplate.template(baseKey).addAmount("%number%", number)
            roleKey = nil
        } else {
            type = StringTemplate.template(nameKey(typeId)).addAmount("%number%", number)
            roleKey = Role.isDefaultRoleId(roleId) ? nil : roleId
        }
        let ret = StringTemplate.label("")
        if let name {
            ret.addName(name).addName(" (")
            if let nationId {
                ret.add(nameKey(nationId)).addName(" ")
                if let roleKey { ret.add(nameKey(roleKey)).addName("/") }
            } else if let roleKey {
                ret.add(nameKey(roleKey)).addName("/")
            }
            ret.addStringTemplate(type)
            if let extra { ret.addName("/").addStringTemplate(extra) }
            return ret.addName(")")
        }
        if let nationId {
            ret.add(nameKey(nationId)).addName(" ")
            if let roleKey {
                ret.add(nameKey(roleKey)).addName(" (").addStringTemplate(type)
                if let extra { ret.addName("/").addStringTemplate(extra) }
                return ret.addName(")")
            }
            ret.addStringTemplate(type)
            if let extra { ret.addName(" (").addStringTemplate(extra).addName(")") }
            return ret
        }
        if let roleKey {
            ret.add(nameKey(roleKey)).addName(" (").addStringTemplate(type)
            if let extra { ret.addName("/").addStringTemplate(extra) }
            return ret.addName(")")
        }
        guard let extra else { return type }
        return ret.addStringTemplate(type).addName(" (").addStringTemplate(extra).addName(")")
    }

    // MARK: Season names (from NameCache)

    /// The season names: "nameCache.season.0", ".1"... if there are at
    /// least two, otherwise spring and autumn (NameCache).  As in Java,
    /// they are collected from the bundle in use the first time they
    /// are asked for, and kept.
    nonisolated(unsafe) public static var seasonNames: [String]?

    public static func seasonName(_ index: Int) -> String {
        if seasonNames == nil {
            var names: [String] = []
            if containsKey("nameCache.season.0") { names.append(message("nameCache.season.0")) }
            var i = 1
            while containsKey("nameCache.season.\(i)") {
                names.append(message("nameCache.season.\(i)"))
                i += 1
            }
            if names.count < 2 {
                names = ["model.season.spring.name", "model.season.autumn.name"].map(message)
            }
            seasonNames = names
        }
        let names = seasonNames!
        if index >= 0 && index < names.count { return names[index] }
        return message(StringTemplate.template("nameCache.season.default").addAmount("%number%", index + 1))
            ?? ""
    }
}

/// Java String operations on UTF-16 code units.
enum JavaUTF16 {

    static func indexOf(_ s: [UInt16], _ c: UInt16, _ from: Int) -> Int? {
        var i = max(from, 0)
        while i < s.count {
            if s[i] == c { return i }
            i += 1
        }
        return nil
    }

    /// String.indexOf(String, int): an empty pattern is found at the
    /// start (clamped to the length).
    static func indexOf(_ s: [UInt16], _ pattern: [UInt16], _ from: Int) -> Int? {
        let start = max(from, 0)
        if pattern.isEmpty { return start <= s.count ? start : s.count }
        guard pattern.count <= s.count else { return nil }
        var i = start
        while i + pattern.count <= s.count {
            if s[i] == pattern[0] && Array(s[i..<(i + pattern.count)]) == pattern { return i }
            i += 1
        }
        return nil
    }

    /// String.replace(CharSequence, CharSequence): every occurrence,
    /// left to right; an empty target goes between every unit.
    static func replace(_ s: [UInt16], _ target: [UInt16], _ replacement: [UInt16]) -> [UInt16] {
        if target.isEmpty {
            var out: [UInt16] = replacement
            for c in s { out.append(c); out += replacement }
            return out
        }
        var out: [UInt16] = []
        var i = 0
        while let j = indexOf(s, target, i) {
            out += s[i..<j]
            out += replacement
            i = j + target.count
        }
        out += s[i...]
        return out
    }
}

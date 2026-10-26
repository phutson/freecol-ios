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

/// XML as a tree of JSON values, exactly as the Java dump tools make it
/// (net.sf.freecol.tools.dump.XmlTree), so the XML Swift writes can be
/// compared with the XML Java writes without caring about attribute
/// order or formatting.
///
/// Each element is an object with "tag", "attrs" (if any, an object),
/// "children" (if any) and "text" (the element's own text, trimmed, if
/// not empty).  Runs of sibling abilities or modifiers are sorted by
/// their canonical JSON, because Java writes them in hash order.
public enum XmlTree {

    /// The tags whose sibling order carries no meaning.
    static let unorderedTags: Set<String> = ["ability", "modifier"]

    /// Parse XML text into the tree of its document element.
    public static func parse(_ xml: String) throws -> JSONValue {
        let builder = Builder()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let root = builder.root else {
            throw XmlTreeError(parser.parserError.map { "\($0)" } ?? "no document element")
        }
        return root.json
    }

    /// Remove the first direct child with a tag.
    ///
    /// - Returns: The child removed, if any.
    @discardableResult
    public static func removeChild(_ tree: inout JSONValue, _ tag: String) -> JSONValue? {
        guard var members = tree.objectValue, var children = members["children"]?.arrayValue,
              let i = children.firstIndex(where: { $0["tag"]?.stringValue == tag }) else { return nil }
        let removed = children.remove(at: i)
        members["children"] = .array(children)
        tree = .object(members)
        return removed
    }

    /// Replace an attribute of the root, if it has it.
    public static func maskAttribute(_ tree: inout JSONValue, _ name: String, _ value: String) {
        guard var members = tree.objectValue, var attrs = members["attrs"]?.objectValue,
              attrs[name] != nil else { return }
        attrs[name] = .string(value)
        members["attrs"] = .object(attrs)
        tree = .object(members)
    }

    /// An element being built.
    final class Element {
        let tag: String
        let attributes: [String: String]
        var children: [Element] = []
        var text = ""

        init(_ tag: String, _ attributes: [String: String]) {
            self.tag = tag
            self.attributes = attributes
        }

        var json: JSONValue {
            var members: [String: JSONValue] = ["tag": .string(tag)]
            if !attributes.isEmpty { members["attrs"] = .object(attributes.mapValues(JSONValue.string)) }
            let kids = XmlTree.sortUnorderedRuns(children.map { ($0.tag, $0.json) })
            if !kids.isEmpty { members["children"] = .array(kids) }
            let t = XmlTree.javaTrim(text)
            if !t.isEmpty { members["text"] = .string(t) }
            return .object(members)
        }
    }

    /// Java's String.trim: without leading and trailing characters up
    /// to space.
    static func javaTrim(_ s: String) -> String {
        let units = Array(s.utf16)
        guard let first = units.firstIndex(where: { $0 > 0x20 }),
              let last = units.lastIndex(where: { $0 > 0x20 }) else { return "" }
        return String(decoding: units[first...last], as: UTF16.self)
    }

    /// Sort each run of adjacent abilities or of adjacent modifiers by
    /// canonical JSON, compared as Java strings.
    static func sortUnorderedRuns(_ children: [(tag: String, json: JSONValue)]) -> [JSONValue] {
        var result: [JSONValue] = []
        var i = 0
        while i < children.count {
            let tag = children[i].tag
            guard unorderedTags.contains(tag) else {
                result.append(children[i].json)
                i += 1
                continue
            }
            var j = i + 1
            while j < children.count && children[j].tag == tag { j += 1 }
            let run = children[i..<j].map { (key: String(CanonicalJSON.document($0.json).dropLast()), json: $0.json) }
            result += run.stableSorted { JavaString.compare($0.key, $1.key) < 0 }.map(\.json)
            i = j
        }
        return result
    }

    final class Builder: NSObject, XMLParserDelegate {
        var stack: [Element] = []
        var root: Element?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            stack.append(Element(elementName, attributeDict))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            let element = stack.removeLast()
            if let parent = stack.last {
                parent.children.append(element)
            } else {
                root = element
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(decoding: CDATABlock, as: UTF8.self)
        }
    }
}

/// XML the tree builder could not parse.
public struct XmlTreeError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

extension Sequence {
    /// Sorted, keeping equal elements in order, as Java's sort does.
    func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            areInIncreasingOrder(a.element, b.element)
                || (!areInIncreasingOrder(b.element, a.element) && a.offset < b.offset)
        }.map(\.element)
    }
}

extension XmlTree {

    /// The differences between two trees, Swift's first, by element
    /// path: attributes and text that differ, and children missing or
    /// extra.  Children are matched in order, so after a missing child
    /// the rest of its siblings differ too; look at the first.
    public static func differences(_ swift: JSONValue, _ java: JSONValue, _ path: String = "",
                                   limit: Int = 30) -> [String] {
        var out: [String] = []
        collect(swift, java, path, &out, limit)
        return out
    }

    private static func name(_ e: JSONValue) -> String {
        let tag = e["tag"]?.stringValue ?? "?"
        if let id = e["attrs"]?["id"]?.stringValue { return "\(tag)[\(id)]" }
        return tag
    }

    private static func collect(_ a: JSONValue, _ b: JSONValue, _ parent: String, _ out: inout [String],
                                _ limit: Int) {
        guard out.count < limit else { return }
        let path = parent + "/" + name(b)
        if a["tag"] != b["tag"] {
            out.append("\(parent): Swift \(name(a)) vs Java \(name(b))")
            return
        }
        let sa = a["attrs"]?.objectValue ?? [:], ja = b["attrs"]?.objectValue ?? [:]
        for key in Set(sa.keys).union(ja.keys).sorted() where sa[key] != ja[key] {
            out.append("\(path) @\(key): Swift \(sa[key]?.stringValue ?? "none")"
                + " vs Java \(ja[key]?.stringValue ?? "none")")
        }
        if a["text"] != b["text"] {
            out.append("\(path) text: Swift \(a["text"]?.stringValue ?? "none")"
                + " vs Java \(b["text"]?.stringValue ?? "none")")
        }
        let sc = a["children"]?.arrayValue ?? [], jc = b["children"]?.arrayValue ?? []
        for i in 0..<min(sc.count, jc.count) {
            collect(sc[i], jc[i], path, &out, limit)
            if out.count >= limit { return }
        }
        if sc.count > jc.count {
            out.append("\(path): extra in Swift \(sc[jc.count...].prefix(3).map(name))")
        } else if jc.count > sc.count {
            out.append("\(path): missing in Swift \(jc[sc.count...].prefix(3).map(name))")
        }
    }
}

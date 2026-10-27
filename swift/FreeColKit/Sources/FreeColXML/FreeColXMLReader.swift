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

/// An error reading FreeCol XML (Java's XMLStreamException).
public struct FreeColXMLError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

/// A pull-style reader over FreeCol XML, port of
/// common/io/FreeColXMLReader (a StAX stream reader).
///
/// The whole document is parsed first, with Foundation's XMLParser,
/// into a list of start and end tags; text, comments and whitespace are
/// dropped, as Java's nextTag skips them.  The reader then steps through
/// the tags the way Java's does, so ported readFromXML code keeps its
/// shape: nextTag, moreTags, closeTag and the typed getAttribute calls.
///
/// Attribute values are parsed with Java's rules (Integer.decode,
/// Float.parseFloat, Boolean.parseBoolean).  Where Java logs a warning
/// for a bad value and uses the default, so does this; the warnings are
/// collected in `warnings`.
public final class FreeColXMLReader {

    /// A tag the reader can stand on.
    public enum Event: Equatable, Sendable {
        case start
        case end
    }

    private let tags: [XMLTag]
    private var index = -1

    /// Warnings about bad attribute values, as Java logs them.
    public private(set) var warnings: [String] = []

    /// Objects created while reading because something referred to them
    /// before they were defined, kept alive until reading is done.
    private var retained: [AnyObject] = []

    /// Read a document.
    ///
    /// - Parameter data: The XML document.
    /// - Throws: FreeColXMLError if it is not well-formed XML.
    public init(data: Data) throws {
        let collector = TagCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw FreeColXMLError("XML parse error at line \(parser.lineNumber): "
                + (parser.parserError.map { "\($0)" } ?? "unknown"))
        }
        tags = collector.tags
    }

    /// Read a document from a string.
    public convenience init(string: String) throws {
        try self.init(data: Data(string.utf8))
    }

    private init(tags: [XMLTag]) {
        self.tags = tags
    }

    /// A reader of its own for the current element, standing before its
    /// start tag, while this one moves to the element's end: for an
    /// element to be read later, by something else.
    public func subReader() throws -> FreeColXMLReader {
        let start = index
        try swallowTag(localName)
        return FreeColXMLReader(tags: Array(tags[start...index]))
    }

    private var current: XMLTag {
        precondition(index >= 0 && index < tags.count, "Reader is not on a tag")
        return tags[index]
    }

    // MARK: Moving

    /// Move to the next start or end tag (Java's nextTag).
    @discardableResult
    public func nextTag() throws -> Event {
        guard index + 1 < tags.count else {
            throw FreeColXMLError("Unexpected end of document")
        }
        index += 1
        return tags[index].event
    }

    /// The name of the current tag.
    public var localName: String {
        current.name
    }

    /// Whether the current tag has a name.
    public func atTag(_ tag: String) -> Bool {
        localName == tag
    }

    /// Fail unless the current tag has a name.
    public func expectTag(_ tag: String) throws {
        let name = localName
        if name != tag {
            throw FreeColXMLError("Parse error, \(tag) expected, not: \(name)")
        }
    }

    /// Move to the next tag, and say whether it starts a child (true) or
    /// ends the current element (false).
    public func moreTags() throws -> Bool {
        try nextTag() != .end
    }

    /// The text of a text-only element, moving to its end tag (Java's
    /// getElementText).
    public func elementText() throws -> String {
        let text = current.text
        guard try nextTag() == .end else {
            throw FreeColXMLError("Text-only element expected: \(localName)")
        }
        return text
    }

    /// Move to the end of an element that should have no more children.
    public func closeTag(_ tag: String) throws {
        if try moreTags() {
            throw FreeColXMLError("Parse error, END_ELEMENT expected, not: \(localName)")
        }
        try expectTag(tag)
    }

    /// Move to the end of an element, closing any empty children with
    /// one of the other names on the way.
    public func closeTag(_ tag: String, others: [String]) throws {
        while try nextTag() != .end {
            guard let at = others.first(where: { atTag($0) }) else {
                throw FreeColXMLError("Parse error, END_ELEMENT(\(tag) or alternatives)"
                    + " expected, not: \(localName)")
            }
            try closeTag(at)
        }
        try expectTag(tag)
    }

    /// Skip to the end of an element, ignoring everything inside.
    public func swallowTag(_ tag: String) throws {
        var depth = 0
        while true {
            if try nextTag() == .start {
                depth += 1
            } else if depth == 0 {
                if localName == tag { return }
            } else {
                depth -= 1
            }
        }
    }

    /// A description of the current tag and its attributes.
    public var currentTag: String {
        let attrs = current.attributes.sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\($0.value)\"" }.joined()
        return "\(localName), attributes:\(attrs)"
    }

    /// Fail on an unexpected tag.
    public func unexpectedTag(_ context: String) throws -> Never {
        throw FreeColXMLError("In \(context), unexpected tag \(localName), at: \(currentTag)")
    }

    // MARK: Attributes

    /// Whether the current tag has an attribute.
    public func hasAttribute(_ name: String) -> Bool {
        current.attributes[name] != nil
    }

    /// A string attribute, or a default.
    public func attribute(_ name: String, default value: String?) -> String? {
        current.attributes[name] ?? value
    }

    /// A boolean attribute (Boolean.parseBoolean), or a default.
    public func attribute(_ name: String, default value: Bool) -> Bool {
        guard let s = current.attributes[name] else { return value }
        return JavaString.parseBoolean(s)
    }

    /// An int attribute (Integer.decode), or a default if missing or bad.
    public func attribute(_ name: String, default value: Int) -> Int {
        guard let s = current.attributes[name] else { return value }
        guard let v = JavaString.decodeIntOrNil(s) else {
            warnings.append("\(name) is not an integer: \(s)")
            return value
        }
        return Int(v)
    }

    /// A long attribute (Long.decode), or a default if missing or bad.
    public func attribute(_ name: String, default value: Int64) -> Int64 {
        guard let s = current.attributes[name] else { return value }
        guard let v = JavaString.decodeLongOrNil(s) else {
            warnings.append("\(name) is not a long: \(s)")
            return value
        }
        return v
    }

    /// A float attribute (Float.parseFloat), or a default if missing or bad.
    public func attribute(_ name: String, default value: Float) -> Float {
        guard let s = current.attributes[name] else { return value }
        guard let v = JavaString.parseFloat(s) else {
            warnings.append("\(name) is not a float: \(s)")
            return value
        }
        return v
    }

    /// An enum attribute, matched by Java constant name, or a default
    /// if missing or bad.
    public func attribute<T: JavaEnum>(_ name: String, _ type: T.Type, default value: T?) -> T? {
        guard let s = current.attributes[name] else { return value }
        guard let v = T(javaName: s) else {
            warnings.append("\(name) is not a \(T.self): \(s)")
            return value
        }
        return v
    }

    /// Some attributes of the current tag, where present.
    public func attributeMap(_ names: [String]) -> [String: String] {
        current.attributes.filter { names.contains($0.key) }
    }

    /// All attributes of the current tag.
    public var allAttributes: [String: String] {
        current.attributes
    }

    /// The "id" attribute, upgrading two identifier forms used by
    /// FreeCol 0.10.x saved games (@compat 0.11.x).
    public func readId() -> String? {
        guard let id = attribute("id", default: nil as String?) else { return nil }
        guard let colon = JavaString.indexOf(id, ":"), colon > 10 else { return id }
        switch JavaString.substring(id, 0, colon) {
        case "tileitemcontainer": return "tileItemContainer" + JavaString.substring(id, colon)
        case "tileimprovement": return "tileImprovement" + JavaString.substring(id, colon)
        default: return id
        }
    }

    /// Keep an object alive for as long as this reader.
    ///
    /// Java keeps objects that were created by reference (a tile naming
    /// a settlement that is defined later in the file) alive through
    /// the reference.  Where the Swift reference is weak, the reader
    /// holds the object until whatever contains it has been read.
    public func retain(_ object: AnyObject) {
        retained.append(object)
    }

    // MARK: Read scope

    /// Whether objects read are registered with their game: not while
    /// reading copies (Java's NOINTERN read scope).
    public private(set) var shouldIntern = true

    /// The objects read or made without registering, by identifier, so
    /// copies refer to each other.  Cleared when the scope changes, as
    /// in Java.
    public private(set) var uninterned: [String: AnyObject] = [:]

    /// Change whether objects are registered, returning the old value.
    @discardableResult
    public func replaceScope(intern: Bool) -> Bool {
        let old = shouldIntern
        if intern != old { uninterned.removeAll() }
        shouldIntern = intern
        return old
    }

    /// Note an object read without registering.
    public func addUninterned(_ id: String, _ object: AnyObject) {
        uninterned[id] = object
        retain(object)
    }

    /// Record a warning, as Java logs one.
    public func warn(_ message: String) {
        warnings.append(message)
    }

    /// Whether containers should be cleared before reading children: not
    /// when the element says "preserve".
    public var shouldClearContainers: Bool {
        !attribute("preserve", default: false)
    }

    /// Whether attributes should be read: not when the element says
    /// "preserve-attributes".
    public var shouldReadAttributes: Bool {
        !attribute("preserve-attributes", default: false)
    }
}

/// One start or end tag of a parsed document.
struct XMLTag {
    let event: FreeColXMLReader.Event
    let name: String
    let attributes: [String: String]
    /// For a start tag, the text up to the next tag.
    var text = ""
}

/// Collects start and end tags from XMLParser.
private final class TagCollector: NSObject, XMLParserDelegate {
    var tags: [XMLTag] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        tags.append(XMLTag(event: .start, name: elementName, attributes: attributes))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        tags.append(XMLTag(event: .end, name: elementName, attributes: [:]))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let last = tags.indices.last, tags[last].event == .start { tags[last].text += string }
    }
}

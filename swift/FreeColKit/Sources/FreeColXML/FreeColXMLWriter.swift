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

/// Writes FreeCol's XML (common/io/FreeColXMLWriter), for saved games,
/// specifications and what a server would send a client.
///
/// Attributes are written as Java writes them: booleans as "true" and
/// "false", numbers by Java's toString, enums by their constant name in
/// lower case, and objects by identifier.  The output is not indented.
public final class FreeColXMLWriter {

    /// What is being written for (FreeColXMLWriter.WriteScope).
    public struct WriteScope {

        public enum ScopeType: Sendable {
            /// Only what one player's client may see.
            case client
            /// Everything a server knows.
            case server
            /// Everything needed to save the game.
            case save
        }

        public let scopeType: ScopeType
        /// The player, for a client scope.
        public let player: AnyObject?

        public static func toClient(_ player: AnyObject) -> WriteScope {
            WriteScope(scopeType: .client, player: player)
        }

        public static func toServer() -> WriteScope {
            WriteScope(scopeType: .server, player: nil)
        }

        public static func toSave() -> WriteScope {
            WriteScope(scopeType: .save, player: nil)
        }

        /// A client scope has a player, and only it.
        public var isValid: Bool {
            (scopeType == .client) == (player != nil)
        }

        public var validForSave: Bool {
            scopeType == .save
        }

        /// Whether a player's private information may be written:
        /// always but for another player's client.
        public func validFor(_ other: AnyObject?) -> Bool {
            scopeType != .client || player === other
        }
    }

    public private(set) var writeScope: WriteScope

    private var output = ""
    private var openTags: [String] = []
    /// Whether the current start tag is still open for attributes.
    private var inStartTag = false

    public init(scope: WriteScope = .toSave()) {
        writeScope = scope
    }

    /// The XML written so far, with any open start tag closed.
    public var xml: String {
        output + (inStartTag ? ">" : "")
    }

    /// Change the scope, returning the old one.
    @discardableResult
    public func replaceScope(_ scope: WriteScope) -> WriteScope {
        let old = writeScope
        writeScope = scope
        return old
    }

    public var clientPlayer: AnyObject? {
        writeScope.player
    }

    public var validForSave: Bool {
        writeScope.validForSave
    }

    public func validFor(_ player: AnyObject?) -> Bool {
        writeScope.validFor(player)
    }

    // MARK: Elements

    public func writeStartElement(_ tag: String) {
        closeStartTag()
        output += "<" + tag
        openTags.append(tag)
        inStartTag = true
    }

    public func writeEndElement() {
        let tag = openTags.removeLast()
        if inStartTag {
            output += "/>"
            inStartTag = false
        } else {
            output += "</" + tag + ">"
        }
    }

    public func writeCharacters(_ text: String) {
        closeStartTag()
        output += Self.escape(text, attribute: false)
    }

    private func closeStartTag() {
        if inStartTag {
            output += ">"
            inStartTag = false
        }
    }

    // MARK: Attributes

    public func writeAttribute(_ name: String, _ value: String) {
        precondition(inStartTag, "Attribute \(name) outside a start tag")
        output += " " + name + "=\"" + Self.escape(value, attribute: true) + "\""
    }

    public func writeAttribute(_ name: String, _ value: Bool) {
        writeAttribute(name, value ? "true" : "false")
    }

    public func writeAttribute(_ name: String, _ value: Int) {
        writeAttribute(name, String(value))
    }

    public func writeAttribute(_ name: String, _ value: Int64) {
        writeAttribute(name, String(value))
    }

    /// Java's String.valueOf(float).
    public func writeAttribute(_ name: String, _ value: Float) {
        writeAttribute(name, JavaNumberFormat.string(value))
    }

    /// Java's String.valueOf(double).
    public func writeAttribute(_ name: String, _ value: Double) {
        writeAttribute(name, JavaNumberFormat.string(value))
    }

    /// An enum, as Java's downCase of its name.
    public func writeAttribute<E: JavaEnum>(_ name: String, _ value: E) {
        writeAttribute(name, value.javaName.lowercased())
    }

    /// An object by identifier; nothing for nil or an object without
    /// one.
    public func writeAttribute(_ name: String, id value: String?) {
        if let value { writeAttribute(name, value) }
    }

    /// A list of identifiers as Java's writeToListElement: an element
    /// with "xLength" and "x0", "x1", ... attributes, or nothing for an
    /// empty list.
    public func writeToListElement(_ tag: String, _ ids: [String?]) {
        if ids.isEmpty { return }
        writeStartElement(tag)
        writeAttribute("xLength", ids.count)
        for (i, id) in ids.enumerated() {
            writeAttribute(name: "x\(i)", id: id)
        }
        writeEndElement()
    }

    private func writeAttribute(name: String, id: String?) {
        writeAttribute(name, id: id)
    }

    // MARK: Escaping

    /// XML escapes, as Java's stream writer makes them.
    static func escape(_ s: String, attribute: Bool) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where attribute: out += "&quot;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }
}

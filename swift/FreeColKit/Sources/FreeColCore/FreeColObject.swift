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
import FreeColXML

/// Something with an identifier (net.sf.freecol.common.ObjectWithId).
public protocol ObjectWithId: AnyObject {
    var id: String? { get }
}

/// Something with a message key for its name (common/model/Named).
public protocol Named {
    var nameKey: String { get }
}

/// The root of all FreeCol objects (common/model/FreeColObject).
///
/// This port covers identifiers, ordering, equality and the hooks for
/// the specification and game.  The rest of the Java class follows
/// with the parts it depends on: abilities and modifiers (port step 2),
/// XML reading and writing (with FreeColXML), and copying.  Java's
/// PropertyChangeSupport is only used by the Swing client and is not
/// ported.
///
/// Equality and hashing follow Java's equals and hashCode, so sets and
/// dictionaries of FreeCol objects behave as Java's do.  Swift's hash
/// values are not Java's, so never port code whose result depends on
/// Java's HashSet or HashMap iteration order without making that order
/// explicit (see JavaString.hashCode).
///
/// FreeColObject is deliberately not Comparable: compareIds can find
/// two different identifiers equal ("unit:7" and "unit:07"), which
/// Swift's Comparable does not allow.  Sort with `compareIds` instead.
open class FreeColObject: ObjectWithId, Hashable, CustomStringConvertible {

    /// The class index used when nothing more specific applies.
    public static let defaultClassIndex = 1000

    /// The identifier attribute in XML.
    public static let idTag = "id"

    /// The identifier.  Java has no constructors setting it, because
    /// some objects only learn their identifier while being read.
    public var id: String?

    public init() {}

    /// The XML element name for this kind of object.  Every concrete
    /// subclass must override this (Java's abstract getXMLTagName).
    open var xmlTagName: String {
        fatalError("\(type(of: self)) must override xmlTagName")
    }

    // MARK: Identifiers

    /// Whether another object has the same non-null identifier.
    public func idEquals(_ other: FreeColObject?) -> Bool {
        guard let other, let id else { return false }
        return id == other.id
    }

    /// The identifier with a prefix removed, or the whole identifier if
    /// it does not start with the prefix.
    public final func suffix(afterPrefix prefix: String) -> String? {
        guard let id else { return nil }
        return JavaString.startsWith(id, prefix)
            ? JavaString.substring(id, prefix.utf16.count) : id
    }

    /// The last part of the identifier after a ".", such as
    /// "freeColonist" for "model.unit.freeColonist".
    public final var suffix: String? {
        id.map { JavaString.lastPart($0, ".") }
    }

    /// The type part of an identifier: everything before the last ":",
    /// or the whole identifier if there is none ("unit" for "unit:123").
    public static func idType(of id: String?) -> String? {
        guard let id else { return nil }
        guard let colon = JavaString.lastIndexOf(id, ":") else { return id }
        return JavaString.substring(id, 0, colon)
    }

    /// The type part of this object's identifier.
    public var idType: String? {
        FreeColObject.idType(of: id)
    }

    /// The number after the last ":" in the identifier, or -1 if there
    /// is none or it is not a valid int.
    public var idNumber: Int {
        FreeColObject.idNumber(of: id)
    }

    /// The number after the last ":" in an identifier, or -1.
    public static func idNumber(of id: String?) -> Int {
        guard let id, let colon = JavaString.lastIndexOf(id, ":") else { return -1 }
        var s = JavaString.substring(id, colon + 1)
        // @compat 0.11.6: AI identifiers were <thing>:am<number>.
        if JavaString.startsWith(s, "am") { s = JavaString.substring(s, 2) }
        return JavaString.parseInt(s).map(Int.init) ?? -1
    }

    /// Compare identifiers: missing objects and identifiers first, then
    /// by identifier type in Java string order, then by number.
    ///
    /// - Returns: -1, 0 or 1.
    public static func compareIds(_ a: FreeColObject?, _ b: FreeColObject?) -> Int {
        guard let a else { return b == nil ? 0 : -1 }
        guard let b else { return 1 }
        return compareIdentifiers(a.id, b.id)
    }

    /// compareIds for identifiers: missing ones first.
    public static func compareIdentifiers(_ a: String?, _ b: String?) -> Int {
        guard a != nil else { return b == nil ? 0 : -1 }
        guard b != nil else { return 1 }
        let cmp = JavaString.compare(idType(of: a)!, idType(of: b)!)
        if cmp != 0 { return cmp > 0 ? 1 : -1 }
        let na = idNumber(of: a), nb = idNumber(of: b)
        return na < nb ? -1 : na > nb ? 1 : 0
    }

    /// Java's compareTo: the same as compareIds.
    public func compareTo(_ other: FreeColObject?) -> Int {
        FreeColObject.compareIds(self, other)
    }

    /// An ordering predicate by compareIds, for sorting.
    public static func idOrder(_ a: FreeColObject, _ b: FreeColObject) -> Bool {
        compareIds(a, b) < 0
    }

    /// The index of this kind of object, used to order mixed objects.
    open var classIndex: Int {
        FreeColObject.defaultClassIndex
    }

    /// The class index of any value: its own for FreeCol objects,
    /// otherwise the default.
    public static func objectClassIndex(_ o: Any?) -> Int {
        (o as? FreeColObject)?.classIndex ?? defaultClassIndex
    }

    // MARK: Specification and game

    /// The specification this object belongs to, if any.  Plain
    /// FreeColObjects have none; FreeColSpecObjects hold one and
    /// FreeColGameObjects use their game's.
    open var specification: Specification? {
        nil
    }

    /// Set the specification, where the subclass holds one.
    open func setSpecification(_ specification: Specification?) {}

    /// The game this object belongs to, if any.
    open var game: Game? {
        nil
    }

    /// Set the game, where the subclass holds one.
    open func setGame(_ game: Game) {}

    // MARK: Features
    //
    // Plain FreeColObjects have no features; subclasses with a feature
    // container provide one, and these methods then work through it.
    // Some subclasses add features of their own by overriding
    // abilities(_:for:turn:) or modifiers(_:for:turn:), as Java's
    // Europe adds the ability to dress missionaries.

    /// The container of this object's own abilities and modifiers.
    open var featureContainer: FeatureContainer? {
        nil
    }

    /// The abilities with an id (or all, for nil) that apply to a
    /// target in a turn.
    open func abilities(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                        turn: Turn? = nil) -> [Ability] {
        featureContainer?.abilities(id, for: target, turn: turn) ?? []
    }

    /// Whether the applicable abilities with an id exist and are all
    /// true.
    public final func hasAbility(_ id: String?, for target: FreeColSpecObjectType? = nil,
                                 turn: Turn? = nil) -> Bool {
        FeatureContainer.allAbilities(abilities(id, for: target, turn: turn))
    }

    /// Whether there is any ability with an id.
    open func containsAbilityKey(_ key: String) -> Bool {
        !abilities(key).isEmpty
    }

    /// All applicable abilities, by id (Java's getSortedAbilities).
    public final var sortedAbilities: [Ability] {
        abilities().sorted(by: FreeColObject.idOrder)
    }

    /// Add an ability.
    ///
    /// - Returns: false if there is no container or it already had it.
    @discardableResult
    open func addAbility(_ ability: Ability?) -> Bool {
        featureContainer?.addAbility(ability) ?? false
    }

    /// Remove an ability.
    @discardableResult
    open func removeAbility(_ ability: Ability?) -> Ability? {
        featureContainer?.removeAbility(ability)
    }

    /// Remove all abilities with an id.
    open func removeAbilities(_ id: String) {
        featureContainer?.removeAbilities(id)
    }

    /// The modifiers with an id (or all, for nil) that apply to a
    /// target in a turn.
    open func modifiers(_ id: String? = nil, for target: FreeColSpecObjectType? = nil,
                        turn: Turn? = nil) -> [Modifier] {
        featureContainer?.modifiers(id, for: target, turn: turn) ?? []
    }

    /// Whether any applicable modifier with an id exists.
    open func hasModifier(_ id: String?, for target: FreeColSpecObjectType? = nil,
                          turn: Turn? = nil) -> Bool {
        !modifiers(id, for: target, turn: turn).isEmpty
    }

    /// Whether any modifier with an id applies when nothing is given.
    public final func containsModifierKey(_ key: String) -> Bool {
        !modifiers(key).isEmpty
    }

    /// Every modifier held, unfiltered, in application order.
    ///
    /// Unlike modifiers(nil), this includes modifiers whose scopes do
    /// not match a missing target, as Java's getModifiers() does.
    public final var allModifiers: [Modifier] {
        featureContainer?.modifierValues ?? []
    }

    /// Every modifier held, in application order (Java's
    /// getSortedModifiers).
    public final var sortedModifiers: [Modifier] {
        allModifiers
    }

    /// Apply the modifiers with an id to a number.
    public final func apply(_ number: Float, turn: Turn?, _ id: String?,
                            for target: FreeColSpecObjectType? = nil) -> Float {
        FeatureContainer.applyModifiers(number, turn: turn,
                                        modifiers(id, for: target, turn: turn))
    }

    /// Add a modifier.
    ///
    /// - Returns: false if there is no container or it already had it.
    @discardableResult
    open func addModifier(_ modifier: Modifier?) -> Bool {
        featureContainer?.addModifier(modifier) ?? false
    }

    /// Remove a modifier.
    @discardableResult
    open func removeModifier(_ modifier: Modifier?) -> Modifier? {
        featureContainer?.removeModifier(modifier)
    }

    /// Remove all modifiers with an id.
    open func removeModifiers(_ id: String) {
        featureContainer?.removeModifiers(id)
    }

    /// Add all the features of another object.
    open func addFeatures(of object: FreeColObject) {
        featureContainer?.addFeatures(of: object)
    }

    /// Remove the features that came from another object.
    open func removeFeatures(of object: FreeColObject) {
        featureContainer?.removeFeatures(of: object)
    }

    /// The defence modifiers that apply when nothing is given.
    open var defenceModifiers: [Modifier] {
        modifiers(Modifier.defence)
    }

    // MARK: Scope support
    //
    // Java scopes find these by reflection.  Swift has none, so objects
    // answer explicitly; anything not answered behaves as Java does
    // when the method is missing.

    /// The specification type of this object, if it has one: what
    /// Java's reflective call to getType() finds.  For example a unit's
    /// unit type or a tile's tile type.
    open var scopeType: FreeColSpecObjectType? {
        nil
    }

    /// The result of the named method, as Java's String.valueOf gives
    /// it ("true", "42", "null"), or nil where Java has no such method.
    ///
    /// The rules use isIndian, isWater and isForested in scopes; each
    /// class answers for its own methods when it is ported.
    open func scopeMethodValue(_ methodName: String) -> String? {
        nil
    }

    // MARK: Reading XML
    //
    // Java's template: readFromXML clears containers (unless the element
    // says "preserve"), reads attributes (unless "preserve-attributes"),
    // then reads children one by one until the element ends.  Subclasses
    // override the parts and call super, as in Java.
    //
    // Differences: Java's readChildren logs and swallows errors from a
    // child; here they propagate.

    /// Read this object from the element the reader is on, leaving the
    /// reader on its end tag.
    open func readFromXML(_ xr: FreeColXMLReader) throws {
        if xr.hasAttribute("partial") {
            try readFromXMLPartial(xr)
            return
        }
        if xr.shouldClearContainers { try clearContainers(xr) }
        if xr.shouldReadAttributes { try readAttributes(xr) }
        try readChildren(xr)
    }

    /// Empty the containers that the children refill.
    open func clearContainers(_ xr: FreeColXMLReader) throws {}

    /// Read the attributes: here, just the identifier if present.
    open func readAttributes(_ xr: FreeColXMLReader) throws {
        if let newId = xr.readId() { id = newId }
    }

    /// Read the children until the element ends.
    open func readChildren(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        while try xr.moreTags() {
            try readChild(xr)
        }
        try xr.expectTag(tag)
    }

    /// Read one child element.  The default rejects it.
    open func readChild(_ xr: FreeColXMLReader) throws {
        try xr.unexpectedTag(xmlTagName)
    }

    /// A partial read: set just the attributes given (Java's
    /// readFromXMLPartial).  Mods use this to change a few attributes of
    /// an existing type, and the server to send client updates.
    public final func readFromXMLPartial(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        id = xr.readId()
        for (name, value) in xr.allAttributes where name != "id" && name != "partial" {
            // Java logs a warning for a field it cannot set.
            _ = setPartialAttribute(name, value)
        }
        try xr.closeTag(tag)
    }

    /// Set one attribute in a partial read.  Java finds the setter by
    /// reflection ("attack-range" calls setAttackRange); here each class
    /// answers for the setters Java has.
    ///
    /// - Returns: Whether the attribute was set.
    open func setPartialAttribute(_ name: String, _ value: String) -> Bool {
        false
    }

    // MARK: Writing XML
    //
    // Java's template: toXML writes the start tag, the attributes, the
    // children and the end tag; subclasses override the parts and call
    // super, as in Java.  What a scope may see is decided in the parts,
    // with the writer's validFor.

    /// Write this object as its own element.
    public final func toXML(_ xw: FreeColXMLWriter) {
        toXML(xw, tag: xmlTagName)
    }

    /// Write this object as an element with the given tag.
    open func toXML(_ xw: FreeColXMLWriter, tag: String) {
        xw.writeStartElement(tag)
        writeAttributes(xw)
        writeChildren(xw)
        xw.writeEndElement()
    }

    /// Write the attributes: here, the identifier.  Java logs a
    /// warning for an object without one.
    open func writeAttributes(_ xw: FreeColXMLWriter) {
        if let id { xw.writeAttribute(Self.idTag, id) }
    }

    /// Write the children.  The default has none.
    open func writeChildren(_ xw: FreeColXMLWriter) {}

    /// This object as XML for a scope (Java's serialize).
    public final func serialize(_ scope: FreeColXMLWriter.WriteScope = .toServer()) -> String {
        let xw = FreeColXMLWriter(scope: scope)
        toXML(xw)
        return xw.xml
    }

    // MARK: Equality, hashing, description

    /// Java's equals.  Override this, not `==`.
    open func isEqual(to other: FreeColObject) -> Bool {
        id == other.id
    }

    public static func == (lhs: FreeColObject, rhs: FreeColObject) -> Bool {
        lhs.isEqual(to: rhs)
    }

    /// Hash consistently with `isEqual(to:)`.
    open func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    open var description: String {
        "\(type(of: self)):\(id ?? "null")"
    }
}

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

/// A game (common/model/Game).
///
/// Every game object is registered by identifier, so references in
/// saved games and messages can be resolved.  The game holds its
/// players and map.
///
/// A game is itself a game object with identifier "0", whose game is
/// itself.
///
/// The combat model is in CombatModel.swift.  Not yet ported: player
/// order and turn handling, the statistics, copyIn and
/// checkIntegrity.
///
/// Not thread safe: Java locks the registry, but the Swift engine is
/// meant to run inside one actor.
open class Game: FreeColGameObject {

    public static let tag = "game"

    /// Clean dead registry entries after this many removals.
    private static let removeCleanThreshold = 64

    private struct WeakEntry {
        weak var object: FreeColGameObject?
        /// When it was registered, for Java's order within a bucket.
        var sequence: Int
    }

    private var objects: [String: WeakEntry] = [:]
    private var registrations = 0
    private var removeCount = 0
    private var storedSpecification: Specification?

    /// The next identifier number to issue (saved as "nextId").
    public var nextId = 1

    /// The players, in turn order, without the unknown enemy.
    public private(set) var players: [Player] = []
    /// The player standing for enemies a player has not met.
    public private(set) var unknownEnemy: Player?
    public var map: Map?
    public weak var currentPlayer: Player?
    public var turn = Turn(1)
    public var spanishSuccession = false
    public var initialActiveUnitId: String?
    /// The game's identity across saves, as a UUID string.
    public private(set) var uuid = UUID().uuidString.lowercased()
    /// The name of the player a client game was sent to.
    public private(set) var clientUserName: String?
    /// The names of the cities of Cibola not yet found (Java keeps these
    /// in the static NameCache).
    public var citiesOfCibola: [String] = []

    /// Create a game.
    ///
    /// - Parameter specification: The rules to play by.
    public init(specification: Specification? = nil) {
        storedSpecification = specification
        super.init(asGame: ())
        setGameReferenceToSelf(self)
        internId("0") // Games are always "0"
        isInitialized = true
    }

    open override var xmlTagName: String {
        Game.tag
    }

    /// Issue the next identifier number.  Only server games issue
    /// identifiers; in Java the base game throws.
    open func getNextId() -> Int {
        fatalError("game.getNextId not implemented: \(self)")
    }

    // MARK: Registry

    /// The live object with an identifier, or nil.
    public func getFreeColGameObject(_ id: String?) -> FreeColGameObject? {
        guard let id, !id.isEmpty, let entry = objects[id] else { return nil }
        guard let object = entry.object else {
            removeFreeColGameObject(id, reason: "missed")
            return nil
        }
        return object
    }

    /// The live object with an identifier, if it has the given type.
    public func getFreeColGameObject<T: FreeColGameObject>(_ id: String?,
                                                           as type: T.Type) -> T? {
        getFreeColGameObject(id) as? T
    }

    /// Register an object, replacing any existing registration.
    public func setFreeColGameObject(_ id: String, _ fcgo: FreeColGameObject) {
        precondition(!id.isEmpty, "Null/empty identifier: \(self)")
        // Replacing keeps the place, as Java's HashMap.put does.
        if objects[id] != nil {
            objects[id]!.object = fcgo
        } else {
            registrations += 1
            objects[id] = WeakEntry(object: fcgo, sequence: registrations)
        }
    }

    /// Register a new object.  It is an error if a live object is
    /// already registered with this identifier.
    public func addFreeColGameObject(_ id: String, _ fcgo: FreeColGameObject) {
        precondition(!id.isEmpty, "Null/empty identifier: \(self)")
        if let old = getFreeColGameObject(id) {
            preconditionFailure("Tried to replace FCGO \(id) : \(type(of: old))"
                + " with \(fcgo.id ?? "null") : \(type(of: fcgo))")
        }
        setFreeColGameObject(id, fcgo)
    }

    /// Unregister an identifier.
    ///
    /// - Parameters:
    ///   - id: The identifier.
    ///   - reason: Why, for debugging (Java logs it).
    public func removeFreeColGameObject(_ id: String, reason: String) {
        precondition(!id.isEmpty, "Null/empty identifier: \(self)")
        objects[id] = nil
        removeCount += 1
        if removeCount > Game.removeCleanThreshold {
            objects = objects.filter { $0.value.object != nil }
            removeCount = 0
        }
    }

    /// All live registered objects, in identifier order.
    ///
    /// Java returns these in HashMap order, which depends on Java's
    /// String hash codes.  Code being ported that depends on that order
    /// must say so; this order is only guaranteed to be stable.
    public var freeColGameObjects: [FreeColGameObject] {
        // The identifier parts are worked out once per object, not once
        // per comparison: there are tens of thousands of objects.
        let keyed = objects.values.compactMap(\.object).map { o in
            (object: o, type: o.idType ?? "", number: o.idNumber, id: o.id ?? "")
        }
        return keyed.sorted { a, b in
            let c = JavaString.compare(a.type, b.type)
            if c != 0 { return c < 0 }
            if a.number != b.number { return a.number < b.number }
            return JavaString.compare(a.id, b.id) < 0
        }.map(\.object)
    }

    /// All live registered objects in the order Java's HashMap of
    /// them iterates (getFreeColGameObjectList), for the code that
    /// depends on it: by bucket of a table made for 10000 objects
    /// (doubled as Java would for more), then in the order registered.
    public var freeColGameObjectsInJavaOrder: [FreeColGameObject] {
        var n = 16384
        while objects.count > n / 4 * 3 { n *= 2 }
        let mask = Int32(n - 1)
        let keyed = objects.compactMap { id, e -> (object: FreeColGameObject, bucket: Int32, sequence: Int)? in
            guard let o = e.object else { return nil }
            let h = JavaString.hashCode(id)
            return (o, (h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16)) & mask, e.sequence)
        }
        return keyed.sorted { $0.bucket != $1.bucket ? $0.bucket < $1.bucket : $0.sequence < $1.sequence }
            .map(\.object)
    }

    // MARK: Players

    /// Keep a player read from a saved game, as the unknown enemy if it
    /// is that.
    private func readPlayer(_ player: Player) {
        if player.isUnknownEnemy {
            unknownEnemy = player
        } else {
            players.append(player)
        }
    }

    /// Add a new player, taking its nation out of the nation options.
    public func addPlayer(_ player: Player) {
        if !players.contains(where: { $0 === player }) { players.append(player) }
        if let nation = specification?.getNation(player.nationId) {
            nationOptions?.setNationState(nation, .notAvailable)
        }
    }

    /// Sort the players, keeping the order of equal ones (Java's
    /// List.sort is stable), as -1, 0 or 1.
    public func sortPlayers(_ compare: (Player, Player) -> Int) {
        players = players.enumerated().sorted {
            let c = compare($0.element, $1.element)
            return c != 0 ? c < 0 : $0.offset < $1.offset
        }.map(\.element)
    }

    /// The first nation still available to a new player.
    public var vacantNation: Nation? {
        nationOptions?.nationStates.first { $0.state == .available }?.nation
    }

    public var canAddNewPlayer: Bool {
        vacantNation != nil
    }

    /// Change the map, moving the players' high seas destinations to
    /// the new one.
    public func changeMap(_ newMap: Map?) {
        let oldMap = map
        map = newMap
        if newMap !== oldMap {
            for highSeas in livePlayers.compactMap(\.highSeas) {
                if let oldMap { highSeas.removeDestination(oldMap) }
                highSeas.addDestination(newMap)
            }
        }
    }

    /// Move an object between its old and new owners' lists, after its
    /// owner changes (Java's checkOwners).
    public func checkOwners(_ o: Ownable, oldOwner: Player?) {
        let newOwner = o.owner
        if oldOwner === newOwner { return }
        if let oldOwner, oldOwner.removeOwnable(o) { oldOwner.invalidateCanSeeTiles() }
        if let newOwner, newOwner.addOwnable(o) { newOwner.invalidateCanSeeTiles() }
    }

    public func player(byNationId nationId: String?) -> Player? {
        players.first { $0.nationId == nationId }
    }

    public func player(byName name: String?) -> Player? {
        players.first { $0.name == name }
    }

    // MARK: FreeColObject

    open override var specification: Specification? {
        storedSpecification
    }

    open override func setSpecification(_ specification: Specification?) {
        storedSpecification = specification
    }

    // MARK: Reading XML
    //
    // The order of the children matters: the specification (if saved)
    // comes first, and the players before the map, so tiles can find
    // their owners.

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        nextId = xr.attribute("nextId", default: -1)
        clientUserName = xr.attribute("clientUserName", default: nil as String?)
        if let str = xr.attribute("UUID", default: nil as String?) {
            // A bad UUID keeps the existing one.
            if let u = UUID(uuidString: str) { uuid = u.uuidString.lowercased() }
        } else {
            uuid = UUID().uuidString.lowercased()
        }
        turn = Turn(xr.attribute("turn", default: 1))
        spanishSuccession = xr.attribute("spanishSuccession", default: false)
        initialActiveUnitId = xr.attribute("initialActiveUnitId", default: nil as String?)
        // The current player is found once the players are read.
    }

    // MARK: Writing XML

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if xw.validForSave {
            xw.writeAttribute("nextId", nextId)
        } else if let client = xw.clientPlayerObject {
            xw.writeAttribute("clientUserName", id: client.name)
        }
        xw.writeAttribute("UUID", uuid)
        xw.writeAttribute("turn", turn.number)
        xw.writeAttribute("spanishSuccession", spanishSuccession)
        xw.writeAttribute("initialActiveUnitId", id: initialActiveUnitId)
        xw.writeAttribute("currentPlayer", currentPlayer)
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        specification?.toXML(xw)
        for city in citiesOfCibola { xw.writeIdElement("cibola", city) }
        nationOptions?.toXML(xw)
        for player in players { player.toXML(xw) }
        unknownEnemy?.toXML(xw)
        map?.toXML(xw)
        xw.writeStartElement("areas")
        for area in areas.values { area.toXML(xw) }
        xw.writeEndElement()
    }

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        citiesOfCibola = []
        players = []
        unknownEnemy = nil
        let current = xr.attribute("currentPlayer", default: nil as String?)
        try super.readChildren(xr)
        currentPlayer = try xr.lookup(self, current, Player.self)
        // Give every work location a sensible production type, now that
        // all the tiles are read.
        for c in allColonies { c.updateProductionTypes() }
    }

    /// The unit that was active when the game was saved.
    public var initialActiveUnit: Unit? {
        getFreeColGameObject(initialActiveUnitId) as? Unit
    }

    /// Which nations the game offers.
    public var nationOptions: NationOptions?

    /// The map editor's areas, by identifier in Java's HashMap order.
    private var areas = JavaHashMap<String, Area>(javaHash: JavaString.hashCode)

    public var areaList: [Area] {
        areas.values
    }

    public func addArea(_ area: Area) {
        if let id = area.id { _ = areas.put(id, area) }
    }

    /// A nation's starting area, if it has one.
    public func nationStartingArea(_ nation: Nation) -> Area? {
        areas[Area.prefixPlayerStartingPosition + (nation.id ?? "")]
    }

    /// Add an empty starting area for each nation that may play.
    public func generateDefaultAreas() {
        for nation in specification?.nations ?? [] where !nation.isUnknownEnemy && !(nation.type?.isREF ?? false) {
            let id = Area.prefixPlayerStartingPosition + (nation.id ?? "")
            if areas[id] == nil { addArea(Area(game: self, id: id, nameKey: nation.nameKey)) }
        }
    }

    /// The players that are not dead.
    public var livePlayers: [Player] {
        players.filter { !$0.isDead }
    }

    /// The live European players.
    public var liveEuropeanPlayers: [Player] {
        players.filter { !$0.isDead && $0.isEuropean }
    }

    /// The colonies of the live European players.
    public var allColonies: [Colony] {
        liveEuropeanPlayers.flatMap(\.colonyList)
    }

    /// The live players other than some.
    public func livePlayers(excluding exclude: Player?...) -> [Player] {
        livePlayers.filter { p in !exclude.contains { $0 === p } }
    }

    /// The live European players other than some.
    public func liveEuropeanPlayers(excluding exclude: Player?...) -> [Player] {
        liveEuropeanPlayers.filter { p in !exclude.contains { $0 === p } }
    }

    /// The live native players other than some.
    public func liveNativePlayers(excluding exclude: Player?...) -> [Player] {
        players.filter { p in !p.isDead && p.isIndian && !exclude.contains { $0 === p } }
    }

    /// The colonies of the live European players other than one.
    public func allColonies(excluding player: Player?) -> [Colony] {
        liveEuropeanPlayers(excluding: player).flatMap(\.colonyList)
    }

    /// A live player's settlement with a name (getSettlementByName).
    public func settlement(byName name: String?) -> Settlement? {
        livePlayers.lazy.flatMap(\.settlements).first { $0.name == name }
    }

    /// The registered object with an identifier, if it is a location
    /// (findFreeColLocation).
    public func findFreeColLocation(_ id: String?) -> (any Location)? {
        getFreeColGameObject(id) as? any Location
    }

    public func player(byNation nation: Nation?) -> Player? {
        player(byNationId: nation?.id)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        switch tag {
        case "cibola":
            var cibola = xr.readId() ?? ""
            // @compat 0.11.3
            if JavaString.startsWith(cibola, "lostCityRumour.cityName") {
                cibola = "nameCache." + cibola
            }
            citiesOfCibola.append(cibola)
            try xr.closeTag(tag)
        case Map.tag:
            guard specification != nil else {
                throw FreeColXMLError("Tried to read \(tag) with null specification")
            }
            map = try xr.readFreeColObject(self, Map.self)
        case "nationOptions":
            guard specification != nil else {
                throw FreeColXMLError("Tried to read \(tag) with null specification")
            }
            nationOptions = try NationOptions(xr, specification: specification)
        case "areas":
            while try xr.moreTags() {
                if let area = try xr.readFreeColObject(self, Area.self), let id = area.id {
                    _ = areas.put(id, area)
                }
            }
        case Player.tag:
            guard specification != nil else {
                throw FreeColXMLError("Tried to read \(tag) with null specification")
            }
            if let player = try xr.readFreeColObject(self, Player.self) { readPlayer(player) }
        case Specification.tag:
            setSpecification(try Specification(reading: xr))
        default:
            try super.readChild(xr)
        }
    }
}

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

import FreeColCore
import FreeColServer
import FreeColUtil
import FreeColXML

/// How sound an object is (Java's IntegrityType): failed, fixed, or
/// good.
public enum Integrity: Int, Sendable {
    case fail = -1
    case fixed = 0
    case good = 1

    /// Not failed (safe).
    public var isSafe: Bool { self != .fail }

    /// Good becomes fixed; the others stay (fix).
    func fixed() -> Integrity { self == .good ? .fixed : self }

    /// The worse of the two (combine).
    func combine(_ other: Integrity) -> Integrity {
        rawValue <= other.rawValue ? self : other
    }
}

/// Something the AI keeps, by identifier (server/ai/AIObject).
open class AIObject {
    public unowned let aiMain: AIMain
    public private(set) var id: String?
    public var initialized = false

    /// An object with no identifier, not registered (a mission).
    init(_ aiMain: AIMain) {
        self.aiMain = aiMain
    }

    /// An object registered under an identifier.
    init(_ aiMain: AIMain, _ id: String?) {
        self.aiMain = aiMain
        if let id {
            self.id = id
            aiMain.addAIObject(id, self)
        }
    }

    public var game: ServerGame { aiMain.game }
    public var specification: Specification? { aiMain.game.specification }

    /// Forget the object (dispose).
    open func dispose() {
        if let id { aiMain.removeAIObject(id) }
    }

    public var isDisposed: Bool {
        guard let id else { return true }
        return aiMain.aiObject(id) == nil
    }

    // MARK: Saving

    /// The element an object is saved as.
    open var xmlTag: String { "" }

    /// Whether the object is sound, fixing what can be fixed
    /// (checkIntegrity).
    open func checkIntegrity(_ fix: Bool) -> Integrity {
        initialized ? .good : .fail
    }

    /// Mark the object initialized if it now has what it needs, after
    /// reading (setInitialized).
    open func setInitialized() {}

    open func toXML(_ xw: FreeColXMLWriter) {
        xw.writeStartElement(xmlTag)
        writeAttributes(xw)
        writeChildren(xw)
        xw.writeEndElement()
    }

    open func writeAttributes(_ xw: FreeColXMLWriter) {
        xw.writeAttribute(FreeColObject.idTag, id: id)
    }

    open func writeChildren(_ xw: FreeColXMLWriter) {}

    /// Read the object from its element (readFromXML), leaving the
    /// reader on its end tag.
    func readFromXML(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        try readAttributes(xr)
        try readChildren(xr)
        try xr.expectTag(tag)
    }

    open func readAttributes(_ xr: FreeColXMLReader) throws {}

    open func readChildren(_ xr: FreeColXMLReader) throws {
        while try xr.moreTags() { try readChild(xr) }
    }

    /// An element the object does not know: Java logs it and skips it.
    open func readChild(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        xr.warn("Unexpected tag \(tag) in \(xmlTag)")
        try xr.swallowTag(tag)
    }
}

/// The AI of the computer players (server/ai/AIMain): an AI object for
/// each computer player, unit and colony, made as the game makes them,
/// and the messages each computer player is sent, handled as they
/// arrive.
///
/// Java's AI runs each player's turn, and each answer, in a thread of
/// its own.  Here everything runs at once on the caller's thread, as the
/// AI oracle runs Java's (see doc/swift-port-plan.md, Phase 4).
public final class AIMain: FreeColGameObjectListener {

    /// Which AI players work their turns: all of them; only the
    /// natives (the others only end their turns); or the natives and
    /// the Europeans' colonies (not their units' missions, as the AI
    /// oracle's patched EuropeanAIPlayer does), while the European AI is
    /// being ported.
    public enum Works: Sendable, Equatable {
        case all
        case natives
        case colonies
    }

    public let game: ServerGame
    public let controller: InGameController
    public var works: Works
    /// Whether the game is single player, when Java's AI cheats.
    public var singlePlayer = true
    var aiObjects: [String: AIObject] = [:]
    /// The number for the next AI object's identifier.
    var nextIdNumber = 1
    /// Errors the AI met that Java's would not have: commands not yet
    /// ported, and the like.  Java logs and carries on.
    public private(set) var errors: [String] = []

    /// The AI for a game, with an AI player for each AI player that has
    /// its seed (as made when the game was built) and an AI unit and
    /// colony for each unit and colony.  From now on it is told of new
    /// objects, and handles what its players are sent.
    public init(game: ServerGame, controller: InGameController, works: Works = .all) {
        self.game = game
        self.controller = controller
        self.works = works
        for player in game.players + [game.unknownEnemy].compactMap({ $0 }) where player.isAI {
            makeAIPlayer(player)
        }
        findNewObjects()
        game.freeColGameObjectListener = self
        attach()
    }

    /// The AI for a saved game read without it, made afresh as Java's
    /// server does when a saved game's AI fails its check
    /// (findNewObjects): every object in Java's order, each AI player
    /// taking a seed from the server's generator as it is found.
    public init(remaking game: ServerGame, controller: InGameController, works: Works = .all) {
        self.game = game
        self.controller = controller
        self.works = works
        for fcgo in game.freeColGameObjectsInJavaOrder where shouldHaveAIObject(fcgo) {
            if let p = fcgo as? Player {
                p.aiSeed = nil
                makeAIPlayer(p)
            } else if let id = fcgo.id, aiObjects[id] == nil {
                setFreeColGameObject(id, fcgo)
            }
        }
        game.freeColGameObjectListener = self
        attach()
    }

    /// An empty AI, to read a saved game's into.
    init(reading game: ServerGame, controller: InGameController, works: Works) {
        self.game = game
        self.controller = controller
        self.works = works
        attach()
    }

    /// Answer the server's questions for the AI: where a new REF lands.
    private func attach() {
        controller.initializeREF = { [unowned self] player, teleport in
            (aiPlayer(player) as? REFAIPlayer)?.initialize(teleport) ?? false
        }
    }

    // MARK: Objects

    func addAIObject(_ id: String, _ object: AIObject) {
        precondition(aiObjects[id] == nil, "AIObject already created: \(id)")
        aiObjects[id] = object
    }

    @discardableResult
    func removeAIObject(_ id: String) -> Bool {
        aiObjects.removeValue(forKey: id) != nil
    }

    func aiObject(_ id: String) -> AIObject? {
        aiObjects[id]
    }

    public func aiPlayer(_ player: Player?) -> AIPlayer? {
        player?.id.flatMap { aiObjects[$0] as? AIPlayer }
    }

    public func aiUnit(_ unit: Unit?) -> AIUnit? {
        unit?.id.flatMap { aiObjects[$0] as? AIUnit }
    }

    public func aiColony(_ colony: Colony?) -> AIColony? {
        colony?.id.flatMap { aiObjects[$0] as? AIColony }
    }

    /// The identifier number for a new AI object (getNextId).
    func nextId() -> String {
        defer { nextIdNumber += 1 }
        return String(nextIdNumber)
    }

    func shouldHaveAIObject(_ fcgo: FreeColGameObject) -> Bool {
        if fcgo is Colony || fcgo is Unit { return true }
        if let p = fcgo as? Player { return p.isAI }
        return false
    }

    /// An AI object for each unit and colony that has none
    /// (findNewObjects).  AI players come with their seeds.
    public func findNewObjects() {
        for fcgo in game.freeColGameObjects where !(fcgo is Player) {
            if let id = fcgo.id, aiObjects[id] == nil, shouldHaveAIObject(fcgo) { setFreeColGameObject(id, fcgo) }
        }
    }

    /// The AI player for a player, taking its seed: drawn from the
    /// server's generator when the game was built, as Java's AI does.
    @discardableResult
    func makeAIPlayer(_ player: Player) -> AIPlayer? {
        if let p = aiPlayer(player) { return p }
        let seed = player.aiSeed ?? RandomUtils.randomInt("Seed for \(player.id ?? "")", controller.random, Int32.max)
        player.aiSeed = seed
        if player.isIndian { return NativeAIPlayer(self, player, seed) }
        if player.isREF { return REFAIPlayer(self, player, seed) }
        if player.isEuropean { return EuropeanAIPlayer(self, player, seed) }
        return nil
    }

    // MARK: FreeColGameObjectListener

    public func setFreeColGameObject(_ id: String, _ fcgo: FreeColGameObject) {
        if aiObjects[id] != nil || !shouldHaveAIObject(fcgo) { return }
        if let colony = fcgo as? Colony {
            _ = AIColony(self, colony)
        } else if let unit = fcgo as? Unit {
            _ = AIUnit(self, unit)
        } else if let player = fcgo as? Player, player.playerType != nil {
            // Java waits until the player has a type, as a new REF has
            // once it is made.
            makeAIPlayer(player)
        }
    }

    public func removeFreeColGameObject(_ id: String) {
        aiObjects[id]?.dispose()
        removeAIObject(id)
    }

    public func ownerChanged(_ source: FreeColGameObject, _ oldOwner: Player?, _ newOwner: Player?) {
        guard let id = source.id, let ao = aiObjects[id] else { return }
        aiPlayer(oldOwner)?.removeAIObject(ao)
        ao.dispose()
        setFreeColGameObject(id, source)
    }

    // MARK: Messages

    /// Handle what an AI player was sent, message by message, as Java's
    /// AIInGameInputHandler does.
    public func handle(_ update: PlayerUpdate, for player: Player) {
        guard let aiPlayer = aiPlayer(player) else { return }
        for change in update.messages {
            if case .message(let m) = change { aiPlayer.handle(m) }
        }
    }

    func record(_ error: Error, _ context: String) {
        errors.append("\(context): \(error)")
    }
}

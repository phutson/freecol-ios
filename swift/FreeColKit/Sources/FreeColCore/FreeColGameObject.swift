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

import FreeColXML

/// An object that belongs to a game, such as a unit, tile or player
/// (common/model/FreeColGameObject).
///
/// Every game object registers itself with its game by identifier.
///
/// Ownership follows Java's: the game's registry holds objects weakly,
/// and objects are kept alive by whatever contains them (the game owns
/// its players and map, a player its units and colonies, and so on).
/// The reference from an object back to its game is weak too, so ARC
/// sees no cycles.  An object that nothing contains disappears from
/// the registry, as it does when Java garbage collects it, except that
/// ARC does it immediately rather than at some later point.
///
/// Not yet ported: copyIn (client updates), getLinkTarget and
/// checkIntegrity, which arrive with Player and the integrity checks.
open class FreeColGameObject: FreeColObject {

    /// The class index of game objects.
    public static let freeColGameObjectClassIndex = 50

    private weak var gameReference: Game?

    /// Whether this object has been disposed.
    public private(set) var isDisposed = false

    /// Whether this object has been fully set up.  Subclasses set this,
    /// like Java's protected `initialized` field.
    public var isInitialized = false

    /// The constructor for Game itself, which is its own game.
    init(asGame: Void) {
        super.init()
    }

    /// Create a new object with a fresh identifier from the game,
    /// "<xmlTagName>:<next id>".  Only server games can issue
    /// identifiers.
    ///
    /// - Parameter game: The game the object belongs to.
    public init(game: Game) {
        gameReference = game
        super.init()
        internId("\(xmlTagName):\(game.getNextId())")
        isInitialized = id != nil
    }

    /// Create an object with a known identifier, typically while
    /// reading a saved game.  It is not initialized until read.
    ///
    /// - Parameters:
    ///   - game: The game the object belongs to.
    ///   - id: The identifier.
    public init(game: Game, id: String?) {
        gameReference = game
        super.init()
        internId(id)
        isInitialized = false
    }

    /// Point a Game at itself.  Only Game.init calls this.
    final func setGameReferenceToSelf(_ game: Game) {
        gameReference = game
    }

    /// Set the identifier and register this object with the game under
    /// it, unregistering any old identifier.
    ///
    /// - Parameter newId: The new identifier.
    public final func internId(_ newId: String?) {
        guard let game = gameReference, let newId, isInternable else {
            id = newId
            return
        }
        if newId == id {
            // This happens when the client receives an update.
            game.setFreeColGameObject(newId, self)
        } else {
            if let oldId = id {
                game.removeFreeColGameObject(oldId, reason: "override")
            }
            id = newId
            game.addFreeColGameObject(newId, self)
        }
    }

    /// Register this object under its current identifier.
    public func intern() {
        internId(id)
    }

    /// Dispose of this object and everything it disposes with it.
    public final func dispose() {
        if isDisposed { return }
        for fcgo in disposables {
            fcgo.disposeResources()
        }
    }

    /// The basic part of disposal: unregister and mark as disposed.
    public final func fundamentalDispose() {
        if let id { game?.removeFreeColGameObject(id, reason: "dispose") }
        isDisposed = true
    }

    // MARK: Overridden by subclasses where meaningful

    /// Whether this object should be registered with its game.
    open var isInternable: Bool {
        true
    }

    /// The objects to dispose of along with this one, this one last.
    open var disposables: [FreeColGameObject] {
        [self]
    }

    /// Release this object's resources.  Overrides must call super.
    open func disposeResources() {
        fundamentalDispose()
    }

    // MARK: FreeColObject

    /// Reading an object initializes it.
    open override func readFromXML(_ xr: FreeColXMLReader) throws {
        isInitialized = true
        try super.readFromXML(xr)
    }

    open override var specification: Specification? {
        gameReference?.specification
    }

    open override func setSpecification(_ specification: Specification?) {
        fatalError("Can not set specification for: \(self)")
    }

    public final override var game: Game? {
        gameReference
    }

    public final override func setGame(_ game: Game) {
        gameReference = game
    }

    open override var classIndex: Int {
        FreeColGameObject.freeColGameObjectClassIndex
    }

    /// Game objects are equal if they are in the same game and have the
    /// same identifier.
    open override func isEqual(to other: FreeColObject) -> Bool {
        if self === other { return true }
        guard let other = other as? FreeColGameObject else { return false }
        return game === other.game && super.isEqual(to: other)
    }

    open override func hash(into hasher: inout Hasher) {
        super.hash(into: &hasher)
        hasher.combine(game.map(ObjectIdentifier.init))
    }
}

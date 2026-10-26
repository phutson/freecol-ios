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

/// A game object that the reader can create from its identifier alone,
/// before or while reading it (Java does this by reflection in
/// Game.newInstance, calling the (Game, String) constructor).
public protocol GameObjectReadable: FreeColGameObject {
    /// Create an object that is not yet registered or read.
    init(readingIn game: Game)
}

extension Game {

    /// The location classes by identifier type, for location attributes
    /// that may name an object not yet read (Game.getLocationClass).
    ///
    /// Building and ColonyTile follow in step 7.
    static let locationTypes: [String: any GameObjectReadable.Type] = [
        "colony": Colony.self,
        "europe": Europe.self,
        "highSeas": HighSeas.self,
        "indianSettlement": IndianSettlement.self,
        "map": Map.self,
        "tile": Tile.self,
        "unit": Unit.self,
    ]
}

/// Reading references to game objects (the game object part of
/// common/io/FreeColXMLReader).
///
/// Java's reader has three read scopes: SERVER (create server
/// classes), NORMAL and NOINTERN (read copies without registering
/// them).  There are no server classes, so SERVER and NORMAL are the
/// same here; NOINTERN reads players' cached copies of tiles and
/// copies objects (FreeColObject.copy).
extension FreeColXMLReader {

    /// The registered object with an identifier, if it has a type.
    ///
    /// - Throws: FreeColXMLError if an object is registered under the
    ///   identifier but has another type (Java's ClassCastException).
    public func lookup<T: FreeColGameObject>(_ game: Game?, _ id: String?,
                                             _ type: T.Type) throws -> T? {
        // While copying, the copies come first.
        let found = (shouldIntern ? nil : id.flatMap { uninterned[$0] as? FreeColGameObject })
            ?? game?.getFreeColGameObject(id)
        guard let found else { return nil }
        guard let typed = found as? T else {
            throw FreeColXMLError("Cannot cast \(Swift.type(of: found)) to \(T.self): \(id ?? "")")
        }
        return typed
    }

    /// The identifier in an attribute.  For "id" it is upgraded from old
    /// forms (@compat 0.11.x).
    private func referenceId(_ attributeName: String) -> String? {
        attributeName == FreeColObject.idTag ? readId()
            : attribute(attributeName, default: nil as String?)
    }

    /// An already registered object named by an attribute (Java's
    /// findFreeColGameObject).
    ///
    /// - Parameters:
    ///   - required: Throw if there is no such object.
    /// - Returns: The object, or nil if the attribute is missing or no
    ///   object is registered under it.
    public func findFreeColGameObject<T: FreeColGameObject>(_ game: Game, _ attributeName: String,
                                                            _ type: T.Type,
                                                            required: Bool) throws -> T? {
        let found = try lookup(game, attribute(attributeName, default: nil as String?), T.self)
        if found == nil && required {
            throw FreeColXMLError("Missing \(attributeName) for \(T.self): \(currentTag)")
        }
        return found
    }

    /// The object named by an attribute, created and registered if it
    /// has not been read yet (Java's makeFreeColObject).  A created
    /// object is not initialized until its own element is read.
    ///
    /// - Parameters:
    ///   - required: Throw if the attribute is missing.
    /// - Returns: The object, or nil if the attribute is missing.
    public func makeFreeColObject<T: GameObjectReadable>(_ game: Game, _ attributeName: String,
                                                         _ type: T.Type,
                                                         required: Bool) throws -> T? {
        guard let id = referenceId(attributeName) else {
            if required {
                throw FreeColXMLError("Missing \(attributeName) for \(T.self): \(currentTag)")
            }
            return nil
        }
        if let found = try lookup(game, id, T.self) { return found }
        return make(game, id, T.self)
    }

    private func make<T: GameObjectReadable>(_ game: Game, _ id: String, _ type: T.Type) -> T {
        let made = T(readingIn: game)
        if shouldIntern {
            made.internId(id)
            retain(made)
        } else {
            made.id = id
            addUninterned(id, made)
        }
        return made
    }

    /// Read the object defined by the element the reader is on,
    /// reusing an object already created by reference to it (Java's
    /// readFreeColObject).
    ///
    /// - Returns: The object, or nil if the element has no identifier.
    @discardableResult
    public func readFreeColObject<T: GameObjectReadable>(_ game: Game,
                                                         _ type: T.Type) throws -> T? {
        if !shouldIntern {
            // A copy: a new object, or one already made by reference
            // while copying, never the registered original.
            guard let id = readId() else {
                throw FreeColXMLError("Null object identifier for: \(T.self)")
            }
            let object: T
            if let found = uninterned[id] {
                guard let typed = found as? T else {
                    throw FreeColXMLError("Cannot cast \(Swift.type(of: found)) to \(T.self): \(id)")
                }
                object = typed
            } else {
                object = make(game, id, T.self)
            }
            try object.readFromXML(self)
            return object
        }
        guard let object = try makeFreeColObject(game, FreeColObject.idTag, T.self,
                                                 required: false) else { return nil }
        try object.readFromXML(self)
        return object
    }

    /// The location named by an attribute (Java's getLocationAttribute).
    ///
    /// - Parameters:
    ///   - make: Create the location if it has not been read yet and
    ///     its kind is known.
    /// - Returns: The object, or nil if the attribute is missing or
    ///   names nothing that can be found or made.
    public func getLocationAttribute(_ game: Game, _ attributeName: String,
                                     make: Bool) throws -> FreeColGameObject? {
        guard let id = referenceId(attributeName) else { return nil }
        if !shouldIntern, let found = uninterned[id] as? FreeColGameObject { return found }
        if let found = game.getFreeColGameObject(id) { return found }
        guard make, let idType = FreeColObject.idType(of: id),
              let type = Game.locationTypes[idType] else {
            warn("Not a location: \(id)")
            return nil
        }
        return self.make(game, id, type)
    }
}

extension GameObjectReadable {

    /// A copy of this object and what it holds, not registered with the
    /// game (FreeColObject.copy): written as the server sees it, then
    /// read without registering.  The copies refer to each other, and
    /// to the registered originals for everything else, such as their
    /// owners.
    ///
    /// - Throws: FreeColXMLError if the copy can not be read (where
    ///   Java logs a warning and returns null).
    public func copy(in game: Game? = nil) throws -> Self {
        try copy(in: game, scope: .toServer())
    }

    /// A copy of this object as a player's client sees it.
    public func copy(in game: Game? = nil, for player: Player) throws -> Self {
        try copy(in: game, scope: .toClient(player))
    }

    private func copy(in game: Game?, scope: FreeColXMLWriter.WriteScope) throws -> Self {
        guard let game = game ?? self.game else { throw FreeColXMLError("No game to copy \(self) in") }
        let xr = try FreeColXMLReader(string: serialize(scope))
        xr.replaceScope(intern: false)
        try xr.nextTag()
        guard let copy = try xr.readFreeColObject(game, Self.self) else {
            throw FreeColXMLError("Copy of \(self) failed")
        }
        return copy
    }
}

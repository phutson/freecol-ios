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

/// The AI's objects in a saved game (AIMain's writeChildren and
/// readChild): every AI object as an element of the aiMain element,
/// in identifier order, referring to each other by identifier.
extension AIMain {

    static let xmlTag = "aiMain"

    /// The AI for a saved game: read from the game's aiMain element and
    /// fixed up as Java's server does when loading (checkIntegrity), or
    /// made afresh if there is none or it can not be fixed.
    public static func loading(_ saved: FreeColXMLReader?, game: ServerGame, controller: InGameController,
                               works: Works = .all) -> AIMain {
        if let saved {
            let ai = AIMain(reading: game, controller: controller, works: works)
            if (try? ai.readFromXML(saved)) != nil, ai.checkIntegrity(true).isSafe {
                game.freeColGameObjectListener = ai
                return ai
            }
        }
        return AIMain(remaking: game, controller: controller, works: works)
    }

    /// Save the AI's objects (toXML).  As in Java, objects that fail
    /// their check are dropped first, and wishes not worth keeping are
    /// left out.
    public func toXML(_ xw: FreeColXMLWriter) {
        xw.writeStartElement(AIMain.xmlTag)
        xw.writeAttribute("nextId", nextIdNumber)
        let objects = aiObjects.values.sorted {
            FreeColObject.compareIdentifiers($0.id, $1.id) < 0
        }
        for aio in objects {
            if !aio.checkIntegrity(false).isSafe {
                aio.dispose()
                continue
            }
            if let wish = aio as? Wish, !wish.shouldBeStored { continue }
            if aio.id != nil { aio.toXML(xw) }
        }
        xw.writeEndElement()
    }

    /// Check every AI object, dropping those that fail if fixing, then
    /// add those missing for the game's objects (checkIntegrity).
    func checkIntegrity(_ fix: Bool) -> Integrity {
        var result = Integrity.good
        let objects = aiObjects.values.sorted {
            FreeColObject.compareIdentifiers($0.id, $1.id) < 0
        }
        for aio in objects where !aio.checkIntegrity(fix).isSafe {
            if fix {
                if let id = aio.id { removeAIObject(id) }
                aio.dispose()
                result = result.fixed()
            } else {
                result = .fail
            }
        }
        for fcgo in game.freeColGameObjectsInJavaOrder {
            guard let id = fcgo.id, aiObjects[id] == nil, shouldHaveAIObject(fcgo) else { continue }
            if fix {
                if let p = fcgo as? Player {
                    p.aiSeed = nil
                    makeAIPlayer(p)
                } else {
                    setFreeColGameObject(id, fcgo)
                }
                result = result.fixed()
            } else {
                result = .fail
            }
        }
        return result
    }

    /// Read the aiMain element (readFromXML), the reader standing before
    /// it.
    func readFromXML(_ xr: FreeColXMLReader) throws {
        try xr.nextTag()
        try xr.expectTag(AIMain.xmlTag)
        nextIdNumber = xr.attribute("nextId", default: -1)
        aiObjects.removeAll()
        while try xr.moreTags() { try readChild(xr) }
        try xr.expectTag(AIMain.xmlTag)
    }

    /// Read one AI object: one referred to already is completed, others
    /// are made by their element (readChild).
    private func readChild(_ xr: FreeColXMLReader) throws {
        let tag = xr.localName
        guard let oid = xr.readId() else {
            try xr.swallowTag(tag)
            return
        }
        if let aio = aiObjects[oid] {
            try aio.readFromXML(xr)
            aio.setInitialized()
            return
        }
        let aio: AIObject?
        switch tag {
        case AIColony.tag:
            aio = (game.getFreeColGameObject(oid) as? Colony).map { AIColony(self, loading: $0) }
        case AIGoods.tag:
            aio = AIGoods(self, placeholder: oid)
        case AIPlayer.tag:
            aio = (game.getFreeColGameObject(oid) as? Player).flatMap { p -> AIPlayer? in
                let random = xr.attribute("randomState", default: nil as String?)
                    .flatMap(JavaRandom.init(serializedState:))
                    ?? JavaRandom(seed: Int64(RandomUtils.randomInt("Seed for \(oid)", controller.random,
                                                                    Int32.max)))
                if p.isIndian { return NativeAIPlayer(self, p, random: random) }
                if p.isREF { return REFAIPlayer(self, p, random: random) }
                if p.isEuropean { return EuropeanAIPlayer(self, p, random: random) }
                return nil
            }
        case AIUnit.tag:
            aio = (game.getFreeColGameObject(oid) as? Unit).map { AIUnit(self, placeholder: $0) }
        case GoodsWish.tag:
            aio = GoodsWish(self, placeholder: oid)
        case TileImprovementPlan.tag:
            aio = TileImprovementPlan(self, placeholder: oid)
        case WorkerWish.tag:
            aio = WorkerWish(self, placeholder: oid)
        default:
            aio = nil
        }
        guard let aio else {
            xr.warn("Bad AI object at \(tag) with \(oid)")
            try xr.swallowTag(tag)
            return
        }
        try aio.readFromXML(xr)
        // Read from its own element, a wish joins its colony's.
        if let wish = aio as? Wish { wish.destinationAIColony?.addWish(wish) }
        aio.setInitialized()
    }

    /// An AI object referred to by identifier, made empty if it has not
    /// been read yet (FreeColXMLReader.makeAIObject).
    func reference<T: AIObject>(_ id: String?, _ type: T.Type) -> T? {
        guard let id else { return nil }
        if let found = aiObjects[id] { return found as? T }
        switch type {
        case is AIUnit.Type:
            return (game.getFreeColGameObject(id) as? Unit).map { AIUnit(self, placeholder: $0) } as? T
        case is AIGoods.Type:
            return AIGoods(self, placeholder: id) as? T
        case is GoodsWish.Type:
            return GoodsWish(self, placeholder: id) as? T
        case is WorkerWish.Type:
            return WorkerWish(self, placeholder: id) as? T
        case is TileImprovementPlan.Type:
            return TileImprovementPlan(self, placeholder: id) as? T
        default:
            return nil
        }
    }

    /// The location an attribute names (getLocationAttribute).
    func location(_ xr: FreeColXMLReader, _ name: String) -> (any Location)? {
        xr.attribute(name, default: nil as String?).flatMap { game.getFreeColGameObject($0) as? any Location }
    }
}

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
import FreeColUtil

/// Something waiting for a player's answer (server/model/Session).
///
/// Java keeps the open sessions in a static HashMap shared by every
/// game; here each server game has its own, keyed and ordered as
/// Java's.  So far only the monarch's sessions are ported.
open class Session {

    public let key: String
    public private(set) var isComplete = false

    /// - Throws: A duplicate session for the key is a bug, as in Java,
    ///   even a complete one that has not been looked up since.
    init(key: String, in sessions: Sessions) {
        precondition(sessions.all[key] == nil, "Duplicate session: \(key)")
        self.key = key
    }

    /// Mark as complete, finishing it with no answer if it was not
    /// (Session.complete; subclasses do the finishing).
    ///
    /// - Returns: Whether it was already complete.
    @discardableResult
    open func complete(_ cs: ChangeSet) throws -> Bool {
        let ret = isComplete
        isComplete = true
        return ret
    }

    /// A key for a session of a class between two objects
    /// (makeSessionKey), as Java writes it: the class, then the two
    /// identifiers in order.
    static func makeKey(_ javaClass: String, _ o1: String, _ o2: String) -> String {
        let cls = "class net.sf.freecol.server.model." + javaClass
        return JavaString.compare(o1, o2) < 0 ? "\(cls)-\(o1)-\(o2)" : "\(cls)-\(o2)-\(o1)"
    }
}

/// The open sessions of a game (Session's static map).
public final class Sessions {

    fileprivate(set) var all = JavaHashMap<String, Session>(javaHash: JavaString.hashCode)

    func register(_ session: Session) {
        _ = all.put(session.key, session)
    }

    /// The open session with a key, forgetting it if it is complete.
    func lookup(_ key: String) -> Session? {
        guard let s = all[key] else { return nil }
        if s.isComplete {
            _ = all.removeValue(forKey: key)
            return nil
        }
        return s
    }

    /// Finish every open session with no answer, in Java's order
    /// (completeAll, at each new turn).
    public func completeAll(_ cs: ChangeSet) throws {
        let open = all.entries.map(\.value).filter { !$0.isComplete }
        all.removeAll()
        for s in open { try s.complete(cs) }
    }
}

/// A monarch's demand or offer waiting for an answer
/// (server/model/MonarchSession): a tax raise, or mercenaries.
public final class MonarchSession: Session {

    public unowned let player: Player
    public let action: Monarch.MonarchAction
    public let tax: Int
    public let goods: Goods?
    public let mercenaries: [AbstractUnit]
    public let price: Int

    private init(_ player: Player, _ action: Monarch.MonarchAction, tax: Int, goods: Goods?,
                 mercenaries: [AbstractUnit], price: Int, in sessions: Sessions) {
        self.player = player
        self.action = action
        self.tax = tax
        self.goods = goods
        self.mercenaries = mercenaries
        self.price = price
        super.init(key: Session.makeKey("MonarchSession", player.id ?? "", ""), in: sessions)
    }

    /// Start a tax raise session and register it.
    @discardableResult
    static func register(_ player: Player, _ action: Monarch.MonarchAction, tax: Int, goods: Goods,
                         in sessions: Sessions) -> MonarchSession {
        let s = MonarchSession(player, action, tax: tax, goods: goods, mercenaries: [], price: 0, in: sessions)
        sessions.register(s)
        return s
    }

    /// Start a mercenaries session and register it.
    @discardableResult
    static func register(_ player: Player, _ action: Monarch.MonarchAction, mercenaries: [AbstractUnit],
                         price: Int, in sessions: Sessions) -> MonarchSession {
        let s = MonarchSession(player, action, tax: 0, goods: nil, mercenaries: mercenaries, price: price,
                               in: sessions)
        sessions.register(s)
        return s
    }

    /// Finish with an answer, or none if it was ignored.
    private func completeInternal(_ result: Bool?, _ cs: ChangeSet) throws {
        switch action {
        case .raiseTaxAct, .raiseTaxWar:
            guard let goods else { return }
            if let result {
                try player.csRaiseTax(tax, goods, result, cs)
            } else {
                try player.ignoreTax(tax, goods, cs)
            }
        case .monarchMercenaries, .hessianMercenaries:
            if let result {
                if result { try player.csAddMercenaries(mercenaries, price, nil, cs) }
            } else {
                player.ignoreMercenaries(cs)
            }
        default:
            break
        }
    }

    /// Finish with the player's answer.
    ///
    /// - Returns: Whether it was already complete.
    @discardableResult
    public func complete(_ result: Bool, _ cs: ChangeSet) throws -> Bool {
        let ret = try super.complete(cs)
        if !ret { try completeInternal(result, cs) }
        return ret
    }

    @discardableResult
    public override func complete(_ cs: ChangeSet) throws -> Bool {
        let ret = try super.complete(cs)
        if !ret { try completeInternal(nil, cs) }
        return ret
    }
}

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
import FreeColXML

/// Negotiation between a unit and another player's settlement or unit
/// (server/model/DiplomacySession).  Java also ends one, refused, after
/// a timeout in real time; here only the new turn ends it.
public final class DiplomacySession: Session {

    public var agreement: DiplomaticTrade?
    /// The unit that started it.
    public unowned let unit: Unit
    /// The other player's settlement.
    public private(set) weak var settlement: Settlement?
    /// The other player's unit, only at a first contact.
    public private(set) weak var otherUnit: Unit?

    private init(_ unit: Unit, settlement: Settlement?, otherUnit: Unit?, in sessions: Sessions) {
        self.unit = unit
        self.settlement = settlement
        self.otherUnit = otherUnit
        let other: Ownable? = settlement ?? otherUnit
        super.init(key: DiplomacySession.key(unit, other), in: sessions)
    }

    /// The key: the two owners (makeDiplomacySessionKey).
    static func key(_ o1: Ownable?, _ o2: Ownable?) -> String {
        Session.makeKey("DiplomacySession", o1?.owner?.id ?? "", o2?.owner?.id ?? "")
    }

    @discardableResult
    static func register(_ unit: Unit, settlement: Settlement?, otherUnit: Unit?, in sessions: Sessions)
        -> DiplomacySession {
        let s = DiplomacySession(unit, settlement: settlement, otherUnit: otherUnit, in: sessions)
        sessions.register(s)
        return s
    }

    private var owner: Player? { unit.owner }

    private var otherOwner: Player? { settlement?.owner ?? otherUnit?.owner }

    /// The player in the session that is not this one.
    public func otherPlayer(_ player: Player) -> Player? {
        owner !== player ? owner : otherOwner
    }

    /// The message telling a player of the agreement, from its side.
    public func message(_ destination: Player) -> DiplomacyMessage {
        let other: FreeColGameObject? = otherUnit ?? settlement
        return destination.owns(unit)
            ? DiplomacyMessage(unit, other, agreement)
            : DiplomacyMessage(other, unit, agreement)
    }

    /// Whether the session was started by these objects.
    public func isCompatible(_ o1: FreeColGameObject?, _ o2: FreeColGameObject?) -> Bool {
        (o1 === unit && (o2 === settlement || o2 === otherUnit))
            || (o2 === unit && (o1 === settlement || o1 === otherUnit))
    }

    /// A contact session under way between two players, complete or
    /// not, as Java's findSession finds it.
    static func findContactSession(_ p1: Player?, _ p2: Player?, in sessions: Sessions) -> DiplomacySession? {
        sessions.find {
            guard let ds = $0 as? DiplomacySession, ds.agreement?.context == .contact else { return false }
            return (ds.owner === p1 && ds.otherOwner === p2) || (ds.owner === p2 && ds.otherOwner === p1)
        } as? DiplomacySession
    }

    private func completeInternal(_ result: Bool, _ cs: ChangeSet) throws {
        // The agreement is null at a first contact.
        if let agreement, let game = unit.game as? ServerGame {
            var result = result
            if result { result = try game.csAcceptTrade(agreement, unit, settlement, cs) }
            agreement.status = result ? .acceptTrade : .rejectTrade
            if let sp = agreement.sender { cs.add(.only(sp), message: message(sp)) }
            if let rp = agreement.recipient { cs.add(.only(rp), message: message(rp)) }
        }
        unit.movesLeft = 0
        if let owner { cs.add(.only(owner), unit) }
    }

    /// Finish a first contact, without the offer's answers.
    @discardableResult
    public func completeFirstContact(_ cs: ChangeSet) throws -> Bool {
        try super.complete(cs)
    }

    /// Finish with an answer.
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
        try complete(false, cs)
    }
}

/// An agreement to consider, from one side (DiplomacyMessage).
public final class DiplomacyMessage: ServerMessage {
    public let ourId: String
    public let otherId: String
    public let agreement: DiplomaticTrade?

    public init(_ our: FreeColGameObject?, _ other: FreeColGameObject?, _ agreement: DiplomaticTrade?) {
        ourId = our?.id ?? ""
        otherId = other?.id ?? ""
        self.agreement = agreement
    }

    public var tag: String { "diplomacy" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { false }
    public var attributes: [(key: String, value: String)] { [("ourId", ourId), ("otherId", otherId)] }
    public func writeChildren(_ xw: FreeColXMLWriter) { agreement?.toXML(xw) }
}

extension Sessions {
    /// The first session, complete or not, in Java's order, that passes
    /// a test (findSession).
    func find(_ pred: (Session) -> Bool) -> Session? {
        all.entries.map(\.value).first(where: pred)
    }
}

extension Player {
    /// Go on with a negotiation (csDiplomacy): pass a proposal to the
    /// other side, or finish with the answer.
    func csDiplomacy(_ session: DiplomacySession, _ agreement: DiplomaticTrade, _ cs: ChangeSet) throws {
        agreement.incrementVersion()
        switch agreement.status {
        case .proposeTrade:
            session.agreement = agreement
            if let other = session.otherPlayer(self) { cs.add(.only(other), message: session.message(other)) }
        case .acceptTrade:
            try session.complete(true, cs)
        case .rejectTrade:
            try session.complete(false, cs)
        }
    }

    /// A European meets another: a peace treaty to agree, in a session,
    /// unless one is under way (csEuropeanFirstContact).
    func csEuropeanFirstContact(_ unit: Unit, _ settlement: Settlement?, _ otherUnit: Unit?, _ cs: ChangeSet) throws {
        guard let game = game as? ServerGame else { return }
        let other: Player?
        if let colony = settlement as? Colony {
            other = colony.owner
        } else if let otherUnit {
            other = otherUnit.owner
        } else {
            preconditionFailure("Non-null settlement (\(String(describing: settlement))) or other unit required")
        }
        guard let other else { return }
        if DiplomacySession.findContactSession(self, other, in: game.sessions) != nil { return }
        let agreement = DiplomaticTrade.makePeaceTreaty(.contact, self, other)
        let session = settlement == nil
            ? DiplomacySession.register(unit, settlement: nil, otherUnit: otherUnit, in: game.sessions)
            : DiplomacySession.register(unit, settlement: settlement, otherUnit: nil, in: game.sessions)
        session.agreement = agreement
        cs.add(.only(self), message: session.message(self))
        unit.movesLeft = 0
        cs.addPartial(.only(self), unit, ("movesLeft", String(unit.movesLeft)))
    }
}

extension ServerGame {
    /// Carry out an accepted agreement, if every item still holds
    /// (csAcceptTrade).
    ///
    /// - Returns: Whether it was carried out.
    func csAcceptTrade(_ agreement: DiplomaticTrade, _ unit: Unit, _ settlement: Settlement?,
                       _ cs: ChangeSet) throws -> Bool {
        let srcPlayer = agreement.sender, dstPlayer = agreement.recipient
        var visibilityChange = false

        // Check carefully first.
        var fail = false
        for item in agreement.items {
            let source = item.source, dest = item.destination
            if !item.isValid { fail = true; continue }
            if source !== srcPlayer && source !== dstPlayer { fail = true; continue }
            if dest !== srcPlayer && dest !== dstPlayer { fail = true; continue }
            guard let source, let dest else { fail = true; continue }
            if let colony = item.colony(self), !source.owns(colony) { fail = true; continue }
            let gold = item.tradeGold
            if gold > 0 && !source.checkGold(gold) { fail = true; continue }
            if let goods = item.goods {
                let loc = goods.location
                if let owned = loc as? Ownable, !source.owns(owned) {
                    fail = true
                } else if !((loc as? GoodsLocation)?.contains(goods) ?? false) {
                    fail = true
                } else if dest.owns(unit) && !unit.couldCarry(goods) {
                    fail = true
                }
            }
            // A stance that fails is harmless.
            if let u = item.tradeUnit {
                if !source.owns(u) {
                    fail = true
                    continue
                } else if dest.owns(unit) && !unit.couldCarry(u) {
                    fail = true
                }
            }
        }
        if fail { return false }

        for item in agreement.items {
            guard let source = item.source, let dest = item.destination else { continue }
            // Things changing hands are shown to the old owner too.
            if let stance = item.tradeStance, source.stance(dest) != stance,
               !(try source.csChangeStance(stance, dest, true, cs)) {
                // Stance trade failure.
            }
            if let colony = item.colony(self) {
                try colony.csChangeOwner(dest, false, nil, cs)
                visibilityChange = true
            }
            let gold = item.tradeGold
            if gold > 0 {
                _ = source.modifyGold(-gold)
                _ = dest.modifyGold(gold)
                cs.addPartial(.only(source), source, ("gold", String(source.gold)), ("score", String(source.score)))
                cs.addPartial(.only(dest), dest, ("gold", String(dest.gold)), ("score", String(dest.score)))
            }
            if let goods = item.goods, let settlement, let type = goods.type {
                if dest.owns(settlement) {
                    _ = goods.setLocation(unit)
                    GoodsLocation.moveGoods(unit, type, goods.amount, settlement)
                    cs.add(.only(source), unit)
                    if let gc = settlement.goodsContainer { cs.add(.only(dest), gc) }
                } else {
                    _ = goods.setLocation(settlement)
                    GoodsLocation.moveGoods(settlement, type, goods.amount, unit)
                    cs.add(.only(dest), unit)
                    if let gc = settlement.goodsContainer { cs.add(.only(source), gc) }
                }
            }
            if let victim = item.tradeVictim {
                if try source.csChangeStance(.war, victim, true, cs) {
                    // The player would not see a stance change between
                    // other nations.
                    cs.addStance(.only(dest), source, .war, victim)
                    cs.addMessage(dest, ModelMessage(.foreignDiplomacy, Player.Stance.war.otherStanceChangeKey,
                                                     source)
                        .addStringTemplate("%attacker%", source.nationLabel)
                        .addStringTemplate("%defender%", victim.nationLabel))
                }
            }
            if let newUnit = item.tradeUnit, let settlement {
                let former = newUnit.owner
                let oldTile = newUnit.tile
                let newLoc: (any Location)?
                if unit.isOnCarrier, let carrier = unit.carrier {
                    if !carrier.couldCarry(newUnit) { continue }
                    newLoc = carrier
                } else if dest === unit.owner {
                    newLoc = unit.tile
                } else {
                    newLoc = settlement.tile
                }
                if try source.csChangeOwner(newUnit, dest, nil, newLoc, cs) {
                    newUnit.movesLeft = 0
                    cs.add(.perhaps().always(former), oldTile)
                }
                visibilityChange = true
            }
        }
        if visibilityChange {
            srcPlayer?.invalidateCanSeeTiles()
            dstPlayer?.invalidateCanSeeTiles()
        }
        return true
    }
}

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

/// An AI object with a value (server/ai/ValuedAIObject).
open class ValuedAIObject: AIObject {
    public var value = 0
}

/// A mission that carries things (TransportMission), which units and
/// goods can leave.
protocol CarrierMission: Mission {
    func removeTransportable(_ t: TransportableAIObject)
}

/// Something a carrier can take somewhere (server/ai/TransportableAIObject):
/// its priority, and the carrier taking it.
open class TransportableAIObject: ValuedAIObject {

    static let importantDelivery = 110
    static let fullDelivery = 100

    public var transport: AIUnit?

    var transportPriority: Int {
        get { value }
        set { value = newValue }
    }

    /// The unit or goods carried.
    var transportLocatable: (any Locatable)? { nil }

    var location: (any Location)? { transportLocatable?.location }

    /// Leave the carrier taking this (dropTransport).
    @discardableResult
    func dropTransport() -> Bool {
        if let transport {
            if !transport.isDisposed, location !== transport.unit,
               let tm = transport.mission as? CarrierMission {
                tm.removeTransportable(self)
            }
            self.transport = nil
        }
        return transport == nil
    }

    var transportSource: (any Location)? { nil }
    var transportDestination: (any Location)? { nil }

    /// Get off the carrier (leaveTransport).
    func leaveTransport() -> Bool {
        aiMain.record(NotYetPorted("leaving a carrier"), "\(self)")
        return false
    }

    /// Change the carrier taking this, getting off the present one
    /// (changeTransport).
    func changeTransport(_ aiCarrier: AIUnit?) -> Bool {
        if let now = transportLocatable?.location as? Unit, !(aiCarrier.map { $0.unit === now } ?? false) {
            if !leaveTransport() { return false }
        }
        if let old = transport {
            if old === aiCarrier { return true }
            (old.mission as? CarrierMission)?.removeTransportable(self)
        }
        transport = aiCarrier
        return true
    }
}

/// The AI of a unit (server/ai/AIUnit): its mission, and the moves it
/// asks the server for.
public final class AIUnit: TransportableAIObject {

    public unowned let unit: Unit
    public private(set) var mission: Mission?

    init(_ aiMain: AIMain, _ unit: Unit) {
        self.unit = unit
        super.init(aiMain, unit.id)
        initialized = true
    }

    public var owner: Player? { unit.owner }

    var aiOwner: AIPlayer? { aiMain.aiPlayer(unit.owner) }

    var aiRandom: JavaRandom? { aiOwner?.aiRandom }

    var hasMission: Bool { mission != nil }

    func setMission(_ m: Mission?) {
        mission = m
    }

    func doMission() {
        mission?.doMission()
    }

    /// Change mission, dropping the old one (changeMission).
    @discardableResult
    func changeMission(_ m: Mission?) -> Mission? {
        if mission === m { return mission }
        removeMission()
        mission = m
        if let m { transportPriority = m.baseTransportPriority }
        return mission
    }

    func removeMission() {
        if let m = mission {
            m.dispose()
            mission = nil
        }
    }

    override var transportLocatable: (any Locatable)? { unit }

    override var transportSource: (any Location)? {
        unit.isDisposed ? nil : unit.location
    }

    override var transportDestination: (any Location)? {
        (unit.isDisposed || !hasMission) ? nil : mission?.transportDestination
    }

    var transportPriorityIfMission: Int {
        hasMission ? transportPriority : 0
    }

    /// Ask to move, if the move makes progress (move).
    @discardableResult
    func move(_ direction: Direction) -> Bool {
        let start = unit.tile
        return unit.moveType(direction).isProgress
            && aiOwner?.ask(.move(unit: unit.id, direction: direction.javaName)) == true
            && unit.tile !== start
    }

    /// Ask to equip for a role, as many as can be paid for
    /// (equipForRole).
    func equipForRole(_ role: Role) -> Bool {
        guard let player = owner, let loc = upLoc(unit.location) as? UnitLocation else { return false }
        var count = role.maximumCount
        if count > 0 {
            while count > 0 {
                let req = unit.goodsDifference(role, count)
                if let price = try? loc.priceGoods(req), player.checkGold(price) { break }
                count -= 1
            }
            if count <= 0 { return false }
        }
        return aiOwner?.ask(.equipForRole(unit: unit.id, role: role.id, count: String(count))) == true
            && unit.role === role && unit.roleCount == count
    }

    public override func dispose() {
        dropTransport()
        aiOwner?.removeAIObject(self)
        if let m = mission {
            m.dispose()
            mission = nil
        }
        super.dispose()
    }
}

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

/// An AI object with a value (server/ai/ValuedAIObject).
open class ValuedAIObject: AIObject {
    public var value = 0

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", value)
    }

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        value = xr.attribute("value", default: -1)
    }
}

/// Something a carrier can take somewhere (server/ai/TransportableAIObject):
/// its priority, the carrier taking it, and how it gets on and off.
open class TransportableAIObject: ValuedAIObject {

    static let importantDelivery = 110
    static let fullDelivery = 100
    static let toolsForColonyPriority = 10
    static let toolsForImprovement = 10
    static let toolsForPioneer = 90
    static let toolsForBuilding = 100

    public var transport: AIUnit?

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let u = transport?.unit, !u.isDisposed { xw.writeAttribute("transport", u) }
    }

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        transport = xr.hasAttribute("transport")
            ? aiMain.reference(xr.attribute("transport", default: nil as String?), AIUnit.self) : nil
    }

    /// The priority for transport (getTransportPriority).
    var transportPriority: Int {
        get { value }
        set { value = newValue }
    }

    /// The unit or goods carried.
    var transportLocatable: (any Locatable)? { nil }

    var location: (any Location)? { transportLocatable?.location }

    var spaceTaken: Int { transportLocatable?.spaceTaken ?? 0 }

    /// Leave the carrier taking this, unless already aboard it
    /// (dropTransport).
    @discardableResult
    func dropTransport() -> Bool {
        if let transport {
            if !transport.isDisposed, location !== transport.unit,
               let tm = transport.mission as? TransportMission {
                tm.removeTransportable(self)
            }
            self.transport = nil
        }
        return transport == nil
    }

    var transportSource: (any Location)? { nil }
    var transportDestination: (any Location)? { nil }

    /// The path for a carrier to deliver this to a destination.
    func deliveryPath(_ carrier: Unit, _ dst: (any Location)?) -> PathNode? { nil }

    /// A path to somewhere better, if not all the way.
    func intermediatePath(_ carrier: Unit, _ dst: (any Location)?) -> PathNode? { nil }

    func carriableBy(_ carrier: Unit) -> Bool { false }

    var canMove: Bool { false }

    /// Get off the carrier where best (leaveTransport).
    func leaveTransport() -> Bool { false }

    /// Get off the carrier, in a direction or here.
    func leaveTransport(_ direction: Direction?) -> Bool { false }

    /// Get on a carrier, from a direction or here.
    func joinTransport(_ carrier: Unit, _ direction: Direction?) -> Bool { false }

    /// Why transporting this is no longer sensible.
    func invalidReason() -> String? { nil }

    /// Change the carrier taking this, getting off the present one
    /// (changeTransport).
    func changeTransport(_ aiCarrier: AIUnit?) -> Bool {
        if let now = transportLocatable?.location as? Unit, !(aiCarrier.map { $0.unit === now } ?? false) {
            if !leaveTransport() { return false }
        }
        if let old = transport {
            if old === aiCarrier { return true }
            (old.mission as? TransportMission)?.removeTransportable(self)
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

    /// An AI unit referred to in a saved game before it is read.
    init(_ aiMain: AIMain, placeholder unit: Unit) {
        self.unit = unit
        super.init(aiMain, unit.id)
    }

    // MARK: Saving

    static let tag = "aiUnit"

    public override var xmlTag: String { AIUnit.tag }

    public override func setInitialized() {
        initialized = true
    }

    public override func checkIntegrity(_ fix: Bool) -> Integrity {
        let result = super.checkIntegrity(fix)
        return unit.isDisposed ? .fail : result
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if let mission, !mission.isOneTime, mission.isValid { mission.toXML(xw) }
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        mission = nil
        switch xr.localName {
        case "buildColonyMission": _ = try BuildColonyMission(loading: aiMain, self, xr)
        case "cashInTreasureTrainMission": _ = try CashInTreasureTrainMission(loading: aiMain, self, xr)
        case "defendSettlementMission": _ = try DefendSettlementMission(loading: aiMain, self, xr)
        case "escortUnitMission": _ = try EscortUnitMission(loading: aiMain, self, xr)
        case "idleAtSettlementMission": _ = try IdleAtSettlementMission(loading: aiMain, self, xr)
        case "indianBringGiftMission": _ = try IndianBringGiftMission(loading: aiMain, self, xr)
        case "indianDemandMission": _ = try IndianDemandMission(loading: aiMain, self, xr)
        case "missionaryMission": _ = try MissionaryMission(loading: aiMain, self, xr)
        case "pioneeringMission": _ = try PioneeringMission(loading: aiMain, self, xr)
        case "privateerMission": _ = try PrivateerMission(loading: aiMain, self, xr)
        case "scoutingMission": _ = try ScoutingMission(loading: aiMain, self, xr)
        case "transportMission": _ = try TransportMission(loading: aiMain, self, xr)
        case "unitSeekAndDestroyMission": _ = try UnitSeekAndDestroyMission(loading: aiMain, self, xr)
        case "unitWanderHostileMission": _ = try UnitWanderHostileMission(loading: aiMain, self, xr)
        case "unitWanderMission": _ = try UnitWanderMission(loading: aiMain, self, xr)
        case "wishRealizationMission": _ = try WishRealizationMission(loading: aiMain, self, xr)
        case "workInsideColonyMission": _ = try WorkInsideColonyMission(loading: aiMain, self, xr)
        default: try super.readChild(xr)
        }
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

    override var transportPriority: Int {
        get { hasMission ? value : 0 }
        set { value = newValue }
    }

    /// The end of the unit's trivial path (getTrivialTarget).
    var trivialTarget: (any Location)? {
        upLoc(unit.trivialPath?.lastNode.location)
    }

    var hasCargo: Bool { unit.hasCargo }

    /// How good the unit would be at building a colony
    /// (getBuilderScore).
    var builderScore: Int {
        if BuildColonyMission.invalidMissionReason(self) != nil { return -1000 }
        var ret = !unit.hasDefaultRole ? 0 : unit.skillLevel > 0 ? 100 : 500 + 100 * unit.skillLevel
        if unit.hasTile { ret += 50 }
        return ret
    }

    var pioneerScore: Int { unit.pioneerScore }

    var scoutScore: Int { unit.scoutScore }

    /// Ask the colony the unit is in, if any, to rearrange
    /// (requestLocalRearrange).
    private func requestLocalRearrange() {
        if let colony = unit.location?.colony { aiMain.aiColony(colony)?.requestRearrange() }
    }

    /// Note the carrier the unit is on as its transport (takeTransport).
    private func takeTransport() {
        let aiCarrier = unit.carrier.flatMap { aiMain.aiUnit($0) }
        if transport !== aiCarrier {
            if transport != nil { dropTransport() } // Java warns
            transport = aiCarrier
        }
    }

    /// Sail to the New World (moveToAmerica).
    @discardableResult
    func moveToAmerica() -> Bool {
        aiOwner?.ask(.moveTo(unit: unit.id, destination: game.map?.id)) == true
    }

    /// Sail to Europe (moveToEurope).
    @discardableResult
    func moveToEurope() -> Bool {
        aiOwner?.ask(.moveTo(unit: unit.id, destination: owner?.europe?.id)) == true
    }

    // MARK: Transportable

    override var spaceTaken: Int { unit.spaceTaken }

    /// The path for a carrier to take the unit to a destination, or
    /// beside it (getDeliveryPath).
    override func deliveryPath(_ carrier: Unit, _ dst: (any Location)?) -> PathNode? {
        guard let d = dst ?? transportDestination, let dst = upLoc(d), let here = unit.location else { return nil }
        var path: PathNode?
        if here === carrier {
            guard let carrierLoc = carrier.location else { return nil }
            path = unit.findPath(carrierLoc, dst, carrier)
            if path == nil, let t = dst.tile {
                path = unit.findPathToNeighbour(carrierLoc, t, carrier, nil)
            }
        } else if here is Unit {
            return nil
        } else {
            path = unit.findPath(here, dst, carrier)
            if path == nil, let t = dst.tile {
                path = unit.findPathToNeighbour(here, t, carrier, nil)
            }
        }
        path?.ensureDisembark()
        return path
    }

    override func carriableBy(_ carrier: Unit) -> Bool { carrier.couldCarry(unit) }

    override var canMove: Bool { unit.movesLeft > 0 }

    /// Get off the carrier: here in Europe or at the target, towards the
    /// target, or onto the safest or best connected land beside
    /// (leaveTransport).
    override func leaveTransport() -> Bool {
        if !unit.isOnCarrier { return true } // Harmless
        if unit.isInEurope { return leaveTransport(nil) }
        guard let tile = unit.tile else { return false }
        let target = (mission?.isValid ?? false) ? mission?.target : nil
        if let target {
            if Map.isSameLocation(target, tile) { return leaveTransport(nil) }
            if let tt = target.tile, let direction = tile.direction(to: tt) { return leaveTransport(direction) }
            if let path = unit.findPath(target), let next = path.next?.tile,
               let direction = tile.direction(to: next) {
                return leaveTransport(direction)
            }
        }
        if tile.isLand { return leaveTransport(nil) }
        var tiles: [Tile] = []
        for t in tile.surroundingTiles(1) where !t.isBlocked(unit) {
            if t.settlement != nil { return leaveTransport(tile.direction(to: t)) }
            tiles.append(t)
        }
        guard var safe = tiles.first, let player = owner else { return false }
        var best: Tile?
        var bestTurns = Unit.manyTurns
        var settlement: Settlement?
        for t in tiles {
            if settlement == nil || (settlement?.tile.map { t.isConnected(to: $0) } ?? false) {
                settlement = t.nearestSettlement(player, 10, true)
            }
            if let settlement {
                let turns = unit.turnsToReach(t, settlement)
                if bestTurns > turns {
                    bestTurns = turns
                    best = t
                }
            }
            if safe.defenceValue < t.defenceValue { safe = t }
        }
        return leaveTransport(tile.direction(to: best ?? safe))
    }

    /// Get off, here or moving in a direction.
    override func leaveTransport(_ direction: Direction?) -> Bool {
        guard unit.isOnCarrier, let carrier = unit.carrier else { return false }
        let result: Bool
        if let direction {
            result = move(direction)
        } else {
            result = aiOwner?.ask(.disembark(unit: unit.id)) == true && unit.location === carrier.location
        }
        if result {
            requestLocalRearrange()
            dropTransport()
        }
        return result
    }

    /// Get on a carrier, here or from a direction.
    override func joinTransport(_ carrier: Unit, _ direction: Direction?) -> Bool {
        guard let aiCarrier = aiMain.aiUnit(carrier) else { return false }
        let result = aiCarrier.aiOwner?.ask(.embark(unit: unit.id, carrier: carrier.id,
                                                    direction: direction?.javaName)) == true
            && unit.location === carrier
        if result {
            requestLocalRearrange()
            takeTransport()
        }
        return result
    }

    override func invalidReason() -> String? {
        Mission.invalidTransportableReason(self) ?? mission?.invalidReason()
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

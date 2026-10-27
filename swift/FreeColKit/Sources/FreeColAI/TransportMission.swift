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

/// Something a carrier is to carry (server/ai/Cargo): where the carrier
/// and the transportable meet, where the carrier drops it, and how long
/// it all takes.
final class Cargo {

    private static let maxTry = 3

    enum Mode: JavaEnum {
        /// Go to the target and load the transportable.
        case load
        /// Go to the target and unload it.
        case unload
        /// Go to the drop node target, where the unit embarks.
        case pickup
        /// Go to the drop node target, where the unit disembarks.
        case dropoff
        /// Dump it at the next opportunity.
        case dump

        var isCollection: Bool { self == .load || self == .pickup }

        var javaName: String {
            switch self {
            case .load: "LOAD"
            case .unload: "UNLOAD"
            case .pickup: "PICKUP"
            case .dropoff: "DROPOFF"
            case .dump: "DUMP"
            }
        }
    }

    /// The plan (Cargo.CargoPlan): where the transportable waits, where
    /// the carrier waits, where the carrier delivers, and where the
    /// transportable ends up.
    final class Plan {
        var twait: (any Location)?
        var cwait: (any Location)?
        var cdst: (any Location)?
        var tdst: (any Location)?
        var turns = 0
        var mode: Mode?
        var fallback = false

        /// Make the plan.
        ///
        /// - Returns: Why it can not be made, or nil.
        func initialize(_ t: TransportableAIObject, _ carrier: Unit?, _ destination: (any Location)?,
                        _ allowFallback: Bool) -> String? {
            if t.isDisposed { return "invalid-disposed" }
            guard let carrier else { return "invalid-null-carrier" }
            guard let destination = destination ?? t.transportDestination else { return "invalid-null-destination" }
            tdst = upLoc(destination)
            let src = t.location
            let carrying = src === carrier
            if !carrying && src is Unit { return "invalid-collected-elsewhere" }

            // The path to the destination, or to somewhere better.
            var deliver = t.deliveryPath(carrier, tdst)
            fallback = false
            if deliver == nil && allowFallback {
                deliver = t.intermediatePath(carrier, tdst)
                fallback = true
            }
            guard let deliver else { return "no-deliver" }

            // Collected at the first node on the carrier.
            guard let pick = deliver.carrierMove else { return "invalid-transport-not-needed" }
            if carrying {
                twait = nil
                cwait = nil
            } else {
                cwait = upLoc(pick.location)
                // Where the transportable waits: before it boards, if
                // it moves to the carrier.
                let prev = pick.previous ?? pick
                twait = upLoc(prev.location)
            }

            // Can the carrier get to the collection point?
            var collect: PathNode?
            if !carrying {
                collect = carrier.findPath(cwait)
                if collect == nil { return "no-collect" }
            }

            // Dropped at the drop node, or before it as the carrier
            // sees it.
            let drop = pick.transportDropNode
            guard let dropPrevious = drop.previous else {
                // Java throws.
                return "invalid-cargo-failure"
            }
            cdst = upLoc(dropPrevious.location)
            tdst = upLoc(deliver.lastNode.location)

            if carrying {
                turns = deliver.totalTurns
                mode = (cdst is Europe || cdst === tdst) ? .unload : .dropoff
            } else {
                turns = max(pick.turns, collect!.totalTurns) + pick.totalTurns
                mode = (cwait is Europe || cwait === twait) ? .load : .pickup
            }
            return nil
        }
    }

    /// Why a cargo could not be made (Java's FreeColException).
    struct Failure: Error {
        let reason: String
    }

    private(set) var transportable: TransportableAIObject?
    private(set) var carrier: Unit?
    private(set) var tries = 0
    var spaceLeft: Int
    private var wrapped: [Cargo]?
    private let plan: Plan

    private init(_ transportable: TransportableAIObject, _ carrier: Unit, _ plan: Plan) {
        self.transportable = transportable
        self.carrier = carrier
        spaceLeft = carrier.spaceLeft
        self.plan = plan
    }

    // MARK: Saving

    static let tag = "cargo"

    /// A cargo read from a saved game (readFromXML), its transportable
    /// made empty if it has not been read yet.
    init(loading aiMain: AIMain, _ xr: FreeColXMLReader) throws {
        let game = aiMain.game
        let tid = xr.readId()
        var t = tid.flatMap { aiMain.aiObject($0) as? TransportableAIObject }
        if t == nil, let tid {
            if tid.hasPrefix(Unit.tag) {
                t = aiMain.reference(tid, AIUnit.self)
            } else if tid.hasPrefix(AIGoods.tag) {
                t = aiMain.reference(tid, AIGoods.self)
            }
        }
        guard let t else { throw FreeColXMLError("Transportable expected: \(tid ?? "nil")") }
        transportable = t
        carrier = xr.attribute("carrier", default: nil as String?).flatMap { game.getFreeColGameObject($0) as? Unit }
        tries = xr.attribute("tries", default: 0)
        spaceLeft = xr.attribute("space", default: -1)
        wrapped = nil
        plan = Plan()
        plan.twait = aiMain.location(xr, "twait")
        plan.cwait = aiMain.location(xr, "cwait")
        plan.cdst = aiMain.location(xr, "cdst")
        plan.tdst = aiMain.location(xr, "tdst")
        plan.turns = xr.attribute("turns", default: -1)
        plan.mode = xr.attribute("mode", Mode.self, default: nil)
        plan.fallback = xr.attribute("fallback", default: false)
        try xr.closeTag(Cargo.tag)
    }

    func toXML(_ xw: FreeColXMLWriter) {
        xw.writeStartElement(Cargo.tag)
        xw.writeAttribute(FreeColObject.idTag, id: transportable?.id)
        xw.writeAttribute("carrier", carrier)
        xw.writeAttribute("tries", tries)
        xw.writeAttribute("space", spaceLeft)
        if let twait = plan.twait { xw.writeLocationAttribute("twait", twait) }
        if let cwait = plan.cwait { xw.writeLocationAttribute("cwait", cwait) }
        if let cdst = plan.cdst { xw.writeLocationAttribute("cdst", cdst) }
        if let tdst = plan.tdst { xw.writeLocationAttribute("tdst", tdst) }
        xw.writeAttribute("turns", plan.turns)
        if let mode = plan.mode { xw.writeAttribute("mode", mode) }
        xw.writeAttribute("fallback", plan.fallback)
        xw.writeEndElement()
    }

    /// A cargo for the transportable's own destination (newCargo).
    static func make(_ t: TransportableAIObject, _ carrier: Unit) throws -> Cargo {
        try make(t, carrier, t.transportDestination, true)
    }

    static func make(_ t: TransportableAIObject, _ carrier: Unit, _ destination: (any Location)?,
                     _ allowFallback: Bool) throws -> Cargo {
        let cargo = Cargo(t, carrier, Plan())
        if let reason = cargo.plan.initialize(t, carrier, destination, allowFallback) {
            throw Failure(reason: reason)
        }
        return cargo
    }

    /// Plan again (update).
    @discardableResult
    func update() -> String? {
        guard let transportable else { return "invalid-disposed" }
        return plan.initialize(transportable, carrier, nil, plan.fallback)
    }

    /// Dump the transportable at the end of the carrier's trivial path
    /// (dump).
    @discardableResult
    func dump() -> String? {
        if !isCarried { return "not-carried" }
        guard let path = carrier?.trivialPath else { return "no-trivial-path" }
        if let reason = plan.initialize(transportable!, carrier, path.lastNode.location, false) { return reason }
        plan.mode = .dump
        return nil
    }

    var isValid: Bool { plan.mode != nil }

    var mode: Mode { plan.mode! }

    var turns: Int { plan.turns }

    var isFallback: Bool { plan.fallback }

    /// Where the transportable should go.
    var transportTarget: (any Location)? { mode.isCollection ? plan.twait : plan.tdst }

    /// Where the carrier should go.
    var carrierTarget: (any Location)? { mode.isCollection ? plan.cwait : plan.cdst }

    func clear() {
        transportable = nil
        carrier = nil
        plan.mode = nil
    }

    var isCarried: Bool {
        guard let transportable else { return false }
        return transportable.location === carrier
    }

    var isCollectable: Bool {
        if !mode.isCollection || isCarried { return false }
        return Map.isSameLocation(plan.twait, transportable?.location)
            && Map.isSameLocation(plan.cwait, carrier?.location)
    }

    var isDeliverable: Bool {
        if mode.isCollection || !isCarried { return false }
        return Map.isSameLocation(plan.cdst, carrier?.location)
    }

    var isDelivered: Bool { !mode.isCollection && !isCarried }

    var hasPath: Bool { carrier?.findPath(carrierTarget) != nil }

    /// The direction for the transportable to board in (getJoinDirection).
    var joinDirection: Direction? {
        guard let carrier, !carrier.isInEurope, plan.cwait !== plan.twait,
              let tw = plan.twait?.tile, let cw = plan.cwait?.tile else { return nil }
        return tw.direction(to: cw)
    }

    /// The direction for the transportable to leave in (getLeaveDirection).
    var leaveDirection: Direction? {
        guard let carrier, carrier.hasTile, plan.cdst !== plan.tdst, let transportable else { return nil }
        return transportable.deliveryPath(carrier, plan.tdst)?.next?.direction
    }

    /// The change in space taken on the carrier (getNewSpace).
    var newSpace: Int {
        guard isValid, let transportable else { return 0 }
        var ret = mode.isCollection ? transportable.spaceTaken : -transportable.spaceTaken
        if let wrapped { ret += wrapped.reduce(0) { $0 + $1.newSpace } }
        return ret
    }

    var hasWrapped: Bool { wrapped != nil }

    func couldWrap(_ other: Cargo) -> Bool {
        carrierTarget === other.carrierTarget && newSpace < 0 && other.newSpace < 0
    }

    func wrap(_ other: Cargo) {
        if wrapped == nil { wrapped = [] }
        wrapped!.append(other)
    }

    func unwrap() -> [Cargo] {
        let result = wrapped ?? []
        wrapped = nil
        return result
    }

    /// Try again, if not too often.
    func retry() -> Bool {
        defer { tries += 1 }
        return tries < Cargo.maxTry
    }

    func resetTries() {
        tries = 0
    }

    func isEuropeanTrade(_ type: GoodsType) -> Bool {
        (transportable as? AIGoods)?.goodsType === type && carrierTarget is Europe
    }

    /// Why the cargo is broken, if it is.
    func check(_ aiCarrier: AIUnit) -> String? {
        guard let transportable else { return "null transportable" }
        if transportable.isDisposed { return "disposed transportable" }
        guard let l = transportable.transportLocatable else { return "null locatable" }
        if (l as? FreeColGameObject)?.isDisposed ?? false { return "locatable disposed" }
        if let tLoc = l.location as? Unit, tLoc !== carrier { return "carrier usurped" }
        return nil
    }

    /// Whether the cargo can be queued at an index without the carrier
    /// overflowing or going negative.
    func canQueueAt(_ carrier: Unit, _ index: Int, _ cargoes: [Cargo]) -> Bool {
        let maxHolds = carrier.cargoCapacity
        let newSpace = self.newSpace
        for j in index..<max(index, cargoes.count) {
            var holds = j == 0 ? carrier.cargoSpaceTaken : maxHolds - cargoes[j - 1].spaceLeft
            holds += newSpace
            if holds < 0 || holds > maxHolds { return false }
        }
        return true
    }
}

/// Carry units and goods (server/ai/mission/TransportMission): a list
/// of cargoes, in the order the carrier will visit their targets.
final class TransportMission: Mission {

    private enum CargoResult {
        case tContinue, tDone, tFail, tNext, tRetry
    }

    /// The most targets to plan for.
    private static let destinationUpperBound = 4

    private var cargoes: [Cargo] = []
    private var transportTarget: (any Location)?

    override init(_ aiMain: AIMain, _ aiUnit: AIUnit) {
        super.init(aiMain, aiUnit)
        transportTarget = aiUnit.trivialTarget
    }

    // MARK: Saving

    override init(loading aiMain: AIMain, _ aiUnit: AIUnit, _ xr: FreeColXMLReader) throws {
        try super.init(loading: aiMain, aiUnit, xr)
    }

    override var xmlTag: String { "transportMission" }

    override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let transportTarget { xw.writeLocationAttribute("target", transportTarget) }
    }

    /// The cargoes, but not those broken or to be dumped: the loaded
    /// mission works out what to do with them.
    override func writeChildren(_ xw: FreeColXMLWriter) {
        for cargo in cargoes {
            if cargo.check(aiUnit) != nil { continue }
            if cargo.isValid && cargo.mode == .dump { continue }
            cargo.toXML(xw)
        }
    }

    override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        transportTarget = aiMain.location(xr, "target")
    }

    override func readChildren(_ xr: FreeColXMLReader) throws {
        _ = tClear()
        try super.readChildren(xr)
    }

    override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == Cargo.tag {
            _ = tAdd(try Cargo(loading: aiMain, xr), -1)
        } else {
            try super.readChild(xr)
        }
    }

    override func dispose() {
        clearCargoes()
        super.dispose()
    }

    private func isCarrying(_ t: TransportableAIObject?) -> Bool {
        guard let t else { return false }
        return t.location === unit
    }

    func isTransporting(_ t: TransportableAIObject) -> Bool { tFind(t) != nil }

    private func shouldAttack(_ other: Unit) -> Bool {
        if Mission.invalidAttackReason(aiUnit, other.owner) != nil { return false }
        guard let cm = game.combatModel as CombatModel? else { return false }
        return cm.offencePower(unit, other) > cm.offencePower(other, unit)
    }

    // MARK: The cargoes; nothing else touches them

    private func tClear() -> [Cargo] {
        let old = cargoes
        cargoes = []
        return old
    }

    @discardableResult
    private func tSet(_ next: [Cargo], _ setSpace: Bool) -> [Cargo] {
        let old = cargoes
        cargoes = next.filter(\.isValid)
        if setSpace { tSpace() }
        tRetarget()
        return old
    }

    private var tSize: Int { cargoes.count }

    private func tFind(_ t: TransportableAIObject) -> Cargo? {
        cargoes.first { $0.transportable === t }
    }

    private func tFirst() -> Cargo? {
        cargoes.first(where: \.isValid)
    }

    private func tAdd(_ cargo: Cargo, _ index: Int) -> Bool {
        if !cargo.isValid { return false }
        if let t = cargo.transportable, tFind(t) != nil { return true }
        let change = cargoes.isEmpty || index == 0
        if index >= 0 { cargoes.insert(cargo, at: index) } else { cargoes.append(cargo) }
        tSpace()
        if change { tRetarget() }
        return true
    }

    @discardableResult
    private func tRemove(_ cargo: Cargo) -> Bool {
        let t = cargo.transportable
        guard let i = cargoes.firstIndex(where: { $0.transportable === t }) else { return false }
        cargoes.remove(at: i)
        tSpace()
        if i == 0 { tRetarget() }
        return true
    }

    private func tSpace() {
        let maxHolds = unit.cargoCapacity
        var holds = unit.cargoSpaceTaken
        for cargo in cargoes where cargo.isValid {
            holds += cargo.newSpace
            cargo.spaceLeft = maxHolds - holds
        }
    }

    private func tRetarget() {
        let c = cargoes.first(where: \.isValid)
        transportTarget = upLoc(c == nil ? aiUnit.trivialTarget : c!.carrierTarget)
    }

    // MARK: Cargoes and targets

    private func destinationCount() -> Int {
        var now: (any Location)?
        var ret = 0
        for cargo in cargoes {
            let t = cargo.carrierTarget
            if !Map.isSameLocation(now, t) {
                ret += 1
                now = t
            }
        }
        return ret
    }

    /// How many more targets the carrier can take on.
    func destinationCapacity() -> Int {
        TransportMission.destinationUpperBound - destinationCount()
    }

    private func dropTransportable(_ t: TransportableAIObject?) {
        if let t, t.transport === aiUnit { t.transport = nil }
    }

    private func takeTransportable(_ t: TransportableAIObject?) {
        if let t, t.transport !== aiUnit { t.transport = aiUnit }
    }

    /// Where a transportable should go to meet the carrier.
    func transportTarget(_ t: TransportableAIObject) -> (any Location)? {
        if isCarrying(t) { return nil }
        return tFind(t)?.transportTarget
    }

    func transportTurns(_ t: TransportableAIObject) -> Int {
        if isCarrying(t) { return Constants.infinity }
        return tFind(t)?.turns ?? Constants.infinity
    }

    private func wrapCargoes() -> [Cargo] {
        var ts = cargoes
        var i = 0
        while i < ts.count - 1 {
            let head = ts[i]
            while i + 1 < ts.count && head.couldWrap(ts[i + 1]) {
                head.wrap(ts.remove(at: i + 1))
            }
            i += 1
        }
        return ts
    }

    private func unwrapCargoes(_ list: [Cargo]) -> [Cargo] {
        var ts = list
        var i = 0
        while i < ts.count {
            let t = ts[i]
            if t.hasWrapped {
                let tl = t.unwrap()
                ts.insert(contentsOf: tl, at: i + 1)
                i += tl.count
            }
            i += 1
        }
        return ts
    }

    private func clearCargoes() {
        for cargo in tClear() { dropTransportable(cargo.transportable) }
        tRetarget()
    }

    var isEmpty: Bool { tSize == 0 }

    /// A cargo for a transportable, or nil if it can not be made
    /// (makeCargo).
    func makeCargo(_ t: TransportableAIObject) -> Cargo? {
        if t.transportDestination == nil {
            guard isCarrying(t), let path = unit.trivialPath else { return nil }
            return try? Cargo.make(t, unit, path.lastNode.location, true)
        } else if !isCarrying(t) && !t.carriableBy(unit) {
            return nil
        }
        return try? Cargo.make(t, unit)
    }

    private func addCargo(_ cargo: Cargo, _ index: Int) -> Bool {
        let result = tAdd(cargo, index)
        if result { takeTransportable(cargo.transportable) }
        return result
    }

    private func removeCargo(_ cargo: Cargo) {
        if !tRemove(cargo) {
            aiMain.record(JavaException("RuntimeException: removeCargo"), "TransportMission")
        }
        dropTransportable(cargo.transportable)
    }

    func spaceAvailable(_ t: TransportableAIObject) -> Bool {
        let newSpace = t.spaceTaken
        for c in cargoes.reversed() where c.spaceLeft < newSpace { return false }
        return true
    }

    /// Queue a cargo: first if the carrier is at its target, else with a
    /// cargo going to the same place, else at the end unless a match is
    /// required (queueCargo).
    private func queueCargo(_ cargo: Cargo, _ requireMatch: Bool) -> Bool {
        let ts = cargoes
        var candidate = -1
        if ts.isEmpty
            || (Map.isSameLocation(unit.location, cargo.carrierTarget) && cargo.canQueueAt(unit, 0, ts)) {
            candidate = 0
        }
        if candidate < 0 {
            for (i, tr) in ts.enumerated() where Map.isSameLocation(tr.carrierTarget, cargo.carrierTarget) {
                if !cargo.canQueueAt(unit, i, ts) { continue }
                candidate = i
                break
            }
        }
        if candidate < 0 {
            if requireMatch { return false }
            candidate = ts.count
        }
        return addCargo(cargo, candidate)
    }

    @discardableResult
    private func dumpCargo(_ cargo: Cargo) -> Bool {
        guard let t = cargo.transportable else { return true }
        if isCarrying(t) { _ = t.leaveTransport() }
        if !isCarrying(t) && tFind(t) != nil { removeCargo(cargo) }
        if tFind(t) != nil { return cargo.dump() == nil }
        return true
    }

    private func requeueCargo(_ cargo: Cargo) -> Bool {
        let t = cargo.transportable
        if cargo.update() != nil {
            dumpCargo(cargo)
            return false
        } else if !tRemove(cargo) {
            return false
        } else if !queueCargo(cargo, false) {
            dropTransportable(t)
            return false
        }
        takeTransportable(t)
        return true
    }

    /// Drop broken and completed cargoes, and take on what is aboard but
    /// not planned for (checkCargoes).
    private func checkCargoes() {
        if unit.isAtSea { return } // Let it emerge.
        var unitsPresent = unit.unitList
        var goodsPresent = unit.compactGoodsList
        var todo: [TransportableAIObject] = []
        var drop: [TransportableAIObject] = []
        for cargo in cargoes {
            var dump = false
            let t = cargo.transportable
            var reason = TransportMission.invalidMissionReason(aiUnit, cargo.carrierTarget)
            if reason == nil { reason = cargo.check(aiUnit) }
            if reason != nil {
                removeCargo(cargo)
            } else if cargo.isDelivered {
                removeCargo(cargo)
            } else if !cargo.hasPath && !cargo.retry() {
                dump = true
            } else if unit.hasTile, let r = cargo.update() {
                if r.hasPrefix("invalid") {
                    removeCargo(cargo)
                } else if cargo.retry() {
                    // Retry.
                } else {
                    dump = true
                }
            } else if cargo.isCollectable || cargo.isDeliverable {
                // Collect or deliver.
            } else {
                cargo.resetTries()
            }
            if dump {
                if cargo.isCarried { dumpCargo(cargo) } else { removeCargo(cargo) }
            }
            if let aiu = t as? AIUnit {
                unitsPresent.removeAll { $0 === aiu.unit }
            } else if let aig = t as? AIGoods, let type = aig.goods?.type {
                goodsPresent.removeAll { $0.type === type }
            }
        }

        // Anything not planned for.
        for u in unitsPresent {
            guard let aiu = aiMain.aiUnit(u) else {
                aiMain.record(JavaException("IllegalStateException: Bogus: \(u)"), "TransportMission")
                continue
            }
            todo.append(aiu)
        }
        for g in goodsPresent {
            guard let type = g.type else { continue }
            todo.append(AIGoods(aiMain, unit, type, g.amount, nil))
        }
        while !todo.isEmpty {
            let t = todo.removeFirst()
            if !queueTransportable(t, false) { drop.append(t) }
        }

        // Drop what can not be queued, or queue it to drop at the end of
        // the trivial path.
        if !drop.isEmpty {
            let end = unit.trivialPath?.lastNode.location
            while !drop.isEmpty {
                let t = drop.removeFirst()
                if t.leaveTransport() {
                    // Left.
                } else if let end {
                    if let cargo = try? Cargo.make(t, unit, end, false) { _ = queueCargo(cargo, false) }
                }
            }
        }
    }

    /// Load or unload a cargo here, if it is time to (tryCargo).
    private func tryCargo(_ cargo: Cargo) -> CargoResult {
        let carrier = unit
        guard let t = cargo.transportable, let l = t.transportLocatable else { return .tDone }
        guard let here = carrier.location else { return .tContinue }
        if !Map.isSameLocation(here, cargo.carrierTarget) { return .tContinue }
        var d: Direction?
        var tloc: (any Location)? = here
        var load = false
        switch cargo.mode {
        case .pickup:
            if !t.canMove { return .tContinue }
            guard let jd = cargo.joinDirection else { return .tFail } // Java warns
            d = jd
            tloc = here.tile?.neighbour(jd.reverseDirection)
            load = true
        case .load:
            load = true
        case .dropoff:
            if !t.canMove { return .tContinue }
            d = cargo.leaveDirection
            if d == nil {
                let mt = (t as? AIUnit)?.unit.simpleMoveType(t.location?.tile, cargo.transportTarget?.tile)
                switch mt {
                case .attackUnit, .moveNoAttackCivilian: return .tRetry
                default: return .tFail // Java warns
                }
            }
            if isCarrying(t) && !t.leaveTransport(d) { return .tRetry }
        case .unload:
            if isCarrying(t) && !t.leaveTransport(d) { return .tRetry }
        case .dump:
            if !t.leaveTransport() { return .tContinue }
        }
        if load {
            if !Map.isSameLocation(tloc, t.location) { return .tContinue }
            switch carrier.noAddReason(l) {
            case .none:
                if !t.joinTransport(carrier, d) { return .tFail }
            case .alreadyPresent:
                break
            case .capacityExceeded:
                if let g = l as? Goods, let type = g.type {
                    let loadableAmount = carrier.loadableAmount(type)
                    if loadableAmount > 0 {
                        g.amount = loadableAmount
                        if !t.joinTransport(carrier, d) { return .tFail }
                        break
                    }
                }
                return .tFail
            default:
                return .tRetry
            }
            if cargo.update() != nil { return .tFail }
            return .tNext
        }

        // Goods or a unit completing a wish.
        if let colony = t.location?.colony, let aiColony = aiMain.aiColony(colony), aiColony.completeWish(transportable: t) {
            aiColony.requestRearrange()
        }
        return .tDone
    }

    /// Deliver what can be delivered here, then collect, then take on
    /// more (doTransport).
    private func doTransport() {
        if tSize > 0 {
            var cont: [Cargo] = []
            var next: [Cargo] = []
            for cargo in tClear() {
                let result = cargo.mode.isCollection ? CargoResult.tContinue : tryCargo(cargo)
                switch result {
                case .tContinue:
                    cont.append(cargo)
                case .tRetry, .tFail, .tDone:
                    if result == .tRetry && cargo.retry() {
                        cont.append(cargo)
                        break
                    }
                    if result != .tDone && cargo.isCarried {
                        cargo.dump()
                        break
                    }
                    dropTransportable(cargo.transportable)
                    cargo.clear()
                case .tNext:
                    aiMain.record(JavaException("RuntimeException: Can not happen: TNEXT"), "TransportMission")
                }
            }
            tSet(cont, true)

            cont = []
            for cargo in tClear() {
                let result = cargo.mode.isCollection ? tryCargo(cargo) : CargoResult.tContinue
                switch result {
                case .tContinue, .tNext:
                    cont.append(cargo)
                case .tRetry, .tFail, .tDone:
                    if result == .tRetry && cargo.retry() {
                        next.append(cargo) // Try again next turn.
                        break
                    }
                    dropTransportable(cargo.transportable)
                    cargo.clear()
                }
            }
            tSet(cont, true)
            for c in next { _ = queueCargo(c, false) }

            checkCargoes()
            optimizeCargoes()
        }
        queueEasilyTransportedCargo()
        let euaip = aiPlayer as? EuropeanAIPlayer
        while destinationCapacity() > 0 && tSize < unit.cargoCapacity * 3 / 2 {
            guard let cargo = bestCargo() else { break }
            if !queueCargo(cargo, false) { break }
            if let t = cargo.transportable { _ = euaip?.claimTransportable(t) }
        }
        queueEasilyTransportedCargo()
    }

    /// The score of visiting the cargoes' targets in an order: turns,
    /// and a little for the holds filled over time, or -1 if the carrier
    /// would overflow (scoreCargoOrder).
    private func scoreCargoOrder(_ initialLocation: (any Location)?, _ order: [Cargo]) -> Float {
        let maxHolds = unit.cargoCapacity
        var holds = unit.cargoSpaceTaken
        var now = initialLocation
        var totalHoldTurns: Float = 0
        var totalTurns: Float = 0
        var favourEarly: Float = 1
        for cargo in order {
            let turns = now.flatMap { n in cargo.carrierTarget.map { unit.turnsToReach(n, $0) } }
                ?? Unit.manyTurns
            totalTurns += Float(turns)
            totalHoldTurns += Float(holds * turns) * favourEarly
            holds += cargo.newSpace
            if holds < 0 || holds > maxHolds { return -1 }
            now = cargo.carrierTarget
            favourEarly += 0.1
        }
        return totalTurns + 0.001 * totalHoldTurns
    }

    /// Visit the targets in the best order (optimizeCargoes).
    private func optimizeCargoes() {
        let ts = wrapCargoes()
        var best: [Cargo]?
        if 1 < ts.count && ts.count <= TransportMission.destinationUpperBound {
            let current = unit.location
            var bestValue = Float(Constants.infinity)
            for tl in javaPermutations(ts) {
                let value = scoreCargoOrder(current, tl)
                if value > 0 && bestValue > value {
                    bestValue = value
                    best = tl
                }
            }
        }
        if let best {
            tSet(unwrapCargoes(best), true)
        } else {
            tSet(unwrapCargoes(ts), false)
        }
    }

    /// The most valuable transportable to take, direct or else as a
    /// fallback (getBestCargo).
    private func bestCargo() -> Cargo? {
        guard let euaip = aiPlayer as? EuropeanAIPlayer else { return nil }
        var bestDirect: Cargo?, bestFallback: Cargo?
        var bestDirectValue: Float = 0, bestFallbackValue: Float = 0
        for t in euaip.transportables() where !t.isDisposed && t.carriableBy(unit) {
            guard let cargo = try? Cargo.make(t, unit) else { continue }
            let value = Float(t.transportPriority) / (Float(cargo.turns) + 1)
            if cargo.isFallback {
                if bestFallbackValue < value {
                    bestFallbackValue = value
                    bestFallback = cargo
                }
            } else if bestDirectValue < value {
                bestDirectValue = value
                bestDirect = cargo
            }
        }
        return bestDirect ?? bestFallback
    }

    /// Take on anything here going elsewhere than the next target, if
    /// there is room (queueEasilyTransportedCargo).
    private func queueEasilyTransportedCargo() {
        guard let euaip = aiPlayer as? EuropeanAIPlayer else { return }
        let ts = cargoes
        guard let nextDestination = ts.first(where: { $0.carrierTarget?.tile != nil })?.carrierTarget else {
            return
        }
        for t in euaip.transportables() where !t.isDisposed && t.carriableBy(unit) {
            if !Map.isSameLocation(t.transportSource, unit.location) { continue }
            if Map.isSameLocation(nextDestination, t.transportDestination) { continue }
            guard let cargo = try? Cargo.make(t, unit) else { continue }
            let spaceAvailable = unit.cargoCapacity - unit.cargoSpaceTaken
            if spaceAvailable < cargo.newSpace { continue }
            _ = t.joinTransport(unit, nil) // Java warns on failure
            cargo.update()
            _ = addCargo(cargo, 0) // Java warns on failure
            _ = euaip.claimTransportable(t)
        }
    }

    private static func invalidUnitReason(_ aiUnit: AIUnit?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        return aiUnit!.unit.isCarrier ? nil : "unit-not-a-carrier"
    }

    private static func invalidCargoReason(_ cargo: Cargo) -> String? {
        guard let t = cargo.transportable else { return "null-transportable" }
        return t.invalidReason().map { "cargo-" + $0 }
    }

    override class func invalidMissionReason(_ aiUnit: AIUnit?) -> String? {
        invalidUnitReason(aiUnit)
    }

    static func invalidMissionReason(_ aiUnit: AIUnit?, _ loc: (any Location)?) -> String? {
        if let reason = invalidMissionReason(aiUnit) { return reason }
        if loc is Tile { return nil }
        if loc is Europe || loc is Colony { return invalidTargetReason(loc, aiUnit!.unit.owner) }
        return Mission.targetInvalid
    }

    // MARK: For transportables

    @discardableResult
    func removeTransportable(_ t: TransportableAIObject) -> Bool {
        guard let cargo = tFind(t) else { return false }
        return tRemove(cargo)
    }

    @discardableResult
    func requeueTransportable(_ t: TransportableAIObject) -> Bool {
        guard let cargo = tFind(t) else { return queueTransportable(t, false) }
        return requeueCargo(cargo)
    }

    @discardableResult
    func queueTransportable(_ t: TransportableAIObject, _ requireMatch: Bool) -> Bool {
        guard let cargo = makeCargo(t) else { return false }
        return queueCargo(cargo, requireMatch)
    }

    @discardableResult
    func dumpTransportable(_ t: TransportableAIObject?) -> Bool {
        guard let t, let cargo = tFind(t) else { return true }
        if !isCarrying(t) {
            removeTransportable(t)
            return true
        }
        return dumpCargo(cargo)
    }

    /// Collect a unit before anything else (forceCollection).
    func forceCollection(_ aiu: AIUnit) -> Bool {
        for c in cargoes where c.mode.isCollection { removeCargo(c) }
        return queueTransportable(aiu, false)
    }

    func suppressEuropeanTrade(_ type: GoodsType) {
        for c in cargoes where c.isEuropeanTrade(type) { removeCargo(c) }
    }

    // MARK: Mission

    /// A carrier is not carried.
    override var transportDestination: (any Location)? { nil }

    override var target: (any Location)? {
        get { transportTarget }
        set { transportTarget = newValue }
    }

    override func findTarget() -> (any Location)? { nil }

    override func invalidReason() -> String? {
        if let reason = TransportMission.invalidMissionReason(aiUnit, target) { return reason }
        guard let cargo = tFirst() else { return nil }
        return TransportMission.invalidCargoReason(cargo)
    }

    override func doMission() -> Mission? {
        checkCargoes()
        if invalidReason() != nil { return lbFail(false) }
        let fallBackDecider = CostDeciders.avoidSettlementsAndBlockingUnits()
        let euaip = aiPlayer as? EuropeanAIPlayer
        var costDecider = CostDeciders.defaultCostDecider(for: unit)
        var usingFallBack = false
        while true {
            let mt = travelToTarget(transportTarget, costDecider)
            switch mt {
            case .move: // Arrived.
                doTransport()
                if isEmpty && unit.isOffensiveUnit, euaip?.privateerMission(aiUnit, nil) != nil {
                    return lbDone(false)
                }
                if invalidReason() != nil { return lbFail(false) } // Java warns
                if unit.isAtLocation(transportTarget) { return lbWait() }
            case .moveHighSeas, .moveNoMoves, .moveIllegal:
                return lbWait()
            case .moveNoRepair:
                return lbFail(false)
            case .moveNoTile:
                _ = moveRandomly("AI transport", nil)
                return lbDodge()
            case .attackUnit, .moveNoAttackCivilian:
                if mt == .attackUnit,
                   let blocker = Mission.resolveBlockage(aiUnit, transportTarget) as? Unit, shouldAttack(blocker),
                   let from = unit.tile, let to = blocker.tile, let d = from.direction(to: to) {
                    aiUnit.aiOwner?.ask(.attack(unit: unit.id, direction: d.javaName))
                    return self
                }
                if (unit.tile.flatMap { u in transportTarget?.tile.map { u.isAdjacent($0) } } ?? false)
                    || usingFallBack {
                    _ = moveRandomly("AI transport", nil)
                    return lbDodge()
                }
                costDecider = fallBackDecider
                usingFallBack = true
            default:
                return self
            }
        }
    }
}

/// Every order of a list, in Java's CollectionUtils.getPermutations
/// order.
func javaPermutations<T>(_ l: [T]) -> [[T]] {
    let n = l.count
    var np = n
    var k = n
    while true {
        k -= 1
        if k <= 1 { break }
        np *= k
    }
    var result: [[T]] = []
    for index in 0..<np {
        var pick = l
        var perm: [T] = []
        var current = index
        var divisor = np
        var i = n
        while i > 0 {
            divisor /= i
            let j = current / divisor
            perm.append(pick.remove(at: j))
            current -= j * divisor
            i -= 1
        }
        result.append(perm)
    }
    return result
}

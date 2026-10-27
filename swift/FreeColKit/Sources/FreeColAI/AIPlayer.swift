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

/// A computer player (server/ai/AIPlayer): its own generator, the
/// answers it gives to what the server asks, and its turn.
open class AIPlayer: AIObject {

    public unowned let player: Player
    /// The player's own generator, seeded from the server's when it was
    /// made.
    public let aiRandom: JavaRandom

    init(_ aiMain: AIMain, _ player: Player, _ seed: Int32) {
        self.player = player
        aiRandom = JavaRandom(seed: Int64(seed))
        super.init(aiMain, player.id)
        initialized = true
    }

    /// The nation type's suffix, which names its advantage
    /// (getAIAdvantage).
    var aiAdvantage: String {
        let prefix = "model.nationType."
        let id = player.nationType?.id ?? ""
        return id.hasPrefix(prefix) ? String(id.dropFirst(prefix.count)) : ""
    }

    func removeAIObject(_ ao: AIObject) {}

    func aiUnit(_ unit: Unit?) -> AIUnit? {
        aiMain.aiUnit(unit)
    }

    /// The AI units of the player's units, in the order of its unit set
    /// (getAIUnits).
    func aiUnits() -> [AIUnit] {
        player.units.compactMap { aiMain.aiUnit($0) }
    }

    /// The stance the tension calls for (determineStance).
    func determineStance(_ other: Player) -> Player.Stance {
        player.stance(other).stance(fromTension: player.tension(other))
    }

    // MARK: Asking the server

    /// Send a command, as Java's AIMessage does through the server API,
    /// and handle the reply.  Java's API reports success if the server
    /// answered at all, refused or not.
    @discardableResult
    public func ask(_ command: PlayerCommand) -> Bool {
        do {
            if let cs = try aiMain.controller.perform(command, by: player), let update = try cs.build(player) {
                aiMain.handle(update, for: player)
            }
        } catch is CommandRefused {
            // An error reply.
        } catch {
            aiMain.record(error, "\(player.nationId ?? "") asked \(command)")
        }
        return true
    }

    /// End the turn (askEndTurn).  The reply is not handled.
    func askEndTurn() {
        do {
            _ = try aiMain.controller.endTurn(player)
        } catch {
            aiMain.record(error, "\(player.nationId ?? "") ending its turn")
        }
    }

    // MARK: Handling what the server sends

    /// One message, as its aiHandler does.
    func handle(_ m: ServerMessage) {
        switch m {
        case let m as SetCurrentPlayerMessage:
            setCurrentPlayerHandler(m.player)
        case let m as ChooseFoundingFatherMessage:
            chooseFoundingFatherHandler(m.fathers)
        case let m as MonarchActionMessage:
            monarchActionHandler(m.action, m.tax ?? -1)
        case let m as FirstContactMessage:
            ask(.firstContact(player: m.player.id, other: m.other.id, tile: m.tile?.id, result: "true"))
        case let m as FountainOfYouthMessage:
            for _ in 0..<m.migrants { ask(.emigrateUnit(slot: "0")) }
        case let m as IndianDemandMessage:
            indianDemandHandler(m.unit, m.colony, m.type, m.amount, m.result)
        case let m as LootCargoMessage:
            lootCargoHandler(m.winner, m.goods, m.loserId)
        case let m as NationSummaryMessage:
            nationSummaries[m.player.id ?? ""] = m.summary
        case let m as NativeTradeMessage:
            let result = handleTrade(m.action, m.trade)
            ask(.nativeTrade(action: result.javaName, trade: CommandElement(serializing: m.trade)))
        case let m as NewLandNameMessage:
            ask(.newLandName(unit: m.unit.id, name: m.name))
        case let m as NewRegionNameMessage:
            ask(.newRegionName(region: m.region.id, tile: m.tile.id, unit: m.unit.id, name: m.name))
        case let m as DiplomacyMessage:
            diplomacyHandler(m)
        default:
            break
        }
    }

    /// The nation summaries this player was sent.
    public internal(set) var nationSummaries: [String: NationSummary] = [:]

    func setCurrentPlayerHandler(_ current: Player) {
        guard current === player else { return }
        switch aiMain.works {
        case .all: startWorking()
        case .natives: if player.isIndian { startWorking() }
        case .colonies: if !player.isREF { startWorking() }
        }
        askEndTurn()
    }

    func chooseFoundingFatherHandler(_ fathers: [FoundingFather]) {
        guard let ff = selectFoundingFather(fathers) else { return }
        ask(.chooseFoundingFather(father: ff.id))
    }

    func monarchActionHandler(_ action: Monarch.MonarchAction, _ tax: Int) {
        let accept: Bool
        switch action {
        case .raiseTaxWar, .raiseTaxAct: accept = acceptTax(tax)
        case .monarchMercenaries, .hessianMercenaries: accept = acceptMercenaries()
        default: return
        }
        ask(.monarchAction(action: action.javaName, result: accept ? "true" : "false"))
    }

    func indianDemandHandler(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int,
                             _ initial: IndianDemandAction?) {
        let result = indianDemand(unit, colony, type, amount, initial)
        if result != .done {
            ask(.indianDemand(unit: unit.id, colony: colony.id, type: type?.id, amount: String(amount),
                              result: result.javaName.lowercased()))
        }
    }

    func lootCargoHandler(_ unit: Unit, _ initialGoods: [Goods], _ defenderId: String) {
        guard let market = player.market else { return }
        // The most valuable first.
        var goods = initialGoods.stableSorted { a, b in
            market.salePrice(a.type!, a.amount) > market.salePrice(b.type!, b.amount)
        }
        var loot: [Goods] = []
        var space = unit.spaceLeft
        while space > 0 && !goods.isEmpty {
            let g = goods.removeFirst()
            if g.spaceTaken > space { continue }
            loot.append(g)
            space -= g.spaceTaken
        }
        ask(.lootCargo(winner: unit.id, loser: defenderId, goods: loot.map { CommandElement(serializing: $0) }))
    }

    func diplomacyHandler(_ m: DiplomacyMessage) {
        guard let agreement = m.agreement, agreement.status == .proposeTrade else { return }
        agreement.status = acceptDiplomaticTrade(agreement)
        ask(.diplomacy(our: m.ourId, other: m.otherId, agreement: CommandElement(serializing: agreement)))
    }

    // MARK: For subclasses

    /// The player's turn.
    open func startWorking() {}

    open func indianDemand(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int,
                           _ accept: IndianDemandAction?) -> IndianDemandAction {
        .reject
    }

    open func acceptDiplomaticTrade(_ agreement: DiplomaticTrade) -> DiplomaticTrade.TradeStatus {
        .rejectTrade
    }

    open func handleTrade(_ action: NativeTrade.NativeTradeAction, _ nt: NativeTrade)
        -> NativeTrade.NativeTradeAction {
        .nakInvalid
    }

    open func acceptTax(_ tax: Int) -> Bool { false }
    open func acceptMercenaries() -> Bool { false }
    open func selectFoundingFather(_ ffs: [FoundingFather]) -> FoundingFather? { nil }
}

/// A computer player that gives its units missions
/// (server/ai/MissionAIPlayer).
open class MissionAIPlayer: AIPlayer {

    private var cachedAIUnits: [AIUnit] = []

    override func removeAIObject(_ ao: AIObject) {
        if let aiu = ao as? AIUnit {
            _ = aiu.dropTransport()
            aiu.changeMission(nil)
            cachedAIUnits.removeAll { $0 === aiu }
        } else {
            super.removeAIObject(ao)
        }
    }

    func clearAIUnits() {
        cachedAIUnits = []
    }

    /// Note a new unit (addAIUnit).
    func addAIUnit(_ aiUnit: AIUnit) {
        cachedAIUnits.append(aiUnit)
    }

    /// The AI units, gathered once until cleared.
    override func aiUnits() -> [AIUnit] {
        if cachedAIUnits.isEmpty { cachedAIUnits = super.aiUnits() }
        return cachedAIUnits
    }

    /// How many of the player's units defend a settlement, there.
    func settlementDefenders(_ settlement: Settlement) -> Int {
        aiUnits().filter { au in
            guard let dm = au.mission as? DefendSettlementMission else { return false }
            return dm.target === settlement && au.unit.settlement === settlement
        }.count
    }

    func defendSettlementMission(_ aiUnit: AIUnit, _ target: Settlement) -> Mission? {
        DefendSettlementMission.invalidMissionReason(aiUnit) != nil ? nil
            : DefendSettlementMission(aiMain, aiUnit, target)
    }

    /// Defend the settlement the unit is in, if badly defended
    /// (getDefendCurrentSettlementMission).
    func defendCurrentSettlementMission(_ aiUnit: AIUnit) -> Mission? {
        if DefendSettlementMission.invalidMissionReason(aiUnit) != nil { return nil }
        guard let settlement = aiUnit.unit.location?.settlement, settlement.settlementIsBadlyDefended else { return nil }
        return defendSettlementMission(aiUnit, settlement)
    }

    func idleAtSettlementMission(_ aiUnit: AIUnit) -> Mission? {
        IdleAtSettlementMission.invalidMissionReason(aiUnit) != nil ? nil
            : IdleAtSettlementMission(aiMain, aiUnit)
    }

    func seekAndDestroyMission(_ aiUnit: AIUnit, range: Int) -> Mission? {
        var loc: (any Location)?
        if UnitSeekAndDestroyMission.invalidMissionReason(aiUnit) == nil {
            loc = UnitSeekAndDestroyMission.findMissionTarget(aiUnit, range, false, false)
        }
        return loc.flatMap { seekAndDestroyMission(aiUnit, $0) }
    }

    func seekAndDestroyMission(_ aiUnit: AIUnit, _ loc: (any Location)?) -> Mission? {
        guard let loc, UnitSeekAndDestroyMission.invalidMissionReason(aiUnit) == nil else { return nil }
        return UnitSeekAndDestroyMission(aiMain, aiUnit, loc)
    }

    func wanderHostileMission(_ aiUnit: AIUnit) -> Mission? {
        UnitWanderHostileMission.invalidMissionReason(aiUnit) != nil ? nil
            : UnitWanderHostileMission(aiMain, aiUnit)
    }

    /// Carry out each unit's mission.
    ///
    /// - Returns: The units with moves left.
    func doMissions(_ aiUnits: [AIUnit]) -> [AIUnit] {
        var result: [AIUnit] = []
        for aiu in aiUnits {
            let unit = aiu.unit
            if unit.isDisposed { continue }
            aiu.doMission()
            if !unit.isDisposed && unit.movesLeft > 0 { result.append(aiu) }
        }
        return result
    }

    /// Adjust a mission's value for this player (adjustMission).
    open func adjustMission(_ aiUnit: AIUnit, _ path: PathNode, _ type: Mission.Type, _ value: Int) -> Int {
        value
    }
}

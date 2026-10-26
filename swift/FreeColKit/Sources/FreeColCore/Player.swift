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

extension FreeColGameObject {
    /// Java's FreeColGameObject.hashCode: the identifier's hash and the
    /// game's (Game.hashCode hashes the game's identifier).
    public var javaGameObjectHash: Int32 {
        31 &* javaHashCode &+ (game?.javaHashCode ?? 31)
    }
}

/// A player (common/model/Player).
///
/// The economy, founding fathers, claims and colony values are in
/// PlayerRules.swift.
///
/// Labels are in Labels.swift, strength and visibility in
/// Defence.swift.  Not yet ported: name generation (NameCache, Phase
/// 3); the score breakdown; the nation summaries (Phase 4);
/// connections; copyIn and the integrity check.
///
/// The player holds its Europe, high seas, market, monarch, trade
/// routes, units and settlements.
public final class Player: FreeColGameObject, GameObjectReadable {

    public static let tag = "player"

    /// The kinds of player.
    public enum PlayerType: JavaEnum, CustomStringConvertible {
        case native, colonial, rebel, independent, royal, undead, retired

        public var javaName: String {
            switch self {
            case .native: "NATIVE"
            case .colonial: "COLONIAL"
            case .rebel: "REBEL"
            case .independent: "INDEPENDENT"
            case .royal: "ROYAL"
            case .undead: "UNDEAD"
            case .retired: "RETIRED"
            }
        }

        public var description: String {
            javaName
        }
    }

    /// The player's name ("username" in saved games).
    public var name: String?
    public var independentNationName: String?
    public var newLandName: String?
    public private(set) var nationId: String?
    public private(set) var playerType: PlayerType?
    public private(set) var nationType: NationType?
    public private(set) var foundingFathers: [FoundingFather] = []
    public var currentFather: FoundingFather?
    public private(set) var offeredFathers: [FoundingFather] = []
    public var europe: Europe?
    public private(set) var highSeas: HighSeas?
    public private(set) var market: Market?
    public var monarch: Monarch?
    let features = FeatureContainer()

    /// Gold, or goldNotAccounted for players who do not count it.
    public var gold = 0
    public var isAdmin = false
    public var isAI = false
    public var ready = false
    public var isDead = false
    public var attackedByPrivateers = false
    public var bankrupt = false
    public var score = 0
    public internal(set) var tax = 0
    var immigrationPoints = 0
    var libertyPoints = 0
    public var oldSoL = 0
    public var interventionBells = 0
    public var immigrationRequired = 12
    /// The stance towards each other player, by identifier.
    private var stances: [String: Stance] = [:]
    /// The tension towards each other player, by identifier.
    private var tensions: [String: Tension] = [:]
    /// The European players banned from building missions here.
    private var bannedMissions: Set<ObjectIdentifier> = []
    private var tradeRouteList: [TradeRoute] = []
    /// The player's history, oldest first.
    public private(set) var history: [HistoryEvent] = []
    /// The messages for the player, in the order added.
    public private(set) var modelMessages: [ModelMessage] = []
    /// The last sale prices, by LastSale key.
    private var lastSales: [String: LastSale]?

    /// The units this player owns, in Java's HashSet order.
    private var ownedUnits = JavaHashMap<UnitKey, Unit>(javaHash: { $0.hash })
    /// The settlements this player owns, in the order acquired.
    public private(set) var settlements: [Settlement] = []
    /// Keeps the colonies sorted when set (a client preference).
    public var colonyComparator: ((Colony, Colony) -> Int)?

    /// Where the player's units arrive from Europe by default.
    public weak var entryTile: Tile?

    /// Goods sold this turn (by a custom house) whose effect on the
    /// other European markets is still to come.  Server state, not
    /// saved (ServerPlayer.extraTrades).
    public var extraTrades: [AbstractGoods] = []

    /// The players whose stance towards this one changed this turn, to
    /// tell others about at the new turn.  Server state, not saved
    /// (ServerPlayer.stanceDirty).
    public var stanceDirty: [Player] = []

    /// Recruits still to come from a Fountain of Youth, chosen by the
    /// player.  Server state, not saved (ServerPlayer.remainingEmigrants).
    public var remainingEmigrants = 0

    var maximumFoodConsumptionCache = -1
    /// The tiles the player can see, until invalidated.
    /// Keyed by position, as Java's array, so a copy of a tile counts
    /// as its original.
    var canSeeTiles: Set<Map.Position>?
    private lazy var nextActiveUnitIterator = UnitIterator(self) { $0.isCandidateForNextActiveUnit }
    private lazy var nextGoingToUnitIterator = UnitIterator(self) { $0.goingToDestination }

    /// Gold for players who do not count it.
    public static let goldNotAccounted = Int(Int32.min)

    /// A unit as a key in the unit set, hashed as Java hashes it.
    private struct UnitKey: Hashable {
        let unit: Unit
        let hash: Int32

        init(_ unit: Unit) {
            self.unit = unit
            hash = unit.javaGameObjectHash
        }

        static func == (a: UnitKey, b: UnitKey) -> Bool { a.unit === b.unit }
        func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(unit)) }
    }

    /// How players stand towards each other (common/model/Stance).
    public enum Stance: JavaEnum, CustomStringConvertible {
        case uncontacted, alliance, peace, ceaseFire, war

        public var javaName: String {
            switch self {
            case .uncontacted: "UNCONTACTED"
            case .alliance: "ALLIANCE"
            case .peace: "PEACE"
            case .ceaseFire: "CEASE_FIRE"
            case .war: "WAR"
            }
        }

        public var description: String {
            javaName
        }
    }

    /// Why a player can not claim a tile (Player.NoClaimReason).
    public enum NoClaimReason: JavaEnum, CustomStringConvertible {
        /// The tile can be claimed.
        case none
        /// Not settleable terrain.
        case terrain
        /// Europeans can not claim tiles with a rumour.
        case rumour
        /// Natives do not claim water.
        case water
        /// A hostile unit is there.
        case occupied
        /// A settlement is there.
        case settlement
        /// One of our settlements is working the tile.
        case worked
        /// Owned by Europeans and not for sale.
        case europeans
        /// Owned by natives, who want payment.
        case natives

        public var javaName: String {
            switch self {
            case .none: "NONE"
            case .terrain: "TERRAIN"
            case .rumour: "RUMOUR"
            case .water: "WATER"
            case .occupied: "OCCUPIED"
            case .settlement: "SETTLEMENT"
            case .worked: "WORKED"
            case .europeans: "EUROPEANS"
            case .natives: "NATIVES"
            }
        }

        public var description: String {
            javaName
        }
    }

    public required init(readingIn game: Game) {
        super.init(game: game, id: nil)
    }

    /// Create a player for a nation (the model side of Java's
    /// ServerPlayer constructor and initialize): Europeans get Europe,
    /// the high seas and, unless royal, a monarch; everyone gets a
    /// market.
    ///
    /// - Parameters:
    ///   - game: The game, which issues the identifier.
    ///   - nation: The player's nation.
    ///   - admin: Whether the player administers the game.
    public init(game: Game, nation: Nation, admin: Bool = false) {
        super.init(game: game)
        name = Messages.rulerName(nation.id)
        isAdmin = admin
        nationId = nation.id
        immigrationPoints = 0
        if nation.isUnknownEnemy {
            nationType = nil
            playerType = .colonial
            gold = 0
            isAI = true
            ready = true
        } else if let type = nation.type {
            nationType = type
            addFeatures(of: type)
            if type.isEuropean {
                playerType = type.isREF ? .royal : .colonial
                europe = Europe(game: game, owner: self)
                highSeas = HighSeas(game: game)
                highSeas?.addDestination(europe)
                highSeas?.addDestination(game.map)
                if playerType == .colonial {
                    monarch = Monarch(game: game, player: self)
                    immigrationPoints = specification?.getInteger(GameOptions.playerImmigrationBonus) ?? 0
                }
                gold = 0
            } else {
                playerType = .native
                gold = Player.goldNotAccounted
            }
        } else {
            preconditionFailure("Bogus nation: \(nation)")
        }
        market = Market(game: game, owner: self)
        libertyPoints = 0
        currentFather = nil
    }

    public override var xmlTagName: String {
        Player.tag
    }

    /// Whether this is the player standing for unknown enemies.
    public var isUnknownEnemy: Bool {
        nationId == Nation.unknownNationId
    }

    /// The player's features: its nation type's, its founding fathers'
    /// and its own.
    public override var featureContainer: FeatureContainer? {
        features
    }

    /// Whether this player owns something.
    public func owns(_ ownable: Ownable?) -> Bool {
        ownable?.owner === self
    }

    // MARK: Kinds

    public var isColonial: Bool { playerType == .colonial }
    public var isRebel: Bool { playerType == .rebel }
    public var isREF: Bool { playerType == .royal }
    public var isIndian: Bool { playerType == .native }
    public var isUndead: Bool { playerType == .undead }

    public var isEuropean: Bool {
        playerType == .colonial || playerType == .rebel || playerType == .independent
            || playerType == .royal
    }

    /// Change the player type, gaining the independence abilities on
    /// rebelling.
    public func changePlayerType(_ type: PlayerType?) {
        if playerType != .rebel && playerType != .independent && (type == .rebel || type == .independent) {
            addAbility(Ability(Ability.independenceDeclared))
            addAbility(Ability(Ability.independentNation))
        }
        playerType = type
    }

    public func changeNationType(_ newNationType: NationType?) {
        if let nationType { removeFeatures(of: nationType) }
        nationType = newNationType
        if let newNationType { addFeatures(of: newNationType) }
    }

    /// Whether a player at peace (or in a cease fire) with this one
    /// could be turned against it by the monarch.
    public func isPotentialEnemy(_ player: Player) -> Bool {
        if !hasAbility(Ability.ignoreEuropeanWars) && player.refPlayer !== self {
            switch stance(player) {
            case .peace, .ceaseFire: return true
            default: break
            }
        }
        return false
    }

    /// Whether a player at war (or in a cease fire) with this one could
    /// make peace through the monarch.
    public func isPotentialFriend(_ player: Player) -> Bool {
        if player.refPlayer !== self {
            switch stance(player) {
            case .war, .ceaseFire: return true
            default: break
            }
        }
        return false
    }

    public var canBuildColonies: Bool {
        nationType?.hasAbility(Ability.foundsColonies) ?? false
    }

    public var canHaveFoundingFathers: Bool {
        nationType?.hasAbility(Ability.electFoundingFather) ?? false
    }

    public var nation: Nation? {
        specification?.getNation(nationId)
    }

    public var isReady: Bool {
        ready || isAI
    }

    /// Whether the REF still has work to do: units in the new world, or
    /// rebels.
    public var isWorkForREF: Bool {
        units.contains { $0.hasTile } || !rebels.isEmpty
    }

    /// The rebels or undead this player is the REF of.
    public var rebels: [Player] {
        game?.liveEuropeanPlayers(excluding: self).filter {
            $0.refPlayer === self && ($0.isRebel || $0.isUndead)
        } ?? []
    }

    /// The player's REF.
    public var refPlayer: Player? {
        game?.player(byNation: nation?.refNation)
    }

    /// Java's playerComparator: by rank.
    public static func comparePlayers(_ a: Player, _ b: Player) -> Int {
        a.rank < b.rank ? -1 : a.rank > b.rank ? 1 : 0
    }

    /// Sorts humans before AIs, and the administrator last.
    public var rank: Int {
        var ret = isEuropean ? 1 : 0
        if isAI { ret |= 2 }
        if isAdmin { ret |= 4 }
        return ret
    }

    public var spanishSuccessionScore: Int {
        score
    }

    // MARK: Gold

    public func checkGold(_ amount: Int) -> Bool {
        gold == Player.goldNotAccounted || gold >= amount
    }

    /// Add gold, but never below zero (Java logs a warning then).
    @discardableResult
    public func modifyGold(_ amount: Int) -> Int {
        if gold != Player.goldNotAccounted {
            gold = gold + amount >= 0 ? gold + amount : 0
        }
        return gold
    }

    // MARK: What the player owns

    /// The units this player owns, in Java's order (a copy of the
    /// HashSet, as Java's getUnitSet makes, which can reorder it).
    public var units: [Unit] {
        let n = ownedUnits.count
        if n == 0 { return [] }
        var copy = JavaHashMap<UnitKey, Unit>(initialCapacity: max(Int(Float(n) / 0.75) + 1, 16),
                                              javaHash: { $0.hash })
        for (key, unit) in ownedUnits.entries { _ = copy.put(key, unit) }
        return copy.values
    }

    public var unitCount: Int {
        ownedUnits.count
    }

    public func hasUnit(_ unit: Unit) -> Bool {
        ownedUnits[UnitKey(unit)] != nil
    }

    @discardableResult
    public func addUnit(_ unit: Unit) -> Bool {
        precondition(owns(unit), "Adding another player's unit: \(unit.id ?? "") to \(self)")
        guard !hasUnit(unit) else { return false }
        _ = ownedUnits.put(UnitKey(unit), unit)
        return true
    }

    @discardableResult
    public func removeUnit(_ unit: Unit) -> Bool {
        nextActiveUnitIterator.remove(unit)
        nextGoingToUnitIterator.remove(unit)
        return ownedUnits.removeValue(forKey: UnitKey(unit)) != nil
    }

    public func unit(byName name: String?) -> Unit? {
        ownedUnits.values.first { $0.name == name }
    }

    /// The units that could carry a unit.
    public func carriers(for unit: Unit) -> [Unit] {
        units.filter { $0.couldCarry(unit) }
    }

    public func unitCount(naval: Bool) -> Int {
        units.filter { $0.isNaval == naval }.count
    }

    public var numberOfKingLandUnits: Int {
        units.filter { $0.hasAbility(Ability.refUnit) && !$0.isNaval }.count
    }

    public func hasUnitType(_ typeId: String) -> Bool {
        units.contains { $0.type?.id == typeId }
    }

    /// The next unit to move this turn, or nil.
    public func nextActiveUnit() -> Unit? {
        nextActiveUnitIterator.next()
    }

    public var hasNextActiveUnit: Bool {
        nextActiveUnitIterator.hasNext()
    }

    /// The next unit to move towards its destination, or nil.
    public func nextGoingToUnit() -> Unit? {
        nextGoingToUnitIterator.next()
    }

    @discardableResult
    public func setNextGoingToUnit(_ unit: Unit) -> Bool {
        nextGoingToUnitIterator.setNext(unit)
    }

    public var hasNextGoingToUnit: Bool {
        nextGoingToUnitIterator.hasNext()
    }

    public func resetIterators() {
        nextActiveUnitIterator.reset()
        nextGoingToUnitIterator.reset()
    }

    /// The unit that was active when the game was saved, if it is ours,
    /// otherwise the next active unit.
    public func restoreActiveUnit() -> Unit? {
        guard let game else { return nil }
        let u = game.initialActiveUnit
        game.initialActiveUnitId = nil
        if let u, owns(u) { return u }
        resetIterators()
        return nextActiveUnit()
    }

    // MARK: Trade routes

    public var tradeRoutes: [TradeRoute] {
        tradeRouteList
    }

    public var tradeRouteCount: Int {
        tradeRouteList.count
    }

    public var newestTradeRoute: TradeRoute? {
        tradeRouteList.last
    }

    /// Add a trade route, unless it has no name or the name is taken.
    public func addTradeRoute(_ tradeRoute: TradeRoute?) {
        guard let tradeRoute, let name = tradeRoute.name,
              self.tradeRoute(byName: name, excluding: tradeRoute) == nil else { return }
        tradeRouteList.append(tradeRoute)
    }

    public func tradeRoute(byName name: String?, excluding exclude: TradeRoute?) -> TradeRoute? {
        tradeRouteList.first { $0 !== exclude && $0.name == name }
    }

    /// Remove a trade route, taking its units off it.
    ///
    /// - Returns: The units that were following it.
    @discardableResult
    public func removeTradeRoute(_ tradeRoute: TradeRoute) -> [Unit] {
        guard let i = tradeRouteList.firstIndex(where: { $0 === tradeRoute }) else { return [] }
        tradeRouteList.remove(at: i)
        let ret = tradeRoute.assignedUnits
        for u in ret { u.tradeRoute = nil }
        return ret
    }

    // MARK: Settlements

    public var hasSettlements: Bool {
        !settlements.isEmpty
    }

    public var settlementCount: Int {
        settlements.count
    }

    public func hasSettlement(_ settlement: Settlement) -> Bool {
        settlements.contains { $0 === settlement }
    }

    /// Add a settlement, in the colony order if one is set.
    @discardableResult
    public func addSettlement(_ settlement: Settlement) -> Bool {
        precondition(owns(settlement), "Does not own: \(settlement)")
        guard !hasSettlement(settlement) else { return false }
        if let colonyComparator {
            let c = settlement as! Colony
            var i = settlements.count - 1
            while i >= 0 {
                if colonyComparator(c, settlements[i] as! Colony) >= 0 { break }
                i -= 1
            }
            settlements.insert(settlement, at: i + 1)
        } else {
            settlements.append(settlement)
        }
        return true
    }

    @discardableResult
    public func removeSettlement(_ settlement: Settlement) -> Bool {
        guard let i = settlements.firstIndex(where: { $0 === settlement }) else { return false }
        settlements.remove(at: i)
        return true
    }

    public var colonyList: [Colony] {
        settlements.compactMap { $0 as? Colony }
    }

    public var indianSettlementList: [IndianSettlement] {
        settlements.compactMap { $0 as? IndianSettlement }
    }

    /// The colonies, sorted (stably) by a three-way comparison.
    public func sortedColonies(_ comp: (Colony, Colony) -> Int) -> [Colony] {
        colonyList.stableSorted { comp($0, $1) < 0 }
    }

    /// The number of colonies with a connection to the high seas.
    public var numberOfPorts: Int {
        isEuropean ? colonyList.filter(\.isConnectedPort).count : 0
    }

    public var connectedPortList: [Colony] {
        isEuropean ? colonyList.filter(\.isConnectedPort) : []
    }

    public var coloniesPopulation: Int {
        colonyList.reduce(0) { $0 + $1.unitCount }
    }

    public func colony(byName name: String?) -> Colony? {
        colonyList.first { $0.name == name }
    }

    public func indianSettlement(byName name: String?) -> IndianSettlement? {
        indianSettlementList.first { $0.name == name }
    }

    public func settlement(byName name: String?) -> Settlement? {
        isIndian ? indianSettlement(byName: name) : colony(byName: name)
    }

    /// Our native settlements with a mission of another player.
    public func indianSettlementsWithMissionary(_ p: Player) -> [IndianSettlement] {
        indianSettlementList.filter { $0.hasMissionary(p) }
    }

    /// The settlement closest to the high seas (the first of the
    /// closest).
    public var closestPortForEurope: Settlement? {
        var best: Settlement?
        for s in settlements where best == nil || s.highSeasCount < best!.highSeasCount { best = s }
        return best
    }

    /// Where to put things with nowhere else: the first settlement's
    /// tile, or the entry tile.
    public var fallbackTile: Tile? {
        settlements.first?.tile ?? entryTile
    }

    /// Record a unit or settlement this player now owns.
    @discardableResult
    func addOwnable(_ o: Ownable) -> Bool {
        if let s = o as? Settlement { return addSettlement(s) }
        if let u = o as? Unit { return addUnit(u) }
        return false
    }

    @discardableResult
    func removeOwnable(_ o: Ownable) -> Bool {
        if let s = o as? Settlement { return removeSettlement(s) }
        if let u = o as? Unit { return removeUnit(u) }
        return false
    }

    // MARK: Europe and the high seas

    public var canMoveToEurope: Bool {
        europe != nil
    }

    /// The message key for the name of the player's Europe.
    public var europeNameKey: String? {
        europe == nil ? nil : "\(nationId ?? "null").europe"
    }

    /// New high seas leading to Europe and the map.
    public func initializeHighSeas() {
        guard let game else { return }
        let hs = HighSeas(game: game)
        if let europe { hs.addDestination(europe) }
        if let map = game.map { hs.addDestination(map) }
        highSeas = hs
    }

    public func reinitialiseMarket() {
        market = Market(game: game!, owner: self)
    }

    // MARK: Stances and tension

    public func stance(_ player: Player?) -> Stance {
        player?.id.flatMap { stances[$0] } ?? .uncontacted
    }

    /// Set the stance towards another player, nil to forget it.
    ///
    /// - Returns: Whether the change was valid (a cease fire needs a
    ///   war, and contact can not be undone).
    @discardableResult
    public func setStance(_ player: Player, _ newStance: Stance?) -> Bool {
        precondition(player !== self, "Cannot set the stance towards ourselves: \(self)")
        guard let id = player.id else { return false }
        guard let newStance else {
            stances[id] = nil
            return true
        }
        let oldStance = stances[id]
        if newStance == oldStance { return true }
        let valid = !((newStance == .ceaseFire && oldStance != .war) || newStance == .uncontacted)
        stances[id] = newStance
        return valid
    }

    public func atWar(with player: Player?) -> Bool {
        stance(player) == .war
    }

    /// Whether at war with any live player.
    public var isAtWar: Bool {
        game?.livePlayers.contains { atWar(with: $0) } ?? false
    }

    public func hasContacted(_ player: Player?) -> Bool {
        stance(player) != .uncontacted
    }

    public var hasContactedEuropeans: Bool {
        game?.liveEuropeanPlayers(excluding: self).contains { hasContacted($0) } ?? false
    }

    public var hasContactedIndians: Bool {
        game?.liveNativePlayers(excluding: self).contains { hasContacted($0) } ?? false
    }

    /// First contact: peace, and no tension, both ways.
    public static func makeContact(_ player1: Player, _ player2: Player) {
        if let id = player2.id { player1.stances[id] = .peace }
        if let id = player1.id { player2.stances[id] = .peace }
        player1.setTension(player2, Tension(Tension.tensionMin))
        player2.setTension(player1, Tension(Tension.tensionMin))
    }

    /// The tension towards another player, starting at none.
    public func tension(_ player: Player) -> Tension {
        let id = player.id ?? ""
        if let t = tensions[id] { return t }
        let t = Tension(Tension.tensionMin)
        tensions[id] = t
        return t
    }

    public func setTension(_ player: Player?, _ newTension: Tension) {
        guard let player, player !== self, let id = player.id else { return }
        tensions[id] = newTension
    }

    public func removeTension(_ player: Player?) {
        if let id = player?.id { tensions[id] = nil }
    }

    public func missionsBanned(_ player: Player) -> Bool {
        bannedMissions.contains(ObjectIdentifier(player))
    }

    public func addMissionBan(_ player: Player) {
        bannedMissions.insert(ObjectIdentifier(player))
    }

    public func removeMissionBan(_ player: Player) {
        bannedMissions.remove(ObjectIdentifier(player))
    }

    // MARK: Messages and history

    /// The messages not yet shown.
    public var newModelMessages: [ModelMessage] {
        modelMessages.filter { !$0.displayed }
    }

    public func addModelMessage(_ message: ModelMessage) {
        modelMessages.append(message)
    }

    public func removeDisplayedModelMessages() {
        modelMessages.removeAll { $0.displayed }
    }

    public func clearModelMessages() {
        modelMessages = []
    }

    /// Point the messages about one object at another, or drop them if
    /// there is none.
    public func divertModelMessages(_ source: FreeColGameObject, _ newSource: FreeColGameObject?) {
        guard let newSource else {
            modelMessages.removeAll { $0.sourceId == source.id }
            return
        }
        for m in modelMessages where m.sourceId == source.id { m.divert(newSource) }
    }

    /// The tutorial message at the start of the game: which way to sail.
    public func addStartGameMessage() {
        let sailTag: String
        if let tile = entryTile, let map = tile.map {
            sailTag = tile.x < map.width / 2 ? "east" : "west"
        } else {
            sailTag = "unknown"
        }
        addModelMessage(ModelMessage(.tutorial, "model.player.startGame", self).addTagged("%direction%", sailTag))
    }

    /// The message that a unit has emigrated.
    public func emigrationMessage(_ unit: Unit) -> ModelMessage {
        ModelMessage(.unitAdded, "model.player.emigrate", self, unit)
            .add("%europe%", europe?.nameKey).addStringTemplate("%unit%", unit.label)
    }

    public func addHistory(_ event: HistoryEvent) {
        history.append(event)
    }

    /// When each founding father was elected, by father id.
    public var electionTurns: [String: Turn] {
        var ret: [String: Turn] = [:]
        for he in history where he.eventType == .foundingFather {
            if let id = he.replacement("%father%")?.id, let turn = he.turn { ret[id] = turn }
        }
        return ret
    }

    // MARK: Last sales

    public func lastSale(_ location: any Location, _ what: GoodsType) -> LastSale? {
        lastSales?[LastSale.makeKey(location, what)]
    }

    public func addLastSale(_ sale: LastSale) {
        if lastSales == nil { lastSales = [:] }
        if let id = sale.id { lastSales![id] = sale }
    }

    public func lastSaleString(_ location: any Location, _ what: GoodsType) -> String? {
        lastSale(location, what).map { String($0.price) }
    }

    // MARK: Founding fathers

    /// Add a founding father and its features.
    public func addFather(_ father: FoundingFather) {
        if !foundingFathers.contains(where: { $0 === father }) { foundingFathers.append(father) }
        addFeatures(of: father)
        for c in colonyList { c.invalidateCache() }
    }

    public func hasFather(_ father: FoundingFather?) -> Bool {
        foundingFathers.contains { $0 === father }
    }

    public var fatherCount: Int {
        foundingFathers.count
    }

    public func setOfferedFathers(_ fathers: [FoundingFather]) {
        offeredFathers = fathers
    }

    public func clearOfferedFathers() {
        offeredFathers = []
    }

    /// Drop the market, monarch, Europe, founding fathers, trade routes,
    /// last sales and features of a player that has died (the end of
    /// ServerPlayer.csKill).  Messages and history are kept.
    public func removeEuropeanAssets() {
        market?.dispose()
        market = nil
        monarch?.dispose()
        monarch = nil
        europe?.dispose()
        europe = nil
        currentFather = nil
        foundingFathers = []
        offeredFathers = []
        tradeRouteList = []
        lastSales = nil
        features.clear()
    }

    /// The player methods limits name.
    public override func scopeMethodValue(_ methodName: String) -> String? {
        switch methodName {
        case "getSoL": "\(sonsOfLiberty)"
        case "isEuropean": "\(isEuropean)"
        case "isIndian": "\(isIndian)"
        case "isColonial": "\(isColonial)"
        case "isRebel": "\(isRebel)"
        case "isREF": "\(isREF)"
        case "isUndead": "\(isUndead)"
        case "isAI": "\(isAI)"
        case "isDead": "\(isDead)"
        case "getGold": "\(gold)"
        case "getTax": "\(tax)"
        case "getScore": "\(score)"
        case "getNationId": nationId
        case "getNationType": nationType?.id
        case "getPlayerType": playerType?.javaName
        default: super.scopeMethodValue(methodName)
        }
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        name = xr.attribute("username", default: nil as String?)
        nationId = xr.attribute("nationId", default: nil as String?)
        nationType = isUnknownEnemy ? nil
            : try specification.flatMap { try xr.getType($0, "nationType", NationType.self) }
        isAdmin = xr.attribute("admin", default: false)
        gold = xr.attribute("gold", default: 0)
        immigrationPoints = xr.attribute("immigration", default: 0)
        libertyPoints = xr.attribute("liberty", default: 0)
        interventionBells = xr.attribute("interventionBells", default: 0)
        oldSoL = xr.attribute("oldSoL", default: 0)
        score = xr.attribute("score", default: 0)
        ready = xr.attribute("ready", default: false)
        isAI = xr.attribute("ai", default: false)
        isDead = xr.attribute("dead", default: false)
        bankrupt = xr.attribute("bankrupt", default: false)
        tax = xr.attribute("tax", default: 0)
        changePlayerType(xr.attribute("playerType", PlayerType.self, default: nil))
        currentFather = try specification.flatMap { try xr.getType($0, "currentFather", FoundingFather.self) }
        immigrationRequired = xr.attribute("immigrationRequired", default: 12)
        newLandName = xr.attribute("newLandName", default: nil as String?)
        independentNationName = xr.attribute("independentNationName", default: nil as String?)
        attackedByPrivateers = xr.attribute("attackedByPrivateers", default: false)
        entryTile = try game.flatMap { try xr.makeFreeColObject($0, "entryLocation", Tile.self, required: false) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        tensions = [:]
        bannedMissions = []
        stances = [:]
        foundingFathers = []
        offeredFathers = []
        europe = nil
        monarch = nil
        tradeRouteList = []
        history = []
        // Java clears the messages only when reading as the server,
        // which this engine is.
        modelMessages = []
        lastSales = nil
        highSeas = nil
        features.clear()
        if let nationType { addFeatures(of: nationType) }
        try super.readChildren(xr)
        recalculateBellsBonus() // Bells bonuses depend on tax
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let spec = specification
        let game = game!
        switch xr.localName {
        case "banMissions":
            if let player = try xr.makeFreeColObject(game, "player", Player.self, required: true),
               player.isEuropean {
                addMissionBan(player)
            }
            try xr.closeTag("banMissions")
        case "foundingFathers":
            for father in try readList(xr, "foundingFathers", FoundingFather.self) {
                addFather(father)
            }
        case "offeredFathers":
            offeredFathers += try readList(xr, "offeredFathers", FoundingFather.self)
        case "stance":
            if let player = try xr.makeFreeColObject(game, "player", Player.self, required: true),
               let id = player.id {
                stances[id] = xr.attribute("value", Stance.self, default: .uncontacted) ?? .uncontacted
            }
            try xr.closeTag("stance")
        case "tension":
            if let player = try xr.makeFreeColObject(game, "player", Player.self, required: true),
               let id = player.id {
                tensions[id] = Tension(xr.attribute("value", default: 0))
            }
            try xr.closeTag("tension")
        case Ability.tag:
            let ability = try Ability(xr, specification: spec)
            if ability.isIndependent { addAbility(ability) }
        case Modifier.tag:
            let modifier = try Modifier(xr, specification: spec)
            if modifier.isIndependent { addModifier(modifier) }
        case Europe.tag:
            europe = try xr.readFreeColObject(game, Europe.self)
        case HighSeas.tag:
            highSeas = try xr.readFreeColObject(game, HighSeas.self)
        case LastSale.tag:
            addLastSale(try LastSale(xr))
        case Market.tag:
            market = try xr.readFreeColObject(game, Market.self)
        case Monarch.tag:
            monarch = try xr.readFreeColObject(game, Monarch.self)
        case TradeRoute.tag:
            addTradeRoute(try xr.readFreeColObject(game, TradeRoute.self))
        case HistoryEvent.historyEventTag:
            addHistory(try HistoryEvent(reading: xr))
        case ModelMessage.modelMessageTag:
            addModelMessage(try ModelMessage(reading: xr))
        default:
            try xr.swallowTag(xr.localName)
        }
    }

    // MARK: Writing XML

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("username", id: name)
        xw.writeAttribute("nationId", id: nationId)
        xw.writeAttribute("nationType", nationType)
        xw.writeAttribute("admin", isAdmin)
        xw.writeAttribute("ready", ready)
        xw.writeAttribute("dead", isDead)
        if let playerType { xw.writeAttribute("playerType", playerType) }
        xw.writeAttribute("ai", isAI)
        if xw.validFor(self) {
            xw.writeAttribute("bankrupt", bankrupt)
            xw.writeAttribute("tax", tax)
            xw.writeAttribute("gold", gold)
            xw.writeAttribute("immigration", immigrationPoints)
            xw.writeAttribute("liberty", libertyPoints)
            xw.writeAttribute("interventionBells", interventionBells)
            xw.writeAttribute("currentFather", currentFather)
            xw.writeAttribute("immigrationRequired", immigrationRequired)
            xw.writeAttribute("attackedByPrivateers", attackedByPrivateers)
            xw.writeAttribute("oldSoL", oldSoL)
            xw.writeAttribute("score", score)
            xw.writeAttribute("entryLocation", entryTile)
        }
        xw.writeAttribute("newLandName", id: newLandName)
        xw.writeAttribute("independentNationName", id: independentNationName)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if xw.validFor(self) {
            market?.toXML(xw)
            for ability in sortedAbilities where ability.isIndependent { ability.toXML(xw) }
            let turn = game?.turn
            for modifier in sortedModifiers where modifier.temporary && !modifier.isOutOfDate(turn) {
                modifier.toXML(xw)
            }
            for id in tensions.keys.sorted(by: { FreeColObject.compareIdentifiers($0, $1) < 0 }) {
                xw.writeStartElement("tension")
                xw.writeAttribute("player", id)
                xw.writeAttribute("value", tensions[id]!.value)
                xw.writeEndElement()
            }
            let banned = (game?.players ?? []) + [game?.unknownEnemy].compactMap { $0 }
            for p in sortedById(banned.filter { missionsBanned($0) }) {
                xw.writeStartElement("banMissions")
                xw.writeAttribute("player", id: p.id)
                xw.writeEndElement()
            }
            for id in stances.keys.sorted(by: { JavaString.compare($0, $1) < 0 }) {
                let s = stances[id]!
                if s == .uncontacted { continue }
                xw.writeStartElement("stance")
                xw.writeAttribute("player", id)
                xw.writeAttribute("value", s)
                xw.writeEndElement()
            }
            for event in history { event.toXML(xw) }
            for route in sortedById(tradeRoutes) { route.toXML(xw) }
            // Java holds the fathers in a HashSet.
            var fathers = JavaHashMap<FoundingFather, Bool>(javaHash: { $0.javaHashCode })
            for father in foundingFathers { _ = fathers.put(father, true) }
            xw.writeToListElement("foundingFathers", fathers.keys)
            xw.writeToListElement("offeredFathers", offeredFathers)
            europe?.toXML(xw)
            monarch?.toXML(xw)
            highSeas?.toXML(xw)
            for message in modelMessages { message.toXML(xw) }
            for sale in sortedById(lastSales?.values ?? [:].values) { sale.toXML(xw) }
        } else if let client = xw.clientPlayerObject {
            xw.writeStartElement("tension")
            xw.writeAttribute("player", client)
            xw.writeAttribute("value", tension(client).value)
            xw.writeEndElement()
            if missionsBanned(client) {
                xw.writeStartElement("banMissions")
                xw.writeAttribute("player", id: client.id)
                xw.writeEndElement()
            }
            let s = stance(client)
            if s != .uncontacted {
                xw.writeStartElement("stance")
                xw.writeAttribute("player", client)
                xw.writeAttribute("value", s)
                xw.writeEndElement()
            }
        }
    }

    /// A list of rule types saved as attributes x0, x1, ... with the
    /// count in xLength (FreeColXMLReader.readList).
    private func readList<T: FreeColSpecObjectType>(_ xr: FreeColXMLReader, _ tag: String,
                                                    _ type: T.Type) throws -> [T] {
        try xr.expectTag(tag)
        let length = xr.attribute("xLength", default: -1)
        var list: [T] = []
        if length > 0, let spec = specification {
            for i in 0..<length {
                // Java keeps a missing value as null.
                if let value = try xr.getType(spec, "x\(i)", T.self) { list.append(value) }
            }
        }
        try xr.closeTag(tag)
        return list
    }

    /// Java's toString: the nation identifier.
    public override var description: String {
        nationId ?? "null"
    }
}

/// Iterates over a player's units that pass a test, in location order,
/// refilling when it runs out (common/model/UnitIterator).
public final class UnitIterator {

    private unowned let owner: Player
    private let predicate: (Unit) -> Bool
    private var units: [Unit] = []

    public init(_ owner: Player, _ predicate: @escaping (Unit) -> Bool) {
        self.owner = owner
        self.predicate = predicate
    }

    private func update() {
        units = owner.units.filter(predicate).stableSorted { $0.rank < $1.rank }
    }

    /// Move to a unit, refilling once if need be.
    ///
    /// - Returns: Whether the unit is next.
    public func setNext(_ unit: Unit) -> Bool {
        guard predicate(unit) else { return false }
        let sentinel = units.first
        while !units.isEmpty {
            if units[0] === unit { return true }
            units.remove(at: 0)
        }
        update()
        while !units.isEmpty && units[0] !== sentinel {
            if units[0] === unit { return true }
            units.remove(at: 0)
        }
        return false
    }

    @discardableResult
    public func remove(_ u: Unit) -> Bool {
        guard let i = units.firstIndex(where: { $0 === u }) else { return false }
        units.remove(at: i)
        return true
    }

    public func reset() {
        update()
    }

    public func hasNext() -> Bool {
        while !units.isEmpty {
            if predicate(units[0]) { return true }
            units.remove(at: 0)
        }
        update()
        return !units.isEmpty
    }

    public func next() -> Unit? {
        hasNext() ? units.remove(at: 0) : nil
    }
}

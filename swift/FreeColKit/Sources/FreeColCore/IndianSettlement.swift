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

/// How angry a player or settlement is with another player
/// (common/model/Tension).
public struct Tension: Hashable, Sendable, CustomStringConvertible {

    /// The levels, with the highest tension each covers.
    public enum Level: JavaEnum, CustomStringConvertible {
        case happy, content, displeased, angry, hateful

        public var javaName: String {
            switch self {
            case .happy: "HAPPY"
            case .content: "CONTENT"
            case .displeased: "DISPLEASED"
            case .angry: "ANGRY"
            case .hateful: "HATEFUL"
            }
        }

        public var limit: Int {
            switch self {
            case .happy: 100
            case .content: 600
            case .displeased: 700
            case .angry: 800
            case .hateful: 1000
            }
        }

        public var key: String {
            javaName.lowercased()
        }

        public var description: String {
            javaName
        }
    }

    public static let tensionMin = 0
    public static let tensionMax = Level.hateful.limit + 100
    /// Hysteresis.
    public static let delta = 10
    public static let tensionAddMinor = 100
    public static let tensionAddNormal = 200
    public static let tensionAddMajor = 300
    public static let tensionAddLandTaken = 200
    public static let tensionAddUnitDestroyed = 400
    public static let tensionAddSettlementAttacked = 500
    public static let tensionAddCapitalAttacked = 600
    public static let tensionAddWarInciter = 250
    public static let contactModifier = 0
    public static let allianceModifier = -500
    public static let dropAllianceModifier = 200
    public static let peaceTreatyModifier = -250
    public static let ceaseFireModifier = -250
    public static let warModifier = Level.hateful.limit
    public static let resumeWarModifier = 750
    public static let surrendered = (Level.content.limit + Level.happy.limit) / 2

    /// The tension, kept within tensionMin and tensionMax.
    public private(set) var value = Level.happy.limit

    public init() {}

    public init(_ value: Int) {
        setValue(value)
    }

    public mutating func setValue(_ newValue: Int) {
        value = min(max(newValue, Tension.tensionMin), Tension.tensionMax)
    }

    public mutating func modify(_ amount: Int) {
        setValue(value + amount)
    }

    public var level: Level {
        Level.allCases.first { value <= $0.limit } ?? .hateful
    }

    public var key: String {
        "tension." + level.key
    }

    public var description: String {
        level.javaName
    }
}

/// A native settlement (common/model/IndianSettlement).
///
/// The settlement holds its missionary and the units it owns (its
/// braves, wherever they are); the most hated player is a weak
/// reference.
///
/// Defence and plunder are in Defence.swift.  Not yet ported:
/// addRandomGoods, which the server uses when making
/// settlements (Phase 3); labels; copyIn and the integrity
/// check.
public final class IndianSettlement: Settlement, GameObjectReadable {

    public static let tag = "indianSettlement"

    /// How well a player knows the settlement.
    public enum ContactLevel: JavaEnum, CustomStringConvertible {
        /// Nothing more than the location.
        case uncontacted
        /// The name and wanted goods are known.
        case contacted
        /// The skill is known.
        case visited
        /// The scouting bonus has been used.
        case scouted

        public var javaName: String {
            switch self {
            case .uncontacted: "UNCONTACTED"
            case .contacted: "CONTACTED"
            case .visited: "VISITED"
            case .scouted: "SCOUTED"
            }
        }

        public var description: String {
            javaName
        }
    }

    public static let nativeProductionEfficiency = 0.67
    public static let wantedGoodsCount = 3
    public static let talesRadius = 6
    public static let tradeMinimumSize = 20
    public static let tradeMinimumPrice = 3
    public static let goodsBasePrice = 12
    public static let keepRawMaterial = 50
    public static let giftThreshold = 25
    public static let giftMinimum = 10
    public static let giftMaximum = 80

    public var learnableSkill: UnitType?
    public private(set) var wantedGoods: [GoodsType?] = Array(repeating: nil, count: IndianSettlement.wantedGoodsCount)
    private var contactLevels: [String: ContactLevel] = [:]
    private var contactPlayers: [String: WeakPlayer] = [:]
    private var ownedUnits: [Unit] = []
    public var missionary: Unit?
    public var convertProgress = 0
    public var lastTribute = 0
    public weak var mostHated: Player?
    private var alarms: [String: Tension] = [:]
    public private(set) var goodsForSale: [Goods] = []

    private final class WeakPlayer {
        weak var player: Player?
        init(_ player: Player) { self.player = player }
    }

    public required override init(readingIn game: Game) {
        super.init(readingIn: game)
    }

    /// Create a native settlement (the model side of Java's
    /// ServerIndianSettlement constructor).  It is not on the map
    /// until placeSettlement.
    ///
    /// - Parameters:
    ///   - game: The game, which issues the identifier.
    ///   - owner: The owner.
    ///   - name: The settlement's name.
    ///   - tile: Where it is.
    ///   - isCapital: Whether it is the capital.
    ///   - learnableSkill: The skill taught here, if any.
    ///   - missionary: The missionary here, if any.
    public init(game: Game, owner: Player, name: String?, tile: Tile, isCapital: Bool,
                learnableSkill: UnitType?, missionary: Unit?) {
        super.init(game: game, owner: owner, name: name, tile: tile)
        setGoodsContainer(GoodsContainer(game: game, parent: self))
        self.learnableSkill = learnableSkill
        setCapital(isCapital)
        self.missionary = missionary
        convertProgress = 0
        updateWantedGoods()
    }

    public override var xmlTagName: String {
        IndianSettlement.tag
    }

    // MARK: Owned units

    /// The units whose home this is.
    public var ownedUnitList: [Unit] {
        ownedUnits
    }

    /// Orphan the units whose home this is.
    public override func disposeResources() {
        while !ownedUnits.isEmpty {
            ownedUnits.removeFirst().changeHomeIndianSettlement(nil)
        }
        super.disposeResources()
    }

    public func addOwnedUnit(_ unit: Unit) {
        if !ownedUnits.contains(where: { $0 === unit }) { ownedUnits.append(unit) }
    }

    @discardableResult
    public func removeOwnedUnit(_ unit: Unit) -> Bool {
        guard let i = ownedUnits.firstIndex(where: { $0 === unit }) else { return false }
        ownedUnits.remove(at: i)
        return true
    }

    // MARK: Missionary

    public var hasMissionary: Bool {
        missionary != nil
    }

    public func hasMissionary(_ player: Player?) -> Bool {
        guard let missionary, let player else { return false }
        return player.owns(missionary)
    }

    /// How far a missionary here sees: the settlement's sight with
    /// enhanced missionaries, otherwise 1.
    public var missionaryLineOfSight: Int {
        (specification?.getBoolean(GameOptions.enhancedMissionaries) ?? false) ? lineOfSight : 1
    }

    public var missionaryVisibleTiles: [Tile] {
        tile?.surroundingTiles(0, missionaryLineOfSight) ?? []
    }

    // MARK: Wanted goods

    public func wantedGoods(_ index: Int) -> GoodsType? {
        (0..<IndianSettlement.wantedGoodsCount).contains(index) ? wantedGoods[index] : nil
    }

    public func setWantedGoods(_ wanted: [GoodsType?]) {
        for i in 0..<IndianSettlement.wantedGoodsCount {
            wantedGoods[i] = i < wanted.count ? wanted[i] : nil
        }
    }

    public func setWantedGoods(_ index: Int, _ type: GoodsType?) {
        if (0..<IndianSettlement.wantedGoodsCount).contains(index) { wantedGoods[index] = type }
    }

    public var wantedGoodsCount: Int {
        wantedGoods.compactMap { $0 }.count
    }

    // MARK: Contact

    public func contactLevel(_ player: Player?) -> ContactLevel {
        player?.id.flatMap { contactLevels[$0] } ?? .uncontacted
    }

    private func setContactLevel(_ player: Player, _ level: ContactLevel) {
        guard let id = player.id else { return }
        contactLevels[id] = level
        contactPlayers[id] = WeakPlayer(player)
    }

    @discardableResult
    public func setContacted(_ player: Player) -> Bool {
        guard !hasContacted(player) else { return false }
        setContactLevel(player, .contacted)
        initializeAlarm(player)
        return true
    }

    public func hasVisited(_ player: Player?) -> Bool {
        contactLevel(player).ordinal >= ContactLevel.visited.ordinal
    }

    @discardableResult
    public func setVisited(_ player: Player) -> Bool {
        guard !hasVisited(player) else { return false }
        if !hasContacted(player) { initializeAlarm(player) }
        setContactLevel(player, .visited)
        return true
    }

    public func hasScouted(_ player: Player?) -> Bool {
        contactLevel(player) == .scouted
    }

    @discardableResult
    public func setScouted(_ player: Player) -> Bool {
        guard !hasScouted(player) else { return false }
        if !hasContacted(player) { initializeAlarm(player) }
        setContactLevel(player, .scouted)
        return true
    }

    public var hasAnyScouted: Bool {
        contactLevels.values.contains(.scouted)
    }

    /// Whether a scout would learn anything: once contacted, or once
    /// visited unless speaking to the chief is a separate action.
    public func worthScouting(_ player: Player?) -> Bool {
        switch contactLevel(player) {
        case .contacted: return true
        case .visited: return !(specification?.getBoolean(GameOptions.settlementActionsContactChief) ?? false)
        default: return false
        }
    }

    public override func hasContacted(_ player: Player?) -> Bool {
        guard let player else { return false }
        return player.isIndian || contactLevel(player) != .uncontacted
    }

    /// Whether a unit may make contact here: its owner has met the
    /// settlement's owner, or it is on land, or it brings goods.
    public func allowContact(_ unit: Unit) -> Bool {
        (unit.owner?.hasContacted(owner) ?? false) || !unit.isNaval || unit.hasGoodsCargo
    }

    // MARK: Alarm

    public func alarm(_ player: Player?) -> Tension? {
        player?.id.flatMap { alarms[$0] }
    }

    /// Store a changed alarm, as Java changes its Tension in place,
    /// without working out the most hated player.
    public func storeAlarm(_ player: Player, _ alarm: Tension) {
        if let id = player.id { alarms[id] = alarm }
    }

    /// Whether this is a settlement of the server's game, as Java's
    /// ServerIndianSettlement, and not a copy a player remembers (which
    /// Java reads as a plain IndianSettlement).
    private var isServerSettlement: Bool {
        guard let game, game.isServer, let id else { return false }
        return game.getFreeColGameObject(id) === self
    }

    /// Set the alarm towards a player.  In the server's game, as Java's
    /// ServerIndianSettlement does, not towards the owner, and the most
    /// hated player is worked out again.
    public func setAlarm(_ player: Player, _ newAlarm: Tension) {
        if isServerSettlement {
            guard player !== owner else { return }
            if let id = player.id { alarms[id] = newAlarm }
            updateMostHated()
        } else if let id = player.id {
            alarms[id] = newAlarm
        }
    }

    /// Start the alarm at the owner's tension towards a player.
    public func initializeAlarm(_ player: Player) {
        guard let owner else { return }
        setAlarm(player, Tension(owner.tension(player).value))
    }

    /// Forget the alarm towards a player.
    public func removeAlarm(_ player: Player) {
        if let id = player.id { alarms[id] = nil }
        if isServerSettlement { updateMostHated() }
    }

    /// Work out the most hated player again: the live European the
    /// settlement is most alarmed by, if not happy with it (the first
    /// such, on a tie).  The server does this whenever an alarm is set.
    ///
    /// - Returns: Whether it changed.
    @discardableResult
    public func updateMostHated() -> Bool {
        let old = mostHated
        let hated = game?.liveEuropeanPlayers.filter {
            guard let a = alarm($0) else { return false }
            return a.level != .happy
        } ?? []
        mostHated = hated.max { alarm($0)!.value < alarm($1)!.value }
        return mostHated !== old
    }

    public func setGoodsForSale(_ forSale: [Goods]) {
        goodsForSale = forSale
    }

    // MARK: Trade

    private var fullPrice: Int {
        IndianSettlement.goodsBasePrice + (type?.tradeBonus ?? 0)
    }

    /// What the settlement would pay for goods (at most 100).
    public func priceToBuy(_ type: GoodsType, _ amount: Int) -> Int {
        precondition(amount <= GoodsContainer.cargoSize, "Amount \(amount) > \(GoodsContainer.cargoSize)")
        var price = 0
        if type.isMilitary {
            // Zero if there is a surplus.
            price = militaryGoodsPriceToBuy(type, amount)
        }
        if price == 0 { price = normalGoodsPriceToBuy(type, amount) }
        // The premium for wanted goods, with Java's integer truncation.
        let wantedBonus = type === wantedGoods(0) ? 150
            : type === wantedGoods(1) ? 125
            : type === wantedGoods(2) ? 110
            : 100
        return wantedBonus * price / 100
    }

    private func normalGoodsPriceToBuy(_ type: GoodsType, _ amount: Int) -> Int {
        let tradeGoodsAdd = 20 // Pretend trade goods are present
        let capacity = goodsCapacity
        var current = goodsCount(type)
        if let rawType = type.inputType {
            // Pretend some of the goods can easily be made from raw
            // materials made here, in proportion to the space left.
            let rawProduction = maximumProduction(rawType)
            var fakeProduction = rawProduction < 5 ? 10 * rawProduction
                : rawProduction < 10 ? 5 * rawProduction + 25
                : rawProduction < 20 ? 2 * rawProduction + 55
                : 100
            fakeProduction /= 2
            current += fakeProduction * max(0, capacity - current) / capacity
        } else if type.isTradeGoods {
            current += tradeGoodsAdd
        }
        // Only the goods that keep the stock under what is wanted count.
        let retain = min(wantedGoodsAmount(type), capacity)
        let valued = retain <= current ? 0 : min(amount, retain - current)
        // The price falls as the stock rises.
        var unitPrice = fullPrice * max(0, capacity - current) / capacity
        // Farmed goods are less interesting, and small settlements do
        // not build.
        if type.isFarmed || type.isRawBuildingMaterial { unitPrice /= 2 }
        return unitPrice < 0 ? 0 : valued * unitPrice
    }

    /// How much of a goods type the settlement wants to keep.
    public func wantedGoodsAmount(_ type: GoodsType) -> Int {
        guard unitCount > 0, let spec = specification, let unitType = firstUnit?.type else { return 0 }
        if type.isMilitary {
            // Enough to arm everyone.
            let militaryRoles = spec.militaryRolesList.filter { $0.isAvailableTo([owner, unitType]) }
            guard let first = militaryRoles.first else { return 0 }
            return ownedUnitList.filter { u in !militaryRoles.contains { $0 === u.role } }
                .reduce(0) { $0 + AbstractGoods.count(of: type, in: $1.goodsDifference(first, 1)) }
        }
        let consumption = self.consumption(of: type)
        if type === spec.primaryFoodType {
            // Food spoils, so not too much.
            return max(40, consumption * 3)
        }
        if type.isTradeGoods || type.isNewWorldLuxuryType || type.isRefined {
            // Ten years' supply, as more may not come.
            return max(80, consumption * 20)
        }
        return 2 * unitCount
    }

    private func militaryGoodsPriceToBuy(_ type: GoodsType, _ amount: Int) -> Int {
        let required = wantedGoodsAmount(type)
        if required == 0 { return 0 } // No military price
        // Top price for all if more than half is needed, otherwise for
        // what is needed and the normal price for the rest.
        let valued = max(0, required - goodsCount(type))
        return valued > amount / 2 ? fullPrice * amount
            : valued * fullPrice + normalGoodsPriceToBuy(type, amount - valued)
    }

    /// What the settlement asks for goods (at most 100).
    public func priceToSell(_ type: GoodsType, _ amount: Int) -> Int {
        precondition(amount <= GoodsContainer.cargoSize, "Amount \(amount) > \(GoodsContainer.cargoSize)")
        // The purchase price plus a margin: military goods at double,
        // trade goods at half again, and more for goods it can not make.
        var price = amount + max(0, 11 * priceToBuy(type, amount) / 10)
        if type.isMilitary {
            price = max(price, amount * fullPrice * 2)
        } else if type.isTradeGoods {
            price = max(price, 150 * amount * fullPrice / 100)
        } else if let raw = type.inputType, maximumProduction(raw) == 0 {
            price += amount
        }
        return price
    }

    public func willSell(_ type: GoodsType) -> Bool {
        !type.isTradeGoods
    }

    /// The goods the settlement would sell to a unit: new world goods
    /// first, then dearest, then most.
    public func sellGoods(_ unit: Unit?) -> [Goods] {
        guard let game else { return [] }
        var result: [Goods] = []
        for g in compactGoodsList {
            guard let type = g.type, willSell(type) else { continue }
            var amount = g.amount
            let retain = wantedGoodsAmount(type)
            if retain >= amount { continue }
            amount -= retain
            if let unit {
                amount = Int(JavaMath.round(FeatureContainer.applyModifiers(
                    Float(amount), turn: game.turn, unit.modifiers(Modifier.tradeVolumePenalty))))
            }
            if amount < IndianSettlement.tradeMinimumSize { continue }
            amount = min(amount, GoodsContainer.cargoSize)
            result.append(Goods(game: game, location: self, type: type, amount: amount))
        }
        return result.stableSorted { a, b in
            let na = a.type!.isNewWorldGoodsType ? 0 : 1, nb = b.type!.isNewWorldGoodsType ? 0 : 1
            if na != nb { return na < nb }
            let pa = priceToSell(a.type!, a.amount), pb = priceToSell(b.type!, b.amount)
            if pa != pb { return pa > pb }
            return AbstractGoods.compareDescendingAmount(a, b) < 0
        }
    }

    /// Give half of any large stock of military goods to another
    /// settlement.
    public func tradeGoods(with other: IndianSettlement) {
        for gt in (specification?.goodsTypeList ?? []) where gt.isMilitary {
            let inStock = goodsCount(gt)
            if inStock <= 50 { continue }
            let traded = inStock / 2
            other.addGoods(gt, traded)
            removeGoods(gt, traded)
        }
    }

    /// What the settlement's land could produce of goods unattended.
    public func maximumProduction(_ goodsType: GoodsType) -> Int {
        guard let tile else { return 0 }
        return tile.surroundingTiles(0, radius)
            .filter { $0.owningSettlement == nil || $0.owningSettlement === self }
            .reduce(0) { $0 + $1.potentialProduction(goodsType, nil) }
    }

    /// Choose the wanted goods: the storable goods it would pay most for,
    /// if it would pay enough.
    /// Share military goods with another settlement: half of each
    /// stock over 50.
    public func tradeGoodsWithSettlement(_ settlement: IndianSettlement) {
        for gt in specification?.goodsTypeList ?? [] where gt.isMilitary {
            let goodsInStock = goodsCount(gt)
            if goodsInStock <= 50 { continue } // Java's magic number
            let goodsTraded = goodsInStock / 2
            settlement.addGoods(gt, goodsTraded)
            removeGoods(gt, goodsTraded)
        }
    }

    public func updateWantedGoods() {
        guard let spec = specification else { return }
        var prices = JavaHashMap<GoodsType, Int>(javaHash: { $0.javaHashCode })
        for gt in spec.goodsTypeList where !gt.isMilitary && gt.isStorable {
            prices.put(gt, normalGoodsPriceToBuy(gt, GoodsContainer.cargoSize))
        }
        var wantedIndex = 0
        for (gt, price) in prices.entries.stableSorted(by: { $0.value > $1.value }) {
            if wantedIndex >= IndianSettlement.wantedGoodsCount { break }
            if price <= GoodsContainer.cargoSize * IndianSettlement.tradeMinimumPrice { break }
            setWantedGoods(wantedIndex, gt)
            wantedIndex += 1
        }
        while wantedIndex < IndianSettlement.wantedGoodsCount {
            setWantedGoods(wantedIndex, nil)
            wantedIndex += 1
        }
    }

    /// The raw material it has spare whose product it most needs.
    private var goodsToMake: GoodsType? {
        guard let spec = specification else { return nil }
        func deficit(_ gt: GoodsType) -> Int { wantedGoodsAmount(gt) - goodsCount(gt) }
        var best: GoodsType?
        for gt in spec.goodsTypeList {
            guard gt.isRawMaterial, let out = gt.outputType, !out.isBreedable, out.isStorable,
                  deficit(gt) < 0, deficit(out) > 0 else { continue }
            if best == nil || deficit(gt) > deficit(best!) { best = gt }
        }
        return best
    }

    /// A random gift of new world goods it has plenty of, or nil.
    public func randomGift(_ random: JavaRandom) -> Goods? {
        guard let spec = specification, let game else { return nil }
        let candidates = spec.newWorldGoodsTypeList
            .filter { goodsCount($0) >= IndianSettlement.giftThreshold + IndianSettlement.keepRawMaterial }
            .map { gt in
                Goods(game: game, location: self, type: gt, amount: min(
                    Int(RandomUtils.randomInt("Gift amount", random,
                        Int32(goodsCount(gt) - IndianSettlement.keepRawMaterial - IndianSettlement.giftMinimum)))
                        + IndianSettlement.giftMinimum,
                    IndianSettlement.giftMaximum))
            }
        return RandomUtils.randomMember("Gift type", candidates, random)
    }

    public var requiredDefenders: Int {
        (type?.minimumSize ?? 1) - 1
    }

    // MARK: Location

    /// Homeless natives who join adopt the settlement.
    @discardableResult
    public override func add(_ locatable: any Locatable) -> Bool {
        let result = super.add(locatable)
        if result, let unit = locatable as? Unit, unit.homeIndianSettlement == nil {
            unit.changeHomeIndianSettlement(self)
        }
        return result
    }

    // MARK: GoodsLocation

    public override func invalidateCache() {}

    public override var goodsCapacity: Int {
        type?.warehouseCapacity ?? 0
    }

    // MARK: Settlement

    public var defenceRatio: Double {
        Double(unitCount) * 2 / Double((type?.minimumSize ?? 0) + (type?.maximumSize ?? 0))
    }

    public var isBadlyDefended: Bool {
        unitCount < requiredDefenders
    }

    /// Native settlements make no rebels.
    public override var sonsOfLiberty: Int { 0 }

    /// Native settlements need no upkeep.
    public override var upkeep: Int { 0 }

    /// The production of goods: a third of the units make the refined
    /// goods it most needs, and its tiles make the rest, at reduced
    /// efficiency when it has more tiles than units.
    public override func totalProduction(of type: GoodsType) -> Int {
        if type.isRefined {
            return type === goodsToMake ? unitCount : 0
        }
        var tiles = 0, potential = 0
        for wt in ownedTiles where wt !== tile && !wt.isOccupied {
            potential += wt.potentialProduction(type, nil)
            tiles += 1
        }
        if tiles > unitCount {
            potential = Int(JavaMath.toInt(Double(potential) * Double(unitCount) / Double(tiles)))
        }
        if !type.isFoodType {
            potential = Int(JavaMath.round(Double(potential) * IndianSettlement.nativeProductionEfficiency))
        }
        // Always the full potential of the center tile.
        return potential + (tile?.potentialProduction(type, nil) ?? 0)
    }

    /// How the AI values attacking this settlement: the angrier, the
    /// better.
    public func calculateSettlementValue(_ value: Int, _ unit: Unit) -> Int {
        value + (alarm(unit.owner)?.value ?? 0) / 2
    }

    // MARK: Trade routes

    public func availableGoodsCount(_ goodsType: GoodsType) -> Int {
        goodsCount(goodsType)
    }

    public func exportAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        let present = max(0, goodsCount(goodsType) + turns * totalProduction(of: goodsType))
        return present - wantedGoodsAmount(goodsType)
    }

    public func importAmount(_ goodsType: GoodsType, _ turns: Int) -> Int {
        if goodsType.limitIgnored { return Int(Int32.max) }
        let present = max(0, goodsCount(goodsType) - turns * totalProduction(of: goodsType))
        return warehouseCapacity - present
    }

    // MARK: Reading XML

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let spec = specification
        lastTribute = xr.attribute("lastTribute", default: 0)
        convertProgress = xr.attribute("convertProgress", default: 0)
        learnableSkill = try spec.flatMap { try xr.getType($0, "learnableSkill", UnitType.self) }
        mostHated = try xr.findFreeColGameObject(game!, "mostHated", Player.self, required: false)
        for i in 0..<IndianSettlement.wantedGoodsCount {
            setWantedGoods(i, try spec.flatMap { try xr.getType($0, "wantedGoods\(i)", GoodsType.self) })
        }
    }

    // MARK: Writing XML

    /// The skill and wanted goods are written for the owner, or a
    /// player who has scouted or visited.
    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        let cl = contactLevel(xw.clientPlayerObject)
        let full = xw.validFor(owner)
        xw.writeAttribute("name", id: name)
        if full {
            xw.writeAttribute("lastTribute", lastTribute)
            xw.writeAttribute("convertProgress", convertProgress)
        }
        if full || cl == .scouted || cl == .visited {
            xw.writeAttribute("learnableSkill", learnableSkill)
            for (i, gt) in wantedGoods.enumerated() {
                xw.writeAttribute("wantedGoods\(i)", gt)
            }
            xw.writeAttribute("mostHated", mostHated)
        }
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        if let missionary {
            xw.writeStartElement("missionary")
            missionary.toXML(xw)
            xw.writeEndElement()
        }
        let byId = { (a: String, b: String) in FreeColObject.compareIdentifiers(a, b) < 0 }
        if xw.validFor(owner) {
            for id in contactLevels.keys.sorted(by: byId) {
                xw.writeStartElement("contactLevel")
                xw.writeAttribute("level", contactLevels[id]!)
                xw.writeAttribute("player", id)
                xw.writeEndElement()
            }
            for id in alarms.keys.sorted(by: byId) {
                xw.writeStartElement("alarm")
                xw.writeAttribute("player", id)
                xw.writeAttribute("value", alarms[id]!.value)
                xw.writeEndElement()
            }
            for unit in sortedById(ownedUnits) { xw.writeIdElement("ownedUnits", unit.id) }
        } else if let client = xw.clientPlayerObject {
            xw.writeStartElement("contactLevel")
            xw.writeAttribute("level", contactLevel(client))
            xw.writeAttribute("player", client)
            xw.writeEndElement()
            if let alarm = alarm(client) {
                xw.writeStartElement("alarm")
                xw.writeAttribute("player", client)
                xw.writeAttribute("value", alarm.value)
                xw.writeEndElement()
            }
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        contactLevels = [:]
        contactPlayers = [:]
        alarms = [:]
        missionary = nil
        ownedUnits = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        let game = game!
        switch xr.localName {
        case "alarm":
            if let player = try xr.findFreeColGameObject(game, "player", Player.self, required: true) {
                setAlarm(player, Tension(xr.attribute("value", default: 0)))
            }
            try xr.closeTag("alarm")
        case "contactLevel":
            let cl = xr.attribute("level", ContactLevel.self, default: .uncontacted) ?? .uncontacted
            if let player = try xr.findFreeColGameObject(game, "player", Player.self, required: true) {
                setContactLevel(player, cl)
            }
            try xr.closeTag("contactLevel")
        case "missionary":
            try xr.nextTag()
            missionary = try xr.readFreeColObject(game, Unit.self)
            missionary?.setLocationNoUpdate(self)
            try xr.closeTag("missionary")
        case "ownedUnits":
            if let unit = try xr.makeFreeColObject(game, FreeColObject.idTag, Unit.self, required: true) {
                addOwnedUnit(unit)
            }
            try xr.closeTag("ownedUnits")
        default:
            try super.readChild(xr)
        }
    }

    public override var description: String {
        (name ?? "NONAME") + (tile.map { " at (\($0.x),\($0.y))" } ?? "")
    }
}

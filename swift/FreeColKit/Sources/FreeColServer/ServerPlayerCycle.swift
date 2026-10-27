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

/// Tiles in the order a Java HashSet of them iterates.
struct JavaTileSet {
    private var map: JavaHashMap<Tile, Bool>

    /// Like `new HashSet<>()`.
    init() {
        map = JavaHashMap(javaHash: { $0.javaGameObjectHash })
    }

    /// Like `new HashSet<>(capacity)`.
    init(capacity: Int) {
        map = JavaHashMap(initialCapacity: capacity, javaHash: { $0.javaGameObjectHash })
    }

    init<S: Sequence>(_ tiles: S) where S.Element == Tile {
        self.init()
        for t in tiles { insert(t) }
    }

    /// Like `new HashSet<>(collection)`, which presizes the table.
    init(copying tiles: [Tile]) {
        self.init(capacity: max(Int(Float(tiles.count) / 0.75) + 1, 16))
        for t in tiles { insert(t) }
    }

    mutating func insert(contentsOf tiles: [Tile]) {
        for t in tiles { insert(t) }
    }

    mutating func remove(_ tile: Tile) {
        _ = map.removeValue(forKey: tile)
    }

    @discardableResult
    mutating func insert(_ tile: Tile) -> Bool {
        map.put(tile, true) == nil
    }

    func contains(_ tile: Tile) -> Bool {
        map[tile] != nil
    }

    /// Like clear(), which keeps the table.
    mutating func removeAll() {
        map.removeAll()
    }

    var tiles: [Tile] {
        map.keys
    }

    var isEmpty: Bool {
        map.isEmpty
    }
}

/// The turn cycle's part of the server's player (ServerPlayer): death
/// and withdrawal, the start and end of a turn, founding fathers,
/// stances and tension, the market, taxes and mercenaries.
extension Player {

    // MARK: Score

    static let scoreGold = 0.001
    static let scoreFoundingFather = 5
    static let scoreIndependenceBonusFirst = 100
    static let scoreIndependenceBonusSecond = 50
    static let scoreIndependenceBonusThird = 25

    /// Work out the score again: units, liberty, fathers, gold and
    /// history, with a bonus for independence by how many others won
    /// it first (updateScore).
    ///
    /// - Returns: Whether it changed.
    func updateScore() -> Bool {
        let oldScore = score
        score = units.reduce(0) { $0 + $1.scoreValue }
            + colonyList.reduce(0) { $0 + $1.liberty }
            + Player.scoreFoundingFather * foundingFathers.count
        if gold != Player.goldNotAccounted {
            score += Int(JavaMath.toInt((Player.scoreGold * Double(gold)).rounded(.down)))
        }
        var bonus = 0
        for h in history where h.playerId == id {
            if h.eventType == .independence {
                switch h.score {
                case 0: bonus = Player.scoreIndependenceBonusFirst
                case 1: bonus = Player.scoreIndependenceBonusSecond
                case 2: bonus = Player.scoreIndependenceBonusThird
                default: bonus = 0
                }
            } else {
                score += h.score
            }
        }
        score += (score * bonus) / 100
        return score != oldScore
    }

    // MARK: Death

    /// Whether a player is alive, dead, beaten or needs a free colonist
    /// (ServerPlayer.DeadCheck).
    public enum DeadCheck {
        case isDead, isDefeated, isAutorecruit, isAlive
    }

    /// Whether this player has died (checkForDeath): natives without
    /// units, rebels without a port, a beaten REF, or a colonial player
    /// with no presence in the New World after the mandatory year or no
    /// means of getting one.  Before that year a player with a ship and
    /// no money is given a colonist.
    public func checkForDeath() -> DeadCheck {
        if isUnknownEnemy { return .isAlive }
        guard let spec = specification, let game else { return .isAlive }
        switch playerType {
        case .native, .undead:
            return unitCount == 0 ? .isDead : .isAlive
        case .colonial:
            break
        case .rebel, .independent:
            return numberOfPorts > 0 ? .isAlive : .isDead
        case .royal:
            return checkForREFDefeat() ? .isDefeated : .isAlive
        default:
            preconditionFailure("Bogus player type: \(self)")
        }

        if !colonyList.isEmpty { return .isAlive }

        // Look for carriers, colonists, and units on the map.
        var hasCarrier = false, hasColonist = false, hasEmbarked = false, hasGoods = false
        for unit in units {
            if unit.isCarrier {
                if unit.hasGoodsCargo { hasGoods = true }
                hasCarrier = true
                continue
            }
            // Must be able to found a colony or capture units.
            if !unit.isColonist && !unit.isOffensiveUnit { continue }
            hasColonist = true
            if let carrier = unit.carrier {
                if carrier.hasTile { return .isAlive }
                hasEmbarked = true
            }
            if unit.hasTile && !unit.isInMission { return .isAlive }
        }

        // After the mandatory year there must be a New World presence.
        let mandatory = spec.getInteger(GameOptions.mandatoryColonyYear) ?? 0
        if spec.turnCalendar.year(of: game.turn) >= mandatory { return .isDead }
        if hasEmbarked || hasGoods { return .isAlive }

        // A carrier is needed, and a colonist.  The sums are Java ints,
        // which wrap.
        let maxPrice = Int32.max
        func price(_ ut: UnitType) -> Int32 {
            guard let europe else { return maxPrice }
            let p = europe.unitPrice(ut)
            return p == Constants.undefined ? maxPrice : Int32(truncatingIfNeeded: p)
        }
        func minPrice(_ ability: String) -> Int32 {
            spec.unitTypeList.filter { $0.hasAbility(ability) }.map(price).min() ?? maxPrice
        }
        var goldNeeded: Int32 = 0
        if !hasCarrier {
            let p = europe == nil ? maxPrice : minPrice(Ability.navalUnit)
            if p == maxPrice || !checkGold(Int(p)) { return .isDead }
            goldNeeded &+= p
        }
        if hasColonist { return .isAlive }
        guard let europe else { return .isDead }
        goldNeeded &+= min(Int32(truncatingIfNeeded: europe.currentRecruitPrice), minPrice(Ability.foundColony))
        if checkGold(Int(goldNeeded)) { return .isAlive }
        return .isAutorecruit
    }

    /// Whether a REF has been beaten and should surrender: no
    /// settlements, a land army that seems no stronger than a rebel's,
    /// and too few land or naval units left (checkForREFDefeat).
    private func checkForREFDefeat() -> Bool {
        if !isREF { return false }
        let rebels = self.rebels
        if rebels.isEmpty || hasSettlements { return false }
        var naval = 0, land = 0
        for u in units {
            if u.isNaval { naval += 1 } else { land += 1 }
        }
        // The REF overestimates its strength.
        let refLandPower = 1.5 * Double(calculateStrength(naval: false))
        for r in rebels where Double(r.calculateStrength(naval: false)) < refLandPower { return false }
        return land < 7 || naval < 2
    }

    /// Kill off this player and clear away what is left: its missions,
    /// the stances and tension of others towards it, its settlements,
    /// land and units, and what it had in Europe (csKill).
    private func csKill(_ cs: ChangeSet) throws {
        guard let game else { return }
        isDead = true
        cs.addPartial(.all(), self, ("dead", "true"))
        cs.add(.all(), message: SetDeadMessage(self))

        // Missions, alarm, tension and stances.
        for other in game.livePlayers(excluding: self) {
            if isEuropean && other.isIndian {
                for settlement in other.indianSettlementList {
                    if settlement.hasMissionary(self) { try settlement.csKillMissionary(nil, cs) }
                    try settlement.tile?.cacheUnseen()
                    settlement.removeAlarm(self)
                    settlement.updateMostHated()
                }
                other.removeTension(self)
            }
            other.setStance(self, nil)
        }

        // Every other unit disappears from view.
        var tiles = JavaTileSet(capacity: 64)
        for case let u as Unit in game.freeColGameObjectsInJavaOrder {
            guard u.hasTile, !owns(u), let t = u.tile else { continue }
            cs.addRemove(.only(self), t, u)
            tiles.insert(t)
        }
        cs.add(.only(self), tiles.tiles)

        // The settlements, and then the rest of the land.
        var settlements = self.settlements
        while !settlements.isEmpty { try csDisposeSettlement(settlements.removeFirst(), cs) }
        tiles.removeAll()
        for t in game.map?.tiles ?? [] where t.owner === self { tiles.insert(t) }
        for t in tiles.tiles {
            try t.cacheUnseen()
            t.changeOwnership(nil, nil)
        }

        // The units.
        for u in units {
            if let t = u.tile { tiles.insert(t) }
            try u.csRemove(.perhaps().always(self), u.location, cs)
        }
        cs.add(.perhaps().always(self), tiles.tiles)

        removeEuropeanAssets()
        invalidateCanSeeTiles()
    }

    /// Withdraw from the New World, with a message and history saying
    /// why, or the standard ones for a death (csWithdraw).
    public func csWithdraw(_ cs: ChangeSet, _ message: ModelMessage? = nil,
                           _ event: HistoryEvent? = nil) throws {
        guard let game else { return }
        let mm = message ?? ModelMessage(.foreignDiplomacy, isEuropean ? "model.player.dead.european"
                                             : "model.player.dead.native", self)
            .addStringTemplate("%nation%", nationLabel)
        let he = event ?? HistoryEvent(game.turn, .nationDestroyed, nil)
            .addStringTemplate("%nation%", nationLabel)
        cs.addGlobalMessage(game, nil, mm)
        cs.addGlobalHistory(game, he)
        try csKill(cs)
    }

    // MARK: End and start of a turn

    /// The buildings the player's founding fathers give each colony
    /// (getFreeBuildingTypes).
    public var freeBuildingTypes: [BuildingType] {
        guard let spec = specification else { return [] }
        return foundingFathers.flatMap(\.events).filter { $0.id == "model.event.freeBuilding" }
            .compactMap { spec.getBuildingType($0.value) }
    }

    /// Just before the turn ends: free buildings for the colonies that
    /// can have them (csEndTurn).
    public func csEndTurn(_ cs: ChangeSet) throws {
        for bt in freeBuildingTypes {
            for c in colonyList { try c.csFreeBuilding(bt, cs) }
        }
    }

    /// The start of the player's turn (csStartTurn).  Europeans' forts
    /// bombard, the market moves, a founding father may join, others
    /// are offered and the score is updated.  Natives grow alarmed at
    /// what is near their settlements, calm down a little as a nation,
    /// hear of changes, and their missionaries may convert.
    public func csStartTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game else { return }
        if isEuropean {
            try csBombardEnemyShips(random, cs)
            csYearlyGoodsAdjust(random, cs)
            if let father = checkFoundingFather() {
                try csAddFoundingFather(father, random, cs)
                clearOfferedFathers()
            }
            var ffs = offeredFathers
            if canRecruitFoundingFather && ffs.isEmpty {
                ffs = randomFoundingFathers(random)
                setOfferedFathers(ffs)
            }
            if !ffs.isEmpty {
                cs.add(.only(self), message: ChooseFoundingFatherMessage(ffs, nil))
            }
            if updateScore() {
                cs.addPartial(.only(self), self, ("score", String(score)))
            }
        } else if isIndian {
            guard let spec = specification else { return }
            let all = indianSettlementList
            // The old alarm levels, to see which changed.
            var oldLevels: [JavaHashMap<Player, Box<Tension.Level?>>] = []
            for settlement in all {
                var old = JavaHashMap<Player, Box<Tension.Level?>>(javaHash: { $0.javaGameObjectHash })
                for enemy in game.liveEuropeanPlayers(excluding: self) {
                    _ = old.put(enemy, Box(settlement.alarm(enemy)?.level))
                }
                oldLevels.append(old)
            }

            // The settlements' alarm first.
            for settlement in all {
                let enemies = game.liveEuropeanPlayers(excluding: self)
                var extra = JavaHashMap<Player, Int>(initialCapacity: enemies.count,
                                                     javaHash: { $0.javaGameObjectHash })
                for enemy in enemies { _ = extra.put(enemy, 0) }
                // What is going on round the settlement.
                guard let center = settlement.tile else { continue }
                for tile in center.surroundingTiles(settlement.radius + Player.alarmRadius) {
                    if let first = tile.firstUnit {
                        guard let enemy = first.owner, enemy.isEuropean, let alarm = extra[enemy] else { continue }
                        let offence = tile.unitList.filter { $0.isOffensiveUnit && !$0.isNaval }
                            .reduce(0.0) { $0 + Double($1.type?.offence ?? 0) }
                        _ = extra.put(enemy, alarm + Int(JavaMath.toInt(offence)))
                    } else if let colony = tile.colony, let enemy = colony.owner {
                        _ = extra.put(enemy, extra[enemy]! + Player.alarmTileInUse + colony.unitCount)
                    } else if let enemy = tile.owningSettlement?.owner, enemy.isEuropean {
                        _ = extra.put(enemy, extra[enemy]! + Player.alarmTileInUse)
                    }
                }
                // A missionary calms the settlement a little.
                if let missionary = settlement.missionary, let enemy = missionary.owner {
                    var missionAlarm = spec.getInteger(GameOptions.missionInfluence) ?? 0
                    if missionary.hasAbility(Ability.expertMissionary) { missionAlarm *= 2 }
                    _ = extra.put(enemy, extra[enemy]! + missionAlarm)
                }
                for e in extra.entries where e.value != 0 {
                    let change = Int(JavaMath.toInt(e.key.apply(Float(e.value), turn: game.turn,
                                                                Modifier.nativeAlarmModifier)))
                    try settlement.csModifyAlarm(e.key, change, true, cs)
                }
            }

            // The nation calms down a little.
            for enemy in game.liveEuropeanPlayers(excluding: self) where tension(enemy).value > 0 {
                let change = -tension(enemy).value / 100 - 4
                try csModifyTension(enemy, change, nil, cs)
            }

            // Tell of the settlements whose alarm changed.
            for (i, settlement) in all.enumerated() {
                for e in oldLevels[i].entries { try settlement.csCheckTension(e.key, e.value.value, cs) }
            }

            for settlement in all { try settlement.csStartTurn(random, cs) }
        }
    }

    static let alarmRadius = 2
    static let alarmTileInUse = 2

    /// The colonies' forts fire at enemy ships beside them: ships of
    /// players at war, and pirates (csBombardEnemyShips).
    private func csBombardEnemyShips(_ random: JavaRandom, _ cs: ChangeSet) throws {
        for colony in colonyList where colony.canBombardEnemyShip {
            guard let tile = colony.tile else { continue }
            let targets = tile.surroundingTiles(1, 1).flatMap(\.unitList).filter { u in
                u.owner !== self && u.isNaval && !(u.tile?.isLand ?? true)
                    && (atWar(with: u.owner) || u.hasAbility(Ability.piracy))
            }
            for u in targets { try csCombat(colony, u, nil, random, cs) }
        }
    }

    // MARK: The market

    /// The market's yearly drift: each traded type of goods moves a
    /// random amount towards its initial amount, one more than the
    /// others, and the other markets follow (csYearlyGoodsAdjust).
    public func csYearlyGoodsAdjust(_ random: JavaRandom, _ cs: ChangeSet) {
        guard let game, let spec = specification, let market else { return }
        let goodsTypes = spec.storableGoodsTypeList
        var extraType: GoodsType?
        repeat {
            extraType = RandomUtils.randomMember("Choose goods type", goodsTypes, random)
        } while !(extraType?.isStorable ?? true)
        for type in goodsTypes where market.hasBeenTraded(type) {
            let add = market.amountInMarket(type) < type.initialAmount
            var amount = game.turn.number / 10
            if type === extraType { amount = 2 * amount + 1 }
            if amount <= 0 { continue }
            amount = Int(RandomUtils.randomInt("Market adjust \(type.id ?? "null")", random, Int32(amount)))
            if !add { amount = -amount }
            market.addGoodsToMarket(type, amount)
            extraTrades.append(AbstractGoods(type, amount))
        }
        flushExtraTrades(random)
        csFlushMarket(cs)
    }

    /// Pass the trades waiting on to the other markets (flushExtraTrades).
    public func flushExtraTrades(_ random: JavaRandom?) {
        while !extraTrades.isEmpty {
            let ag = extraTrades.removeFirst()
            if let type = ag.type { propagateToEuropeanMarkets(type, ag.amount, random) }
        }
    }

    /// Tell the player of the prices that have changed (csFlushMarket).
    ///
    /// - Returns: Whether any had.
    @discardableResult
    public func csFlushMarket(_ cs: ChangeSet) -> Bool {
        guard let spec = specification, market != nil else { return false }
        var ret = false
        for type in spec.goodsTypeList where csFlushMarket(type, cs) { ret = true }
        return ret
    }

    @discardableResult
    public func csFlushMarket(_ type: GoodsType, _ cs: ChangeSet) -> Bool {
        guard let market, market.hasPriceChanged(type) else { return false }
        if let mm = market.priceChangeMessage(type) { cs.addMessage(self, mm) }
        market.flushPriceChange(type)
        cs.add(.only(self), market.marketData(type))
        return true
    }

    // MARK: Founding fathers

    /// The father being recruited, if the liberty for it is in, with the
    /// liberty left over kept if the rules say (checkFoundingFather).
    private func checkFoundingFather() -> FoundingFather? {
        guard let father = currentFather else { return nil }
        let extraLiberty = remainingFoundingFatherCost
        if extraLiberty > 0 { return nil }
        let overflow = specification?.getBoolean(GameOptions.saveProductionOverflow) ?? false
        liberty = overflow ? -extraLiberty : 0
        currentFather = nil
        return father
    }

    /// Whether to start recruiting a father (canRecruitFoundingFather).
    public var canRecruitFoundingFather: Bool {
        guard let spec = specification else { return false }
        switch playerType {
        case .colonial:
            break
        case .rebel, .independent:
            if !spec.getBoolean(GameOptions.continueFoundingFatherRecruitment) { return false }
        default:
            return false
        }
        return currentFather == nil && hasSettlements && fatherCount < spec.foundingFathers.count
            && canHaveFoundingFathers
    }

    /// A father of each type to choose from, at random by the weights
    /// for the age (getRandomFoundingFathers).
    private func randomFoundingFathers(_ random: JavaRandom) -> [FoundingFather] {
        guard let game, let spec = specification else { return [] }
        let age = spec.age(game.turn)
        var choices: [FoundingFather.FoundingFatherType: [RandomChoice<FoundingFather>]] = [:]
        for father in spec.foundingFathers where !hasFather(father) && father.isAvailableTo(self) {
            guard let type = father.type else { continue }
            choices[type, default: []].append(RandomChoice(father, father.weight(age)))
        }
        return FoundingFather.FoundingFatherType.allCases.compactMap { type in
            choices[type].flatMap { RandomChoice.weightedRandom("Choose founding father", $0, random) }
        }
    }

    /// A founding father joins the congress, with whatever its arrival
    /// brings: units, unit changes, special modifiers and events
    /// (csAddFoundingFather).
    public func csAddFoundingFather(_ father: FoundingFather, _ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game, let spec = specification else { return }
        let europe = self.europe
        let turn = game.turn
        var europeDirty = false, visibilityChange = false

        addFather(father)
        addHistory(HistoryEvent(turn, .foundingFather, self).addNamed("%father%", father))
        // The whole player, as only that gets the features to the client.
        cs.add(.only(self), self)
        cs.addMessage(self, ModelMessage(.sonsOfLiberty, "model.player.foundingFatherJoinedCongress", self)
            .addNamed("%foundingFather%", father)
            .add("%description%", father.descriptionKey))

        let fatherUnits = father.units
        if let europe, !fatherUnits.isEmpty {
            createUnits(fatherUnits, europe, random)
            europeDirty = true
        }

        if let uct = spec.getUnitChangeType(UnitChangeType.foundingFather), uct.appliesTo(self) {
            for u in units {
                guard let type = u.type else { continue }
                for uc in uct.unitChanges(type) where uc.appliesTo(u) {
                    if let to = uc.to { _ = u.changeType(to) }
                    visibilityChange = true
                    cs.add(.perhaps(), u)
                    break
                }
            }
        }

        // Some modifiers are special.
        for m in father.allModifiers {
            if m.id == Modifier.lineOfSightBonus {
                // Newly visible tiles are explored, and always updated so
                // the units on them show.  The tiles seen must not have
                // been worked out again yet.
                let tiles = collectNewTiles(javaVisibleTileSet)
                cs.add(.only(self), tiles)
                visibilityChange = !tiles.isEmpty
            } else if m.id == Modifier.sol {
                for c in colonyList {
                    c.addLiberty(0) // Kick the rebels and production bonus.
                    c.invalidateCache()
                }
            }
        }

        // Some events are special.
        for event in father.events {
            switch event.id {
            case "model.event.resetBannedMissions":
                for p in game.liveNativePlayers(excluding: nil) where p.missionsBanned(self) {
                    p.removeMissionBan(self)
                    cs.add(.only(self), p)
                }
            case "model.event.resetNativeAlarm":
                for p in game.liveNativePlayers(excluding: nil) where p.hasContacted(self) {
                    p.setTension(self, Tension(Tension.tensionMin))
                    for settlement in p.indianSettlementList where settlement.hasContacted(self) {
                        try settlement.tile?.cacheUnseen()
                        settlement.setAlarm(self, Tension(Tension.tensionMin))
                        settlement.updateMostHated()
                        cs.add(.only(self), settlement)
                    }
                    try csChangeStance(.peace, p, true, cs)
                }
            case "model.event.boycottsLifted":
                guard let market else { break }
                for goodsType in spec.goodsTypeList where market.arrears(goodsType) > 0 {
                    market.setArrears(goodsType, 0)
                    cs.add(.only(self), market.marketData(goodsType))
                }
            case "model.event.freeBuilding":
                if let type = spec.getBuildingType(event.value) {
                    for c in colonyList { try c.csFreeBuilding(type, cs) }
                }
            case "model.event.seeAllColonies":
                visibilityChange = true // Other colonies can now be seen.
                for colony in game.allColonies {
                    guard let t = colony.tile else { continue }
                    var tiles = JavaTileSet()
                    if exploreTile(t) {
                        if !hasAbility(Ability.seeAllColonies) {
                            // Col1 showed colonies as size 1; the FreeCol
                            // rules add the ability to see them in full.
                            let c = try t.copy(in: game)
                            c.colony?.displayUnitCount = 1
                            t.setCachedTile(self, c)
                        }
                        tiles.insert(t)
                    }
                    // The tiles round about are revealed too.
                    let fullRadius = Int(JavaMath.toInt(father.apply(Float(colony.lineOfSight), turn: turn,
                                                                     Modifier.exposedTilesRadius)))
                    for e in exploreTiles(t.surroundingTiles(1, fullRadius)) { tiles.insert(e) }
                    cs.add(.only(self), tiles.tiles)
                }
            case "model.event.newRecruits":
                if let europe { europeDirty = europe.replaceRecruits(random) }
            case "model.event.movementChange":
                for u in units where u.movesLeft > 0 {
                    u.movesLeft = u.initialMovesLeft
                    cs.addPartial(.only(self), u, ("movesLeft", String(u.movesLeft)))
                }
            default:
                break
            }
        }

        if europeDirty { cs.add(.only(self), europe) }
        if visibilityChange { invalidateCanSeeTiles() }
    }

    // MARK: Exploring

    /// Explore a tile, if not explored already (exploreTile).
    ///
    /// - Returns: Whether it is newly explored.
    @discardableResult
    public func exploreTile(_ tile: Tile) -> Bool {
        let ret = !hasExplored(tile)
        if ret { tile.setExplored(self, true) }
        return ret
    }

    /// Explore tiles, giving those newly explored, in a Java HashSet's
    /// order (exploreTiles).
    @discardableResult
    public func exploreTiles<S: Sequence>(_ tiles: S) -> [Tile] where S.Element == Tile {
        JavaTileSet(tiles.filter { exploreTile($0) }).tiles
    }

    /// Explore what a unit can see (exploreForUnit).
    @discardableResult
    public func exploreForUnit(_ unit: Unit?) -> [Tile] {
        guard let unit, unit.isOnTile, game?.map != nil else { return [] }
        return exploreTiles(unit.javaVisibleTileSet)
    }

    /// The tiles the player can see, in the order of Java's HashSet of
    /// them (getVisibleTileSet), which matters where they are
    /// collected into another.
    var javaVisibleTileSet: [Tile] {
        guard let spec = specification, let game else { return [] }
        var tiles = JavaTileSet()
        if spec.getBoolean(GameOptions.fogOfWar) {
            let settlements: [Settlement] = hasAbility(Ability.seeAllColonies)
                ? game.allColonies(excluding: nil) : self.settlements
            for s in settlements { tiles.insert(contentsOf: s.javaVisibleTileSet) }
            for u in units where u.isOnTile { tiles.insert(contentsOf: u.javaVisibleTileSet) }
            if isEuropean && spec.getBoolean(GameOptions.enhancedMissionaries) {
                for other in game.liveNativePlayers(excluding: self) {
                    for s in other.indianSettlementsWithMissionary(self) {
                        tiles.insert(contentsOf: s.javaVisibleTileSet)
                    }
                }
            }
        } else {
            tiles.insert(contentsOf: (game.map?.tiles ?? []).filter(hasExplored))
        }
        return tiles.tiles
    }

    /// Reveal or hide the whole map (exploreMap).
    ///
    /// - Returns: The tiles that changed, in a Java HashSet's order.
    @discardableResult
    public func exploreMap(_ reveal: Bool) -> [Tile] {
        let tiles = JavaTileSet((game?.map?.tiles ?? []).filter { hasExplored($0) != reveal }).tiles
        for t in tiles { t.setExplored(self, reveal) }
        invalidateCanSeeTiles()
        if !reveal {
            for s in settlements {
                // exploreForSettlement
                var ts = JavaTileSet(copying: s.ownedTiles)
                ts.insert(contentsOf: s.javaVisibleTileSet)
                if let t = s.tile { ts.remove(t) }
                exploreTiles(ts.tiles)
            }
            for u in units { exploreForUnit(u) }
        }
        return tiles
    }

    /// Explore tiles, giving those newly explored or not seen now, in a
    /// Java HashSet's order (collectNewTiles).
    public func collectNewTiles<S: Sequence>(_ tiles: S) -> [Tile] where S.Element == Tile {
        JavaTileSet(tiles.filter { exploreTile($0) || !canSee($0) }).tiles
    }

    // MARK: Units

    /// Make units from abstract ones at a location, naming ships, and
    /// leaving out those the player can not have (createUnits).
    @discardableResult
    public func createUnits(_ abstractUnits: [AbstractUnit], _ location: (any Location)?,
                            _ random: JavaRandom?) -> [Unit] {
        guard let game, let spec = specification else { return [] }
        var units: [Unit] = []
        for au in abstractUnits {
            guard let type = au.type(spec), type.isAvailableTo([self]),
                  let role = au.role(spec), role.isAvailableTo([self, type]) else { continue }
            for _ in 0..<au.number {
                let unit = Unit(game: game, location: location, owner: self, type: type, role: role)
                unit.name = nameForUnit(type, random)
                units.append(unit)
            }
        }
        return units
    }

    /// Put land units on ships, filling the first ships first
    /// (loadShips).
    ///
    /// - Returns: The units that did not fit.
    @discardableResult
    public func loadShips(_ landUnits: [Unit], _ navalUnits: [Unit], _ random: JavaRandom?) -> [Unit] {
        var landUnits = landUnits, navalUnits = navalUnits
        if let random {
            RandomUtils.randomShuffle("Naval load", &navalUnits, random)
            RandomUtils.randomShuffle("Land load", &landUnits, random)
        }
        var leftOver: [Unit] = []
        for unit in landUnits {
            if let carrier = navalUnits.first(where: { $0.canAdd(unit) }) {
                _ = unit.setLocation(carrier)
            } else {
                leftOver.append(unit)
            }
        }
        return leftOver
    }

    /// Give a unit to another player, changing its type as the change
    /// says, or losing it if the new owner can not have it
    /// (csChangeOwner).
    ///
    /// - Returns: Whether the new owner has it.
    @discardableResult
    public func csChangeOwner(_ unit: Unit, _ newOwner: Player, _ change: String?,
                              _ location: (any Location)?, _ cs: ChangeSet) throws -> Bool {
        if newOwner === self { return true }
        let oldTile = unit.tile
        // The undead can not avoid a change.
        let change = newOwner.isUndead ? UnitChangeType.undead : change
        if let change {
            var mainType = unit.type
            if let uc = unit.unitChange(change, nil, newOwner) {
                if uc.isAvailableTo(newOwner) {
                    mainType = uc.to
                } else {
                    try unit.csRemove(.perhaps().always(self), oldTile, cs)
                    return false
                }
            }
            for u in unit.unitList {
                guard let uc = u.unitChange(change, nil, newOwner) else { continue }
                if uc.isAvailableTo(newOwner) {
                    if let to = uc.to, to !== u.type { _ = u.changeType(to) }
                } else {
                    try u.csRemove(.only(self), unit, cs)
                }
            }
            unit.changeOwner(newOwner)
            if let mainType, mainType !== unit.type, !unit.changeType(mainType) { return false }
        } else {
            unit.changeOwner(newOwner)
        }
        if let location { _ = unit.setLocation(location) }
        if unit.isCarrier { cs.addRemoves(.only(self), unit, unit.unitList) }
        cs.add(.only(newOwner), newOwner.exploreForUnit(unit))
        return true
    }

    // MARK: Stance and tension

    private func addStanceChange(_ other: Player) {
        if !stanceDirty.contains(where: { $0 === other }) { stanceDirty.append(other) }
    }

    /// Change the stance towards another player, and its towards this
    /// one too if symmetric, with the tension, history and messages that
    /// go with it (csChangeStance).
    ///
    /// - Returns: Whether anything changed.
    @discardableResult
    public func csChangeStance(_ stance: Stance, _ other: Player, _ symmetric: Bool,
                               _ cs: ChangeSet) throws -> Bool {
        guard let game else { return false }
        var change = false
        var old = self.stance(other)
        if old != stance {
            let modifier = old.tensionModifier(stance)
            setStance(other, stance)
            if modifier != 0 { try csModifyTension(other, modifier, nil, cs) }
            if let type = HistoryEvent.HistoryEventType.from(stance) {
                cs.addHistory(self, HistoryEvent(game.turn, type, other)
                    .addStringTemplate("%nation%", other.nationLabel))
            }
            addStanceChange(other)
            if old != .uncontacted {
                cs.addMessage(other, ModelMessage(.foreignDiplomacy, stance.stanceChangeKey, self)
                    .addStringTemplate("%nation%", nationLabel))
            }
            cs.addStance(.only(self), self, stance, other)
            cs.addStance(.only(other), self, stance, other)
            change = true
        }
        if symmetric {
            old = other.stance(self)
            if old != stance {
                let modifier = old.tensionModifier(stance)
                other.setStance(self, stance)
                if modifier != 0 { try other.csModifyTension(self, modifier, nil, cs) }
                if let type = HistoryEvent.HistoryEventType.from(stance) {
                    cs.addHistory(other, HistoryEvent(game.turn, type, self)
                        .addStringTemplate("%nation%", nationLabel))
                }
                other.addStanceChange(self)
                if old != .uncontacted {
                    cs.addMessage(self, ModelMessage(.foreignDiplomacy, stance.stanceChangeKey, other)
                        .addStringTemplate("%nation%", other.nationLabel))
                }
                cs.addStance(.only(self), other, stance, self)
                cs.addStance(.only(other), other, stance, self)
                change = true
            }
        }
        return change
    }

    /// Change the tension towards a player, and for natives the alarm of
    /// their settlements that know the player, except where it began
    /// (csModifyTension).
    public func csModifyTension(_ player: Player, _ add: Int, _ origin: Settlement?,
                                _ cs: ChangeSet) throws {
        var t = tension(player)
        let oldLevel = t.level
        t.modify(add)
        setTension(player, t)
        if oldLevel != t.level { cs.add(.only(player), self) }
        if isIndian {
            for settlement in indianSettlementList where settlement !== origin && settlement.hasContacted(player) {
                try settlement.csModifyAlarm(player, add, false, cs)
            }
        }
    }

    // MARK: Taxes and mercenaries

    /// Set the tax, telling the player of the whole player if the bells
    /// bonus changes with it (csSetTax).
    public func csSetTax(_ tax: Int, _ cs: ChangeSet) {
        setTax(tax)
        if recalculateBellsBonus() {
            cs.add(.only(self), self)
        } else {
            cs.addPartial(.only(self), self, ("tax", String(self.tax)))
        }
    }

    /// The bells bonus of a goods party this turn
    /// (makeTeaPartyModifier).
    public func makeTeaPartyModifier() -> Modifier? {
        guard let game, let spec = specification,
              let template = spec.modifiers(Modifier.colonyGoodsParty).first else { return nil }
        let modifier = Modifier.makeTimedModifier("model.goods.bells", template: template, start: game.turn)
        modifier.modifierIndex = Modifier.partyProductionIndex
        return modifier
    }

    /// Raise the tax as the monarch asked, or by more if the goods have
    /// gone, or hold a goods party (csRaiseTax).
    public func csRaiseTax(_ tax: Int, _ goods: Goods, _ accepted: Bool, _ cs: ChangeSet) throws {
        guard let goodsType = goods.type, let colony = goods.location as? Colony else { return }
        let amount = min(goods.amount, GoodsContainer.cargoSize)
        if accepted {
            csSetTax(tax, cs)
        } else if colony.goodsCount(goodsType) < amount {
            // The goods have been moved away, so the tax rises anyway.
            let extraTax = 3
            csSetTax(tax + extraTax, cs)
            cs.add(.only(self), message: MonarchActionMessage(Monarch.MonarchAction.forceTax, StringTemplate.template(
                Monarch.MonarchAction.forceTax.textKey).addAmount("%amount%", tax + extraTax), nationId ?? ""))
        } else {
            // A goods party.
            guard let spec = specification, let market else { return }
            colony.goodsContainer?.saveState()
            _ = colony.removeGoods(goodsType, amount)
            let arrears = market.paidForSale(goodsType) * (spec.getInteger(GameOptions.arrearsFactor) ?? 0)
            market.setArrears(goodsType, arrears)
            if let tpm = makeTeaPartyModifier() { cs.addModifier(self, colony, tpm, true) }
            if let container = colony.goodsContainer { cs.add(.only(self), container) }
            if let data = market.marketData(goodsType) { cs.add(.only(self), data) }
            var messageId = "model.player.colonyGoodsParty." + (goodsType.suffix ?? "")
            if !Messages.containsKey(messageId) {
                messageId = colony.isLandLocked ? "model.player.colonyGoodsParty.landLocked"
                    : "model.player.colonyGoodsParty.harbour"
            }
            cs.addMessage(self, ModelMessage(.foreignDiplomacy, messageId, self)
                .addName("%colony%", colony.name)
                .addAmount("%amount%", amount)
                .addNamed("%goods%", goodsType))
            cs.addAttribute(.only(self), "flush", "true")
            // Reset the goods wishes.
            colony.requestRearrange(goodsType)
        }
    }

    /// The player ignored a tax raise, so it happens (ignoreTax).
    public func ignoreTax(_ tax: Int, _ goods: Goods, _ cs: ChangeSet) throws {
        try csRaiseTax(tax, goods, true, cs)
        cs.addMessage(self, ModelMessage(.foreignDiplomacy, "model.player.ignoredTax", self)
            .addAmount("%amount%", tax))
    }

    /// The player ignored an offer of mercenaries (ignoreMercenaries).
    public func ignoreMercenaries(_ cs: ChangeSet) {
        cs.addMessage(self, ModelMessage(.foreignDiplomacy, "model.player.ignoredMercenaries", self))
    }

    /// Offer mercenaries, led by someone at random (csMercenaries).
    public func csMercenaries(_ price: Int, _ mercenaries: [AbstractUnit], _ action: Monarch.MonarchAction,
                              _ random: JavaRandom, _ cs: ChangeSet) {
        guard price > 0, !mercenaries.isEmpty, let game = game as? ServerGame else { return }
        let n = game.nameCache.mercenaryLeaderIndex(random)
        cs.add(.only(self), message: MonarchActionMessage(action, StringTemplate.template(action.textKey)
            .addName("%leader%", game.nameCache.mercenaryLeaderName(n))
            .addAmount("%gold%", price)
            .addStringTemplate("%mercenaries%", AbstractUnit.listLabel(", ", mercenaries)),
            String(n)))
        MonarchSession.register(self, action, mercenaries: mercenaries, price: price, in: game.sessions)
    }

    /// Take on mercenaries the player accepted, if it can pay; if not,
    /// the monarch is displeased (csAddMercenaries).
    public func csAddMercenaries(_ mercs: [AbstractUnit], _ price: Int, _ random: JavaRandom?,
                                 _ cs: ChangeSet) throws {
        guard let spec = specification else { return }
        if checkGold(price) {
            let naval = mercs.filter { $0.type(spec)?.isNaval ?? false }
            let dst: Tile
            if naval.isEmpty {
                // To the first colony.
                guard let t = colonyList.first?.tile else { return }
                dst = t
                createUnits(mercs, dst, nil)
                cs.add(.only(self), dst)
            } else {
                // They sail in.
                guard let t = entryTile else { return }
                dst = t
                loadShips(createUnits(mercs.filter { !($0.type(spec)?.isNaval ?? false) }, nil, nil),
                          createUnits(naval, dst, random), nil)
                invalidateCanSeeTiles()
                cs.add(.perhaps(), dst)
            }
            cs.addMessage(self, ModelMessage(.unitArrived, "model.player.mercenariesArrived", self)
                .addStringTemplate("%location%", locationLabel(dst.up(), for: self)))
            _ = modifyGold(-price)
            cs.addPartial(.only(self), self, ("gold", String(gold)))
        } else {
            monarch?.displeasure = true
            cs.add(.only(self), message: MonarchActionMessage(.displeasure,
                StringTemplate.template(Monarch.MonarchAction.displeasure.textKey), nationId ?? ""))
        }
    }
}

extension Unit {
    /// What the unit can see, in the order of Java's HashSet of it
    /// (getVisibleTileSet).
    var javaVisibleTileSet: [Tile] {
        guard let tile else { return [] }
        return JavaTileSet(copying: tile.surroundingTiles(0, lineOfSight)).tiles
    }
}

extension Settlement {
    /// What the settlement can see, in the order of Java's HashSet of
    /// it (getVisibleTileSet).
    var javaVisibleTileSet: [Tile] {
        guard let tile else { return [] }
        return JavaTileSet(copying: tile.surroundingTiles(0, lineOfSight)).tiles
    }
}

extension Player.Stance {
    /// How much the tension changes moving from this stance to another
    /// (Stance.getTensionModifier).
    public func tensionModifier(_ newStance: Player.Stance) -> Int {
        func bad() -> Never { preconditionFailure("Bad stance transition: \(self) -> \(newStance)") }
        switch newStance {
        case .uncontacted: bad()
        case .alliance:
            switch self {
            case .uncontacted: bad()
            case .alliance: return 0
            case .peace: return Tension.allianceModifier
            case .ceaseFire: return Tension.allianceModifier + Tension.peaceTreatyModifier
            case .war: return Tension.allianceModifier + Tension.ceaseFireModifier + Tension.peaceTreatyModifier
            }
        case .peace:
            switch self {
            case .uncontacted: return Tension.contactModifier
            case .alliance: return Tension.dropAllianceModifier
            case .peace: return 0
            case .ceaseFire: return Tension.peaceTreatyModifier
            case .war: return Tension.ceaseFireModifier + Tension.peaceTreatyModifier
            }
        case .ceaseFire:
            switch self {
            case .uncontacted, .alliance, .peace: bad()
            case .ceaseFire: return 0
            case .war: return Tension.ceaseFireModifier
            }
        case .war:
            switch self {
            case .uncontacted, .alliance, .peace: return Tension.warModifier
            case .ceaseFire: return Tension.resumeWarModifier
            case .war: return 0
            }
        }
    }
}

extension Europe {
    /// Replace the recruits that can no longer be recruited
    /// (replaceRecruits).
    ///
    /// - Returns: Whether any were.
    func replaceRecruits(_ random: JavaRandom) -> Bool {
        guard let spec = specification else { return false }
        let keep = recruitables.filter { au in au.type(spec).map { hasAbility(Ability.canRecruitUnit, for: $0) } ?? false }
        let result = keep.count != recruitables.count
        setRecruitables(keep)
        fillRecruitables(random)
        return result
    }
}

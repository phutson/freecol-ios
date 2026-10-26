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

// What needs the combat model or paths: defenders, defence and plunder
// for tiles and settlements, player strength and visibility, and the
// monarch's war support.

extension Tile {

    /// Whether a ship here could be bombarded by a settlement it is not
    /// friends with.
    public func isDangerousToShip(_ ship: Unit) -> Bool {
        guard let player = ship.owner else { return false }
        return surroundingTiles(0, 1).contains { t in
            guard let settlement = t.settlement else { return false }
            return !player.owns(settlement) && settlement.canBombardEnemyShip
                && (player.atWar(with: settlement.owner) || ship.hasAbility(Ability.piracy))
        }
    }

    /// The land tiles here and around that a player could stand on,
    /// best defence first.
    public func safestSurroundingLandTiles(_ player: Player) -> [Tile] {
        surroundingTiles(0, 1)
            .filter { $0.isLand && (!$0.hasSettlement || player.owns($0.settlement)) }
            .stableSorted { $0.defenceValue > $1.defenceValue }
    }

    /// The safest land tile next to the high seas.
    public func bestDisembarkTile(_ player: Player) -> Tile? {
        safestSurroundingLandTiles(player).first { $0.isHighSeasConnected }
    }

    /// Whether a unit could not pass: a foreign unit, foreign or no
    /// settlement on land for ships, or water for land units.
    public func isBlocked(_ unit: Unit) -> Bool {
        guard let owner = unit.owner else { return true }
        if let u = firstUnit, !owner.owns(u) { return true }
        if isLand {
            let s = settlement
            return unit.isNaval ? s == nil || !owner.owns(s) : s != nil && !owner.owns(s)
        }
        return !unit.isNaval
    }

    /// The nearest tile with no foreign units or settlement, in random
    /// order within each ring if a generator is given.
    public func safeTile(_ player: Player?, _ random: JavaRandom?) -> Tile? {
        func safe(_ t: Tile) -> Bool {
            (t.firstUnit == nil || t.firstUnit!.owner === player)
                && (t.settlement == nil || t.settlement!.owner === player)
        }
        if safe(self) { return self }
        var r = 1
        while true {
            var tiles = surroundingTiles(r, r)
            if tiles.isEmpty { return nil }
            if let random { RandomUtils.randomShuffle("Safe tile", &tiles, random) }
            if let t = tiles.first(where: safe) { return t }
            r += 1
        }
    }

    /// The unit that would defend this tile against an attacker: the
    /// best unit that can fight here, then the settlement's defender if
    /// that is not a soldier, and finally a beached ship.
    public func defendingUnit(_ attacker: Unit?) -> Unit? {
        guard let cm = game?.combatModel else { return nil }
        var defender: Unit?
        var defenderPower = -1.0
        // On land, ships are docked and can not defend (unless beached,
        // below); at sea, land units are cargo.
        for u in unitList where isLand != u.isNaval {
            let power = cm.defencePower(attacker, u)
            if Unit.betterDefender(defender, defenderPower, u, power) {
                defender = u
                defenderPower = power
            }
        }
        // Then a settlement defender, if any.  (Java keeps the tile
        // defender's power here, as the unknown inside power.)
        if defender == nil || !defender!.isDefensiveUnit, let settlement,
           let u = settlement.defendingUnit(attacker) {
            let power = cm.defencePower(attacker, u)
            if Unit.betterDefender(defender, defenderPower, u, power) { defender = u }
        }
        // Finally a beached ship defends (and loses) on land.
        if defender == nil && isLand { defender = firstUnit }
        return defender
    }

    // MARK: Players' views
    //
    // Java's server tiles keep each European player's view: the tile
    // itself while the player can see it, or a copy of what the player
    // last saw (cachedTiles), and what the player knows of a native
    // settlement here (playerIndianSettlements).  This engine is the
    // server, so every tile keeps them.

    /// A player's view of this tile: this tile for non-European
    /// players, nil for a European player who has not explored it.
    public func cachedTile(_ player: Player) -> Tile? {
        guard player.isEuropean else { return self }
        switch cachedTiles[ObjectIdentifier(player)] {
        case nil: return nil
        case .current: return self
        case .copy(let tile): return tile
        }
    }

    /// Set a European player's view: this tile, or a detached copy.
    public func setCachedTile(_ player: Player, _ tile: Tile) {
        guard player.isEuropean else { return }
        cachedTiles[ObjectIdentifier(player)] = tile === self ? .current : .copy(tile)
    }

    /// A copy of this tile for a player's view: without its units, and
    /// with a colony showing at least one unit (getTileToCache).
    public func tileToCache() throws -> Tile {
        let tile = try copy()
        tile.clearUnitList()
        // The colony may be being destroyed, with no units left.
        if let colony, let copied = tile.colony {
            copied.displayUnitCount = max(1, colony.unitCount)
        }
        return tile
    }

    /// A change is about to happen here: give each live European
    /// player (but one, who will see it) that can not see the tile and
    /// has a current view a copy of the tile as it is now, made once.
    public func cacheUnseen(except player: Player? = nil, copied: Tile? = nil) throws {
        var copied = copied
        for p in game?.liveEuropeanPlayers(excluding: player) ?? []
        where !p.canSee(self) && cachedTile(p) === self {
            if copied == nil { copied = try tileToCache() }
            setCachedTile(p, copied!)
        }
    }

    /// Whether a player has explored this tile: natives know their
    /// land, Europeans need a view of the tile.
    public func isExploredBy(_ player: Player?) -> Bool {
        guard let player else { return false }
        if !player.isEuropean { return true }
        if !isExplored { return false }
        return cachedTiles[ObjectIdentifier(player)] != nil
    }

    /// Give a European player a current view of this tile.
    public func seeTile(_ player: Player) {
        setCachedTile(player, self)
    }

    /// Give every live European player who can see this tile a
    /// current view of it.
    public func seeTile() {
        for p in game?.liveEuropeanPlayers ?? [] where p.canSee(self) { seeTile(p) }
    }

    /// Reveal or hide the tile for a European player.
    public func setExplored(_ player: Player, _ reveal: Bool) {
        guard player.isEuropean else { return }
        if reveal {
            seeTile(player)
        } else {
            cachedTiles[ObjectIdentifier(player)] = nil
        }
    }

    /// What a player knows of the native settlement here: the skill
    /// taught, and the goods wanted.
    public func learnableSkill(for player: Player) -> UnitType? {
        playerIndianSettlements[ObjectIdentifier(player)]?.skill
    }

    public func wantedGoods(for player: Player) -> [GoodsType?]? {
        playerIndianSettlements[ObjectIdentifier(player)]?.wantedGoods
    }

    /// Update what a European player knows of the native settlement
    /// here.
    public func updateIndianSettlement(_ player: Player) {
        guard player.isEuropean else { return }
        if let settlement = indianSettlement {
            setIndianSettlementInternals(player, settlement.learnableSkill, settlement.wantedGoods)
        } else {
            removeIndianSettlementInternals(player)
        }
    }

    public func removeIndianSettlementInternals(_ player: Player) {
        playerIndianSettlements[ObjectIdentifier(player)] = nil
    }

    func setIndianSettlementInternals(_ player: Player, _ skill: UnitType?, _ wanted: [GoodsType?]?) {
        playerIndianSettlements[ObjectIdentifier(player)] = IndianSettlementInternals(skill: skill, wantedGoods: wanted)
    }
}

extension SettlementType {
    /// The plunder for a unit that captures a settlement of this type:
    /// the first plunder kind that applies to it.
    public func plunderRange(_ unit: Unit) -> RandomRange? {
        plunderTypes.first { $0.appliesTo(unit) }?.plunder
    }
}

extension Settlement {
    /// The unit that defends the settlement against an attacker.
    public func defendingUnit(_ attacker: Unit?) -> Unit? {
        if let colony = self as? Colony { return colony.colonyDefendingUnit(attacker) }
        if let settlement = self as? IndianSettlement { return settlement.nativeDefendingUnit(attacker) }
        return nil
    }

    /// The plunder an attacker takes, chosen at random.
    public func plunder(_ attacker: Unit, _ random: JavaRandom) -> Int {
        guard let range = plunderRange(attacker) else { return 0 }
        return range.amount("Plunder \(name ?? "null")", random, continuous: false)
    }

    /// What an attacker could plunder.
    public func plunderRange(_ attacker: Unit) -> RandomRange? {
        if let colony = self as? Colony { return colony.colonyPlunderRange }
        return type?.plunderRange(attacker)
    }
}

extension Colony {

    /// The best defender working in the colony, or nil if the units are
    /// hidden (a foreign colony's display count).  Units outside the
    /// colony on its tile are Tile.defendingUnit's business.
    func colonyDefendingUnit(_ attacker: Unit?) -> Unit? {
        if displayUnitCount > 0 { return nil }
        guard let cm = game?.combatModel else { return nil }
        // Java's maximize: the first of the best.
        var best: Unit?
        var bestPower = 0.0
        for u in unitList {
            let p = cm.defencePower(attacker, u)
            if best == nil || p > bestPower {
                best = u
                bestPower = p
            }
        }
        return best
    }

    /// The defence power of the soldiers on the colony tile.
    public var totalDefencePower: Double {
        guard let cm = game?.combatModel else { return 0 }
        return JavaMath.doubleStreamSum((tile?.unitList ?? []).filter(\.isDefensiveUnit)
            .map { cm.defencePower(nil, $0) })
    }

    public var defenceRatio: Double {
        totalDefencePower / Double(1 + unitCount)
    }

    private var offensiveUnitsOnTile: Int {
        (tile?.unitList ?? []).filter(\.isOffensiveUnit).count
    }

    public var isBadlyDefended: Bool {
        let defencePower = totalDefencePower
        if offensiveUnitsOnTile < 1 { return true }
        if offensiveUnitsOnTile > 5 { return false }
        return defencePower < 0.95 * Double(unitCount) - 2.5
    }

    public var isVeryWellDefended: Bool {
        let defencePower = totalDefencePower
        if offensiveUnitsOnTile < 3 { return false }
        if offensiveUnitsOnTile > 5 { return true }
        return defencePower / 2 > 0.95 * Double(unitCount) - 2.5
    }

    /// The gold an attacker could take: a share of the owner's gold by
    /// the colony's share of the population.
    public var colonyPlunderRange: RandomRange? {
        guard canBePlundered, let owner else { return nil }
        let upper = (owner.gold * (unitCount + 1)) / (owner.coloniesPopulation + 1)
        return upper > 0 ? RandomRange(probability: 100, minimum: 1, maximum: upper + 1, factor: 1) : nil
    }
}

extension IndianSettlement {
    /// The best defender among the settlement's units.
    func nativeDefendingUnit(_ attacker: Unit?) -> Unit? {
        guard let cm = (attacker?.game ?? game)?.combatModel else { return nil }
        var defender: Unit?
        var defencePower = -1.0
        for u in unitList {
            let power = cm.defencePower(attacker, u)
            if Unit.betterDefender(defender, defencePower, u, power) {
                defender = u
                defencePower = power
            }
        }
        return defender
    }
}

extension Player {

    /// The offence of the player's naval or land units, truncated.
    public func calculateStrength(naval: Bool) -> Int {
        guard let cm = game?.combatModel else { return 0 }
        return Int(JavaMath.toInt(JavaMath.doubleStreamSum(units.filter { $0.isNaval == naval }
            .map { cm.offencePower($0, nil) })))
    }

    /// The colonial player's share of strength against its REF.
    public func rebelStrengthRatio(naval: Bool) -> Double {
        guard playerType == .colonial, let monarch else { return 0 }
        return Player.strengthRatio(Double(calculateStrength(naval: naval)),
                                    monarch.expeditionaryForce.calculateStrength(naval))
    }

    // MARK: Visibility

    /// Whether the player has explored a tile (the server's view).
    public func hasExplored(_ tile: Tile) -> Bool {
        tile.isExploredBy(self)
    }

    /// The tiles the player can see: with fog of war, around its
    /// settlements (all colonies with Coronado), units and (with
    /// enhanced missionaries) missions; otherwise all it has explored.
    public var visibleTileSet: [Tile] {
        guard let spec = specification, let game else { return [] }
        var seen = Set<ObjectIdentifier>()
        var tiles: [Tile] = []
        func add<S: Sequence>(_ ts: S) where S.Element == Tile {
            for t in ts where seen.insert(ObjectIdentifier(t)).inserted { tiles.append(t) }
        }
        if spec.getBoolean(GameOptions.fogOfWar) {
            let settlements: [Settlement] = hasAbility(Ability.seeAllColonies)
                ? game.allColonies(excluding: nil) : self.settlements
            for s in settlements { add(s.visibleTileSet) }
            for u in units where u.isOnTile { add(u.visibleTileSet) }
            if isEuropean && spec.getBoolean(GameOptions.enhancedMissionaries) {
                for other in game.liveNativePlayers(excluding: self) {
                    for s in other.indianSettlementsWithMissionary(self) { add(s.visibleTileSet) }
                }
            }
        } else {
            add(game.map?.tiles.filter(hasExplored) ?? [])
        }
        return tiles
    }

    /// Whether the player can see a tile.  As in Java, the answer is
    /// kept until invalidateCanSeeTiles, and working it out with fog of
    /// war gives the player a view of each visible tile.
    public func canSee(_ tile: Tile?) -> Bool {
        guard let tile, let spec = specification, game?.map != nil else { return false }
        if canSeeTiles == nil {
            let visible = visibleTileSet
            if spec.getBoolean(GameOptions.fogOfWar) {
                for t in visible { t.seeTile(self) }
            }
            canSeeTiles = Set(visible.map(\.position))
        }
        return canSeeTiles!.contains(tile.position)
    }

    public func invalidateCanSeeTiles() {
        canSeeTiles = nil
    }

    /// Whether the player can see a unit: its own, or one in the open
    /// on a visible tile.
    public func canSeeUnit(_ unit: Unit) -> Bool {
        if owns(unit) { return true }
        guard let tile = unit.tile, canSee(tile) else { return false }
        return !tile.hasSettlement && !unit.isOnCarrier
    }
}

extension Monarch {
    /// The war support force, if the crown thinks the player needs it,
    /// reduced if it would make the player too strong.  As in Java, the
    /// units come from the rules' list and are changed in place.
    public func warSupport(_ enemy: Player, _ random: JavaRandom) -> [AbstractUnit] {
        guard let spec = specification, let player else { return [] }
        let baseStrength = Double(player.calculateStrength(naval: false))
        let enemyStrength = Double(enemy.calculateStrength(naval: false))
        let strengthRatio = Player.strengthRatio(baseStrength, enemyStrength)
        var result: [AbstractUnit] = []

        // Support in negative proportion to the strength ratio: always
        // when the enemy is stronger, never when the player is more than
        // 50% stronger.
        let noSupport = 0.6
        let p = 10.0 * (noSupport - strengthRatio)
        if p >= 1.0 // Avoid calling randomDouble if unnecessary
            || (p > 0.0 && p > RandomUtils.randomDouble("War support?", random)) {
            let wsf = warSupportForce
            result += wsf.unitList
            let supportStrength = wsf.calculateStrength(false)
            let fullRatio = Player.strengthRatio(baseStrength + supportStrength, enemyStrength)
            if fullRatio < noSupport { // Full support, some randomization
                for au in result {
                    au.addToNumber(Int(RandomUtils.randomInt("Vary war force \(au.id ?? "null")", random, 3)) - 1)
                }
            } else if enemyStrength <= 0.0 { // Enemy is defenceless: 1 unit
                while result.count > 1 { result.remove(at: 0) }
                result[0].number = 1
            } else { // Reduce force until below noSupport or single units
                outer: for au in result {
                    var n = au.number - 1
                    while n >= 1 {
                        au.number = n
                        let strength = AbstractUnit.calculateStrength(spec, result)
                        if Player.strengthRatio(baseStrength + strength, enemyStrength) < noSupport {
                            break outer
                        }
                        n -= 1
                    }
                }
            }
        }
        return result
    }
}

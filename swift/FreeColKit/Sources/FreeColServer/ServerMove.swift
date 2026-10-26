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

/// Moving units (ServerUnit.csMove and what it reaches): exploring,
/// lost city rumours, first contact, sentries, being slowed by enemy
/// ships, and discovering regions.
extension Unit {

    /// Move to a neighbouring tile, or onto the map from the high seas
    /// (csMove).  The move is checked already.
    public func csMove(_ newTile: Tile, _ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let owner, let oldLocation = location else { return }
        // The tiles that will come into sight.
        var oldTiles = javaVisibleTileSet
        let newTiles = owner.collectNewTiles(newTile.surroundingTiles(0, lineOfSight))

        setState(.active)
        setStateToAllChildren(.sentry)
        if oldLocation is HighSeas {
            // No move cost from Europe.
        } else if oldLocation is Unit {
            movesLeft = 0 // Disembarking takes all the moves.
        } else {
            if moveCost(newTile) <= 0 { movesLeft = 0 }
            movesLeft -= moveCost(newTile)
        }

        // Move, and explore a rumour.
        if oldLocation is WorkLocation { try oldLocation.tile?.cacheUnseen() }
        _ = setLocation(newTile)
        if newTile.lostCityRumour != nil && owner.isEuropean, try !csExploreLostCityRumour(random, cs) {
            try csRemove(.perhaps().always(owner), oldLocation, cs)
        }
        owner.invalidateCanSeeTiles()

        // The tiles now out of sight.
        oldTiles.removeAll { owner.canSee($0) }
        if !oldTiles.isEmpty { cs.add(.only(owner), oldTiles) }

        // The move is always seen, even if the unit dies, unless it
        // comes from off the map.  The dead discover nothing.
        if oldLocation.tile != nil {
            cs.addMove(.perhaps().always(owner), self, oldLocation, newTile)
            cs.add(.perhaps().always(owner), oldLocation as? FreeColGameObject)
        } else {
            cs.add(.only(owner), oldLocation as? FreeColGameObject)
        }
        cs.add(.perhaps().always(owner), newTile)
        if isDisposed { return }
        owner.csSeeNewTiles(newTiles, cs)

        if newTile.isLand {
            // Natives claim land near home.
            if newTile.owner == nil || ((newTile.owner?.isEuropean ?? false) && newTile.owningSettlement == nil),
               owner.isIndian, let settlement = homeIndianSettlement, let home = settlement.tile {
                let d = newTile.distance(to: home)
                if d < settlement.radius + (settlement.type?.extraClaimableRadius ?? 0),
                   RandomUtils.randomInt("Claim tribal land", random, Int32(d + 1)) == 0 {
                    try newTile.cacheUnseen()
                    newTile.changeOwnership(owner, settlement)
                }
            }

            // A first landing names the new land, by default.
            let firstLanding = owner.newLandName == nil
            if firstLanding && owner.isEuropean {
                let newLand = (owner.game as? ServerGame)?.nameCache.newLandName(owner) ?? ""
                owner.newLandName = newLand
                cs.add(.only(owner), message: NewLandNameMessage(self, newLand))
            }

            try csNewContactCheck(newTile, firstLanding, cs)
        } else {
            for t in newTile.surroundingTiles(1, 1)
            where !t.isLand && t.firstUnit != nil && t.firstUnit?.owner !== owner {
                csActivateSentries(t, cs)
            }
        }

        // Units aboard leave the ship in a colony.
        if isCarrier && !unitList.isEmpty && newTile.colony != nil
            && (specification?.getBoolean(GameOptions.disembarkInColony) ?? false) {
            for u in unitList { try u.csMove(newTile, random, cs) }
            movesLeft = 0
        }

        if let slowedBy = slowedBy(newTile, random) {
            cs.addMessage(owner, ModelMessage(.foreignDiplomacy, "model.unit.slowed", self, slowedBy)
                .addStringTemplate("%unit%", label(.national))
                .addStringTemplate("%enemyUnit%", slowedBy.label(.plain))
                .addStringTemplate("%enemyNation%", slowedBy.apparentOwnerName))
        }

        csCheckDiscoverRegion(newTile, cs)
    }

    /// The enemy ship beside a tile that slows this ship, if one does,
    /// taking moves away (getSlowedBy).
    private func slowedBy(_ newTile: Tile, _ random: JavaRandom) -> Unit? {
        guard isNaval, movesLeft > 0, let player = owner, let game else { return nil }
        let combatModel = game.combatModel
        let pirate = hasAbility(Ability.piracy)
        var attacker: Unit?
        var attackPower = 0.0, totalAttackPower = 0.0
        for tile in newTile.surroundingTiles(1) {
            // Ships in settlements do not slow ships.
            guard !tile.isLand, tile.colony == nil, let first = tile.firstUnit,
                  let enemy = first.owner, enemy !== player else { continue }
            for enemyUnit in tile.unitList where enemyUnit.isNaval
                && (pirate || enemyUnit.hasAbility(Ability.piracy)
                    || (enemyUnit.isOffensiveUnit && player.atWar(with: enemy))) {
                let power = combatModel.offencePower(enemyUnit, self)
                totalAttackPower += power
                if power > attackPower {
                    attacker = enemyUnit
                    attackPower = power
                }
            }
        }
        guard let found = attacker else { return nil }
        let defencePower = combatModel.defencePower(found, self)
        let totalProbability = totalAttackPower + defencePower
        let range = Int32(truncatingIfNeeded: JavaMath.round(totalProbability + 1))
        if Double(RandomUtils.randomInt("Slowed", random, range)) < totalAttackPower {
            let diff = max(0, Int(JavaMath.round(totalAttackPower - defencePower)))
            movesLeft -= min(9, 3 + diff / 3)
            return found
        }
        return nil
    }

    /// Disturbing a burial ground means war with its natives
    /// (csNativeBurialGround).
    private func csNativeBurialGround(_ cs: ChangeSet) throws {
        guard let owner, let indianPlayer = tile?.owner else { return }
        _ = owner.csContact(indianPlayer, cs)
        try indianPlayer.csModifyTension(owner, Tension.Level.hateful.limit, nil, cs)
        try owner.csChangeStance(.war, indianPlayer, true, cs)
        cs.addMessage(owner, ModelMessage(.lostCityRumour, LostCityRumour.RumourType.burialGround.descriptionKey,
                                          owner, self)
            .addStringTemplate("%nation%", indianPlayer.nationLabel))
    }

    /// Explore the rumour here (csExploreLostCityRumour).
    ///
    /// - Returns: Whether the unit survives.
    private func csExploreLostCityRumour(_ random: JavaRandom, _ cs: ChangeSet) throws -> Bool {
        guard let owner, let tile, let lostCity = tile.lostCityRumour, let game = game as? ServerGame,
              let spec = specification else { return true }
        let difficulty = spec.getInteger(GameOptions.rumourDifficulty) ?? 0
        let dx = 10 - difficulty
        let treasureUnitTypes = spec.unitTypes(withAnyAbility: Ability.carryTreasure)

        var rumour = lostCity.type ?? lostCity.chooseType(self, random) ?? .nothing
        // Cases that could only be set for debugging.
        switch rumour {
        case .burialGround, .mounds:
            if !(tile.owner?.isIndian ?? false) { rumour = .nothing }
        case .learn:
            if unitChange(UnitChangeType.lostCity) != nil { rumour = .nothing }
        default:
            break
        }

        // Mounds turn into something else.
        let mounds = rumour == .mounds
        if mounds {
            var done = false, nothing = false
            while !done {
                rumour = lostCity.chooseType(self, random) ?? .nothing
                switch rumour {
                case .nothing:
                    // Not nothing at the first try.
                    if nothing { done = true } else { nothing = true }
                case .expeditionVanishes, .tribalChief:
                    done = true
                case .ruins:
                    done = true
                    // De Soto does not protect against a burial ground
                    // found with ruins.
                    if Int(RandomUtils.randomInt("Ruins+Burial", random, 100))
                        >= (spec.getPercentage(GameOptions.badRumour) ?? spec.getInteger(GameOptions.badRumour) ?? 0) {
                        break
                    }
                    // As in Java, this falls through to the burial
                    // ground case, but stays ruins.
                    done = tile.owner?.isIndian ?? false
                case .burialGround:
                    done = tile.owner?.isIndian ?? false
                default:
                    break // Not acceptable for mounds.
                }
            }
        }

        var result = true
        var key = rumour.descriptionKey
        var newUnit: Unit?
        switch rumour {
        case .burialGround:
            try csNativeBurialGround(cs)
        case .expeditionVanishes:
            cs.addMessage(owner, ModelMessage(.lostCityRumour, key, owner))
            result = false
        case .nothing:
            cs.addMessage(owner, game.nameCache.nothingMessage(owner, mounds, game, random))
        case .learn:
            let oldName = label
            let changes = spec.unitChanges(UnitChangeType.lostCity, type)
            if let uc = RandomUtils.randomMember("Choose learn", changes, random), let to = uc.to {
                _ = changeType(to)
            }
            owner.invalidateCanSeeTiles()
            cs.addMessage(owner, ModelMessage(.lostCityRumour, key, owner, self)
                .addStringTemplate("%unit%", oldName)
                .addNamed("%type%", type!))
        case .tribalChief:
            let chiefAmount = Int(RandomUtils.randomInt("Chief base amount", random, Int32(dx * 10))) + dx * 5
            _ = owner.modifyGold(chiefAmount)
            cs.addPartial(.only(owner), owner, ("gold", String(owner.gold)), ("score", String(owner.score)))
            if mounds { key = rumour.alternateDescriptionKey("mounds") }
            cs.addMessage(owner, ModelMessage(.lostCityRumour, key, owner, self).addAmount("%money%", chiefAmount))
            owner.invalidateCanSeeTiles()
        case .colonist:
            let foundTypes = spec.unitTypes(withAnyAbility: Ability.foundInLostCity)
            if let unitType = RandomUtils.randomMember("Choose found", foundTypes, random) {
                newUnit = Unit(game: game, location: tile, owner: owner, type: unitType)
                cs.addMessage(owner, ModelMessage(.lostCityRumour, key, owner, newUnit))
            }
        case .cibola, .ruins:
            if rumour == .cibola, let cityName = game.nameCache.nextCityOfCibola(game) {
                let treasureAmount = Int(RandomUtils.randomInt("Base treasure amount", random, Int32(dx * 600)))
                    + dx * 300
                if let unitType = RandomUtils.randomMember("Choose train", treasureUnitTypes, random) {
                    newUnit = Unit(game: game, location: tile, owner: owner, type: unitType)
                    newUnit!.treasureAmount = treasureAmount
                }
                cs.addMessage(owner, ModelMessage(.lostCityRumour, key, owner, newUnit)
                    .addName("%city%", cityName)
                    .addAmount("%money%", treasureAmount))
                cs.addGlobalHistory(game, HistoryEvent(game.turn, .cityOfGold, owner)
                    .addStringTemplate("%nation%", owner.nationLabel)
                    .addName("%city%", cityName)
                    .addAmount("%treasure%", treasureAmount))
                break
            }
            // Ruins, or every city of gold has been found (keeping, as
            // Java does, the message key it had).
            let ruinsAmount = Int(RandomUtils.randomInt("Base ruins amount", random, Int32(dx * 2))) * 300 + 50
            if ruinsAmount < 500 {
                _ = owner.modifyGold(ruinsAmount)
                cs.addPartial(.only(owner), owner, ("gold", String(owner.gold)), ("score", String(owner.score)))
            } else if let unitType = RandomUtils.randomMember("Choose train", treasureUnitTypes, random) {
                newUnit = Unit(game: game, location: tile, owner: owner, type: unitType)
                newUnit!.treasureAmount = ruinsAmount
            }
            if mounds { key = rumour.alternateDescriptionKey("mounds") }
            cs.addMessage(owner, ModelMessage(.lostCityRumour, key, owner, newUnit ?? self)
                .addAmount("%money%", ruinsAmount))
        case .fountainOfYouth:
            if let europe = owner.europe {
                if owner.isAI {
                    // The AI does not choose.
                    europe.generateFountainRecruits(dx, random)
                    cs.add(.only(owner), europe)
                } else {
                    owner.remainingEmigrants = dx
                    cs.add(.only(owner), message: FountainOfYouthMessage(dx))
                }
                cs.addMessage(owner, ModelMessage(.lostCityRumour, key, owner, self))
                cs.addAttribute(.only(owner), "sound", "sound.event.fountainOfYouth")
            } else {
                cs.addMessage(owner, ModelMessage(.lostCityRumour, rumour.alternateDescriptionKey("noEurope"),
                                                  owner, self))
            }
        case .noSuchRumour, .mounds:
            break
        }
        try tile.cacheUnseen()
        _ = tile.removeLostCityRumour()
        return result
    }

    /// Contact with the players beside a tile: first contacts, native
    /// settlements meeting a European, and sentries woken
    /// (csNewContactCheck).
    public func csNewContactCheck(_ newTile: Tile, _ firstLanding: Bool, _ cs: ChangeSet) throws {
        guard let owner else { return }
        var pending: [Player] = []
        for t in newTile.surroundingTiles(1, 1) where t.isLand {
            let settlement = t.settlement
            var unit: Unit?
            let other: Player?
            if let settlement {
                other = settlement.owner
            } else {
                unit = t.firstUnit
                other = unit?.owner
            }
            guard let other, other !== owner, !pending.contains(where: { $0 === other }) else { continue }
            if owner.csContact(other, cs) {
                // A first contact; Europeans' needs a diplomacy session
                // to finish.
                pending.append(other)
                if owner.isEuropean {
                    if other.isIndian {
                        let offer = (firstLanding && other.owns(newTile)) ? newTile : nil
                        try owner.csNativeFirstContact(other, offer, cs)
                    } else {
                        try owner.csEuropeanFirstContact(self, settlement, unit, cs)
                    }
                } else if !other.isIndian {
                    try other.csNativeFirstContact(owner, nil, cs)
                }
            }

            // A native settlement, or a native unit's home, meets the
            // European.
            var contactPlayer = owner
            var settlementMet = settlement as? IndianSettlement
            if settlementMet == nil, let unit {
                settlementMet = unit.homeIndianSettlement
                if settlementMet == nil, let uo = unit.owner, uo.isEuropean,
                   let home = homeIndianSettlement, home.tile != nil {
                    contactPlayer = uo
                    settlementMet = home
                }
            }
            if let settlementMet, let stile = settlementMet.tile {
                let copied = try stile.tileToCache()
                if contactPlayer.hasExplored(stile) && settlementMet.setContacted(contactPlayer) {
                    try stile.cacheUnseen(copied: copied)
                    cs.add(.only(contactPlayer), settlementMet)
                    cs.addMessage(contactPlayer, ModelMessage(.foreignDiplomacy, "model.unit.nativeSettlementContact",
                                                              self, settlementMet)
                        .addStringTemplate("%nation%", settlementMet.owner?.nationLabel)
                        .addName("%settlement%", settlementMet.name))
                }
            }
            csActivateSentries(t, cs)
        }
    }

    /// Wake the sentries on a tile (csActivateSentries).
    private func csActivateSentries(_ tile: Tile, _ cs: ChangeSet) {
        for u in tile.unitList where u.state == .sentry {
            u.setState(.active)
            cs.add(.perhaps(), u)
        }
    }

    /// Ask the owner to name a region the unit has discovered
    /// (csCheckDiscoverRegion).
    public func csCheckDiscoverRegion(_ tile: Tile, _ cs: ChangeSet) {
        guard let region = tile.discoverableRegion, let owner, owner.isEuropean, region.checkDiscover(self),
              let game = game as? ServerGame else { return }
        cs.add(.only(owner), message: NewRegionNameMessage(region, tile, self,
                                                            game.nameCache.regionName(owner, region)))
    }
}

extension Player {

    /// A first contact with another player, recorded in the European's
    /// history (csContact).
    ///
    /// - Returns: Whether it was a first contact.
    @discardableResult
    public func csContact(_ other: Player, _ cs: ChangeSet) -> Bool {
        if hasContacted(other) { return false }
        guard let game else { return false }
        if isIndian {
            if other.isIndian { return false } // Natives meeting natives does not count.
            cs.addHistory(other, HistoryEvent(game.turn, .meetNation, other)
                .addStringTemplate("%nation%", nationLabel))
        } else {
            cs.addHistory(self, HistoryEvent(game.turn, .meetNation, other)
                .addStringTemplate("%nation%", other.nationLabel))
        }
        return true
    }

    /// A European meets a native nation: peace, and the European is told
    /// (csNativeFirstContact).  At a first landing on the natives' land
    /// they offer it, in a session, so that accepting can be checked.
    public func csNativeFirstContact(_ other: Player, _ tile: Tile?, _ cs: ChangeSet) throws {
        cs.add(.only(self), message: FirstContactMessage(self, other, tile))
        try csChangeStance(.peace, other, true, cs)
        if let tile, let unit = tile.firstUnit, let game = game as? ServerGame {
            let ds = DiplomacySession.register(unit, settlement: tile.owningSettlement, otherUnit: nil,
                                               in: game.sessions)
            ds.agreement = DiplomaticTrade.makePeaceTreaty(.contact, self, other)
        }
    }
}

extension Europe {
    /// The recruits a Fountain of Youth brings an AI, which does not
    /// choose them (generateFountainRecruits).
    @discardableResult
    public func generateFountainRecruits(_ n: Int, _ random: JavaRandom) -> [Unit] {
        guard let game, let owner else { return [] }
        let recruits = recruitablesList()
        var ret: [Unit] = []
        for _ in 0..<n {
            guard let ut = RandomChoice.weightedRandom("Choose FoY", recruits, random) else { continue }
            ret.append(Unit(game: game, location: self, owner: owner, type: ut))
        }
        return ret
    }
}

extension Region {
    /// A player names a region it discovered, and everyone learns of it
    /// (ServerRegion.csDiscover).
    public func csDiscover(_ player: Player, _ unit: Unit, _ turn: Turn, _ newName: String?,
                           _ cs: ChangeSet) {
        guard discoverable, let game else { return }
        let score = (specification?.getBoolean(GameOptions.explorationPoints) ?? false) ? scoreValue : 0
        if !hasName { name = newName }
        for r in discover(player, unit, turn) { cs.add(.all(), r) }
        let h = HistoryEvent(turn, .discoverRegion, player)
            .addStringTemplate("%nation%", player.nationLabel)
            .addName("%region%", newName)
        h.score = score
        cs.addGlobalHistory(game, h)
    }
}

extension NameCache {
    /// The nation's name for the new land, unless the player has named
    /// it (getNewLandName).
    public func newLandName(_ player: Player) -> String {
        player.newLandName ?? Messages.message((player.nationId ?? "null") + ".newLandName")
    }

    /// The next city of Cibola, from the game's list (getNextCityOfCibola).
    public func nextCityOfCibola(_ game: Game) -> String? {
        game.citiesOfCibola.isEmpty ? nil : Messages.message(game.citiesOfCibola.removeFirst())
    }

    /// What a player finds at a rumour with nothing in it
    /// (LostCityRumour.getNothingMessage).
    public func nothingMessage(_ player: Player, _ mounds: Bool, _ game: Game, _ random: JavaRandom) -> ModelMessage {
        let nothing = LostCityRumour.RumourType.nothing
        if mounds { return ModelMessage(.lostCityRumour, nothing.alternateDescriptionKey("mounds"), player) }
        let year = game.specification.map { $0.turnCalendar.year(of: game.turn) } ?? 0
        if year % 100 == 12 && RandomUtils.randomInt("Mayans?", random, 4) == 0 {
            return ModelMessage(.lostCityRumour, nothing.alternateDescriptionKey("mayans"), player)
                .addAmount("%years%", 2012 - year)
        }
        return ModelMessage(.lostCityRumour, rumourNothingKey(random), player)
    }
}

// MARK: Messages

/// The default name for the new land, on a first landing
/// (NewLandNameMessage).
public final class NewLandNameMessage: ServerMessage {
    public unowned let unit: Unit
    public let name: String

    public init(_ unit: Unit, _ name: String) {
        self.unit = unit
        self.name = name
    }

    public var tag: String { "newLandName" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("unit", unit.id ?? ""), ("newLandName", name)] }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// A region discovered, with a name to suggest (NewRegionNameMessage).
public final class NewRegionNameMessage: ServerMessage {
    public unowned let region: Region
    public unowned let tile: Tile
    public unowned let unit: Unit
    public let name: String

    public init(_ region: Region, _ tile: Tile, _ unit: Unit, _ name: String) {
        self.region = region
        self.tile = tile
        self.unit = unit
        self.name = name
    }

    public var tag: String { "newRegionName" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        [("region", region.id ?? ""), ("tile", tile.id ?? ""), ("unit", unit.id ?? ""), ("newRegionName", name)]
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// A first meeting, with the native camps' count (FirstContactMessage).
public final class FirstContactMessage: ServerMessage {
    public unowned let player: Player
    public unowned let other: Player
    public let tile: Tile?

    public init(_ player: Player, _ other: Player, _ tile: Tile?) {
        self.player = player
        self.other = other
        self.tile = tile
    }

    public var tag: String { "firstContact" }
    public var priority: MessagePriority { .early }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        var ret = [("player", player.id ?? ""), ("other", other.id ?? "")]
        if let tile { ret.append(("tile", tile.id ?? "")) }
        if !other.isEuropean { ret.append(("camps", String(other.settlementCount))) }
        return ret
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// Recruits to choose from a Fountain of Youth (FountainOfYouthMessage).
public final class FountainOfYouthMessage: ServerMessage {
    public let migrants: Int

    public init(_ migrants: Int) {
        self.migrants = migrants
    }

    public var tag: String { "fountainOfYouth" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("migrants", String(migrants))] }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

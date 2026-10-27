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

extension Player {
    /// Why the player may not declare independence, or nil if it may
    /// (checkDeclareIndependence).
    public func checkDeclareIndependence() -> StringTemplate? {
        if playerType != .colonial { return StringTemplate.template("model.player.colonialIndependence") }
        guard let event = specification?.getEvent("model.event.declareIndependence"),
              let limit = event.limitValues.first(where: { !$0.evaluate(self) }) else { return nil }
        return StringTemplate.template(Messages.descriptionKey(limit.id))
            .addAmount("%limit%", game.flatMap { limit.rightHandSide.value(in: $0) } ?? 0)
    }
}

extension InGameController {

    /// Make the REF's player, with what the rebels know of the seas,
    /// coasts and their land, and its force in Europe, on its ships
    /// (createREFPlayer).  As Java's server makes an AI player
    /// (makeAIPlayer), the AI is told of it once it is in the game.
    func createREFPlayer(_ player: Player) -> Player? {
        guard let refNation = player.nation?.refNation, let monarch = player.monarch else { return nil }
        let refPlayer = Player(game: game, nation: refNation)
        refPlayer.isAI = true
        refPlayer.ready = true
        game.addPlayer(refPlayer)
        if let id = refPlayer.id { game.freeColGameObjectListener?.setFreeColGameObject(id, refPlayer) }
        let europe = refPlayer.europe
        var explore: [Tile] = []
        game.map?.forEachTile(where: {
            (!$0.isLand || $0.isCoastland || $0.owner === player) && $0.isExploredBy(player)
        }) { explore.append($0) }
        refPlayer.exploreTiles(JavaTileSet(explore).tiles)
        // Set up when it arrives.
        refPlayer.entryTile = nil
        Player.makeContact(player, refPlayer)
        // The force, in Europe.
        let exf = monarch.expeditionaryForce
        exf.prepareToBoard(monarch.navalREFUnitType)
        let landUnits = refPlayer.createUnits(exf.landUnitsList, europe, nil)
        let navalUnits = refPlayer.createUnits(exf.navalUnitsList, europe, random)
        refPlayer.loadShips(landUnits, navalUnits, random)
        return refPlayer
    }

    /// Bring in a newly made REF (csLaunchREF): its entry tile from its
    /// rebels', and its navy at the entry locations its AI chose, or on
    /// the high seas a turn's sail from them.
    func csLaunchREF(_ refPlayer: Player, _ teleport: Bool, _ cs: ChangeSet) {
        if let rebel = refPlayer.rebels.first { refPlayer.entryTile = rebel.entryTile }
        if teleport {
            var seen = Set<ObjectIdentifier>()
            for u in refPlayer.units where u.isNaval {
                let entry = u.fullEntryLocation
                u.setLocation(entry)
                u.workLeft = -1
                u.setState(.active)
                if let entry, seen.insert(ObjectIdentifier(entry)).inserted {
                    cs.add(.only(refPlayer), refPlayer.exploreForUnit(u))
                    cs.add(.perhaps().except(refPlayer), entry)
                }
            }
            refPlayer.invalidateCanSeeTiles()
        } else {
            for u in refPlayer.units where u.isNaval {
                u.workLeft = 1
                u.destination = u.fullEntryLocation
                u.setLocation(refPlayer.highSeas)
            }
        }
    }

    /// Declare independence (declareIndependence): the player becomes a
    /// rebel, loses Europe and what is there, faces the REF, musters a
    /// continental army where liberty is strong, gains a native friend
    /// and a native enemy, and is offered mercenaries.
    func declareIndependence(_ player: Player, _ nationName: String, _ countryName: String) throws -> ChangeSet {
        guard let spec = game.specification, let europe = player.europe else {
            throw CommandRefused("No Europe to declare independence from")
        }
        let cs = ChangeSet()
        // Cross the Rubicon.
        let oldNation = player.nationLabel
        player.independentNationName = nationName
        player.newLandName = countryName
        player.changePlayerType(.rebel)
        // The whole player is sent, so its history and messages are not.
        let h = HistoryEvent(game.turn, .declareIndependence, player)
        h.score = max(0, (spec.getInteger(GameOptions.independenceTurn) ?? 0) - game.turn.number)
        cs.addGlobalHistory(game, h)
        player.clearModelMessages()
        cs.addMessage(player, ModelMessage(.foreignDiplomacy, "declareIndependence.resolution", player))

        // The units in or bound for Europe are seized.
        var seized = StringTemplate.label(", ")
        var lost = false
        for u in europe.unitList {
            seized = seized.addStringTemplate(u.label)
            try u.csRemove(.only(player), nil, cs)
            lost = true
        }
        for u in (player.highSeas?.unitList ?? []) where u.destination === europe {
            seized = seized.addStringTemplate(u.label)
            try u.csRemove(.only(player), nil, cs)
            lost = true
        }
        if lost {
            cs.addMessage(player, ModelMessage(.unitLost, "declareIndependence.unitsSeized", player)
                .addStringTemplate("%units%", seized))
        }
        player.csLoseLocation(europe, cs)
        player.reinitialiseMarket()

        // The REF.
        guard let refPlayer = createREFPlayer(player) else { throw CommandRefused("No REF nation") }
        cs.addPlayers([refPlayer])
        let monarch = player.monarch
        monarch?.updateInterventionForce()
        let otherKey = randomNonPlayerNationNameKey()
        cs.addMessage(player, ModelMessage(.foreignDiplomacy, "declareIndependence.interventionForce", player)
            .add("%nation%", otherKey)
            .addAmount("%number%", spec.getInteger(GameOptions.interventionBells) ?? 0))
        _ = try player.csChangeStance(.war, refPlayer, true, cs)

        // A continental army musters where liberty is over half.
        for colony in player.colonyList where colony.sonsOfLiberty > 50 {
            let allUnits = colony.allUnitsList
            var limit = (allUnits.count + 2) * (colony.sonsOfLiberty - 50) / 100
            var unitMap = JavaHashMap<String, (type: UnitType, units: [Unit])>(javaHash: JavaString.hashCode)
            for unit in allUnits where unit.unitChange(UnitChangeType.independence) != nil {
                guard let type = unit.type, let tid = type.id else { continue }
                var entry = unitMap[tid] ?? (type: type, units: [])
                entry.units.append(unit)
                unitMap[tid] = entry
            }
            for (_, entry) in unitMap.entries {
                var n = 0
                let fromType = entry.type
                guard let toType = spec.unitChange(UnitChangeType.independence, fromType)?.to else { continue }
                var units = entry.units
                while n < limit && !units.isEmpty {
                    let unit = units.removeFirst()
                    _ = unit.changeType(toType)
                    cs.add(.only(player), unit)
                    n += 1
                }
                cs.addMessage(player, ModelMessage(.unitImproved, "declareIndependence.continentalArmyMuster",
                                                   player, colony)
                    .addName("%colony%", colony.name)
                    .addAmount("%number%", n)
                    .addNamed("%oldUnit%", fromType)
                    .addNamed("%unit%", toType))
                limit -= n
            }
        }

        // The least hostile natives that have met the rebels make peace
        // with them and war on the REF; the most hostile, unless the
        // same, the other way round.
        var natives = game.liveNativePlayers().filter { $0.hasContacted(player) }
            .stableSorted { $0.tension(player).value < $1.tension(player).value }
        if let good = natives.first {
            cs.addMessage(player, ModelMessage(.foreignDiplomacy, "declareIndependence.nativeSupport", good)
                .addStringTemplate("%nation%", good.nationLabel)
                .add("%ruler%", player.rulerNameKey))
            var delta: Int
            switch good.stance(player) {
            case .ceaseFire:
                delta = Tension.Level.happy.limit - good.tension(player).value
            case .war:
                delta = Tension.Level.content.limit - good.tension(player).value
            default:
                delta = 0
            }
            try good.csModifyTension(player, delta, nil, cs)
            Player.makeContact(good, refPlayer)
            try good.csModifyTension(refPlayer, Tension.Level.hateful.limit, nil, cs)
            natives.reverse()
            var bad: Player?
            for p in natives {
                if p === good || p.stance(player) == .alliance { break }
                bad = p
                if !p.atWar(with: player) { break }
            }
            if let bad {
                switch bad.stance(player) {
                case .peace, .ceaseFire:
                    delta = Tension.Level.hateful.limit - bad.tension(player).value
                default:
                    delta = 0
                }
                cs.addMessage(player, ModelMessage(.foreignDiplomacy, "declareIndependence.nativeHostile", bad)
                    .addStringTemplate("%nation%", bad.nationLabel))
                if delta != 0 { try bad.csModifyTension(player, delta, nil, cs) }
                Player.makeContact(bad, refPlayer)
                try bad.csModifyTension(refPlayer, -bad.tension(refPlayer).value, nil, cs)
            }
        }

        // Mercenaries are offered.
        var mercs: [AbstractUnit] = []
        if let monarch {
            let price = monarch.loadMercenaryForce(random, &mercs)
            if price > 0 { player.csMercenaries(price, mercs, .hessianMercenaries, random, cs) }
        }

        // Others are told of the new nation, after its name changes.
        cs.addPartial(.all().except(player), player,
                      ("playerType", player.playerType?.javaName ?? ""),
                      ("independentNationName", player.independentNationName ?? ""),
                      ("newLandName", player.newLandName ?? ""))
        cs.addGlobalMessage(game, player, ModelMessage(.foreignDiplomacy, "declareIndependence.announce", player)
            .addStringTemplate("%oldNation%", oldNation)
            .addStringTemplate("%newNation%", player.nationLabel)
            .add("%ruler%", player.rulerNameKey))
        cs.add(.only(player), player)
        player.invalidateCanSeeTiles()

        // Now Europe can go.  The monarch stays, with the intervention
        // force.
        cs.addRemove(.only(player), nil, europe)
        europe.dispose()

        try sendToOthers(player, cs)
        return cs
    }

    /// The REF gives up, and a rebel is independent (csGiveIndependence):
    /// peace, the REF's land units on the map surrender, and the new
    /// nation sees the whole map.
    func csGiveIndependence(_ ref: Player, _ independent: Player, _ cs: ChangeSet) throws {
        _ = try ref.csChangeStance(.peace, independent, true, cs)
        independent.changePlayerType(.independent)
        independent.setTax(0)
        independent.reinitialiseMarket()
        let h = HistoryEvent(game.turn, .independence, independent)
        // The score is the number of others already independent, made a
        // bonus by the score update.
        h.score = game.liveEuropeanPlayers(excluding: independent).filter { $0.playerType == .independent }.count
        cs.addGlobalHistory(game, h)
        cs.addMessage(independent, ModelMessage(.foreignDiplomacy, "giveIndependence.announce", independent)
            .addStringTemplate("%ref%", ref.nationLabel))
        // Who surrenders?
        var surrendered: [Unit] = []
        for u in ref.units where u.hasTile && !u.isNaval && !u.isOnCarrier
            && (!u.hasAbility(Ability.refUnit) || u.hasAbility(Ability.canBeSurrendered)) {
            if try ref.csChangeOwner(u, independent, UnitChangeType.capture, nil, cs) { surrendered.append(u) }
        }
        for u in surrendered {
            u.movesLeft = 0
            u.setState(.active)
            cs.add(.perhaps().always(ref), u.tile)
        }
        if !surrendered.isEmpty {
            var units = StringTemplate.label(", ")
            for u in surrendered { units = units.addStringTemplate(u.label(.plain)) }
            cs.addMessage(independent, ModelMessage(.foreignDiplomacy, "giveIndependence.unitsAcquired", independent)
                .addStringTemplate("%units%", units))
            independent.invalidateCanSeeTiles()
            ref.invalidateCanSeeTiles()
        }
        // The player type, for the others.
        cs.addPartial(.all().except(independent), independent,
                      ("playerType", independent.playerType?.javaName ?? ""))
        cs.addGlobalMessage(game, independent, ModelMessage(.foreignDiplomacy, "giveIndependence.otherAnnounce",
                                                            independent)
            .addStringTemplate("%nation%", independent.nationLabel)
            .addStringTemplate("%ref%", ref.nationLabel))
        cs.add(.only(independent), independent)
        // The map is revealed.
        cs.add(.only(independent), independent.exploreMap(true))
    }
}

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

/// Dealing with natives: learning, scouting, missions, inciting,
/// tribute, gifts, trade and demands (InGameController and the
/// messages' handlers).
extension InGameController {

    func performNative(_ command: PlayerCommand, by player: Player) throws -> ChangeSet? {
        switch command {
        case let .askSkill(unitId, direction):
            let unit = try ours(player, unitId, Unit.self)
            let settlement = try neighbourSettlement(unit, direction)
            try requireMove(unit, settlement, unit.moveType(settlement.tile), .enterIndianSettlementWithFreeColonist)
            let cs = ChangeSet()
            unit.csVisit(player, settlement, 0, cs)
            settlement.tile?.updateIndianSettlement(player)
            cs.add(.only(player), settlement.tile)
            unit.movesLeft = 0
            cs.addPartial(.only(player), unit, ("movesLeft", String(unit.movesLeft)))
            return cs

        case let .learnSkill(unitId, direction):
            let unit = try ours(player, unitId, Unit.self)
            let settlement = try neighbourSettlement(unit, direction)
            // Not the full move type, as asking took the moves.
            try requireMove(unit, settlement, unit.simpleMoveType(settlement.tile),
                            .enterIndianSettlementWithFreeColonist)
            return try learnFromIndianSettlement(player, unit, settlement)

        case let .scoutIndianSettlement(unitId, direction):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.hasAbility(Ability.speakWithChief) {
                throw CommandRefused("Unit lacks ability to speak to chief: \(unitId ?? "null")")
            }
            let settlement = try neighbourSettlement(unit, direction)
            try requireMove(unit, settlement, unit.moveType(settlement.tile), .enterIndianSettlementWithScout)
            let cs = ChangeSet()
            settlement.tile?.updateIndianSettlement(player)
            cs.add(.only(player), settlement.tile)
            if let owner = settlement.owner {
                cs.add(.only(player), message: NationSummaryMessage(owner, NationSummary(owner, player)))
            }
            return cs

        case let .scoutSpeakToChief(unitId, settlementId):
            let unit = try ours(player, unitId, Unit.self)
            if !unit.hasAbility(Ability.speakWithChief) {
                throw CommandRefused("Unit lacks ability to speak to chief: \(unitId ?? "null")")
            }
            let settlement = try adjacent(unit, settlementId, IndianSettlement.self)
            try requireMove(unit, settlement, unit.moveType(settlement.tile), .enterIndianSettlementWithScout)
            return try scoutSpeakToChief(player, unit, settlement)

        case let .missionary(unitId, direction, denounceString):
            let unit = try ours(player, unitId, Unit.self)
            let settlement = try neighbourSettlement(unit, direction)
            let missionary = settlement.missionary
            let denounce = denounceString == "true"
            if denounce {
                guard let missionary else {
                    throw CommandRefused("Denouncing an empty mission at: \(settlement.id ?? "null")")
                }
                if missionary.owner === player {
                    throw CommandRefused("Denouncing our own missionary at: \(settlement.id ?? "null")")
                }
                if !unit.hasAbility(Ability.denounceHeresy) {
                    throw CommandRefused("Unit lacks denouncement ability: \(unitId ?? "null")")
                }
            } else {
                if missionary != nil {
                    throw CommandRefused("Establishing extra mission at: \(settlement.id ?? "null")")
                }
                if !unit.hasAbility(Ability.establishMission) {
                    throw CommandRefused("Unit lacks establish mission ability: \(unitId ?? "null")")
                }
            }
            try requireMove(unit, settlement, unit.moveType(settlement.tile), .enterIndianSettlementWithMissionary)
            return denounce ? try denounceMission(player, unit, settlement)
                : try establishMission(player, unit, settlement)

        case let .incite(unitId, settlementId, enemyId, goldString):
            let unit = try ours(player, unitId, Unit.self)
            let settlement = try adjacent(unit, settlementId, IndianSettlement.self)
            guard let enemy = game.getFreeColGameObject(enemyId) as? Player else {
                throw CommandRefused("Not a player: \(enemyId ?? "null")")
            }
            if enemy === player { throw CommandRefused("Inciting against oneself!") }
            if !enemy.isEuropean { throw CommandRefused("Inciting against non-European!") }
            try requireMove(unit, settlement, unit.moveType(settlement.tile), .enterIndianSettlementWithMissionary)
            // A negative amount asks the price.
            let gold = goldString.flatMap { JavaString.parseInt($0) }.map(Int.init) ?? -1
            return try incite(player, unit, settlement, enemy, gold)

        case let .demandTribute(unitId, direction):
            let unit = try ours(player, unitId, Unit.self)
            if !(unit.isArmed || unit.hasAbility(Ability.demandTribute)) {
                throw CommandRefused("Unit is neither armed nor able to demand tribute: \(unitId ?? "null")")
            }
            let tile = try neighbourTile(unit, direction)
            guard let settlement = tile.indianSettlement else {
                throw CommandRefused("There is native settlement at: \(tile.id ?? "null")")
            }
            let type = unit.moveType(tile)
            if type != .attackSettlement && type != .enterIndianSettlementWithScout {
                throw CommandRefused("Unable to demand tribute at: \(settlement.name ?? ""): \(type.whyIllegal)")
            }
            return try demandTribute(player, unit, settlement)

        case let .deliverGift(unitId, settlementId, goodsElement):
            let unit = try ours(player, unitId, Unit.self)
            let settlement = try adjacent(unit, settlementId, IndianSettlement.self)
            guard let goodsElement else { throw CommandRefused("No goods found") }
            let goods = try Goods(game: game, reading: reader(goodsElement))
            if goods.location !== unit {
                throw CommandRefused("Gift \(goods.id ?? "null") is not with unit \(unitId ?? "null")")
            }
            return try deliverGiftToSettlement(player, unit, settlement, goods)

        case let .nativeGift(unitId, colonyId):
            let unit = try ours(player, unitId, Unit.self)
            let colony = try adjacent(unit, colonyId, Colony.self)
            return try nativeGift(player, unit, colony)

        case let .indianDemand(unitId, colonyId, typeId, amountString, resultName):
            // Read as Java reads an enumerated attribute, in any case; without
            // one it is "done".
            let result: IndianDemandAction? = resultName.flatMap { r in
                IndianDemandAction.allCases.first { $0.javaName == r.uppercased() }
            } ?? .done
            let unit: Unit
            let colony: Colony
            if player.isIndian {
                unit = try ours(player, unitId, Unit.self)
                if unit.movesLeft <= 0 { throw CommandRefused("Unit has no moves left: \(unitId ?? "null")") }
                colony = try adjacent(unit, colonyId, Colony.self)
                if result != .done { throw CommandRefused("Result in demand: \(player.id ?? "null")") }
            } else {
                guard let u = game.getFreeColGameObject(unitId) as? Unit else {
                    throw CommandRefused("Not a unit: \(unitId ?? "null")")
                }
                unit = u
                colony = try ours(player, colonyId, Colony.self)
                if result == nil { throw CommandRefused("No result in demand response: \(player.id ?? "null")") }
            }
            let amount = amountString.flatMap { JavaString.parseInt($0) }.map(Int.init) ?? -1
            if amount <= 0 { throw CommandRefused("Bad amount: \(amount)") }
            return try indianDemand(player, unit, colony, game.specification?.getGoodsType(typeId), amount, result)

        case let .nativeTrade(actionName, tradeElement):
            guard let tradeElement else { throw CommandRefused("Null native trade") }
            let nt = try NativeTrade(game: game, reader(tradeElement))
            guard let unit = nt.unit else { throw CommandRefused("Null unit") }
            guard let unitTile = unit.tile else { throw CommandRefused("Unit not on the map: \(unit.id ?? "null")") }
            guard let settlement = nt.indianSettlement else { throw CommandRefused("Null settlement") }
            guard let st = settlement.tile, unitTile.isAdjacent(st) else {
                throw CommandRefused("Unit not adjacent to settlement")
            }
            guard let action = NativeTrade.NativeTradeAction.allCases.first(where: { $0.javaName == actionName }) else {
                throw CommandRefused("Bogus action: \(actionName ?? "null")")
            }
            return try nativeTrade(player, action, nt)

        case let .nationSummary(playerId):
            guard let other = game.getFreeColGameObject(playerId) as? Player else {
                throw CommandRefused("Not a player: \(playerId ?? "null")")
            }
            if other.isIndian && !player.hasContacted(other) { return nil }
            return ChangeSet().add(.only(player), message: NationSummaryMessage(other, NationSummary(other, player)))

        default:
            preconditionFailure("Not a native command: \(command)")
        }
    }

    // MARK: Checks

    /// A reader on an element a command carries.
    func reader(_ element: CommandElement) throws -> FreeColXMLReader {
        let xr = try FreeColXMLReader(string: element.xml)
        try xr.nextTag()
        return xr
    }

    /// The native settlement beside a unit in a direction.
    private func neighbourSettlement(_ unit: Unit, _ direction: String?) throws -> IndianSettlement {
        let tile = try neighbourTile(unit, direction)
        guard let settlement = tile.indianSettlement else {
            throw CommandRefused("There is no native settlement at: \(tile.id ?? "null")")
        }
        return settlement
    }

    private func adjacent<T: Settlement>(_ unit: Unit, _ id: String?, _ type: T.Type) throws -> T {
        switch unit.adjacentSettlement(id, type) {
        case .success(let s): return s
        case .failure(let e): throw CommandRefused(e.description)
        }
    }

    private func requireMove(_ unit: Unit, _ settlement: Settlement, _ type: Unit.MoveType,
                             _ expected: Unit.MoveType) throws {
        if type != expected {
            throw CommandRefused("Unable to enter \(settlement.name ?? ""): \(type.whyIllegal)")
        }
    }

    // MARK: Learning and scouting

    private func learnFromIndianSettlement(_ player: Player, _ unit: Unit, _ settlement: IndianSettlement) throws
        -> ChangeSet {
        guard let spec = game.specification else { return ChangeSet() }
        guard let skill = settlement.learnableSkill else {
            throw CommandRefused("No skill to learn at \(settlement.name ?? "")")
        }
        if unit.unitChange(UnitChangeType.natives, skill) == nil {
            throw CommandRefused("Unit \(unit.id ?? "null") can not learn skill \(skill.id ?? "") at \(settlement.name ?? "")")
        }
        let cs = ChangeSet()
        unit.movesLeft = 0
        let loc = unit.location
        switch settlement.alarm(player)?.level ?? .happy {
        case .hateful:
            // Killed, which others might see.
            cs.add(.perhaps().always(player), loc as? FreeColGameObject)
            try unit.csRemove(.perhaps().always(player), loc, cs)
            player.invalidateCanSeeTiles()
        case .angry:
            // Nothing learnt.
            cs.addPartial(.only(player), unit, ("movesLeft", String(unit.movesLeft)))
        default:
            _ = unit.changeType(skill)
            player.invalidateCanSeeTiles()
            cs.add(.perhaps(), unit)
            if !settlement.isCapital
                && !(settlement.hasMissionary(player) && spec.getBoolean(GameOptions.enhancedMissionaries)) {
                settlement.learnableSkill = nil
            }
        }
        settlement.tile?.updateIndianSettlement(player)
        cs.add(.only(player), settlement.tile)
        try sendToOthers(player, cs)
        return cs
    }

    private func scoutSpeakToChief(_ player: Player, _ unit: Unit, _ settlement: IndianSettlement) throws
        -> ChangeSet {
        guard let tile = settlement.tile, let spec = game.specification else { return ChangeSet() }
        let cs = ChangeSet()
        var tileDirty = settlement.setVisited(player)
        let result: String
        if settlement.alarm(player)?.level == .hateful {
            let loc = unit.location
            cs.add(.perhaps().always(player), loc as? FreeColGameObject)
            try unit.csRemove(.perhaps().always(player), loc, cs)
            player.invalidateCanSeeTiles()
            result = "die"
        } else {
            let scoutSkill = spec.unitTypes(withAnyAbility: Ability.expertScout).first
            var radius = unit.lineOfSight
            let skill = settlement.learnableSkill
            let rnd = RandomUtils.randomInt("scouting", random, 10)
            if settlement.hasAnyScouted {
                result = "nothing"
            } else if let scoutSkill, unit.type !== scoutSkill,
                      (skill?.hasAbility(Ability.expertScout) ?? false) || rnd == 0 {
                _ = unit.changeType(scoutSkill)
                player.invalidateCanSeeTiles()
                result = "expert"
            } else {
                var gold = settlement.type?.gifts?.amount("Base beads amount", random, continuous: true) ?? 0
                if gold <= 0 || rnd <= 3 {
                    radius = max(radius, IndianSettlement.talesRadius)
                    result = "tales"
                } else {
                    if unit.hasAbility(Ability.expertScout) { gold = (gold * 11) / 10 }
                    _ = player.modifyGold(gold)
                    _ = settlement.owner?.modifyGold(-gold)
                    result = String(gold)
                    cs.addPartial(.only(player), player, ("gold", String(player.gold)),
                                  ("score", String(player.score)))
                }
            }
            unit.csVisit(player, settlement, 1, cs)
            tileDirty = true
            let tiles = tile.surroundingTiles(1, radius).filter { !player.canSee($0) && ($0.isLand || $0.isShore) }
            cs.add(.only(player), player.exploreTiles(JavaTileSet(tiles).tiles))
            unit.movesLeft = 0
            if result == "expert" {
                cs.add(.perhaps(), unit)
            } else {
                cs.addPartial(.only(player), unit, ("movesLeft", String(unit.movesLeft)))
            }
        }
        if tileDirty {
            tile.updateIndianSettlement(player)
            cs.add(.only(player), tile)
        }
        cs.add(.only(player), message: ScoutSpeakToChiefMessage(unit, settlement, result))
        try sendToOthers(player, cs)
        return cs
    }

    // MARK: Missions and inciting

    private func establishMission(_ player: Player, _ unit: Unit, _ settlement: IndianSettlement) throws
        -> ChangeSet {
        let cs = ChangeSet()
        unit.csVisit(player, settlement, 0, cs)
        let tension = settlement.alarm(player) ?? Tension()
        let loc = unit.location
        switch tension.level {
        case .hateful, .angry:
            cs.add(.perhaps().always(player), loc as? FreeColGameObject)
            try unit.csRemove(.perhaps().always(player), loc, cs)
            player.invalidateCanSeeTiles()
        case .happy, .content, .displeased:
            if settlement.hasMissionary { try settlement.csKillMissionary(false, cs) }
            cs.add(.perhaps().always(player), unit.tile)
            try settlement.csChangeMissionary(unit, cs)
        }
        cs.addMessage(player, ModelMessage(.foreignDiplomacy, "indianSettlement.mission." + tension.key, player, unit)
            .addStringTemplate("%nation%", settlement.owner?.nationLabel))
        try sendToOthers(player, cs)
        return cs
    }

    private func denounceMission(_ player: Player, _ unit: Unit, _ settlement: IndianSettlement) throws
        -> ChangeSet {
        let cs = ChangeSet()
        unit.csVisit(player, settlement, 0, cs)
        guard let missionary = settlement.missionary, let enemy = missionary.owner else {
            throw CommandRefused("Denouncing null missionary")
        }
        var denounce = RandomUtils.randomDouble("Denounce base", random) * Double(enemy.immigration)
            / Double(player.immigration + 1)
        if missionary.hasAbility(Ability.expertMissionary) { denounce += 0.2 }
        if unit.hasAbility(Ability.expertMissionary) { denounce -= 0.2 }
        if denounce < 0.5 {
            // The old mission goes, and ours takes its place.
            return try establishMission(player, unit, settlement)
        }
        let owner = settlement.owner
        cs.add(.only(player), settlement)
        cs.addMessage(player, ModelMessage(.foreignDiplomacy, "indianSettlement.mission.noDenounce", player, unit)
            .addStringTemplate("%nation%", owner?.nationLabel))
        cs.addMessage(enemy, ModelMessage(.foreignDiplomacy, "indianSettlement.mission.enemyDenounce", enemy,
                                          settlement)
            .addStringTemplate("%enemy%", player.nationLabel)
            .addStringTemplate("%settlement%", locationLabel(settlement, for: enemy))
            .addStringTemplate("%nation%", owner?.nationLabel))
        cs.add(.perhaps().always(player), unit.location as? FreeColGameObject)
        try unit.csRemove(.perhaps().always(player), unit.location, cs)
        player.invalidateCanSeeTiles()
        try sendToOthers(player, cs)
        return cs
    }

    private func incite(_ player: Player, _ unit: Unit, _ settlement: IndianSettlement, _ enemy: Player,
                        _ gold: Int) throws -> ChangeSet {
        let cs = ChangeSet()
        unit.csVisit(player, settlement, 0, cs)
        settlement.tile?.updateIndianSettlement(player)
        cs.add(.only(player), settlement.tile)
        guard let nativePlayer = settlement.owner else { return cs }
        let payingValue = nativePlayer.tension(player).value
        let targetValue = nativePlayer.tension(enemy).value
        var goldToPay = payingValue > targetValue ? 10000 : 5000
        goldToPay += 20 * (payingValue - targetValue)
        goldToPay = max(goldToPay, 650)
        if gold < 0 {
            // Asking the price.
            cs.add(.only(player), message: InciteMessage(unit, settlement, enemy, goldToPay))
        } else if gold < goldToPay || !player.checkGold(gold) {
            cs.addMessage(player, ModelMessage(.foreignDiplomacy, "missionarySettlement.inciteGoldFail", player,
                                               settlement)
                .addStringTemplate("%player%", enemy.nationLabel)
                .addAmount("%amount%", goldToPay))
            unit.movesLeft = 0
            cs.addPartial(.only(player), unit, ("movesLeft", String(unit.movesLeft)))
        } else {
            try nativePlayer.csModifyTension(enemy, Tension.warModifier, nil, cs)
            try enemy.csModifyTension(player, Tension.tensionAddWarInciter, nil, cs)
            _ = player.modifyGold(-gold)
            _ = nativePlayer.modifyGold(gold)
            cs.addMessage(player, ModelMessage(.foreignDiplomacy, "missionarySettlement.inciteSuccess", nativePlayer)
                .addStringTemplate("%native%", nativePlayer.nationLabel)
                .addStringTemplate("%enemy%", enemy.nationLabel))
            cs.addPartial(.only(player), player, ("gold", String(player.gold)))
            unit.movesLeft = 0
            cs.addPartial(.only(player), unit, ("movesLeft", String(unit.movesLeft)))
        }
        try sendToOthers(player, cs)
        return cs
    }

    private func demandTribute(_ player: Player, _ unit: Unit, _ settlement: IndianSettlement) throws -> ChangeSet {
        let turnsPerTribute = 5
        let cs = ChangeSet()
        unit.csVisit(player, settlement, 0, cs)
        guard let indianPlayer = settlement.owner else { return cs }
        var gold = 0
        let year = game.turn.number
        if settlement.lastTribute + turnsPerTribute < year, let gifts = settlement.type?.gifts {
            switch indianPlayer.tension(player).level {
            case .happy, .content:
                gold = min(gifts.amount("Tribute", random, continuous: true) / 10, 100)
            case .displeased:
                gold = min(gifts.amount("Tribute", random, continuous: true) / 20, 100)
            case .angry, .hateful:
                gold = 0 // No tribute.
            }
        }
        try settlement.csModifyAlarm(player, Tension.tensionAddNormal, true, cs)
        settlement.lastTribute = year
        let m: ModelMessage
        if gold > 0 {
            _ = indianPlayer.modifyGold(-gold)
            _ = player.modifyGold(gold)
            cs.addPartial(.only(player), player, ("gold", String(player.gold)), ("score", String(player.score)))
            m = ModelMessage(.foreignDiplomacy, "scoutSettlement.tributeAgree", unit, settlement)
                .addAmount("%amount%", gold)
        } else {
            m = ModelMessage(.foreignDiplomacy, "scoutSettlement.tributeDisagree", unit, settlement)
        }
        cs.addMessage(player, m)
        settlement.tile?.updateIndianSettlement(player)
        cs.add(.only(player), settlement.tile)
        unit.movesLeft = 0
        cs.addPartial(.only(player), unit, ("movesLeft", String(unit.movesLeft)))
        return cs
    }

    // MARK: Gifts and demands

    private func deliverGiftToSettlement(_ player: Player, _ unit: Unit, _ settlement: IndianSettlement,
                                         _ goods: Goods) throws -> ChangeSet {
        guard let session = game.sessions.lookup(NativeTradeSession.key(unit, settlement)) as? NativeTradeSession
        else {
            throw CommandRefused("Trying to deliver gift without opening a session")
        }
        let nt = session.nativeTrade
        if !nt.gift {
            throw CommandRefused("Trying to deliver gift in a session where gift giving is not allowed")
        }
        guard let type = goods.type, let spec = game.specification else { return ChangeSet() }
        let cs = ChangeSet()
        let tile = settlement.tile
        GoodsLocation.moveGoods(unit, type, goods.amount, settlement)
        cs.add(.perhaps(), unit)
        let alarmBonus = -JavaMath.round(Float(settlement.priceToBuy(type, goods.amount)) * 0.001
                                         * Float(spec.getPercentage(GameOptions.alarmBonusGift) ?? 0))
        unit.csVisit(player, settlement, 0, cs)
        try settlement.csModifyAlarm(player, Int(alarmBonus), true, cs)
        settlement.updateWantedGoods()
        tile?.updateIndianSettlement(player)
        cs.add(.only(player), tile)
        nt.gift = true
        let m = ModelMessage(.giftGoods, "deliverGift.goods", settlement, type)
            .addStringTemplate("%player%", player.nationLabel)
            .addNamed("%type%", goods)
            .addAmount("%amount%", goods.amount)
            .addName("%settlement%", settlement.name)
        cs.addMessage(player, m)
        try sendToOthers(player, cs)
        return cs
    }

    private func nativeGift(_ player: Player, _ unit: Unit, _ colony: Colony) throws -> ChangeSet {
        guard let goods = unit.goodsList.first, let type = goods.type else {
            throw CommandRefused("No gift to deliver: \(unit.id ?? "null")")
        }
        guard let otherPlayer = colony.owner else { return ChangeSet() }
        let cs = ChangeSet()
        let amount = goods.amount
        GoodsLocation.moveGoods(unit, type, amount, colony)
        cs.add(.perhaps(), unit)
        cs.addMessage(otherPlayer, ModelMessage(.giftGoods, "deliverGift.goods", colony, type)
            .addStringTemplate("%player%", player.nationLabel)
            .addNamed("%type%", goods)
            .addAmount("%amount%", amount)
            .addName("%settlement%", colony.name))
        cs.add(.only(otherPlayer), colony)
        try sendToOthers(player, cs)
        return cs
    }

    private func indianDemand(_ player: Player, _ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int,
                              _ result: IndianDemandAction?) throws -> ChangeSet {
        let victim = colony.owner
        let key = NativeDemandSession.key(unit, colony)
        let session = game.sessions.lookup(key) as? NativeDemandSession
        let cs = ChangeSet()
        if player.isIndian {
            if session != nil {
                throw CommandRefused("Repeated native demand: \(unit.id ?? "null"),\(colony.id ?? "null")")
            }
            NativeDemandSession.register(unit, colony, type, amount, in: game.sessions)
            cs.add(.only(victim), message: IndianDemandMessage(unit, colony, type, amount, nil))
        } else {
            guard let session else {
                throw CommandRefused("Replying to missing demand: \(unit.id ?? "null"),\(colony.id ?? "null")")
            }
            try session.complete(result == .accept, cs)
        }
        try sendToOthers(player, cs)
        return cs
    }

    // MARK: Trade

    private func nativeTrade(_ player: Player, _ action: NativeTrade.NativeTradeAction, _ incoming: NativeTrade) throws
        -> ChangeSet {
        var nt = incoming
        guard let unit = nt.unit, let settlement = nt.indianSettlement else { return ChangeSet() }
        guard let otherPlayer = player.owns(unit) ? settlement.owner : unit.owner else { return ChangeSet() }
        let session = game.sessions.lookup(NativeTradeSession.key(unit, settlement)) as? NativeTradeSession
        if action.isEuropean != player.isEuropean {
            throw CommandRefused("\(action.isEuropean ? "European" : "Native") player expected for \(action)")
        } else if action == .open && session != nil {
            throw CommandRefused("Session already open")
        } else if action != .open && session == nil {
            throw CommandRefused("No session found")
        }
        let cs = ChangeSet()
        switch action {
        case .open:
            if unit.movesLeft <= 0 { throw CommandRefused("Unit \(unit.id ?? "null") has no moves left.") }
            nt = NativeTradeSession.open(nt, in: game.sessions)
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
        case .close:
            try session!.complete(cs)
        case .buy, .sell, .gift:
            let item = nt.item
            nt.mergeFrom(session!.nativeTrade)
            guard let item else { throw CommandRefused("Null \(action == .buy ? "purchase" : action == .sell ? "sale" : "gift")") }
            switch action {
            case .buy:
                if !nt.canBuy { throw CommandRefused("Can not buy") }
                if !nt.settlementToUnit.contains(where: { Goods.javaEquals($0.goods, item.goods) }) {
                    throw CommandRefused("Item missing for \(action)")
                }
                if !player.checkGold(item.price) { throw CommandRefused("Player can not afford item") }
            case .sell:
                if item.priceIsSet && !nt.canSell { throw CommandRefused("Can not sell") }
                if !nt.unitToSettlement.contains(where: { Goods.javaEquals($0.goods, item.goods) }) {
                    throw CommandRefused("Item missing for \(action)")
                }
            default:
                if !nt.canGift { throw CommandRefused("Can not gift") }
                if !nt.unitToSettlement.contains(where: { Goods.javaEquals($0.goods, item.goods) }) {
                    throw CommandRefused("Item missing for \(action)")
                }
            }
            nt.item = item
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
        case .ackOpen:
            session!.nativeTrade.mergeFrom(nt)
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
            unit.movesLeft = 0
            cs.addPartial(.only(otherPlayer), unit, ("movesLeft", String(unit.movesLeft)))
        case .ackBuyHaggle, .ackSellHaggle, .nakGoods:
            session!.nativeTrade.mergeFrom(nt)
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
        case .ackBuy:
            guard let item = nt.item, let goods = item.goods else { break }
            try csBuy(unit, goods, item.price, settlement, cs)
            nt.buy = false
            nt.addToUnit(item)
            session!.nativeTrade.mergeFrom(nt)
            session!.nativeTrade.buy = false
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
        case .ackSell:
            guard let item = nt.item, let goods = item.goods else { break }
            try csSell(unit, goods, item.price, settlement, cs)
            nt.sell = false
            nt.removeFromUnit(item)
            session!.nativeTrade.mergeFrom(nt)
            session!.nativeTrade.sell = false
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
        case .ackGift:
            guard let item = nt.item, let goods = item.goods else { break }
            try csGift(unit, goods, item.price, settlement, cs)
            nt.gift = false
            nt.removeFromUnit(item)
            session!.nativeTrade.mergeFrom(nt)
            session!.nativeTrade.gift = false
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
        case .nakHaggle, .nakNosale, .nakInvalid, .nakHostile:
            if action == .nakHaggle || action == .nakNosale {
                unit.movesLeft = 0
                cs.addPartial(.only(otherPlayer), unit, ("movesLeft", String(unit.movesLeft)))
            }
            session!.nativeTrade.mergeFrom(nt)
            cs.add(.only(otherPlayer), message: NativeTradeMessage(action, nt))
            try session!.complete(cs)
        }
        try sendToOthers(player, cs)
        return cs
    }

    /// Buy goods from a native settlement (csBuy).
    private func csBuy(_ unit: Unit, _ goods: Goods, _ price: Int, _ settlement: IndianSettlement,
                       _ cs: ChangeSet) throws {
        guard let spec = game.specification, let owner = unit.owner, let type = goods.type else { return }
        let alarmBonus = -JavaMath.round(Float(price) * 0.001 * Float(spec.getPercentage(GameOptions.alarmBonusBuy) ?? 0))
        unit.csVisit(owner, settlement, 0, cs)
        GoodsLocation.moveGoods(settlement, type, goods.amount, unit)
        cs.add(.perhaps(), unit)
        _ = settlement.owner?.modifyGold(price)
        _ = owner.modifyGold(-price)
        try settlement.csModifyAlarm(owner, Int(alarmBonus), true, cs)
        settlement.updateWantedGoods()
        settlement.tile?.updateIndianSettlement(owner)
        cs.add(.only(owner), settlement.tile)
        cs.addPartial(.only(owner), owner, ("gold", String(owner.gold)))
    }

    /// Sell goods to a native settlement (csSell).
    private func csSell(_ unit: Unit, _ goods: Goods, _ price: Int, _ settlement: IndianSettlement,
                        _ cs: ChangeSet) throws {
        guard let spec = game.specification, let owner = unit.owner, let type = goods.type else { return }
        let alarmBonus = -JavaMath.round(Float(price) * 0.001 * Float(spec.getPercentage(GameOptions.alarmBonusSell) ?? 0))
        unit.csVisit(owner, settlement, 0, cs)
        GoodsLocation.moveGoods(unit, type, goods.amount, settlement)
        cs.add(.perhaps(), unit)
        _ = settlement.owner?.modifyGold(-price)
        _ = owner.modifyGold(price)
        try settlement.csModifyAlarm(owner, Int(alarmBonus), true, cs)
        settlement.updateWantedGoods()
        settlement.tile?.updateIndianSettlement(owner)
        cs.add(.only(owner), settlement.tile)
        cs.addPartial(.only(owner), owner, ("gold", String(owner.gold)))
        cs.addSale(owner, settlement, type, Int(JavaMath.round(Float(price) / Float(goods.amount))))
    }

    /// Give goods to a native settlement in trade (csGift).
    private func csGift(_ unit: Unit, _ goods: Goods, _ price: Int, _ settlement: IndianSettlement,
                        _ cs: ChangeSet) throws {
        guard let spec = game.specification, let owner = unit.owner, let type = goods.type else { return }
        let alarmBonus = -JavaMath.round(Float(price) * 0.001 * Float(spec.getPercentage(GameOptions.alarmBonusGift) ?? 0))
        unit.csVisit(owner, settlement, 0, cs)
        GoodsLocation.moveGoods(unit, type, goods.amount, settlement)
        cs.add(.perhaps(), unit)
        try settlement.csModifyAlarm(owner, Int(alarmBonus), true, cs)
        settlement.updateWantedGoods()
        settlement.tile?.updateIndianSettlement(owner)
        cs.add(.only(owner), settlement.tile)
    }
}

/// How a colony answers a native demand (Constants.IndianDemandAction).
public enum IndianDemandAction: JavaEnum {
    case accept, reject, done

    public var javaName: String {
        switch self {
        case .accept: "INDIAN_DEMAND_ACCEPT"
        case .reject: "INDIAN_DEMAND_REJECT"
        case .done: "INDIAN_DEMAND_DONE"
        }
    }
}

extension Unit {
    /// A visit to a native settlement: contact if first, and the
    /// settlement visited and perhaps scouted (csVisit).
    public func csVisit(_ player: Player, _ settlement: IndianSettlement, _ scout: Int, _ cs: ChangeSet) {
        guard let owner = settlement.owner else { return }
        if player.csContact(owner, cs) { try? player.csNativeFirstContact(owner, nil, cs) }
        _ = settlement.setVisited(player)
        if scout > 0 || (scout == 0 && (specification?.getBoolean(GameOptions.settlementActionsContactChief) ?? false)) {
            _ = settlement.setScouted(player)
        }
        // Make the settlement tile current for the player.
        guard let tile = settlement.tile else { return }
        tile.seeTile(player)
        csCheckDiscoverRegion(tile, cs)
    }
}

extension Player {
    /// The colony's answer to a native demand: the demander is told, and
    /// if it is accepted the goods or gold go and the natives calm down
    /// (csCompleteNativeDemand).
    public func csCompleteNativeDemand(_ demandPlayer: Player, _ unit: Unit, _ colony: Colony, _ type: GoodsType?,
                                       _ amount: Int, _ result: IndianDemandAction, _ cs: ChangeSet) throws {
        cs.add(.only(demandPlayer), message: IndianDemandMessage(unit, colony, type, amount, result))
        guard result == .accept else { return }
        if let type {
            GoodsContainer.moveGoods(colony.goodsContainer, type, amount, unit.goodsContainer)
            cs.add(.only(self), colony.goodsContainer)
            cs.add(.only(demandPlayer), unit.goodsContainer)
        } else {
            _ = modifyGold(-amount)
            _ = demandPlayer.modifyGold(amount)
            cs.addPartial(.only(self), self, ("gold", String(gold)))
            cs.addPartial(.only(demandPlayer), demandPlayer, ("gold", String(demandPlayer.gold)))
        }
        let difficulty = specification?.getInteger(GameOptions.nativeDemands) ?? 0
        let tension = -(5 - difficulty) * 50
        if let home = unit.homeIndianSettlement {
            try home.csModifyAlarm(self, tension, true, cs)
        } else {
            try demandPlayer.csModifyTension(self, tension, nil, cs)
        }
    }
}

// MARK: Sessions

/// A trading session between a unit and a native settlement
/// (server/model/NativeTradeSession).
public final class NativeTradeSession: Session {
    private let movesLeft: Int
    public let nativeTrade: NativeTrade

    private init(_ nt: NativeTrade, in sessions: Sessions) {
        movesLeft = nt.unit?.movesLeft ?? 0
        nativeTrade = nt
        super.init(key: NativeTradeSession.key(nt.unit, nt.indianSettlement), in: sessions)
    }

    static func key(_ unit: Unit?, _ settlement: Settlement?) -> String {
        Session.makeKey("NativeTradeSession", unit?.id ?? "", settlement?.id ?? "")
    }

    /// Start a session for a unit and settlement, listing what each
    /// has (openSession).
    static func open(_ nt: NativeTrade, in sessions: Sessions) -> NativeTrade {
        let fresh = NativeTrade(unit: nt.unit!, indianSettlement: nt.indianSettlement!)
        sessions.register(NativeTradeSession(fresh, in: sessions))
        fresh.initialize()
        return fresh
    }

    /// Close, giving the unit its moves back if nothing was traded.
    @discardableResult
    public override func complete(_ cs: ChangeSet) throws -> Bool {
        let ret = try super.complete(cs)
        if nativeTrade.hasNotTraded, let unit = nativeTrade.unit {
            unit.movesLeft = movesLeft
            cs.addPartial(.only(unit.owner), unit, ("movesLeft", String(unit.movesLeft)))
        }
        nativeTrade.setDone()
        return ret
    }
}

/// A native demand of a colony, waiting for its answer
/// (server/model/NativeDemandSession).
///
/// Java also completes it, refused, after a timeout in real time; here
/// that is left to the new turn's completeAll.
public final class NativeDemandSession: Session {
    public unowned let unit: Unit
    public unowned let colony: Colony
    public let type: GoodsType?
    public let amount: Int

    private init(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int, in sessions: Sessions) {
        self.unit = unit
        self.colony = colony
        self.type = type
        self.amount = amount
        super.init(key: NativeDemandSession.key(unit, colony), in: sessions)
    }

    static func key(_ unit: Unit, _ colony: Colony) -> String {
        Session.makeKey("NativeDemandSession", unit.id ?? "", colony.id ?? "")
    }

    @discardableResult
    static func register(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int,
                         in sessions: Sessions) -> NativeDemandSession {
        let s = NativeDemandSession(unit, colony, type, amount, in: sessions)
        sessions.register(s)
        return s
    }

    private func completeInternal(_ result: Bool, _ cs: ChangeSet) throws {
        guard let demandPlayer = unit.owner, let colonyPlayer = colony.owner else { return }
        try colonyPlayer.csCompleteNativeDemand(demandPlayer, unit, colony, type, amount,
                                                result ? .accept : .reject, cs)
    }

    /// Finish with the colony's answer.
    @discardableResult
    public func complete(_ result: Bool, _ cs: ChangeSet) throws -> Bool {
        let ret = try super.complete(cs)
        if !ret { try completeInternal(result, cs) }
        return ret
    }

    /// Finish unanswered, as refused.
    @discardableResult
    public override func complete(_ cs: ChangeSet) throws -> Bool {
        let ret = try super.complete(cs)
        if !ret { try completeInternal(false, cs) }
        return ret
    }
}

// MARK: Messages

/// What a player knows of another nation (NationSummaryMessage).
public final class NationSummaryMessage: ServerMessage {
    public unowned let player: Player
    public let summary: NationSummary

    public init(_ player: Player, _ summary: NationSummary) {
        self.player = player
        self.summary = summary
    }

    public var tag: String { "nationSummary" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("player", player.id ?? "")] }
    public func writeChildren(_ xw: FreeColXMLWriter) { summary.toXML(xw) }
}

/// What came of speaking to a chief (ScoutSpeakToChiefMessage).
public final class ScoutSpeakToChiefMessage: ServerMessage {
    public unowned let unit: Unit
    public unowned let settlement: IndianSettlement
    public let result: String

    public init(_ unit: Unit, _ settlement: IndianSettlement, _ result: String) {
        self.unit = unit
        self.settlement = settlement
        self.result = result
    }

    public var tag: String { "scoutSpeakToChief" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        [("unit", unit.id ?? ""), ("settlement", settlement.id ?? ""), ("result", result)]
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// The price of inciting natives against an enemy (InciteMessage).
public final class InciteMessage: ServerMessage {
    public unowned let unit: Unit
    public unowned let settlement: IndianSettlement
    public unowned let enemy: Player
    public let gold: Int

    public init(_ unit: Unit, _ settlement: IndianSettlement, _ enemy: Player, _ gold: Int) {
        self.unit = unit
        self.settlement = settlement
        self.enemy = enemy
        self.gold = gold
    }

    public var tag: String { "incite" }
    public var priority: MessagePriority { .normal }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        [("unit", unit.id ?? ""), ("settlement", settlement.id ?? ""), ("enemy", enemy.id ?? ""),
         ("gold", String(gold))]
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// A native demand, or its outcome (IndianDemandMessage).
public final class IndianDemandMessage: ServerMessage {
    public unowned let unit: Unit
    public unowned let colony: Colony
    public let type: GoodsType?
    public let amount: Int
    public let result: IndianDemandAction?

    public init(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int, _ result: IndianDemandAction?) {
        self.unit = unit
        self.colony = colony
        self.type = type
        self.amount = amount
        self.result = result
    }

    public var tag: String { "indianDemand" }
    public var priority: MessagePriority { .normal }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] {
        var ret = [("unit", unit.id ?? ""), ("colony", colony.id ?? "")]
        if let type { ret.append(("type", type.id ?? "")) }
        ret.append(("amount", String(amount)))
        // Written as Java writes an enumerated attribute.
        if let result { ret.append(("result", result.javaName.lowercased())) }
        return ret
    }
    public func writeChildren(_ xw: FreeColXMLWriter) {}
}

/// A step in a native trade (NativeTradeMessage).
public final class NativeTradeMessage: ServerMessage {
    public let action: NativeTrade.NativeTradeAction
    public let trade: NativeTrade

    public init(_ action: NativeTrade.NativeTradeAction, _ trade: NativeTrade) {
        self.action = action
        self.trade = trade
    }

    public var tag: String { "nativeTrade" }
    public var priority: MessagePriority { .late }
    public var isAttributeMessage: Bool { true }
    public var attributes: [(key: String, value: String)] { [("action", action.javaName)] }
    public func writeChildren(_ xw: FreeColXMLWriter) { trade.toXML(xw) }
}

extension Goods {
    /// Java's Goods.equals: the same location, type, amount and
    /// identifier.
    public static func javaEquals(_ a: Goods?, _ b: Goods?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.location === b.location && a.type === b.type && a.amount == b.amount && a.id == b.id
    }
}

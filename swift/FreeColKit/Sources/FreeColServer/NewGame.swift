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

extension ServerGame {

    /// Start a new game for one human player, as FreeColServer does: the
    /// game and its map generator from one random source, the player
    /// logging in with the first nation free, then buildGame.
    ///
    /// - Parameters:
    ///   - specification: The rules, with the map generator and game
    ///     options set.
    ///   - random: The server's random source.
    ///   - playerName: The human player's name.
    public static func startNewGame(_ specification: Specification, _ random: JavaRandom,
                                    playerName: String) -> ServerGame {
        let game = newGame(specification, random)
        let generator = SimpleMapGenerator(random)
        // The human logs in (LoginMessage.preGameLogin).
        if let nation = game.vacantNation {
            let human = Player(game: game, nation: nation, admin: game.livePlayers.isEmpty)
            human.name = playerName
            game.addPlayer(human)
            if game.currentPlayer == nil { game.currentPlayer = human }
        }
        game.buildGame(generator, random)
        return game
    }

    /// Fill in the game (FreeColServer.buildGame): a player for every
    /// nation still available, the map, the price options, each
    /// player's starting gold, recruits and prices, and the natives at
    /// peace with each other.
    ///
    /// Java gives each AI player an AI, which takes a seed from the
    /// server's random source as it is made; here the seed is drawn the
    /// same way and kept for when the AI is ported.
    public func buildGame(_ generator: SimpleMapGenerator, _ random: JavaRandom) {
        guard let spec = specification, let options = nationOptions else { return }
        establishUnknownEnemy()
        // The other nations, in the nation options' order.
        for (nation, state) in options.nationStates
        where state != .notAvailable && player(byNationId: nation.id) == nil {
            let player = Player(game: self, nation: nation)
            player.isAI = true
            player.ready = true
            addPlayer(player)
            player.aiSeed = RandomUtils.randomInt("Seed for \(player.id ?? "")", random, Int32.max)
        }
        if map == nil {
            generator.generateMap(self, true)
            spec.generateDynamicOptions()
            for player in livePlayers {
                player.randomizeGame(random)
                if player.isIndian {
                    // The natives know each other.
                    let alarm = (Tension.Level.happy.limit + Tension.Level.content.limit) / 2
                    for other in liveNativePlayers(excluding: player) {
                        _ = player.setStance(other, .peace)
                        for settlement in player.indianSettlementList {
                            settlement.setAlarm(other, Tension(alarm))
                        }
                    }
                }
            }
        }
        // Java's AI then finds the unknown enemy, which is an AI player.
        if let enemy = unknownEnemy, enemy.aiSeed == nil {
            enemy.aiSeed = RandomUtils.randomInt("Seed for \(enemy.id ?? "")", random, Int32.max)
        }
    }
}

extension Player {
    /// The new game's settings for a European (randomizeGame): the
    /// immigration needed, the starting gold, the recruits in Europe,
    /// and starting prices within their options' ranges.
    public func randomizeGame(_ random: JavaRandom) {
        guard isEuropean && !isREF && !isUnknownEnemy, let spec = specification else { return }
        let i0 = spec.getInteger(GameOptions.initialImmigration) ?? 0
        immigrationRequired = Int(JavaMath.toInt(apply(Float(i0), turn: nil, Modifier.religiousUnrestBonus)))
        _ = modifyGold(spec.getInteger(GameOptions.startingMoney) ?? 0)
        europe?.initializeMigration(random)
        guard let market else { return }
        for type in spec.goodsTypeList {
            let prefix = "model.option." + (type.suffix(afterPrefix: "model.goods.") ?? "")
            guard spec.hasOption(prefix + ".minimumPrice", IntegerOption.self),
                  spec.hasOption(prefix + ".maximumPrice", IntegerOption.self),
                  var min = spec.getInteger(prefix + ".minimumPrice"),
                  var max = spec.getInteger(prefix + ".maximumPrice") else { continue }
            if max < min {
                swap(&min, &max)
            } else if max == min {
                continue
            }
            let add = Int(RandomUtils.randomInt("\(type.id ?? "") initial price", random, Int32(max - min)))
            if add > 0 {
                market.setInitialPrice(type, min + add)
                market.update(type)
                market.flushPriceChange(type)
            }
        }
    }
}

extension Europe {
    /// The first recruits: those the options name, then random ones
    /// (ServerEurope.initializeMigration).
    func initializeMigration(_ random: JavaRandom) {
        guard let spec = specification else { return }
        for au in spec.getUnitList(GameOptions.immigrants) { _ = addRecruitable(au, force: true) }
        fillRecruitables(random)
    }
}

extension IndianSettlement {
    /// Goods the natives have gathered, from what their land makes,
    /// more for all but food (addRandomGoods).
    public func addRandomGoods(_ random: JavaRandom) {
        // Java sums them in a HashMap by goods type.
        var goodsMap = JavaHashMap<String, (type: GoodsType, amount: Int)>(javaHash: JavaString.hashCode)
        for tile in ownedTiles {
            for ag in tile.sortedAutoPotential {
                guard let stored = ag.type?.storedAs, let id = stored.id else { continue }
                goodsMap[id] = (stored, (goodsMap[id]?.amount ?? 0) + ag.amount)
            }
        }
        let d = Double(RandomUtils.randomInt("Goods at \(name ?? "")", random, 10)) * 0.1 + 1.0
        for (_, entry) in goodsMap.entries {
            var i = entry.amount
            if !entry.type.isFoodType { i = Int(JavaMath.round(d * Double(entry.amount))) }
            i = min(i, GoodsContainer.cargoSize)
            if i > 0 { _ = addGoods(entry.type, i) }
        }
    }

    /// Braves, between the settlement type's sizes (addUnits).
    public func addUnits(_ random: JavaRandom?) {
        let low = type?.minimumSize ?? 0
        let high = type?.maximumSize ?? 0
        let count = random.map { Int(RandomUtils.randomInt("Units at \(name ?? "")", $0, Int32(high - low + 1))) + low }
            ?? (high + low) / 2
        addUnits(count)
    }

    public func addUnits(_ count: Int) {
        guard let game, let owner, let spec = specification,
              let brave = spec.defaultUnitType(owner.nationType) else { return }
        for _ in 0..<count {
            let unit = Unit(game: game, location: self, owner: owner, type: brave, role: brave.defaultRole)
            unit.changeHomeIndianSettlement(self)
            _ = unit.setLocation(self)
        }
    }
}

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

/// The parts of the server's player (server/model/ServerPlayer) the
/// ported turn processing needs so far.
extension Player {

    /// A name for a new unit (getNameForUnit): ships are named, other
    /// units are not.
    public func nameForUnit(_ type: UnitType, _ random: JavaRandom?) -> String? {
        (game as? ServerGame)?.nameCache.unitName(self, type, random)
    }

    /// Sell goods in Europe, in loads of at most 100 so the price moves
    /// as it goes, taking them from a container (sellInEurope).
    ///
    /// - Returns: The amount added to the market, after trade bonuses.
    public func sellInEurope(_ random: JavaRandom?, _ container: GoodsContainer?, _ type: GoodsType,
                             _ amount: Int) -> Int {
        guard let market, let spec = specification, let game else { return 0 }
        var amount = amount
        var marketAmount = 0
        while amount > 0 {
            let a = min(amount, GoodsContainer.cargoSize)
            let incomeBeforeTaxes = market.salePrice(type, a)
            let incomeAfterTaxes = ((100 - tax) * incomeBeforeTaxes) / 100
            if isAI {
                // The AI's cheat: more profit, falling to none by a turn.
                let cheat = Double(spec.getInteger(GameOptions.tradeProfitMultiplierCheat) ?? 0)
                let cheatTurns = Double(spec.getInteger(GameOptions.tradeProfitMultiplierCheatTurns) ?? 0)
                let multiplier = max(1.0, cheat * (cheatTurns - Double(game.turn.number)) / cheatTurns)
                _ = modifyGold(Int(JavaMath.toInt(Double(incomeAfterTaxes) * multiplier)))
            } else {
                _ = modifyGold(incomeAfterTaxes)
            }
            market.modifySales(type, a)
            _ = container?.addGoods(type, -a)
            market.modifyIncomeBeforeTaxes(type, incomeBeforeTaxes)
            market.modifyIncomeAfterTaxes(type, incomeAfterTaxes)
            let ma = Int(JavaMath.toInt(apply(Float(a), turn: game.turn, "model.modifier.tradeBonus", for: type)))
            market.addGoodsToMarket(type, ma)
            marketAmount += ma
            propagateToEuropeanMarkets(type, a, random)
            amount -= a
        }
        return marketAmount
    }

    /// Buy goods in Europe, in loads of at most 100 so the price moves
    /// as it goes, putting them in a container (buyInEurope).
    ///
    /// - Returns: The amount taken from the market, after trade
    ///   bonuses, or -1 if not even the first load could be paid for.
    public func buyInEurope(_ random: JavaRandom?, _ container: GoodsContainer?, _ type: GoodsType,
                            _ amount: Int) -> Int {
        guard let market, let game else { return -1 }
        var amount = amount
        var marketAmount = 0
        while amount > 0 {
            let a = min(amount, GoodsContainer.cargoSize)
            let price = market.bidPrice(type, a)
            if !checkGold(price) {
                if marketAmount == 0 { return -1 }
                break
            }
            _ = modifyGold(-price)
            market.modifySales(type, -a)
            _ = container?.addGoods(type, a)
            market.modifyIncomeBeforeTaxes(type, -price)
            market.modifyIncomeAfterTaxes(type, -price)
            let ma = Int(JavaMath.toInt(apply(Float(a), turn: game.turn, "model.modifier.tradeBonus", for: type)))
            market.addGoodsToMarket(type, -ma)
            marketAmount += ma
            propagateToEuropeanMarkets(type, -a, random)
            amount -= a
        }
        return marketAmount
    }

    /// Add 5 to 30 percent of some goods traded to the other European
    /// markets (propagateToEuropeanMarkets).
    public func propagateToEuropeanMarkets(_ type: GoodsType, _ amount: Int, _ random: JavaRandom?) {
        guard type.isStorable, let game else { return }
        let lowerBound = 5, upperBound = 30
        let r = random.map {
            Int(RandomUtils.randomInt("Propagate goods", $0, Int32(upperBound - lowerBound + 1))) + lowerBound
        } ?? (lowerBound + upperBound) / 2
        let change = amount * r / 100
        if change == 0 { return }
        for p in game.liveEuropeanPlayers(excluding: self) {
            p.market?.addGoodsToMarket(type, change)
        }
    }

    /// Remove a settlement and give its tiles to its neighbours, after
    /// destroying any mission there (csDisposeSettlement).
    public func csDisposeSettlement(_ settlement: Settlement, _ cs: ChangeSet) throws {
        guard let owner = settlement.owner, let centerTile = settlement.tile else { return }
        let owned = settlement.ownedTiles
        for t in owned { try t.cacheUnseen() }

        // The missionary first.
        var missionaryOwner: Player?
        var radius = 0
        if let native = settlement as? IndianSettlement, let missionary = native.missionary {
            missionaryOwner = missionary.owner
            radius = native.missionaryLineOfSight
            try native.csKillMissionary(true, cs)
        }

        // Off the map and off the owner's list.
        settlement.exciseSettlement()
        _ = owner.removeSettlement(settlement)
        precondition(!owner.settlements.contains { $0 === settlement }, "Still has settlement: \(settlement)")

        owner.reassignTiles(owned, avoid: nil)

        var vis = ChangeSet.See.perhaps().always(owner)
        if let missionaryOwner { vis = vis.except(missionaryOwner) }
        cs.add(vis, owned)
        cs.addRemove(vis, centerTile, settlement)
        settlement.dispose()
        owner.invalidateCanSeeTiles()

        // The missionary's owner knows the settlement fell.
        if let missionaryOwner {
            let surrounding = centerTile.surroundingTiles(1, radius).filter { t in !owned.contains { $0 === t } }
            cs.add(.only(missionaryOwner), owned)
            cs.add(.only(missionaryOwner), surrounding)
            cs.addRemove(.only(missionaryOwner), centerTile, settlement)
            missionaryOwner.invalidateCanSeeTiles()
            for t in surrounding { try t.cacheUnseen(except: missionaryOwner) }
        }

        // Only the cleared tiles should show now to the former owner.
        for t in owned { try t.cacheUnseen() }
        // Native settlement tiles are always cached, so clear them for
        // the players who can see the settlement is gone.
        if settlement is IndianSettlement { centerTile.seeTile() }
        if let missionaryOwner { centerTile.seeTile(missionaryOwner) }
    }

    /// Give tiles to the neighbouring settlements that can claim them,
    /// preferring this player's, then those of the same kind of player,
    /// and one settlement last (reassignTiles).
    public func reassignTiles(_ tiles: [Tile], avoid: Settlement?) {
        var claims = JavaHashMap<Tile, Box<Settlement?>>(javaHash: { $0.javaGameObjectHash })
        for tile in tiles {
            let occupier = tile.firstUnit?.owner
            _ = claims.put(tile, Box(nil))
            var votes = JavaHashMap<Settlement, Int>(javaHash: { $0.javaGameObjectHash })
            for t in tile.surroundingTiles(1) {
                guard let claimant = t.owningSettlement, !claimant.isDisposed,
                      let claimantOwner = claimant.owner, claimantOwner.canOwnTile(tile),
                      // An occupying unit's owner alone may claim it.
                      occupier == nil || claimantOwner === occupier,
                      let ct = claimant.tile, ct.distance(to: tile) <= claimant.radius else { continue }
                var value = claimantOwner === self ? 3 : claimantOwner.isEuropean == isEuropean ? 2 : 1
                if let v = votes[claimant] { value += v }
                _ = votes.put(claimant, value)
            }
            var lastResort = false
            var bestValue = 0
            var best: Settlement?
            for e in votes.entries {
                if e.key === avoid {
                    lastResort = true
                    continue
                }
                if bestValue < e.value {
                    bestValue = e.value
                    best = e.key
                }
            }
            if best == nil && lastResort { best = avoid }
            _ = claims.put(tile, Box(best))
        }
        for e in claims.entries {
            let claimant = e.value.value
            e.key.changeOwnership(claimant?.owner, claimant)
        }
    }
}

/// A reference to a value, for maps whose values may be nil.
final class Box<T> {
    let value: T

    init(_ value: T) {
        self.value = value
    }
}

/// Claiming land, losing locations and choosing fathers
/// (server/model/ServerPlayer).
extension Player {

    /// Claim a tile for a settlement, paying for it, or angering the
    /// natives whose land it was if taken (csClaimLand).
    public func csClaimLand(_ tile: Tile, _ settlement: Settlement?, _ price: Int, _ cs: ChangeSet) throws {
        let owner = tile.owner
        let ownerSettlement = tile.owningSettlement
        try tile.cacheUnseen()
        tile.changeOwnership(self, settlement)
        cs.add(.perhaps(), tile)
        if price > 0 {
            _ = modifyGold(-price)
            _ = owner?.modifyGold(price)
            cs.addPartial(.only(self), self, ("gold", String(gold)))
        } else if price < 0, let owner, owner.isIndian {
            if let sis = ownerSettlement as? IndianSettlement {
                try sis.csModifyAlarm(self, Tension.tensionAddLandTaken, true, cs)
            } else {
                try owner.csModifyTension(self, Tension.tensionAddLandTaken, nil, cs)
            }
        }
    }

    /// Drop a lost location from the trade routes, suspending the units
    /// on them (csLoseLocation).
    public func csLoseLocation(_ location: any Location, _ cs: ChangeSet) {
        for tr in tradeRoutes where tr.removeMatchingStops(location) {
            for u in tr.assignedUnits {
                u.tradeRoute = nil
                cs.add(.only(self), u)
            }
            cs.addMessage(self, ModelMessage(.goodsMovement, "combat.tradeRouteSuspended", self)
                .addName("%route%", tr.name)
                .addStringTemplate("%stop%", locationLabel(location)))
            cs.add(.only(self), tr)
        }
    }

    /// Recruit a founding father next (updateCurrentFather).
    public func updateCurrentFather(_ father: FoundingFather?) {
        currentFather = father
        clearOfferedFathers()
    }

    /// Explore some tiles, and tell the player of them (csSeeNewTiles).
    public func csSeeNewTiles(_ tiles: [Tile], _ cs: ChangeSet) {
        exploreTiles(tiles)
        cs.add(.only(self), tiles)
    }

    /// Explore what a settlement can see, which the player need not own
    /// (exploreForSettlement).
    @discardableResult
    public func exploreForSettlement(_ settlement: Settlement) -> [Tile] {
        var tiles = JavaTileSet(copying: settlement.ownedTiles)
        tiles.insert(contentsOf: settlement.javaVisibleTileSet)
        if let t = settlement.tile { tiles.remove(t) }
        return exploreTiles(tiles.tiles)
    }
}

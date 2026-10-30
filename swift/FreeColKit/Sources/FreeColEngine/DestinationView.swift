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

/// A place a unit could be sent to, as Java's SelectDestinationDialog
/// lists it: its name, the turns to get there, and what is of interest
/// there (a mission, prices, a skill to learn, war).
public struct DestinationChoice: Sendable, Equatable {
    public let id: String
    public let name: String
    public let turns: Int
    public let extras: String
    /// "<name> (<turns> turns) <extras>".
    public let text: String
    /// Europe, the map, or one of the player's colonies: what the
    /// dialog shows when only the player's colonies are wanted.
    public let isOwn: Bool
    /// The dialog's order by owner: home first, then the player's
    /// colonies, others' colonies and native settlements.
    let score: Int
    let isSettlement: Bool
}

/// How the destinations are ordered (the dialog's choices).
public enum DestinationOrder: Int, Sendable, CaseIterable {
    case owner, name, distance
}

extension PlayerView {

    /// The mark for the player's own mission ("cross" in Java's
    /// resources).
    static let cross = "\u{271d}"

    /// The places a unit could be sent to (loadDestinations), those it
    /// can not reach dropped, in the dialog's order.
    func destinations(_ unit: Unit, order: DestinationOrder = .owner) -> [DestinationChoice] {
        guard let player = unit.owner, let type = unit.type, let map = game.map else { return [] }
        if unit.isInEurope && !type.canMoveToHighSeas { return [] }
        let goodsTypes = unit.compactGoodsList.compactMap(\.type)
        let inSettlement = unit.settlement
        let canTrade = player.hasAbility(Ability.tradeWithForeignColonies)
        func canReach(_ s: Settlement) -> Bool {
            unit.isNaval ? s.isConnectedPort : Map.isSameContiguity(unit.location?.tile, s.tile)
        }
        var td: [DestinationChoice] = []
        if unit.isInEurope {
            td.append(destination(map, unit.sailTurns, unit, goodsTypes))
        } else if let europe = player.europe, player.canMoveToEurope, type.canMoveToHighSeas {
            let turns = unit.turnsToReach(europe)
            if turns < Unit.manyTurns { td.append(destination(europe, turns, unit, goodsTypes)) }
        }
        for s in player.settlements where s !== inSettlement && canReach(s) {
            td.append(destination(s, unit.turnsToReach(s), unit, goodsTypes))
        }
        // The others' settlements, by a bulk search for their tiles.
        var locs: [any Location] = []
        for p in game.livePlayers(excluding: player) where p.hasContacted(player) && (canTrade || !p.isEuropean) {
            for s in p.settlements where canReach(s) && s.hasContacted(p) {
                if let t = s.tile { locs.append(t) }
            }
        }
        let md = GoalDeciders.MultipleAdjacentDecider(locs)
        _ = unit.search(unit.location, md.goalDecider, nil, Constants.infinity, nil)
        for (_, entry) in md.results.entries {
            guard let s = entry.location.tile?.settlement else { continue }
            var turns = entry.path.totalTurns
            if unit.isInEurope { turns += unit.sailTurns }
            if entry.path.movesLeft < unit.initialMovesLeft { turns += 1 }
            td.append(destination(s, turns, unit, goodsTypes))
        }
        return javaSorted(td.filter { $0.turns < Unit.manyTurns }, order)
    }

    private func destination(_ loc: any Location, _ turns: Int, _ unit: Unit, _ goodsTypes: [GoodsType])
        -> DestinationChoice {
        let owner = unit.owner
        let name = Messages.message(locationLabel(loc, for: owner)) ?? ""
        let extras = destinationExtras(loc, unit, goodsTypes)
        let settlement = loc as? Settlement
        let own = loc is Europe || loc is Map || (loc is Colony && (owner?.owns(settlement) ?? false))
        let score = loc is Europe || loc is Map ? 10
            : loc is Colony ? ((owner?.owns(settlement) ?? false) ? 20 : 30)
            : loc is IndianSettlement ? 40 : 100
        let text = Messages.message(StringTemplate.template("selectDestinationDialog.destinationTurns")
            .addName("%location%", name).addAmount("%turns%", turns).addName("%extras%", extras)) ?? ""
        return DestinationChoice(id: loc.id ?? "", name: name, turns: turns, extras: extras, text: text,
                                 isOwn: own, score: score, isSettlement: settlement != nil)
    }

    /// What is of interest to the unit at a place (getExtras).
    private func destinationExtras(_ loc: any Location, _ unit: Unit, _ goodsTypes: [GoodsType]) -> String {
        guard let owner = unit.owner else { return "" }
        let sep = ", "
        var lb = ""
        var dropSep = false
        if let is_ = loc as? IndianSettlement, is_.hasMissionary(owner) { lb += PlayerView.cross }
        if loc is Europe && !goodsTypes.isEmpty, let market = owner.market {
            for g in goodsTypes {
                lb += Messages.name(g) + " " + String(market.salePrice(g, 1)) + sep
                dropSep = true
            }
        } else if let s = loc as? Settlement, owner.owns(s) {
            // Nothing.
        } else if let s = loc as? Settlement, s.owner?.atWar(with: owner) ?? false {
            lb += "[" + Messages.name(Player.Stance.war) + "]"
        } else if let s = loc as? Settlement {
            if let is_ = s as? IndianSettlement, let skill = is_.learnableSkill {
                let canLearn: (Unit) -> Bool = { $0.unitChange(UnitChangeType.natives) != nil }
                let up = unit.isCarrier ? unit.unitList.first(where: canLearn) : canLearn(unit) ? unit : nil
                if up != nil { lb += "[" + Messages.name(skill) + "]" }
            }
            for g in goodsTypes {
                let sale = owner.lastSaleString(s, g)
                var more: String?
                if let is_ = s as? IndianSettlement {
                    more = g === is_.wantedGoods(0) ? "***" : g === is_.wantedGoods(1) ? "**"
                        : g === is_.wantedGoods(2) ? "*" : nil
                }
                if let sale, let more {
                    lb += Messages.name(g) + " " + sale + more + sep
                    dropSep = true
                }
            }
        }
        if dropSep && lb.hasSuffix(sep) { lb.removeLast(sep.count) }
        return lb
    }

    /// Sort as the dialog's comparators do, stably as Java's List.sort.
    private func javaSorted(_ list: [DestinationChoice], _ order: DestinationOrder) -> [DestinationChoice] {
        func byName(_ a: DestinationChoice, _ b: DestinationChoice) -> Int {
            if !a.isSettlement { return -1 }
            if !b.isSettlement { return 1 }
            return a.name < b.name ? -1 : a.name == b.name ? 0 : 1
        }
        func compare(_ a: DestinationChoice, _ b: DestinationChoice) -> Int {
            switch order {
            case .name: return byName(a, b)
            case .distance: return a.turns != b.turns ? (a.turns < b.turns ? -1 : 1) : byName(a, b)
            case .owner: return a.score != b.score ? (a.score < b.score ? -1 : 1) : byName(a, b)
            }
        }
        return list.stableSorted { compare($0, $1) < 0 }
    }
}

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

/// The names the server hands out (common/i18n/NameCache): so far
/// ship and settlement names, and the mercenary leaders.
///
/// Java keeps these in static fields, shared by every game in the
/// program; here each server game has its own, which is the same for
/// a program playing one game.  Each player's ship names are collected
/// from the messages and shuffled when the player first names a ship.
public final class NameCache {

    private var shipNames: [ObjectIdentifier: [String]] = [:]
    private var settlementNames: [ObjectIdentifier: [String]] = [:]
    private var capitalNames: [ObjectIdentifier: String] = [:]
    private var mercenaryLeaders: [String]?
    private var regionNames: [String: [String]] = [:]
    private var regionIndex: [String: Int] = [:]
    private var riverNames: [String]?
    private var rumourNothingKeys: [String]?

    public init() {}

    /// All the messages with a prefix and a number, from 0 or 1 up to
    /// the first missing (collectNames).
    private static func collectNames(_ prefix: String) -> [String] {
        var names: [String] = []
        if Messages.containsKey(prefix + "0") { names.append(Messages.message(prefix + "0")) }
        var i = 1
        while Messages.containsKey(prefix + String(i)) {
            names.append(Messages.message(prefix + String(i)))
            i += 1
        }
        return names
    }

    /// A name for a new unit: ships are named, from the player's
    /// nation's ship names not yet in use, or else a numbered fallback
    /// (getUnitName).
    public func unitName(_ player: Player, _ type: UnitType, _ random: JavaRandom?) -> String? {
        if !type.isNaval || player.isREF { return nil }
        let key = ObjectIdentifier(player)
        if shipNames[key] == nil {
            var names = NameCache.collectNames((player.nationId ?? "null") + ".ship.")
            if let random { RandomUtils.randomShuffle("Ship names", &names, random) }
            shipNames[key] = names
        }
        while !shipNames[key]!.isEmpty {
            let name = shipNames[key]!.removeFirst()
            if player.unit(byName: name) == nil { return name }
        }
        let base = Messages.message("nameCache.base.ship") + "-"
        var i = 1
        while player.unit(byName: base + String(i)) != nil { i += 1 }
        return base + String(i)
    }

    /// Collect a player's settlement names, when first needed: for
    /// Europeans those of the rules then the general ones, in order; for
    /// natives the capital first and the rest shuffled
    /// (requireSettlementNames).
    private func requireSettlementNames(_ player: Player, _ random: JavaRandom?) {
        let key = ObjectIdentifier(player)
        if settlementNames[key] != nil { return }
        let nation = player.nationId ?? "null"
        var names: [String] = []
        if player.isEuropean {
            let specId = player.specification?.id ?? "null"
            names = NameCache.collectNames(nation + ".settlementName." + specId + ".")
            names += NameCache.collectNames(nation + ".settlementName.")
            if names.isEmpty && specId != "freecol" {
                names = NameCache.collectNames(nation + ".settlementName.freecol.")
            }
        } else {
            names = NameCache.collectNames(nation + ".settlementName.")
            if !names.isEmpty {
                capitalNames[key] = names.removeFirst()
                if let random { RandomUtils.randomShuffle("Native settlement names", &names, random) }
            }
        }
        settlementNames[key] = names
    }

    /// A name for a new settlement, not yet used, or a numbered
    /// fallback (getSettlementName).
    public func settlementName(_ player: Player, _ random: JavaRandom?) -> String {
        requireSettlementNames(player, random)
        let key = ObjectIdentifier(player)
        let game = player.game
        while !settlementNames[key]!.isEmpty {
            let name = settlementNames[key]!.removeFirst()
            if game?.settlement(byName: name) == nil { return name }
        }
        let base = Messages.message(player.isEuropean ? "nameCache.base.colony" : "nameCache.base.settlement") + "-"
        var i = player.settlementCount + 1
        while game?.settlement(byName: base + String(i)) != nil { i += 1 }
        return base + String(i)
    }

    /// A name for a region a player discovered: its own, if it has one,
    /// or the next unused of the nation's names for its type, the
    /// extra river names, or a numbered name (getRegionName).
    ///
    /// Java shuffles the extra river names with its global generator,
    /// so which comes first can not be repeated; here they come in
    /// order.
    public func regionName(_ player: Player, _ region: Region) -> String {
        if region.hasName { return Messages.message(region.label) ?? "" }
        let map = player.game?.map
        let type = region.type
        let prefix = (player.nationId ?? "null") + ".region."
            + JavaString.lastPart(type?.key ?? "", ".") + "."
        if regionNames[prefix] == nil {
            regionNames[prefix] = NameCache.collectNames(prefix)
        }
        if regionIndex[prefix] == nil { regionIndex[prefix] = regionNames[prefix]!.count + 1 }
        while !regionNames[prefix]!.isEmpty {
            let name = regionNames[prefix]!.removeFirst()
            if map?.region(byName: name) == nil { return name }
        }
        if type == .river {
            if riverNames == nil { riverNames = NameCache.collectNames("model.other.region.river.") }
            while !riverNames!.isEmpty {
                let name = riverNames!.removeFirst()
                if map?.region(byName: name) == nil { return name }
            }
        }
        var index = regionIndex[prefix]!
        var name: String
        repeat {
            var template = StringTemplate.label(" ").addStringTemplate(player.nationLabel)
            if let type { template = template.addNamed(type) }
            name = Messages.message(template.addName(String(index))) ?? ""
            index += 1
        } while map?.region(byName: name) != nil
        regionIndex[prefix] = index
        return name
    }

    /// One of the messages for finding nothing, at random
    /// (getRumourNothingKey).
    public func rumourNothingKey(_ random: JavaRandom) -> String {
        if rumourNothingKeys == nil {
            var keys: [String] = []
            var i = 0
            while Messages.containsKey("model.lostCityRumour.nothing.\(i).description") {
                keys.append("model.lostCityRumour.nothing.\(i).description")
                i += 1
            }
            rumourNothingKeys = keys
        }
        return RandomUtils.randomMember("nothingKey", rumourNothingKeys!, random) ?? ""
    }

    private var leaders: [String] {
        if mercenaryLeaders == nil { mercenaryLeaders = NameCache.collectNames("nameCache.mercenaries.") }
        return mercenaryLeaders!
    }

    /// A mercenary leader at random (getMercenaryLeaderIndex).
    public func mercenaryLeaderIndex(_ random: JavaRandom) -> Int {
        Int(RandomUtils.randomInt("Mercenary leader", random, Int32(leaders.count)))
    }

    public func mercenaryLeaderName(_ index: Int) -> String {
        leaders[index]
    }
}

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

/// A unit's new turn and the server's unit actions the turn needs
/// (server/model/ServerUnit).
extension Unit {


    /// Repair one hit point, telling the owner when done (csRepairUnit).
    public func csRepairUnit(_ cs: ChangeSet) {
        guard let owner else { return }
        hitPoints += 1
        if !isDamaged, let loc = location?.up() {
            cs.addMessage(owner, ModelMessage(.unitRepaired, "model.unit.unitRepaired", self,
                                              loc as? FreeColGameObject)
                .addStringTemplate("%unit%", label)
                .addStringTemplate("%repairLocation%", locationLabel(loc, for: owner)))
            setState(.active)
        }
        cs.addPartial(.only(owner), self, ("hitPoints", String(hitPoints)))
    }

    /// Remove this unit from the game (csRemove).
    public func csRemove(_ see: ChangeSet.See, _ location: (any Location)?, _ cs: ChangeSet) throws {
        if let home = changeHomeIndianSettlement(nil) { cs.add(.only(owner), home) }
        cs.addRemove(see, location, self)
        dispose()
    }

    // MARK: The new turn

    /// The unit's new turn (csNewTurn): attrition, promotion by
    /// experience, moves, work on improvements, arriving from the high
    /// seas, and fortifying.
    public func csNewTurn(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let spec = specification, let owner, let type else { return }
        let loc = location
        var locDirty = false
        var unitDirty = false

        // Attrition first, as the unit might die.
        if type.hasMaximumAttrition, let tile = loc as? Tile, !tile.hasSettlement {
            attrition += 1
            if attrition > type.maximumAttrition {
                cs.addMessage(owner, ModelMessage(.unitLost, "model.unit.attrition", self)
                    .addStringTemplate("%unit%", label)
                    .addStringTemplate("%location%", locationLabel(loc, for: owner)))
                cs.add(.perhaps(), tile)
                try csRemove(.perhaps().always(owner), loc, cs)
                owner.invalidateCanSeeTiles()
                return
            }
        } else {
            attrition = 0
        }

        // Promotion by experience.
        if isInColony, let produce = workType, let learn = spec.expert(producing: produce), learn !== type,
           let uc = unitChange(UnitChangeType.experience, learn), uc.probability > 0 {
            let maximumExperience = type.maximumExperience
            let maxValue = (100 * maximumExperience) / uc.probability
            if maxValue > 0
                && Int(RandomUtils.randomInt("Experience", random, Int32(maxValue))) < min(experience, maximumExperience) {
                let oldName = label
                _ = changeType(learn)
                if let colony {
                    cs.addMessage(owner, ModelMessage(.unitImproved, "model.unit.experience", colony, self)
                        .addStringTemplate("%oldName%", oldName)
                        .addStringTemplate("%unit%", label)
                        .addName("%colony%", colony.name))
                }
                unitDirty = true
            }
        }

        // Moves.
        if isInMission {
            tile?.updateIndianSettlement(owner)
            movesLeft = 0
        } else if isDamagedAndUnderForcedRepair {
            movesLeft = 0
        } else {
            movesLeft = initialMovesLeft
        }

        if workLeft > 0 {
            unitDirty = true
            if state == .improving {
                // Done already (perhaps by another unit)?  Then stop.
                if let ti = workImprovement, !ti.isComplete {
                    let amount = type.hasAbility(Ability.expertPioneer) ? 2 : 1
                    let turns = max(0, ti.turnsToComplete - amount)
                    ti.turnsToComplete = turns
                    workLeft = turns
                    if ti.isRoad && ti.isComplete {
                        _ = ti.updateRoadConnections(true)
                        for t in loc?.tile?.surroundingTiles(1, 1) ?? [] where t.hasRoad {
                            cs.add(.perhaps(), t)
                        }
                        locDirty = true
                    }
                } else {
                    setState(.active)
                    workLeft = -1
                }
            } else {
                workLeft -= 1
            }
            // The REF crosses at once.
            if loc is HighSeas && owner.isREF { workLeft = 0 }
        }

        if state == .skipped {
            setState(.active)
            unitDirty = true
        }

        if workLeft <= 0 {
            if location is HighSeas {
                let europe = owner.europe
                let result = resolveDestination()
                if let europe, result === europe {
                    if tradeRoute == nil {
                        destination = nil
                        cs.addMessage(owner, ModelMessage(.unitArrived, "model.unit.arriveInEurope", europe, self)
                            .add("%europe%", europe.nameKey))
                    }
                    setState(.active)
                    _ = setLocation(europe)
                    cs.add(.only(owner), owner.highSeas)
                    locDirty = true
                } else {
                    let dst = destination
                    var target = result?.tile
                    if !(result is Tile) { target = fullEntryLocation }
                    if let tile = target?.safeTile(owner, random) {
                        if dst is Map { destination = nil }
                        try csMove(tile, random, cs)
                    }
                    locDirty = false // The move updates the location.
                    unitDirty = false
                }
            } else {
                switch state {
                case .active, .fortified, .sentry, .inColony:
                    break // Stable.
                case .improving:
                    try csImproveTile(random, cs)
                    workImprovement = nil
                    locDirty = true
                case .fortifying:
                    setState(.fortified)
                    unitDirty = true
                case .skipped:
                    setState(.active)
                    unitDirty = true
                }
            }
        }

        if locDirty {
            cs.add(.perhaps(), location as? FreeColGameObject)
        } else if unitDirty {
            cs.add(.perhaps(), self)
        } else {
            cs.addPartial(.only(owner), self, ("movesLeft", String(movesLeft)))
        }
    }

    /// Finish improving the unit's tile (csImproveTile): goods for the
    /// owner's settlement, the tile's new type, perhaps a resource
    /// found, tools used up, and others doing the same stopped.
    private func csImproveTile(_ random: JavaRandom, _ cs: ChangeSet) throws {
        guard let game, let owner, let tile, let ti = workImprovement, let tiType = ti.type else { return }
        try tile.cacheUnseen()
        if let deliver = tiType.production(from: tile.type), let goodsType = deliver.type {
            // Goods for the settlement owning the tile, if it is ours.
            var amount = Int(JavaMath.toInt(apply(Float(deliver.amount), turn: game.turn,
                                                  Modifier.tileTypeChangeProduction, for: goodsType)))
            if let settlement = tile.owningSettlement, owner.owns(settlement) {
                amount = Int(JavaMath.toInt(settlement.apply(Float(amount), turn: game.turn,
                                                             Modifier.tileTypeChangeProduction, for: goodsType)))
                _ = settlement.addGoods(goodsType, amount)
            }
        }

        // Changes such as clearing a forest happen now; roads are
        // already there.
        if let changeType = ti.change(tile.type) { tile.changeType(changeType) }

        // Perhaps a resource is found.
        let exposeResource = tiType.exposeResourcePercent
        if exposeResource > 0 && !tile.hasResource,
           Int(RandomUtils.randomInt("Expose resource", random, 100)) < exposeResource,
           let resType = RandomChoice.weightedRandom("Resource type", tile.type?.resourceTypes ?? [], random) {
            let minValue = resType.minValue, maxValue = resType.maxValue
            let value = minValue + (minValue == maxValue ? 0
                : Int(RandomUtils.randomInt("Resource quantity", random, Int32(maxValue - minValue + 1))))
            tile.addResource(Resource(game: game, tile: tile, type: resType, quantity: value))
        }

        // Tools used up.
        if changeRoleCount(-tiType.expendedAmount) {
            var messageId = "\(type?.id ?? "null").noMoreTools"
            if !Messages.containsKey(messageId) { messageId = "model.unit.noMoreTools" }
            cs.addMessage(owner, ModelMessage(.warning, messageId, self)
                .addStringTemplate("%unit%", label)
                .addStringTemplate("%location%", locationLabel(location, for: owner)))
        }

        // Others making the same improvement here stop.
        for unit in tile.unitList where unit.workImprovement?.type === tiType && unit.state == .improving {
            unit.workLeft = -1
            unit.workImprovement = nil
            unit.setState(.active)
            unit.movesLeft = 0
        }
    }
}

extension Unit {
    /// Board a carrier, perhaps from a neighbouring tile (csEmbark).
    public func csEmbark(_ carrier: Unit, _ cs: ChangeSet) throws {
        guard let owner else { return }
        let oldLocation = location
        let colony = oldLocation is WorkLocation ? self.colony : nil
        if colony != nil { try oldLocation?.tile?.cacheUnseen() }
        _ = setLocation(carrier)
        movesLeft = 0
        cs.add(.only(owner), colony ?? (oldLocation as? FreeColGameObject))
        if carrier.location !== oldLocation { cs.add(.only(owner), carrier) }
        if let oldTile = oldLocation as? Tile {
            if let tile = carrier.tile, tile !== oldTile {
                cs.addMove(.only(owner), self, oldTile, tile)
                owner.invalidateCanSeeTiles()
            }
            cs.addDisappear(owner, oldTile, self)
        }
    }
}

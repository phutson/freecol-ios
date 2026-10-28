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
import FreeColServer

/// What the colony panel does when the player moves colonists, changes
/// their work or the build queue (ColonyPanel, and the client
/// InGameController's work, putOutsideColony, changeWorkType,
/// setBuildQueue and claimTile).
extension PlayController {

    /// Put a colonist to work in a building or on a tile of its colony
    /// (ASingleBuildingPanel.tryWork and ASingleTilePanel.tryWork):
    /// claiming the tile first if need be, then working there at the
    /// work the place suits best, and saying if another tile would do
    /// better.
    func work(_ unitId: String, at workLocationId: String) {
        guard ourTurn, unit(unitId) != nil,
              let wl = view.game.getFreeColGameObject(workLocationId) as? WorkLocation,
              let colony = wl.colony else { return }
        let colonyId = colony.id
        if let ct = wl as? ColonyTile, let tile = ct.workTile {
            if tile.owningSettlement !== colony {
                switch view.player.canClaimForSettlementReason(tile) {
                case .none, .natives:
                    guard claimForColony(tile, colonyId) else { return }
                case let reason:
                    tell(.key("model.noClaimReason.\(reason.javaName.lowercased()).description"))
                    return
                }
            }
            guard let u = unit(unitId), let ct = workLocation(workLocationId) as? ColonyTile else { return }
            let reason = ct.noAddReason(u)
            if reason != .none {
                tell(.template(reason.descriptionKey))
                return
            }
            guard tryWork(unitId, workLocationId) else { return }
            // Say if another tile would make more of this work.
            if let u = unit(unitId), let workType = u.workType, let ct = workLocation(workLocationId),
               let best = ct.colony?.workLocation(for: u, workType), best !== ct,
               ct.potentialProduction(workType, u.type) < best.potentialProduction(workType, u.type) {
                tell(StringTemplate.template("colonyPanel.notBestTile")
                    .addStringTemplate("%unit%", u.label(.national)).addNamed("%goods%", workType)
                    .addStringTemplate("%tile%", (best as? ColonyTile)?.label ?? (best as? Building)?.label))
            }
        } else if let building = wl as? Building, let u = unit(unitId) {
            let reason = building.noAddReason(u)
            if reason != .none {
                tell(.key(reason.descriptionKey))
                return
            }
            _ = tryWork(unitId, workLocationId)
        }
        updateProduction(colonyId)
    }

    private func workLocation(_ id: String) -> WorkLocation? {
        view.game.getFreeColGameObject(id) as? WorkLocation
    }

    /// Work somewhere, then change to the work the place suits best
    /// (ColonyPanel.tryWork).
    private func tryWork(_ unitId: String, _ workLocationId: String) -> Bool {
        guard let u = unit(unitId), let wl = workLocation(workLocationId) else { return false }
        let workType = wl.work(for: u)
        guard clientWork(unitId, workLocationId) else { return false }
        if let workType, unit(unitId)?.workType !== workType {
            changeWorkType(unitId, workType.id ?? "")
        }
        return true
    }

    /// Ask the server for a colonist to work somewhere
    /// (InGameController.work).
    private func clientWork(_ unitId: String, _ workLocationId: String) -> Bool {
        guard ourTurn, let u = unit(unitId), let wl = workLocation(workLocationId) else { return false }
        if u.student != nil && !confirmAbandonEducation(unitId, leaveColony: false) { return false }
        if let tile = wl.workTile {
            if tile.hasLostCityRumour {
                tell(.key("tileHasRumour"))
                return false
            }
            if !view.player.owns(tile), let colonyId = wl.colony?.id, !claimForColony(tile, colonyId) {
                return false
            }
        }
        let ret = command(.work(unit: unitId, workLocation: workLocationId))
            && unit(unitId)?.location?.id == workLocationId
        if ret { updateGUI() }
        return ret
    }

    /// Claim a tile for a colony, free if the colony may simply take it
    /// (InGameController.claimTile).
    private func claimForColony(_ tile: Tile, _ colonyId: String?) -> Bool {
        guard let colonyId else { return false }
        let player = view.player
        let price = player.canClaimForSettlement(tile) ? 0 : player.landPrice(tile)
        let ret = claimTile(tile, claimant: colonyId, price: price)
        if ret { updateGUI() }
        return ret
    }

    /// Change what a colonist works at (InGameController.changeWorkType).
    @discardableResult
    func changeWorkType(_ unitId: String, _ goodsTypeId: String) -> Bool {
        guard ourTurn, unit(unitId) != nil else { return false }
        let ret = command(.changeWorkType(unit: unitId, workType: goodsTypeId))
            && unit(unitId)?.workType?.id == goodsTypeId
        if ret { updateGUI() }
        return ret
    }

    /// Take a colonist out of the colony onto its tile
    /// (OutsideColonyPanel, InGameController.putOutsideColony).
    func putOutsideColony(_ unitId: String) {
        guard ourTurn, let u = unit(unitId), let colony = u.colony, !u.isOnCarrier else { return }
        let colonyId = colony.id
        if !confirmLeaveColony(unitId) { return }
        if command(.putOutsideColony(unit: unitId)), unit(unitId)?.location is Tile { updateGUI() }
        updateProduction(colonyId)
    }

    /// Set a colony's build queue (InGameController.setBuildQueue).
    func setBuildQueue(_ colonyId: String, _ queue: [String]) {
        guard ourTurn else { return }
        if command(.setBuildQueue(colony: colonyId, queue: queue)) { updateGUI() }
    }

    /// Set colonists to the work their places suit, where a place makes
    /// nothing or not what they work at (ColonyPanel.updateProduction).
    func updateProduction(_ colonyId: String?) {
        guard let colonyId, let colony = view.game.getFreeColGameObject(colonyId, as: Colony.self) else { return }
        for wlId in colony.currentWorkLocations.compactMap(\.id) {
            guard let wl = workLocation(wlId) else { continue }
            let check = wl.productionType == nil
            let units = wl.units.filter { check || !wl.produces($0.workType) }.compactMap(\.id)
            for id in units {
                guard let u = unit(id), let wl = workLocation(wlId), let workType = wl.work(for: u),
                      workType !== u.workType else { continue }
                changeWorkType(id, workType.id ?? "")
            }
        }
    }
}

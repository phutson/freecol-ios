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
import FreeColUtil

/// Work in a colony (server/ai/mission/WorkInsideColonyMission): go
/// there, then wait while the colony's AI arranges the work.
final class WorkInsideColonyMission: Mission {

    private var colony: Colony? // Strong, as Java keeps a destroyed colony.

    init(_ aiMain: AIMain, _ aiUnit: AIUnit, _ aiColony: AIColony) {
        super.init(aiMain, aiUnit)
        colony = aiColony.colony
    }

    var aiColony: AIColony? { colony.flatMap { aiMain.aiColony($0) } }

    static func invalidMissionReason(_ aiUnit: AIUnit?, _ loc: (any Location)?) -> String? {
        if let reason = invalidAIUnitReason(aiUnit) { return reason }
        if !aiUnit!.unit.isPerson { return Mission.unitNotAPerson }
        return invalidTargetReason(loc, aiUnit!.unit.owner)
    }

    override var baseTransportPriority: Int { Mission.normalTransportPriority }

    override var target: (any Location)? {
        get { colony }
        set { if let c = newValue as? Colony { colony = c } }
    }

    override func findTarget() -> (any Location)? { target }

    override func invalidReason() -> String? {
        WorkInsideColonyMission.invalidMissionReason(aiUnit, target)
    }

    override func doMission() -> Mission? {
        if invalidReason() != nil { return lbFail(false) }
        switch travelToTarget(target, CostDeciders.avoidSettlementsAndBlockingUnits()) {
        case .move: break // Arrived.
        case .moveHighSeas, .moveNoMoves, .moveIllegal: return lbWait()
        case .moveNoRepair: return lbFail(false)
        case .moveNoAccessEmbark, .moveNoTile: return self
        default: return self
        }
        return lbWait()
    }
}

extension AIUnit {

    var hasDefendSettlementMission: Bool { mission is DefendSettlementMission }

    /// Whether the unit has realized a wish at a colony
    /// (isCompleteWishRealizationMission).
    func isCompleteWishRealizationMission(_ colony: Colony) -> Bool {
        guard let wm = mission as? WishRealizationMission else { return false }
        return Map.isSameLocation(wm.target, colony)
    }

    /// Whether the unit may be put to work in a colony: it has no
    /// mission, or one that can be given up (isAvailableForWork).
    func isAvailableForWork(_ colony: Colony) -> Bool {
        guard let m = mission else { return true }
        if m is BuildColonyMission {
            return Map.isSameLocation(m.target, colony.tile) || colony.unitCount <= 1
        }
        return m is DefendSettlementMission || m is IdleAtSettlementMission || m is WorkInsideColonyMission
    }

    /// Work in the colony, if not already (tryWorkInsideColonyMission).
    ///
    /// - Returns: Whether the unit has the mission.
    func tryWorkInsideColonyMission(_ aiColony: AIColony) -> Bool {
        if mission is WorkInsideColonyMission { return true }
        guard let euai = aiOwner as? EuropeanAIPlayer,
              euai.workInsideColonyMission(self, aiColony) != nil else { return false }
        dropTransport()
        return true
    }

    /// Become a pioneer, if there is work (tryPioneeringMission).
    func tryPioneeringMission() -> Bool {
        let oldTarget = mission?.target
        guard let euai = aiOwner as? EuropeanAIPlayer, euai.pioneeringMission(self, nil) != nil else {
            return false
        }
        euai.updateTransport(self, oldTarget)
        return true
    }

    /// Find something useful to do from a colony: keep a useful
    /// mission, or scout, defend or preach (trySomeUsefulMission).
    func trySomeUsefulMission(_ colony: Colony) -> Bool {
        if mission is BuildColonyMission || mission is DefendSettlementMission || mission is MissionaryMission
            || mission is PioneeringMission || mission is ScoutingMission || mission is UnitSeekAndDestroyMission {
            return true
        }
        let oldTarget = mission?.target
        guard let euai = aiOwner as? EuropeanAIPlayer else { return false }
        if unit.hasAbility(Ability.speakWithChief), euai.scoutingMission(self) != nil {
            euai.updateTransport(self, oldTarget)
            return true
        } else if unit.isDefensiveUnit, euai.defendSettlementMission(self, colony) != nil {
            euai.updateTransport(self, oldTarget)
            return true
        } else if unit.hasAbility(Ability.establishMission), euai.missionaryMission(self) != nil {
            euai.updateTransport(self, oldTarget)
            return true
        }
        return false
    }

    /// Stop a carrier carrying some goods.
    func removeTransportable(_ ag: AIGoods) {
        (mission as? TransportMission)?.removeTransportable(ag)
    }
}

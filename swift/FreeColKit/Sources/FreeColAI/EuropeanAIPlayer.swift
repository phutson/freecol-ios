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

/// A European computer player (server/ai/EuropeanAIPlayer).  So far its
/// answers to the server are ported: tax raises, mercenaries, founding
/// fathers and native demands.  Its turns (colonies and missions) come
/// in Phase 4's next steps; until then it only ends them.
class EuropeanAIPlayer: MissionAIPlayer {

    /// Whether this nation likes attacking natives (the conquest
    /// nations).
    var likesAttackingNatives: Bool {
        player.nation?.type?.id == "model.nationType.conquest"
    }

    override func startWorking() {
        aiMain.record(NotYetPorted("the European AI's turn"), "\(player.nationId ?? "")")
    }

    /// Working in a colony comes with the European AI's colonies.
    func workInsideColonyMission(_ aiUnit: AIUnit, _ colony: Colony) -> Mission? {
        aiMain.record(NotYetPorted("WorkInsideColonyMission"), "\(player.nationId ?? "")")
        return nil
    }

    /// Accept a tax raise unless it costs too much (acceptTax).
    override func acceptTax(_ tax: Int) -> Bool {
        let toBeDestroyed = player.mostValuableGoods
        let goodsType = toBeDestroyed?.type
        let ret: Bool
        if tax <= 2 {
            ret = true
        } else if toBeDestroyed == nil {
            ret = false
        } else if goodsType!.isFoodType {
            ret = false
        } else if goodsType!.isBreedable {
            ret = player.settlements.filter { $0.goodsCount(goodsType!) > 0 }.count < 2
        } else if goodsType!.isMilitary || goodsType!.isTradeGoods || goodsType!.isBuildingMaterial {
            ret = game.turn.number < 300
        } else {
            let goodsTypes = specification?.storableGoodsTypeList ?? []
            let averageIncome = goodsTypes.reduce(0) { $0 + player.incomeAfterTaxes($1) } / goodsTypes.count
            let income = player.incomeAfterTaxes(goodsType!)
            ret = income <= 0 || income > averageIncome
        }
        if !ret, let goodsType { suppressEuropeanTrade(goodsType) }
        return ret
    }

    /// Stop trading goods that are to be boycotted: sell what is in
    /// Europe and on the way (suppressEuropeanTrade).  Transport missions
    /// and goods wishes come with the European AI.
    private func suppressEuropeanTrade(_ type: GoodsType) {
        guard let europe = player.europe else { return }
        let units = europe.unitList + (player.highSeas?.unitList ?? [])
        for u in units {
            let amount = u.goodsCount(type)
            if u.isCarrier && amount > 0, aiUnit(u) != nil {
                ask(.unloadGoods(type: type.id, amount: String(amount), carrier: u.id))
            }
        }
    }

    override func acceptMercenaries() -> Bool {
        player.isAtWar || aiAdvantage == "conquest"
    }

    /// The father with a custom house, or the heaviest for the age
    /// (selectFoundingFather).
    override func selectFoundingFather(_ ffs: [FoundingFather]) -> FoundingFather? {
        let age = game.age
        var bestFather: FoundingFather?
        var bestWeight = Int(Int32.min)
        for father in ffs {
            if father.hasAbility(Ability.buildCustomHouse) { return father }
            let weight = father.weight(age)
            if weight > bestWeight {
                bestWeight = weight
                bestFather = father
            }
        }
        return bestFather
    }

    override func indianDemand(_ unit: Unit, _ colony: Colony, _ type: GoodsType?, _ amount: Int,
                               _ accept: IndianDemandAction?) -> IndianDemandAction {
        aiAdvantage == "conquest" ? .accept : .reject
    }

    override func acceptDiplomaticTrade(_ agreement: DiplomaticTrade) -> DiplomaticTrade.TradeStatus {
        aiMain.record(NotYetPorted("the European AI's diplomacy"), "\(player.nationId ?? "")")
        return .rejectTrade
    }
}

/// The REF's computer player (server/ai/REFAIPlayer), which comes with
/// Phase 4's last step.
final class REFAIPlayer: EuropeanAIPlayer {
    override func startWorking() {
        aiMain.record(NotYetPorted("the REF's AI"), "\(player.nationId ?? "")")
    }
}

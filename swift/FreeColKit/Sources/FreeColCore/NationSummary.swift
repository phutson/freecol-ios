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

import FreeColXML

/// What one player knows of another's nation (common/model/NationSummary).
///
/// A value of -1 is unknown: natives' units, strength and gold, and a
/// European's rebels, fathers and tax unless it is the asking player or
/// that player has the better foreign affairs report.
public final class NationSummary: FreeColObject {

    public static let tag = "nationSummary"

    public private(set) var stance: Player.Stance = .peace
    public private(set) var numberOfSettlements = -1
    public private(set) var numberOfUnits = -1
    public private(set) var militaryStrength = -1
    public private(set) var navalStrength = -1
    public private(set) var gold = -1
    public private(set) var soL = -1
    public private(set) var foundingFathers = -1
    public private(set) var tax = -1

    /// The summary of a player, as another asks for it.
    public init(_ player: Player, _ requester: Player) {
        super.init()
        id = "" // As Java's, which writes it.
        stance = player.stance(requester)
        if stance == .uncontacted { stance = .peace }
        numberOfSettlements = player.settlementCount
        if player.isEuropean {
            numberOfUnits = player.unitCount
            militaryStrength = player.calculateStrength(naval: false)
            navalStrength = player.calculateStrength(naval: true)
            gold = player.gold
            if player === requester || requester.hasAbility(Ability.betterForeignAffairsReport) {
                soL = player.sonsOfLiberty
                foundingFathers = player.fatherCount
                tax = player.tax
            }
        }
    }

    public override var xmlTagName: String {
        NationSummary.tag
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("numberOfSettlements", numberOfSettlements)
        xw.writeAttribute("numberOfUnits", numberOfUnits)
        xw.writeAttribute("militaryStrength", militaryStrength)
        xw.writeAttribute("navalStrength", navalStrength)
        xw.writeAttribute("stance", stance)
        xw.writeAttribute("gold", gold)
        if soL >= 0 { xw.writeAttribute("SoL", soL) }
        if foundingFathers >= 0 { xw.writeAttribute("foundingFathers", foundingFathers) }
        if tax >= 0 { xw.writeAttribute("tax", tax) }
    }
}

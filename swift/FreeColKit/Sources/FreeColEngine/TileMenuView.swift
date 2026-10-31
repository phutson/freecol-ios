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

/// What a tile's menu offers (TilePopup), opened by a long press.
public struct TileMenu: Sendable, Equatable {
    public let title: String
    public let items: [TileMenuItem]
}

public struct TileMenuItem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Attack the tile, or go there, with the active unit.
        case attack, goTo
        case goToEurope, activate, fortify, skip, cashIn, clearOrders
        case colony(String), rename(String), settlement(String)
        /// The tile itself, whether explored.
        case tile(explored: Bool)
        case unit(String)
        /// Goods aboard a unit, to read.
        case goods
        case dumpCargo(String)
        case activateAll
    }

    public let kind: Kind
    public let label: String
    public let enabled: Bool
}

extension PlayerView {

    /// The menu of a tile, for the unit being moved (TilePopup).  Java's
    /// "more" submenus are one list here.
    func tileMenu(_ tile: Tile, activeUnit: Unit?) -> TileMenu {
        var items: [TileMenuItem] = []
        func add(_ kind: TileMenuItem.Kind, _ label: String, enabled: Bool = true) {
            items.append(TileMenuItem(kind: kind, label: label, enabled: enabled))
        }
        if let a = activeUnit, player.owns(a), let at = a.tile {
            if a.isOffensiveUnit && at.isAdjacent(tile) && a.moveType(tile).isAttack {
                add(.attack, Messages.message(a.combatLabel(tile)) ?? "")
            } else if a.simpleMoveType(at, tile).isLegal {
                add(.goTo, Messages.message("goToThisTile"))
            }
            if at === tile {
                if a.canMoveToHighSeas { add(.goToEurope, Messages.message("goToEurope")) }
                if a.checkSetState(.active) { add(.activate, Messages.message("activateUnit")) }
                if a.checkSetState(.fortifying) { add(.fortify, Messages.message("fortify")) }
                if a.checkSetState(.skipped) { add(.skip, Messages.message("skip")) }
                if a.canCarryTreasure && a.canCashInTreasureTrain {
                    add(.cashIn, Messages.message("cashInTreasureTrain"))
                }
                if a.destination != nil { add(.clearOrders, Messages.message("clearOrders")) }
            }
        }
        if let s = tile.settlement, let id = s.id {
            let name = Messages.message(locationLabel(s, for: player)) ?? ""
            if s.owner === player {
                add(.colony(id), name)
                add(.rename(id), Messages.message("rename"))
            } else if s is IndianSettlement {
                add(.settlement(id), name)
            }
        }
        add(.tile(explored: tile.isExplored), Messages.message(tile.label) ?? "")

        func addUnit(_ u: Unit, enabled: Bool, indent: Bool) {
            let text = (indent ? "    " : "") + (Messages.message(u.label(.national)) ?? "")
                + " (" + (Messages.message(u.occupationLabel(player, true)) ?? "") + ")"
            add(.unit(u.id ?? ""), text, enabled: enabled)
            for c in u.unitList { addUnit(c, enabled: true, indent: true) }
            let goods = u.goodsList
            for g in goods {
                add(.goods, (indent ? "         " : "     ") + (Messages.message(g.label(sellable: true)) ?? ""),
                    enabled: false)
            }
            if !goods.isEmpty { add(.dumpCargo(u.id ?? ""), Messages.message("dumpCargo")) }
        }
        let sorted = tile.unitList.sorted { a, b in
            let c = FreeColObject.compareIds(a.type, b.type)
            if c != 0 { return c < 0 }
            let ra = a.role?.roleIndex ?? 0, rb = b.role?.roleIndex ?? 0
            if ra != rb { return ra < rb }
            return FreeColObject.compareIds(a, b) < 0
        }
        for u in sorted { addUnit(u, enabled: !u.isDamaged, indent: false) }
        if tile.unitList.count > 1 && player.owns(tile.firstUnit) {
            add(.activateAll, Messages.message("activateAllUnits"))
        }
        return TileMenu(title: Messages.message(tile.simpleLabel) ?? "", items: items)
    }
}

extension PlayController {
    /// Clear the orders of every unit on a tile, and move the first
    /// (TilePopup's activateAllItem).
    func activateAll(_ position: MapPosition) {
        guard let tile = view.tile(position) else { return }
        let ids = tile.unitList.compactMap(\.id), first = tile.firstUnit?.id
        for id in ids { clearOrders(id) }
        if question == nil, let first { select(first) }
    }

    /// Rename a colony (rename).
    func renameColony(_ colonyId: String, _ name: String) {
        if !name.isEmpty, command(.rename(nameable: colonyId, name: name)) { updateGUI() }
    }

    func cashIn(_ unitId: String) {
        if checkCashInTreasureTrain(unitId) { updateGUI(true) }
    }
}

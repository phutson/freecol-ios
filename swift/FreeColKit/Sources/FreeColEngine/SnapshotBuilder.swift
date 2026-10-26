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

/// Makes a player's snapshot of the live game.  It must run where the
/// game lives (in the engine actor), with the player's messages loaded.
struct SnapshotBuilder {
    let game: ServerGame
    let player: Player

    func build() -> GameSnapshot {
        let spec = game.specification
        let calendar = spec?.turnCalendar ?? .standard
        var units: [UnitSnapshot] = []
        var seen = Set<ObjectIdentifier>()
        func add(_ unit: Unit) {
            guard seen.insert(ObjectIdentifier(unit)).inserted else { return }
            units.append(Self.unit(unit))
        }
        // The player's own units, then the others it can see.
        for unit in player.units { add(unit) }
        let map = mapSnapshot { unit in add(unit) }
        return GameSnapshot(
            turn: game.turn.number,
            turnName: Messages.message(game.turn.label(calendar)) ?? String(game.turn.number),
            playerId: player.id ?? "",
            currentPlayerId: game.currentPlayer?.id,
            players: game.players.map(playerSnapshot),
            map: map,
            units: units,
            colonies: player.colonyList.map(Self.colony),
            settlements: settlements(),
            europe: europe(),
            market: market(),
            messages: player.modelMessages.map(Self.message))
    }

    private func playerSnapshot(_ p: Player) -> PlayerSnapshot {
        PlayerSnapshot(
            id: p.id ?? "",
            nationId: p.nationId ?? "",
            nationName: Messages.message(p.nationLabel) ?? p.nationId ?? "",
            name: p.name ?? "",
            playerType: p.playerType?.javaName ?? "",
            isAI: p.isAI,
            isDead: p.isDead,
            isEuropean: p.isEuropean,
            gold: p === player ? p.gold : nil,
            tax: p.tax,
            score: p.score,
            stance: p === player ? nil : player.stance(p).javaName)
    }

    /// The map as the player knows it; the units on the tiles it sees
    /// now are passed to `visibleUnit`.
    private func mapSnapshot(_ visibleUnit: (Unit) -> Void) -> MapSnapshot {
        guard let map = game.map else { return MapSnapshot(width: 0, height: 0, tiles: []) }
        var tiles: [TileSnapshot] = []
        tiles.reserveCapacity(map.width * map.height)
        for y in 0..<map.height {
            for x in 0..<map.width {
                guard let tile = map.tile(x, y), player.hasExplored(tile) else {
                    tiles.append(TileSnapshot(x: x, y: y, isExplored: false, isVisible: false, typeId: nil, style: 0,
                                              riverStyle: nil, roadStyle: nil, resourceTypeId: nil,
                                              hasLostCityRumour: false, ownerId: nil, owningSettlementId: nil,
                                              settlementId: nil, unitIds: []))
                    continue
                }
                let visible = player.canSee(tile)
                // What the player last saw, if it does not see it now.
                let view = visible ? tile : (tile.cachedTile(player) ?? tile)
                var unitIds: [String] = []
                if visible {
                    for unit in tile.unitList where player.owns(unit) || player.canSeeUnit(unit) {
                        unitIds.append(unit.id ?? "")
                        visibleUnit(unit)
                    }
                }
                tiles.append(TileSnapshot(
                    x: x, y: y, isExplored: true, isVisible: visible,
                    typeId: view.type?.id, style: view.style,
                    riverStyle: view.river?.style?.string, roadStyle: view.road?.style?.string,
                    resourceTypeId: view.resource?.type?.id,
                    hasLostCityRumour: view.hasLostCityRumour,
                    ownerId: view.owner?.id, owningSettlementId: view.owningSettlement?.id,
                    settlementId: view.settlement?.id, unitIds: unitIds))
            }
        }
        return MapSnapshot(width: map.width, height: map.height, tiles: tiles)
    }

    static func position(_ tile: Tile?) -> MapPosition? {
        tile.map { MapPosition(x: $0.x, y: $0.y) }
    }

    static func unit(_ unit: Unit) -> UnitSnapshot {
        let place: UnitPlace
        switch unit.location {
        case let t as Tile: place = .tile(MapPosition(x: t.x, y: t.y))
        case let carrier as Unit: place = .carrier(carrier.id ?? "")
        case let b as Building:
            place = .building(colonyId: b.settlement?.id ?? "", buildingTypeId: b.type?.id ?? "")
        case let ct as ColonyTile:
            place = .colonyTile(colonyId: ct.settlement?.id ?? "",
                                position: position(ct.workTile) ?? MapPosition(x: -1, y: -1))
        case let s as IndianSettlement: place = .settlement(s.id ?? "")
        case is Europe: place = .europe
        case is HighSeas: place = .highSeas
        default: place = .unknown
        }
        return UnitSnapshot(
            id: unit.id ?? "",
            label: Messages.message(unit.label) ?? unit.type?.id ?? "",
            name: unit.name,
            typeId: unit.type?.id ?? "",
            roleId: unit.role?.id,
            ownerId: unit.owner?.id,
            place: place,
            position: position(unit.tile),
            movesLeft: unit.movesLeft,
            initialMoves: unit.initialMovesLeft,
            state: unit.state.javaName,
            workTypeId: unit.workType?.id,
            isNaval: unit.isNaval,
            isCarrier: unit.isCarrier,
            isDamaged: unit.isDamaged,
            hitPoints: unit.hitPoints,
            treasureAmount: unit.treasureAmount,
            goods: unit.goodsList.compactMap { g in g.type.map { GoodsAmount(typeId: $0.id ?? "", amount: g.amount) } },
            carriedUnitIds: unit.unitList.map { $0.id ?? "" },
            destinationId: (unit.destination as? FreeColGameObject)?.id)
    }

    static func colony(_ colony: Colony) -> ColonySnapshot {
        ColonySnapshot(
            id: colony.id ?? "",
            name: colony.name ?? "",
            position: position(colony.tile) ?? MapPosition(x: -1, y: -1),
            ownerId: colony.owner?.id,
            unitCount: colony.unitCount,
            sonsOfLiberty: colony.sonsOfLiberty,
            tory: 100 - colony.sonsOfLiberty,
            buildings: colony.buildings.map { b in
                BuildingSnapshot(id: b.id ?? "", typeId: b.type?.id ?? "", name: Messages.name(b.type?.id),
                                 unitIds: b.unitList.map { $0.id ?? "" })
            },
            workTiles: colony.colonyTiles.compactMap { ct in
                position(ct.workTile).map { WorkTileSnapshot(position: $0, unitIds: ct.unitList.map { $0.id ?? "" }) }
            },
            goods: (colony.goodsContainer?.storedEntries ?? []).map { GoodsAmount(typeId: $0.type.id ?? "",
                                                                                   amount: $0.amount) },
            buildQueue: colony.buildQueue.values.map { $0.id ?? "" })
    }

    private func settlements() -> [SettlementSnapshot] {
        guard let map = game.map else { return [] }
        var ret: [SettlementSnapshot] = []
        for tile in map.tiles where player.hasExplored(tile) {
            let view = player.canSee(tile) ? tile : (tile.cachedTile(player) ?? tile)
            guard let s = view.settlement, s.owner !== player else { continue }
            let natives = s as? IndianSettlement
            let known = natives.map { $0.hasVisited(player) || $0.hasScouted(player) } ?? false
            ret.append(SettlementSnapshot(
                id: s.id ?? "",
                name: s.name ?? "",
                position: MapPosition(x: tile.x, y: tile.y),
                ownerId: s.owner?.id,
                isCapital: s.isCapital,
                isNative: natives != nil,
                skillTypeId: known ? natives?.learnableSkill?.id : nil,
                missionaryOwnerId: natives?.missionary?.owner?.id,
                alarmLevel: natives?.alarm(player)?.level.javaName))
        }
        return ret
    }

    private func europe() -> EuropeSnapshot? {
        guard let europe = player.europe else { return nil }
        return EuropeSnapshot(recruitableTypeIds: europe.recruitables.map { $0.id ?? "" },
                              unitIds: europe.unitList.map { $0.id ?? "" })
    }

    private func market() -> [MarketPrice] {
        guard let market = player.market, let spec = game.specification else { return [] }
        return spec.goodsTypeList.filter(\.isStorable).map { type in
            MarketPrice(typeId: type.id ?? "", costToBuy: market.costToBuy(type), paidForSale: market.paidForSale(type))
        }
    }

    static func message(_ m: ModelMessage) -> MessageSnapshot {
        MessageSnapshot(id: m.id, messageType: m.messageType?.javaName, text: Messages.message(m) ?? m.id ?? "",
                        sourceId: m.sourceId, displayId: m.displayId)
    }
}

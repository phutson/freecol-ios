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

// The game as one player sees it, as plain values the user interface can
// keep and read on any thread.  The engine makes a new snapshot after
// each change; nothing in one refers back to the live game.  Objects are
// named by their identifiers ("unit:123"), types by their specification
// identifiers ("model.unit.freeColonist"), and names are already
// translated.

/// An amount of goods.
public struct GoodsAmount: Sendable, Equatable, Hashable {
    public let typeId: String
    public let amount: Int
}

/// A map position.
public struct MapPosition: Sendable, Equatable, Hashable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Everything one player can see of the game.
public struct GameSnapshot: Sendable, Equatable {
    public let turn: Int
    /// The turn as the game names it ("Spring 1600").
    public let turnName: String
    /// The player this snapshot is for.
    public let playerId: String
    /// Whose turn it is, if anyone's.
    public let currentPlayerId: String?
    public let players: [PlayerSnapshot]
    public let map: MapSnapshot
    /// The player's own units, wherever they are, and the others' it
    /// can see on the map.
    public let units: [UnitSnapshot]
    /// The player's own colonies.
    public let colonies: [ColonySnapshot]
    /// The other settlements on tiles the player has explored, as it
    /// last saw them.
    public let settlements: [SettlementSnapshot]
    /// The player's Europe, if it still has one.
    public let europe: EuropeSnapshot?
    /// Prices in the player's market.
    public let market: [MarketPrice]
    /// The player's messages for this turn.
    public let messages: [MessageSnapshot]
    /// Whether the game hides what is not in sight (the fogOfWar game
    /// option).
    public var fogOfWar = false

    public func unit(_ id: String) -> UnitSnapshot? { units.first { $0.id == id } }
    public func colony(_ id: String) -> ColonySnapshot? { colonies.first { $0.id == id } }
    public func player(_ id: String) -> PlayerSnapshot? { players.first { $0.id == id } }
    public var player: PlayerSnapshot? { player(playerId) }
    /// The player's own units.
    public var ownUnits: [UnitSnapshot] { units.filter { $0.ownerId == playerId } }
    public var isPlayersTurn: Bool { currentPlayerId == playerId }
}

/// A player, as another sees it.
public struct PlayerSnapshot: Sendable, Equatable {
    public let id: String
    public let nationId: String
    /// The nation's name ("Dutch").
    public let nationName: String
    public let name: String
    /// Java's player type: COLONIAL, REBEL, INDEPENDENT, ROYAL, NATIVE or
    /// UNDEAD.
    public let playerType: String
    public let isAI: Bool
    public let isDead: Bool
    public let isEuropean: Bool
    /// Gold, for the player itself only.
    public let gold: Int?
    public let tax: Int
    public let score: Int
    /// The stance towards the player the snapshot is for (UNCONTACTED,
    /// PEACE, WAR...), or nil for that player itself.
    public let stance: String?
    /// The last part of the nation's id ("dutch"), which picks
    /// national images (getNationResourceKey).
    public let nationResourceKey: String
    /// The nation's colour, as ARGB, if it has one.
    public var nationColor: Int32?
}

/// The map, row by row.
public struct MapSnapshot: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let tiles: [TileSnapshot]

    public func tile(_ x: Int, _ y: Int) -> TileSnapshot? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        return tiles[y * width + x]
    }
}

/// A tile, as the player last saw it.  Unexplored tiles show nothing.
public struct TileSnapshot: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let isExplored: Bool
    /// Whether the player sees it now (and so its units).
    public let isVisible: Bool
    public let typeId: String?
    /// The style that picks the coast image.
    public let style: Int
    /// The river's style (a digit per side), if there is one.
    public let riverStyle: String?
    public let roadStyle: String?
    public let resourceTypeId: String?
    public let hasLostCityRumour: Bool
    public let ownerId: String?
    public let owningSettlementId: String?
    public let settlementId: String?
    /// The units the player can see here, the defender first.
    public let unitIds: [String]
    /// The region the tile is in, as the player saw it.
    public var regionId: String?
    /// Whether the tile type is land, and forested.
    public var isLand = false
    public var isForested = false
    /// The settlement here as the player saw it, for drawing.
    public var settlement: TileSettlementSnapshot?
    /// The finished items on it (improvements, a resource, a rumour),
    /// in the order the tile keeps them, for drawing by z-index.
    public var items: [TileItemSnapshot] = []
    /// The units here the player can see, and those they carry.
    public var totalUnitCount = 0
}

/// A finished item on a tile, as the map draws it.
public struct TileItemSnapshot: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case improvement
        case resource
        case lostCityRumour
    }

    public let kind: Kind
    /// The improvement or resource type ("model.improvement.road").
    public let typeId: String?
    public let zIndex: Int
    /// An improvement's style (a digit per side), for roads and rivers.
    public let style: String?
    /// An improvement's magnitude (a major river is 2).
    public var magnitude = 0
}

/// A settlement as the map draws it: what picks its image.
public struct TileSettlementSnapshot: Sendable, Equatable {
    /// The settlement type ("model.settlement.colony", or a native one).
    public let typeId: String
    public let isColony: Bool
    /// For a colony: the unit count it shows, its stockade, if any
    /// ("stockade", "fort", "fortress"), and whether it is undead.
    public let apparentUnitCount: Int
    public let stockadeKey: String?
    public let isUndead: Bool
    /// For a native settlement: whether it has a missionary.
    public let hasMissionary: Bool
    /// The owner's nation resource key ("dutch", "inca").
    public let ownerNationResourceKey: String?
    /// Its name as the player knows it, and the owner's colour.
    public var name: String?
    public var ownerColor: Int32?
    /// For a colony: whether it would take more units, and its
    /// production bonus (-2 to 2).
    public var wantsMoreUnits = false
    public var productionBonus = 0
    /// For a native settlement: whether it is a capital, its
    /// missionary's colour and expertise, and, if the player has met
    /// it, how it feels.
    public var isCapital = false
    public var missionaryColor: Int32?
    public var missionaryIsExpert = false
    public var alarm: SettlementAlarmSnapshot?
}

/// How a native settlement the player has met feels, as its alarm chip
/// shows it.
public struct SettlementAlarmSnapshot: Sendable, Equatable {
    /// The colour of the player it hates most (Nation.UNKNOWN_NATION_RGB
    /// if none).
    public let mostHatedColor: Int32
    /// Whether it is still worth scouting.
    public let isWorthScouting: Bool
}

/// Where a unit is.
public enum UnitPlace: Sendable, Equatable {
    case tile(MapPosition)
    /// On a ship or wagon.
    case carrier(String)
    /// Working in a colony building.
    case building(colonyId: String, buildingTypeId: String)
    /// Working a colony's tile.
    case colonyTile(colonyId: String, position: MapPosition)
    /// In a native settlement (a brave, or a missionary).
    case settlement(String)
    case europe
    case highSeas
    /// Nowhere the player can be told of.
    case unknown
}

/// A unit.
public struct UnitSnapshot: Sendable, Equatable {
    public let id: String
    /// Its label as the game shows it ("Expert Farmer", "Soldier (Free
    /// Colonist)").
    public let label: String
    public let name: String?
    public let typeId: String
    public let roleId: String?
    public let ownerId: String?
    public let place: UnitPlace
    /// Where it stands on the map, even if inside a colony or carrier.
    public let position: MapPosition?
    public let movesLeft: Int
    public let initialMoves: Int
    /// Java's unit state: ACTIVE, SENTRY, FORTIFIED, IMPROVING...
    public let state: String
    public let workTypeId: String?
    public let isNaval: Bool
    public let isCarrier: Bool
    public let isDamaged: Bool
    public let hitPoints: Int
    public let treasureAmount: Int
    public let goods: [GoodsAmount]
    public let carriedUnitIds: [String]
    public let destinationId: String?
    /// Whether the unit is of native ethnicity, and whether its type
    /// is born in native settlements, which pick its image.
    public var hasNativeEthnicity = false
    public var isNativeBorn = false
    /// What it is doing, as the player sees it, in a letter or two
    /// (Unit.getOccupationLabel, short).
    public var occupation = ""
    public var maximumHitPoints = 0
}

/// A colony of the player's.
public struct ColonySnapshot: Sendable, Equatable {
    public let id: String
    public let name: String
    public let position: MapPosition
    public let ownerId: String?
    public let unitCount: Int
    public let sonsOfLiberty: Int
    public let tory: Int
    public let buildings: [BuildingSnapshot]
    /// The tiles round it, with who works them.
    public let workTiles: [WorkTileSnapshot]
    public let goods: [GoodsAmount]
    public let buildQueue: [String]
}

public struct BuildingSnapshot: Sendable, Equatable {
    public let id: String
    public let typeId: String
    public let name: String
    public let unitIds: [String]
}

public struct WorkTileSnapshot: Sendable, Equatable {
    public let position: MapPosition
    public let unitIds: [String]
}

/// Another player's settlement, as last seen.
public struct SettlementSnapshot: Sendable, Equatable {
    public let id: String
    public let name: String
    public let position: MapPosition
    public let ownerId: String?
    public let isCapital: Bool
    public let isNative: Bool
    /// The skill taught, once the player knows it.
    public let skillTypeId: String?
    /// The owner of the missionary there, if any.
    public let missionaryOwnerId: String?
    /// How the natives feel about the player (HAPPY, CONTENT,
    /// DISPLEASED, ANGRY, HATEFUL), once in contact.
    public let alarmLevel: String?
}

/// The player's Europe.
public struct EuropeSnapshot: Sendable, Equatable {
    /// The unit types waiting at the docks to be recruited.
    public let recruitableTypeIds: [String]
    /// The units in Europe, docked or on the docks.
    public let unitIds: [String]
}

/// A goods type's prices in a player's market.
public struct MarketPrice: Sendable, Equatable {
    public let typeId: String
    public let costToBuy: Int
    public let paidForSale: Int
}

/// A message for the player, translated.
public struct MessageSnapshot: Sendable, Equatable {
    public let id: String?
    /// Java's message type: COMBAT_RESULT, UNIT_ARRIVED...
    public let messageType: String?
    public let text: String
    public let sourceId: String?
    public let displayId: String?
}

/// Something the player was shown happening, for the interface to
/// animate or announce.
public enum EngineEvent: Sendable, Equatable {
    case unitMoved(unitId: String, from: MapPosition, to: MapPosition)
    case attack(attackerId: String, defenderId: String, attackerWon: Bool)
    case message(MessageSnapshot)
    /// The server asks the player something.
    case request(ServerRequest)
}

/// What came of a command.
public struct CommandResult: Sendable, Equatable {
    /// Why the command was refused, or nil if it was carried out.
    public let refusal: String?
    /// What the player was shown.
    public let events: [EngineEvent]
    /// The game afterwards.
    public let snapshot: GameSnapshot

    /// What the client asks before going on, if anything: ask it and
    /// make the request again with the answer.
    public var question: PlayQuestion?
    /// What the player is told (Java's information panels).
    public var notices: [String] = []
    /// The unit the player is now moving, if any.
    public var activeUnitId: String?
    /// The colony to show the player, after arriving or founding it.
    public var colonyToShow: String?

    public var wasRefused: Bool { refusal != nil }
}

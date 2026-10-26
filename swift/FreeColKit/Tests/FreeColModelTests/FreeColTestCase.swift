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

import Foundation
import FreeColCore
import FreeColIO
import FreeColTestSupport
import FreeColUtil
import Testing

/// Foundation also has a Unit.
typealias Unit = FreeColCore.Unit

/// The helpers of Java's FreeColTestCase (test/src/net/sf/freecol/util/test).
///
/// Java shares one specification per rule set between all tests, and
/// some tests change it.  Swift Testing runs suites in parallel, so
/// each suite loads its own specifications and runs its tests one at a
/// time (`.serialized`).
enum FreeColTestCase {

    static let data = FreeColDataDirectory(url: ReferenceDumps.repositoryRoot.appendingPathComponent("data"))

    /// The maps Java restricts some tests to.
    static let standardMaps = [
        "data/maps/M_Africa_Gilolat.fsm",
        "data/maps/S_AustraliaOceania_Gilolat.fsm",
        "data/maps/L_America_JsTheDude.fsm",
        "data/maps/S_Caribbean_Phil.fsm",
    ]

    /// Load a rule set as Java's getSpecification does, at medium
    /// difficulty.  The US English messages are loaded the first time,
    /// as Java's setUp does.
    static func loadSpecification(_ name: String = "freecol") -> Specification {
        _ = messagesLoaded
        return try! data.loadSpecification(name, difficulty: "model.difficulty.medium")
    }

    /// Load the US English messages, once.
    nonisolated(unsafe) private static let messagesLoaded: Bool = {
        let strings = data.url.appendingPathComponent("strings")
        let numberRules = try! NumberRules(data: Data(contentsOf: strings.appendingPathComponent("plurals.xml")))
        Messages.bundle = MessageBundle.load(directory: strings, languageId: "en_US", numberRules: numberRules,
                                             rulesDirectories: ["classic", "freecol"].map {
                                                 data.url.appendingPathComponent("rules/" + $0)
                                             })
        return true
    }()

    /// A new game with a player for every nation but the unknown enemy
    /// (getStandardGame).  The difficulty level is applied again, as
    /// in Java, which undoes changes earlier tests made to it.
    static func standardGame(_ spec: Specification) -> Game {
        let game = ServerTestGame(specification: spec)
        let nationOptions = NationOptions(specification: spec)
        for nation in spec.europeanNations {
            nationOptions.setNationState(nation, .available)
        }
        game.nationOptions = nationOptions

        spec.applyDifficultyLevel("model.difficulty.medium")
        for n in spec.nations where !n.isUnknownEnemy {
            let p = Player(game: game, nation: n)
            let ai = !(n.type?.isEuropean ?? false) || (n.type?.isREF ?? false)
            p.isAI = ai
            if ai || game.canAddNewPlayer { game.addPlayer(p) }
        }
        return game
    }

    /// A 20 by 15 map of one tile type, plains by default, not set as
    /// the game's map (getTestMap).
    static func testMap(_ game: Game, _ tileType: TileType? = nil, explored: Bool = false) -> Map {
        let builder = MapBuilder(game)
        if let tileType { builder.setBaseTileType(tileType) }
        return builder.setExploredByAll(explored).build()
    }

    /// A 20 by 15 map with land of a type on the left half, ocean on
    /// the right and high seas down the right edge (getCoastTestMap).
    static func coastTestMap(_ game: Game, _ landTileType: TileType, explored: Bool = false) -> Map {
        let totalWidth = 20, totalHeight = 15
        let spec = game.specification!
        let builder = MapBuilder(game)
            .setDimensions(totalWidth, totalHeight)
            .setBaseTileType(spec.getTileType("model.tile.ocean")!)
        if explored { builder.setExploredByAll(true) }
        // Fill half with land; the builder fills the rest with ocean.
        for x in 0..<totalWidth / 2 {
            for y in 0..<totalHeight {
                builder.setTileType(x, y, landTileType)
            }
        }
        let highSeasType = spec.getTileType("model.tile.highSeas")!
        for y in 0..<totalHeight {
            builder.setTileType(totalWidth - 1, y, highSeasType)
        }
        return builder.build()
    }

    /// A colony at a tile with free colonists in it (getStandardColony).
    @discardableResult
    static func standardColony(_ game: Game, _ numberOfSettlers: Int = 1, _ tileX: Int = 5,
                               _ tileY: Int = 8) -> Colony {
        let tile = game.map!.tile(tileX, tileY)!
        let colony = ColonyBuilder(game).colonyTile(tile).initialColonists(numberOfSettlers).build()
        colony.owner!.exploreForSettlement(colony)
        return colony
    }

    /// Move a work location's units elsewhere in the colony, and say
    /// whether it is now empty (clearWorkLocation).
    @discardableResult
    static func clearWorkLocation(_ wl: WorkLocation) -> Bool {
        for u in wl.unitList {
            if let w = wl.colony?.currentWorkLocations.first(where: { $0 !== wl && $0.canAdd(u) }) {
                u.setLocation(w)
            }
        }
        return wl.isEmpty
    }

    /// Add a unit type change to the rules, and its change type if
    /// missing (addUnitTypeChange).
    static func addUnitTypeChange(_ spec: Specification, _ type: String, _ from: UnitType, _ to: UnitType,
                                  _ probability: Int, _ turns: Int) {
        let utc = UnitTypeChange(id: "\(type).\(from.suffix ?? "null")-\(to.suffix ?? "null")",
                                 specification: spec, from: from, to: to,
                                 probability: probability, turns: turns)
        let uct = spec.getUnitChangeType(type) ?? {
            let uct = UnitChangeType(id: type, specification: spec)
            spec.addUnitChangeType(uct)
            return uct
        }()
        uct.addUnitTypeChange(utc)
    }

    /// Build a colony with a unit, without the server.
    static func nonServerBuildColony(_ builder: Unit, _ colony: Colony) {
        colony.placeSettlement(true)
        colony.owner?.invalidateCanSeeTiles()
        nonServerJoinColony(builder, colony)
    }

    /// Join a colony with a unit, without the server.
    static func nonServerJoinColony(_ builder: Unit, _ colony: Colony) {
        builder.setLocation(colony)
        builder.setMovesLeft(0)
    }
}

/// The games made by the tests.  Game objects refer to their game
/// weakly, so a test that keeps only a map or a colony would otherwise
/// lose the game (at once in an optimized build); Java's tests keep it
/// in a static field.
nonisolated(unsafe) private var testGames: [Game] = []
private let testGamesLock = NSLock()

/// A game that issues identifiers, as Java's ServerGame does, and is
/// kept for the rest of the test run.
final class ServerTestGame: Game {
    override init(specification: Specification? = nil) {
        super.init(specification: specification)
        testGamesLock.withLock { testGames.append(self) }
    }

    override func getNextId() -> Int {
        defer { nextId += 1 }
        return nextId
    }
}

extension Player {
    /// Explore a tile, and say whether it is new to the player
    /// (ServerPlayer.exploreTile).
    @discardableResult
    func exploreTile(_ tile: Tile) -> Bool {
        let ret = !hasExplored(tile)
        if ret { tile.setExplored(self, true) }
        return ret
    }

    /// Explore the tiles a settlement owns or sees, but not its own
    /// (ServerPlayer.exploreForSettlement).
    @discardableResult
    func exploreForSettlement(_ settlement: Settlement) -> Set<Tile> {
        var tiles = Set(settlement.ownedTiles).union(settlement.visibleTileSet)
        if let tile = settlement.tile { tiles.remove(tile) }
        return Set(tiles.filter { exploreTile($0) })
    }
}

/// Builds test maps (FreeColTestCase.MapBuilder).
final class MapBuilder {
    private let game: Game
    private var tileTypes: [[TileType?]] = []
    private var width = 20
    private var height = 15
    private var baseTile: TileType
    private var exploredByAll = false
    private var initiated = false

    init(_ game: Game) {
        self.game = game
        baseTile = game.specification!.getTileType("model.tile.plains")!
        reset()
    }

    @discardableResult
    func reset() -> MapBuilder {
        width = 20
        height = 15
        baseTile = game.specification!.getTileType("model.tile.plains")!
        exploredByAll = false
        initiated = false
        tileTypes = Array(repeating: Array(repeating: nil, count: height), count: width)
        return self
    }

    @discardableResult
    func setBaseTileType(_ baseType: TileType) -> MapBuilder {
        baseTile = baseType
        return self
    }

    @discardableResult
    func setDimensions(_ width: Int, _ height: Int) -> MapBuilder {
        precondition(width > 0 && height > 0, "Dimensions must be positive")
        precondition(!initiated, "Cannot resize map after setting a tile")
        self.width = width
        self.height = height
        tileTypes = Array(repeating: Array(repeating: nil, count: height), count: width)
        return self
    }

    @discardableResult
    func setExploredByAll(_ exploredByAll: Bool) -> MapBuilder {
        self.exploredByAll = exploredByAll
        return self
    }

    @discardableResult
    func setTileType(_ x: Int, _ y: Int, _ tileType: TileType) -> MapBuilder {
        precondition(0 <= x && x < width && 0 <= y && y < height, "Coordinate out of bounds")
        tileTypes[x][y] = tileType
        initiated = true
        return self
    }

    func build() -> Map {
        let map = Map(game: game, width: width, height: height)
        // Java's tiles refer to the region, which the map does not
        // hold; here the map holds it, as tiles refer to regions weakly.
        let region = Region(game: game)
        map.addRegion(region)
        _ = map.populateTiles { x, y in
            let t = Tile(game: game, type: tileTypes[x][y] ?? baseTile, x: x, y: y)
            t.region = region
            return t
        }
        initiated = true
        map.resetContiguity()
        map.resetHighSeasCount()
        if exploredByAll {
            map.forEachTile { t in
                for p in game.liveEuropeanPlayers { t.setExplored(p, true) }
            }
        }
        return map
    }
}

/// Builds test colonies (FreeColTestUtils.ColonyBuilder).
final class ColonyBuilder {
    private let game: Game
    private var colonists: [(type: UnitType, count: Int)] = []
    private var player: Player?
    private var name = "New Amsterdam"
    private var initialColonists = 1
    private var colonyTile: Tile?

    init(_ game: Game) {
        self.game = game
    }

    func player(_ player: Player) -> ColonyBuilder {
        precondition(game.players.contains { $0 === player }, "Player not in game")
        self.player = player
        return self
    }

    func initialColonists(_ colonists: Int) -> ColonyBuilder {
        precondition(colonists > 0, "Number of colonists must be positive")
        initialColonists = colonists
        return self
    }

    func colonyTile(_ tile: Tile) -> ColonyBuilder {
        precondition(game.map?.tile(tile.x, tile.y) === tile, "Given tile not on map")
        colonyTile = tile
        return self
    }

    func colonyName(_ name: String) -> ColonyBuilder {
        self.name = name
        return self
    }

    func addColonist(_ type: UnitType) -> ColonyBuilder {
        if let i = colonists.firstIndex(where: { $0.type === type }) {
            colonists[i].count += 1
        } else {
            colonists.append((type, 1))
        }
        return self
    }

    func build() -> Colony {
        let player = player ?? game.player(byNationId: "model.nation.dutch")!
        let colonyTile = colonyTile ?? game.map!.tile(5, 8)!
        let colony = Colony(game: game, owner: player, name: name, tile: colonyTile)
        player.addSettlement(colony)
        colony.placeSettlement(true)
        player.invalidateCanSeeTiles()

        // Java adds the colonists from a HashMap; the order only
        // matters for identifiers.
        for (type, n) in colonists {
            for _ in 0..<n {
                Unit(game: game, location: colonyTile, owner: player, type: type).setLocation(colony)
            }
        }
        // The rest are free colonists.
        let colonistType = game.specification!.defaultUnitType!
        for _ in colony.unitCount..<max(colony.unitCount, initialColonists) {
            Unit(game: game, location: colonyTile, owner: player, type: colonistType).setLocation(colony)
        }
        return colony
    }
}

/// Builds test native settlements
/// (FreeColTestCase.IndianSettlementBuilder).
final class IndianSettlementBuilder {
    private static let defaultIndianPlayer = "model.nation.tupi"
    nonisolated(unsafe) private static var settlementNumber = 1

    private let game: Game
    private var indianPlayer: Player?
    private var skillTaught: String? = "model.unit.masterCottonPlanter"
    private var initialBravesInCamp = 1
    private var settlementTile: Tile?
    private var isCapital = false
    private var residentMissionary: Unit?

    init(_ game: Game) {
        self.game = game
    }

    func player(_ player: Player) -> IndianSettlementBuilder {
        precondition(game.players.contains { $0 === player }, "Indian player not in game")
        indianPlayer = player
        return self
    }

    func initialBravesInCamp(_ nBraves: Int) -> IndianSettlementBuilder {
        precondition(nBraves > 0, "Number of braves must be positive")
        initialBravesInCamp = nBraves
        return self
    }

    func settlementTile(_ tile: Tile) -> IndianSettlementBuilder {
        precondition(game.map?.tile(tile.x, tile.y) === tile, "Given tile not on map")
        settlementTile = tile
        return self
    }

    func capital(_ isCapital: Bool) -> IndianSettlementBuilder {
        self.isCapital = isCapital
        return self
    }

    func missionary(_ missionary: Unit?) -> IndianSettlementBuilder {
        residentMissionary = missionary
        return self
    }

    func skillToTeach(_ skill: String?) -> IndianSettlementBuilder {
        skillTaught = skill
        return self
    }

    func build() -> IndianSettlement {
        let spec = game.specification!
        let skillToTeach = skillTaught.flatMap { spec.getUnitType($0) }
        let indianPlayer = indianPlayer ?? game.player(byNationId: Self.defaultIndianPlayer)!
        let braveType = spec.defaultUnitType(indianPlayer.nationType)!
        let tile = settlementTile ?? game.map!.tile(5, 8)!
        let name: String
        if isCapital {
            name = (indianPlayer.name ?? "null") + "-capital"
        } else {
            name = "Settlement-\(Self.settlementNumber)"
            Self.settlementNumber += 1
        }
        let camp = IndianSettlement(game: game, owner: indianPlayer, name: name, tile: tile,
                                    isCapital: isCapital, learnableSkill: skillToTeach,
                                    missionary: residentMissionary)
        indianPlayer.addSettlement(camp)
        for _ in 0..<initialBravesInCamp {
            camp.addOwnedUnit(Unit(game: game, location: camp, owner: indianPlayer, type: braveType))
        }
        camp.placeSettlement(true)
        return camp
    }
}

/// Check a list of goods against the expected goods, in any order
/// (FreeColTestCase.checkGoods).
func checkGoods(_ err: String, _ goods: [AbstractGoods], _ results: AbstractGoods...,
                sourceLocation: SourceLocation = #_sourceLocation) {
    var check = goods
    for ag in results {
        let i = check.firstIndex { $0 == ag }
        #expect(i != nil, "\(err) requires \(ag)", sourceLocation: sourceLocation)
        if let i { check.remove(at: i) }
    }
    #expect(check.isEmpty, "\(err) requires more goods", sourceLocation: sourceLocation)
}

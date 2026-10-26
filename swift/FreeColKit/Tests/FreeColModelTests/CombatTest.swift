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
import Testing

/// CombatTest.java.  Java's modifier sets are arrays here; the source
/// objects Java compares by identity are compared by id.
@Suite(.serialized)
struct CombatTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    func role(_ id: String) -> Role { spec.getRole("model.role." + id)! }
    func unitType(_ id: String) -> UnitType { spec.getUnitType("model.unit." + id)! }
    var hills: TileType { spec.getTileType("model.tile.hills")! }
    var ocean: TileType { spec.getTileType("model.tile.ocean")! }
    var plains: TileType { spec.getTileType("model.tile.plains")! }
    var colonistType: UnitType { unitType("freeColonist") }
    var braveType: UnitType { unitType("brave") }

    func isSource(_ m: Modifier, _ id: String) -> Bool {
        m.source?.id == id
    }

    /// A game on a map of a tile type, with the Dutch and French.
    func setUp(_ tileType: TileType? = nil, explored: Bool = false) -> (Game, Map, Player, Player) {
        let game = FreeColTestCase.standardGame(spec)
        let map = FreeColTestCase.testMap(game, tileType, explored: explored)
        game.changeMap(map)
        return (game, map, game.player(byNationId: "model.nation.dutch")!,
                game.player(byNationId: "model.nation.french")!)
    }

    @Test func colonistAttackedByVeteran() throws {
        let (game, map, dutch, french) = setUp(plains)
        let combatModel = game.combatModel
        let tile1 = try #require(map.tile(5, 8))
        tile1.type = hills
        #expect(tile1.type === hills)
        let tile2 = try #require(map.tile(4, 8))
        for tile in [tile1, tile2] {
            tile.setExplored(dutch, true)
            tile.setExplored(french, true)
        }

        let colonist = Unit(game: game, location: tile1, owner: dutch, type: colonistType)
        colonist.setStateUnchecked(.fortified)
        let soldier = Unit(game: game, location: tile2, owner: french, type: unitType("veteranSoldier"),
                           role: role("dragoon"))
        soldier.setMovesLeft(1)
        #expect(!soldier.hasAbility(Ability.ambushBonus))
        #expect(!colonist.hasAbility(Ability.ambushPenalty))

        let bigMovementPenalty = try #require(spec.modifiers(Modifier.bigMovementPenalty).first)
        let attackModifier = try #require(spec.modifiers(Modifier.attackBonus).first)
        let veteranModifiers = unitType("veteranSoldier").modifiers(Modifier.offence)
        #expect(veteranModifiers.count == 1)
        let veteranModifier = try #require(veteranModifiers.first)

        let offenceModifiers = combatModel.offensiveModifiers(soldier, colonist)
        #expect(offenceModifiers.count == 5)
        var n = 0
        for m in offenceModifiers {
            if isSource(m, Specification.SourceId.baseOffence) { n += 1 }
            if m === bigMovementPenalty { n += 2 }
            if m === attackModifier { n += 4 }
            if m === veteranModifier { n += 8 }
            if m.source === role("dragoon") { n += 16 }
        }
        #expect(n == 31)

        let fortifiedModifier = try #require(spec.modifiers(Modifier.fortified).first)
        let hillsModifiers = hills.defenceModifiers
        #expect(hillsModifiers.count == 1)
        let hillsModifier = try #require(hillsModifiers.first)

        var defenceModifiers = combatModel.defensiveModifiers(soldier, colonist)
        #expect(defenceModifiers.count == 3)
        #expect(defenceModifiers.contains { $0 == fortifiedModifier })
        defenceModifiers.removeAll { $0 == fortifiedModifier }
        #expect(defenceModifiers.contains { $0 == hillsModifier })
        defenceModifiers.removeAll { $0 == hillsModifier }
        // This was also added by the combat model.
        #expect(defenceModifiers.first.map { isSource($0, Specification.SourceId.baseDefence) } == true)
    }

    @Test func galleonAttackedByPrivateer() throws {
        let (game, map, dutch, french) = setUp(ocean)
        let combatModel = game.combatModel
        let tile1 = try #require(map.tile(5, 8))
        let tile2 = try #require(map.tile(4, 8))
        for tile in [tile1, tile2] {
            tile.setExplored(dutch, true)
            tile.setExplored(french, true)
        }
        let galleon = Unit(game: game, location: tile1, owner: dutch, type: unitType("galleon"))
        let privateer = Unit(game: game, location: tile2, owner: french, type: unitType("privateer"))

        // Only the base modifiers apply.
        var offenceModifiers = combatModel.offensiveModifiers(privateer, galleon)
        #expect(offenceModifiers.count == 2)
        var n = 0
        for m in offenceModifiers {
            if isSource(m, Specification.SourceId.attackBonus) { n += 1 }
            if isSource(m, Specification.SourceId.baseOffence) { n += 2 }
        }
        #expect(n == 3)

        var defenceModifiers = combatModel.defensiveModifiers(privateer, galleon)
        #expect(defenceModifiers.count == 1)
        #expect(defenceModifiers.first.map { isSource($0, Specification.SourceId.baseDefence) } == true)

        // Fortification has no effect.
        galleon.setStateUnchecked(.fortified)
        defenceModifiers = combatModel.defensiveModifiers(privateer, galleon)
        #expect(defenceModifiers.count == 1)
        #expect(defenceModifiers.first.map { isSource($0, Specification.SourceId.baseDefence) } == true)

        // Penalties for cargo
        let lumberType = spec.getGoodsType("model.goods.lumber")!
        privateer.add(Goods(game: game, location: nil, type: lumberType, amount: 50))
        offenceModifiers = combatModel.offensiveModifiers(privateer, galleon)
        #expect(offenceModifiers.count == 3)
        n = 0
        for m in offenceModifiers {
            if isSource(m, Specification.SourceId.baseOffence) { n += 1 }
            if isSource(m, Specification.SourceId.attackBonus) { n += 2 }
            if isSource(m, Specification.SourceId.cargoPenalty) { n += 4 }
        }
        #expect(n == 7)

        galleon.add(Goods(game: game, location: nil, type: lumberType, amount: 150))
        #expect(galleon.visibleGoods == 2)
        defenceModifiers = combatModel.defensiveModifiers(privateer, galleon)
        #expect(defenceModifiers.count == 2)
        n = 0
        for m in defenceModifiers {
            if isSource(m, Specification.SourceId.baseDefence) { n += 1 }
            if isSource(m, Specification.SourceId.cargoPenalty) {
                n += 2
                #expect(m.value == -25)
            }
        }
        #expect(n == 3)

        // Francis Drake
        let drake = try #require(spec.getFoundingFather("model.foundingFather.francisDrake"))
        let drakeModifier = try #require(drake.modifiers(Modifier.offence, for: unitType("privateer")).first)
        french.addFather(drake)
        #expect(french.modifiers(Modifier.offence, for: unitType("privateer")).first === drakeModifier)

        offenceModifiers = combatModel.offensiveModifiers(privateer, galleon)
        #expect(offenceModifiers.count == 4)
        n = 0
        for m in offenceModifiers {
            if isSource(m, Specification.SourceId.baseOffence) { n += 1 }
            if m.source === drake { n += 2 }
            if isSource(m, Specification.SourceId.attackBonus) { n += 4 }
            if isSource(m, Specification.SourceId.cargoPenalty) {
                n += 8
                #expect(m.value == -12.5)
            }
        }
        #expect(n == 15)

        // The move is an attack.
        #expect(privateer.moveType(tile1) == .attackUnit, "Wrong move type")
    }

    @Test func defendColonyWithUnarmedColonist() throws {
        let (game, map, dutch, _) = setUp(explored: true)
        let colony = FreeColTestCase.standardColony(game)
        let inca = try #require(game.player(byNationId: "model.nation.inca"))
        let tile2 = try #require(map.tile(4, 8))
        tile2.setExplored(dutch, true)

        let colonist = try #require(colony.unitList.first)
        let attacker = Unit(game: game, location: tile2, owner: inca, type: braveType, role: role("armedBrave"))
        #expect(colony.defendingUnit(attacker) === colonist)
        #expect(colony.tile?.defendingUnit(attacker) === colonist)

        let defender = Unit(game: game, location: colony.tile, owner: dutch, type: colonistType)
        #expect(!defender.isDefensiveUnit, "Colonist should not be defensive unit")
        #expect(colony.tile?.defendingUnit(attacker) === defender)
    }

    @Test func defendColonyWithRevere() throws {
        let (game, map, dutch, _) = setUp(explored: true)
        let combatModel = SimpleCombatModel()
        let inca = try #require(game.player(byNationId: "model.nation.inca"))
        let colony = FreeColTestCase.standardColony(game)
        let tile2 = try #require(map.tile(4, 8))
        tile2.setExplored(dutch, true)
        let colonist = try #require(colony.unitList.first)
        let attacker = Unit(game: game, location: tile2, owner: inca, type: braveType, role: role("armedBrave"))

        // The colonist defends
        #expect(colony.defendingUnit(attacker) === colonist)

        // Set up for auto-equip
        dutch.addFather(spec.getFoundingFather("model.foundingFather.paulRevere")!)
        for ag in role("soldier").requiredGoods { colony.addGoods(ag) }

        // The colonist arms itself
        #expect(colonist.automaticRole === role("soldier"))
        let defenceModifiers = combatModel.defensiveModifiers(attacker, colonist)
        for m in role("soldier").modifiers(Modifier.defence) {
            #expect(defenceModifiers.contains { $0 == m })
        }
    }

    @Test func defendSettlement() throws {
        let (game, map, dutch, _) = setUp()
        let combatModel = SimpleCombatModel()
        let inca = try #require(game.player(byNationId: "model.nation.inca"))
        let tile1 = try #require(map.tile(5, 8))
        tile1.setExplored(dutch, true)
        let tile2 = try #require(map.tile(4, 8))
        tile2.setExplored(dutch, true)

        let settlement = IndianSettlementBuilder(game).player(inca).settlementTile(tile1).skillToTeach(nil)
            .capital(true).build()
        let defender = Unit(game: game, location: settlement, owner: inca, type: braveType,
                            role: role("nativeDragoon"))
        let attacker = Unit(game: game, location: tile2, owner: dutch, type: colonistType, role: role("dragoon"))
        for ag in role("nativeDragoon").requiredGoods { settlement.addGoods(ag) }

        let defenceModifiers = combatModel.defensiveModifiers(attacker, defender)
        for m in role("nativeDragoon").modifiers(Modifier.defence) {
            #expect(defenceModifiers.contains { $0 == m })
        }
    }

    @Test func attackIgnoresMovementPoints() throws {
        let (game, map, dutch, french) = setUp(plains, explored: true)
        let tile1 = try #require(map.tile(5, 8))
        let tile2 = try #require(map.tile(4, 8))
        tile1.type = hills
        #expect(tile1.type === hills)
        dutch.setStance(french, .war)
        french.setStance(dutch, .war)

        let colonist = Unit(game: game, location: tile1, owner: dutch, type: colonistType)
        colonist.setStateUnchecked(.fortified)
        let soldier = Unit(game: game, location: tile2, owner: french, type: unitType("veteranSoldier"),
                           role: role("dragoon"))
        soldier.setStateUnchecked(.fortified)
        #expect(colonist.location === tile1)
        #expect(soldier.location === tile2)

        #expect(soldier.moveType(tile2, tile1, 9) == .attackUnit)
        #expect(soldier.moveType(tile2, tile1, 1) == .attackUnit)
        #expect(soldier.moveType(tile2, tile1, 0) == .moveNoMoves)
    }

    @Test func spanishAgainstNatives() throws {
        let (game, map, dutch, _) = setUp(plains, explored: true)
        let spanish = try #require(game.player(byNationId: "model.nation.spanish"))
        let tupi = try #require(game.player(byNationId: "model.nation.tupi"))
        let combatModel = SimpleCombatModel()
        let tile1 = try #require(map.tile(5, 8))
        let tile2 = try #require(map.tile(4, 8))
        tile1.type = hills
        spanish.setStance(tupi, .war)
        tupi.setStance(spanish, .war)

        let soldier = Unit(game: game, location: tile1, owner: spanish, type: colonistType, role: role("soldier"))
        let brave = Unit(game: game, location: tile2, owner: tupi, type: braveType)
        #expect(soldier.location === tile1)
        #expect(brave.location === tile2)

        // The Spanish have a bonus against natives
        var offenceAgainst = combatModel.offensiveModifiers(soldier, brave).first { $0.id == Modifier.offenceAgainst }
        #expect(offenceAgainst.map { Int($0.value) } == 50)

        // but not against Europeans.
        let dutchSoldier = Unit(game: game, location: map.tile(6, 8), owner: dutch, type: colonistType,
                                role: role("soldier"))
        offenceAgainst = combatModel.offensiveModifiers(soldier, dutchSoldier)
            .first { $0.id == Modifier.offenceAgainst }
        #expect(offenceAgainst == nil)
    }

    @Test func attackShipWithLandUnit() throws {
        let (game, map, _, _) = setUp(plains, explored: true)
        let spanish = try #require(game.player(byNationId: "model.nation.spanish"))
        let tupi = try #require(game.player(byNationId: "model.nation.tupi"))
        let tile1 = try #require(map.tile(5, 8))
        let tile2 = try #require(map.tile(4, 8))
        tile1.type = hills
        tile2.type = ocean
        spanish.setStance(tupi, .war)
        tupi.setStance(spanish, .war)

        let galleon = Unit(game: game, location: tile2, owner: spanish, type: unitType("galleon"))
        let brave = Unit(game: game, location: tile1, owner: tupi, type: braveType)
        #expect(brave.location === tile1)
        #expect(galleon.location === tile2)

        #expect(galleon.moveType(tile2, tile1, 3) == .moveNoAccessLand)
        #expect(brave.moveType(tile1, tile2, 3) == .moveNoAccessEmbark)
    }

    @Test(.disabled("Needs the server: InGameController.createREFPlayer and ServerPlayer.csCombat (Phase 3)"))
    func regulars() {}

    @Test(.disabled("Needs the server: ServerTestHelper.startServerGame and ServerPlayer.csCombat (Phase 3)"))
    func captureConvert() {}
}

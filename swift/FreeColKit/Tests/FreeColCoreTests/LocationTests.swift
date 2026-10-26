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
import FreeColIO
import Testing

/// Units, their locations and goods, as read from the recorded game.
/// The values are checked against Java in MapTests; these check that
/// the pieces hang together.
@Suite(.serialized)
struct LocationTests {

    static func recordedGame() throws -> Game {
        try MapTests.read("freecol-seed1-turn005.fsg").game
    }

    static func units(_ game: Game) -> [Unit] {
        game.freeColGameObjects.compactMap { $0 as? Unit }
    }

    /// Every unit is in the location it names, once.
    @Test func unitsAreWhereTheySayTheyAre() throws {
        let game = try Self.recordedGame()
        let units = Self.units(game)
        #expect(units.count == 187)
        for u in units {
            let location = try #require(u.location, "\(u.id ?? "")")
            #expect(location.unitList.filter { $0 === u }.count == 1)
        }
        // Units in Europe and on the high seas are read with players.
        #expect(units.contains { $0.isInEurope })
        #expect(game.players.contains { !($0.highSeas?.destinations.isEmpty ?? true) })
    }

    /// Goods containers know their locations, and their goods say where
    /// they are.
    @Test func goodsKnowTheirLocations() throws {
        let game = try Self.recordedGame()
        for gl in game.freeColGameObjects.compactMap({ $0 as? GoodsLocation }) {
            guard let gc = gl.goodsContainer else { continue }
            #expect(gc.parent === gl)
            #expect(gc.owner === (gl as? Ownable)?.owner)
            for g in gl.goodsList {
                #expect(g.location === gl)
                #expect(g.amount <= GoodsContainer.cargoSize)
            }
        }
    }

    /// Moving goods between two holds changes both and remembers both.
    @Test func moveGoods() throws {
        let game = try Self.recordedGame()
        let spec = try #require(game.specification)
        let food = try #require(spec.primaryFoodType)
        let holders = Self.units(game).filter { $0.goodsContainer != nil }
        let a = holders[0], b = holders[1]
        let before = (a.goodsCount(food), b.goodsCount(food))
        a.addGoods(food, 50)
        GoodsLocation.moveGoods(a, food, 30, b)
        #expect(a.goodsCount(food) == before.0 + 20)
        #expect(b.goodsCount(food) == before.1 + 30)
        #expect(a.goodsContainer?.oldGoodsCount(food) == before.0 + 50)
        #expect(a.goodsContainer?.hasChanged == true)
        a.goodsContainer?.restoreState()
        #expect(a.goodsCount(food) == before.0 + 50)
    }

    /// A ship takes units until its holds are full, and part-filled
    /// holds take more of the same goods.
    @Test func cargoSpace() throws {
        let game = try Self.recordedGame()
        let spec = try #require(game.specification)
        let ship = try #require(Self.units(game).first { $0.isNaval && $0.canCarryGoods })
        let cargo = ship.unitList
        for u in cargo { #expect(ship.noAddReason(u) == .alreadyPresent) }
        let left = ship.spaceLeft
        let cotton = try #require(spec.getGoodsType("model.goods.cotton"))
        #expect(ship.loadableAmount(cotton) == left * 100 + (ship.goodsCount(cotton) % 100 == 0 ? 0
            : 100 - ship.goodsCount(cotton) % 100))
        ship.addGoods(cotton, 30)
        #expect(ship.spaceLeft == left - 1)
        #expect(ship.loadableAmount(cotton) == (left - 1) * 100 + 70)
    }

    /// The game owns everything: when it goes, so do units, goods
    /// containers, Europe and the high seas.
    @Test func gameOwnsUnitsAndGoods() throws {
        weak var unit: Unit?
        weak var container: GoodsContainer?
        weak var europe: Europe?
        weak var highSeas: HighSeas?
        do {
            let game = try Self.recordedGame()
            unit = Self.units(game).first { $0.isOnCarrier }
            container = unit?.carrier?.goodsContainer
            europe = game.players.compactMap(\.europe).first
            highSeas = game.players.compactMap(\.highSeas).first
            #expect(unit != nil && container != nil && europe != nil && highSeas != nil)
        }
        #expect(unit == nil)
        #expect(container == nil)
        #expect(europe == nil)
        #expect(highSeas == nil)
    }
}

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

/// TileItemContainerTest.java.
@Suite(.serialized)
struct TileItemContainerTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()

    func sample(_ game: Game, _ t: Tile, addImprovements: Bool, addResources: Bool,
                addRumours: Bool) -> TileItemContainer {
        if addImprovements {
            t.addRiver(1, "0101")
            t.addRoad()?.turnsToComplete = 0
        }
        if addResources {
            t.addResource(Resource(game: game, tile: t, type: Self.spec.getResourceType("model.resource.ore")!))
        }
        if addRumours {
            t.add(LostCityRumour(game: game, tile: t, type: .fountainOfYouth, name: "fountain"))
        }
        if t.tileItemContainer == nil {
            t.tileItemContainer = TileItemContainer(game: game, tile: t)
        }
        return t.tileItemContainer!
    }

    @Test func copyFromWithEveryThing() throws {
        let game = FreeColTestCase.standardGame(Self.spec)
        let map = FreeColTestCase.testMap(game)
        game.changeMap(map)

        let tOriginal = try #require(map.tile(8, 8))
        tOriginal.type = Self.spec.getTileType("model.tile.plains")
        let tCopy = try #require(map.tile(8, 9))
        tCopy.type = Self.spec.getTileType("model.tile.desert")
        let original = sample(game, tOriginal, addImprovements: true, addResources: true, addRumours: true)
        let copy = sample(game, tCopy, addImprovements: false, addResources: false, addRumours: false)

        #expect(original.road != nil, "Setup error, original must have road")
        #expect(copy.road == nil, "Setup error, copy cannot have road")
        #expect(original.river != nil, "Setup error, original must have river")
        #expect(copy.river == nil, "Setup error, copy cannot have river")
        #expect(original.resource != nil, "Setup error, original must have resource")
        #expect(copy.resource == nil, "Setup error, copy cannot have resource")
        #expect(original.lostCityRumour != nil, "Setup error, original must have rumour")
        #expect(copy.lostCityRumour == nil, "Setup error, copy cannot have rumour")

        copy.copyFrom(original, layer: .all)
        #expect(copy.road != nil, "Copy should have road")
        #expect(copy.river != nil, "Copy should have river")
        #expect(copy.resource != nil, "Copy should have resource")
        #expect(copy.lostCityRumour != nil, "Copy should have rumour")

        // Copy only natural
        copy.copyFrom(original, layer: .resources)
        #expect(copy.road == nil, "Copy should not have road")
        #expect(copy.river != nil, "Copy should have river")
        #expect(copy.resource != nil, "Copy should have resource")
        #expect(copy.lostCityRumour == nil, "Copy should not have rumour")
    }
}

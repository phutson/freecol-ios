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
import FreeColTestSupport
import Testing

/// ClassicTileProductionTest.java: the production of every tile type,
/// goods, resource, worker, set of improvements and colony bonus,
/// compared with the results confirmed in the classic game
/// (test/expected-data/verified-tile-production.csv) and the regression
/// results (expected-tile-production.csv).
///
/// Java writes the results to test/data/actual-tile-production.csv
/// first; here they are kept in memory.  Java's spec() is the freecol
/// rule set, despite the name.
@Suite(.serialized)
struct ClassicTileProductionTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    static let expectedDirectory = ReferenceDumps.repositoryRoot.appendingPathComponent("test/expected-data")

    struct TileImprovementTypeWithMagnitude {
        let tileImprovementType: TileImprovementType?
        let magnitude: Int
    }

    struct ProductionTestCombination {
        let tileType: TileType
        let goodsType: GoodsType
        let resourceType: ResourceType?
        let unitType: UnitType?
        let tileImprovementsWithMagnitude: [TileImprovementTypeWithMagnitude]
        let colonyProductionBonus: Int
    }

    @Test func tileProduction() throws {
        let actual = produceActualResults()
        try compare(Self.expectedDirectory.appendingPathComponent("verified-tile-production.csv"), actual)
        try compare(Self.expectedDirectory.appendingPathComponent("expected-tile-production.csv"), actual)
    }

    /// The results as Java's result file would have them, by everything
    /// after the production.
    func produceActualResults() -> [String: Int] {
        let game = FreeColTestCase.standardGame(spec)
        let tileImprovementColumns = spec.tileImprovementTypeList
        var result: [String: Int] = [:]
        for tileType in spec.tileTypeList {
            for goodsType in spec.farmedGoodsTypeList {
                for resourceType in tileType.resourceTypeValues.map(Optional.some) + [nil] {
                    let permutations = tileImprovementPermutations(tileType)
                    for unitType in unitTypesThatShouldBeTested(goodsType) {
                        for improvements in permutations {
                            for bonus in -2...2 {
                                let ptc = ProductionTestCombination(
                                    tileType: tileType, goodsType: goodsType, resourceType: resourceType,
                                    unitType: unitType, tileImprovementsWithMagnitude: improvements,
                                    colonyProductionBonus: bonus)
                                let output = execute(ptc, game, tileImprovementColumns)
                                result[output.key] = output.production
                            }
                        }
                    }
                }
            }
        }
        return result
    }

    func execute(_ ptc: ProductionTestCombination, _ game: Game,
                 _ tileImprovementColumns: [TileImprovementType]) -> (production: Int, key: String) {
        let defaultUnitType = spec.defaultUnitType!
        let pettyCriminalUnitType = spec.getUnitType("model.unit.pettyCriminal")!
        let indenturedServantUnitType = spec.getUnitType("model.unit.indenturedServant")!

        let tile = Tile(game: game, type: ptc.tileType, x: 0, y: 1)
        if let resourceType = ptc.resourceType {
            tile.addResource(Resource(game: game, tile: tile, type: resourceType))
        }
        for titwm in ptc.tileImprovementsWithMagnitude {
            let tileImprovement = TileImprovement(game: game, tile: tile, type: titwm.tileImprovementType!,
                                                  style: nil)
            tileImprovement.magnitude = titwm.magnitude
            tileImprovement.turnsToComplete = 0
            tile.add(tileImprovement)
        }

        let productionType = ProductionType.bestProductionType(
            ptc.goodsType, in: ptc.tileType.availableProductionTypes(unattended: false))
        let tpc = TileProductionCalculator(owner: nil, colonyProductionBonus: ptc.colonyProductionBonus)
        let pi: ProductionInfo
        if let unitType = ptc.unitType {
            pi = tpc.basicProductionInfo(tile, turn: Turn(1), WorkerAssignment(unitType, productionType),
                                         colonyCenterTile: false)
        } else {
            let unattendedProductionType = ProductionType.bestProductionType(
                ptc.goodsType, in: ptc.tileType.availableProductionTypes(unattended: true))
            pi = tpc.basicProductionInfo(tile, turn: Turn(1), WorkerAssignment(nil, unattendedProductionType),
                                         colonyCenterTile: true)
        }
        if ptc.unitType === defaultUnitType {
            let piCriminal = tpc.basicProductionInfo(tile, turn: Turn(1),
                                                     WorkerAssignment(pettyCriminalUnitType, productionType),
                                                     colonyCenterTile: false)
            #expect(productionAmount(ptc.goodsType, piCriminal) == productionAmount(ptc.goodsType, pi),
                    "Petty criminals should have the same production as a Free Colonist on tiles.")
            let piIndentured = tpc.basicProductionInfo(tile, turn: Turn(1),
                                                       WorkerAssignment(indenturedServantUnitType, productionType),
                                                       colonyCenterTile: false)
            #expect(productionAmount(ptc.goodsType, piIndentured) == productionAmount(ptc.goodsType, pi),
                    "Indentured Servants should have the same production as a Free Colonist on tiles.")
        }

        var fields = [ptc.tileType.id ?? "null", ptc.goodsType.id ?? "null", ptc.resourceType?.id ?? "",
                      ptc.unitType?.id ?? "unattended"]
        for columnType in tileImprovementColumns {
            let magnitude = ptc.tileImprovementsWithMagnitude
                .first { $0.tileImprovementType === columnType }?.magnitude ?? 0
            fields.append(String(magnitude))
        }
        fields.append(String(ptc.colonyProductionBonus))
        return (productionAmount(ptc.goodsType, pi), fields.joined(separator: ";"))
    }

    func unitTypesThatShouldBeTested(_ goodsType: GoodsType) -> [UnitType?] {
        var unitTypes: [UnitType?] = [spec.defaultUnitType!, spec.getUnitType("model.unit.indianConvert")!, nil]
        if let expert = spec.expert(producing: goodsType) { unitTypes.append(expert) }
        return unitTypes
    }

    func compare(_ expectedFile: URL, _ actual: [String: Int]) throws {
        let expected = try readResultFile(expectedFile)
        var failures: [String] = []
        for (key, value) in expected {
            let actualProduction = try #require(actual[key], "Missing actual production for: \(key)")
            if value != actualProduction { failures.append("\(value);\(actualProduction);\(key)") }
        }
        #expect(failures.isEmpty, """
            There are actual production values that do not match the expected values.
            Expected Production;Actual;key
            \(failures.sorted().joined(separator: "\n"))
            """)
    }

    func readResultFile(_ file: URL) throws -> [String: Int] {
        var result: [String: Int] = [:]
        let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines.dropFirst() { // Ignore the header.
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
            result[String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))] = Int(parts[0])!
        }
        return result
    }

    func productionAmount(_ goodsType: GoodsType, _ pi: ProductionInfo) -> Int {
        pi.production.first { $0.type == goodsType }?.amount ?? 0
    }

    func tileImprovementPermutations(_ tileType: TileType) -> [[TileImprovementTypeWithMagnitude]] {
        let tileImprovements = spec.tileImprovementTypeList.filter { $0.isTileTypeAllowed(tileType) }
        var result: [[TileImprovementTypeWithMagnitude]] = []
        for i in 0..<(1 << tileImprovements.count) {
            var permutation: [TileImprovementTypeWithMagnitude] = []
            var permutation2: [TileImprovementTypeWithMagnitude] = []
            var hasRiver = false
            for j in tileImprovements.indices where i & (1 << j) != 0 {
                let tileImprovementType = tileImprovements[j]
                permutation.append(TileImprovementTypeWithMagnitude(tileImprovementType: tileImprovementType,
                                                                    magnitude: 1))
                if tileImprovementType.id == "model.improvement.river" {
                    permutation2.append(TileImprovementTypeWithMagnitude(tileImprovementType: tileImprovementType,
                                                                         magnitude: 2))
                    hasRiver = true
                } else {
                    permutation2.append(TileImprovementTypeWithMagnitude(tileImprovementType: tileImprovementType,
                                                                         magnitude: 1))
                }
            }
            result.append(permutation)
            if hasRiver { result.append(permutation2) }
        }
        return result
    }
}

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
import Testing
import FreeColUtil
import FreeColXML
import FreeColCore
import FreeColIO
import FreeColTestSupport

/// The values net.sf.freecol.tools.dump.Derived records for a
/// specification, computed by the Swift port, in the same JSON form.
enum SpecDerived {

    static func of(_ spec: Specification) -> JSONValue {
        func byId<T: FreeColObject>(_ items: [T], _ f: (T) -> [String: JSONValue]) -> JSONValue {
            .object(Dictionary(uniqueKeysWithValues: items.map { ($0.id ?? "null", .object(f($0))) }))
        }
        return .object([
            "goodsTypes": byId(spec.goodsTypeList, goodsType),
            "unitTypes": byId(spec.unitTypeList, unitType),
            "tileTypes": byId(spec.tileTypeList) { tileType(spec, $0) },
            "buildingTypes": byId(spec.buildingTypeList, buildingType),
            "roles": byId(spec.rolesList, features),
            "foundingFathers": byId(spec.foundingFathers, features),
            "nationTypes": byId(spec.nationTypes, features),
            "defaultUnitType": id(spec.defaultUnitType),
            "options": .object(spec.registeredOptions.mapValues {
                .string("\(type(of: $0)) \($0)")
            }),
            "optionGroups": .object(spec.registeredOptionGroups.mapValues { g in
                .object(["id": g.id.map(JSONValue.string) ?? .null,
                         "options": .array(g.options.map { $0.id.map(JSONValue.string) ?? .null }),
                         "editable": .bool(g.isEditable),
                         "visible": .bool(g.isVisible),
                         "group": .string(g.group)])
            }),
            "difficultyLevel": spec.difficultyLevel.map(JSONValue.string) ?? .null,
            "ages": .array(spec.ages.map(int)),
            "turnCalendar": .object(["startingYear": int(spec.turnCalendar.startingYear),
                                     "seasonYear": int(spec.turnCalendar.seasonYear),
                                     "seasonNumber": int(spec.turnCalendar.seasonNumber)]),
        ])
    }

    // JSON helpers matching Java's Json writer.
    static func id(_ o: FreeColObject?) -> JSONValue { o?.id.map(JSONValue.string) ?? .null }
    static func int(_ i: Int) -> JSONValue { .integer(Int64(i)) }
    static func bool(_ b: Bool) -> JSONValue { .bool(b) }
    static func double(_ d: Double) -> JSONValue { .decimal(d) }
    /// A Java float is written with Float.toString, so compare through
    /// the same text.
    static func float(_ f: Float) -> JSONValue { .decimal(Double(JavaNumberFormat.string(f))!) }
    static func ids(_ items: [FreeColObject]) -> JSONValue { .array(items.map(id)) }
    static func sortedStrings(_ items: [CustomStringConvertible]) -> JSONValue {
        .array(items.map(\.description).sorted { JavaString.compare($0, $1) < 0 }.map(JSONValue.string))
    }
    static func goods(_ items: [AbstractGoods]) -> JSONValue {
        .array(items.map { .string("\($0.type?.id ?? "null"):\($0.amount)") })
    }

    static func features(_ o: FreeColObject) -> [String: JSONValue] {
        ["abilities": sortedStrings(o.sortedAbilities),
         "modifiers": sortedStrings(o.allModifiers)]
    }

    static func goodsType(_ gt: GoodsType) -> [String: JSONValue] {
        var m = features(gt)
        m["farmed"] = bool(gt.isFarmed)
        m["food"] = bool(gt.isFoodType)
        m["storable"] = bool(gt.isStorable)
        m["rawMaterial"] = bool(gt.isRawMaterial)
        m["refined"] = bool(gt.isRefined)
        m["buildingMaterial"] = bool(gt.isBuildingMaterial)
        m["libertyType"] = bool(gt.isLibertyType)
        m["immigrationType"] = bool(gt.isImmigrationType)
        m["inputType"] = id(gt.inputType)
        m["outputType"] = id(gt.outputType)
        m["storedAs"] = id(gt.storedAs)
        m["breedingNumber"] = int(gt.breedingNumber)
        m["price"] = int(gt.price)
        m["initialAmount"] = int(gt.initialAmount)
        m["productionChain"] = ids(gt.productionChain)
        return m
    }

    static func buildable(_ bt: BuildableType) -> [String: JSONValue] {
        ["requiredPopulation": int(bt.requiredPopulation),
         "requiredGoods": goods(bt.requiredGoods),
         "requiredAbilities": .object(bt.requiredAbilities.mapValues(JSONValue.bool))]
    }

    static func unitType(_ ut: UnitType) -> [String: JSONValue] {
        var m = features(ut)
        m["baseOffence"] = int(ut.baseOffence)
        m["baseDefence"] = int(ut.baseDefence)
        m["offence"] = double(ut.offence)
        m["defence"] = double(ut.defence)
        m["movement"] = int(ut.movement)
        m["lineOfSight"] = int(ut.lineOfSight)
        m["space"] = int(ut.space)
        m["spaceTaken"] = int(ut.spaceTaken)
        m["hitPoints"] = int(ut.hitPoints)
        m["skill"] = int(ut.skill)
        m["price"] = int(ut.price)
        m["mercenaryPrice"] = int(ut.mercenaryPrice)
        m["recruitProbability"] = int(ut.recruitProbability)
        m["maximumExperience"] = int(ut.maximumExperience)
        m["scoreValue"] = int(ut.scoreValue)
        m["naval"] = bool(ut.isNaval)
        m["person"] = bool(ut.isPerson)
        m["expertProduction"] = id(ut.expertProduction)
        m["skillTaught"] = id(ut.skillTaught)
        m["defaultRole"] = id(ut.defaultRole)
        m["consumedGoods"] = goods(ut.consumedGoods)
        m.merge(buildable(ut)) { $1 }
        return m
    }

    static func tileType(_ spec: Specification, _ tt: TileType) -> [String: JSONValue] {
        var m = features(tt)
        m["water"] = bool(tt.isWater)
        m["forested"] = bool(tt.isForested)
        m["elevation"] = bool(tt.isElevation)
        m["basicMoveCost"] = int(tt.basicMoveCost)
        m["basicWorkTurns"] = int(tt.basicWorkTurns)
        m["resourceTypes"] = ids(tt.resourceTypeValues)
        let colonist = spec.defaultUnitType
        var unattended: [String: JSONValue] = [:], worked: [String: JSONValue] = [:]
        for gt in spec.goodsTypeList {
            let u = tt.potentialProduction(gt, nil), w = tt.potentialProduction(gt, colonist)
            if u != 0 { unattended[gt.id!] = int(u) }
            if w != 0 { worked[gt.id!] = int(w) }
        }
        m["potentialUnattended"] = .object(unattended)
        m["potentialByDefaultUnit"] = .object(worked)
        return m
    }

    static func buildingType(_ bt: BuildingType) -> [String: JSONValue] {
        var m = features(bt)
        m["level"] = int(bt.level)
        m["workPlaces"] = int(bt.workPlaces)
        m["minimumSkill"] = int(bt.minimumSkill)
        m["maximumSkill"] = int(bt.maximumSkill)
        m["upkeep"] = int(bt.upkeep)
        m["priority"] = int(bt.priority)
        m["competenceFactor"] = float(bt.competenceFactor)
        m["rebelFactor"] = float(bt.rebelFactor)
        m["expertConnectionProduction"] = int(bt.expertConnectionProduction)
        m["automaticBuild"] = bool(bt.isAutomaticBuild)
        m["defenceType"] = bool(bt.isDefenceType)
        m["upgradesFrom"] = id(bt.upgradesFrom)
        m["upgradesTo"] = id(bt.upgradesTo)
        m["firstLevel"] = id(bt.firstLevel)
        m["producedGoodsType"] = id(bt.producedGoodsType)
        m.merge(buildable(bt)) { $1 }
        return m
    }
}

/// Lists every difference between two JSON values, by path.
func jsonDifferences(_ a: JSONValue, _ b: JSONValue, _ path: String = "") -> [String] {
    switch (a, b) {
    case let (.object(x), .object(y)):
        var out: [String] = []
        for key in Set(x.keys).union(y.keys).sorted() {
            switch (x[key], y[key]) {
            case let (u?, v?): out += jsonDifferences(u, v, "\(path)/\(key)")
            case (nil, _): out.append("\(path)/\(key): missing in Swift")
            case (_, nil): out.append("\(path)/\(key): only in Swift")
            }
        }
        return out
    default:
        return a == b ? [] : ["\(path): Swift \(a) vs Java \(b)"]
    }
}

struct SpecificationTests {

    static func load(_ rules: String) throws -> (Specification, JSONValue) {
        let dir = JavaOracle.url.deletingLastPathComponent()
        let spec = try Specification(resolved: Data(contentsOf: dir.appendingPathComponent("spec-\(rules).xml")))
        let java = try JSONValue.parse(Data(contentsOf: dir.appendingPathComponent("spec-\(rules).json")))
        return (spec, java)
    }

    /// Reading the resolved XML gives everything the Java server had,
    /// as a Java client reading it does.
    @Test(arguments: ["classic", "freecol", "freecol-veryHard"])
    func resolvedSpecMatchesJava(rules: String) throws {
        let (spec, java) = try Self.load(rules)
        let diffs = jsonDifferences(SpecDerived.of(spec), try #require(java["derived"]))
        #expect(diffs.isEmpty, "\(diffs.count) differences, first: \(diffs.prefix(15).joined(separator: "\n"))")
    }

    static let data = FreeColDataDirectory(url: ReferenceDumps.repositoryRoot.appendingPathComponent("data"))

    /// Loading the raw rule sets (freecol extends classic) gives the same
    /// specification as Java: every type, option, group, the ages and
    /// the calendar.
    @Test(arguments: [("classic", "model.difficulty.medium", "classic"),
                      ("freecol", "model.difficulty.medium", "freecol"),
                      ("freecol", "model.difficulty.veryHard", "freecol-veryHard")])
    func rawRulesMatchJava(rules: String, difficulty: String, dump: String) throws {
        let spec = try Self.data.loadSpecification(rules, difficulty: difficulty)
        let (_, java) = try Self.load(dump)
        let diffs = jsonDifferences(SpecDerived.of(spec), try #require(java["derived"]))
        #expect(diffs.isEmpty, "\(diffs.count) differences, first: \(diffs.prefix(15).joined(separator: "\n"))")
    }

    static let modDumps: [String] = {
        let dir = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("mods")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".json") }.sorted()
    }()

    /// Each mod loaded onto the freecol rules matches Java.
    @Test(arguments: modDumps)
    func modsMatchJava(dump: String) throws {
        let dir = JavaOracle.url.deletingLastPathComponent().appendingPathComponent("mods")
        let java = try JSONValue.parse(Data(contentsOf: dir.appendingPathComponent(dump)))
        let mods = try #require(java["mods"]?.arrayValue).compactMap(\.stringValue)
        let spec = try Self.data.loadSpecification("freecol", mods: mods,
                                                   difficulty: "model.difficulty.medium")
        let diffs = jsonDifferences(SpecDerived.of(spec), try #require(java["derived"]))
        #expect(diffs.isEmpty, "\(diffs.count) differences, first: \(diffs.prefix(15).joined(separator: "\n"))")
    }

    @Test func allModsAreTested() {
        #expect(Self.modDumps.count == 15)
    }

    @Test(arguments: ["classic", "freecol"])
    func readsEverySection(rules: String) throws {
        let (spec, _) = try Self.load(rules)
        #expect(spec.id == rules)
        #expect(spec.difficultyLevel == "model.difficulty.medium")
        #expect(spec.goodsTypeList.count == 21)
        #expect(spec.unitTypeList.count == 42)
        #expect(spec.tileTypeList.count == 23)
        #expect(spec.buildingTypeList.count == 41)
        #expect(!spec.rolesList.isEmpty && !spec.foundingFathers.isEmpty && !spec.nations.isEmpty)
        #expect(!spec.events.isEmpty && !spec.disasters.isEmpty && !spec.unitChangeTypeList.isEmpty)
        #expect(spec.europeanNations.count + spec.refNations.count + spec.indianNations.count
                == spec.nations.count - 1) // Less the unknown enemy.
        #expect(spec.unitTypeList.enumerated().allSatisfy { $0.offset == $0.element.index })
        #expect(spec.getString(GameOptions.tileProduction) != nil)
        #expect(spec.isInitialized)
    }

    /// Production types for exactly the level win over general ones.
    /// The derived values cannot show this: in these rules the
    /// level-specific production never beats the general production.
    @Test func exactProductionLevelsWin() throws {
        let (spec, _) = try Self.load("freecol")
        let desert = try #require(spec.getTileType("model.tile.desert"))
        let veryLow = desert.availableProductionTypes(unattended: true, level: "veryLow")
        #expect(veryLow.count == 1 && veryLow.allSatisfy { $0.productionLevel == "veryLow" })
        let medium = desert.availableProductionTypes(unattended: true, level: "medium")
        #expect(!medium.isEmpty && medium.allSatisfy { $0.productionLevel == nil })
        let any = desert.availableProductionTypes(unattended: true, level: nil)
        #expect(any.count > medium.count)
    }

    /// Only the specification's own difficulty level sets option values.
    @Test func optionValuesComeFromTheChosenDifficulty() throws {
        let (medium, _) = try Self.load("freecol")
        let (veryHard, _) = try Self.load("freecol-veryHard")
        #expect(medium.difficultyLevel == "model.difficulty.medium")
        #expect(veryHard.difficultyLevel == "model.difficulty.veryHard")
        #expect(medium.getString("model.option.tileProduction") == "medium")
        #expect(veryHard.getString("model.option.tileProduction") == "veryLow")
    }

    @Test func unknownTypesFailAfterLoading() throws {
        let (spec, _) = try Self.load("freecol")
        #expect(throws: FreeColXMLError.self) { try spec.findType("model.unit.nonsense", UnitType.self) }
        #expect(throws: FreeColXMLError.self) { try spec.findType("model.goods.food", UnitType.self) }
        #expect(spec.getUnitType("model.goods.food") == nil)
    }

    @Test func lookupsWork() throws {
        let (spec, _) = try Self.load("freecol")
        #expect(spec.primaryFoodType?.id == "model.goods.food")
        #expect(spec.defaultRole?.isDefaultRole == true)
        #expect(spec.missionaryRole?.id == "model.role.missionary")
        #expect(spec.expert(producing: spec.getGoodsType("model.goods.furs")!)?.id == "model.unit.expertFurTrapper")
        #expect(spec.fastestNavalUnitType != nil && spec.fastestLandUnitType != nil)
        let scot = spec.getUnitType("model.unit.freeColonist")!
        let farmer = spec.getUnitType("model.unit.expertFarmer")!
        #expect(scot.teachingType(farmer) === farmer)
        #expect(spec.neededTurnsOfTraining(farmer, scot) == 4)
        #expect(!spec.militaryRolesList.isEmpty && spec.militaryRolesList.allSatisfy(\.isOffensive))
    }
}

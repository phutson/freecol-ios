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
import Testing

/// SpecificationTest.java.
@Suite(.serialized)
struct SpecificationTest {

    nonisolated(unsafe) static let spec = FreeColTestCase.loadSpecification()
    var spec: Specification { Self.spec }

    var depotType: BuildingType { spec.getBuildingType("model.building.depot")! }
    var fishType: GoodsType { spec.getGoodsType("model.goods.fish")! }
    var foodType: GoodsType { spec.primaryFoodType! }
    var horsesType: GoodsType { spec.getGoodsType("model.goods.horses")! }
    var musketsType: GoodsType { spec.getGoodsType("model.goods.muskets")! }
    var toolsType: GoodsType { spec.getGoodsType("model.goods.tools")! }
    var blackSmithType: UnitType { spec.getUnitType("model.unit.masterBlacksmith")! }
    var braveType: UnitType { spec.getUnitType("model.unit.brave")! }
    var caravelType: UnitType { spec.getUnitType("model.unit.caravel")! }
    var freeColonistType: UnitType { spec.getUnitType("model.unit.freeColonist")! }
    var kingsRegularType: UnitType { spec.getUnitType("model.unit.kingsRegular")! }
    var privateerType: UnitType { spec.getUnitType("model.unit.privateer")! }
    var wagonType: UnitType { spec.getUnitType("model.unit.wagonTrain")! }

    /// A specification can be created without an error.
    @Test func load() throws {
        let spec = try FreeColTestCase.data.loadSpecification("classic", difficulty: nil)
        #expect(spec.getUnitType("model.unit.freeColonist") != nil)
    }

    /// Some typical abilities.
    @Test func unitAbilities() {
        #expect(freeColonistType.hasAbility(Ability.foundColony))
        #expect(!freeColonistType.hasAbility(Ability.bornInIndianSettlement))
        #expect(freeColonistType.isRecruitable)
        #expect(!freeColonistType.hasAbility(Ability.navalUnit))
        #expect(!freeColonistType.hasAbility(Ability.carryGoods))
        #expect(!freeColonistType.hasAbility(Ability.carryUnits))
        #expect(!freeColonistType.hasAbility(Ability.captureGoods))

        #expect(!wagonType.hasAbility(Ability.foundColony))
        #expect(!wagonType.isRecruitable)
        #expect(!wagonType.hasAbility(Ability.navalUnit))
        #expect(wagonType.hasAbility(Ability.carryGoods))
        #expect(!wagonType.hasAbility(Ability.carryUnits))
        #expect(!wagonType.hasAbility(Ability.captureGoods))

        #expect(braveType.hasAbility(Ability.bornInIndianSettlement))
        #expect(!braveType.isRecruitable)
        #expect(!braveType.hasAbility(Ability.navalUnit))
        #expect(braveType.hasAbility(Ability.carryGoods))
        #expect(!braveType.hasAbility(Ability.carryUnits))
        #expect(!braveType.hasAbility(Ability.captureGoods))

        #expect(!caravelType.hasAbility(Ability.foundColony))
        #expect(!caravelType.isRecruitable)
        #expect(caravelType.hasAbility(Ability.navalUnit))
        #expect(caravelType.hasAbility(Ability.carryGoods))
        #expect(caravelType.hasAbility(Ability.carryUnits))
        #expect(!caravelType.hasAbility(Ability.captureGoods))

        #expect(!privateerType.hasAbility(Ability.foundColony))
        #expect(!privateerType.isRecruitable)
        #expect(privateerType.hasAbility(Ability.navalUnit))
        #expect(privateerType.hasAbility(Ability.carryGoods))
        #expect(privateerType.hasAbility(Ability.carryUnits))
        #expect(privateerType.hasAbility(Ability.captureGoods))
    }

    @Test func foundingFathers() throws {
        let smith = try #require(spec.getFoundingFather("model.foundingFather.adamSmith"))
        #expect(smith.type == .trade)
        // The weight is some value in [0, 10].
        for age in 0...2 {
            #expect(smith.weight(age) >= 0)
            #expect(smith.weight(age) <= 10)
        }
        #expect(smith.weight(-1) == 0)
        #expect(smith.weight(34) == 0)
        #expect(smith.hasAbility(Ability.buildFactory))
    }

    @Test func modifiers() throws {
        // Additive
        var modifier = try #require(depotType.modifiers(Modifier.warehouseStorage).first)
        #expect(modifier.type == .additive)
        #expect(modifier.value == 100)

        // Multiplicative
        modifier = try #require(blackSmithType.modifiers("model.goods.tools").first)
        #expect(modifier.type == .multiplicative)
        #expect(modifier.value == 2)
    }

    @Test func nations() {
        // 4 original European nations, 4 in the freecol rules.  The
        // unknown enemy is deliberately not a European nation.
        #expect(spec.europeanNations.count == 8)
        // 8 original native nations
        #expect(spec.indianNations.count == 8)
        // The unknown enemy has no REF
        #expect(spec.refNations.count == spec.europeanNations.count)
    }

    @Test func nationTypes() {
        #expect(spec.indianNationTypes.count == 8)
        #expect(spec.refNationTypes.count == 1)
    }

    @Test func requiredAbilitiesForRoles() throws {
        let european: [String: Bool] = [Ability.canBeEquipped: true, Ability.native: false,
                                        Ability.refUnit: false]
        let ref: [String: Bool] = [Ability.canBeEquipped: true, Ability.native: false,
                                   Ability.refUnit: true, Ability.royalExpeditionaryForce: true]
        let native: [String: Bool] = [Ability.canBeEquipped: true, Ability.native: true,
                                      Ability.refUnit: false]
        var missionary = european
        missionary[Ability.dressMissionary] = true
        let roleAbilities: [String: [String: Bool]] = [
            "model.role.scout": european,
            "model.role.soldier": european,
            "model.role.dragoon": european,
            "model.role.pioneer": european,
            "model.role.missionary": missionary,
            "model.role.infantry": ref,
            "model.role.cavalry": ref,
            "model.role.mountedBrave": native,
            "model.role.armedBrave": native,
            "model.role.nativeDragoon": native,
        ]
        for (roleId, expected) in roleAbilities {
            let role = try #require(spec.getRole(roleId))
            #expect(role.requiredAbilities == expected, "\(roleId)")
        }

        func goods(_ roleId: String, _ results: AbstractGoods...) throws {
            let role = try #require(spec.getRole(roleId))
            var check = role.requiredGoods
            for ag in results {
                let i = check.firstIndex { $0 == ag }
                #expect(i != nil, "\(roleId) requires \(ag)")
                if let i { check.remove(at: i) }
            }
            #expect(check.isEmpty, "\(roleId) requires more goods")
        }
        try goods("model.role.default")
        try goods("model.role.scout", AbstractGoods(horsesType, 50))
        try goods("model.role.soldier", AbstractGoods(musketsType, 50))
        try goods("model.role.dragoon", AbstractGoods(horsesType, 50), AbstractGoods(musketsType, 50))
        try goods("model.role.pioneer", AbstractGoods(toolsType, 20))
        try goods("model.role.missionary")
        try goods("model.role.infantry", AbstractGoods(musketsType, 50))
        try goods("model.role.cavalry", AbstractGoods(horsesType, 50), AbstractGoods(musketsType, 50))
        try goods("model.role.mountedBrave", AbstractGoods(horsesType, 25))
        try goods("model.role.armedBrave", AbstractGoods(musketsType, 25))
        try goods("model.role.nativeDragoon", AbstractGoods(horsesType, 25), AbstractGoods(musketsType, 25))
    }

    @Test func goodsTypes() {
        #expect(foodType.isFarmed)
        #expect(spec.farmedGoodsTypeList.contains(foodType))
        #expect(foodType.isFoodType)
        #expect(spec.foodGoodsTypeList.contains(foodType))

        #expect(fishType.isFarmed)
        #expect(spec.farmedGoodsTypeList.contains(fishType))
        #expect(fishType.isFoodType)
        #expect(spec.foodGoodsTypeList.contains(fishType))
    }

    @Test func extends() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>\
            <freecol-specification id="test" extends="freecol">\
            <unit-types>\
            <unit-type id="model.unit.milkmaid" extends="colonist" expert-production="model.goods.food" />\
            </unit-types>\
            </freecol-specification>
            """
        let spec = try Specification(resolved: Data(xml.utf8), source: FreeColTestCase.data)
        #expect(spec.getUnitType("model.unit.milkmaid") != nil)
        #expect(spec.getUnitType("model.unit.caravel") != nil)
    }

    @Test func extendsDelete() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>\
            <freecol-specification id="test" extends="freecol">\
            <unit-types>\
            <delete id="model.unit.caravel" />\
            </unit-types>\
            </freecol-specification>
            """
        let spec = try Specification(resolved: Data(xml.utf8), source: FreeColTestCase.data)
        #expect(spec.getUnitType("model.unit.caravel") == nil, "Caravel should be undefined")
        #expect(!spec.unitTypeList.contains { $0.id == "model.unit.caravel" })
    }

    @Test func getDefaultUnitType() throws {
        let europeanNationType = try #require(spec.nationTypes.first { !$0.isIndian && !$0.isREF },
                                              "No European nation type")
        let nativeNationType = try #require(spec.nationTypes.first { $0.isIndian }, "No native nation type")
        let refNationType = try #require(spec.nationTypes.first { $0.isREF }, "No REF nation type")
        #expect(spec.defaultUnitType(europeanNationType) === freeColonistType, "Should find free colonist")
        #expect(spec.defaultUnitType(nativeNationType) === braveType, "Should find brave")
        #expect(spec.defaultUnitType(refNationType) === kingsRegularType, "Should find kings regular")
    }

    @Test func loadMods() throws {
        let spec = try FreeColTestCase.data.loadSpecification("freecol", difficulty: nil)
        let numberOfUnitTypes = spec.unitTypeList.count
        try spec.loadMods([FreeColTestCase.data.mods()["example"]?.specificationData()])
        #expect(spec.getUnitType("model.unit.milkmaid") != nil)
        #expect(spec.unitTypeList.count == numberOfUnitTypes + 1)
    }
}

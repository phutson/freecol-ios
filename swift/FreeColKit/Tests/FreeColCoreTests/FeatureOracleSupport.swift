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
import FreeColTestSupport

/// A minimal rule type, like FeatureOracle.TestType in Java.
final class TestType: FreeColSpecObjectType {
    convenience init(_ id: String) {
        self.init(id: id, specification: nil)
    }

    required init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    override var xmlTagName: String { "test-type" }
}

/// Rebuilds the objects FeatureOracle describes.
///
/// The type pool matches Java's: one shared object per id, with the
/// same abilities, so scopes and sources resolve the same way.
final class FeatureBuilder {
    private var pool: [String: TestType] = [:]

    init() {
        type("model.unit.expertFarmer")!.addAbility(Ability("model.ability.expertsUseConnections"))
        type("model.unit.artillery")!.addAbility(Ability("model.ability.bombard"))
        type("model.unit.freeColonist")!.addAbility(Ability("model.ability.bombard", value: false))
    }

    func type(_ id: String?) -> TestType? {
        guard let id else { return nil }
        if let t = pool[id] { return t }
        let t = TestType(id)
        pool[id] = t
        return t
    }

    func scope(_ json: JSONValue) -> Scope {
        let s = Scope()
        s.type = json["type"]?.stringValue
        s.abilityId = json["abilityId"]?.stringValue
        s.abilityValue = json["abilityValue"] == .bool(true)
        s.methodName = json["methodName"]?.stringValue
        s.methodValue = json["methodValue"]?.stringValue
        s.matchNegated = json["matchNegated"] == .bool(true)
        s.matchesNull = json["matchesNull"] == .bool(true)
        return s
    }

    private func fillFeature(_ f: Feature, _ json: JSONValue) {
        f.source = type(json["source"]?.stringValue)
        f.firstTurn = json["firstTurn"]?.intValue.map { Turn(Int($0)) }
        f.lastTurn = json["lastTurn"]?.intValue.map { Turn(Int($0)) }
        f.duration = Int(json["duration"]?.intValue ?? 0)
        f.temporary = json["temporary"] == .bool(true)
        for s in json["scopes"]?.arrayValue ?? [] { f.addScope(scope(s)) }
    }

    func modifier(_ json: JSONValue) -> Modifier {
        let m = Modifier(json["id"]?.stringValue,
                         float(json["valueBits"]),
                         Modifier.ModifierType(javaName: json["type"]!.stringValue!)!,
                         index: Int(json["index"]!.intValue!))
        fillFeature(m, json)
        if let inc = json["incrementType"]?.stringValue {
            m.incrementType = Modifier.ModifierType(javaName: inc)
        }
        m.increment = float(json["incrementBits"])
        return m
    }

    func ability(_ json: JSONValue) -> Ability {
        let a = Ability(json["id"]?.stringValue, value: json["value"] == .bool(true))
        fillFeature(a, json)
        return a
    }
}

/// A Float from the raw bits Java recorded.
func float(_ json: JSONValue?) -> Float {
    Float(bitPattern: UInt32(truncatingIfNeeded: json!.intValue!))
}

/// The raw bits of a Float, as Java's floatToRawIntBits.
func bits(_ f: Float) -> Int64 {
    Int64(Int32(bitPattern: f.bitPattern))
}

/// The oracle's features section, loaded once.
enum FeatureCases {
    static let features: JSONValue? = try? JavaOracle.load()["features"]

    static func list(_ key: String) -> [JSONValue] {
        features?[key]?.arrayValue ?? []
    }
}

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

import CryptoKit
import Foundation
import FreeColCore
import FreeColIO
import FreeColTestSupport
import FreeColUtil
import Testing

/// The messages, templates and labels, compared with what Java makes
/// of the bundled strings (I18nOracle.java).
///
/// The message bundle is global, as in Java, so the tests run one at a
/// time and each loads the languages it needs.
@Suite(.serialized)
struct I18nTests {

    static let stringsDirectory = ReferenceDumps.repositoryRoot.appendingPathComponent("data/strings")
    static let oracleDirectory = MapTests.oracleDirectory.appendingPathComponent("i18n")

    nonisolated(unsafe) static let numberRules: NumberRules = {
        try! NumberRules(data: Data(contentsOf: stringsDirectory.appendingPathComponent("plurals.xml")))
    }()

    /// The rule sets Java loads messages from.
    static let rulesDirectories = ["classic", "freecol"].map {
        ReferenceDumps.repositoryRoot.appendingPathComponent("data/rules/" + $0)
    }

    /// A language's messages.  The tests use them in place of the
    /// global ones (Messages.scopedBundle), which tests in other
    /// targets, running at the same time, rely on being English.
    static func bundle(_ languageId: String) -> MessageBundle {
        MessageBundle.load(directory: stringsDirectory, languageId: languageId,
                           numberRules: numberRules, rulesDirectories: rulesDirectories)
    }

    /// The language ids, from the message file names
    /// (FreeColDirectories.getLanguageIdList).
    static let languageIds: [String] = {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: stringsDirectory.path)) ?? []
        var ids: [String] = []
        for name in names where name.hasPrefix("FreeColMessages") && name.hasSuffix(".properties") {
            var id = String(name.dropFirst("FreeColMessages".count).dropLast(".properties".count))
            if id.isEmpty { id = "en" } else if id == "_qqq" { continue } else if id.hasPrefix("_") { id.removeFirst() }
            if !ids.contains(id) { ids.append(id) }
        }
        return ids.sorted(by: { JavaString.compare($0, $1) < 0 })
    }()

    static let javaDigests: [String: String] = {
        guard let data = try? Data(contentsOf: oracleDirectory.appendingPathComponent("digests.json")),
              let json = try? JSONValue.parse(data), let members = json.objectValue else { return [:] }
        return members.compactMapValues(\.stringValue)
    }()

    static func javaDocument(_ name: String) throws -> JSONValue {
        let archive = try ZipArchive(contentsOf: oracleDirectory.appendingPathComponent("full.zip"))
        return try JSONValue.parse(try #require(try archive.contents(of: name)))
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Against Java

    /// Every message, template and plural category of a language
    /// matches, compared one by one.
    @Test(arguments: ["en", "de", "ru", "pl_PL"])
    func languageMatchesJava(id: String) throws {
        let diffs = try Messages.$scopedBundle.withValue(Self.bundle(id)) {
            elementDifferences(I18nDerived.language(id), try Self.javaDocument(id + ".json"))
        }
        #expect(diffs.count == 0, "first: \(diffs.prefix(20).joined(separator: "\n"))")
    }

    /// The languages checked by digest: by default a dozen with
    /// different plural rules and scripts (all of them take over a
    /// minute in a debug build); FREECOL_ALL_MAPS=1 checks every one.
    static let digestedLanguages: [String] = {
        ProcessInfo.processInfo.environment["FREECOL_ALL_MAPS"] == "1" ? languageIds
            : ["ar", "be-tarask", "cs_CZ", "fr", "ga", "hsb", "ja", "lt", "pt_BR", "sk", "uk", "zh_CN"]
    }()

    /// The same for the other bundled languages, by digest.
    @Test func languagesMatchJava() throws {
        #expect(Self.languageIds.count == Self.javaDigests.count)
        var failed: [String] = []
        for id in Self.digestedLanguages {
            let document = Messages.$scopedBundle.withValue(Self.bundle(id)) {
                CanonicalJSON.document(I18nDerived.language(id))
            }
            if Self.sha256(document) != Self.javaDigests[id] { failed.append(id) }
        }
        #expect(failed.isEmpty, "Languages that differ: \(failed)")
    }

    /// The labels of the economy game, and its players' history and
    /// messages, in several languages.
    @Test func labelsMatchJava() throws {
        // As in Java, the season names are kept from the first language
        // that asks for them.
        Messages.seasonNames = nil
        let saved = try MapTests.read("freecol-economy-seed1.fsg")
        var doc: [String: JSONValue] = [:]
        for id in ["en", "de", "fr", "ru", "pl_PL", "ar", "ja"] {
            doc[id] = Messages.$scopedBundle.withValue(Self.bundle(id)) { I18nDerived.labels(saved.game) }
        }
        let diffs = elementDifferences(.object(doc), try Self.javaDocument("labels.json"))
        if let path = ProcessInfo.processInfo.environment["FREECOL_DIFF_FILE"], !diffs.isEmpty {
            try (diffs.joined(separator: "\n") + "\n").write(toFile: path + ".labels", atomically: true,
                                                            encoding: .utf8)
        }
        #expect(diffs.count == 0, "first: \(diffs.prefix(20).joined(separator: "\n"))")
    }

    // MARK: Pieces

    @Test func loaderFollowsJava() {
        let bundle = MessageBundle()
        bundle.load(Data("# comment\n a = one\\ntwo \r\nb=x=y\r=skipped\n  #c=not a comment\nd\\t=\\tz\n".utf8))
        #expect(bundle.value("a") == "one\ntwo")
        #expect(bundle.value("b") == "x=y")
        #expect(bundle.value("#c") == "not a comment" || bundle.value("#c") == nil)
        #expect(bundle.value("d\\t") == "\tz")
        #expect(bundle.count == 3)
    }

    @Test func templatesShareCopiedPairs() {
        let t = StringTemplate.template("a").addName("%x%", "1")
        let c = StringTemplate.copy("b", t)
        t.addName("%y%", "2")
        #expect(c.entryList.count == 2)
        #expect("\(c)" == "TEMPLATE:b[%x%=NAME:1%y%=NAME:2]")
    }

    @Test func pluralRules() {
        #expect(Self.numberRules.number(forLanguage: "en") === NumberRules.pluralNumberRule)
        // French's CLDR rule ("n within 0..2 and n is not 2") is not one
        // of the forms Java recognises, so Java gives it no plurals.
        #expect(Self.numberRules.number(forLanguage: "fr") === NumberRules.otherNumberRule)
        #expect(Self.numberRules.number(forLanguage: "hi") === NumberRules.zeroOneNumberRule)
        #expect(Self.numberRules.number(forLanguage: "ja") === NumberRules.otherNumberRule)
        let ru = Self.numberRules.number(forLanguage: "ru")
        #expect(ru.key("21", "") == "one" && ru.key("22", "") == "few" && ru.key("25", "") == "many")
    }
}

/// What I18nOracle.java records, computed in Swift.
enum I18nDerived {

    static let numbers = ["0", "1", "2", "5", "21"]
    static let selectors = [
        "0", "1", "2", "3", "4", "5", "6", "7", "10", "11", "12", "13", "14", "19", "20",
        "21", "22", "25", "100", "101", "102", "103", "111", "112", "1000", "0.5", "1.5",
        "2.0", "-1", "-2", "+3", " 4 ", "1e1", "3f", "4d", "NaN", "Infinity", "abc", "",
    ]

    /// The placeholders of a message, in order, once each (Java's
    /// %[A-Za-z0-9_]+% matches).
    static func placeholders(_ value: String) -> [String] {
        let u = Array(value.utf16)
        func word(_ c: UInt16) -> Bool {
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
        }
        var names: [String] = []
        var i = 0
        while i < u.count {
            if u[i] == 37 {
                var j = i + 1
                while j < u.count && word(u[j]) { j += 1 }
                if j > i + 1 && j < u.count && u[j] == 37 {
                    let name = String(decoding: u[i...j], as: UTF16.self)
                    if !names.contains(name) { names.append(name) }
                    i = j + 1
                    continue
                }
            }
            i += 1
        }
        return names
    }

    static func language(_ id: String) -> JSONValue {
        let bundle = Messages.bundle.messages
        var messages: [String: JSONValue] = [:]
        var templates: [String: JSONValue] = [:]
        var raw: [String: JSONValue] = [:]
        for (key, value) in bundle {
            raw[key] = .string(value)
            messages[key] = .string(Messages.message(key))
            let names = placeholders(value)
            if names.isEmpty && !value.contains("{{") { continue }
            templates[key] = .array(numbers.map { n in
                let t = StringTemplate.template(key)
                for name in names { t.addName(name, n) }
                return .string(Messages.message(t) ?? "null")
            })
        }
        let number = I18nTests.numberRules.number(forLanguage: Messages.localeParts(id).language)
        var plurals: [String: JSONValue] = [:]
        for s in selectors { plurals["[\(s)]"] = .string(number.key(s, "test")) }
        return .object([
            "count": .integer(Int64(bundle.count)),
            "bundle": .object(raw),
            "messages": .object(messages),
            "templates": .object(templates),
            "plurals": .object(plurals),
        ])
    }

    static func text(_ t: StringTemplate?) -> JSONValue {
        t.flatMap { Messages.message($0) }.map(JSONValue.string) ?? .null
    }

    static func textString(_ t: StringTemplate?) -> String {
        t.flatMap { Messages.message($0) } ?? "null"
    }

    static func full(_ t: StringTemplate?) -> JSONValue {
        guard let t else { return .array([.null, .null, .null]) }
        return .array([text(t), .string("\(t)"), .integer(Int64(t.javaHash))])
    }

    static func labels(_ game: Game) -> JSONValue {
        let spec = game.specification!
        let europeans = game.liveEuropeanPlayers
        var units: [String: JSONValue] = [:]
        for case let u as FreeColCore.Unit in game.freeColGameObjects {
            let other = europeans.first { $0 !== u.owner }
            var v: [JSONValue] = [
                text(u.label(.plain)), text(u.label(.national)), text(u.label(.full)),
                text(u.apparentOwnerName),
                text(u.occupationLabel(u.owner, true)), text(u.occupationLabel(u.owner, false)),
                text(u.occupationLabel(other, false)),
                u.destination == nil ? .null : text(u.destinationLabel),
                text(u.repairLabel), text(locationLabel(u)),
                u.location == nil ? .null : text(locationLabel(u.location)),
                u.location == nil ? .null : text(locationLabel(u.location, for: other)),
                .string(u.label(.full).map { "\($0)" } ?? "null"),
            ]
            if let tile = u.tile {
                for t in tile.surroundingTiles(1, 1) {
                    if let d = t.defendingUnit(u), d.owner !== u.owner {
                        v.append(text(u.combatLabel(t)))
                        break
                    }
                }
            }
            units[u.id!] = .array(v)
        }

        var settlements: [String: JSONValue] = [:]
        for o in game.freeColGameObjects {
            if let c = o as? Colony {
                var v: [JSONValue] = [text(locationLabel(c))]
                for p in europeans {
                    v.append(.string("\(textString(locationLabel(c, for: p))) | \(textString(c.alarmLevelLabel(p)))"))
                }
                v.append(text(c.reducePopulationMessage))
                for wl in c.allWorkLocations {
                    var s = "\(textString(locationLabel(wl))) | \(textString(locationLabel(wl, for: europeans[0])))"
                        + " | \(textString((wl as? ColonyTile)?.claimTemplate ?? StringTemplate.name("")))"
                    if let b = wl as? Building { s += " | \(textString(b.label))" }
                    if let ct = wl as? ColonyTile { s += " | \(textString(ct.label))" }
                    v.append(.string(s))
                }
                settlements[c.id!] = .array(v)
            } else if let s = o as? IndianSettlement {
                var v: [JSONValue] = [text(locationLabel(s))]
                for p in europeans {
                    v.append(.string("\(textString(locationLabel(s, for: p))) | \(textString(s.alarmLevelLabel(p)))"))
                }
                v.append(.string("\(textString(s.learnableSkillLabel(true))) | \(textString(s.learnableSkillLabel(false)))"))
                v.append(.string("\(textString(s.mostHatedLabel(true))) | \(textString(s.mostHatedLabel(false)))"))
                settlements[s.id!] = .array(v)
            }
        }

        var tiles: [String: JSONValue] = [:]
        for t in game.map!.tiles where (t.x * 7 + t.y) % 23 == 0 || t.hasSettlement {
            var v: [JSONValue] = [text(t.label), text(t.simpleLabel), text(locationLabel(t))]
            for p in europeans { v.append(text(locationLabel(t, for: p))) }
            tiles["\(t.x),\(t.y)"] = .array(v)
        }

        var players: [String: JSONValue] = [:]
        for p in game.players {
            var v: [JSONValue] = [
                text(p.label), text(p.nationLabel), text(p.countryLabel), text(p.forcesLabel),
                text(p.waitingLabel), text(p.marketName), text(p.checkDeclareIndependence),
            ]
            for he in p.history { v.append(full(he)) }
            for m in p.modelMessages {
                v.append(full(m))
                v.append(m.ignoredMessageKey.map(JSONValue.string) ?? .null)
            }
            // Java's HashMap toString.
            var turns = JavaHashMap<String, Int>(javaHash: JavaString.hashCode)
            for (k, t) in p.electionTurns { _ = turns.put(k, t.number) }
            v.append(.string("{" + turns.entries.map { "\($0.key)=\($0.value)" }.joined(separator: ", ") + "}"))
            for tr in p.tradeRoutes {
                v.append(.string("\(textString(tr.verify)) | \(textString(tr.verifyUniqueName))"))
            }
            players[p.id!] = .array(v)
        }

        let calendar = spec.turnCalendar
        let turns: [JSONValue] = [1, 2, 100, 108, 109, 110, 200, game.turn.number].map {
            text(Turn($0).label(calendar))
        }
        let goods: [JSONValue] = spec.goodsTypeList.map { gt in
            let ag = AbstractGoods(gt, 37)
            return .string("\(textString(ag.label)) | \(textString(ag.label(sellable: false))) | \(textString(gt.label))")
        }
        var aus: [JSONValue] = []
        for p in europeans {
            guard let monarch = p.monarch else { continue }
            for au in monarch.expeditionaryForce.unitList {
                aus.append(.string("\(textString(au.label(spec))) | \(textString(au.singleLabel))"))
            }
            aus.append(text(AbstractUnit.listLabel("model.player.forces", monarch.interventionForce.unitList)))
        }
        return .object([
            "units": .object(units), "settlements": .object(settlements), "tiles": .object(tiles),
            "players": .object(players),
            "misc": .object(["turns": .array(turns), "goods": .array(goods), "abstractUnits": .array(aus)]),
        ])
    }
}

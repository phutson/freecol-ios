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

/// Something a player asks the server to do: one of Java's messages
/// from a client, as a typed value.
///
/// Objects are named by identifier and values are given as the
/// message carries them, so a command can be checked as Java's server
/// checks a message (InGameController.perform), and read from Java's
/// message XML (init(tag:attributes:children:)).  Objects a message
/// carries whole (goods, a native trade) are kept as their XML, and read
/// into the game when the command is carried out.  So far: managing
/// units, colonies and goods, Europe, moving, dealing with natives,
/// combat, diplomacy, the monarch and independence.
public enum PlayerCommand: Equatable, Sendable {
    case abandonColony(colony: String?)
    /// Ask a native settlement what it teaches.
    case askSkill(unit: String?, direction: String?)
    /// Attack the tile in a direction.
    case attack(unit: String?, direction: String?)
    case assignTeacher(student: String?, teacher: String?)
    /// An empty name asks the server to choose one.
    case buildColony(name: String?, unit: String?)
    case cashInTreasureTrain(unit: String?)
    case changeState(unit: String?, state: String?)
    case changeWorkImprovementType(unit: String?, improvementType: String?)
    case changeWorkType(unit: String?, workType: String?)
    case chooseFoundingFather(father: String?)
    /// The claimant is a unit on the tile, or a settlement; a negative
    /// price steals the land.
    case claimLand(tile: String?, claimant: String?, price: String?)
    case clearSpeciality(unit: String?)
    /// Declare independence, naming the new nation and country.
    case declareIndependence(nationName: String?, countryName: String?)
    /// Leave the mounds on the tile in a direction unexplored.
    case declineMounds(unit: String?, direction: String?)
    /// Tribute from a native settlement, by an armed unit or a scout.
    case demandTribute(unit: String?, direction: String?)
    /// Give goods to a native settlement, in a trade session.
    case deliverGift(unit: String?, settlement: String?, goods: CommandElement?)
    /// A step in negotiating with another European, from either side.
    case diplomacy(our: String?, other: String?, agreement: CommandElement?)
    case disbandUnit(unit: String?)
    case disembark(unit: String?)
    /// With a direction the unit moves onto the carrier beside it.
    case embark(unit: String?, carrier: String?, direction: String?)
    case emigrateUnit(slot: String?)
    /// End the player's turn.
    case endTurn
    case equipForRole(unit: String?, role: String?, count: String?)
    /// The answer to meeting natives: peace, and any land they offered.
    case firstContact(player: String?, other: String?, tile: String?, result: String?)
    /// Ask natives to make war on another European; a negative gold
    /// asks the price.
    case incite(unit: String?, settlement: String?, enemy: String?, gold: String?)
    /// A native demand of a colony, or the colony's answer to one.
    case indianDemand(unit: String?, colony: String?, type: String?, amount: String?, result: String?)
    case joinColony(colony: String?, unit: String?)
    /// Learn what a native settlement teaches.
    case learnSkill(unit: String?, direction: String?)
    /// Establish or denounce a mission.
    case missionary(unit: String?, direction: String?, denounce: String?)
    case loadGoods(location: String?, type: String?, amount: String?, carrier: String?)
    /// The answer to the monarch's demand or offer.
    case monarchAction(action: String?, result: String?)
    /// Take cargo from a beaten ship.
    case lootCargo(winner: String?, loser: String?, goods: [CommandElement])
    /// Move to the tile in a direction.
    case move(unit: String?, direction: String?)
    /// Sail across the high seas, to Europe, the map, or a settlement.
    case moveTo(unit: String?, destination: String?)
    case nationSummary(player: String?)
    /// A natives' gift to a colony.
    case nativeGift(unit: String?, colony: String?)
    /// A step in trading with a native settlement, from either side.
    case nativeTrade(action: String?, trade: CommandElement?)
    case newLandName(unit: String?, name: String?)
    case newRegionName(region: String?, tile: String?, unit: String?, name: String?)
    case payArrears(goodsType: String?)
    case payForBuilding(colony: String?)
    case putOutsideColony(unit: String?)
    case rename(nameable: String?, name: String?)
    /// Look round a native settlement.
    case scoutIndianSettlement(unit: String?, direction: String?)
    case scoutSpeakToChief(unit: String?, settlement: String?)
    case setBuildQueue(colony: String?, queue: [String])
    /// The export data's attributes.
    case setGoodsLevels(colony: String?, exportData: [String: String]?)
    case setDestination(unit: String?, destination: String?)
    case trainUnitInEurope(unitType: String?)
    case unloadGoods(type: String?, amount: String?, carrier: String?)
    case work(unit: String?, workLocation: String?)

    /// A message's tag was not one of the commands.
    public struct UnknownMessage: Error, CustomStringConvertible {
        public let tag: String
        public var description: String { "Not a command: \(tag)" }
    }

    /// Read a command from Java's message: its tag, attributes and
    /// child elements.
    public init(tag: String, attributes a: [String: String], children: [CommandElement] = []) throws {
        switch tag {
        case "abandonColony": self = .abandonColony(colony: a["colony"])
        case "askSkill": self = .askSkill(unit: a["unit"], direction: a["direction"])
        case "attack": self = .attack(unit: a["unit"], direction: a["direction"])
        case "declareIndependence":
            self = .declareIndependence(nationName: a["nationName"], countryName: a["countryName"])
        case "diplomacy":
            self = .diplomacy(our: a["ourId"], other: a["otherId"],
                              agreement: children.first { $0.tag == "diplomaticTrade" })
        case "endTurn": self = .endTurn
        case "firstContact":
            self = .firstContact(player: a["player"], other: a["other"], tile: a["tile"], result: a["result"])
        case "monarchAction": self = .monarchAction(action: a["action"], result: a["result"])
        case "lootCargo":
            self = .lootCargo(winner: a["winner"], loser: a["loser"], goods: children.filter { $0.tag == "goods" })
        case "deliverGift":
            self = .deliverGift(unit: a["unit"], settlement: a["settlement"],
                                goods: children.first { $0.tag == "goods" })
        case "demandTribute": self = .demandTribute(unit: a["unit"], direction: a["direction"])
        case "incite": self = .incite(unit: a["unit"], settlement: a["settlement"], enemy: a["enemy"], gold: a["gold"])
        case "indianDemand":
            self = .indianDemand(unit: a["unit"], colony: a["colony"], type: a["type"], amount: a["amount"],
                                 result: a["result"])
        case "learnSkill": self = .learnSkill(unit: a["unit"], direction: a["direction"])
        case "missionary": self = .missionary(unit: a["unit"], direction: a["direction"], denounce: a["denounce"])
        case "nationSummary": self = .nationSummary(player: a["player"])
        case "nativeGift": self = .nativeGift(unit: a["unit"], colony: a["colony"])
        case "nativeTrade":
            self = .nativeTrade(action: a["action"], trade: children.first { $0.tag == "nativeTrade" })
        case "scoutIndianSettlement": self = .scoutIndianSettlement(unit: a["unit"], direction: a["direction"])
        case "scoutSpeakToChief": self = .scoutSpeakToChief(unit: a["unit"], settlement: a["settlement"])
        case "assignTeacher": self = .assignTeacher(student: a["student"], teacher: a["teacher"])
        case "buildColony": self = .buildColony(name: a["name"], unit: a["unit"])
        case "cashInTreasureTrain": self = .cashInTreasureTrain(unit: a["unit"])
        case "changeState": self = .changeState(unit: a["unit"], state: a["state"])
        case "changeWorkImprovementType":
            self = .changeWorkImprovementType(unit: a["unit"], improvementType: a["improvementType"])
        case "changeWorkType": self = .changeWorkType(unit: a["unit"], workType: a["workType"])
        case "claimLand": self = .claimLand(tile: a["tile"], claimant: a["claimant"], price: a["price"])
        case "clearSpeciality": self = .clearSpeciality(unit: a["unit"])
        case "declineMounds": self = .declineMounds(unit: a["unit"], direction: a["direction"])
        case "disbandUnit": self = .disbandUnit(unit: a["unit"])
        case "disembark": self = .disembark(unit: a["unit"])
        case "embark": self = .embark(unit: a["unit"], carrier: a["carrier"], direction: a["direction"])
        case "emigrateUnit": self = .emigrateUnit(slot: a["slot"])
        case "equipForRole": self = .equipForRole(unit: a["unit"], role: a["role"], count: a["count"])
        case "joinColony": self = .joinColony(colony: a["colony"], unit: a["unit"])
        case "loadGoods":
            self = .loadGoods(location: a["location"], type: a["type"], amount: a["amount"], carrier: a["carrier"])
        case "move": self = .move(unit: a["unit"], direction: a["direction"])
        case "moveTo": self = .moveTo(unit: a["unit"], destination: a["destination"])
        case "newLandName": self = .newLandName(unit: a["unit"], name: a["newLandName"])
        case "newRegionName":
            self = .newRegionName(region: a["region"], tile: a["tile"], unit: a["unit"], name: a["newRegionName"])
        case "payArrears": self = .payArrears(goodsType: a["goodsType"])
        case "payForBuilding": self = .payForBuilding(colony: a["colony"])
        case "putOutsideColony": self = .putOutsideColony(unit: a["unit"])
        case "rename": self = .rename(nameable: a["nameable"], name: a["name"])
        case "setBuildQueue":
            let n = Int(a["xLength"] ?? "") ?? 0
            self = .setBuildQueue(colony: a["colony"], queue: (0..<n).map { a["x\($0)"] ?? "" })
        case "setGoodsLevels":
            self = .setGoodsLevels(colony: a["colony"],
                                   exportData: children.first { $0.tag == "exportData" }?.attributes)
        case "chooseFoundingFather": self = .chooseFoundingFather(father: a["foundingFather"])
        case "setDestination": self = .setDestination(unit: a["unit"], destination: a["destination"])
        case "trainUnitInEurope": self = .trainUnitInEurope(unitType: a["unitType"])
        case "unloadGoods": self = .unloadGoods(type: a["type"], amount: a["amount"], carrier: a["carrier"])
        case "work": self = .work(unit: a["unit"], workLocation: a["workLocation"])
        default: throw UnknownMessage(tag: tag)
        }
    }
}

/// The server refused a command, as Java's clientError does.
public struct CommandRefused: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

/// An XML element a command carries whole: its tag, attributes and
/// children.
public struct CommandElement: Equatable, Sendable {
    public var tag: String
    public var attributes: [String: String]
    public var children: [CommandElement]

    public init(tag: String, attributes: [String: String] = [:], children: [CommandElement] = []) {
        self.tag = tag
        self.attributes = attributes
        self.children = children
    }

    /// The element as XML text.
    public var xml: String {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var s = "<" + tag
        for (k, v) in attributes.sorted(by: { $0.key < $1.key }) { s += " \(k)=\"\(escape(v))\"" }
        if children.isEmpty { return s + "/>" }
        return s + ">" + children.map(\.xml).joined() + "</" + tag + ">"
    }
}

extension CommandElement {
    /// An object as a command carries it: written as XML to the server,
    /// and parsed back into an element tree.
    public init(serializing object: FreeColObject) {
        let parser = ElementParser(Data(object.serialize(.toServer()).utf8))
        self = parser.root ?? CommandElement(tag: object.xmlTagName)
    }
}

/// Parses XML text into a tree of command elements.
private final class ElementParser: NSObject, XMLParserDelegate {
    private var stack: [CommandElement] = []
    private(set) var root: CommandElement?

    init(_ data: Data) {
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        stack.append(CommandElement(tag: elementName, attributes: attributeDict))
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let done = stack.removeLast()
        if stack.isEmpty { root = done } else { stack[stack.count - 1].children.append(done) }
    }
}

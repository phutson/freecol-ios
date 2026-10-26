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

import FreeColUtil
import FreeColXML

/// A message to be translated later: a key, or a template with values
/// for its placeholders, or a label joining parts, or a plain name
/// (common/model/StringTemplate).  Messages.message turns it into
/// text.
///
/// Java's `copy` shares the list of pairs with the original, so adding
/// to one adds to both; the shared list is kept here as a reference.
open class StringTemplate: FreeColObject {

    public static let tag = "stringTemplate"

    /// What kind of template this is.
    public enum TemplateType: Int, JavaEnum, CustomStringConvertible {
        /// A literal string.
        case name
        /// A message key.
        case key
        /// A message key with replacements.
        case template
        /// Parts joined with the id as a separator.
        case label

        public var javaName: String {
            switch self {
            case .name: "NAME"
            case .key: "KEY"
            case .template: "TEMPLATE"
            case .label: "LABEL"
            }
        }

        public var description: String { javaName }
    }

    /// A key (or none, for labels) and its replacement.
    public final class Pair {
        public var key: String?
        public var value: StringTemplate?

        init(_ key: String?, _ value: StringTemplate?) {
            self.key = key
            self.value = value
        }
    }

    /// The pairs, shared with copies.
    final class Pairs {
        var list: [Pair] = []
    }

    public private(set) var templateType = TemplateType.key
    public var defaultId: String?
    var kv: Pairs?

    public override init() {
        super.init()
    }

    init(_ id: String?, _ defaultId: String?, _ templateType: TemplateType) {
        super.init()
        self.id = id
        self.defaultId = defaultId
        self.templateType = templateType
    }

    /// Read a template from the element the reader is on.
    public convenience init(_ xr: FreeColXMLReader) throws {
        self.init()
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        StringTemplate.tag
    }

    // MARK: Factories

    /// A template with another id sharing an existing one's contents.
    public static func copy(_ id: String?, _ template: StringTemplate) -> StringTemplate {
        let t = StringTemplate(id, template.defaultId, template.templateType)
        t.kv = template.kv
        return t
    }

    public static func name(_ value: String?) -> StringTemplate {
        StringTemplate(value, nil, .name)
    }

    public static func key(_ value: String?) -> StringTemplate {
        StringTemplate(value, nil, .key)
    }

    public static func key(_ named: Named) -> StringTemplate {
        key(named.nameKey)
    }

    public static func template(_ value: String?) -> StringTemplate {
        StringTemplate(value, nil, .template)
    }

    public static func template(_ named: Named) -> StringTemplate {
        template(named.nameKey)
    }

    public static func label(_ value: String?) -> StringTemplate {
        StringTemplate(value, nil, .label)
    }

    // MARK: Contents

    public var isEmpty: Bool {
        kv?.list.isEmpty ?? true
    }

    /// The pairs, in the order added.
    public var entryList: [Pair] {
        kv?.list ?? []
    }

    /// The replacement for a key, or nil.
    public func replacement(_ key: String?) -> StringTemplate? {
        kv?.list.first { $0.key == key }?.value
    }

    private func addPair(_ key: String?, _ value: StringTemplate?) {
        precondition(key != nil || value != nil, "Null key and pair: \(self)")
        if kv == nil { kv = Pairs() }
        kv!.list.append(Pair(key, value))
    }

    /// @compat 0.11.x: a key whose value follows separately.
    private func addKey(_ key: String?) {
        addPair(key, nil)
    }

    /// @compat 0.11.x: the value for the first key still without one.
    private func addReplacement(_ replacement: StringTemplate) {
        if kv == nil { kv = Pairs() }
        if let pair = kv!.list.first(where: { $0.value == nil }) {
            pair.value = replacement
            return
        }
        addPair(nil, replacement)
    }

    private func requireType(_ type: TemplateType, _ what: String) {
        precondition(templateType == type, "Cannot add \(what) to StringTemplate.\(templateType)")
    }

    /// Add a key to be translated as a replacement.
    @discardableResult
    public func add(_ key: String?, _ value: String?) -> Self {
        requireType(.template, "key-value pair")
        addPair(key, StringTemplate.key(value))
        return self
    }

    /// Add a key to be translated as a part of a label.
    @discardableResult
    public func add(_ value: String?) -> Self {
        requireType(.label, "a single string")
        addPair(nil, StringTemplate.key(value))
        return self
    }

    /// Add a literal replacement.
    @discardableResult
    public func addName(_ key: String?, _ value: String?) -> Self {
        requireType(.template, "key-name pair")
        addPair(key, StringTemplate.name(value))
        return self
    }

    /// Add an object's name as a replacement.
    @discardableResult
    public func addName(_ key: String?, _ object: FreeColObject?) -> Self {
        requireType(.template, "key-object pair")
        addPair(key, StringTemplate.key(Messages.nameKey(object?.id)))
        return self
    }

    /// Add a literal part of a label.
    @discardableResult
    public func addName(_ value: String?) -> Self {
        requireType(.label, "a single string")
        addPair(nil, StringTemplate.name(value))
        return self
    }

    @discardableResult
    public func addNamed(_ key: String?, _ named: Named) -> Self {
        add(key, named.nameKey)
    }

    @discardableResult
    public func addNamed(_ named: Named) -> Self {
        add(named.nameKey)
    }

    /// Add a number as a literal replacement.
    @discardableResult
    public func addAmount(_ key: String?, _ amount: Int) -> Self {
        addName(key, String(amount))
    }

    /// Add a number as a literal replacement, as Java prints it.
    @discardableResult
    public func addAmount(_ key: String?, _ amount: Double) -> Self {
        addName(key, JavaNumberFormat.string(amount))
    }

    @discardableResult
    public func addAmount(_ key: String?, _ amount: Float) -> Self {
        addName(key, JavaNumberFormat.string(amount))
    }

    @discardableResult
    public func addStringTemplate(_ key: String?, _ template: StringTemplate?) -> Self {
        requireType(.template, "key-template pair")
        addPair(key, template)
        return self
    }

    @discardableResult
    public func addStringTemplate(_ template: StringTemplate?) -> Self {
        requireType(.label, "a template")
        addPair(nil, template)
        return self
    }

    @discardableResult
    public func addTagged(_ key: String?, _ value: String?) -> Self {
        add(key, value)
    }

    // MARK: Java's equals, hashCode and toString

    /// Java's equals: the same type, default, pairs and id.  (Java's
    /// pair comparison calls equals on a key that may be null, which
    /// throws; nil keys compare equal here.)
    public func javaEquals(_ other: StringTemplate) -> Bool {
        if self === other { return true }
        if templateType != other.templateType || defaultId != other.defaultId { return false }
        if (kv == nil) != (other.kv == nil) { return false }
        if let kv, let okv = other.kv {
            if kv.list.count != okv.list.count { return false }
            for (a, b) in zip(kv.list, okv.list) {
                if a.key != b.key { return false }
                switch (a.value, b.value) {
                case (nil, nil): break
                case let (x?, y?): if !x.javaEquals(y) { return false }
                default: return false
                }
            }
        }
        return id == other.id
    }

    /// Java's hashCode.
    open var javaHash: Int32 {
        var hash = javaHashCode
        hash = 31 &* hash &+ Int32(templateType.rawValue)
        hash = 31 &* hash &+ (defaultId.map(JavaString.hashCode) ?? 31)
        for e in entryList {
            hash = 31 &* hash &+ (e.key.map(JavaString.hashCode) ?? 31)
            hash = 31 &* hash &+ (e.value?.javaHash ?? 31)
        }
        return hash
    }

    /// Java's toString.  (Java separates a template's pairs with an
    /// empty string, so they run together; mirrored.)
    open override var description: String {
        var sb = "\(templateType):\(id ?? "null")"
        if let defaultId { sb += "(\(defaultId))" }
        switch templateType {
        case .label:
            if let kv {
                var start = "["
                for (index, e) in kv.list.enumerated() {
                    sb += "\(start)\(index):\(e.value.map { "\($0)" } ?? "null")"
                    start = " "
                }
                sb += "]"
            }
        case .template:
            sb += "["
            for e in entryList {
                sb += "\(e.key ?? "null")=\(e.value.map { "\($0)" } ?? "null")"
            }
            sb += "]"
        case .key, .name:
            break
        }
        return sb
    }

    // MARK: Reading XML

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        templateType = xr.attribute("templateType", TemplateType.self, default: .template) ?? .template
        defaultId = xr.attribute("defaultId", default: nil as String?)
    }

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        kv?.list.removeAll()
        try super.readChildren(xr)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "pair":
            // A nil key is allowed.
            let key = xr.attribute("value", default: nil as String?)
            var val: StringTemplate?
            while try xr.moreTags() {
                if xr.localName == StringTemplate.tag && val == nil {
                    val = try StringTemplate(xr)
                } else {
                    try xr.expectTag(val == nil ? StringTemplate.tag : "pair")
                }
            }
            addPair(key, val)
        case "key":
            // @compat 0.11.x: keys and values written separately.
            addKey(xr.attribute("value", default: nil as String?))
            try xr.closeTag("key")
        case StringTemplate.tag:
            addReplacement(try StringTemplate(xr))
        default:
            try super.readChild(xr)
        }
    }

    // MARK: Writing XML

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("templateType", templateType)
        if let defaultId { xw.writeAttribute("defaultId", defaultId) }
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for pair in kv?.list ?? [] {
            xw.writeStartElement("pair")
            if let key = pair.key { xw.writeAttribute("value", key) }
            pair.value?.toXML(xw)
            xw.writeEndElement()
        }
    }
}

/// A message for a player, such as a building being completed
/// (common/model/ModelMessage): a template with the object it is about
/// and the object to show with it.
public final class ModelMessage: StringTemplate {

    public static let modelMessageTag = "modelMessage"

    /// The kinds of message, each with the client option that shows it
    /// (ModelMessage.MessageType).
    public enum MessageType: Int, JavaEnum, CustomStringConvertible, Named {
        case `default`, buildingCompleted, combatResult, demands, disasters, foreignDiplomacy
        case giftGoods, goodsMovement, governmentEfficiency, lostCityRumour, marketPrices
        case missingGoods, sonsOfLiberty, tutorial, unitAdded, unitArrived, unitDemoted
        case unitImproved, unitLost, unitRepaired, warehouseCapacity, warning

        public var javaName: String {
            switch self {
            case .default: "DEFAULT"
            case .buildingCompleted: "BUILDING_COMPLETED"
            case .combatResult: "COMBAT_RESULT"
            case .demands: "DEMANDS"
            case .disasters: "DISASTERS"
            case .foreignDiplomacy: "FOREIGN_DIPLOMACY"
            case .giftGoods: "GIFT_GOODS"
            case .goodsMovement: "GOODS_MOVEMENT"
            case .governmentEfficiency: "GOVERNMENT_EFFICIENCY"
            case .lostCityRumour: "LOST_CITY_RUMOUR"
            case .marketPrices: "MARKET_PRICES"
            case .missingGoods: "MISSING_GOODS"
            case .sonsOfLiberty: "SONS_OF_LIBERTY"
            case .tutorial: "TUTORIAL"
            case .unitAdded: "UNIT_ADDED"
            case .unitArrived: "UNIT_ARRIVED"
            case .unitDemoted: "UNIT_DEMOTED"
            case .unitImproved: "UNIT_IMPROVED"
            case .unitLost: "UNIT_LOST"
            case .unitRepaired: "UNIT_REPAIRED"
            case .warehouseCapacity: "WAREHOUSE_CAPACITY"
            case .warning: "WARNING"
            }
        }

        /// The client option that shows these messages, if any.
        public var optionName: String? {
            switch self {
            case .default: ""
            case .combatResult, .lostCityRumour: nil
            case .buildingCompleted: "model.option.guiShowBuildingCompleted"
            case .demands: "model.option.guiShowDemands"
            case .disasters: "model.option.guiShowDisasters"
            case .foreignDiplomacy: "model.option.guiShowForeignDiplomacy"
            case .giftGoods: "model.option.guiShowGifts"
            case .goodsMovement: "model.option.guiShowGoodsMovement"
            case .governmentEfficiency: "model.option.guiShowGovernmentEfficiency"
            case .marketPrices: "model.option.guiShowMarketPrices"
            case .missingGoods: "model.option.guiShowMissingGoods"
            case .sonsOfLiberty: "model.option.guiShowSonsOfLiberty"
            case .tutorial: "model.option.guiShowTutorial"
            case .unitAdded: "model.option.guiShowUnitAdded"
            case .unitArrived: "model.option.guiShowUnitArrived"
            case .unitDemoted: "model.option.guiShowUnitDemoted"
            case .unitImproved: "model.option.guiShowUnitImproved"
            case .unitLost: "model.option.guiShowUnitLost"
            case .unitRepaired: "model.option.guiShowUnitRepaired"
            case .warehouseCapacity: "model.option.guiShowWarehouseCapacity"
            case .warning: "model.option.guiShowWarning"
            }
        }

        public var nameKey: String {
            Messages.nameKey("model.messageType." + Messages.enumKey(javaName))
        }

        public var description: String { javaName }
    }

    public var sourceId: String?
    public var displayId: String?
    public var messageType: MessageType?
    public var displayed = false

    public override init() {
        super.init()
    }

    /// A message about a source, shown with a display object (the source
    /// if none).
    public init(_ messageType: MessageType, _ id: String?, _ defaultId: String?,
                _ source: FreeColGameObject, _ display: FreeColObject?) {
        super.init(id, defaultId, .template)
        self.messageType = messageType
        sourceId = source.id
        displayId = display?.id ?? source.id
    }

    public convenience init(_ messageType: MessageType, _ id: String?, _ source: FreeColGameObject,
                            _ display: FreeColObject?) {
        self.init(messageType, id, nil, source, display)
    }

    /// A message shown with the usual object for its kind.
    public convenience init(_ messageType: MessageType, _ id: String?, _ source: FreeColGameObject) {
        self.init(messageType, id, source, ModelMessage.defaultDisplay(messageType, source))
    }

    /// Read a message from the element the reader is on.
    public convenience init(reading xr: FreeColXMLReader) throws {
        self.init()
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        ModelMessage.modelMessageTag
    }

    /// Point the message at a new source, and its display too if that
    /// was the source.
    public func divert(_ newSource: FreeColGameObject) {
        if displayId == sourceId { displayId = newSource.id }
        sourceId = newSource.id
    }

    public var optionName: String? {
        messageType?.optionName
    }

    @discardableResult
    public func addDefaultId(_ id: String?) -> ModelMessage {
        defaultId = id
        return self
    }

    private static func defaultDisplay(_ messageType: MessageType, _ source: FreeColGameObject) -> FreeColObject? {
        switch messageType {
        case .sonsOfLiberty, .governmentEfficiency:
            return source.specification?.getGoodsType("model.goods.bells")
        case .unitImproved, .unitDemoted, .unitLost, .unitAdded, .lostCityRumour, .combatResult,
             .demands, .goodsMovement:
            return source
        case .buildingCompleted:
            return source.specification?.getGoodsType("model.goods.hammers")
        default:
            return source is Player ? source : nil
        }
    }

    /// The key to ignore repeats of this message by, for the warehouse
    /// warnings, or nil.
    public var ignoredMessageKey: String? {
        guard messageType == .warehouseCapacity else { return nil }
        var sb = sourceId ?? "null"
        if templateType == .template, let t = replacement("%goods%") { sb += "-\(t.id ?? "null")" }
        return sb
    }

    /// Java's hashCode.
    public override var javaHash: Int32 {
        var hash = super.javaHash
        if let sourceId { hash = 37 &* hash &+ JavaString.hashCode(sourceId) }
        if let displayId { hash = 37 &* hash &+ JavaString.hashCode(displayId) }
        hash = 37 &* hash &+ Int32(messageType?.rawValue ?? 0)
        hash = 37 &* hash &+ (displayed ? 1 : 0)
        return hash
    }

    public override var description: String {
        "[ModelMessage \(javaHash) \(sourceId ?? "null")/\(displayId ?? "null")"
            + " \(messageType.map { "\($0)" } ?? "null") \(displayed) \(super.description)]"
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        sourceId = xr.attribute("source", default: nil as String?)
        displayId = xr.attribute("display", default: nil as String?)
        messageType = xr.attribute("messageType", MessageType.self, default: .default)
        displayed = xr.attribute("hasBeenDisplayed", default: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        if let sourceId { xw.writeAttribute("source", sourceId) }
        if let displayId { xw.writeAttribute("display", displayId) }
        if let messageType { xw.writeAttribute("messageType", messageType) }
        xw.writeAttribute("hasBeenDisplayed", displayed)
    }
}

/// An event in a player's history, such as founding a colony
/// (common/model/HistoryEvent).
public final class HistoryEvent: StringTemplate {

    public static let historyEventTag = "historyEvent"

    /// The kinds of event (HistoryEvent.HistoryEventType).
    public enum HistoryEventType: Int, JavaEnum, CustomStringConvertible, Named {
        case discoverNewWorld, discoverRegion, meetNation, cityOfGold, foundColony, abandonColony
        case conquerColony, colonyDestroyed, colonyConquered, destroySettlement, destroyNation
        case foundingFather, declareIndependence, independence, spanishSuccession, declareWar
        case ceaseFire, makePeace, formAlliance, nationDestroyed

        public var javaName: String {
            switch self {
            case .discoverNewWorld: "DISCOVER_NEW_WORLD"
            case .discoverRegion: "DISCOVER_REGION"
            case .meetNation: "MEET_NATION"
            case .cityOfGold: "CITY_OF_GOLD"
            case .foundColony: "FOUND_COLONY"
            case .abandonColony: "ABANDON_COLONY"
            case .conquerColony: "CONQUER_COLONY"
            case .colonyDestroyed: "COLONY_DESTROYED"
            case .colonyConquered: "COLONY_CONQUERED"
            case .destroySettlement: "DESTROY_SETTLEMENT"
            case .destroyNation: "DESTROY_NATION"
            case .foundingFather: "FOUNDING_FATHER"
            case .declareIndependence: "DECLARE_INDEPENDENCE"
            case .independence: "INDEPENDENCE"
            case .spanishSuccession: "SPANISH_SUCCESSION"
            case .declareWar: "DECLARE_WAR"
            case .ceaseFire: "CEASE_FIRE"
            case .makePeace: "MAKE_PEACE"
            case .formAlliance: "FORM_ALLIANCE"
            case .nationDestroyed: "NATION_DESTROYED"
            }
        }

        private var key: String { "historyEventType." + Messages.enumKey(javaName) }

        public var descriptionKey: String { Messages.descriptionKey("model." + key) }
        public var nameKey: String { Messages.nameKey("model." + key) }
        public var description: String { javaName }

        /// The event for a change of stance, if any.
        public static func from(_ stance: Player.Stance) -> HistoryEventType? {
            switch stance {
            case .war: .declareWar
            case .ceaseFire: .ceaseFire
            case .peace: .makePeace
            case .alliance: .formAlliance
            case .uncontacted: nil
            }
        }
    }

    public private(set) var turn: Turn?
    public private(set) var eventType: HistoryEventType?
    public var playerId: String?
    public var score = 0

    public override init() {
        super.init()
    }

    public init(_ turn: Turn, _ eventType: HistoryEventType, _ player: Player?) {
        super.init(eventType.descriptionKey, nil, .template)
        self.turn = turn
        self.eventType = eventType
        playerId = player?.id
    }

    public convenience init(reading xr: FreeColXMLReader) throws {
        self.init()
        try readFromXML(xr)
    }

    public override var xmlTagName: String {
        HistoryEvent.historyEventTag
    }

    /// Java's hashCode (Turn.hashCode is the turn number's).
    public override var javaHash: Int32 {
        var hash = super.javaHash
        hash = 31 &* hash &+ Int32(truncatingIfNeeded: turn?.number ?? 0)
        hash = 31 &* hash &+ Int32(eventType?.rawValue ?? 0)
        if let playerId { hash = 31 &* hash &+ JavaString.hashCode(playerId) }
        hash = 31 &* hash &+ Int32(truncatingIfNeeded: score)
        return hash
    }

    /// Java's toString, with the year from the standard calendar
    /// (Java's static Turn settings).
    public override var description: String {
        let year = turn.map { TurnCalendar.standard.year(of: $0) } ?? 0
        var sb = "[\(id ?? "null") \(eventType.map { "\($0)" } ?? "null") (\(year))"
        if let playerId { sb += " playerId=\(playerId) score=\(score)" }
        return sb + " \(super.description)]"
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        turn = Turn(xr.attribute("turn", default: 0))
        eventType = xr.attribute("eventType", HistoryEventType.self, default: nil)
        playerId = xr.attribute("playerId", default: nil as String?)
        score = xr.attribute("score", default: 0)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("turn", turn?.number ?? 0)
        if let eventType { xw.writeAttribute("eventType", eventType) }
        if let playerId { xw.writeAttribute("playerId", playerId) }
        xw.writeAttribute("score", score)
    }
}

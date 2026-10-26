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

/// The base of all game options (common/option/AbstractOption).
///
/// Java's options are generic (`AbstractOption<T>` with getValue and
/// setValue of T); here each subclass has its own typed value, and the
/// shared parts are in this class.  Not ported: the client-only options
/// (audio mixer, language, mods) and property change notifications.
open class AbstractOption: FreeColSpecObject {

    /// The id of the group holding this option, or "".
    public var group = ""
    /// Whether a value has been set.
    public var isDefined = false
    /// The id of an option that enables this one, if any.
    public private(set) var enabledBy: String?

    public init(id: String?, specification: Specification?) {
        super.init(specification: specification)
        self.id = id
    }

    /// Whether the option may have no value.
    open var isNullValueOK: Bool {
        false
    }

    /// Set the value from XML attribute text: the value, or failing that
    /// the default.
    open func setValue(string value: String?, default defaultValue: String?) throws {
        throw FreeColXMLError("setValue unsupported: \(self)")
    }

    /// Fill in the choices offered for the option, where it has any.
    open func generateChoices() {}

    /// A copy of the option.
    open func cloneOption() -> AbstractOption {
        fatalError("\(type(of: self)) must override cloneOption")
    }

    /// Copy the shared fields (Java's setValues), except the value.
    func copyBase(from other: AbstractOption) {
        id = other.id
        setSpecification(other.specification)
        group = other.group
        isDefined = other.isDefined
    }

    // MARK: Reading XML

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        let defaultValue = xr.attribute("defaultValue", default: nil as String?)
        let value = xr.attribute("value", default: nil as String?)
        if defaultValue == nil && value == nil {
            if !isNullValueOK {
                throw FreeColXMLError("invalid option \(id ?? "null"): no value nor default value found.")
            }
        } else {
            try setValue(string: value, default: defaultValue)
        }
        enabledBy = xr.attribute("enabledBy", default: nil as String?)
    }

    // MARK: Writing XML
    //
    // The identifier is written by FreeColObject; each kind writes its
    // value.  The default value is not written.

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("enabledBy", id: enabledBy)
    }

    /// Read an option of the kind named by the current tag (Java's
    /// readOption).  Unknown kinds and actions are stepped over.
    public func readOption(_ xr: FreeColXMLReader) throws -> AbstractOption? {
        let spec = specification
        let option: AbstractOption?
        switch xr.localName {
        case AbstractUnitOption.tag: option = AbstractUnitOption(id: nil, specification: spec)
        case BooleanOption.tag: option = BooleanOption(id: nil, specification: spec)
        case FileOption.tag: option = FileOption(id: nil, specification: spec)
        case IntegerOption.tag: option = IntegerOption(id: nil, specification: spec)
        case OptionGroup.tag: option = OptionGroup(id: nil, specification: spec)
        case PercentageOption.tag: option = PercentageOption(id: nil, specification: spec)
        case RangeOption.tag: option = RangeOption(id: nil, specification: spec)
        case SelectOption.tag: option = SelectOption(id: nil, specification: spec)
        case StringOption.tag: option = StringOption(id: nil, specification: spec)
        case UnitListOption.tag: option = UnitListOption(id: nil, specification: spec)
        case UnitTypeOption.tag: option = UnitTypeOption(id: nil, specification: spec)
        case TextOption.tag: option = TextOption(id: nil, specification: spec)
        default:
            // "action" elements, and kinds Java warns about.
            try xr.nextTag()
            return nil
        }
        try option?.readFromXML(xr)
        option?.generateChoices()
        return option
    }
}

/// A group of options, itself an option (common/option/OptionGroup).
///
/// Not yet ported: merging groups from saved games and files, which
/// comes with game setup.
public final class OptionGroup: AbstractOption {

    public static let tag = "optionGroup"

    /// The options, in order.
    public private(set) var options: [AbstractOption] = []
    /// Every option here and in groups below, by id.
    private var optionMap: [String: AbstractOption] = [:]
    public var isEditable = true
    public private(set) var isVisible = true

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String {
        OptionGroup.tag
    }

    /// An option here or in a group below.
    public func option(_ id: String?) -> AbstractOption? {
        id.flatMap { optionMap[$0] }
    }

    /// An option of a kind here or below.
    public func option<T: AbstractOption>(_ id: String?, as type: T.Type) -> T? {
        option(id) as? T
    }

    /// Whether there is an option of a kind here or below.
    public func hasOption<T: AbstractOption>(_ id: String?, _ type: T.Type) -> Bool {
        option(id, as: T.self) != nil
    }

    /// Whether any direct member is a group.
    public var hasOptionGroup: Bool {
        options.contains { $0 is OptionGroup }
    }

    /// Add an option, replacing one with the same id in place.
    public func add(_ option: AbstractOption) {
        let id = option.id ?? ""
        if optionMap[id] != nil, let index = options.firstIndex(where: { $0.id == id }) {
            options[index] = option
        } else {
            options.append(option)
        }
        optionMap[id] = option
        if let group = option as? OptionGroup {
            group.isEditable = isEditable && group.isEditable
            addMembers(of: group)
        }
    }

    private func addMembers(of group: OptionGroup) {
        for o in group.options {
            optionMap[o.id ?? ""] = o
            if let g = o as? OptionGroup { addMembers(of: g) }
        }
    }

    /// Remove an option from here and any groups below.
    @discardableResult
    public func remove(_ id: String) -> AbstractOption? {
        let op = optionMap.removeValue(forKey: id)
        if let op {
            options.removeAll { $0 === op }
            for g in options.compactMap({ $0 as? OptionGroup }) { g.remove(id) }
        }
        return op
    }

    /// Remove everything.
    public func removeAll() {
        options = []
        optionMap = [:]
    }

    /// Copy the values of another group's options into the matching
    /// options here (Java's setValue(OptionGroup)).
    public func setValues(from other: OptionGroup) {
        for o in other.options {
            guard let mine = option(o.id) else { continue }
            mine.copyValue(from: o)
        }
    }

    public override func cloneOption() -> AbstractOption {
        let result = OptionGroup(id: id, specification: specification)
        result.isEditable = isEditable
        result.copyBase(from: self)
        result.options = options
        result.optionMap = optionMap
        return result
    }

    public override var isNullValueOK: Bool { true }

    public override func setValue(string value: String?, default defaultValue: String?) throws {}

    public override func generateChoices() {
        for o in options { o.generateChoices() }
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        isEditable = xr.attribute("editable", default: true)
        isVisible = xr.attribute("visible", default: true)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("editable", isEditable)
        xw.writeAttribute("visible", isVisible)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for option in options { option.toXML(xw) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        try super.readChildren(xr)
        for o in options {
            optionMap[o.id ?? ""] = o
            if let g = o as? OptionGroup { addMembers(of: g) }
        }
    }

    /// An option already here is read in place (so a mod or later file
    /// can change it); a new one is created and added.
    public override func readChild(_ xr: FreeColXMLReader) throws {
        let optionId = xr.readId()
        if let existing = option(optionId) {
            try existing.readFromXML(xr)
        } else if let created = try readOption(xr) {
            add(created)
            created.group = id ?? ""
        }
    }

    /// Java's toString: "[id < option... >]".
    public override var description: String {
        "[\(id ?? "null") <" + options.map { " \($0)" }.joined() + " >]"
    }
}

extension AbstractOption {
    /// Take the value of another option of the same kind.
    func copyValue(from other: AbstractOption) {
        switch (self, other) {
        case let (a as IntegerOption, b as IntegerOption): a.setValue(b.value)
        case let (a as BooleanOption, b as BooleanOption): a.setValue(b.value)
        case let (a as StringOption, b as StringOption): a.setValue(b.value)
        case let (a as TextOption, b as TextOption): a.setValue(b.value)
        case let (a as FileOption, b as FileOption): a.setValue(b.value)
        case let (a as UnitTypeOption, b as UnitTypeOption): a.setValue(b.value)
        case let (a as AbstractUnitOption, b as AbstractUnitOption): a.setValue(b.value)
        case let (a as UnitListOption, b as UnitListOption): a.setValue(b.value)
        case let (a as OptionGroup, b as OptionGroup): a.setValues(from: b)
        default: break
        }
    }
}

/// An integer option with optional limits (common/option/IntegerOption).
open class IntegerOption: AbstractOption {

    public class var tag: String { "integerOption" }

    public private(set) var value = 0
    private var originalValue = 0
    public var maximumValue = Int(Int32.max)
    public var minimumValue = Int(Int32.min)
    public private(set) var stepSize = 0
    public var isPreviewEnabled = false

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    open override var xmlTagName: String {
        Self.tag
    }

    /// Restore the value read.
    public func resetValue() {
        setValue(originalValue)
    }

    /// A value brought within the limits.
    public func limitValue(_ v: Int) -> Int {
        min(max(v, minimumValue), maximumValue)
    }

    /// Set the value, within the limits.
    open func setValue(_ newValue: Int) {
        value = limitValue(newValue)
        isDefined = true
    }

    /// Java parses with Integer.valueOf (decimal only) and logs, rather
    /// than fails, on a bad number.
    open override func setValue(string value: String?, default defaultValue: String?) throws {
        guard let str = value ?? defaultValue, let v = JavaString.parseInt(str) else { return }
        setValue(Int(v))
    }

    open override func cloneOption() -> AbstractOption {
        let result = IntegerOption(id: id, specification: specification)
        result.copyIntegerFields(from: self)
        return result
    }

    func copyIntegerFields(from other: IntegerOption) {
        copyBase(from: other)
        minimumValue = other.minimumValue
        maximumValue = other.maximumValue
        value = other.value
    }

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        maximumValue = xr.attribute("maximumValue", default: Int(Int32.max))
        minimumValue = xr.attribute("minimumValue", default: Int(Int32.min))
        stepSize = xr.attribute("stepSize", default: 0)
        isPreviewEnabled = xr.attribute("previewEnabled", default: false)
        value = limitValue(value)
        originalValue = value
    }

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", value)
        if maximumValue < Int(Int32.max) { xw.writeAttribute("maximumValue", maximumValue) }
        if minimumValue > Int(Int32.min) { xw.writeAttribute("minimumValue", minimumValue) }
        if stepSize > 0 { xw.writeAttribute("stepSize", stepSize) }
        if isPreviewEnabled { xw.writeAttribute("previewEnabled", isPreviewEnabled) }
    }

    /// Java's toString.
    open override var description: String {
        var s = "[\(id ?? "null") value=\(value)"
        if minimumValue > Int(Int32.min) { s += " min=\(minimumValue)" }
        if maximumValue < Int(Int32.max) { s += " max=\(maximumValue)" }
        return s + "]"
    }
}

/// A percentage (common/option/PercentageOption).
///
/// Java sets limits of 0 to 100 when one is made, but reading one from
/// XML resets them to the full int range, as here.
public final class PercentageOption: IntegerOption {

    public override class var tag: String { "percentageOption" }

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
        minimumValue = 0
        maximumValue = 100
    }

    public override func cloneOption() -> AbstractOption {
        let result = PercentageOption(id: id, specification: specification)
        result.copyIntegerFields(from: self)
        return result
    }

    public override var description: String {
        "[\(id ?? "null") \(value)%]"
    }
}

/// A choice among numbered labels (common/option/SelectOption).
open class SelectOption: IntegerOption {

    public override class var tag: String { "selectOption" }

    public private(set) var localizedLabels = false
    /// The values and their labels, in order.
    public private(set) var itemValues: [(value: Int, label: String?)] = []

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    /// The element name of the choices.
    open var itemElementTag: String {
        "selectValue"
    }

    /// The label of the current value.
    public var name: String? {
        itemValues.first { $0.value == value }?.label
    }

    /// Set a value that is one of the choices, or the first choice.
    /// Before the choices are read this does nothing, as in Java.
    public override func setValue(_ newValue: Int) {
        guard let fallback = itemValues.first?.value else { return }
        super.setValue(itemValues.contains { $0.value == newValue } ? newValue : fallback)
    }

    public override func cloneOption() -> AbstractOption {
        let result = SelectOption(id: id, specification: specification)
        result.copyIntegerFields(from: self)
        result.itemValues = itemValues
        result.localizedLabels = localizedLabels
        return result
    }

    open override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        localizedLabels = xr.attribute("localizedLabels", default: true)
    }

    open override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("localizedLabels", localizedLabels)
    }

    open override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for item in itemValues {
            xw.writeStartElement(itemElementTag)
            xw.writeAttribute("value", item.value)
            xw.writeAttribute("label", id: item.label)
            xw.writeEndElement()
        }
    }

    open override func readChildren(_ xr: FreeColXMLReader) throws {
        let value = xr.attribute("value", default: nil as String?)
        let defaultValue = xr.attribute("defaultValue", default: nil as String?)
        itemValues = []
        try super.readChildren(xr)
        try setValue(string: value, default: defaultValue)
    }

    open override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == itemElementTag {
            let v = xr.attribute("value", default: Constants.infinity)
            let label = xr.attribute("label", default: nil as String?)
            // A LinkedHashMap: a repeated value keeps its place.
            if let i = itemValues.firstIndex(where: { $0.value == v }) {
                itemValues[i].label = label
            } else {
                itemValues.append((v, label))
            }
            try xr.closeTag(xr.localName)
        } else {
            try super.readChild(xr)
        }
    }

    open override var description: String {
        "[\(id ?? "null") value=\(value) localized=\(localizedLabels)]"
    }
}

/// A choice on a scale (common/option/RangeOption).
public final class RangeOption: SelectOption {

    public override class var tag: String { "rangeOption" }

    public override var itemElementTag: String {
        "rangeValue"
    }

    /// The position of the value among the choices, or 0.
    public var valueRank: Int {
        itemValues.firstIndex { $0.value == value } ?? 0
    }

    /// Set the value by position, the last choice if beyond them.
    public func setValueRank(_ rank: Int) {
        guard !itemValues.isEmpty else { setValue(Constants.undefined); return }
        setValue(itemValues[min(rank, itemValues.count - 1)].value)
    }

    public override func cloneOption() -> AbstractOption {
        let result = RangeOption(id: id, specification: specification)
        result.copyIntegerFields(from: self)
        return result
    }
}

/// A true or false option (common/option/BooleanOption).
public final class BooleanOption: AbstractOption {

    public static let tag = "booleanOption"

    public private(set) var value = false

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String { BooleanOption.tag }

    public func setValue(_ newValue: Bool) {
        value = newValue
        isDefined = true
    }

    public override func setValue(string value: String?, default defaultValue: String?) throws {
        setValue(JavaString.parseBoolean(value ?? defaultValue))
    }

    public override func cloneOption() -> AbstractOption {
        let result = BooleanOption(id: id, specification: specification)
        result.copyBase(from: self)
        result.value = value
        return result
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", value)
    }

    public override var description: String {
        "[\(id ?? "null") value=\(value)]"
    }
}

/// A string option, possibly with choices (common/option/StringOption).
public final class StringOption: AbstractOption {

    public static let tag = "stringOption"

    public private(set) var value: String?
    public var choices: [String?] = []

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String { StringOption.tag }

    public func setValue(_ newValue: String?) {
        value = newValue
        isDefined = true
    }

    public override func setValue(string value: String?, default defaultValue: String?) throws {
        setValue(value ?? defaultValue)
    }

    public override func cloneOption() -> AbstractOption {
        let result = StringOption(id: id, specification: specification)
        result.copyBase(from: self)
        result.value = value
        result.choices = choices
        return result
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", id: value)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for choice in choices {
            xw.writeStartElement("choice")
            xw.writeAttribute("value", id: choice)
            xw.writeEndElement()
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        choices = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "choice" {
            choices.append(xr.attribute("value", default: nil as String?))
            try xr.closeTag("choice")
        } else {
            try super.readChild(xr)
        }
    }

    public override var description: String {
        "[\(id ?? "null") value=\(value ?? "null") choices=[" + choices.map { " \($0 ?? "null")" }.joined() + "]]"
    }
}

/// A free text option (common/option/TextOption).
public final class TextOption: AbstractOption {

    public static let tag = "textOption"

    public private(set) var value: String?

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String { TextOption.tag }

    public func setValue(_ newValue: String?) {
        value = newValue
        isDefined = true
    }

    public override func setValue(string value: String?, default defaultValue: String?) throws {
        setValue(value ?? defaultValue)
    }

    public override func cloneOption() -> AbstractOption {
        let result = TextOption(id: id, specification: specification)
        result.copyBase(from: self)
        result.value = value
        return result
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", id: value)
    }

    public override var description: String {
        "[\(id ?? "null") value=\(value ?? "null")]"
    }
}

/// A file option, kept as a path (common/option/FileOption).
public final class FileOption: AbstractOption {

    public static let tag = "fileOption"

    public private(set) var value: String?
    public var fileType: String?

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String { FileOption.tag }

    public override var isNullValueOK: Bool { true }

    public func setValue(_ newValue: String?) {
        value = newValue
        isDefined = true
    }

    /// Unlike the other options, this does not mark the value defined.
    public override func setValue(string value: String?, default defaultValue: String?) throws {
        self.value = value ?? defaultValue
    }

    public override func cloneOption() -> AbstractOption {
        let result = FileOption(id: nil, specification: specification)
        result.copyBase(from: self)
        result.value = value
        result.fileType = fileType
        return result
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        fileType = xr.attribute("type", default: nil as String?)
        if fileType == nil {
            fileType = (value?.hasSuffix(".fsm") ?? false) ? "map" : "save"
        }
    }

    /// Java writes the file's absolute path.
    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", id: value)
        xw.writeAttribute("type", id: fileType)
    }

    /// Java's toString, with the file's name (after the last "/").
    public override var description: String {
        let name = value.map { JavaString.lastPart($0, "/") } ?? "null"
        return "[\(id ?? "null") value=\(name) type=\(fileType ?? "null")]"
    }
}

/// A choice of unit type (common/option/UnitTypeOption).
public final class UnitTypeOption: AbstractOption {

    public static let tag = "unitTypeOption"

    /// Which unit types to offer.
    public enum TypeSelector: JavaEnum {
        case units, immigrants, landUnits, navalUnits
        public var javaName: String {
            switch self {
            case .units: "UNITS"
            case .immigrants: "IMMIGRANTS"
            case .landUnits: "LAND_UNITS"
            case .navalUnits: "NAVAL_UNITS"
            }
        }
    }

    public private(set) var value: UnitType?
    public private(set) var addNone = false
    public private(set) var selector: TypeSelector? = .units
    public private(set) var choices: [UnitType?] = []

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String { UnitTypeOption.tag }

    public override var isNullValueOK: Bool { true }

    public func setValue(_ newValue: UnitType?) {
        value = newValue
        isDefined = true
    }

    public override func setValue(string value: String?, default defaultValue: String?) throws {
        setValue((value ?? defaultValue).flatMap { specification?.getUnitType($0) })
    }

    public override func cloneOption() -> AbstractOption {
        let result = UnitTypeOption(id: id, specification: specification)
        result.value = value
        result.addNone = addNone
        result.selector = selector
        result.choices = choices
        return result
    }

    public override func generateChoices() {
        guard let selector else {
            if let value, choices.isEmpty { choices.append(value) }
            return
        }
        let all = specification?.unitTypeList ?? []
        switch selector {
        case .units: choices = all
        case .immigrants: choices = all.filter(\.isRecruitable)
        case .navalUnits: choices = all.filter(\.isNaval)
        case .landUnits: choices = all.filter { !$0.isNaval }
        }
        if addNone { choices.insert(nil, at: 0) }
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        selector = xr.attribute("generate", TypeSelector.self, default: nil)
        addNone = xr.attribute("addNone", default: false)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("value", value)
        if let selector { xw.writeAttribute("generate", selector) }
        if addNone { xw.writeAttribute("addNone", addNone) }
    }

    /// The choices, as generated.
    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        for choice in choices {
            xw.writeStartElement("choice")
            xw.writeAttribute("value", choice)
            xw.writeEndElement()
        }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        choices = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "choice" {
            choices.append(try specification.flatMap { try xr.getType($0, "value", UnitType.self) })
            try xr.closeTag("choice")
        } else {
            try super.readChild(xr)
        }
    }

    public override var description: String {
        "[\(id ?? "null") value=\(value?.id ?? "null") addNone=\(addNone)"
            + " selector=\(selector?.javaName ?? "null") choices=["
            + choices.map { " \($0?.id ?? "null")" }.joined() + " ]]"
    }
}

/// A number of units of a type in a role, built from three sub-options
/// (common/option/AbstractUnitOption).
public final class AbstractUnitOption: AbstractOption {

    public static let tag = "unitOption"

    public private(set) var value: AbstractUnit?
    public private(set) var unitTypeOption: UnitTypeOption?
    public private(set) var roleOption: StringOption?
    public private(set) var numberOption: IntegerOption?
    public private(set) var nationType: NationType?

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String { AbstractUnitOption.tag }

    public override var isNullValueOK: Bool { true }

    private func requireUnitTypeOption() -> UnitTypeOption {
        if unitTypeOption == nil {
            unitTypeOption = UnitTypeOption(id: "\(id ?? "null").unitType", specification: specification)
        }
        return unitTypeOption!
    }

    private func requireRoleOption() -> StringOption {
        if roleOption == nil {
            roleOption = StringOption(id: "\(id ?? "null").role", specification: specification)
        }
        return roleOption!
    }

    private func requireNumberOption() -> IntegerOption {
        if numberOption == nil {
            numberOption = IntegerOption(id: "\(id ?? "null").number", specification: specification)
        }
        return numberOption!
    }

    /// Set the units, updating the sub-options.
    public func setValue(_ newValue: AbstractUnit?) {
        value = newValue
        if let newValue {
            requireUnitTypeOption().setValue(specification?.getUnitType(newValue.id))
            requireRoleOption().setValue(newValue.roleId)
            requireNumberOption().setValue(newValue.number)
        } else {
            unitTypeOption = nil
            roleOption = nil
            numberOption = nil
        }
        isDefined = true
    }

    public override func cloneOption() -> AbstractOption {
        let result = AbstractUnitOption(id: id, specification: specification)
        result.copyBase(from: self)
        if let value, let spec = specification {
            result.setValue(AbstractUnit(id: value.type(spec)?.id, roleId: value.roleId,
                                         number: value.number))
        }
        result.unitTypeOption = unitTypeOption?.cloneOption() as? UnitTypeOption
        result.roleOption = roleOption?.cloneOption() as? StringOption
        result.numberOption = numberOption?.cloneOption() as? IntegerOption
        result.nationType = nationType
        return result
    }

    public override func generateChoices() {
        unitTypeOption?.generateChoices()
        if let roleOption, roleOption.choices.isEmpty, let role = roleOption.value {
            roleOption.choices = [role]
        }
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        nationType = try specification.flatMap { try xr.getType($0, "nationType", NationType.self) }
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("nationType", nationType)
    }

    public override func writeChildren(_ xw: FreeColXMLWriter) {
        super.writeChildren(xw)
        numberOption?.toXML(xw, tag: "number")
        roleOption?.toXML(xw, tag: "role")
        unitTypeOption?.toXML(xw, tag: "unitType")
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        try super.readChildren(xr)
        var au: AbstractUnit?
        if let u = unitTypeOption, let r = roleOption, let n = numberOption {
            au = AbstractUnit(id: u.value?.id, roleId: r.value, number: n.value)
        }
        setValue(au)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        switch xr.localName {
        case "number": try requireNumberOption().readFromXML(xr)
        case "role": try requireRoleOption().readFromXML(xr)
        case "unitType": try requireUnitTypeOption().readFromXML(xr)
        default: try super.readChild(xr)
        }
    }

    public override var description: String {
        var s = "[\(id ?? "null") \(value.map(\.description) ?? "null")"
        if let unitTypeOption { s += " \(unitTypeOption)" }
        if let roleOption { s += " \(roleOption)" }
        if let numberOption { s += " \(numberOption)" }
        return s + "]"
    }
}

/// A list of unit options (common/option/UnitListOption, with the parts
/// of ListOption it uses).
public final class UnitListOption: AbstractOption {

    public static let tag = "unitListOption"

    public private(set) var template: AbstractOption?
    public var maximumNumber = Int(Int32.max)
    public private(set) var value: [AbstractOption] = []
    public var allowDuplicates = true

    public override init(id: String?, specification: Specification?) {
        super.init(id: id, specification: specification)
    }

    public override var xmlTagName: String { UnitListOption.tag }

    public override var isNullValueOK: Bool { true }

    /// The units listed.
    public var optionValues: [AbstractUnit] {
        value.compactMap { ($0 as? AbstractUnitOption)?.value }
    }

    /// Add a member, unless duplicates are refused and it is present.
    public func add(_ option: AbstractOption) {
        if allowDuplicates || !value.contains(where: { $0 == option }) {
            value.append(option)
        }
    }

    public func setValue(_ newValue: [AbstractOption]) {
        value = []
        for o in newValue { add(o) }
        isDefined = true
    }

    public override func cloneOption() -> AbstractOption {
        let result = UnitListOption(id: id, specification: specification)
        result.copyBase(from: self)
        result.value = value
        result.maximumNumber = maximumNumber
        result.template = template
        result.allowDuplicates = allowDuplicates
        return result
    }

    public override func readAttributes(_ xr: FreeColXMLReader) throws {
        try super.readAttributes(xr)
        maximumNumber = xr.attribute("maximumNumber", default: 1)
    }

    public override func writeAttributes(_ xw: FreeColXMLWriter) {
        super.writeAttributes(xw)
        xw.writeAttribute("maximumNumber", maximumNumber)
    }

    /// Java's ListOption writes no children of its superclasses.
    public override func writeChildren(_ xw: FreeColXMLWriter) {
        if let template {
            xw.writeStartElement("template")
            template.toXML(xw)
            xw.writeEndElement()
        }
        for option in value { option.toXML(xw) }
    }

    public override func readChildren(_ xr: FreeColXMLReader) throws {
        value = []
        try super.readChildren(xr)
    }

    public override func readChild(_ xr: FreeColXMLReader) throws {
        if xr.localName == "template" {
            try xr.nextTag()
            template = try readOption(xr)
            try xr.closeTag("template")
        } else if let op = try readOption(xr) {
            add(op)
        }
    }

    public override var description: String {
        var s = "[\(id ?? "null") [" + value.map { " \($0)" }.joined() + " ]"
        if let template { s += " template=\(template)" }
        return s + "]"
    }
}

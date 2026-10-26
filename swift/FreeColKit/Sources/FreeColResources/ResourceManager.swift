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
import FreeColIO

/// The resources the client uses, merged from its layers in order:
/// data/base, the total conversion (data/default and its parents), the
/// active mods, then the saved game, each replacing keys of the ones
/// before (common/resources/ResourceManager).
///
/// Java keeps one static manager and preloads in a thread; here the
/// client owns an instance, and decoding is left to the user interface.
public final class ResourceManager {

    public private(set) var baseMapping = ResourceMapping()
    public private(set) var tcMapping = ResourceMapping()
    public private(set) var modMappings: [ResourceMapping] = []
    public private(set) var savegameMapping = ResourceMapping()
    /// The layers merged.
    public private(set) var merged = ResourceMapping()

    public init() {}

    /// The mappings the client starts with: data/base and the "default"
    /// total conversion, as FreeColClient loads them.
    public convenience init(dataDirectory: URL, tc: String = "default", languageId: String,
                            highQuality: Bool = true) throws {
        self.init()
        let base = try FreeColDataFile(directory: dataDirectory.appendingPathComponent("base"))
        setBase(base.resourceMapping(languageId: languageId, highQuality: highQuality) ?? ResourceMapping())
        setTc(try FreeColTcFile.resourceMapping(dataDirectory: dataDirectory, id: tc, languageId: languageId,
                                                highQuality: highQuality))
    }

    public func setBase(_ mapping: ResourceMapping) {
        baseMapping = mapping
        prepare()
    }

    public func setTc(_ mapping: ResourceMapping?) {
        tcMapping = mapping ?? ResourceMapping()
        prepare()
    }

    public func setMods(_ mappings: [ResourceMapping]) {
        modMappings = mappings
        prepare()
    }

    public func setSavegame(_ mapping: ResourceMapping?) {
        savegameMapping = mapping ?? ResourceMapping()
        prepare()
    }

    /// Merge the layers.
    private func prepare() {
        let m = ResourceMapping()
        m.addAll(baseMapping)
        m.addAll(tcMapping)
        for mod in modMappings { m.addAll(mod) }
        m.addAll(savegameMapping)
        merged = m
    }

    // MARK: Lookups

    public func audioResource(_ key: String) -> AudioResource? { merged.audioResources[key] }
    public func colorResource(_ key: String) -> ColorResource? { merged.colorResources[key] }
    public func fafResource(_ key: String) -> FAFileResource? { merged.fafResources[key] }
    public func fontResource(_ key: String) -> FontResource? { merged.fontResources[key] }
    public func imageResource(_ key: String) -> ImageResource? { merged.imageResources[key] }
    public func stringResource(_ key: String) -> StringResource? { merged.stringResources[key] }
    public func szaResource(_ key: String) -> SZAResource? { merged.szaResources[key] }
    public func videoResource(_ key: String) -> VideoResource? { merged.videoResources[key] }

    /// A colour, or the replacement (magenta unless given).
    public func color(_ key: String, replacement: Int32? = nil) -> Int32 {
        colorResource(key)?.rgb ?? replacement ?? ColorResource.replacementColor
    }

    /// A string, or "X".
    public func string(_ key: String) -> String {
        stringResource(key)?.string ?? StringResource.replacementString
    }

    /// A string, or a default.
    public func string(_ key: String, default defaultString: String?) -> String? {
        stringResource(key)?.string ?? defaultString
    }

    /// A string of "name=value" pairs.
    public func propertyList(_ key: String) -> PropertyList {
        PropertyList(stringResource(key)?.string ?? "")
    }

    /// The image keys starting with a prefix.
    public func imageKeys(_ prefix: String) -> [String] {
        merged.imageKeys.filter { $0.hasPrefix(prefix) }
    }
}

/// "name=value" pairs separated by commas, from a string resource
/// (common/resources/PropertyList).
public struct PropertyList: Sendable {

    public private(set) var values: [String: String] = [:]

    /// Java splits on commas, then on "="; a pair without a value fails
    /// in Java and is skipped here.
    public init(_ propertiesString: String) {
        for pair in propertiesString.split(separator: ",", omittingEmptySubsequences: false) {
            let s = pair.split(separator: "=", omittingEmptySubsequences: false)
            guard s.count >= 2 else { continue }
            values[String(s[0])] = String(s[1])
        }
    }

    public func string(_ key: String) -> String? {
        values[key]
    }

    public func int(_ key: String, default defaultValue: Int) -> Int {
        values[key].flatMap { Int($0) } ?? defaultValue
    }
}

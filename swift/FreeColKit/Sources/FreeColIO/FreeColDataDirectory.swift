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
import FreeColXML

/// FreeCol's data directory: rule sets in rules/<id>, mods in
/// mods/<id>, compatibility files in base (common/io FreeColRules,
/// FreeColModFile and FreeColDirectories).
///
/// Rule sets and mods are found by the id in their mod.xml descriptor,
/// as Java does, not by directory name.  Only directories are
/// supported, not zipped mods.
public struct FreeColDataDirectory: RulesSource, Sendable {

    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A rule set or mod: its directory, id and parent.
    public struct ModFile: Sendable {
        public let directory: URL
        public let id: String
        public let parent: String?

        /// The specification, or nil for a mod with only resources.
        public func specificationData() throws -> Data? {
            let file = directory.appendingPathComponent("specification.xml")
            return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
        }
    }

    /// The rule sets, by id.
    public func rules() throws -> [String: ModFile] {
        try modFiles(in: url.appendingPathComponent("rules"))
    }

    /// The mods, by id.
    public func mods() throws -> [String: ModFile] {
        try modFiles(in: url.appendingPathComponent("mods"))
    }

    /// Read the mod.xml descriptors of the subdirectories.
    private func modFiles(in directory: URL) throws -> [String: ModFile] {
        let fm = FileManager.default
        var result: [String: ModFile] = [:]
        for name in try fm.contentsOfDirectory(atPath: directory.path).sorted() {
            let dir = directory.appendingPathComponent(name)
            let descriptor = dir.appendingPathComponent("mod.xml")
            guard fm.fileExists(atPath: descriptor.path) else { continue }
            let xr = try FreeColXMLReader(data: Data(contentsOf: descriptor))
            try xr.nextTag()
            guard let id = xr.readId() else { continue }
            result[id] = ModFile(directory: dir, id: id,
                                 parent: xr.attribute("parent", default: nil as String?))
        }
        return result
    }

    // MARK: RulesSource

    public func rulesData(_ id: String) throws -> Data? {
        try rules()[id]?.specificationData()
    }

    public func compatibilityData(_ fileName: String) throws -> Data? {
        let file = url.appendingPathComponent("base").appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
    }

    // MARK: Loading

    /// Load a rule set with mods, as the game does.
    ///
    /// - Parameters:
    ///   - rules: The rule set id.
    ///   - mods: Mod ids, loaded in order after the rules.
    ///   - difficulty: The difficulty level id.
    public func loadSpecification(_ rules: String, mods modIds: [String] = [],
                                  advantages: Advantages? = nil,
                                  difficulty: String?) throws -> Specification {
        let spec = try Specification.loadRules(rules, from: self, advantages: advantages,
                                               difficulty: difficulty)
        if !modIds.isEmpty {
            let available = try mods()
            let data = try modIds.map { id -> Data? in
                guard let mod = available[id] else { throw FreeColXMLError("No such mod: \(id)") }
                return try mod.specificationData()
            }
            try spec.loadMods(data)
        }
        return spec
    }
}

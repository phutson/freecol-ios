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

/// Locates the reference dumps written by the Java dump tools.
///
/// The directory is $FREECOL_REFERENCE_DIR if set, otherwise
/// build/dumps at the top of the FreeCol tree, which is where
/// swift/scripts/make-reference-dumps.sh and the ant dump targets
/// write them.  Tests that need dumps should be disabled when
/// `directory` is nil, so a fresh checkout still passes.
public enum ReferenceDumps {

    /// The top of the FreeCol source tree.
    public static let repositoryRoot: URL = {
        // This file is swift/FreeColKit/Tests/FreeColTestSupport/ReferenceDumps.swift.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }()

    /// The reference dump directory, or nil if it does not exist.
    public static var directory: URL? {
        let url: URL
        if let env = ProcessInfo.processInfo.environment["FREECOL_REFERENCE_DIR"],
           !env.isEmpty {
            url = URL(fileURLWithPath: env)
        } else {
            url = repositoryRoot.appendingPathComponent("build/dumps")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path,
                                             isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return url
    }

    /// Whether any reference dumps are available.
    public static var available: Bool {
        !jsonFiles().isEmpty
    }

    /// All JSON dumps below a subdirectory, sorted by path.
    ///
    /// - Parameter subdirectory: An optional subdirectory, such as "spec".
    /// - Returns: The dump files, or an empty list if there are none.
    public static func jsonFiles(in subdirectory: String? = nil) -> [URL] {
        guard var root = directory else { return [] }
        if let subdirectory { root.appendPathComponent(subdirectory) }
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "json" }
            .sorted { $0.path < $1.path }
    }

    /// Read and parse one dump.
    ///
    /// - Parameter url: The dump file.
    /// - Returns: The parsed document.
    public static func load(_ url: URL) throws -> JSONValue {
        try JSONValue.parse(try Data(contentsOf: url))
    }
}

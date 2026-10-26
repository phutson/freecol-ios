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
import FreeColUtil
import FreeColXML

/// A saved game (.fsg) or map (.fsm): a zip archive, or a directory,
/// holding savegame.xml, savegame.properties and a thumbnail
/// (common/io/FreeColSavegameFile).
public struct FreeColSavegameFile: Sendable {

    public static let savegameFile = "savegame.xml"
    public static let propertiesFile = "savegame.properties"
    public static let thumbnailFile = "thumbnail.png"

    /// The current saved game format version.
    public static let savegameVersion = 14
    /// The oldest version that can still be read.
    public static let minimumSavegameVersion = 12

    public let url: URL
    private let archive: ZipArchive?

    /// Open a saved game file or directory.
    public init(url: URL) throws {
        self.url = url
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            archive = nil
        } else {
            archive = try ZipArchive(contentsOf: url)
        }
    }

    /// The contents of a file in the saved game, or nil if missing.
    public func contents(of name: String) throws -> Data? {
        if let archive { return try archive.contents(of: name) }
        let file = url.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
    }

    /// The saved game XML.
    public func savegameData() throws -> Data {
        guard let data = try contents(of: FreeColSavegameFile.savegameFile) else {
            throw FreeColXMLError("No \(FreeColSavegameFile.savegameFile) in \(url.path)")
        }
        return data
    }

    /// The saved game properties (Java properties format: key=value
    /// lines, # and ! comments).  Line continuations and escapes are
    /// not handled; FreeCol does not write them.
    public func properties() throws -> [String: String] {
        guard let data = try contents(of: FreeColSavegameFile.propertiesFile) else { return [:] }
        var ret: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("#") || s.hasPrefix("!") { continue }
            guard let sep = s.firstIndex(where: { $0 == "=" || $0 == ":" }) else {
                ret[s] = ""
                continue
            }
            ret[s[..<sep].trimmingCharacters(in: .whitespaces)]
                = s[s.index(after: sep)...].trimmingCharacters(in: .whitespaces)
        }
        return ret
    }

    /// The thumbnail image, if any.
    public func thumbnail() throws -> Data? {
        try contents(of: FreeColSavegameFile.thumbnailFile)
    }

    /// The format version of the saved game, or -1 if missing or bad.
    public func version() throws -> Int {
        let xr = try FreeColXMLReader(data: savegameData())
        try xr.nextTag()
        return xr.attribute("version", default: nil as String?)
            .flatMap(JavaString.parseInt).map(Int.init) ?? -1
    }

    /// Read the game, as the server does when loading a saved game
    /// (FreeColServer.readGame).
    ///
    /// - Parameters:
    ///   - specification: The rules to use if the file has none of its
    ///     own (maps usually have none).
    ///   - makeGame: Makes the empty game to read into: the server's
    ///     game, which issues identifiers, for a game to play on.
    public func readGame(specification: Specification? = nil,
                         makeGame: (Specification?) -> Game = { Game(specification: $0) }) throws -> SavedGame {
        let xr = try FreeColXMLReader(data: savegameData())
        try xr.nextTag()
        try xr.expectTag("savedGame")
        let version = xr.attribute("version", default: nil as String?)
            .flatMap(JavaString.parseInt).map(Int.init) ?? -1
        if version < FreeColSavegameFile.minimumSavegameVersion {
            throw FreeColXMLError("server.incompatibleVersions: \(version)"
                + " < \(FreeColSavegameFile.minimumSavegameVersion)")
        }
        let owner = xr.attribute("owner", default: nil as String?)
        let singlePlayer = xr.attribute("singleplayer", default: true)
        let publicServer = xr.attribute("publicServer", default: false)
        let randomState = xr.attribute("randomState", default: nil as String?)
        let debug = xr.attribute("debug", default: nil as String?)
        // @compat 0.11.6
        let active = xr.attribute("activeUnit", default: nil as String?)

        var game: Game?
        while try xr.moreTags() {
            switch xr.localName {
            case "serverObjects": // @compat 0.11.6, no longer used
                try xr.swallowTag("serverObjects")
            case Game.tag:
                let g = makeGame(specification)
                try g.readFromXML(xr)
                g.currentPlayer = nil
                game = g
            case "aiMain":
                // The AI comes in Phase 4.
                try xr.swallowTag("aiMain")
            default:
                throw FreeColXMLError("Unknown tag reading server game: \(xr.localName)")
            }
        }
        guard let game else { throw FreeColXMLError("No game in \(url.path)") }
        // @compat 0.11.6
        if let active { game.initialActiveUnitId = active }
        return SavedGame(game: game, version: version, owner: owner, singlePlayer: singlePlayer,
                         publicServer: publicServer,
                         serverRandom: randomState.flatMap(JavaRandom.init(serializedState:)),
                         debugModes: debug, warnings: xr.warnings)
    }
}

/// A game read from a saved game file, with the server settings saved
/// alongside it.
public struct SavedGame {
    public let game: Game
    public let version: Int
    /// "mapEditor" for maps saved by the map editor.
    public let owner: String?
    public let singlePlayer: Bool
    public let publicServer: Bool
    /// The server's random number generator, as saved.
    public let serverRandom: JavaRandom?
    public let debugModes: String?
    /// What Java would have logged as warnings while reading.
    public let warnings: [String]
}

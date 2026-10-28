// swift-tools-version: 6.0
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

import PackageDescription

// The FreeCol game engine in Swift, with no UI code.  See
// doc/swift-port-plan.md for what goes where and in what order.
//
// Dependencies only point downwards (and FreeColMap, at the top, uses
// FreeColEngine and FreeColResources):
//
//                    FreeColEngine
//                         |
//                     FreeColAI
//                         |
//   FreeColResources  FreeColServer
//          |         /
//   FreeColIO, FreeColI18n
//        \        /
//        FreeColCore
//        /        \
//   FreeColXML     |
//        \        /
//        FreeColUtil
let package = Package(
    name: "FreeColKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "FreeColKit",
            targets: ["FreeColUtil", "FreeColXML", "FreeColCore",
                      "FreeColI18n", "FreeColIO", "FreeColResources",
                      "FreeColServer", "FreeColAI", "FreeColEngine", "FreeColMap"]),
    ],
    targets: [
        // Java compatibility (random numbers, rounding) and collection
        // helpers, from common/util.
        .target(name: "FreeColUtil"),

        // Streaming XML reading and writing, from common/io's
        // FreeColXMLReader and FreeColXMLWriter.
        .target(name: "FreeColXML",
                dependencies: ["FreeColUtil"]),

        // The game model and rules, from common/model and common/option.
        .target(name: "FreeColCore",
                dependencies: ["FreeColUtil", "FreeColXML"]),

        // Translated strings and message templates, from common/i18n.
        .target(name: "FreeColI18n",
                dependencies: ["FreeColCore"]),

        // Rules files, mods and saved games, from common/io.
        .target(name: "FreeColIO",
                dependencies: ["FreeColCore", "FreeColXML"]),

        // Images, sounds, fonts and the other resources the data files
        // map keys to, from common/resources (and common/io/sza).
        .target(name: "FreeColResources",
                dependencies: ["FreeColUtil", "FreeColXML", "FreeColCore", "FreeColIO"]),

        // The game engine: the server's model and turn processing
        // (server/model, server/control) and the change sets that tell
        // each player what changed (common/networking/ChangeSet),
        // without the network.
        .target(name: "FreeColServer",
                dependencies: ["FreeColUtil", "FreeColXML", "FreeColCore", "FreeColIO"]),

        // The computer players (server/ai): an AI player for each, with
        // missions for its units, acting through the same commands as a
        // human player.
        .target(name: "FreeColAI",
                dependencies: ["FreeColUtil", "FreeColXML", "FreeColCore", "FreeColServer"]),

        // The engine as the user interface sees it: an actor that owns
        // the game, takes the human player's commands, plays the other
        // players' turns, saves and loads, and hands out snapshots of
        // what the human can see.
        .target(name: "FreeColEngine",
                dependencies: ["FreeColUtil", "FreeColXML", "FreeColCore", "FreeColIO", "FreeColServer",
                               "FreeColAI"]),

        // What the map draws, as plain values the screen draws: image
        // keys, where on each tile, and in what order (from Java's
        // client TileViewer, MapViewer and ImageLibrary).  No UI code.
        .target(name: "FreeColMap",
                dependencies: ["FreeColEngine", "FreeColResources"]),

        // Helpers shared by the tests: reading and writing the
        // canonical JSON dumps made by the Java tools, and the Java
        // oracle in Tests/JavaOracle (which is data, not a target).
        .target(name: "FreeColTestSupport",
                dependencies: ["FreeColUtil"],
                path: "Tests/FreeColTestSupport"),

        .testTarget(name: "FreeColKitTests",
                    dependencies: ["FreeColUtil", "FreeColXML",
                                   "FreeColCore", "FreeColI18n",
                                   "FreeColIO", "FreeColResources", "FreeColServer"]),
        .testTarget(name: "ReferenceDumpTests",
                    dependencies: ["FreeColUtil", "FreeColTestSupport"]),
        .testTarget(name: "FreeColUtilTests",
                    dependencies: ["FreeColUtil", "FreeColXML", "FreeColTestSupport"]),
        .testTarget(name: "FreeColCoreTests",
                    dependencies: ["FreeColUtil", "FreeColXML", "FreeColCore",
                                   "FreeColIO", "FreeColTestSupport"]),
        .testTarget(name: "FreeColResourcesTests",
                    dependencies: ["FreeColUtil", "FreeColIO", "FreeColResources",
                                   "FreeColTestSupport"]),
        .testTarget(name: "FreeColServerTests",
                    dependencies: ["FreeColUtil", "FreeColXML", "FreeColCore",
                                   "FreeColIO", "FreeColServer", "FreeColTestSupport"]),
        .testTarget(name: "FreeColAITests",
                    dependencies: ["FreeColUtil", "FreeColCore", "FreeColIO", "FreeColServer",
                                   "FreeColAI", "FreeColTestSupport"]),
        .testTarget(name: "FreeColMapTests",
                    dependencies: ["FreeColUtil", "FreeColCore", "FreeColIO", "FreeColServer",
                                   "FreeColEngine", "FreeColResources", "FreeColMap", "FreeColTestSupport"]),
        .testTarget(name: "FreeColEngineTests",
                    dependencies: ["FreeColUtil", "FreeColCore", "FreeColIO", "FreeColServer",
                                   "FreeColEngine", "FreeColTestSupport"]),
        // The Java model tests (test/src/net/sf/freecol/common/model),
        // ported one file to one file.
        .testTarget(name: "FreeColModelTests",
                    dependencies: ["FreeColUtil", "FreeColXML", "FreeColCore",
                                   "FreeColIO", "FreeColTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)

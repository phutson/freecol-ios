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

/// Comparing the player's copy kept up to date with one read afresh,
/// for PlayController.checkUpdates.
extension PlayController {

    /// The player and the tiles the server's player can see, as
    /// written by a copy of the game.
    static func visible(_ view: PlayerView, as serverPlayer: Player) -> String {
        var out = withoutRules(view.player.serialize(.toServer()))
        for tile in serverPlayer.game?.map?.tiles ?? [] where serverPlayer.canSee(tile) {
            if let t = view.game.map?.tile(tile.x, tile.y) { out += withoutRules(t.serialize(.toServer())) }
        }
        return out
    }

    static func withoutRules(_ xml: String) -> String {
        var xml = xml
        if let start = xml.range(of: "<freecol-specification"),
           let end = xml.range(of: "</freecol-specification>") {
            xml = String(xml[..<start.lowerBound]) + String(xml[end.upperBound...])
        }
        // Left out too, as Java's client has them: the messages it was
        // sent, which a copy read afresh lacks, and market data, which
        // the server sends only when a price changes.
        // So is a land name the server chose before the player named it,
        // which Java's client also has only once it is named.
        for pattern in ["<modelMessage [^>]*/>", "<modelMessage [^>]*>.*?</modelMessage>",
                        "<marketData [^>]*/>", " newLandName=\"[^\"]*\""] {
            xml = xml.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return xml
    }

    /// Where two documents first differ, with some context.
    static func firstDifference(_ a: String, _ b: String) -> String {
        let a = Array(a.utf8), b = Array(b.utf8)
        var i = 0
        while i < min(a.count, b.count) && a[i] == b[i] { i += 1 }
        let from = max(0, i - 160)
        func around(_ s: [UInt8]) -> String {
            String(decoding: s[from..<min(s.count, i + 120)], as: UTF8.self)
        }
        return "kept: …\(around(a))…\nread: …\(around(b))…"
    }
}

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

import FreeColEngine
import FreeColMap
import SwiftUI

/// The map as the player sees it, drawn with Canvas: panned by
/// dragging and zoomed by pinching.  What to draw comes from
/// FreeColMap (MapScene), for the tiles on screen only.
struct MapView: View {
    let snapshot: GameSnapshot
    let images: MapImageStore

    /// The map pixel (at scale 1) at the screen's centre, and the zoom.
    @State private var centre: CGPoint?
    @State private var zoom: CGFloat = 0.75
    @State private var dragStart: CGPoint?
    @State private var zoomStart: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let centre = self.centre ?? initialCentre
            Canvas { context, size in
                draw(&context, size, centre)
            }
            .gesture(drag(centre).simultaneously(with: magnify))
        }
    }

    // MARK: Moving about

    /// Start over the player's first colony, or else its first unit on
    /// the map.
    private var initialCentre: CGPoint {
        let at = snapshot.colonies.first?.position ?? snapshot.ownUnits.compactMap(\.position).first
        guard let at else { return .zero }
        let o = MapScene.origin(at.x, at.y)
        return CGPoint(x: o.x + MapScene.tileWidth / 2, y: o.y + MapScene.tileHeight / 2)
    }

    private func drag(_ centre: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let start = dragStart ?? centre
                if dragStart == nil { dragStart = centre }
                self.centre = clamped(CGPoint(x: start.x - value.translation.width / zoom,
                                              y: start.y - value.translation.height / zoom))
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = zoomStart ?? zoom
                if zoomStart == nil { zoomStart = zoom }
                zoom = min(2, max(0.2, start * value.magnification))
            }
            .onEnded { _ in zoomStart = nil }
    }

    private func clamped(_ p: CGPoint) -> CGPoint {
        let size = MapScene.size(snapshot.map)
        return CGPoint(x: min(max(p.x, 0), CGFloat(size.width)), y: min(max(p.y, 0), CGFloat(size.height)))
    }

    // MARK: Drawing

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, _ centre: CGPoint) {
        // The map pixels on screen, and the tiles that reach into them
        // (with a row and a column more, for tall images).
        let left = centre.x - size.width / 2 / zoom, top = centre.y - size.height / 2 / zoom
        let right = centre.x + size.width / 2 / zoom, bottom = centre.y + size.height / 2 / zoom
        let tw = CGFloat(MapScene.tileWidth), th = CGFloat(MapScene.tileHeight)
        let columns = Int((left / tw).rounded(.down)) - 1 ..< Int((right / tw).rounded(.up)) + 1
        let rows = Int((top / (th / 2)).rounded(.down)) - 2 ..< Int((bottom / (th / 2)).rounded(.up)) + 3
        let draws = MapScene.plan(snapshot, images.lookup, columns: columns, rows: rows)

        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -left, y: -top)
        for d in draws {
            let o = MapScene.origin(d.x, d.y)
            switch d.drawing {
            case .fog:
                context.fill(diamond(CGFloat(o.x), CGFloat(o.y)), with: .color(.black.opacity(0.2)))
            case let .image(image, placement, dimmed, grey):
                guard let picture = images.image(image) else { continue }
                let w = Int(picture.size.width * picture.scale), h = Int(picture.size.height * picture.scale)
                let at = placement.origin(width: w, height: h)
                var c = context
                if dimmed { c.addFilter(.colorMultiply(Color(white: 0.8))) }
                if grey { c.addFilter(.grayscale(1)) }
                c.draw(Image(uiImage: picture),
                       in: CGRect(x: CGFloat(o.x + at.x), y: CGFloat(o.y + at.y), width: CGFloat(w), height: CGFloat(h)))
            }
        }
    }

    /// A tile's diamond.
    private func diamond(_ x: CGFloat, _ y: CGFloat) -> Path {
        let tw = CGFloat(MapScene.tileWidth), th = CGFloat(MapScene.tileHeight)
        var p = Path()
        p.move(to: CGPoint(x: x + tw / 2, y: y))
        p.addLine(to: CGPoint(x: x + tw, y: y + th / 2))
        p.addLine(to: CGPoint(x: x + tw / 2, y: y + th))
        p.addLine(to: CGPoint(x: x, y: y + th / 2))
        p.closeSubpath()
        return p
    }
}

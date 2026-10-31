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
    /// The unit being moved, drawn in front with the cursor on it.
    var activeUnitId: String?
    /// The path to show: the goto path, or the active unit's way to its
    /// destination.
    var path: UnitPath?
    /// A tile tapped.
    var onTap: (MapPosition) -> Void = { _ in }
    /// A tile pressed and held.
    var onLongPress: (MapPosition) -> Void = { _ in }

    /// The map pixel (at scale 1) at the screen's centre, and the zoom.
    @State private var centre: CGPoint?
    @State private var zoom: CGFloat = 0.75
    @State private var dragStart: CGPoint?
    @State private var zoomStart: CGFloat?
    /// Where the finger came down, for a long press, which does not say.
    @State private var touch: CGPoint?
    /// A long press was just recognized: its lifting is not a tap.
    @State private var held = false

    var body: some View {
        GeometryReader { geometry in
            let centre = self.centre ?? initialCentre
            // Java's animation frames are 125 milliseconds.
            TimelineView(.periodic(from: .now, by: 0.125)) { timeline in
                Canvas { context, size in
                    var options = MapOptions()
                    options.ticks = Int64(timeline.date.timeIntervalSince1970 * 1000) / 125
                    options.activeUnitId = activeUnitId
                    draw(&context, size, centre, options)
                }
            }
            .gesture(drag(centre).simultaneously(with: magnify))
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                if held {
                    held = false
                } else if let tile = tile(at: value.location, geometry.size, centre) {
                    onTap(tile)
                }
            })
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { touch = $0.startLocation })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                if let touch, let tile = tile(at: touch, geometry.size, centre) {
                    held = true
                    onLongPress(tile)
                }
            })
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Map")
            .accessibilityChildren { accessibleMap }
        }
    }

    /// What VoiceOver reads of the map, which is drawn as one picture:
    /// the colonies and the player's units on it.  Activating one taps
    /// it; the menu of its tile is a further action.
    @ViewBuilder private var accessibleMap: some View {
        ForEach(snapshot.colonies, id: \.id) { c in
            Rectangle().accessibilityLabel("Colony \(c.name)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onTap(c.position) }
                .accessibilityAction(named: "Menu") { onLongPress(c.position) }
        }
        ForEach(snapshot.ownUnits.filter { if case .tile = $0.place { true } else { false } }, id: \.id) { u in
            Rectangle().accessibilityLabel(u.id == activeUnitId ? "\(u.label), being moved" : u.label)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if let p = u.position { onTap(p) } }
                .accessibilityAction(named: "Menu") { if let p = u.position { onLongPress(p) } }
        }
    }

    /// The tile under a point on screen: the one whose diamond holds
    /// it, of the tiles round the row and column it falls in.
    private func tile(at point: CGPoint, _ size: CGSize, _ centre: CGPoint) -> MapPosition? {
        let x = centre.x + (point.x - size.width / 2) / zoom, y = centre.y + (point.y - size.height / 2) / zoom
        let tw = CGFloat(MapScene.tileWidth), th = CGFloat(MapScene.tileHeight)
        let row = Int((y / (th / 2)).rounded(.down))
        for r in [row, row - 1, row + 1] {
            let column = Int(((x - CGFloat(r & 1) * tw / 2) / tw).rounded(.down))
            for c in [column, column - 1, column + 1] {
                guard snapshot.map.tile(c, r) != nil else { continue }
                let o = MapScene.origin(c, r)
                let dx = abs(x - CGFloat(o.x) - tw / 2) / (tw / 2), dy = abs(y - CGFloat(o.y) - th / 2) / (th / 2)
                if dx + dy <= 1 { return MapPosition(x: c, y: r) }
            }
        }
        return nil
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

    private func draw(_ context: inout GraphicsContext, _ size: CGSize, _ centre: CGPoint, _ options: MapOptions) {
        // The map pixels on screen, and the tiles that reach into them
        // (with a row and a column more, for tall images).
        let left = centre.x - size.width / 2 / zoom, top = centre.y - size.height / 2 / zoom
        let right = centre.x + size.width / 2 / zoom, bottom = centre.y + size.height / 2 / zoom
        let tw = CGFloat(MapScene.tileWidth), th = CGFloat(MapScene.tileHeight)
        let columns = Int((left / tw).rounded(.down)) - 1 ..< Int((right / tw).rounded(.up)) + 1
        let rows = Int((top / (th / 2)).rounded(.down)) - 2 ..< Int((bottom / (th / 2)).rounded(.up)) + 3
        // The cursor blinks every half second (TerrainCursor).
        let cursor = activeUnitId.flatMap { snapshot.unit($0)?.position }
        let draws = MapScene.plan(snapshot, images.lookup, options, columns: columns, rows: rows)
            + MapScene.overlay(cursor: (options.ticks / 4) % 2 == 0 ? cursor : nil, path: path)

        context.scaleBy(x: zoom, y: zoom)
        context.translateBy(x: -left, y: -top)
        Self.render(draws, &context, images)
    }

    /// Draw a plan, in map pixels at scale 1.
    static func render(_ draws: [MapDraw], _ context: inout GraphicsContext, _ images: MapImageStore) {
        for d in draws {
            let o = MapScene.origin(d.x, d.y)
            switch d.drawing {
            case .fog:
                context.fill(diamond(CGFloat(o.x), CGFloat(o.y)), with: .color(.black.opacity(0.2)))
            case let .composite(composite, dimmed):
                guard let picture = images.image(composite) else { continue }
                var c = context
                if dimmed { c.addFilter(.colorMultiply(Color(white: 0.8))) }
                c.draw(Image(uiImage: picture), in: CGRect(x: CGFloat(o.x), y: CGFloat(o.y),
                                                          width: CGFloat(MapScene.tileWidth),
                                                          height: CGFloat(MapScene.tileHeight)))
            case let .image(image, placement, size, dimmed, grey):
                guard let picture = images.image(image) else { continue }
                let w = size.dimensions?.width ?? Int(picture.size.width * picture.scale)
                let h = size.dimensions?.height ?? Int(picture.size.height * picture.scale)
                let at = placement.origin(width: w, height: h)
                var c = context
                if dimmed { c.addFilter(.colorMultiply(Color(white: 0.8))) }
                if grey { c.addFilter(.grayscale(1)) }
                c.draw(Image(uiImage: picture),
                       in: CGRect(x: CGFloat(o.x + at.x), y: CGFloat(o.y + at.y), width: CGFloat(w), height: CGFloat(h)))
            case let .path(segments, color, width):
                var c = context
                c.translateBy(x: CGFloat(o.x), y: CGFloat(o.y))
                // Java's BasicStroke: square ends, mitred corners.
                c.stroke(path(segments), with: .color(Self.color(color)),
                         style: StrokeStyle(lineWidth: CGFloat(width), lineCap: .square, lineJoin: .miter))
            case let .chips(chips, x, y, dimmed):
                var c = context
                c.translateBy(x: CGFloat(o.x + x), y: CGFloat(o.y + y))
                if dimmed { c.addFilter(.colorMultiply(Color(white: 0.8))) }
                drawChips(&c, chips)
            case let .text(text, placement, dimmed):
                var c = context
                if dimmed { c.addFilter(.colorMultiply(Color(white: 0.8))) }
                drawText(&c, text, placement, CGFloat(o.x), CGFloat(o.y))
            case let .line(x1, y1, x2, y2, color):
                // The pixels from one end to the other.
                let r = CGRect(x: CGFloat(o.x + min(x1, x2)), y: CGFloat(o.y + min(y1, y2)),
                               width: CGFloat(abs(x2 - x1) + 1), height: CGFloat(abs(y2 - y1) + 1))
                context.fill(Path(r), with: .color(Self.color(color)))
            case let .pathStep(x2, y2, color):
                var p = Path()
                let cx = CGFloat(o.x + MapScene.tileWidth / 2), cy = CGFloat(o.y + MapScene.tileHeight / 2)
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: CGFloat(o.x + x2), y: CGFloat(o.y + y2)))
                context.stroke(p, with: .color(Self.color(color)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            case let .pathNode(color, turns):
                let cx = CGFloat(o.x + MapScene.tileWidth / 2), cy = CGFloat(o.y + MapScene.tileHeight / 2)
                let disc = Path(ellipseIn: CGRect(x: cx - 10, y: cy - 10, width: 20, height: 20))
                context.fill(disc, with: .color(Self.color(color)))
                context.stroke(disc, with: .color(.black.opacity(0.5)), lineWidth: 2)
                if let turns {
                    context.draw(Text(String(turns)).font(Self.font("normal-plain-smaller")).foregroundColor(.black),
                                 at: CGPoint(x: cx, y: cy))
                }
            case let .rectangle(x, y, w, h, color, filled):
                let r = CGRect(x: CGFloat(o.x + x), y: CGFloat(o.y + y), width: CGFloat(w), height: CGFloat(h))
                if filled {
                    context.fill(Path(r), with: .color(Self.color(color)))
                } else {
                    context.stroke(Path(r.offsetBy(dx: 0.5, dy: 0.5)), with: .color(Self.color(color)), lineWidth: 1)
                }
            }
        }
    }

    /// A row of chips, as Java makes them (ImageLibrary.createChip): a
    /// black edge, the background, and the text 3 pixels in.  Each
    /// after the first is stepped along by the first's width and 2.
    private static func drawChips(_ c: inout GraphicsContext, _ chips: [MapChip]) {
        var step: CGFloat?
        var x: CGFloat = 0
        for chip in chips {
            let text = c.resolve(Text(chip.text).font(Self.font(MapChip.font))
                .foregroundColor(Self.color(chip.foreground)))
            let size = text.measure(in: CGSize(width: 1000, height: 1000))
            let w = ceil(size.width) + 6, h = ceil(size.height) + 6
            let r = CGRect(x: x, y: 0, width: w, height: h)
            c.fill(Path(r), with: .color(.black))
            c.fill(Path(r.insetBy(dx: 1, dy: 1)), with: .color(Self.color(chip.background)))
            c.draw(text, at: CGPoint(x: x + 3, y: 3), anchor: .topLeading)
            if step == nil { step = w + 2 }
            x += step ?? 0
        }
    }

    /// Text with its letters edged a pixel round (ImageLibrary's string
    /// images: 2 pixels in, 4 wider than the text).
    private static func drawText(_ c: inout GraphicsContext, _ text: MapText, _ placement: MapPlacement,
                          _ ox: CGFloat, _ oy: CGFloat) {
        let font = Self.font(text.font)
        let edge = c.resolve(Text(text.text).font(font).foregroundColor(Self.color(text.borderColor)))
        let face = c.resolve(Text(text.text).font(font).foregroundColor(Self.color(text.color)))
        let size = face.measure(in: CGSize(width: 1000, height: 1000))
        let at = placement.origin(width: Int(ceil(size.width)) + 4, height: Int(ceil(size.height)))
        let p = CGPoint(x: ox + CGFloat(at.x) + 2, y: oy + CGFloat(at.y))
        for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
            c.draw(edge, at: CGPoint(x: p.x + CGFloat(dx), y: p.y + CGFloat(dy)), anchor: .topLeading)
        }
        c.draw(face, at: p, anchor: .topLeading)
    }

    private static func path(_ segments: [MapPathSegment]) -> Path {
        var p = Path()
        for s in segments {
            switch s {
            case let .move(x, y): p.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            case let .line(x, y): p.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            case let .quad(cx, cy, x, y):
                p.addQuadCurve(to: CGPoint(x: CGFloat(x), y: CGFloat(y)), control: CGPoint(x: CGFloat(cx), y: CGFloat(cy)))
            }
        }
        return p
    }

    /// A Java ARGB colour.
    static func color(_ argb: Int32) -> Color {
        let v = UInt32(bitPattern: argb)
        return Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                     blue: Double(v & 0xFF) / 255, opacity: Double(v >> 24) / 255)
    }

    /// Java's font names ("simple-bold-tiny"): the simple face (Java's
    /// Dialog) or the normal one (Serif), the style, and the size (tiny
    /// 12, smaller 14, at scale 1).
    static func font(_ name: String) -> Font {
        let parts = name.split(separator: "-").map(String.init)
        let size: CGFloat = parts.last == "tiny" ? 12 : parts.last == "smaller" ? 14 : 16
        let style = parts.count > 1 ? parts[1] : "plain"
        var font = Font.system(size: size, weight: style.contains("bold") ? .bold : .regular,
                               design: parts.first == "normal" ? .serif : .default)
        if style.contains("italic") { font = font.italic() }
        return font
    }

    /// A tile's diamond.
    static func diamond(_ x: CGFloat, _ y: CGFloat) -> Path {
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

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
import SwiftUI
import UIKit

/// The game's commands in the menu bar (on the Mac) and for a hardware
/// keyboard (on an iPad), with the keys of Java's client
/// (FreeColMessages.properties, "*Action.accelerator").  Java's Ctrl is
/// Command here, End Turn is Command-Return rather than Return, and the
/// numeric keypad's moves are left to the arrows, Home, End, Page Up and
/// Page Down, its other keys.
struct GameCommands: Commands {
    let store: GameStore

    var body: some Commands {
        // Java's New starts a new game, not another window onto this one.
        CommandGroup(replacing: .newItem) {
            Button("New Game…") { store.stopGamePrompt = true }
                .keyboardShortcut("n")
                .disabled(!store.hasGame || store.busy)
        }
        CommandGroup(after: .saveItem) {
            Button("Save Game…") { store.savePrompt = true }
                .keyboardShortcut("s")
                .disabled(!store.hasGame)
        }
        CommandMenu("Game") {
            // Java's key is Return alone, too easily pressed by accident.
            play("End Turn", .endTurn, key: .return, modifiers: .command)
            play("Wait", .wait, key: "w")
            Button("Execute Go-to Orders") { Task { await store.play(.executeGotoOrders) } }
                .keyboardShortcut("o", modifiers: [])
                .disabled(!store.hasGame || store.busy)
            Divider()
            Button("Europe") { Task { await store.openEurope() } }
                .keyboardShortcut("e", modifiers: [])
                .disabled(store.snapshot?.europe == nil || store.busy)
            Button("Reports") { Task { await store.openReports() } }
                .disabled(!store.hasGame || store.busy)
            Button("Trade Routes") { Task { await store.openRoutes() } }
                .keyboardShortcut("t", modifiers: [])
                .disabled(!store.hasGame || store.busy)
            Divider()
            Button("Sound…") { store.soundSettingsShown = true }
        }
        CommandMenu("Unit") {
            unit("Done", key: " ") { .skip(unitId: $0) }
            unit("Sentry", key: "s") { .changeState(unitId: $0, state: "SENTRY") }
            unit("Fortify", key: "f", enabled: store.actions?.fortify == true) {
                .changeState(unitId: $0, state: "FORTIFYING")
            }
            unit("Build Colony", key: "b", enabled: store.actions?.buildColony == true) { .buildColony(unitId: $0) }
            unit("Plow", key: "p", enabled: store.actions?.improvements["plow"] == true) {
                .improve(unitId: $0, improvementTypeId: "model.improvement.plow")
            }
            unit("Road", key: "r", enabled: store.actions?.improvements["road"] == true) {
                .improve(unitId: $0, improvementTypeId: "model.improvement.road")
            }
            unit("Clear Forest", key: "c", enabled: store.actions?.improvements["clearForest"] == true) {
                .improve(unitId: $0, improvementTypeId: "model.improvement.clearForest")
            }
            Button("Go To…") { store.startGoto() }
                .keyboardShortcut("g", modifiers: [])
                .disabled(store.activeUnitId == nil || store.actions?.gotoTile != true || store.busy)
            unit("Clear Orders", key: "z") { .clearOrders(unitId: $0) }
            unit("Disband", key: "d") { .disband(unitId: $0) }
            Divider()
            move("Move North", "N", .upArrow)
            move("Move North-East", "NE", .pageUp)
            move("Move East", "E", .rightArrow)
            move("Move South-East", "SE", .pageDown)
            move("Move South", "S", .downArrow)
            move("Move South-West", "SW", .end)
            move("Move West", "W", .leftArrow)
            move("Move North-West", "NW", .home)
        }
    }

    private func play(_ title: String, _ action: GameEngine.PlayAction, key: KeyEquivalent,
                      modifiers: EventModifiers = []) -> some View {
        Button(title) { Task { await store.play(action) } }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(!store.hasGame || store.busy)
    }

    private func unit(_ title: String, key: KeyEquivalent, enabled: Bool = true,
                      _ action: @escaping (String) -> GameEngine.PlayAction) -> some View {
        Button(title) {
            if let id = store.activeUnitId { Task { await store.play(action(id)) } }
        }
        .keyboardShortcut(key, modifiers: [])
        .disabled(store.activeUnitId == nil || !enabled || store.busy)
    }

    private func move(_ title: String, _ direction: String, _ key: KeyEquivalent) -> some View {
        unit(title, key: key) { .move(unitId: $0, direction: direction) }
    }
}

/// A right click (or a two-finger click on a trackpad) where this view
/// lies, for the tile menu that a long press opens on a touch screen.
/// Catalyst gives a right click to a context menu interaction, not as a
/// touch: one on the window asks for a menu, and this answers with none,
/// passing on where the click was.  Clicks on a sheet over this view do
/// not count.  On a touch screen the long press does it, so this is for
/// the Mac only.
struct SecondaryClickReader: UIViewRepresentable {
    var action: (CGPoint) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.action = action
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        probe.action = action
    }

    final class Probe: UIView, UIContextMenuInteractionDelegate {
        var action: (CGPoint) -> Void = { _ in }
        private var interaction: UIContextMenuInteraction?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            #if targetEnvironment(macCatalyst)
            if let interaction { interaction.view?.removeInteraction(interaction) }
            interaction = nil
            guard let window else { return }
            let i = UIContextMenuInteraction(delegate: self)
            window.addInteraction(i)
            interaction = i
            #endif
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let window, let hit = window.hitTest(location, with: nil),
                  Self.screen(of: hit) === Self.screen(of: self) else { return nil }
            let point = window.convert(location, to: self)
            if bounds.contains(point) { action(point) }
            return nil
        }

        /// The SwiftUI screen a view is drawn in: the window's, or a
        /// sheet's.
        private static func screen(of view: UIView) -> UIView? {
            var v: UIView? = view
            while let u = v, !String(describing: type(of: u)).hasPrefix("_UIHostingView") { v = u.superview }
            return v
        }
    }
}

/// Keeps the Mac's window large enough for the map and its panels.
struct MinimumWindowSize: UIViewRepresentable {
    let size: CGSize

    func makeUIView(context: Context) -> UIView {
        let view = SizedView()
        view.size = size
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}

    private final class SizedView: UIView {
        var size = CGSize.zero
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.windowScene?.sizeRestrictions?.minimumSize = size
        }
    }
}

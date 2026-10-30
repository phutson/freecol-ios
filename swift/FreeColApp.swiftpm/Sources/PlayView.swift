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

/// The map with what is needed to play on it: the turn and the end
/// turn button, the unit being moved and what it can do, and the
/// client's and server's questions.
struct PlayView: View {
    @Environment(GameStore.self) private var store
    let snapshot: GameSnapshot
    let images: MapImageStore

    var body: some View {
        ZStack(alignment: .top) {
            MapView(snapshot: snapshot, images: images, activeUnitId: store.activeUnitId, path: store.shownPath,
                    onTap: { p in Task { await store.tap(p) } })
                .ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar(snapshot: snapshot)
                Spacer()
                if !store.messages.isEmpty { MessagesView(messages: store.messages) }
                if let unit = store.activeUnit { UnitPanel(unit: unit) }
            }
            .padding()
            if store.busy {
                ProgressView().tint(.white).padding().background(.thinMaterial, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // While a colony or Europe is shown, its own dialogs ask.
        .modifier(Dialogs(active: store.colony == nil && store.europe == nil && store.reports == nil))
        .sheet(isPresented: Binding(get: { store.reports != nil }, set: { if !$0 { store.closeReports() } })) {
            if let reports = store.reports { ReportsView(reports: reports, snapshot: snapshot).environment(store) }
        }
        .modifier(TradeSheets())
        .sheet(isPresented: Binding(get: { store.sendingUnitId != nil }, set: { if !$0 { store.sendingUnitId = nil } })) {
            if let id = store.sendingUnitId { DestinationSheet(unitId: id).environment(store) }
        }
        .sheet(isPresented: Binding(get: { store.routes != nil }, set: { if !$0 { store.closeRoutes() } })) {
            if let routes = store.routes { TradeRoutesView(screen: routes).environment(store) }
        }
        .fullScreenCover(isPresented: Binding(get: { store.europe != nil }, set: { if !$0 { store.closeEurope() } })) {
            if let europe = store.europe, let snapshot = store.snapshot {
                EuropeView(europe: europe, snapshot: snapshot, images: images)
                    .environment(store)
                    .modifier(Dialogs())
            }
        }
        .fullScreenCover(isPresented: Binding(get: { store.colony != nil }, set: { if !$0 { store.closeColony() } })) {
            if let colony = store.colony, let snapshot = store.snapshot {
                ColonyView(colony: colony, snapshot: snapshot, images: images)
                    .environment(store)
                    .modifier(Dialogs())
            }
        }
    }
}

/// The nation, the turn and gold, and ending the turn.
struct TopBar: View {
    @Environment(GameStore.self) private var store
    let snapshot: GameSnapshot
    @State private var saving = false
    @State private var saveName = ""

    var body: some View {
        HStack {
            Text("\(snapshot.player?.nationName ?? "") — \(snapshot.turnName)")
                .font(.headline)
            if let gold = snapshot.player?.gold { Text("\(gold) gold").monospacedDigit() }
            Spacer()
            Menu("Game") {
                Button("Reports") { Task { await store.openReports() } }
                Button("Trade routes") { Task { await store.openRoutes() } }
                Button("Save…") { saving = true }
            }
            if snapshot.europe != nil {
                Button("Europe") { Task { await store.openEurope() } }
            }
            Button("Next unit") { Task { await store.play(.wait) } }
            Button("End turn") { Task { await store.play(.endTurn) } }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.isPlayersTurn)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .disabled(store.busy)
        .alert("Save the game", isPresented: $saving) {
            TextField("Name", text: $saveName)
                .onAppear { saveName = "\(snapshot.player?.nationName ?? "") \(snapshot.turnName)" }
            Button("Save") { Task { await store.save(as: saveName) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// The turn's messages, most recent last.
struct MessagesView: View {
    let messages: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(messages.enumerated()), id: \.offset) { Text($0.element).font(.callout) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 90)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(.bottom, 8)
    }
}

/// The unit being moved: what it is, its moves, a pad to move it, and
/// the unit actions open to it (the map controls' unit buttons).
struct UnitPanel: View {
    @Environment(GameStore.self) private var store
    let unit: UnitSnapshot

    /// Moves in thirds, as Java shows them ("1 2/3").
    private var moves: String {
        let whole = unit.movesLeft / 3, part = unit.movesLeft % 3
        return part == 0 ? "\(whole)" : whole == 0 ? "\(part)/3" : "\(whole) \(part)/3"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            DirectionPad { d in Task { await store.play(.move(unitId: unit.id, direction: d)) } }
            VStack(alignment: .leading, spacing: 8) {
                Text(unit.label).font(.headline)
                Text("Moves \(moves) · \(unit.state.lowercased())").font(.subheadline).foregroundStyle(.secondary)
                actions
                if store.choosingGoto {
                    Text(store.gotoPath == nil ? "Tap where to go." : "Tap again to go there.")
                        .font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .disabled(store.busy)
    }

    private var actions: some View {
        let a = store.actions
        let improvements = (a?.improvements ?? [:]).filter(\.value).keys.sorted()
        return FlowLayout {
            button("Wait") { await store.play(.wait) }
            button("Done") { await store.play(.skip(unitId: unit.id)) }
            button("Sentry") { await store.play(.changeState(unitId: unit.id, state: "SENTRY")) }
            button("Fortify", enabled: a?.fortify == true) {
                await store.play(.changeState(unitId: unit.id, state: "FORTIFYING"))
            }
            ForEach(improvements, id: \.self) { suffix in
                button(Self.improvementNames[suffix] ?? suffix) {
                    await store.play(.improve(unitId: unit.id, improvementTypeId: "model.improvement." + suffix))
                }
            }
            button("Build colony", enabled: a?.buildColony == true) { await store.play(.buildColony(unitId: unit.id)) }
            if store.choosingGoto {
                button("Cancel go to") { store.stopGoto() }
            } else {
                button("Go to", enabled: a?.gotoTile == true) { store.startGoto() }
            }
            if unit.isNaval { button("Europe") { await store.goToEurope() } }
            if unit.destinationId != nil || unit.state != "ACTIVE" {
                button("Clear orders") { await store.play(.clearOrders(unitId: unit.id)) }
            }
            button("Disband") { await store.play(.disband(unitId: unit.id)) }
            button("Send to") { store.sendingUnitId = unit.id }
            if unit.isCarrier { RouteMenu(unitId: unit.id).buttonStyle(.bordered) }
        }
    }

    static let improvementNames = ["plow": "Plow", "road": "Road", "clearForest": "Clear forest"]

    private func button(_ title: String, enabled: Bool = true, _ action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .buttonStyle(.bordered)
            .disabled(!enabled)
    }
}

/// Eight arrows for the directions on the map, as the screen shows them:
/// north up, east right.
struct DirectionPad: View {
    let move: (String) -> Void

    private static let rows = [[("NW", "arrow.up.left"), ("N", "arrow.up"), ("NE", "arrow.up.right")],
                               [("W", "arrow.left"), ("", ""), ("E", "arrow.right")],
                               [("SW", "arrow.down.left"), ("S", "arrow.down"), ("SE", "arrow.down.right")]]

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<3, id: \.self) { r in
                GridRow {
                    ForEach(0..<3, id: \.self) { c in
                        let (d, icon) = Self.rows[r][c]
                        if d.isEmpty {
                            Color.clear.frame(width: 44, height: 44)
                        } else {
                            Button { move(d) } label: { Image(systemName: icon).frame(width: 44, height: 44) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Move \(d)")
                        }
                    }
                }
            }
        }
    }
}

/// Buttons wrapped onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(bounds.width, subviews)
        for (view, at) in zip(subviews, placed.points) {
            view.place(at: CGPoint(x: bounds.minX + at.x, y: bounds.minY + at.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, s.height)
        }
        return (CGSize(width: widest, height: y + rowHeight), points)
    }
}

/// The client's questions, the server's requests, and what the player
/// is told, as alerts.
struct Dialogs: ViewModifier {
    @Environment(GameStore.self) private var store
    /// Whether these dialogs are the ones showing (a full screen cover
    /// shows its own).
    var active = true
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(store.question?.text ?? "", isPresented: binding(active && !sheetShown && store.question != nil) { store.dismissQuestion() },
                   presenting: store.question) { q in
                if q.choices.isEmpty {
                    TextField(q.suggestion.flatMap { Int($0) } != nil ? "Amount" : "Name", text: $name)
                        .onAppear { name = q.suggestion ?? "" }
                    Button("OK") { store.answer(name) }
                    Button("Cancel", role: .cancel) { store.dismissQuestion() }
                } else {
                    ForEach(q.choices, id: \.id) { c in
                        Button(c.label) { store.answer(c.id) }
                    }
                }
            }
            .alert(requestTitle, isPresented: binding(active && !sheetShown && store.question == nil && !store.requests.isEmpty) {},
                   presenting: store.requests.first) { r in
                switch r {
                case let .newLandName(_, suggestion, _), let .newRegionName(_, _, _, suggestion, _):
                    TextField("Name", text: $name).onAppear { name = suggestion }
                    Button("OK") { store.answer(r, .name(name)) }
                case .firstContact:
                    Button("Accept") { store.answer(r, .accept(true)) }
                    Button("Refuse", role: .cancel) { store.answer(r, .accept(false)) }
                case let .monarch(_, _, _, yes, no):
                    if let yes { Button(yes) { store.answer(r, .accept(true)) } }
                    Button(no, role: .cancel) { store.answer(r, .accept(false)) }
                case let .chooseFather(fathers):
                    ForEach(fathers, id: \.id) { f in
                        Button("\(f.name) (\(f.typeName))") { store.answer(r, .choice(f.id)) }
                    }
                case let .emigrate(_, _, _, choices):
                    ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                        Button(c) { store.answer(r, .choice(String(i))) }
                    }
                case let .nativeDemand(_, _, _, _, _, _, yes, no):
                    Button(yes) { store.answer(r, .accept(true)) }
                    Button(no, role: .cancel) { store.answer(r, .accept(false)) }
                case let .loot(_, _, goods, space, _):
                    ForEach(Array(goods.enumerated()), id: \.offset) { _, g in
                        Button("\(g.amount) \(g.typeId.split(separator: ".").last ?? "")") {
                            store.answer(r, .goods([g]))
                        }
                    }
                    if goods.count > 1 && space > 1 {
                        Button("All that fits") { store.answer(r, .goods(Array(goods.prefix(space)))) }
                    }
                    Button("None", role: .cancel) { store.answer(r, .goods([])) }
                case .incite:
                    Button("Yes") { store.answer(r, .accept(true)) }
                    Button("No", role: .cancel) { store.answer(r, .accept(false)) }
                case .nativeTrade, .negotiation:
                    // Shown in their own sheets.
                    EmptyView()
                }
            } message: { r in
                switch r {
                case let .firstContact(_, _, _, _, text), let .monarch(_, _, text, _, _),
                     let .emigrate(_, _, text, _), let .nativeDemand(_, _, _, _, _, text, _, _),
                     let .incite(_, _, _, _, text):
                    Text(text)
                case let .chooseFather(fathers):
                    Text(fathers.map { "\($0.name): \($0.description)" }.joined(separator: "\n\n"))
                default:
                    EmptyView()
                }
            }
            .alert(store.notices.first ?? "",
                   isPresented: binding(active && !sheetShown && store.question == nil && store.requests.isEmpty && !store.notices.isEmpty) {
                       store.notices.removeFirst()
                   }) {
                Button("OK") {}
            }
    }

    private var requestTitle: String {
        switch store.requests.first {
        case let .newLandName(_, _, text)?, let .newRegionName(_, _, _, _, text)?: text
        case let .firstContact(_, _, _, title, _)?, let .monarch(_, title, _, _, _)?: title
        case .chooseFather?: "Continental Congress"
        case let .emigrate(count, _, _, _)?: count > 1 ? "Choose \(count) emigrants" : "Choose an emigrant"
        case let .nativeDemand(_, _, _, _, title, _, _, _)?, let .loot(_, _, _, _, title)?: title
        case .incite?: "Incite"
        case .nativeTrade?, .negotiation?, nil: ""
        }
    }

    /// Whether a trade, negotiation or spy's sheet is up, which an
    /// alert would dismiss.
    private var sheetShown: Bool {
        store.trade != nil || store.negotiation != nil || store.spiedColony != nil || store.routes != nil
            || store.sendingUnitId != nil
    }

    /// A presentation binding that runs an action when dismissed.
    private func binding(_ shown: Bool, onDismiss: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: { shown }, set: { if !$0 { onDismiss() } })
    }
}

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

/// The sheets for trading with natives, negotiating with Europeans, and
/// what a spy saw, each hung on its own view so they do not clash.
struct TradeSheets: ViewModifier {
    @Environment(GameStore.self) private var store

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear.sheet(isPresented: Binding(get: { store.trade != nil },
                                                       set: { if !$0, store.trade != nil { store.tradeStep(.close) } })) {
                    if let screen = store.trade { NativeTradeSheet(screen: screen).environment(store) }
                }
            }
            .background {
                Color.clear.sheet(isPresented: Binding(get: { store.negotiation != nil }, set: { _ in })) {
                    if let n = store.negotiation { NegotiationSheet(negotiation: n).environment(store) }
                }
            }
            .background {
                Color.clear.sheet(isPresented: Binding(get: { store.spiedColony != nil },
                                                       set: { if !$0 { store.spiedColony = nil } })) {
                    if let colony = store.spiedColony { SpiedColonySheet(colony: colony) }
                }
            }
    }
}

/// Trading at a native settlement, as Java's client asks it: buy, sell
/// or give, which goods, and at the price or haggling.
struct NativeTradeSheet: View {
    @Environment(GameStore.self) private var store
    let screen: NativeTradeScreen

    private enum Step: Equatable {
        case menu, buyList, sellList, giftList
        /// Goods to buy or sell (nil for those haggled over).
        case buy(Int?), sell(Int?)
    }

    @State private var step: Step?
    @State private var firstTime = true

    private var current: Step {
        step ?? (screen.haggleBuy != nil ? .buy(nil) : screen.haggleSell != nil ? .sell(nil) : .menu)
    }

    var body: some View {
        let l = screen.labels
        VStack(alignment: .leading, spacing: 16) {
            switch current {
            case .menu:
                Text(firstTime ? screen.prompt : screen.welcome).font(.headline)
                if screen.canBuy { Button(l.toBuy) { go(.buyList) } }
                if screen.canSell { Button(l.toSell) { go(.sellList) } }
                if screen.canGift { Button(l.toGift) { go(.giftList) } }
                Button(l.cancel, role: .cancel) { store.tradeStep(.close) }
            case .buyList:
                Text(l.buyQuestion).font(.headline)
                ForEach(Array(screen.buy.enumerated()), id: \.offset) { i, item in
                    Button(item.label) { go(.buy(i)) }
                }
                Button(l.nothing, role: .cancel) { go(.menu) }
            case .sellList:
                Text(l.sellQuestion).font(.headline)
                ForEach(Array(screen.sell.enumerated()), id: \.offset) { i, item in
                    Button(item.label) { go(.sell(i)) }
                }
                Button(l.nothing, role: .cancel) { go(.menu) }
            case .giftList:
                Text(l.giftQuestion).font(.headline)
                ForEach(Array(screen.gift.enumerated()), id: \.offset) { i, label in
                    Button(label) { store.tradeStep(.gift(i)) }
                }
                Button(l.cancel, role: .cancel) { go(.menu) }
            case .buy(let i):
                if let item = i.map({ screen.buy.indices.contains($0) ? screen.buy[$0] : nil }) ?? screen.haggleBuy {
                    Text(item.text)
                    Button(l.takeBuy) { store.tradeStep(.buy(i, haggle: false)) }.disabled(!item.canBuy)
                    Button(l.haggleBuy) { store.tradeStep(.buy(i, haggle: true)) }
                }
                Button(l.cancel, role: .cancel) { go(.menu) }
            case .sell(let i):
                if let item = i.map({ screen.sell.indices.contains($0) ? screen.sell[$0] : nil }) ?? screen.haggleSell {
                    Text(item.text)
                    Button(l.takeSell) { store.tradeStep(.sell(i, haggle: false)) }
                    Button(l.haggleSell) { store.tradeStep(.sell(i, haggle: true)) }
                    // As in Java, offering it as a gift here does nothing.
                    Button(item.giftLabel) { go(.menu) }
                }
                Button(l.cancel, role: .cancel) { go(.menu) }
            }
        }
        .buttonStyle(.bordered)
        .padding(24)
        .frame(maxWidth: 500, alignment: .leading)
        .presentationDetents([.medium, .large])
        .onChange(of: screen) {
            step = nil
            firstTime = true
        }
    }

    private func go(_ next: Step) {
        if next == .menu { firstTime = false }
        step = next
    }
}

/// A negotiation with another European (NegotiationDialog): what each
/// side could give, what is on the table, and the answers.
struct NegotiationSheet: View {
    @Environment(GameStore.self) private var store
    let negotiation: Negotiation

    @State private var items: [TradeOffer] = []
    @State private var changed = false
    @State private var screen: NegotiationScreen?
    @State private var goldDemand = 0
    @State private var goldOffer = 0

    var body: some View {
        NavigationStack {
            Form {
                if let s = screen {
                    Section {
                        ForEach(Array(s.summary.enumerated()), id: \.offset) { i, line in
                            Text(line).font(i == 0 ? .body : .callout).foregroundStyle(i == 0 ? .primary : .secondary)
                        }
                        if !items.isEmpty {
                            Button(s.labels.clear + " all", role: .destructive) { set([]) }
                        }
                    }
                    Section(s.demand) { side(s, fromPlayer: false) }
                    Section(s.offer) { side(s, fromPlayer: true) }
                    if let stances = s.stances, !stances.isEmpty {
                        Section(s.labels.stance) {
                            ForEach(stances, id: \.id) { c in
                                Button(c.label + (s.stance == c.id ? " ✓" : "")) {
                                    add(.stance(fromPlayer: false, stance: c.id))
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(screen?.title ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let s = screen {
                    if let cancel = s.cancel {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(cancel) { store.answer(negotiation, .cancel, items) }
                        }
                    }
                    ToolbarItemGroup(placement: .confirmationAction) {
                        if let accept = s.accept {
                            Button(accept) { store.answer(negotiation, .accept, items) }.disabled(!s.acceptEnabled)
                        }
                        Button(s.send) { store.answer(negotiation, .send, items) }
                    }
                }
            }
        }
        .interactiveDismissDisabled()
        .task {
            items = negotiation.items
            await refresh()
        }
    }

    /// One side's panels: gold, colonies, goods, natives to incite and
    /// units.
    @ViewBuilder private func side(_ s: NegotiationScreen, fromPlayer: Bool) -> some View {
        let gold = fromPlayer ? s.goldOffer : s.goldDemand
        let amount = fromPlayer ? $goldOffer : $goldDemand
        HStack {
            Text("\(s.labels.gold) \(gold.text)")
            Spacer()
            TextField("0", value: amount, format: .number).keyboardType(.numberPad).frame(width: 90)
                .multilineTextAlignment(.trailing)
            Button(s.labels.add) {
                let g = min(max(amount.wrappedValue, 0), gold.maximum)
                add(.gold(fromPlayer: fromPlayer, amount: g))
            }
        }
        choices(s.labels.colony, fromPlayer ? s.coloniesOffer : s.coloniesDemand) {
            .colony(fromPlayer: fromPlayer, colonyId: $0)
        }
        if let goods = fromPlayer ? s.goodsOffer : s.goodsDemand, !goods.isEmpty {
            Menu(s.labels.goods) {
                ForEach(goods, id: \.goodsTypeId) { g in
                    Button(g.label) {
                        add(.goods(fromPlayer: fromPlayer, goodsTypeId: g.goodsTypeId, amount: g.amount,
                                   locationId: g.locationId))
                    }
                }
            }
        }
        choices(s.labels.incite, fromPlayer ? s.inciteOffer : s.inciteDemand) {
            .incite(fromPlayer: fromPlayer, victimId: $0)
        }
        choices(s.labels.unit, fromPlayer ? s.unitsOffer : s.unitsDemand) { .unit(fromPlayer: fromPlayer, unitId: $0) }
    }

    @ViewBuilder private func choices(_ title: String, _ list: [NegotiationScreen.Choice]?,
                                      _ make: @escaping (String) -> TradeOffer) -> some View {
        if let list, !list.isEmpty {
            Menu(title) {
                ForEach(list, id: \.id) { c in Button(c.label) { add(make(c.id)) } }
            }
        }
    }

    private func add(_ item: TradeOffer) {
        set(TradeOffer.adding(item, to: items))
    }

    private func set(_ new: [TradeOffer]) {
        items = new
        changed = true
        Task { await refresh() }
    }

    private func refresh() async {
        screen = await store.negotiationScreen(negotiation, items, changed: changed)
        if let s = screen {
            goldOffer = max(s.goldOffer.given, 0)
            goldDemand = max(s.goldDemand.given, 0)
        }
    }
}

/// What a spy saw of a foreign colony: its people, buildings and goods.
struct SpiedColonySheet: View {
    let colony: ColonyScreen

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(colony.unitCount) colonists, \(colony.sonsOfLiberty)% for liberty")
                    if let building = colony.building { Text("Building: \(building)") }
                }
                Section("Buildings") {
                    ForEach(Array(colony.buildings.enumerated()), id: \.offset) { _, b in
                        HStack {
                            Text(b.name)
                            Spacer()
                            if !b.unitIds.isEmpty { Text("\(b.unitIds.count) at work").foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("Warehouse") {
                    ForEach(colony.warehouse, id: \.typeId) { g in
                        HStack {
                            Text(g.typeId.split(separator: ".").last.map(String.init) ?? g.typeId)
                            Spacer()
                            Text("\(g.amount)")
                        }
                    }
                }
            }
            .navigationTitle(colony.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The trade routes (TradeRoutePanel and TradeRouteInputPanel): each with
/// its stops and what is loaded at them.
struct TradeRoutesView: View {
    @Environment(GameStore.self) private var store
    let screen: TradeRoutesScreen

    var body: some View {
        NavigationStack {
            List {
                ForEach(screen.routes) { r in
                    NavigationLink {
                        TradeRouteEditor(route: r, screen: screen).environment(store)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(r.name)
                            Text(r.stops.map(\.locationName).joined(separator: " → ") + " · \(r.unitIds.count) units")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets {
                        let id = screen.routes[i].id
                        Task { await store.changeRoutes(.deleteTradeRoute(routeId: id)) }
                    }
                }
            }
            .navigationTitle("Trade routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New") { Task { await store.changeRoutes(.newTradeRoute) } }
                }
                ToolbarItem(placement: .cancellationAction) { Button("Done") { store.closeRoutes() } }
            }
        }
    }
}

struct TradeRouteEditor: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var route: TradeRouteInfo
    let screen: TradeRoutesScreen

    var body: some View {
        Form {
            TextField("Name", text: $route.name)
            ForEach(Array(route.stops.indices), id: \.self) { i in
                Section(route.stops[i].locationName) {
                    ForEach(Array(screen.goodsIds.enumerated()), id: \.offset) { g, id in
                        CheckRow(title: screen.goodsNames[g], isOn: Binding(get: { route.stops[i].cargo.contains(id) }, set: { on in
                            if on { route.stops[i].cargo.append(id) } else { route.stops[i].cargo.removeAll { $0 == id } }
                        }))
                    }
                    Button("Remove stop", role: .destructive) { route.stops.remove(at: i) }
                }
            }
            Menu("Add a stop") {
                ForEach(screen.locations, id: \.locationId) { l in Button(l.locationName) { route.stops.append(l) } }
            }
        }
        .navigationTitle(route.name)
        .toolbar {
            Button("Save") {
                Task {
                    await store.changeRoutes(.updateTradeRoute(route))
                    dismiss()
                }
            }
        }
    }
}

/// Give the unit a trade route, or take it away.
struct RouteMenu: View {
    @Environment(GameStore.self) private var store
    let unitId: String
    @State private var routes: [TradeRouteInfo] = []

    var body: some View {
        Menu("Route") {
            ForEach(routes) { r in
                Button(r.name) { Task { await store.play(.assignTradeRoute(unitId: unitId, routeId: r.id)) } }
            }
            Button("None") { Task { await store.play(.assignTradeRoute(unitId: unitId, routeId: nil)) } }
        }
        .task(id: unitId) { routes = await store.routeList() }
    }
}

/// Where to send a unit (SelectDestinationDialog).
struct DestinationSheet: View {
    @Environment(GameStore.self) private var store
    let unitId: String
    @State private var order = DestinationOrder.owner
    @State private var onlyMine = true
    @State private var list: [DestinationChoice] = []

    var body: some View {
        NavigationStack {
            List {
                CheckRow(title: "Only my colonies", isOn: $onlyMine)
                Picker("Sort by", selection: $order) {
                    Text("Owner").tag(DestinationOrder.owner)
                    Text("Name").tag(DestinationOrder.name)
                    Text("Distance").tag(DestinationOrder.distance)
                }
                ForEach(list.filter { !onlyMine || $0.isOwn }, id: \.id) { d in
                    Button(d.text) {
                        store.sendingUnitId = nil
                        Task { await store.play(.selectDestination(unitId: unitId, destinationId: d.id)) }
                    }
                }
            }
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { store.sendingUnitId = nil } }
            }
        }
        .task(id: order) { list = await store.destinations(unitId, order: order) }
    }
}

/// A row with a tick, turned on and off by tapping it.
struct CheckRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack {
                Text(title)
                Spacer()
                if isOn { Image(systemName: "checkmark") }
            }
        }
    }
}

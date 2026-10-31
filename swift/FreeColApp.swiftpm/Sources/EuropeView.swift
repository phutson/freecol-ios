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

/// What is dragged between the screens' panels: a unit, or goods from
/// the market, a warehouse or a carrier.
enum Drag {
    case unit(String)
    /// Goods of a type, an amount, and where from: "market", or the
    /// carrier's or colony's identifier.
    case goods(String, Int, from: String)

    var text: String {
        switch self {
        case .unit(let id): "unit|\(id)"
        case let .goods(type, amount, from): "goods|\(type)|\(amount)|\(from)"
        }
    }

    init?(_ text: String) {
        let p = text.split(separator: "|").map(String.init)
        switch p.first {
        case "unit" where p.count == 2: self = .unit(p[1])
        case "goods" where p.count == 4: self = .goods(p[1], Int(p[2]) ?? 0, from: p[3])
        default: return nil
        }
    }
}

/// Europe, as Java's Europe panel shows it: the ships in port and their
/// cargo, the docks, the market, recruiting, training and buying, and
/// the ships at sea.  Goods are dragged between the market and ships,
/// and units between the docks and ships.
struct EuropeView: View {
    @Environment(GameStore.self) private var store
    let europe: EuropeScreen
    let snapshot: GameSnapshot
    let images: MapImageStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    inPort
                    docks
                    market
                    recruit
                    offers("Train", europe.train)
                    offers("Buy", europe.purchase)
                    atSea
                }
                .padding()
            }
            .navigationTitle("Europe · \(europe.gold) gold")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { store.closeEurope() } }
            }
            .disabled(store.busy)
        }
    }

    private var inPort: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("In port").font(.headline)
            if europe.carriers.isEmpty { Text("No ships").foregroundStyle(.secondary) }
            ForEach(europe.carriers, id: \.id) { c in
                ShipCard(shipId: c.id, goods: c.goods, unitIds: c.unitIds, snapshot: snapshot, images: images) {
                    Button("Unload") { Task { await store.play(.unloadAll(carrierId: c.id)) } }
                    DestinationMenu(title: "Sail to", destinations: store.destinations[c.id] ?? []) { id in
                        Task { await store.play(.sail(carrierId: c.id, destinationId: id)) }
                    }
                }
            }
        }
    }

    private var docks: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Docks").font(.headline)
            FlowLayout {
                ForEach(europe.docks, id: \.self) { id in
                    UnitIcon(unitId: id, snapshot: snapshot, images: images)
                        .draggable(Drag.unit(id).text)
                        .contextMenu { RoleMenu(unitId: id) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .dropDestination(for: String.self) { items, _ in
                guard case .unit(let id)? = items.first.flatMap(Drag.init) else { return false }
                Task { await store.play(.leaveShip(unitId: id)) }
                return true
            }
        }
    }

    /// The market: each goods' sale and purchase prices, boycotted goods
    /// marked; drag goods onto a ship to buy, and from a ship here to
    /// sell.
    private var market: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Market").font(.headline)
            FlowLayout {
                ForEach(europe.market, id: \.typeId) { g in
                    VStack(spacing: 2) {
                        GoodsIcon(typeId: g.typeId, images: images, size: 32)
                            .overlay { if !g.canTrade { Image(systemName: "nosign").foregroundStyle(.red) } }
                        Text("\(g.paidForSale)/\(g.costToBuy)").font(.caption).monospacedDigit()
                    }
                    .frame(width: 52)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue("Sells for \(g.paidForSale), costs \(g.costToBuy)")
                    .draggable(Drag.goods(g.typeId, 100, from: "market").text)
                    .contextMenu {
                        if !g.canTrade {
                            Button("Pay arrears (\(g.arrears))") {
                                Task { await store.play(.payArrears(goodsTypeId: g.typeId)) }
                            }
                        }
                    }
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .dropDestination(for: String.self) { items, _ in
                guard case let .goods(type, amount, from)? = items.first.flatMap(Drag.init), from != "market"
                else { return false }
                Task { await store.play(.unload(goodsTypeId: type, amount: amount, carrierId: from)) }
                return true
            }
        }
    }

    private var recruit: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recruit · \(europe.recruitPrice) gold, or free in \(europe.recruitTurns) turns").font(.headline)
            HStack {
                ForEach(Array(europe.recruitables.enumerated()), id: \.offset) { i, r in
                    Button(r.label) { Task { await store.play(.recruit(index: i)) } }
                        .buttonStyle(.bordered)
                        .disabled(!europe.canRecruit)
                }
            }
        }
    }

    private func offers(_ title: String, _ list: [UnitOffer]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            FlowLayout {
                ForEach(list, id: \.typeId) { o in
                    Button("\(o.name) · \(o.price)") { Task { await store.play(.train(unitTypeId: o.typeId)) } }
                        .buttonStyle(.bordered)
                        .disabled(!o.affordable)
                }
            }
        }
    }

    private var atSea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("At sea").font(.headline)
            HStack {
                Text("To Europe:")
                ForEach(europe.toEurope, id: \.self) { UnitIcon(unitId: $0, snapshot: snapshot, images: images) }
                Spacer()
                Text("To America:")
                ForEach(europe.toAmerica, id: \.self) { UnitIcon(unitId: $0, snapshot: snapshot, images: images) }
            }
        }
    }
}

/// A ship and its holds: the goods and units aboard, each draggable;
/// units dropped on it board, goods dropped on it load.
struct ShipCard<Buttons: View>: View {
    @Environment(GameStore.self) private var store
    let shipId: String
    let goods: [GoodsAmount]
    let unitIds: [String]
    let snapshot: GameSnapshot
    let images: MapImageStore
    @ViewBuilder var buttons: Buttons

    var body: some View {
        HStack(spacing: 8) {
            UnitIcon(unitId: shipId, snapshot: snapshot, images: images, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.unit(shipId)?.label ?? "").font(.subheadline).bold()
                HStack(spacing: 6) {
                    ForEach(goods, id: \.typeId) { g in
                        VStack(spacing: 0) {
                            GoodsIcon(typeId: g.typeId, images: images, size: 28)
                            Text("\(g.amount)").font(.caption2).monospacedDigit()
                        }
                        .draggable(Drag.goods(g.typeId, g.amount, from: shipId).text)
                    }
                    ForEach(unitIds, id: \.self) { id in
                        UnitIcon(unitId: id, snapshot: snapshot, images: images, size: 36)
                            .draggable(Drag.unit(id).text)
                    }
                }
                .frame(minHeight: 40)
            }
            Spacer()
            buttons.buttonStyle(.bordered)
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .dropDestination(for: String.self) { items, _ in
            switch items.first.flatMap(Drag.init) {
            case .unit(let id)?:
                guard id != shipId else { return false }
                Task { await store.play(.board(unitId: id, carrierId: shipId)) }
            case let .goods(type, amount, from)?:
                guard from != shipId else { return false }
                Task {
                    await store.play(.load(goodsTypeId: type, amount: amount, carrierId: shipId,
                                           sourceId: from == "market" ? nil : from))
                }
            case nil:
                return false
            }
            return true
        }
    }
}

/// The role changes the unit menu offers (QuickActionMenu).
struct RoleMenu: View {
    @Environment(GameStore.self) private var store
    let unitId: String

    var body: some View {
        ForEach(store.roles[unitId] ?? [], id: \.roleId) { c in
            Button(c.text) { Task { await store.play(.equip(unitId: unitId, roleId: c.roleId, count: c.count)) } }
        }
    }
}

/// Java's destination dialog as a menu: home and the player's colonies
/// first, the others' settlements under "Other destinations".
struct DestinationMenu: View {
    let title: String
    let destinations: [DestinationChoice]
    let choose: (String) -> Void

    var body: some View {
        Menu(title) {
            ForEach(destinations.filter(\.isOwn), id: \.id) { d in Button(d.text) { choose(d.id) } }
            let others = destinations.filter { !$0.isOwn }
            if !others.isEmpty {
                Menu("Other destinations") {
                    ForEach(others, id: \.id) { d in Button(d.text) { choose(d.id) } }
                }
            }
        }
        .disabled(destinations.isEmpty)
    }
}

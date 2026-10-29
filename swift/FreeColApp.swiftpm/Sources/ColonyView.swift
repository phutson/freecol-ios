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

/// A colony, as Java's colony panel shows it: its tiles, buildings,
/// population, production, warehouse and what it builds.  Colonists
/// are dragged between tiles and buildings, and out of the colony.
struct ColonyView: View {
    @Environment(GameStore.self) private var store
    let colony: ColonyScreen
    let snapshot: GameSnapshot
    let images: MapImageStore
    @State private var editingQueue = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    population
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ColonyTilesView(colony: colony, snapshot: snapshot, images: images)
                            VStack(alignment: .leading, spacing: 16) { construction; netProduction }
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            ColonyTilesView(colony: colony, snapshot: snapshot, images: images)
                            construction
                            netProduction
                        }
                    }
                    buildings
                    outside
                    warehouse
                }
                .padding()
            }
            .navigationTitle(colony.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { store.closeColony() } }
            }
            .sheet(isPresented: $editingQueue) {
                BuildQueueView(colonyId: colony.id).environment(store)
            }
            .disabled(store.busy)
        }
    }

    /// Rebels and royalists, and the production bonus (PopulationPanel).
    private var population: some View {
        let royalists = colony.unitCount - colony.rebels
        let growth = colony.sizeChange == 0 ? "" : " (\(colony.sizeChange >= 10 ? "many" : String(colony.sizeChange)))"
        return HStack(spacing: 24) {
            Label("Rebels \(colony.rebels) · \(colony.sonsOfLiberty)%", systemImage: "flag")
            Label("Royalists \(royalists) · \(100 - colony.sonsOfLiberty)%", systemImage: "crown")
            Text("Population \(colony.unitCount)")
            Text("Bonus \(colony.bonus > 0 ? "+" : "")\(colony.bonus)\(growth)")
        }
        .font(.callout)
    }

    /// What is being built, the goods it needs, and the queue
    /// (ConstructionPanel).
    private var construction: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Building").font(.headline)
                Spacer()
                Button("Build queue") { editingQueue = true }.buttonStyle(.bordered)
            }
            if colony.building != nil {
                Text(colony.queueNames.first ?? "")
                ForEach(colony.needs, id: \.typeId) { n in
                    HStack {
                        GoodsIcon(typeId: n.typeId, images: images)
                        ProgressView(value: Double(min(n.held, n.needed)), total: Double(max(n.needed, 1)))
                        Text("\(n.held)/\(n.needed)\(n.net != 0 ? " (\(n.net > 0 ? "+" : "")\(n.net))" : "")")
                            .monospacedDigit().font(.caption)
                    }
                }
            } else {
                Text("Nothing").foregroundStyle(.secondary)
            }
            if colony.queueNames.count > 1 {
                Text("Then: " + colony.queueNames.dropFirst().joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 260, alignment: .leading)
    }

    /// The net production of what changes.
    private var netProduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Production").font(.headline)
            FlowLayout {
                ForEach(colony.net, id: \.typeId) { g in
                    HStack(spacing: 2) {
                        GoodsIcon(typeId: g.typeId, images: images)
                        Text("\(g.amount > 0 ? "+" : "")\(g.amount)").monospacedDigit()
                            .foregroundStyle(g.amount < 0 ? .red : .primary)
                    }
                }
            }
        }
    }

    /// The buildings, in the panel's order, each taking colonists.
    private var buildings: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Buildings").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 8)], spacing: 8) {
                ForEach(colony.buildings.filter { $0.id != nil }, id: \.id) { b in
                    BuildingCard(building: b, snapshot: snapshot, images: images)
                        .dropDestination(for: String.self) { items, _ in
                            guard case .unit(let unit)? = items.first.flatMap(Drag.init), let id = b.id else { return false }
                            Task { await store.play(.work(unitId: unit, workLocationId: id)) }
                            return true
                        }
                }
            }
        }
    }

    /// Colonists outside the colony, and ships in port with their
    /// cargo.
    private var outside: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Outside the colony").font(.headline)
            HStack {
                ForEach(colony.outsideUnitIds, id: \.self) { id in
                    UnitIcon(unitId: id, snapshot: snapshot, images: images)
                        .draggable(Drag.unit(id).text).contextMenu { RoleMenu(unitId: id) }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 60)
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .dropDestination(for: String.self) { items, _ in
                guard case .unit(let unit)? = items.first.flatMap(Drag.init) else { return false }
                Task { await store.play(.putOutsideColony(unitId: unit)) }
                return true
            }
            ForEach(colony.inPortUnitIds, id: \.self) { id in
                if let ship = snapshot.unit(id) {
                    ShipCard(shipId: id, goods: ship.goods, unitIds: ship.carriedUnitIds, snapshot: snapshot,
                             images: images) {
                        Button("Unload") { Task { await store.play(.unloadAll(carrierId: id)) } }
                    }
                }
            }
        }
    }

    /// The goods held, red over the warehouse's capacity.
    private var warehouse: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warehouse (holds \(colony.warehouseCapacity))").font(.headline)
            FlowLayout {
                ForEach(colony.warehouse, id: \.typeId) { g in
                    VStack(spacing: 2) {
                        GoodsIcon(typeId: g.typeId, images: images, size: 32)
                        Text("\(g.amount)").monospacedDigit().font(.caption)
                            .foregroundStyle(g.amount > colony.warehouseCapacity ? .red : .primary)
                    }
                    .frame(width: 44)
                    .draggable(Drag.goods(g.typeId, min(100, g.amount), from: colony.id).text)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard case let .goods(type, amount, from)? = items.first.flatMap(Drag.init), from != colony.id
                else { return false }
                Task { await store.play(.unload(goodsTypeId: type, amount: amount, carrierId: from)) }
                return true
            }
        }
    }
}

/// The colony's tiles, drawn from the map, with the colonists working
/// them and what they make; colonists dropped on a tile work it.
struct ColonyTilesView: View {
    @Environment(GameStore.self) private var store
    let colony: ColonyScreen
    let snapshot: GameSnapshot
    let images: MapImageStore

    static let scale: CGFloat = 0.9
    private var tw: CGFloat { CGFloat(MapScene.tileWidth) * Self.scale }
    private var th: CGFloat { CGFloat(MapScene.tileHeight) * Self.scale }

    /// A tile's top left, relative to the patch: the centre tile's at
    /// one tile across and down.
    private func origin(_ p: MapPosition) -> CGPoint {
        let c = MapScene.origin(colony.position.x, colony.position.y), o = MapScene.origin(p.x, p.y)
        return CGPoint(x: CGFloat(o.x - c.x) * Self.scale + tw, y: CGFloat(o.y - c.y) * Self.scale + th)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let c = MapScene.origin(colony.position.x, colony.position.y)
                context.scaleBy(x: Self.scale, y: Self.scale)
                context.translateBy(x: CGFloat(MapScene.tileWidth - c.x), y: CGFloat(MapScene.tileHeight - c.y))
                var options = MapOptions()
                options.displayColonyLabels = 0
                let draws = MapScene.plan(snapshot, images.lookup, options,
                                          columns: colony.position.x - 2 ..< colony.position.x + 3,
                                          rows: colony.position.y - 3 ..< colony.position.y + 4)
                    .filter { d in colony.tiles.contains { $0.position == MapPosition(x: d.x, y: d.y) } }
                    .filter { $0.pass != .units && $0.pass != .labels }
                MapView.render(draws, &context, images)
            }
            ForEach(colony.tiles, id: \.id) { t in
                tile(t).frame(width: tw, height: th)
                    .contentShape(Diamond())
                    .offset(x: origin(t.position).x, y: origin(t.position).y)
            }
        }
        .frame(width: tw * 3, height: th * 3, alignment: .topLeading)
    }

    private func tile(_ t: ColonyTileView) -> some View {
        VStack(spacing: 0) {
            if t.isCentre {
                HStack(spacing: 2) {
                    ForEach(t.centre, id: \.typeId) { g in
                        GoodsIcon(typeId: g.typeId, images: images, size: 16)
                        Text("\(g.amount)").font(.caption2).bold()
                    }
                }
                .padding(2).background(.thinMaterial, in: Capsule())
            }
            ForEach(Array(t.unitIds.enumerated()), id: \.element) { i, id in
                HStack(spacing: 0) {
                    UnitIcon(unitId: id, snapshot: snapshot, images: images, size: 34).draggable(Drag.unit(id).text).contextMenu { RoleMenu(unitId: id) }
                    if let made = t.made[i] {
                        GoodsIcon(typeId: made.typeId, images: images, size: 16)
                        Text("\(made.amount)").font(.caption2).bold()
                    }
                }
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard case .unit(let unit)? = items.first.flatMap(Drag.init), !t.isCentre else { return false }
            Task { await store.play(.work(unitId: unit, workLocationId: t.id)) }
            return true
        }
    }
}

/// A building: its picture, name, production and workers.
struct BuildingCard: View {
    let building: ColonyBuildingSlot
    let snapshot: GameSnapshot
    let images: MapImageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let type = building.typeId,
                   let picture = images.image(MapImage("image.buildingicon." + type)) {
                    Image(uiImage: picture).resizable().scaledToFit().frame(height: 40)
                }
                VStack(alignment: .leading) {
                    Text(building.name).font(.subheadline).bold().lineLimit(1)
                    if let o = building.output {
                        HStack(spacing: 2) {
                            GoodsIcon(typeId: o.typeId, images: images, size: 16)
                            Text(o.amount == o.maximum ? "\(o.amount)" : "\(o.amount)/\(o.maximum)")
                                .font(.caption).monospacedDigit()
                        }
                    }
                }
            }
            HStack(spacing: 2) {
                ForEach(building.unitIds, id: \.self) { id in
                    UnitIcon(unitId: id, snapshot: snapshot, images: images, size: 34).draggable(Drag.unit(id).text).contextMenu { RoleMenu(unitId: id) }
                }
            }
            .frame(minHeight: 34)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A unit's picture, as the map draws it.
struct UnitIcon: View {
    let unitId: String
    let snapshot: GameSnapshot
    let images: MapImageStore
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let unit = snapshot.unit(unitId) {
                let nation = unit.ownerId.flatMap { snapshot.player($0)?.nationResourceKey }
                if let picture = images.image(MapImage(MapScene.unitKey(unit, ownerNation: nation, images.lookup))) {
                    Image(uiImage: picture).resizable().scaledToFit()
                } else {
                    Image(systemName: "person.fill")
                }
            } else {
                Image(systemName: "questionmark")
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(snapshot.unit(unitId)?.label ?? "Unit")
    }
}

/// A goods type's icon.
struct GoodsIcon: View {
    let typeId: String
    let images: MapImageStore
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let picture = images.image(MapImage("image.icon." + typeId)) {
                Image(uiImage: picture).resizable().scaledToFit()
            } else {
                Text(typeId.split(separator: ".").last.map(String.init) ?? typeId).font(.caption2)
            }
        }
        .frame(width: size, height: size)
    }
}

struct Diamond: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}

/// The build queue: what is queued, to reorder or remove, and what can
/// be added, the locked with why (BuildQueuePanel).
struct BuildQueueView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let colonyId: String

    var body: some View {
        NavigationStack {
            if let colony = store.colony, colony.id == colonyId {
                List {
                    Section("Queue") {
                        if colony.queue.isEmpty { Text("Nothing").foregroundStyle(.secondary) }
                        ForEach(Array(colony.queueNames.enumerated()), id: \.offset) { _, name in
                            Text(name)
                        }
                        .onDelete { offsets in
                            var q = colony.queue
                            q.remove(atOffsets: offsets)
                            set(colony, q)
                        }
                        .onMove { from, to in
                            var q = colony.queue
                            q.move(fromOffsets: from, toOffset: to)
                            set(colony, q)
                        }
                    }
                    choices("Buildings", colony.buildingChoices, colony)
                    choices("Units", colony.unitChoices, colony)
                }
                .toolbar {
                    EditButton()
                    Button("Done") { dismiss() }
                }
                .navigationTitle("Build queue")
            }
        }
        .disabled(store.busy)
    }

    private func choices(_ title: String, _ list: [BuildChoice], _ colony: ColonyScreen) -> some View {
        Section(title) {
            ForEach(list, id: \.typeId) { c in
                Button { set(colony, colony.queue + [c.typeId]) } label: {
                    VStack(alignment: .leading) {
                        Text(c.name)
                        if let locked = c.locked { Text(locked).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .disabled(c.locked != nil)
            }
        }
    }

    private func set(_ colony: ColonyScreen, _ queue: [String]) {
        Task { await store.play(.setBuildQueue(colonyId: colony.id, queue: queue)) }
    }
}

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

/// The reports, as Java's report panels show them.
struct ReportsView: View {
    @Environment(GameStore.self) private var store
    let reports: GameStore.Reports
    let snapshot: GameSnapshot
    @State private var tab = 0
    @State private var produced: ProductionReport?
    @State private var chosen = Set<String>()

    static let titles = ["Congress", "Religion", "Military", "Naval", "Cargo", "Colonies", "Labour", "Trade",
                         "Production", "Requirements", "Education", "Natives", "Foreign affairs", "Exploration",
                         "History"]

    var body: some View {
        NavigationStack {
            List {
                switch tab {
                case 0: congress
                case 1: religion
                case 2: units(reports.military)
                case 3: units(reports.naval)
                case 4: units(reports.cargo)
                case 5: colonies
                case 6: labour
                case 7: trade
                case 8: production
                case 9: requirements
                case 10: education
                case 11: natives
                case 12: foreign
                case 13: exploration
                default: history
                }
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Report", selection: $tab) {
                        ForEach(Array(Self.titles.enumerated()), id: \.offset) { i, t in Text(t).tag(i) }
                    }
                    .pickerStyle(.menu)
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { store.closeReports() } }
            }
        }
    }

    @ViewBuilder private var congress: some View {
        let c = reports.congress
        Section("Recruiting") {
            if let name = c.currentName {
                Text(name).font(.headline)
                ProgressView(value: Double(min(c.liberty, c.cost)), total: Double(max(c.cost, 1))) {
                    Text("Liberty \(c.liberty) of \(c.cost)"
                         + c.production.map { " (+\($0.amount) a turn)" }.joined())
                }
            } else {
                Text("None")
            }
        }
        ForEach(Array(Set(c.fathers.map(\.typeName))).sorted(), id: \.self) { type in
            Section(type) {
                ForEach(c.fathers.filter { $0.typeName == type }, id: \.id) { f in
                    HStack {
                        Text(f.name)
                        Spacer()
                        Text(f.state == "available" ? "" : f.state == "recruiting" ? "Recruiting" : f.state)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var religion: some View {
        ForEach(reports.religion, id: \.typeId) { r in
            Section {
                ProgressView(value: Double(min(r.immigration, r.required)), total: Double(max(r.required, 1))) {
                    Text("Immigration \(r.immigration) of \(r.required) (+\(r.production) a turn)")
                }
                ForEach(r.colonies, id: \.colonyId) { c in
                    Text(snapshot.colony(c.colonyId)?.name ?? c.colonyId)
                }
            }
        }
    }

    @ViewBuilder private func units(_ report: UnitReport) -> some View {
        Section("Forces") {
            ForEach(Array(report.forces.enumerated()), id: \.offset) { _, f in
                Text("\(f.number) × \(f.typeName) (\(f.roleName))")
            }
        }
        if !report.ref.isEmpty {
            Section("Royal Expeditionary Force") {
                ForEach(Array(report.ref.enumerated()), id: \.offset) { _, f in
                    Text("\(f.number) × \(f.typeName) (\(f.roleName))")
                }
            }
        }
        ForEach(Array(report.places.enumerated()), id: \.offset) { _, p in
            Section(p.name) {
                if p.unitIds.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(p.unitIds, id: \.self) { Text(snapshot.unit($0)?.label ?? $0) }
            }
        }
    }

    private func goodsName(_ id: String) -> String { name(id) }

    private func row(_ left: String, _ right: String) -> some View {
        HStack(alignment: .top) {
            Text(left)
            Spacer()
            Text(right).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder private var colonies: some View {
        ForEach(reports.colonies, id: \.id) { c in
            Section(c.name) {
                if let b = c.building { row("Building", b) }
                row("Colonists", String(c.colonistIds.count))
                if !c.outsideIds.isEmpty { row("Outside", String(c.outsideIds.count)) }
                ForEach(c.goods, id: \.typeId) { g in
                    row(goodsName(g.typeId), "\(g.stock) (\(g.net >= 0 ? "+" : "")\(g.net), up to \(g.maximum))")
                }
                Text(c.buildings.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var labour: some View {
        ForEach(reports.labour.filter { $0.count > 0 }, id: \.typeId) { l in
            Section("\(l.typeName): \(l.count)") {
                ForEach(Array(l.places.enumerated()), id: \.offset) { _, p in row(p.name, String(p.count)) }
                if l.canTrain { Text("* Could train others").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    @ViewBuilder private var trade: some View {
        let t = reports.trade
        Section("Goods") {
            ForEach(Array(t.goodsTypeIds.enumerated()), id: \.offset) { i, id in
                row(goodsName(id), "sold \(t.sold[i]), \(t.afterTaxes[i]) gold, cargo \(t.cargo[i]), "
                    + "total \(t.total[i]) (\(t.delta[i] >= 0 ? "+" : "")\(t.delta[i]))")
            }
        }
        ForEach(t.colonies, id: \.id) { c in
            Section(c.name) {
                ForEach(Array(t.goodsTypeIds.enumerated()), id: \.offset) { i, id in
                    if c.stock[i] != 0 || c.production[i] != 0 {
                        VStack(alignment: .leading) {
                            row(goodsName(id), "\(c.stock[i]) (\(c.production[i] >= 0 ? "+" : "")\(c.production[i]))")
                            if let e = c.exports[i] { Text(e).font(.footnote).foregroundStyle(.secondary) }
                            if let w = c.warnings[i] { Text(w).font(.footnote).foregroundStyle(.red) }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var production: some View {
        Section("Goods to show") {
            ForEach(reports.productionGoods, id: \.id) { g in
                CheckRow(title: g.name, isOn: Binding(get: { chosen.contains(g.id) }, set: { on in
                    if on { chosen.insert(g.id) } else { chosen.remove(g.id) }
                    let ids = reports.productionGoods.map(\.id).filter { chosen.contains($0) }
                    Task { produced = await store.productionReport(ids) }
                }))
            }
        }
        if let p = produced {
            ForEach(p.colonies, id: \.id) { c in
                Section(c.name) {
                    ForEach(Array(zip(p.columns, c.cells).enumerated()), id: \.offset) { _, pair in
                        row(pair.0.goodsName, "\(pair.1.net)  " + pair.1.buildings.compactMap { $0 }.joined(separator: ", "))
                    }
                }
            }
        }
    }

    @ViewBuilder private var requirements: some View {
        ForEach(reports.requirements, id: \.colonyId) { c in
            Section(c.colonyName) {
                ForEach(Array(c.lines.enumerated()), id: \.offset) { _, l in Text(l) }
            }
        }
    }

    @ViewBuilder private var education: some View {
        ForEach(Array(reports.education.enumerated()), id: \.offset) { _, s in
            Section("\(s.colonyName): \(s.buildingName)") {
                ForEach(s.teacherIds, id: \.self) { row(snapshot.unit($0)?.label ?? $0, "Teacher") }
                ForEach(Array(s.students.enumerated()), id: \.offset) { _, st in
                    row(snapshot.unit(st.unitId)?.label ?? st.unitId, st.learning)
                }
            }
        }
    }

    @ViewBuilder private var natives: some View {
        ForEach(reports.natives, id: \.nation) { n in
            Section(n.nation) {
                row("Chieftain", n.chieftain)
                row(n.settlementType, n.numberOfSettlements)
                row("Tension", n.tension)
                ForEach(n.settlements, id: \.id) { s in
                    VStack(alignment: .leading) {
                        row(s.name, s.alarm)
                        Text(([s.skill, s.mostHated, s.mission].compactMap { $0 } + s.wanted.filter { !$0.isEmpty }).joined(separator: " · "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private var foreign: some View {
        ForEach(reports.foreign, id: \.country) { f in
            Section(f.country) {
                row("Stance", f.stance)
                row("Colonies", String(f.settlements))
                row("Units", String(f.units))
                row("Military strength", String(f.military))
                row("Naval strength", String(f.naval))
                row("Gold", String(f.gold))
                if let n = f.fathers { row("Founding fathers", String(n)) }
                if let n = f.tax { row("Tax", "\(n)%") }
                if let n = f.sonsOfLiberty { row("Sons of Liberty", "\(n)%") }
            }
        }
    }

    @ViewBuilder private var exploration: some View {
        ForEach(Array(reports.exploration.enumerated()), id: \.offset) { _, r in
            VStack(alignment: .leading) {
                row(r.name, "\(r.value)")
                Text("\(r.typeName), \(r.discoveredIn), \(r.discoveredBy)").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var history: some View {
        ForEach(Array(reports.history.enumerated()), id: \.offset) { _, h in
            VStack(alignment: .leading) {
                Text(h.turn).font(.footnote).foregroundStyle(.secondary)
                Text(h.text)
            }
        }
    }

    private func name(_ id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

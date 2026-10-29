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

/// The reports: the Continental Congress, religion, and the military
/// and naval forces, as Java's report panels show them.
struct ReportsView: View {
    @Environment(GameStore.self) private var store
    let reports: GameStore.Reports
    let snapshot: GameSnapshot
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            List {
                switch tab {
                case 0: congress
                case 1: religion
                case 2: units(reports.military)
                default: units(reports.naval)
                }
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Report", selection: $tab) {
                        Text("Congress").tag(0)
                        Text("Religion").tag(1)
                        Text("Military").tag(2)
                        Text("Naval").tag(3)
                    }
                    .pickerStyle(.segmented)
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

    private func name(_ id: String) -> String {
        let last = id.split(separator: ".").last.map(String.init) ?? id
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

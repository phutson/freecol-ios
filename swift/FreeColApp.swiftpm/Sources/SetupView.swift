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

import FreeColCore
import FreeColEngine
import FreeColServer
import SwiftUI

/// A new game's settings, as Java's new game and start game panels
/// offer them for one player against the computer: the player's name,
/// the rules and difficulty, the player's nation and its advantage
/// (PlayersTable), which other nations play, and the map generator and
/// game options; then the saved games.
struct SetupView: View {
    @Environment(GameStore.self) private var store
    @State private var name = "Player"
    @State private var rules = "freecol"
    @State private var difficulty = "model.difficulty.medium"
    @State private var saved = GameStore.savedGames
    @State private var importing = false
    @State private var importFailure: String?

    /// The choices on offer for the rules and difficulty, and what the
    /// player has chosen of them.
    @State private var setup: NewGameSetup?
    @State private var nationId = ""
    @State private var advantageId = ""
    @State private var plays: [String: Bool] = [:]
    @State private var values: [String: GameEngine.OptionValue] = [:]
    /// Settings saved under a name, one being loaded (its choices wait
    /// for the rules and difficulty to load), and one being named.
    @State private var savedSettings = SetupSettings.savedNames
    @State private var loading: SetupSettings?
    @State private var naming = false
    @State private var settingsName = ""
    /// Whether the next change of nation keeps the advantage set with it.
    @State private var keepAdvantage = false

    static let difficulties = [("model.difficulty.veryEasy", "Very easy"), ("model.difficulty.easy", "Easy"),
                               ("model.difficulty.medium", "Medium"), ("model.difficulty.hard", "Hard"),
                               ("model.difficulty.veryHard", "Very hard")]

    var body: some View {
        NavigationStack {
            Form {
                Section("New game") {
                    TextField("Your name", text: $name)
                    Picker("Rules", selection: $rules) {
                        Text("FreeCol").tag("freecol")
                        Text("Classic").tag("classic")
                    }
                    Picker("Difficulty", selection: $difficulty) {
                        ForEach(Self.difficulties, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    if let setup {
                        Picker("Your nation", selection: $nationId) {
                            ForEach(setup.nations.filter(\.isPlayable)) { Text($0.name).tag($0.id) }
                        }
                        Picker("National advantage", selection: $advantageId) {
                            ForEach(setup.advantages) { Text($0.name).tag($0.id) }
                        }
                    }
                    Button("Start") { Task { await start() } }
                        .disabled(name.isEmpty || setup == nil)
                }
                Section("Settings") {
                    ForEach(savedSettings, id: \.self) { name in
                        Button(name) { load(name) }
                            .contextMenu {
                                Button("Delete", role: .destructive) { deleteSettings(name) }
                            }
                    }
                    .onDelete { offsets in
                        for i in offsets { deleteSettings(savedSettings[i]) }
                    }
                    Button("Save these settings…") { settingsName = ""; naming = true }
                        .disabled(setup == nil)
                }
                if let setup {
                    Section("Options") {
                        NavigationLink("Other nations") { NationsPage(setup: setup, nationId: nationId, plays: $plays) }
                        ForEach(setup.groups) { group in
                            NavigationLink(group.name) { OptionsPage(group: group, values: $values) }
                        }
                    }
                }
                Section("Saved games") {
                    ForEach(saved, id: \.self) { url in
                        HStack {
                            Button(url.deletingPathExtension().lastPathComponent) { Task { await store.load(url) } }
                                .buttonStyle(.borderless)
                            Spacer()
                            // To Files, iCloud Drive or another device.
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Share \(url.deletingPathExtension().lastPathComponent)")
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { try? FileManager.default.removeItem(at: saved[i]) }
                        saved = GameStore.savedGames
                    }
                    Button("Import from Files…") { importing = true }
                }
                Section {
                    Button("Play the sample game") { Task { await store.loadSample() } }
                    Button("Sound…") { store.soundSettingsShown = true }
                }
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: rules + " " + difficulty) {
            setup = nil
            setup = await GameStore.newGameSetup(rules: rules, difficulty: difficulty)
            // Settings being loaded, or Java's defaults: the first nation
            // free to take, its own advantage, the usual nations
            // playing, the rules' options.
            if let s = loading, s.rules == rules, s.difficulty == difficulty {
                loading = nil
                keepAdvantage = s.nationId != nationId
                nationId = s.nationId
                advantageId = s.advantageId
                plays = s.plays
                values = s.optionValues
            } else {
                let first = setup?.nations.first { $0.isPlayable && $0.playsByDefault }
                nationId = first?.id ?? ""
                advantageId = first?.nationTypeId ?? ""
                plays = [:]
                values = [:]
            }
        }
        .onChange(of: nationId) { _, id in
            // A nation chosen comes with its own advantage (PlayersTable);
            // not one set with the rest of saved settings.
            if keepAdvantage {
                keepAdvantage = false
                return
            }
            guard let n = setup?.nations.first(where: { $0.id == id }) else { return }
            advantageId = n.nationTypeId
        }
        .alert("Save these settings", isPresented: $naming) {
            TextField("Name", text: $settingsName)
            Button("Save") { saveSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The rules, difficulty, nation, advantage, other nations and options.")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                try GameStore.importGame(try result.get())
                saved = GameStore.savedGames
            } catch {
                importFailure = error.localizedDescription
            }
        }
        .alert(importFailure ?? "", isPresented: Binding(get: { importFailure != nil }, set: { if !$0 { importFailure = nil } })) {
            Button("OK") {}
        }
    }

    private var currentSettings: SetupSettings {
        SetupSettings(rules: rules, difficulty: difficulty, nationId: nationId, advantageId: advantageId,
                      plays: plays, optionValues: values)
    }

    private func saveSettings() {
        let name = settingsName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        currentSettings.save(as: name)
        savedSettings = SetupSettings.savedNames
    }

    private func load(_ name: String) {
        guard let s = SetupSettings.load(name) else { return }
        if s.rules == rules && s.difficulty == difficulty {
            // The choices on offer stay; only the player's change.
            keepAdvantage = s.nationId != nationId
            nationId = s.nationId
            advantageId = s.advantageId
            plays = s.plays
            values = s.optionValues
        } else {
            loading = s
            rules = s.rules
            difficulty = s.difficulty
        }
    }

    private func deleteSettings(_ name: String) {
        SetupSettings.delete(name)
        savedSettings = SetupSettings.savedNames
    }

    private func start() async {
        guard let setup else { return }
        var states: [String: NationOptions.NationState] = [:]
        for n in setup.nations where n.id != nationId {
            guard let on = plays[n.id], on != n.playsByDefault else { continue }
            states[n.id] = on ? (n.isPlayable ? .available : .aiOnly) : .notAvailable
        }
        let choices = NewGameChoices(nationId: nationId, nationTypeId: advantageId, nationStates: states)
        await store.newGame(playerName: name, rules: rules, difficulty: difficulty, options: values, choices: choices)
    }
}

/// Which other nations play (the availability column of Java's table).
struct NationsPage: View {
    let setup: NewGameSetup
    let nationId: String
    @Binding var plays: [String: Bool]

    var body: some View {
        Form {
            Section("European nations") {
                ForEach(setup.nations.filter { $0.isEuropean && $0.id != nationId }) { row($0) }
            }
            Section("Native nations") {
                ForEach(setup.nations.filter { !$0.isEuropean }) { row($0) }
            }
        }
        .navigationTitle("Other nations")
    }

    private func row(_ n: NewGameSetup.NationChoice) -> some View {
        CheckRow(title: n.name, isOn: Binding(get: { plays[n.id] ?? n.playsByDefault }, set: { plays[n.id] = $0 }))
    }
}

/// A group of options, as Java's option dialogs show it: each option
/// with its control, and the groups within it.
struct OptionsPage: View {
    let group: NewGameSetup.Group
    @Binding var values: [String: GameEngine.OptionValue]

    var body: some View {
        Form {
            if !group.options.isEmpty {
                Section { ForEach(group.options) { OptionRow(option: $0, values: $values) } }
            }
            ForEach(group.groups) { sub in
                Section(sub.name) {
                    ForEach(sub.options) { OptionRow(option: $0, values: $values) }
                    ForEach(sub.groups) { g in
                        NavigationLink(g.name) { OptionsPage(group: g, values: $values) }
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .toolbar {
            Button("Defaults") {
                for o in Self.all(group) { values[o.id] = nil }
            }
        }
    }

    static func all(_ g: NewGameSetup.Group) -> [NewGameSetup.Option] {
        g.options + g.groups.flatMap(all)
    }
}

/// One option's control: a check, a choice, or a number.
struct OptionRow: View {
    let option: NewGameSetup.Option
    @Binding var values: [String: GameEngine.OptionValue]

    private var value: GameEngine.OptionValue { values[option.id] ?? option.value }

    @State private var explaining = false

    var body: some View {
        HStack {
            // Borderless, so a tap on the row is not also a tap on the
            // info button beside it.
            control
                .buttonStyle(.borderless)
                .disabled(!option.isEditable)
                .help(option.description)
                .accessibilityHint(option.description)
            // What the option does, as Java's tooltip says, for a click
            // or a tap: an iPad has no hover.
            if !option.description.isEmpty {
                Button { explaining = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.borderless)
                    .help(option.description)
                    .accessibilityLabel("About \(option.name)")
                    .popover(isPresented: $explaining) {
                        Text(option.description)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(idealWidth: 320)
                            .padding()
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
    }

    @ViewBuilder private var control: some View {
        switch option.kind {
        case .boolean:
            CheckRow(title: option.name, isOn: Binding(get: {
                if case .boolean(let b) = value { b } else { false }
            }, set: { set(.boolean($0)) }))
        case .select(let items):
            Picker(option.name, selection: Binding(get: { integer }, set: { set(.integer($0)) })) {
                ForEach(items, id: \.value) { Text($0.label).tag($0.value) }
            }
        case .integer(let minimum, let maximum):
            LabeledContent(option.name) {
                HStack {
                    TextField(option.name, value: Binding(get: { integer }, set: {
                        set(.integer(min(max($0, minimum), maximum)))
                    }), format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
                    .labelsHidden()
                    Stepper(option.name, value: Binding(get: { integer }, set: { set(.integer($0)) }),
                            in: minimum...maximum)
                        .labelsHidden()
                }
            }
        }
    }

    private var integer: Int {
        if case .integer(let i) = value { i } else { 0 }
    }

    private func set(_ v: GameEngine.OptionValue) {
        values[option.id] = v == option.value ? nil : v
    }
}

/// The setup screen's choices saved under a name, as a JSON file in the
/// app's own support folder (Java's option dialogs save to a file).
struct SetupSettings: Codable, Equatable {
    var rules: String
    var difficulty: String
    var nationId: String
    var advantageId: String
    var plays: [String: Bool]
    var integers: [String: Int]
    var booleans: [String: Bool]

    init(rules: String, difficulty: String, nationId: String, advantageId: String, plays: [String: Bool],
         optionValues: [String: GameEngine.OptionValue]) {
        self.rules = rules
        self.difficulty = difficulty
        self.nationId = nationId
        self.advantageId = advantageId
        self.plays = plays
        var integers: [String: Int] = [:], booleans: [String: Bool] = [:]
        for (id, value) in optionValues {
            switch value {
            case .integer(let i): integers[id] = i
            case .boolean(let b): booleans[id] = b
            }
        }
        self.integers = integers
        self.booleans = booleans
    }

    var optionValues: [String: GameEngine.OptionValue] {
        integers.mapValues { .integer($0) }.merging(booleans.mapValues { .boolean($0) }) { a, _ in a }
    }

    static var folder: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Settings", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func url(_ name: String) -> URL {
        // A name is a file name: no folders in it.
        folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-")).appendingPathExtension("json")
    }

    /// The names of the saved settings, in order.
    static var savedNames: [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func save(as name: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) { try? data.write(to: Self.url(name), options: .atomic) }
    }

    static func load(_ name: String) -> SetupSettings? {
        (try? Data(contentsOf: url(name))).flatMap { try? JSONDecoder().decode(SetupSettings.self, from: $0) }
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }
}

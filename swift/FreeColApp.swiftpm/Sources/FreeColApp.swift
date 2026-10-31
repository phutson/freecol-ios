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

import SwiftUI

@main
struct FreeColApp: App {
    @State private var store = GameStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, store.hasGame else { return }
            // The system allows a little time to finish, if asked.
            let application = UIApplication.shared
            var task = UIBackgroundTaskIdentifier.invalid
            task = application.beginBackgroundTask { application.endBackgroundTask(task) }
            Task {
                await store.autosave()
                application.endBackgroundTask(task)
            }
        }
    }
}

/// The setup screen until a game is started, then the map and the
/// controls for playing on it.
struct ContentView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if store.hasGame, let snapshot = store.snapshot, let images = store.images {
                PlayView(snapshot: snapshot, images: images)
            } else if let failure = store.failure {
                Text(failure).foregroundStyle(.white).padding()
            } else if store.busy {
                ProgressView().tint(.white)
            } else {
                SetupView()
            }
        }
    }
}

/// A new game's settings (Java's new game panel, for one player against
/// the computer): the player's name, the rules and the difficulty.
struct SetupView: View {
    @Environment(GameStore.self) private var store
    @State private var name = "Player"
    @State private var rules = "freecol"
    @State private var difficulty = "model.difficulty.medium"
    @State private var saved = GameStore.savedGames
    @State private var importing = false
    @State private var importFailure: String?

    static let difficulties = [("model.difficulty.veryEasy", "Very easy"), ("model.difficulty.easy", "Easy"),
                               ("model.difficulty.medium", "Medium"), ("model.difficulty.hard", "Hard"),
                               ("model.difficulty.veryHard", "Very hard")]

    var body: some View {
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
                Button("Start") {
                    Task { await store.newGame(playerName: name, rules: rules, difficulty: difficulty) }
                }
                .disabled(name.isEmpty)
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
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                try GameStore.importGame(try result.get())
                saved = GameStore.savedGames
            } catch {
                importFailure = "\(error)"
            }
        }
        .alert(importFailure ?? "", isPresented: Binding(get: { importFailure != nil }, set: { if !$0 { importFailure = nil } })) {
            Button("OK") {}
        }
        .frame(maxWidth: 500)
        .scrollContentBackground(.hidden)
    }
}

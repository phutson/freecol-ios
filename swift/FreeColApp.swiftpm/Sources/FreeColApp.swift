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
                .onAppear { store.startAudio() }
                .background(MinimumWindowSize(size: CGSize(width: 900, height: 640)))
        }
        .commands { GameCommands(store: store) }
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
        // From the menus, on the setup screen as in a game: the music
        // begins at the setup screen.
        .sheet(isPresented: Binding(get: { store.soundSettingsShown }, set: { store.soundSettingsShown = $0 })) {
            SoundSettings().environment(store)
        }
    }
}


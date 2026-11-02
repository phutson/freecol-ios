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

import AVFoundation
import FreeColEngine
import FreeColIO
import FreeColResources
import Foundation

/// The game's sounds and music (SoundController and SoundPlayer), played
/// from the app's converted copies: one effect at a time and one piece of
/// music at a time, each new one stopping the last, and when the music
/// runs out, the default playlist, shuffled.
@MainActor
final class GameAudio: NSObject, AVAudioPlayerDelegate {

    static let musicVolumeKey = "musicVolume"
    static let effectsVolumeKey = "soundEffectsVolume"

    private let manager = ResourceManager()
    private let folder: URL
    private var effect: AVAudioPlayer?
    private var music: AVAudioPlayer?
    private var playlist: [URL] = []

    init?(dataDirectory data: URL) {
        guard let folder = Bundle.main.url(forResource: "audio", withExtension: nil) else { return nil }
        self.folder = folder
        super.init()
        do {
            if let base = try FreeColDataFile(directory: data.appendingPathComponent("base"))
                .resourceMapping(languageId: "en_US") {
                manager.setBase(base)
            }
            manager.setTc(try FreeColTcFile.resourceMapping(dataDirectory: data, id: "default", languageId: "en_US"))
        } catch {
            return nil
        }
        // Ambient: other apps' audio goes on, and the mute switch counts.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    /// Volumes run from 0 to 100, default 100, as in Java's options.
    private func volume(_ key: String) -> Float {
        let stored = UserDefaults.standard.object(forKey: key) as? Double ?? 100
        return Float(stored / 100)
    }

    func volumesChanged() {
        effect?.volume = volume(Self.effectsVolumeKey)
        music?.volume = volume(Self.musicVolumeKey)
    }

    private func url(_ path: String) -> URL { folder.appendingPathComponent(path) }

    /// Play a sound by its key; one that does not exist plays nothing.
    func play(_ key: String) {
        guard let path = manager.convertedSoundFiles(key).randomElement() else { return }
        if manager.isMusic(key) {
            startMusic(url(path))
        } else if let player = try? AVAudioPlayer(contentsOf: url(path)) {
            player.volume = volume(Self.effectsVolumeKey)
            player.play()
            effect = player
        }
    }

    private func startMusic(_ url: URL) {
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.delegate = self
        player.volume = volume(Self.musicVolumeKey)
        player.play()
        music = player
    }

    private func nextMusic() {
        if playlist.isEmpty {
            playlist = manager.convertedSoundFiles("sound.music.playlist.default").map(url).shuffled()
        }
        if let next = playlist.popLast() { startMusic(next) }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.music === player { self.nextMusic() }
        }
    }
}

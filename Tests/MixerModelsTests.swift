// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreAudio
import Foundation

enum MixerModelsTests {
    static func run(_ suite: TestSuite) {
        // 1. MixerOutputDevice
        let device1 = MixerOutputDevice(
            id: "dev-1",
            uid: "BuiltInSpeakerDevice",
            name: "MacBook Pro Speakers",
            isDefault: true,
            isHeadphones: false,
            canBeDefaultOutput: true,
            canBeDefaultSystemOutput: true,
            priorityTier: .builtIn,
            audioObjectID: 42
        )

        let device2 = MixerOutputDevice(
            id: "dev-1",
            uid: "BuiltInSpeakerDevice",
            name: "MacBook Pro Speakers",
            isDefault: true,
            isHeadphones: false,
            canBeDefaultOutput: true,
            canBeDefaultSystemOutput: true,
            priorityTier: .builtIn,
            audioObjectID: 42
        )

        let headphones = MixerOutputDevice(
            id: "dev-2",
            uid: "HeadphonesDevice",
            name: "External Headphones",
            isDefault: false,
            isHeadphones: true,
            canBeDefaultOutput: true,
            canBeDefaultSystemOutput: true,
            priorityTier: .hardware,
            audioObjectID: 43
        )

        suite.expect(device1 == device2, "MixerOutputDevice implements value equality")
        suite.expect(device1 != headphones, "Different devices are not equal")
        suite.expect(device1.id == "dev-1", "MixerOutputDevice identifies by id")
        suite.expect(device1.audioObjectID == 42, "MixerOutputDevice preserves CoreAudio AudioObjectID")
        suite.expect(headphones.isHeadphones, "MixerOutputDevice reflects headphone state")
        suite.expect(headphones.systemImageName == "headphones", "Headphones device uses headphones SF Symbol")
        suite.expect(device1.systemImageName == "speaker.wave.2.fill", "Speaker device uses speaker SF Symbol")

        // 2. MixerApp
        var app = MixerApp(
            id: "app-spotify",
            persistenceID: "com.spotify.client",
            ownerPid: 1234,
            name: "Spotify",
            audioObjects: [101, 102],
            isPlaying: true,
            isBypassed: false,
            supportsVolumeOverride: false,
            universalOutputRouteUID: nil,
            selectedOutputDeviceUID: nil,
            effectiveOutputDeviceUID: "BuiltInSpeakerDevice",
            outputDeviceUnavailable: false,
            volume: 0.8
        )

        suite.expect(app.id == "app-spotify", "MixerApp id matches")
        suite.expect(app.persistenceID == "com.spotify.client", "MixerApp persistence ID matches")
        suite.expect(app.isPlaying, "MixerApp indicates playback")
        suite.expect(app.volume == 0.8, "MixerApp preserves volume")
        suite.expect(app.identity.rowID == "app-spotify" && app.identity.persistenceID == "com.spotify.client",
                     "MixerApp identity correctly derives from row and persistence IDs")

        app.volume = 0.5
        app.isBypassed = true
        suite.expect(app.volume == 0.5, "MixerApp volume updates mutably")
        suite.expect(app.isBypassed, "MixerApp bypass flag updates")

        // 3. MixerHiddenApp
        let hidden = MixerHiddenApp(id: "com.apple.quicktimeplayerx", name: "QuickTime Player")
        suite.expect(hidden.id == "com.apple.quicktimeplayerx", "MixerHiddenApp id matches")
        suite.expect(hidden.name == "QuickTime Player", "MixerHiddenApp name matches")

        // 4. Mixer Service Presets & Mute Methods
        let mixerSource = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift", encoding: .utf8)) ?? ""
        suite.expect(mixerSource.contains("func toggleMuteFrontmostApp()"), "AppVolumeMixer supports muting frontmost app")
        suite.expect(mixerSource.contains("func setPresetVolume("), "AppVolumeMixer supports setting preset volumes")
        suite.expect(mixerSource.contains("func toggleMute("), "AppVolumeMixer supports toggling mute")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchSplitIslandTests {
    static func run(_ suite: TestSuite) {
        func source(_ path: String) -> String {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }

        let defaultsSource = source("Sources/Vorssaint/Core/Defaults.swift")
        suite.expect(defaultsSource.contains("static let notchSplitCapsuleEnabled = \"notchSplitCapsuleEnabled\""),
                     "Defaults key for split capsule is defined")
        suite.expect(defaultsSource.contains("DefaultsKey.notchSplitCapsuleEnabled: true"),
                     "Split capsule is enabled by default")

        let settingsSource = source("Sources/Vorssaint/UI/Settings/NotchSettings.swift")
        suite.expect(settingsSource.contains("DefaultsKey.notchSplitCapsuleEnabled"),
                     "Notch settings includes toggle for split capsule")

        let capsuleViewSource = source("Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift")
        suite.expect(!capsuleViewSource.isEmpty, "NotchCapsuleViews exists")
        suite.expect(capsuleViewSource.contains("activeCompanion: NotchCompactActivity?"),
                     "Music strip determines active companion activity")
        suite.expect(capsuleViewSource.contains("splitCapsuleEnabled && NotchMusicService.shared.playback?.isPlaying == true"),
                     "Concurrent activities trigger split pod in agent, timer and download strips")
        suite.expect(capsuleViewSource.contains("NotchLiveEqualizerBars(isPlaying: true"),
                     "Split capsule pod renders live music equalizer when music runs alongside active strip")
    }
}

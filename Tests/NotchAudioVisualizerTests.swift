// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchAudioVisualizerTests {
    static func run(_ suite: TestSuite) {
        func source(_ path: String) -> String {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }

        let badgeSource = source("Sources/Vorssaint/UI/Notch/NotchAudioVisualizerView.swift")
        suite.expect(!badgeSource.isEmpty, "NotchAudioVisualizerView source exists")
        suite.expect(badgeSource.contains("struct NotchExpandedAudioBadge: View"),
                     "NotchExpandedAudioBadge is defined as a SwiftUI View")
        suite.expect(badgeSource.contains("NotchLiveEqualizerBars(isPlaying: true"),
                     "NotchExpandedAudioBadge integrates live animated equalizer bars")
        suite.expect(badgeSource.contains("music.playback?.isPlaying == true"),
                     "NotchExpandedAudioBadge checks music playback state")
        suite.expect(badgeSource.contains("mixer.apps.first"),
                     "NotchExpandedAudioBadge observes active mixer applications")

        let notchViewSource = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        suite.expect(notchViewSource.contains("NotchExpandedAudioBadge()"),
                     "NotchView includes audio visualizer badge in expanded header row")
    }
}

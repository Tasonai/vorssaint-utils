// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Visualizer badge for active audio in the expanded Dynamic Island header row.
///
/// Displays live animated equalizer bars and current audio source (music or playing application)
/// with 1-click controls.
struct NotchExpandedAudioBadge: View {
    @ObservedObject private var notch = NotchService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var mixer = AppVolumeMixer.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activePlayingApp: MixerApp? {
        mixer.apps.first { $0.isPlaying && !$0.isBypassed }
    }

    private var isMusicPlaying: Bool {
        music.playback?.isPlaying == true
    }

    private var isRedundantOnCurrentPage: Bool {
        notch.showingSections || notch.selected == .controls || notch.selected == .music || notch.selected == .mixer
    }

    var body: some View {
        if !isRedundantOnCurrentPage {
            if isMusicPlaying {
                let trackTitle = music.playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying
                Button {
                    notch.select(.music)
                } label: {
                    NotchLiveEqualizerBars(isPlaying: true, bars: 4, barWidth: 2, height: 10, tint: .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help(trackTitle)
                .accessibilityLabel(trackTitle)
                .transition(.opacity.combined(with: .scale))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isMusicPlaying)
            } else if let playingApp = activePlayingApp {
                Button {
                    notch.select(.mixer)
                } label: {
                    NotchLiveEqualizerBars(isPlaying: true, bars: 4, barWidth: 2, height: 10, tint: .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(.white.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .help("\(playingApp.name) — \(l10n.s.mixerSection)")
                .accessibilityLabel("\(playingApp.name) — \(l10n.s.mixerSection)")
                .transition(.opacity.combined(with: .scale))
                .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: playingApp.id)
            }
        }
    }
}

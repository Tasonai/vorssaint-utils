// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Visualizer badge for active audio in the expanded Dynamic Island header row.
///
/// Displays live animated equalizer bars and current audio source (music or playing application)
/// with 1-click controls.
struct NotchExpandedAudioBadge: View {
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

    var body: some View {
        if isMusicPlaying {
            let trackTitle = music.playback?.track.title ?? FeatureStrings.radialMenu(l10n.language).mediaNowPlaying
            Button {
                _ = NotchService.shared.toggleMusicStripSong()
            } label: {
                HStack(spacing: 5) {
                    NotchLiveEqualizerBars(isPlaying: true, bars: 4, barWidth: 2, height: 10, tint: .white)
                    Text(trackTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: 120, alignment: .leading)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(trackTitle)
            .transition(.opacity.combined(with: .scale))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isMusicPlaying)
        } else if let playingApp = activePlayingApp {
            Button {
                mixer.toggleMute(playingApp)
            } label: {
                HStack(spacing: 5) {
                    NotchLiveEqualizerBars(isPlaying: true, bars: 4, barWidth: 2, height: 10, tint: .white)
                    Text(playingApp.name)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                        .frame(maxWidth: 100, alignment: .leading)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("\(playingApp.name): \(l10n.s.actionMute)")
            .transition(.opacity.combined(with: .scale))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: playingApp.id)
        }
    }
}

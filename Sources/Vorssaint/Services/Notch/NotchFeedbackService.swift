// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AudioToolbox
import Foundation

/// Provides subtle tactile Force Touch haptic feedback and acoustic micro-clicks
/// for Dynamic Island interactions.
final class NotchFeedbackService {
    static let shared = NotchFeedbackService()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isHapticsEnabled: Bool {
        let master = defaults.object(forKey: DefaultsKey.notchHapticFeedback) as? Bool ?? true
        guard master else { return false }
        return defaults.object(forKey: DefaultsKey.notchHapticsEnabled) as? Bool ?? true
    }

    var isAcousticsEnabled: Bool {
        defaults.object(forKey: DefaultsKey.notchAcousticsEnabled) as? Bool ?? true
    }

    /// Emits a soft haptic tick and micro-sound when the Island expands from the notch.
    func performOpen() {
        if isHapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if isAcousticsEnabled {
            playAcoustic(1104) // subtle system click
        }
    }

    /// Emits a soft haptic snap when the Island returns to its compact capsule.
    func performClose() {
        if isHapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    /// Emits a delicate level-change feedback when switching sections or hovering controls.
    func performSelection() {
        if isHapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if isAcousticsEnabled {
            playAcoustic(1105)
        }
    }

    private func playAcoustic(_ soundID: SystemSoundID) {
        // Runs asynchronously and never blocks UI
        DispatchQueue.global(qos: .userInitiated).async {
            AudioServicesPlaySystemSound(soundID)
        }
    }
}

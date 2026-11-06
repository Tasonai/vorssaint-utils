// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchPrivacyTests {
    static func run(_ suite: TestSuite) {
        func source(_ path: String) -> String {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }

        let monitorSource = source("Sources/Vorssaint/Services/Notch/CameraMicrophonePrivacyMonitor.swift")
        suite.expect(!monitorSource.isEmpty, "CameraMicrophonePrivacyMonitor source file exists")
        suite.expect(monitorSource.contains("kAudioDevicePropertyDeviceIsRunningSomewhere"),
                     "CameraMicrophonePrivacyMonitor monitors CoreAudio running state")
        suite.expect(monitorSource.contains("AVCaptureDevice.DiscoverySession"),
                     "CameraMicrophonePrivacyMonitor monitors AVCapture devices")
        suite.expect(monitorSource.contains("MicMuteSupport.isOwnDevice"),
                     "CameraMicrophonePrivacyMonitor filters out Vorssaint aggregate audio devices")

        let privacyViewSource = source("Sources/Vorssaint/UI/Notch/NotchPrivacyView.swift")
        suite.expect(!privacyViewSource.isEmpty, "NotchPrivacyView source file exists")
        suite.expect(privacyViewSource.contains("struct NotchPrivacyDots"),
                     "NotchPrivacyDots view is defined")
        suite.expect(privacyViewSource.contains("struct NotchPrivacyHeaderBadge"),
                     "NotchPrivacyHeaderBadge view is defined")
        suite.expect(privacyViewSource.contains("monitor.toggleMicrophoneMute()"),
                     "Privacy view provides 1-click microphone mute control")

        let notchViewSource = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        suite.expect(notchViewSource.contains("NotchPrivacyDots()"),
                     "NotchView includes privacy dots in resting strip")
        suite.expect(notchViewSource.contains("NotchPrivacyHeaderBadge()"),
                     "NotchView includes privacy header badge when expanded")

        let capsuleViewSource = source("Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift")
        suite.expect(capsuleViewSource.contains("NotchPrivacyDots()"),
                     "NotchCapsuleViews includes privacy dots in floating capsule")

        // Own virtual devices must never trigger false microphone alerts
        suite.expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Mixer"),
                     "Vorssaint Mixer is recognized as own device")
        suite.expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Island Levels"),
                     "Vorssaint Island Levels is recognized as own device")
        suite.expect(!MicMuteSupport.isOwnDevice(name: "MacBook Pro Microphone"),
                     "Hardware microphone is recognized as external device")
    }
}

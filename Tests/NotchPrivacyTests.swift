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

        let evaluateBody = monitorSource.components(separatedBy: "    private func evaluate() {").dropFirst().first?
            .components(separatedBy: "        DispatchQueue.main.async").first ?? ""
        suite.expect(!evaluateBody.contains("CameraPreviewService.shared")
                         && !evaluateBody.contains("MicMuteService.shared"),
                     "CameraMicrophonePrivacyMonitor never reads main-thread @Published singletons on halQueue")
        suite.expect(!monitorSource.contains("withTimeInterval: 1.5"),
                     "CameraMicrophonePrivacyMonitor eliminates continuous 1.5s background polling")
        suite.expect(monitorSource.contains("CMIOObjectAddPropertyListenerBlock")
                         && monitorSource.contains("kCMIODevicePropertyDeviceIsRunningSomewhere"),
                     "CameraMicrophonePrivacyMonitor listens to CoreMediaIO camera running-state callbacks")
        suite.expect(monitorSource.contains("screensDidSleepNotification")
                         && monitorSource.contains("screensDidWakeNotification")
                         && monitorSource.contains("activeReconcileTolerance"),
                     "CameraMicrophonePrivacyMonitor pauses reconciliation during display sleep and configures timer tolerance")

        NotchPrivacyMuteContract.run(suite)
    }
}

enum NotchPrivacyMuteContract {
    final class MicMuteService {
        static let shared = MicMuteService()
        var isMuted = false
        var toggles = 0
        func toggle() { toggles += 1 }
    }

    class Fixture {
        var isMicrophoneMuted = false
        var pendingMuteTarget: (muted: Bool, expiresAt: TimeInterval)?
        var muteReconcileWork: DispatchWorkItem?
    }

    static func run(_ suite: TestSuite) {
        defer {
            MicMuteService.shared.isMuted = false
            MicMuteService.shared.toggles = 0
        }
        let host = Host()
        host.toggleMicrophoneMute()
        suite.expect(host.isMicrophoneMuted == true && MicMuteService.shared.toggles == 1,
                     "toggleMicrophoneMute immediately reflects target mute state while async HAL sweep starts")

        // Simulate a periodic HAL poll arriving before MicMuteService's async sweep finishes:
        host.reconcileMutedStateOnMain(false, fromPublisher: false)
        suite.expect(host.isMicrophoneMuted == true,
                     "stale pre-toggle poll read does not overwrite in-flight mute toggle")

        // Simulate MicMuteService.$isMuted publishing completion of the sweep:
        MicMuteService.shared.isMuted = true
        host.reconcileMutedStateOnMain(true, fromPublisher: true)
        suite.expect(host.isMicrophoneMuted == true && host.pendingMuteTarget == nil,
                     "publisher emission clears pending target and keeps settled mute state")

        // Toggling again unmutes cleanly without inversion:
        host.toggleMicrophoneMute()
        suite.expect(host.isMicrophoneMuted == false && MicMuteService.shared.toggles == 2,
                     "second toggleMicrophoneMute transitions cleanly back to unmuted")
        host.muteReconcileWork?.cancel()
    }
}

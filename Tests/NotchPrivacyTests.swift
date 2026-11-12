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
        runWave4UXContractChecks(suite, source: source)
    }

    private static func runWave4UXContractChecks(_ suite: TestSuite, source: (String) -> String) {
        let privacyViewSource = source("Sources/Vorssaint/UI/Notch/NotchPrivacyView.swift")
        suite.expect(privacyViewSource.range(of: "\\p{Cyrillic}", options: .regularExpression) == nil
                         && privacyViewSource.contains("FeatureStrings.notch(l10n.language)"),
                     "NotchPrivacyView uses localized FeatureStrings.notch tokens with zero hardcoded Cyrillic strings")
        suite.expect(!privacyViewSource.contains(".transition(.scale.combined")
                         && privacyViewSource.contains(".scale(scale: 0.95).combined(with: .opacity)")
                         && privacyViewSource.contains("accessibilityReduceMotion"),
                     "NotchPrivacyView avoids scale(0) transitions and respects Reduce Motion")

        for language in AppLanguage.allCases {
            let notch = FeatureStrings.notch(language)
            suite.expect(!notch.privacyCameraFallback.isEmpty
                             && !notch.privacyCameraActive.isEmpty
                             && notch.privacyCameraStatusFormat.contains("%@")
                             && notch.privacyMicrophoneActionFormat.components(separatedBy: "%@").count == 3
                             && !notch.privacyMuteMicrophone.isEmpty
                             && !notch.privacyUnmuteMicrophone.isEmpty,
                         "NotchStrings privacy catalog is complete for \(language.rawValue)")
        }

        suite.expect(FeatureStrings.recorder(.ru).zoomSectionLabel == "Масштаб",
                     "Russian recorder inspector uses concise Масштаб tab label")

        let switcherSource = source("Sources/Vorssaint/UI/Switcher/SwitcherView.swift")
        let dockPreviewSource = source("Sources/Vorssaint/UI/Switcher/DockPreviewPanelView.swift")
        let quickToolHUDSource = source("Sources/Vorssaint/Services/QuickTools/QuickToolHUD.swift")
        suite.expect(!switcherSource.contains("Color.white.opacity(0.06)")
                         && !switcherSource.contains("Color.white.opacity(0.14)")
                         && switcherSource.contains("Color.primary.opacity(0.06)")
                         && switcherSource.contains("Color.accentColor.opacity(0.15)"),
                     "SwitcherView WindowCard uses adaptive primary/accent tokens for Light and Dark modes")
        suite.expect(!dockPreviewSource.contains("Color.white.opacity(0.06)")
                         && !dockPreviewSource.contains("Color.white.opacity(0.14)")
                         && dockPreviewSource.contains("Color.primary.opacity(0.06)")
                         && dockPreviewSource.contains("Color.accentColor.opacity(0.15)"),
                     "DockPreviewPanelView cards and capsules use adaptive primary/accent tokens")
        suite.expect(!quickToolHUDSource.contains("Color.white.opacity(0.12)")
                         && quickToolHUDSource.contains("Color.primary.opacity(0.12)"),
                     "QuickToolHUD countdown ring uses adaptive primary token over HUDBackdrop")

        let shelfTilesSource = source("Sources/Vorssaint/UI/Shelf/ShelfTilesView.swift")
        suite.expect(!shelfTilesSource.contains("NSColor.white")
                         && shelfTilesSource.contains("private func updateLayerColors()")
                         && shelfTilesSource.contains("override func viewDidChangeEffectiveAppearance()")
                         && shelfTilesSource.contains("effectiveAppearance.performAsCurrentDrawingAppearance"),
                     "ShelfTilesView resolves dynamic CALayer colors on effective appearance changes")

        let commandBarSource = source("Sources/Vorssaint/UI/CommandBar/CommandBarView.swift")
        let snippetLibrarySource = source("Sources/Vorssaint/UI/SnippetLibraryView.swift")
        suite.expect(!commandBarSource.contains("table: \"CommandBar\"")
                         && !commandBarSource.contains("Color(nsColor: .windowBackgroundColor)")
                         && commandBarSource.contains("l10n.s.actionClear")
                         && snippetLibrarySource.contains("ClearIconButton(label: l10n.s.actionClear)"),
                     "CommandBarView and SnippetLibraryView use localized actionClear and dark-aware status ring")

        for path in [
            "Sources/Vorssaint/UI/Shelf/ShelfDropZoneView.swift",
            "Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift",
            "Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift",
        ] {
            let text = source(path)
            suite.expect(!text.contains(".scale.combined(with: .opacity)")
                             && text.contains(".scale(scale: 0.95).combined(with: .opacity)"),
                         "\(path) replaces scale(0) transition with scale(0.95) + opacity")
        }

        for path in [
            "Sources/Vorssaint/UI/RadialMenu/RadialMenuView.swift",
            "Sources/Vorssaint/UI/Notch/NotchQuickAccessView.swift",
            "Sources/Vorssaint/UI/MenuPanel/DiskSection.swift",
        ] {
            suite.expect(!source(path).contains(".easeIn("),
                         "\(path) eliminates sluggish .easeIn exit curves")
        }

        let sharedUISource = source("Sources/Vorssaint/UI/SharedUI.swift")
        let screenshotEditorSource = source("Sources/Vorssaint/UI/Screenshot/ScreenshotEditorView.swift")
        let recorderEditorSource = source("Sources/Vorssaint/UI/Recorder/RecorderEditorView.swift")
        let updateHighlightsSource = source("Sources/Vorssaint/UI/UpdateHighlightsView.swift")
        suite.expect(sharedUISource.contains(".frame(minWidth: 22, minHeight: 22)")
                         && sharedUISource.contains(".contentShape(Rectangle())")
                         && screenshotEditorSource.contains(".accessibilityLabel(l10n.s.menuUndo)")
                         && screenshotEditorSource.contains(".accessibilityLabel(l10n.s.menuRedo)"),
                     "Shared icon buttons and ScreenshotEditor Undo/Redo expose >=22pt hit shapes and VoiceOver labels")
        suite.expect(updateHighlightsSource.contains(".onExitCommand")
                         && recorderEditorSource.contains(".onExitCommand")
                         && screenshotEditorSource.contains(".onExitCommand"),
                     "Modal overlays and shared-link sheets dismiss on Escape")

        let clipboardPanelSource = source("Sources/Vorssaint/UI/MenuPanel/ClipboardQuickPanelView.swift")
        let scrollingTitleSource = source("Sources/Vorssaint/UI/Switcher/ScrollingTitle.swift")
        suite.expect(clipboardPanelSource.contains(".overlay(alignment: .trailing)")
                         && clipboardPanelSource.contains("hoverActionCluster(entry)")
                         && scrollingTitleSource.contains("weight: .semibold")
                         && scrollingTitleSource.contains(".hidden()"),
                     "ClipboardQuickPanelView and ScrollingTitle prevent hover reflow and font-weight width jitter")
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

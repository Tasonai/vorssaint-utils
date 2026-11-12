// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Glowing privacy indicators displayed in Dynamic Island when
/// camera or microphone are in active use by any application.
struct NotchPrivacyDots: View {
    @ObservedObject private var monitor = CameraMicrophonePrivacyMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    private var itemTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity)
    }

    var body: some View {
        if monitor.isAnyActive {
            Group {
                if monitor.isMicrophoneActive {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        monitor.toggleMicrophoneMute()
                    } label: {
                        dotsRow
                            .frame(minWidth: 22, minHeight: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tooltipText)
                    .accessibilityAddTraits(monitor.isMicrophoneMuted ? .isSelected : [])
                } else {
                    dotsRow
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(tooltipText)
                }
            }
            .help(tooltipText)
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08), value: monitor.isCameraActive)
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08), value: monitor.isMicrophoneActive)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: monitor.isMicrophoneMuted)
        }
    }

    private var dotsRow: some View {
        HStack(spacing: 3) {
            if monitor.isCameraActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6.5, height: 6.5)
                    .shadow(color: Color.green.opacity(0.8), radius: 2.5)
                    .transition(itemTransition)
            }
            if monitor.isMicrophoneActive {
                ZStack {
                    Circle()
                        .fill(monitor.isMicrophoneMuted ? Color.orange.opacity(0.4) : Color.orange)
                        .frame(width: 6.5, height: 6.5)
                        .shadow(color: monitor.isMicrophoneMuted ? Color.clear : Color.orange.opacity(0.8), radius: 2.5)
                    if monitor.isMicrophoneMuted {
                        Image(systemName: "line.diagonal")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .transition(itemTransition)
            }
        }
    }

    private var tooltipText: String {
        var items: [String] = []
        if monitor.isCameraActive {
            let camName = monitor.activeCameraName ?? text.privacyCameraFallback
            items.append(String(format: text.privacyCameraStatusFormat, camName))
        }
        if monitor.isMicrophoneActive {
            let micName = monitor.activeMicrophoneName ?? text.privacyMicrophoneFallback
            let format = monitor.isMicrophoneMuted
                ? text.privacyMicrophoneMutedFormat
                : text.privacyMicrophoneActiveFormat
            items.append(String(format: format, micName))
        }
        return items.joined(separator: "\n")
    }
}

/// Compact Apple-style privacy pill for the expanded Dynamic Island header row.
/// Displays camera/microphone indicators with 1-click microphone mute and full device names in tooltip.
struct NotchPrivacyHeaderBadge: View {
    @ObservedObject private var monitor = CameraMicrophonePrivacyMonitor.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }

    var body: some View {
        if monitor.isAnyActive {
            HStack(spacing: 5) {
                if monitor.isCameraActive {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 18, height: 18)
                        .background(Color.green.opacity(0.14), in: Circle())
                        .accessibilityLabel(
                            String(format: text.privacyCameraStatusFormat,
                                   monitor.activeCameraName ?? text.privacyCameraActive)
                        )
                }

                if monitor.isMicrophoneActive {
                    Button {
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        monitor.toggleMicrophoneMute()
                    } label: {
                        Image(systemName: monitor.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(monitor.isMicrophoneMuted ? .red : .orange)
                            .frame(width: 18, height: 18)
                            .background(
                                (monitor.isMicrophoneMuted ? Color.red.opacity(0.16) : Color.orange.opacity(0.14)),
                                in: Circle()
                            )
                            .frame(minWidth: 22, minHeight: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(monitor.isMicrophoneMuted ? text.privacyUnmuteMicrophone : text.privacyMuteMicrophone)
                    .accessibilityAddTraits(monitor.isMicrophoneMuted ? .isSelected : [])
                }
            }
            .help(tooltipText)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08), value: monitor.isCameraActive)
            .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.08), value: monitor.isMicrophoneActive)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: monitor.isMicrophoneMuted)
        }
    }

    private var tooltipText: String {
        var items: [String] = []
        if monitor.isCameraActive {
            items.append(String(format: text.privacyCameraStatusFormat,
                                monitor.activeCameraName ?? text.privacyCameraActive))
        }
        if monitor.isMicrophoneActive {
            let micName = monitor.activeMicrophoneName ?? text.privacyMicrophoneFallback
            let action = monitor.isMicrophoneMuted ? text.privacyUnmuteMicrophone : text.privacyMuteMicrophone
            items.append(String(format: text.privacyMicrophoneActionFormat, micName, action))
        }
        return items.joined(separator: "\n")
    }
}

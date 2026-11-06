// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Glowing privacy indicators displayed in Dynamic Island when
/// camera or microphone are in active use by any application.
struct NotchPrivacyDots: View {
    @ObservedObject private var monitor = CameraMicrophonePrivacyMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if monitor.isAnyActive {
            HStack(spacing: 3) {
                if monitor.isCameraActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6.5, height: 6.5)
                        .shadow(color: Color.green.opacity(0.8), radius: 2.5)
                        .transition(.scale.combined(with: .opacity))
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
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if monitor.isMicrophoneActive {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    monitor.toggleMicrophoneMute()
                }
            }
            .help(tooltipText)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: monitor.isCameraActive)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: monitor.isMicrophoneActive)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: monitor.isMicrophoneMuted)
        }
    }

    private var tooltipText: String {
        var items: [String] = []
        if monitor.isCameraActive {
            let camName = monitor.activeCameraName ?? "Камера"
            items.append("Камера: \(camName)")
        }
        if monitor.isMicrophoneActive {
            let micName = monitor.activeMicrophoneName ?? "Микрофон"
            let state = monitor.isMicrophoneMuted ? " (заглушен, нажмите для включения)" : " (активен, нажмите для отключения)"
            items.append("Микрофон: \(micName)\(state)")
        }
        return items.joined(separator: "\n")
    }
}

/// Compact Apple-style privacy pill for the expanded Dynamic Island header row.
/// Displays camera/microphone indicators with 1-click microphone mute and full device names in tooltip.
struct NotchPrivacyHeaderBadge: View {
    @ObservedObject private var monitor = CameraMicrophonePrivacyMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if monitor.isAnyActive {
            HStack(spacing: 5) {
                if monitor.isCameraActive {
                    Image(systemName: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.green)
                        .frame(width: 18, height: 18)
                        .background(Color.green.opacity(0.14), in: Circle())
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .help(tooltipText)
            .transition(.opacity.combined(with: .scale))
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: monitor.isCameraActive)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: monitor.isMicrophoneActive)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: monitor.isMicrophoneMuted)
        }
    }

    private var tooltipText: String {
        var items: [String] = []
        if monitor.isCameraActive {
            items.append("Камера: \(monitor.activeCameraName ?? "Активна")")
        }
        if monitor.isMicrophoneActive {
            let micName = monitor.activeMicrophoneName ?? "Микрофон"
            let action = monitor.isMicrophoneMuted ? "Включить микрофон" : "Заглушить микрофон"
            items.append("\(micName) — \(action)")
        }
        return items.joined(separator: "\n")
    }
}

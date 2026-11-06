// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Styling and animation parameters for Dynamic Island system HUD indicators.
enum NotchHUDTheme {
    /// Distinct Apple-inspired semantic accent color for each system HUD event.
    static func tint(for event: NotchEvent, level: Double? = nil, symbol: String = "") -> Color {
        switch event {
        case .brightness:
            return Color(red: 1.0, green: 0.82, blue: 0.22)
        case .keyboardLight:
            return Color(red: 0.38, green: 0.85, blue: 0.98)
        case .volume:
            if let level, level <= 0.001 {
                return Color(red: 1.0, green: 0.36, blue: 0.36)
            }
            return .white
        case .agents:
            return symbol.hasPrefix("exclamationmark") ? .orange : .white
        case .timer:
            return .orange
        default:
            return .white
        }
    }

    /// Background track opacity for the HUD meter.
    static let trackOpacity: Double = 0.16

    /// Standard height for HUD level meters across both wing and capsule presentations.
    static let meterHeight: CGFloat = 6.0

    /// Spring animation for responsive tactile feedback on level changes.
    static let levelSpring = Animation.spring(response: 0.22, dampingFraction: 0.8)
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

enum NotchHUDThemeTests {
    static func run(_ suite: TestSuite) {
        testColorTheming(suite)
        testLayoutAndMetrics(suite)
    }

    private static func testColorTheming(_ suite: TestSuite) {
        let brightnessTint = NotchHUDTheme.tint(for: .brightness)
        suite.expect(brightnessTint == Color(red: 1.0, green: 0.82, blue: 0.22),
                     "Brightness HUD uses warm solar amber tint")

        let keyboardLightTint = NotchHUDTheme.tint(for: .keyboardLight)
        suite.expect(keyboardLightTint == Color(red: 0.38, green: 0.85, blue: 0.98),
                     "Keyboard backlight HUD uses cool cyan tint")

        let normalVolumeTint = NotchHUDTheme.tint(for: .volume, level: 0.6)
        suite.expect(normalVolumeTint == .white,
                     "Active volume HUD uses crisp white tint")

        let mutedVolumeTint = NotchHUDTheme.tint(for: .volume, level: 0.0)
        suite.expect(mutedVolumeTint == Color(red: 1.0, green: 0.36, blue: 0.36),
                     "Muted volume HUD uses alert coral tint")

        let timerTint = NotchHUDTheme.tint(for: .timer)
        suite.expect(timerTint == .orange,
                     "Timer HUD maintains orange theme tint")
    }

    private static func testLayoutAndMetrics(_ suite: TestSuite) {
        suite.expect(NotchHUDTheme.meterHeight == 6.0,
                     "HUD meter has 6pt height for prominent Apple-style readability")
        suite.expect(NotchHUDTheme.trackOpacity == 0.16,
                     "HUD meter background track has standard 0.16 opacity")

        // Verify spring animation exists
        _ = NotchHUDTheme.levelSpring
        suite.expect(true, "HUD theme declares spring physics for level adjustments")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchFeedbackTests {
    static func run(_ suite: TestSuite) {
        let defaults = UserDefaults(suiteName: "vorss.tests.notch-feedback")!
        defaults.removePersistentDomain(forName: "vorss.tests.notch-feedback")
        let service = NotchFeedbackService(defaults: defaults)

        suite.expect(service.isHapticsEnabled && service.isAcousticsEnabled,
                     "haptics and acoustics default to true")

        defaults.set(false, forKey: DefaultsKey.notchHapticsEnabled)
        defaults.set(false, forKey: DefaultsKey.notchAcousticsEnabled)
        suite.expect(!service.isHapticsEnabled && !service.isAcousticsEnabled,
                     "preferences respect user defaults")

        // Verifies methods execute safely without exceptions
        service.performOpen()
        service.performClose()
        service.performSelection()
        suite.expect(true, "feedback methods execute safely")
    }
}

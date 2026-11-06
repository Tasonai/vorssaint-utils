// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchQuickScratchpadTests {
    static func run(_ suite: TestSuite) {
        func source(_ path: String) -> String {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }

        let buttonSource = source("Sources/Vorssaint/UI/Notch/NotchQuickScratchpadButton.swift")
        suite.expect(!buttonSource.isEmpty, "NotchQuickScratchpadButton source exists")
        suite.expect(buttonSource.contains("struct NotchQuickScratchpadButton: View"),
                     "NotchQuickScratchpadButton is defined as a SwiftUI View")
        suite.expect(buttonSource.contains("service.open(.scratchpad)"),
                     "NotchQuickScratchpadButton switches island to scratchpad module")
        suite.expect(buttonSource.contains("pad.createPad"),
                     "NotchQuickScratchpadButton offers quick pad creation")
        suite.expect(buttonSource.contains("pad.selectPad"),
                     "NotchQuickScratchpadButton supports switching between pads")

        let notchViewSource = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        suite.expect(notchViewSource.contains("NotchQuickScratchpadButton(service: service)"),
                     "NotchView embeds NotchQuickScratchpadButton in expanded header row")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum NotchShelfDropTests {
    static func run(_ suite: TestSuite) {
        func source(_ path: String) -> String {
            (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        }

        let dropTargetSource = source("Sources/Vorssaint/UI/Notch/NotchShelfDropTargetView.swift")
        suite.expect(!dropTargetSource.isEmpty, "NotchShelfDropTargetView source exists")
        suite.expect(dropTargetSource.contains("struct NotchShelfDropTargetView: View"),
                     "NotchShelfDropTargetView is defined as a SwiftUI View")
        suite.expect(dropTargetSource.contains("shelf.visibleItems.count"),
                     "NotchShelfDropTargetView queries shelf visible items count")
        suite.expect(dropTargetSource.contains("tray.and.arrow.down.fill"),
                     "NotchShelfDropTargetView displays drop target tray symbol")
        suite.expect(dropTargetSource.contains("LinearGradient"),
                     "NotchShelfDropTargetView renders glowing border gradient")

        let notchViewSource = source("Sources/Vorssaint/UI/Notch/NotchView.swift")
        suite.expect(notchViewSource.contains("NotchShelfDropTargetView(service: service)"),
                     "NotchView embeds NotchShelfDropTargetView when dragPlaceholder is active")
    }
}

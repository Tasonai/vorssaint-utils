// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum NotchSettingsTab: CaseIterable {
    case layout, content, activity, behavior, companion
}

/// The Dynamic Island page's tabs, with the button that opens the island.
/// Four tab names can need more room than the narrowest window leaves the
/// page in longer languages, and a page wider than its column is centered and
/// cut on both sides, under the sidebar. The segments give way to a menu
/// whenever they don't fit beside the button.
struct NotchSettingsTabRow: View {
    @Binding var tab: NotchSettingsTab
    let language: AppLanguage
    /// The companion's tab, once it is installed.
    var showsCompanion = false
    let canOpen: Bool
    let open: () -> Void

    var body: some View {
        let text = FeatureStrings.notch(language)
        let segmentedSize = measuredSegmentedSize
        HStack {
            ViewThatFits(in: .horizontal) {
                Color.clear
                    .frame(width: segmentedSize.width, height: segmentedSize.height)
                    .overlay { picker.pickerStyle(.segmented).fixedSize() }
                picker.pickerStyle(.menu)
            }
            Button(action: open) { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.bordered).disabled(!canOpen).help(text.open).accessibilityLabel(text.open)
        }
    }

    private var segmentTitles: [String] {
        let editor = FeatureStrings.notchEditor(language)
        var titles = [editor.layout, editor.content, editor.activity, editor.behavior]
        if showsCompanion {
            titles.append(FeatureStrings.notchMascot(language).title)
        }
        return titles
    }

    private var measuredSegmentedSize: CGSize {
        let control = NSSegmentedControl(labels: segmentTitles, trackingMode: .selectOne, target: nil, action: nil)
        let fitting = control.fittingSize
        let alignment = control.alignmentRect(forFrame: NSRect(origin: .zero, size: fitting)).size
        return CGSize(width: ceil(alignment.width), height: ceil(alignment.height))
    }

    private var selectionBinding: Binding<NotchSettingsTab> {
        Binding(
            get: { !showsCompanion && tab == .companion ? .layout : tab },
            set: { newValue in
                guard tab != newValue else { return }
                tab = newValue
            }
        )
    }

    private var picker: some View {
        let editor = FeatureStrings.notchEditor(language)
        return Picker(FeatureStrings.notch(language).title, selection: selectionBinding) {
            Text(editor.layout).tag(NotchSettingsTab.layout)
            Text(editor.content).tag(NotchSettingsTab.content)
            Text(editor.activity).tag(NotchSettingsTab.activity)
            Text(editor.behavior).tag(NotchSettingsTab.behavior)
            if showsCompanion {
                Text(FeatureStrings.notchMascot(language).title).tag(NotchSettingsTab.companion)
            }
        }
        .labelsHidden()
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A 1-click header access button for Scratchpad notes directly in Dynamic Island.
struct NotchQuickScratchpadButton: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared

    private var isSelected: Bool {
        service.selected == .scratchpad && !service.showingSections
    }

    private var title: String {
        FeatureStrings.scratchpad(l10n.language).pageTitle
    }

    var body: some View {
        Button(action: toggleScratchpad) {
            Image(systemName: isSelected ? "square.and.pencil.circle.fill" : "square.and.pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Color.yellow : Color.white.opacity(0.72))
                .frame(width: 24, height: 24)
                .background {
                    if isSelected {
                        Circle().fill(Color.yellow.opacity(0.18))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .contextMenu {
            Button {
                pad.createPad(defaultName: FeatureStrings.scratchpad(l10n.language).pageTitle)
                service.open(.scratchpad)
            } label: {
                Label(FeatureStrings.scratchpad(l10n.language).newPad, systemImage: "plus")
            }

            if !pad.pads.isEmpty {
                Divider()
                ForEach(pad.pads) { item in
                    Button {
                        pad.selectPad(item.id)
                        service.open(.scratchpad)
                    } label: {
                        HStack {
                            Text(item.name)
                            if item.id == pad.selectedPadID {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }
    }

    private func toggleScratchpad() {
        NotchFeedbackService.shared.performSelection()
        if isSelected {
            service.toggleSections()
        } else {
            service.open(.scratchpad)
        }
    }
}

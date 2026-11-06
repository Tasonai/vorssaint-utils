// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A unified header pill dock for 1-click navigation between core Dynamic Island hubs
/// (Controls, Music, Mixer, Files, System, Scratchpad, and All Sections).
struct NotchQuickScratchpadButton: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.notchBand) private var band

    private var isSelected: Bool {
        service.selected == .scratchpad && !service.showingSections
    }

    private var shouldShowInHeader: Bool {
        !service.showingSections && !band.besideCamera
    }

    private var title: String {
        FeatureStrings.scratchpad(l10n.language).pageTitle
    }

    private var primaryHubs: [NotchModule] {
        let candidates: [NotchModule] = [.controls, .music, .mixer, .files, .system]
        return candidates.filter { service.modules.contains($0) }
    }

    private var compactHubs: [NotchModule] {
        let candidates: [NotchModule] = [.controls, .music, .mixer]
        return candidates.filter { service.modules.contains($0) }
    }

    private var showsInlineSectionsButton: Bool {
        !band.sectionsButton && !band.trailingSectionsButton && !service.modules.isEmpty
    }

    var body: some View {
        if shouldShowInHeader {
            ViewThatFits(in: .horizontal) {
                if service.selected != .controls {
                    dockPill(modules: primaryHubs, includeScratchpad: true)
                }
                dockPill(modules: compactHubs, includeScratchpad: true)
                dockPill(modules: [], includeScratchpad: true)
            }
        }
    }

    private func dockPill(modules: [NotchModule], includeScratchpad: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(modules) { module in
                moduleButton(module)
            }
            if includeScratchpad && service.modules.contains(.scratchpad) {
                scratchpadButton
            }
            if showsInlineSectionsButton {
                sectionsButton
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        )
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.16), .white.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        }
    }

    private func moduleButton(_ module: NotchModule) -> some View {
        let active = !service.showingSections && !service.showingAppPanel && service.selected == module
        let moduleTitle = module.title(l10n.language)
        return Button {
            NotchFeedbackService.shared.performSelection()
            service.select(module)
        } label: {
            Image(systemName: module.symbol)
                .font(.system(size: 11, weight: active ? .semibold : .medium))
                .foregroundStyle(active ? .white : .white.opacity(0.62))
                .frame(width: 24, height: 22)
                .background {
                    if active {
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.16))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(moduleTitle)
        .accessibilityLabel(moduleTitle)
    }

    private var sectionsButton: some View {
        let sectionsTitle = FeatureStrings.notch(l10n.language).sectionsTitle
        return Button {
            NotchFeedbackService.shared.performSelection()
            service.toggleSections()
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .frame(width: 24, height: 22)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(sectionsTitle)
        .accessibilityLabel(sectionsTitle)
    }

    private var scratchpadButton: some View {
        Button(action: toggleScratchpad) {
            Image(systemName: isSelected ? "square.and.pencil.circle.fill" : "square.and.pencil")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isSelected ? Color.yellow : Color.white.opacity(0.68))
                .frame(width: 24, height: 22)
                .background {
                    if isSelected {
                        Capsule(style: .continuous).fill(Color.yellow.opacity(0.20))
                    }
                }
                .contentShape(Capsule())
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

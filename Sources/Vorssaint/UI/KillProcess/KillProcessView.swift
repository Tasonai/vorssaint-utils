// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Kill Process, embedded as a Settings page: a live, searchable list of
/// every running process with kill, force-kill, kill-all, kill-tree, and
/// restart actions.
struct KillProcessView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = KillProcessService.shared
    @AppStorage(DefaultsKey.killProcessCommandBarEnabled) private var commandBarEnabled = true
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var refreshTimer: Timer?
    @State private var pendingAction: PendingAction?

    private var strings: KillProcessFeatureStrings { FeatureStrings.killProcess(l10n.language) }

    fileprivate enum PendingAction {
        case kill(KillProcessEntry, force: Bool)
        case killAll(name: String, force: Bool)
        case killTree(KillProcessEntry, force: Bool)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            columnHeader
            Divider()
            list
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            service.refresh(force: true)
            updateTimer(for: controlActiveState)
        }
        .onDisappear { stopTimer() }
        .onChange(of: controlActiveState) { _, newValue in
            updateTimer(for: newValue)
        }
        .alert(alertTitle,
               isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
               presenting: pendingAction) { action in
            Button(l10n.s.uninstallerCancel, role: .cancel) {}
            Button(confirmButtonTitle(action), role: .destructive) {
                perform(action)
                pendingAction = nil
            }
        } message: { action in
            Text(alertMessage(for: action))
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(strings.searchPlaceholder, text: $service.query)
                        .textFieldStyle(.plain)
                    if service.isRefreshing {
                        ProgressView().controlSize(.small)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(String(format: strings.processCountFormat, service.filteredEntries.count))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button {
                    service.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(strings.refreshTooltip)
            }

            HStack(spacing: 18) {
                Toggle(strings.groupToggle, isOn: groupBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(strings.groupCaption)

                Toggle(strings.commandBarToggle, isOn: $commandBarEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(strings.commandBarCaption)

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var groupBinding: Binding<Bool> {
        Binding(get: { service.groupRelated }, set: { service.setGroupRelated($0) })
    }

    // MARK: Column header

    /// Mirrors `row(_:)`'s HStack widths exactly, so each label sits over its
    /// column: the leading `22`pt gap matches the row icon, and the trailing
    /// hidden action cluster matches the localized Kill + "..." button widths.
    private var columnHeader: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 22)
            columnHeaderButton(strings.columnProcess, column: .name)
                .frame(maxWidth: .infinity, alignment: .leading)
            columnHeaderButton(strings.columnCPU, column: .cpu)
                .frame(width: 52, alignment: .trailing)
            columnHeaderButton(strings.columnMemory, column: .memory)
                .frame(width: 72, alignment: .trailing)
            columnHeaderButton(strings.columnPID, column: .pid)
                .frame(width: 56, alignment: .trailing)
            rowActionsWidthPlaceholder
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var rowActionsWidthPlaceholder: some View {
        HStack(spacing: 10) {
            Button(strings.killButton) {}
                .frame(minWidth: 44)
            Image(systemName: "ellipsis")
                .frame(minWidth: 44)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .hidden()
        .accessibilityHidden(true)
    }

    private func columnHeaderButton(_ title: String, column: KillProcessService.SortBy) -> some View {
        Button {
            service.toggleSort(column)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .lineLimit(1)
                if service.sortBy == column {
                    Image(systemName: service.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let displayed = service.filteredEntries
        if displayed.isEmpty {
            // A transient ps hiccup no longer clears `entries` (KillProcessService
            // keeps the last good snapshot), so an empty list here means either
            // the very first load hasn't landed yet, or a search genuinely
            // matched nothing - two different messages, not one.
            if service.hasLoadedOnce {
                emptyState
            } else {
                loadingState
            }
        } else {
            List(displayed) { entry in
                KillProcessRowView(
                    entry: entry,
                    strings: strings,
                    canRestart: service.canRestart(entry),
                    onPendingAction: { pendingAction = $0 },
                    onRestart: { service.restart(entry) },
                    onCopy: copy
                )
            }
            .listStyle(.inset)
        }
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(strings.emptyStateTitle).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Confirmation

    private var alertTitle: String {
        guard let pendingAction else { return "" }
        switch pendingAction {
        case let .kill(entry, force):
            return String(format: force ? strings.confirmForceKillFormat : strings.confirmKillFormat, entry.name)
        case let .killAll(name, _):
            return String(format: strings.confirmKillAllFormat, name)
        case let .killTree(entry, _):
            return String(format: strings.confirmKillTreeFormat, entry.name)
        }
    }

    private func alertMessage(for action: PendingAction) -> String {
        switch action {
        case let .kill(entry, _): return entry.path
        case let .killTree(entry, _): return entry.path
        case .killAll: return ""
        }
    }

    private func confirmButtonTitle(_ action: PendingAction) -> String {
        switch action {
        case let .kill(_, force): return force ? strings.forceKillButton : strings.killButton
        case .killAll: return strings.killButton
        case .killTree: return strings.killTreeButton
        }
    }

    private func perform(_ action: PendingAction) {
        switch action {
        case let .kill(entry, force): service.kill(entry, force: force)
        case let .killAll(name, force): service.killAll(named: name, force: force)
        case let .killTree(entry, force): service.killTree(entry, force: force)
        }
    }

    // MARK: Helpers

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.declareVorssaintSource()
        NSPasteboard.general.setString(value, forType: .string)
    }

    /// Ticks only while this page is open AND its window is key, so the
    /// CPU/memory columns read live without polling `ps` in the background -
    /// neither while some other Settings page is showing, nor while this one
    /// is open but not the focused window.
    /// The interval matches the service's own freshness cache exactly, so
    /// every tick does real work instead of a third of them being no-ops.
    private func updateTimer(for state: ControlActiveState) {
        guard state != .inactive else {
            stopTimer()
            return
        }
        guard refreshTimer == nil else { return }
        service.refresh()
        let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            service.refresh()
        }
        timer.tolerance = 0.6
        refreshTimer = timer
    }

    private func stopTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

private struct KillProcessRowView: View {
    let entry: KillProcessEntry
    let strings: KillProcessFeatureStrings
    let canRestart: Bool
    let onPendingAction: (KillProcessView.PendingAction) -> Void
    let onRestart: () -> Void
    let onCopy: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: ResponsibleProcess.icon(for: entry.pid))
                .resizable().frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.name).font(.system(size: 12.5)).lineLimit(1).truncationMode(.middle)
                    if entry.groupedCount > 1 {
                        Text(String(format: strings.processCountFormat, entry.groupedCount))
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                Text(entry.path)
                    .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.head)
            }
            Spacer()
            Text(String(format: "%.1f%%", locale: MetricFormat.locale, entry.cpuPercent))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            Text(MetricFormat.bytes(UInt64(max(0, entry.memoryBytes))))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(String(entry.pid))
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Button(strings.killButton) {
                onPendingAction(.kill(entry, force: false))
            }
            .frame(minWidth: 44)
            .disabled(entry.isProtected)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
            Menu {
                rowActions
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(minWidth: 44)
            .opacity(isHovered ? 1 : 0)
            .allowsHitTesting(isHovered)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            if isHovered != hovering {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(strings.killButton) { onPendingAction(.kill(entry, force: false)) }
                .disabled(entry.isProtected)
            rowActions
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        Button(strings.forceKillButton) { onPendingAction(.kill(entry, force: true)) }
            .disabled(entry.isProtected)
        Button(String(format: strings.killAllFormat, entry.name)) {
            onPendingAction(.killAll(name: entry.name, force: false))
        }
        .disabled(entry.isProtected)
        Button(strings.killTreeButton) { onPendingAction(.killTree(entry, force: false)) }
            .disabled(entry.isProtected)
        if canRestart {
            Button(strings.restartButton, action: onRestart)
        }
        Divider()
        Button(strings.copyPID) { onCopy(String(entry.pid)) }
        Button(strings.copyPath) { onCopy(entry.path) }
    }
}

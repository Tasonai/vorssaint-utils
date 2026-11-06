// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

/// The operational status of a CoreAudio process tap for a specific application.
public enum MixerTapStatus: Equatable, Hashable, Sendable {
    /// No process tap is active or requested for this application.
    case idle
    /// A background build is currently acquiring the HAL tap description and aggregate device.
    case building(token: Int)
    /// The process tap and aggregate IO proc are actively re-rendering audio with gain.
    case active(deviceUID: String, objectsCount: Int)
    /// The tap was created, but audio rendering cycles are not advancing (stalled HAL driver).
    case stalled(cycles: UInt64)
    /// The tap failed due to missing System Audio Recording consent or HAL refusal.
    case permissionDenied
}

/// A value snapshot of a tracked mixer tap session.
public struct MixerTapSessionInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let status: MixerTapStatus
    public let outputDeviceUID: String
    public let gain: Float
    public let renderCycles: UInt64
    public let updatedAt: CFAbsoluteTime

    public var isActive: Bool {
        if case .active = status { return true }
        return false
    }

    public var isBuilding: Bool {
        if case .building = status { return true }
        return false
    }

    public init(id: String,
                status: MixerTapStatus,
                outputDeviceUID: String,
                gain: Float,
                renderCycles: UInt64 = 0,
                updatedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        self.id = id
        self.status = status
        self.outputDeviceUID = outputDeviceUID
        self.gain = gain
        self.renderCycles = renderCycles
        self.updatedAt = updatedAt
    }
}

/// Thread-safe registry and lifecycle coordinator for per-process CoreAudio taps.
public final class MixerTapCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: MixerTapSessionInfo] = [:]

    public init() {}

    /// Record that an engine build has started for an app.
    public func recordBuildStarted(appID: String, token: Int, outputDeviceUID: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions[appID] = MixerTapSessionInfo(
            id: appID,
            status: .building(token: token),
            outputDeviceUID: outputDeviceUID,
            gain: 1.0,
            renderCycles: 0
        )
    }

    /// Record successful activation of a process tap and aggregate device.
    public func recordBuildFinished(appID: String,
                                    token: Int,
                                    outputDeviceUID: String,
                                    gain: Float,
                                    objectsCount: Int) {
        lock.lock()
        defer { lock.unlock() }
        // Verify that the finishing build matches or succeeds the current building token
        if let current = sessions[appID], case .building(let currentToken) = current.status {
            guard token == currentToken else { return }
        }
        sessions[appID] = MixerTapSessionInfo(
            id: appID,
            status: .active(deviceUID: outputDeviceUID, objectsCount: objectsCount),
            outputDeviceUID: outputDeviceUID,
            gain: gain,
            renderCycles: 0
        )
    }

    /// Update recorded render cycle count for active observation.
    public func recordRenderCycles(appID: String, cycles: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        guard let current = sessions[appID] else { return }
        let newStatus: MixerTapStatus
        if cycles > 0 && cycles == current.renderCycles {
            newStatus = .stalled(cycles: cycles)
        } else if case .stalled = current.status, cycles > current.renderCycles {
            // Recovered from stalled state
            newStatus = .active(deviceUID: current.outputDeviceUID, objectsCount: 1)
        } else {
            newStatus = current.status
        }
        sessions[appID] = MixerTapSessionInfo(
            id: appID,
            status: newStatus,
            outputDeviceUID: current.outputDeviceUID,
            gain: current.gain,
            renderCycles: cycles
        )
    }

    /// Record permission denial or hardware failure.
    public func recordPermissionDenied(appID: String, outputDeviceUID: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions[appID] = MixerTapSessionInfo(
            id: appID,
            status: .permissionDenied,
            outputDeviceUID: outputDeviceUID,
            gain: 1.0,
            renderCycles: 0
        )
    }

    /// Terminate and unregister an app's tap session.
    public func unregister(appID: String) {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeValue(forKey: appID)
    }

    /// Clear all active sessions (e.g. during system sleep, audio server restart or app shutdown).
    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        sessions.removeAll()
    }

    /// Snapshot of all currently tracked sessions.
    public var allSessions: [MixerTapSessionInfo] {
        lock.lock()
        defer { lock.unlock() }
        return Array(sessions.values)
    }

    /// Total number of actively rendering taps.
    public var activeTapCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sessions.values.reduce(0) { count, session in
            session.isActive ? count + 1 : count
        }
    }

    /// Check if a specific app currently has an active tap.
    public func isTapActive(appID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessions[appID]?.isActive ?? false
    }

    /// Check if a tap is in a stalled state.
    public func isTapStalled(appID: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .stalled = sessions[appID]?.status { return true }
        return false
    }

    /// Retrieve session info for an app.
    public func session(for appID: String) -> MixerTapSessionInfo? {
        lock.lock()
        defer { lock.unlock() }
        return sessions[appID]
    }
}

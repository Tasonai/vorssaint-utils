// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MixerTapEngineTests {
    static func run(_ suite: TestSuite) {
        testSessionLifecycle(suite)
        testStalledDetectionAndRecovery(suite)
        testTokenMismatchRejection(suite)
        testConcurrentAccess(suite)
    }

    private static func testSessionLifecycle(_ suite: TestSuite) {
        let coordinator = MixerTapCoordinator()
        suite.expect(coordinator.activeTapCount == 0, "fresh coordinator has 0 active taps")
        suite.expect(coordinator.allSessions.isEmpty, "fresh coordinator has empty sessions")

        // 1. Start build
        coordinator.recordBuildStarted(appID: "com.spotify.client", token: 1, outputDeviceUID: "BuiltInSpeakerDevice")
        suite.expect(!coordinator.isTapActive(appID: "com.spotify.client"), "building tap is not yet active")
        let buildingSession = coordinator.session(for: "com.spotify.client")
        suite.expect(buildingSession?.isBuilding == true, "session reports isBuilding")
        suite.expect(buildingSession?.status == .building(token: 1), "session has building(token: 1) status")

        // 2. Finish build
        coordinator.recordBuildFinished(appID: "com.spotify.client", token: 1, outputDeviceUID: "BuiltInSpeakerDevice", gain: 0.75, objectsCount: 2)
        suite.expect(coordinator.isTapActive(appID: "com.spotify.client"), "finished build is active")
        suite.expect(coordinator.activeTapCount == 1, "activeTapCount is 1")
        let activeSession = coordinator.session(for: "com.spotify.client")
        suite.expect(activeSession?.isActive == true, "session reports isActive")
        suite.expect(activeSession?.outputDeviceUID == "BuiltInSpeakerDevice", "outputDeviceUID matches")
        suite.expect(activeSession?.gain == 0.75, "gain matches 0.75")

        // 3. Unregister
        coordinator.unregister(appID: "com.spotify.client")
        suite.expect(!coordinator.isTapActive(appID: "com.spotify.client"), "unregistered tap is inactive")
        suite.expect(coordinator.activeTapCount == 0, "activeTapCount returns to 0")
        suite.expect(coordinator.session(for: "com.spotify.client") == nil, "unregistered session is nil")
    }

    private static func testStalledDetectionAndRecovery(_ suite: TestSuite) {
        let coordinator = MixerTapCoordinator()
        coordinator.recordBuildStarted(appID: "com.apple.Music", token: 10, outputDeviceUID: "Headphones")
        coordinator.recordBuildFinished(appID: "com.apple.Music", token: 10, outputDeviceUID: "Headphones", gain: 1.0, objectsCount: 1)

        // Advance cycles
        coordinator.recordRenderCycles(appID: "com.apple.Music", cycles: 1200)
        suite.expect(!coordinator.isTapStalled(appID: "com.apple.Music"), "advancing cycles is not stalled")

        // Report same cycles again -> stalled
        coordinator.recordRenderCycles(appID: "com.apple.Music", cycles: 1200)
        suite.expect(coordinator.isTapStalled(appID: "com.apple.Music"), "non-advancing render cycle detects stalled tap")

        // Recovery -> cycles advance again
        coordinator.recordRenderCycles(appID: "com.apple.Music", cycles: 1500)
        suite.expect(!coordinator.isTapStalled(appID: "com.apple.Music"), "cycle advancement recovers tap from stalled state")
        suite.expect(coordinator.isTapActive(appID: "com.apple.Music"), "tap is active again after recovery")
    }

    private static func testTokenMismatchRejection(_ suite: TestSuite) {
        let coordinator = MixerTapCoordinator()
        coordinator.recordBuildStarted(appID: "com.google.Chrome", token: 5, outputDeviceUID: "Default")

        // An outdated token landing should be rejected
        coordinator.recordBuildFinished(appID: "com.google.Chrome", token: 4, outputDeviceUID: "Default", gain: 0.5, objectsCount: 1)
        suite.expect(!coordinator.isTapActive(appID: "com.google.Chrome"), "outdated build token 4 is rejected")
        suite.expect(coordinator.session(for: "com.google.Chrome")?.isBuilding == true, "remains building with token 5")

        // Valid token 5 lands
        coordinator.recordBuildFinished(appID: "com.google.Chrome", token: 5, outputDeviceUID: "Default", gain: 0.5, objectsCount: 1)
        suite.expect(coordinator.isTapActive(appID: "com.google.Chrome"), "matching token 5 activates tap")
    }

    private static func testConcurrentAccess(_ suite: TestSuite) {
        let coordinator = MixerTapCoordinator()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "vorssaint.tests.mixertap.concurrent", attributes: .concurrent)

        for i in 0..<50 {
            group.enter()
            queue.async {
                let appID = "app.\(i)"
                coordinator.recordBuildStarted(appID: appID, token: i, outputDeviceUID: "Device.\(i)")
                coordinator.recordBuildFinished(appID: appID, token: i, outputDeviceUID: "Device.\(i)", gain: 1.0, objectsCount: 1)
                _ = coordinator.allSessions
                _ = coordinator.activeTapCount
                coordinator.recordRenderCycles(appID: appID, cycles: UInt64(i * 100))
                if i % 2 == 0 {
                    coordinator.unregister(appID: appID)
                }
                group.leave()
            }
        }

        let waitResult = group.wait(timeout: .now() + 5.0)
        suite.expect(waitResult == .success, "concurrent coordinator access completes without deadlock")
        suite.expect(coordinator.activeTapCount <= 50, "coordinator maintains thread safety under concurrency")
    }
}

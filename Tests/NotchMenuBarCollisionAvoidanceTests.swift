// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum NotchMenuBarCollisionAvoidanceTests {
    static func run(_ suite: TestSuite) {
        testCollisionEvaluation(suite)
        testSpacingCompressionCalculation(suite)
    }

    private static func testCollisionEvaluation(_ suite: TestSuite) {
        // Screen width: 1512 (14" MacBook Pro), notch center: 756, width: 200 (656...856)
        let cameraRect = CGRect(x: 656, y: 0, width: 200, height: 32)

        // 1. Clear layout: Menus end at 500, Status items start at 1000
        let clearMenus = [
            CGRect(x: 20, y: 0, width: 100, height: 24),
            CGRect(x: 130, y: 0, width: 80, height: 24),
            CGRect(x: 220, y: 0, width: 90, height: 24)
        ]
        let clearStatus = [
            CGRect(x: 1000, y: 0, width: 50, height: 24),
            CGRect(x: 1060, y: 0, width: 50, height: 24)
        ]
        let clearState = NotchMenuBarCollisionAvoidance.evaluate(
            menuItems: clearMenus,
            statusItems: clearStatus,
            cameraRect: cameraRect
        )
        if case .clear(let left, let right) = clearState {
            suite.expect(left > NotchMenuBarCollisionAvoidance.safeNotchMargin, "Left margin is comfortably safe")
            suite.expect(right > NotchMenuBarCollisionAvoidance.safeNotchMargin, "Right margin is comfortably safe")
        } else {
            suite.expect(false, "Expected clear state for non-overlapping items")
        }

        // 2. Menu overlap: Large pro app with 12 menus extending to 720 (into 656...856 notch)
        let overlappingMenus = [
            CGRect(x: 20, y: 0, width: 300, height: 24),
            CGRect(x: 330, y: 0, width: 200, height: 24),
            CGRect(x: 540, y: 0, width: 180, height: 24) // maxX = 720 (crosses 656)
        ]
        let menuOverlapState = NotchMenuBarCollisionAvoidance.evaluate(
            menuItems: overlappingMenus,
            statusItems: clearStatus,
            cameraRect: cameraRect
        )
        if case .menuOverlap(let excess) = menuOverlapState {
            suite.expect(excess == 720 - 656, "Detected menu overlap excess width")
        } else {
            suite.expect(false, "Expected menuOverlap state")
        }

        // 3. Status item overlap: Busy tray starting at 800 (encroaches into 656...856)
        let overlappingStatus = [
            CGRect(x: 800, y: 0, width: 100, height: 24),
            CGRect(x: 910, y: 0, width: 100, height: 24)
        ]
        let statusOverlapState = NotchMenuBarCollisionAvoidance.evaluate(
            menuItems: clearMenus,
            statusItems: overlappingStatus,
            cameraRect: cameraRect
        )
        if case .statusOverlap(let excess) = statusOverlapState {
            suite.expect(excess == 856 - 800, "Detected status items encroaching into notch from right")
        } else {
            suite.expect(false, "Expected statusOverlap state")
        }

        // 4. Dense crowding: Menus end at 650 (within safe margin of 656)
        let crowdedMenus = [
            CGRect(x: 20, y: 0, width: 630, height: 24) // maxX = 650, clearance = 6 < safeNotchMargin (12)
        ]
        let crowdingState = NotchMenuBarCollisionAvoidance.evaluate(
            menuItems: crowdedMenus,
            statusItems: clearStatus,
            cameraRect: cameraRect
        )
        if case .denseCrowding(let leftClearance, _) = crowdingState {
            suite.expect(leftClearance == 6, "Detected dense crowding near notch left wing")
        } else {
            suite.expect(false, "Expected denseCrowding state")
        }
    }

    private static func testSpacingCompressionCalculation(_ suite: TestSuite) {
        // 10 items taking 680pt total with standard 10pt spacing
        // Available width left of notch is 640pt
        let compressedSpacing = NotchMenuBarCollisionAvoidance.recommendedSpacing(
            menuItemsCount: 10,
            totalMenuWidth: 680,
            availableWidth: 640
        )
        suite.expect(compressedSpacing < NotchMenuBarCollisionAvoidance.standardItemSpacing,
                     "Spacing is reduced under crowding")
        suite.expect(compressedSpacing >= NotchMenuBarCollisionAvoidance.minimumItemSpacing,
                     "Spacing stays above minimum safe threshold")
    }
}

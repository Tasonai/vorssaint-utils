// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Analyzes and prevents menu bar item collision with the physical MacBook display notch.
public enum NotchCollisionState: Equatable, Sendable {
    /// Safe clearance between menu items, status items, and the central notch.
    case clear(leftMargin: CGFloat, rightMargin: CGFloat)
    /// Left application menus extend into or across the central notch area.
    case menuOverlap(excessWidth: CGFloat)
    /// Right status items crowd into or across the central notch area.
    case statusOverlap(excessWidth: CGFloat)
    /// Tight proximity warning where margin before notch drops below minimum safe threshold.
    case denseCrowding(leftClearance: CGFloat, rightClearance: CGFloat)
}

/// Geometry math and policy for avoiding menu bar cutouts on 13", 14", and 16" MacBooks.
public enum NotchMenuBarCollisionAvoidance {
    /// Minimum comfortable margin between menu items and the notch edge (in points).
    public static let safeNotchMargin: CGFloat = 12.0

    /// Default item spacing in standard macOS menu bar.
    public static let standardItemSpacing: CGFloat = 10.0

    /// Minimum compressed item spacing allowable without visual degradation.
    public static let minimumItemSpacing: CGFloat = 4.0

    /// Evaluates the clearance between menu bar items and the hardware camera cutout.
    public static func evaluate(menuItems: [CGRect],
                                statusItems: [CGRect],
                                cameraRect: CGRect) -> NotchCollisionState {
        guard !menuItems.isEmpty || !statusItems.isEmpty else {
            return .clear(leftMargin: .infinity, rightMargin: .infinity)
        }

        // Calculate rightmost edge of application menu items
        let maxMenuX = menuItems.filter { $0.maxX <= cameraRect.maxX }
            .map(\.maxX)
            .max() ?? 0

        // Calculate leftmost edge of system status items
        let minStatusX = statusItems.filter { $0.minX >= cameraRect.minX }
            .map(\.minX)
            .min() ?? cameraRect.maxX + 500

        // Check if any menu item physically overlaps or crosses into cameraRect
        let menuOverlaps = menuItems.contains { item in
            item.intersects(cameraRect) || (item.maxX > cameraRect.minX && item.minX < cameraRect.maxX)
        }
        if menuOverlaps {
            let maxOverlapX = menuItems.map(\.maxX).max() ?? cameraRect.minX
            return .menuOverlap(excessWidth: max(0, maxOverlapX - cameraRect.minX))
        }

        // Check if any status item physically overlaps or crosses into cameraRect
        let statusOverlaps = statusItems.contains { item in
            item.intersects(cameraRect) || (item.minX < cameraRect.maxX && item.maxX > cameraRect.minX)
        }
        if statusOverlaps {
            let minOverlapX = statusItems.map(\.minX).min() ?? cameraRect.maxX
            return .statusOverlap(excessWidth: max(0, cameraRect.maxX - minOverlapX))
        }

        let leftClearance = cameraRect.minX - maxMenuX
        let rightClearance = minStatusX - cameraRect.maxX

        if leftClearance < safeNotchMargin || rightClearance < safeNotchMargin {
            return .denseCrowding(leftClearance: max(0, leftClearance),
                                 rightClearance: max(0, rightClearance))
        }

        return .clear(leftMargin: leftClearance, rightMargin: rightClearance)
    }

    /// Calculates the required spacing compression to fit all menu items left of the notch.
    public static func recommendedSpacing(menuItemsCount: Int,
                                          totalMenuWidth: CGFloat,
                                          availableWidth: CGFloat) -> CGFloat {
        guard menuItemsCount > 1 else { return standardItemSpacing }
        let gapsCount = CGFloat(menuItemsCount - 1)
        let pureContentWidth = totalMenuWidth - (gapsCount * standardItemSpacing)
        let targetSpacing = (availableWidth - pureContentWidth - safeNotchMargin) / gapsCount
        return min(standardItemSpacing, max(minimumItemSpacing, targetSpacing))
    }
}

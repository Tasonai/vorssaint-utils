// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Pure geometric calculations for Dynamic Island surface bounds, shifts and compact activity
/// sizing across hanging notches and floating capsules.
enum NotchSurfaceGeometryEngine {
    /// Extra horizontal clearance added to compact activity strips when privacy indicators are active.
    static let privacyIndicatorWidth: CGFloat = 14

    /// Returns the resting surface size on physical notch or floating displays.
    static func restingSurfaceSize(geometry: NotchGeometry, showsContent: Bool, hoverEmphasized: Bool) -> CGSize {
        let resting = geometry.restingSize(showsContent: showsContent)
        return hoverEmphasized ? NotchHoverEmphasis.size(from: resting, geometry: geometry) : resting
    }

    /// Returns the surface size for an active compact activity strip, taking into account
    /// asymmetric music wings, active privacy indicators, and pointer hover expansion.
    static func compactActivitySurfaceSize(baseSize: CGSize,
                                           geometry: NotchGeometry,
                                           namedMusicDiff: CGFloat?,
                                           isPrivacyActive: Bool,
                                           hoverEmphasized: Bool) -> CGSize {
        var size = baseSize
        if let diff = namedMusicDiff {
            size.width += diff
        }
        if isPrivacyActive {
            size.width += privacyIndicatorWidth
        }
        let reach = namedMusicDiff.map { $0 / 2 } ?? 0
        return hoverEmphasized
            ? NotchHoverEmphasis.size(from: size, geometry: geometry, reach: reach)
            : size
    }

    /// Computes horizontal shift of the island surface relative to the physical camera center.
    static func surfaceShift(floats: Bool,
                             fullscreenCompact: Bool,
                             hasCaptureControls: Bool,
                             expanded: Bool,
                             dragPlaceholder: Bool,
                             noticeShift: CGFloat?,
                             namedMusicShift: CGFloat?) -> CGFloat {
        guard !floats, !fullscreenCompact, !hasCaptureControls, !expanded, !dragPlaceholder else {
            return 0
        }
        if let noticeShift {
            return noticeShift
        }
        return namedMusicShift ?? 0
    }

    /// Adjusts compact strip width when privacy indicators are active.
    static func adjustedCompactStripWidth(_ baseWidth: CGFloat, isPrivacyActive: Bool) -> CGFloat {
        isPrivacyActive ? baseWidth + privacyIndicatorWidth : baseWidth
    }
}

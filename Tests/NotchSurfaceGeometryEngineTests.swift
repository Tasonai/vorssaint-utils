// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum NotchSurfaceGeometryEngineTests {
    static func run(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let physical = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: 180)
        let floating = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, silhouette: .capsule)

        let restingEmpty = NotchSurfaceGeometryEngine.restingSurfaceSize(
            geometry: physical,
            showsContent: false,
            hoverEmphasized: false
        )
        suite.expect(restingEmpty == physical.restingSize(showsContent: false),
                     "empty resting size matches bare camera cutout")

        let restingWithContent = NotchSurfaceGeometryEngine.restingSurfaceSize(
            geometry: physical,
            showsContent: true,
            hoverEmphasized: false
        )
        suite.expect(restingWithContent == physical.collapsed,
                     "resting size with content matches collapsed wings")

        let baseActivity = CGSize(width: 200, height: 32)
        let quietActivity = NotchSurfaceGeometryEngine.compactActivitySurfaceSize(
            baseSize: baseActivity,
            geometry: physical,
            namedMusicDiff: nil,
            isPrivacyActive: false,
            hoverEmphasized: false
        )
        suite.expect(quietActivity == baseActivity, "quiet activity maintains base size")

        let privacyActivity = NotchSurfaceGeometryEngine.compactActivitySurfaceSize(
            baseSize: baseActivity,
            geometry: physical,
            namedMusicDiff: nil,
            isPrivacyActive: true,
            hoverEmphasized: false
        )
        suite.expect(privacyActivity.width == baseActivity.width + NotchSurfaceGeometryEngine.privacyIndicatorWidth,
                     "privacy indicator adds clearance to compact activity")

        let musicDiffActivity = NotchSurfaceGeometryEngine.compactActivitySurfaceSize(
            baseSize: baseActivity,
            geometry: physical,
            namedMusicDiff: 20,
            isPrivacyActive: false,
            hoverEmphasized: false
        )
        suite.expect(musicDiffActivity.width == baseActivity.width + 20,
                     "asymmetric music wings expand activity surface")

        let shiftedNotice = NotchSurfaceGeometryEngine.surfaceShift(
            floats: false,
            fullscreenCompact: false,
            hasCaptureControls: false,
            expanded: false,
            dragPlaceholder: false,
            noticeShift: 15,
            namedMusicShift: 5
        )
        suite.expect(shiftedNotice == 15, "notice shift takes priority over music shift")

        let shiftedMusic = NotchSurfaceGeometryEngine.surfaceShift(
            floats: false,
            fullscreenCompact: false,
            hasCaptureControls: false,
            expanded: false,
            dragPlaceholder: false,
            noticeShift: nil,
            namedMusicShift: 8
        )
        suite.expect(shiftedMusic == 8, "music shift is applied when no notice is active")

        let floatingShift = NotchSurfaceGeometryEngine.surfaceShift(
            floats: floating.floats,
            fullscreenCompact: false,
            hasCaptureControls: false,
            expanded: false,
            dragPlaceholder: false,
            noticeShift: 15,
            namedMusicShift: 8
        )
        suite.expect(floatingShift == 0, "floating capsule never shifts horizontally")

        suite.expect(NotchSurfaceGeometryEngine.adjustedCompactStripWidth(100, isPrivacyActive: false) == 100,
                     "strip width unchanged without privacy")
        suite.expect(NotchSurfaceGeometryEngine.adjustedCompactStripWidth(100, isPrivacyActive: true) == 114,
                     "strip width widened with privacy")
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShelfEdgeDragMonitorTests {
    static func run(_ suite: TestSuite) {
        let monitor = ShelfEdgeDragMonitor()
        let screens = [
            ShelfEdgeScreen(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))
        ]

        // 1. Initial state
        suite.expect(!monitor.isPeeking, "Monitor starts not peeking")
        suite.expect(monitor.edgeDwellMatch == nil, "Initial dwell match is nil")
        suite.expect(monitor.edgeDwellStart == nil, "Initial dwell start is nil")

        // 2. Cursor in center of screen -> Action.none
        let centerPoint = CGPoint(x: 960, y: 500)
        let centerAction = monitor.handleDrag(at: centerPoint, now: 100.0, isVisible: false, screens: screens)
        suite.expect(centerAction == .none, "Center screen drag returns none")
        suite.expect(monitor.edgeDwellMatch == nil, "Dwell is nil when away from edges")

        // 3. Cursor in left edge trigger zone (e.g. x: 50) -> dwell starts
        let edgePoint = CGPoint(x: 50, y: 500)
        let dwellAction1 = monitor.handleDrag(at: edgePoint, now: 100.0, isVisible: false, screens: screens)
        suite.expect(dwellAction1 == .none, "First drag event starts dwell without immediate summon")
        suite.expect(monitor.edgeDwellMatch != nil && monitor.edgeDwellMatch?.edge == .left,
                     "Left edge dwell is recorded")
        suite.expect(monitor.edgeDwellStart == 100.0, "Dwell start time is recorded")

        // 4. Cursor still in edge zone before required dwell (e.g. 0.05s later) -> still .none
        let dwellAction2 = monitor.handleDrag(at: edgePoint, now: 100.05, isVisible: false, screens: screens)
        suite.expect(dwellAction2 == .none, "Short dwell does not trigger summon")

        // 5. Cursor dwelled long enough (0.16s later) -> Action.summon
        let summonAction = monitor.handleDrag(at: edgePoint, now: 100.16, isVisible: false, screens: screens)
        switch summonAction {
        case let .summon(match, mouse):
            suite.expect(match.edge == .left, "Summon action has left edge match")
            suite.expect(mouse == edgePoint, "Summon action captures mouse point")
        default:
            suite.expect(false, "Summon action was expected after 0.16s dwell")
        }

        // 6. Start peek
        if let match = monitor.edgeDwellMatch {
            monitor.startPeek(match)
            suite.expect(monitor.isPeeking, "Monitor reports isPeeking after startPeek")
            suite.expect(monitor.edgePeekMatch == match, "Peek match is saved")
            suite.expect(monitor.edgeDwellMatch == nil, "Dwell match is cleared on peek start")
        }

        // 7. While peeking, cursor within retreat distance (330pt) -> Action.none
        let nearPoint = CGPoint(x: 200, y: 500)
        let nearAction = monitor.handleDrag(at: nearPoint, now: 101.0, isVisible: true, screens: screens)
        suite.expect(nearAction == .none, "Cursor within retreat distance holds peek open")

        // 8. While peeking, cursor retreats far into center (e.g. x: 500 > 330) -> Action.retract
        let farPoint = CGPoint(x: 500, y: 500)
        let retractAction = monitor.handleDrag(at: farPoint, now: 101.5, isVisible: true, screens: screens)
        suite.expect(retractAction == .retract, "Retreating cursor triggers retract action")

        // 9. Graduate peek
        let graduatedMatch = monitor.graduatePeek()
        suite.expect(graduatedMatch?.edge == .left, "Graduated peek returns previous match")
        suite.expect(!monitor.isPeeking, "Monitor no longer peeking after graduation")

        // 10. Frame math calculations
        let visible = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let contentSize = CGSize(width: 300, height: 200)
        let leftMatch = ShelfEdgeMatch(edge: .left, screen: visible)
        let rightMatch = ShelfEdgeMatch(edge: .right, screen: visible)

        let leftPeekFrame = ShelfEdgeDragMonitor.peekFrame(contentSize: contentSize, match: leftMatch,
                                                           mouse: CGPoint(x: 10, y: 500), visible: visible)
        suite.expect(leftPeekFrame.width == 300 && leftPeekFrame.height == 200, "Peek frame has correct size")
        suite.expect(leftPeekFrame.minX < visible.minX, "Left peek frame extends off-screen to the left")

        let leftRevealFrame = ShelfEdgeDragMonitor.revealFrame(contentSize: contentSize, match: leftMatch,
                                                               currentY: leftPeekFrame.minY, visible: visible)
        suite.expect(leftRevealFrame.minX == visible.minX + 8, "Left revealed frame is docked at left + 8pt")

        let rightPeekFrame = ShelfEdgeDragMonitor.peekFrame(contentSize: contentSize, match: rightMatch,
                                                            mouse: CGPoint(x: 1910, y: 500), visible: visible)
        suite.expect(rightPeekFrame.maxX > visible.maxX, "Right peek frame extends off-screen to the right")

        let rightRevealFrame = ShelfEdgeDragMonitor.revealFrame(contentSize: contentSize, match: rightMatch,
                                                                currentY: rightPeekFrame.minY, visible: visible)
        suite.expect(rightRevealFrame.maxX == visible.maxX - 8, "Right revealed frame is docked at right - 8pt")

        // 11. Reset
        monitor.startPeek(leftMatch)
        suite.expect(monitor.isPeeking, "Peeking before reset")
        monitor.reset()
        suite.expect(!monitor.isPeeking, "Not peeking after reset")
    }
}

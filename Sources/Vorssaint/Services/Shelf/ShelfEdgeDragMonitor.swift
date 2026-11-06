// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Manages edge-drag gesture detection and layout for the Shelf panel.
///
/// When a file drag dwells near the left or right edge of a screen,
/// `ShelfEdgeDragMonitor` computes trigger zones, handles grace periods,
/// and calculates peek and reveal frames for the panel.
final class ShelfEdgeDragMonitor {
    enum Action: Equatable {
        case none
        case summon(match: ShelfEdgeMatch, mouse: CGPoint)
        case retract
    }

    /// The edge and screen a drag is currently dwelling near before triggering a peek.
    private(set) var edgeDwellMatch: ShelfEdgeMatch?
    private(set) var edgeDwellStart: TimeInterval?

    /// Active match while the panel is peeking from an edge.
    private(set) var edgePeekMatch: ShelfEdgeMatch?
    private var edgePeekEndWork: DispatchWorkItem?

    var isPeeking: Bool {
        edgePeekMatch != nil
    }

    /// Evaluates current mouse drag position and returns whether to summon, retract, or do nothing.
    func handleDrag(at mouse: CGPoint, now: TimeInterval, isVisible: Bool, screens: [ShelfEdgeScreen]) -> Action {
        if let edgePeekMatch {
            // Check if cursor retreated past the retreat threshold
            if !ShelfEdgeDragSupport.stillNear(edgePeekMatch, point: mouse, distance: ShelfEdgeDragSupport.retreatDistance) {
                return .retract
            }
            return .none
        }

        guard !isVisible else { return .none }

        guard let matched = ShelfEdgeDragSupport.match(at: mouse, screens: screens,
                                                       distance: ShelfEdgeDragSupport.triggerDistance) else {
            edgeDwellMatch = nil
            edgeDwellStart = nil
            return .none
        }

        if edgeDwellMatch != matched {
            edgeDwellMatch = matched
            edgeDwellStart = now
        }

        guard let edgeDwellStart, ShelfEdgeDragSupport.hasDwelled(since: edgeDwellStart, now: now) else {
            return .none
        }

        return .summon(match: matched, mouse: mouse)
    }

    /// Marks the start of a peek.
    func startPeek(_ match: ShelfEdgeMatch) {
        edgePeekMatch = match
        edgeDwellMatch = nil
        edgeDwellStart = nil
        cancelGracePeriod()
    }

    /// Ends an active peek and cleans up state.
    func retractPeek() {
        cancelGracePeriod()
        edgePeekMatch = nil
    }

    /// Graduates the peek to an ordinary panel (e.g. after a drop lands), returning the previous match.
    @discardableResult
    func graduatePeek() -> ShelfEdgeMatch? {
        cancelGracePeriod()
        let match = edgePeekMatch
        edgePeekMatch = nil
        return match
    }

    /// Schedules a short grace period before executing a retract, allowing a landing drop to claim the panel.
    func scheduleGraceRetract(after delay: TimeInterval = 0.15, onRetract: @escaping () -> Void) {
        guard edgePeekMatch != nil, edgePeekEndWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.edgePeekEndWork = nil
            onRetract()
        }
        edgePeekEndWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func cancelGracePeriod() {
        edgePeekEndWork?.cancel()
        edgePeekEndWork = nil
    }

    func reset() {
        cancelGracePeriod()
        edgeDwellMatch = nil
        edgeDwellStart = nil
        edgePeekMatch = nil
    }

    // MARK: - Frame Positioning

    /// Calculates initial peeking frame (partially off-screen).
    static func peekFrame(contentSize: CGSize, match: ShelfEdgeMatch, mouse: CGPoint, visible: CGRect) -> NSRect {
        let onScreenWidth = (contentSize.width / 3).rounded()
        let x: CGFloat
        switch match.edge {
        case .left: x = visible.minX - contentSize.width + onScreenWidth
        case .right: x = visible.maxX - onScreenWidth
        }
        var y = mouse.y - contentSize.height / 2
        y = min(max(visible.minY + 8, y), visible.maxY - contentSize.height - 8)
        return NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height)
    }

    /// Calculates revealed frame (fully on-screen).
    static func revealFrame(contentSize: CGSize, match: ShelfEdgeMatch, currentY: CGFloat, visible: CGRect) -> NSRect {
        let x: CGFloat
        switch match.edge {
        case .left: x = visible.minX + 8
        case .right: x = visible.maxX - contentSize.width - 8
        }
        let y = min(max(visible.minY + 8, currentY), visible.maxY - contentSize.height - 8)
        return NSRect(x: x, y: y, width: contentSize.width, height: contentSize.height)
    }

    /// Resolves visible frame for a screen rect.
    static func visibleFrame(for screenFrame: CGRect) -> CGRect {
        NSScreen.screens.first { $0.frame == screenFrame }?.visibleFrame ?? screenFrame
    }
}

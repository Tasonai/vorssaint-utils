# Dynamic Island Ultra: Fluid Morphing, Split Island & Haptic Acoustics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Elevate Vorssaint Dynamic Island with elastic spring morphing (squash & stretch), split dual-activity capsule, and tactile Force Touch / acoustic feedback.

**Architecture:** CoreAnimation CASpringAnimation / SwiftUI spring integration in `NotchWindowHost` and `NotchView`, dual-pill rendering in `NotchCapsuleViews`, and a unified `NotchFeedbackService` integrating `NSHapticFeedbackManager` and subtle system sound clicks.

**Tech Stack:** Swift, SwiftUI, AppKit, CoreAnimation, NSHapticFeedbackManager, AudioToolbox.

**Spec:** `docs/superpowers/specs/2026-11-05-dynamic-island-fluid-design.md`

## Global Constraints
- Target macOS 14+ through macOS 26.
- 0% CPU at idle, ProMotion 120 FPS during morphing.
- All existing notch test suite checks (`67,229+ checks`) must remain 100% passing.
- Default settings must feel natural, non-intrusive, and configurable in island settings.

---

### Task 1: Haptic & Acoustic Feedback Engine (`NotchFeedbackService.swift`)

**Files:**
- Create: `Sources/Vorssaint/Services/Notch/NotchFeedbackService.swift`
- Create: `Tests/NotchFeedbackTests.swift`
- Modify: `Sources/Vorssaint/Core/Defaults.swift`
- Modify: `build.sh`

- [ ] **Step 1: Define default keys in `Defaults.swift`**
  - Add `notchHapticsEnabled` (default `true`)
  - Add `notchAcousticsEnabled` (default `true`)
  - Add `notchSplitCapsuleEnabled` (default `true`)

- [ ] **Step 2: Create `NotchFeedbackService.swift`**
  - Implement `performOpen()` (haptic `.alignment` + subtle click)
  - Implement `performClose()` (haptic `.alignment`)
  - Implement `performSelection()` (haptic `.levelChange`)
  - Guard calls by user defaults and `NSHapticFeedbackManager` availability.

- [ ] **Step 3: Create unit test `NotchFeedbackTests.swift` and add to `build.sh`**
  - Verify feedback methods execute safely without crash on headless/test runners.

- [ ] **Step 4: Run tests and commit**
  - Verify build: `build.sh --test-suite=notch`
  - Git commit: `feat(notch): add NotchFeedbackService for haptic and acoustic feedback`

---

### Task 2: Fluid Spring Morphing in `NotchWindowHost.swift` & `NotchView.swift`

**Files:**
- Modify: `Sources/Vorssaint/Services/Notch/NotchWindowHost.swift`
- Modify: `Sources/Vorssaint/UI/Notch/NotchView.swift`

- [ ] **Step 1: Tune spring animation curve in `NotchWindowHost.swift`**
  - Adjust expansion spring parameters to `response: 0.38`, `dampingFraction: 0.72` for snappy, fluid bounce.
  - Implement subtle vertical leading (squash & stretch) during frame transition.

- [ ] **Step 2: Wire haptic & sound feedback**
  - Trigger `NotchFeedbackService.shared.performOpen()` on island expansion start.
  - Trigger `NotchFeedbackService.shared.performClose()` when island collapses into capsule.

- [ ] **Step 3: Run tests and verify zero regression**
  - Verify `build.sh --test-suite=notch`

- [ ] **Step 4: Commit**
  - Git commit: `feat(notch): implement fluid spring dynamics and morphing feedback`

---

### Task 3: Split Island Dual Activity Presentation

**Files:**
- Modify: `Sources/Vorssaint/Services/Notch/NotchService.swift`
- Modify: `Sources/Vorssaint/UI/Notch/NotchCapsuleViews.swift`

- [ ] **Step 1: Secondary activity detection in `NotchService.swift`**
  - Detect when primary activity (e.g. music playing) and secondary activity (active AI agent or running timer) are active at the same time.

- [ ] **Step 2: Implement `NotchCapsuleSplitView` in `NotchCapsuleViews.swift`**
  - Left pill: mini album art or live equalizer (width ~68pt).
  - Center gap: clean transparent spacer (8pt).
  - Right pill: secondary indicator (pulsing atom for Antigravity or timer badge).
  - Tap on left pill routes to music, tap on right pill routes to agent/timer.

- [ ] **Step 3: Run tests and commit**
  - Verify `build.sh --test-suite=notch`
  - Git commit: `feat(notch): add Split Island multi-activity capsule presentation`

---

### Task 4: Settings Controls, App Assembly & Live Verification

**Files:**
- Modify: `Sources/Vorssaint/UI/Settings/NotchSettingsView.swift` (or controls)
- Modify: `Sources/Vorssaint/Core/NotchSettingsStrings.swift`

- [ ] **Step 1: Add toggles in Island Settings**
  - Add "Тактильный отклик (Force Touch)" and "Мягкие звуки защёлкивания".
  - Add "Раздельный остров при двух активностях".

- [ ] **Step 2: Run full build and test suite**
  - Run `build.sh --test-suite=notch`
  - Run `./build.sh --install`

- [ ] **Step 3: Restart app and verify live on desktop**
  - Kill and restart `/Applications/Vorssaint.app`.
  - Verify fluid spring morphing, split pill with music + agent, and haptic feedback.

- [ ] **Step 4: Final commit**
  - Git commit: `feat(notch): polish Dynamic Island with fluid springs, split capsule and haptics`

# Architecture Review: Vorssaint (2026-11-06)

Architecture check-in performed according to the `improve-architecture` guidelines.

## Survey Summary

- **Codebase size:** ~315,000 lines across `Sources/`
- **Largest Swift files:**
  1. `Sources/Vorssaint/Services/Notch/NotchService.swift` (5,256 lines)
  2. `Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift` (3,843 lines)
  3. `Sources/Vorssaint/Services/CommandBar/CommandBarService.swift` (3,717 lines)
  4. `Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift` (3,258 lines)
  5. `Sources/Vorssaint/Services/Notch/NotchSupport.swift` (3,215 lines)
  6. `Sources/Vorssaint/Services/QuickTools/ScreenshotSupport.swift` (3,171 lines)
  7. `Sources/Vorssaint/Services/WindowLayout/WindowLayoutService.swift` (3,169 lines)
  8. `Sources/Vorssaint/Services/Display/BrightnessService.swift` (3,024 lines)
  9. `Sources/Vorssaint/Services/Shelf/ShelfService.swift` (2,781 lines)
- **Top git-frequency files (last 30 days):**
  - `ShelfTilesView.swift`, `ShelfView.swift`, `ShelfService.swift` (Dropshelf interactions)
  - `NotchService.swift`, `NotchCapsuleViews.swift`, `NotchSupport.swift` (Dynamic Island activities & indicators)

---

## 1. Dynamic Island Surface Sizing Engine (`NotchSurfaceGeometryEngine`) [Strong]

- **Files:** `Sources/Vorssaint/Services/Notch/NotchService.swift` (5,256 lines), `Sources/Vorssaint/Services/Notch/NotchSupport.swift` (3,215 lines)
- **Signal:** File passes 5,000 lines. Pure geometric calculations (`surfaceSize`, `surfaceShift`, `capsuleSurfaceSize`, `compactStripSize`) reside inside a massive `@MainActor` stateful service. `Tests/generate_sources.py` currently has to perform fragile string manipulation to carve out `surfaceSize` for test harnesses.
- **Problem:** When changing or adding island behaviors (e.g., privacy indicators, new compact activities, banner notices), developers must edit `NotchService.swift`. The surface sizing logic requires reading 8 different flags and delegates (`geometry`, `fullscreenCompact`, `captureControls`, `expanded`, `dragPlaceholder`, `notice`, `compactActivity`, `idleContent`, `isPrivacyIndicatorActive`). Because this logic is embedded in the service, testing sizing contracts independently of NSWindows or CoreAudio requires source extraction hacks.
- **Proposal:**
  Extract a pure, stateless layout engine `NotchSurfaceGeometryEngine`:
  ```swift
  struct NotchSurfaceLayoutInput {
      let geometry: NotchGeometry
      let state: NotchSurfaceState // resting, peeking, compact, expanded, notice, drag
      let idleContent: NotchIdleContent
      let compactActivity: NotchCompactActivity?
      let compactCompanion: NotchCompactActivity?
      let isPrivacyActive: Bool
      let hoverEmphasized: Bool
  }

  enum NotchSurfaceGeometryEngine {
      static func surfaceSize(for input: NotchSurfaceLayoutInput) -> CGSize
      static func surfaceShift(for input: NotchSurfaceLayoutInput) -> CGFloat
  }
  ```
- **Benefits:**
  - **Locality:** All sizing rules (hanging notch wings, floating capsule, notice expansions, hover emphasis) are localized in one dedicated file.
  - **Leverage:** Sizing calculations become 100% pure functions: easy to unit test with parameter matrices without mocking NSPanels, MASShortcut, or CoreAudio.
  - **Test Simplification:** Eliminates the need for source-code regex splicing in `Tests/generate_sources.py`.
- **Proof of same behavior:**
  - `build.sh --test-suite=notch` (all 67,246 checks must pass unchanged).
  - Exact equality of `service.surfaceSize` across all permutations of idle, compact, expanded, and notice states.
- **Plan:**
  1. Commit 1: Create `NotchSurfaceGeometryEngine.swift` with pure input struct and calculation methods; add unit test suite `NotchSurfaceGeometryEngineTests.swift`.
  2. Commit 2: Route `NotchService.surfaceSize`, `capsuleSurfaceSize`, and `surfaceShift` through `NotchSurfaceGeometryEngine`.
  3. Commit 3: Clean up `generate_sources.py` to directly use the pure engine rather than string replacement.

---

## 2. Dropshelf File Drag & Drop Coordinator (`ShelfDragCoordinator`) [Worth exploring]

- **Files:** `Sources/Vorssaint/Services/Shelf/ShelfService.swift` (2,781 lines), `Sources/Vorssaint/UI/Shelf/ShelfTilesView.swift` (1,840 lines)
- **Signal:** Highest git churn in the last 30 days (6 commits to `ShelfTilesView`, 5 to `ShelfView`, 4 to `ShelfService`).
- **Problem:** `ShelfService` combines item storage (JSON serialization, file bookmarks, metadata extraction) with real-time drag interaction (mouse drag tracking, internal item reordering, drag-out pasteboard generation, and drop dismissal logic).
- **Proposal:**
  Extract a dedicated `ShelfDragCoordinator`:
  ```swift
  final class ShelfDragCoordinator {
      func beginInternalDrag(from index: Int, item: ShelfItem)
      func updateDragLocation(_ point: CGPoint) -> ShelfDropTarget?
      func completeDrag(with result: ShelfDragResult) -> ShelfDragCompletionDecision
      func pasteboardWriter(for item: ShelfItem) -> NSPasteboardWriting
  }
  ```
- **Benefits:**
  - Isolates drag-and-drop state machine from shelf storage and view management.
  - Fixes regressions where shelf dismissal logic during external drops conflicts with internal reordering.
- **Proof of same behavior:**
  - `build.sh --test-suite=shelf` and `ShelfDragCompletionTests.swift`.
- **Plan:**
  1. Commit 1: Introduce `ShelfDragCoordinator` and test state transitions.
  2. Commit 2: Delegate drag callbacks in `ShelfService` to `ShelfDragCoordinator`.

---

## 3. Per-App Audio Tap Lifecycle Registry (`MixerTapRegistry`) [Speculative]

- **Files:** `Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift` (3,843 lines)
- **Signal:** File over 3,800 lines. Heavy concurrency across HAL queue and main thread.
- **Problem:** Audio tap installation, buffer format negotiation, device UID matching, and level metering are tightly coupled with the application list and SwiftUI presentation.
- **Proposal:**
  Decouple low-level CoreAudio HAL tap lifecycle into `MixerTapRegistry`.
- **Benefits:**
  - Separates dangerous low-level CoreAudio C pointer operations from SwiftUI state publishing.
- **Proof of same behavior:**
  - `build.sh --test-suite=mixer` and manual volume test.

---

## Top Recommendation

**Candidate 1: Dynamic Island Surface Sizing Engine (`NotchSurfaceGeometryEngine`)** [Strong]
- Solves the single biggest maintenance bottleneck in the project (`NotchService.swift` at 5,256 lines).
- Directly removes fragile test-generation string splicing in `Tests/generate_sources.py`.
- Low risk, high payoff, proven via existing 67,246 notch unit tests.

---

## Considered, Not Recommended

- **Refactoring `CommandBarService.swift`**: While large (3,717 lines), its sub-services (`CommandBarMath`, `CommandBarUnits`, `CommandBarColors`) are already well separated into dedicated files. The main file primarily acts as a coordinator.
- **Splitting `Defaults.swift` (2,816 lines)**: It is mostly constant key declarations and standard accessors. Splitting it provides low architectural leverage.

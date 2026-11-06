# Architecture Review: Vorssaint - Check-in 2 (2026-11-06)

Second architecture check-in following the successful extraction of `NotchSurfaceGeometryEngine`.

## Survey Summary

- **Top active churn files:**
  - `Sources/Vorssaint/UI/Shelf/ShelfTilesView.swift` (6 commits)
  - `Sources/Vorssaint/UI/Shelf/ShelfView.swift` (5 commits)
  - `Sources/Vorssaint/Services/Shelf/ShelfService.swift` (4 commits, 2,781 lines)
  - `Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift` (3,843 lines)
- **Focus Area:** The Dropshelf subsystem (`ShelfService.swift`), which is the highest-churn service after Dynamic Island.

---

## 1. Extract Shelf Item Domain Model & Storage (`ShelfItem` & `ShelfStorageEngine`) [Strong]

- **Files:** `Sources/Vorssaint/Services/Shelf/ShelfService.swift` (2,781 lines)
- **Signal:** `ShelfService.Item` is a 200+ line nested type inside `ShelfService`. Sibling components like `ShelfActionsEngine`, `SystemScreenshotWatcher`, and `ShelfTilesView` must import or navigate `ShelfService` just to work with shelf items.
- **Problem:** Adding capabilities to shelf items (such as action metadata, OCR text, or bookmark resolution) swells `ShelfService.swift`. Persistence encoding/decoding is entangled with the service's published arrays.
- **Proposal:**
  Extract `ShelfItem.swift` as a first-class domain model, keeping `typealias ShelfService.Item = ShelfItem` for full backward compatibility:
  ```swift
  struct ShelfItem: Identifiable, Equatable, Hashable {
      let id: UUID
      var title: String
      var url: URL?
      var kind: ShelfItemKind
      var bookmarkData: Data?
      var isPinned: Bool
      // Thumbnail & content properties...
  }
  ```
- **Benefits:**
  - **Depth & Leverage:** Makes `ShelfItem` a reusable value type across all shelf features.
  - **Locality:** Bookmark creation and validation logic lives with the item, not in the service.
- **Proof of same behavior:**
  - All existing shelf tests (`ShelfSupportTests`, `ShelfDragCompletionTests`) compile and pass identically.
- **Plan:**
  1. Commit 1: Move `ShelfItem` to `Sources/Vorssaint/Services/Shelf/ShelfItem.swift`, declare typealias in `ShelfService`.
  2. Commit 2: Verify `build.sh --test-suite=notch` and full build.

---

## 2. Extract Screen Edge & Dock Drag Monitor (`ShelfEdgeDragMonitor`) [Strong]

- **Files:** `Sources/Vorssaint/Services/Shelf/ShelfService.swift` (2,781 lines)
- **Signal:** Lines 518–930 (over 410 lines) are dedicated to global mouse drag monitoring, dock process detection, edge proximity math, and edge peek reveal timers.
- **Problem:** Low-level AppKit event monitoring (`NSEvent.addGlobalMonitorForEvents`) and dock hit-testing clutter the higher-level service that manages open shelves and collections.
- **Proposal:**
  Extract `ShelfEdgeDragMonitor` to manage the event tap, watchdog timer, and edge proximity calculations, reporting transitions via lightweight callbacks.
- **Benefits:**
  - Drops 400+ lines from `ShelfService.swift`.
  - Can be paused/resumed cleanly without touching shelf item arrays.
- **Proof of same behavior:**
  - Edge peek and drag activation contracts pass.

---

## 3. Extract Mixer CoreAudio HAL Tap Registry (`MixerTapRegistry`) [Worth exploring]

- **Files:** `Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift` (3,843 lines)
- **Signal:** File over 3,800 lines. CoreAudio HAL C-APIs mixed with volume curves and slider UI state.

---

## Top Recommendation

**Candidate 1: Extract Shelf Item Domain Model (`ShelfItem`)** [Strong]
- Decouples the core domain entity from the 2,780-line service.
- Foundation for all future Dropshelf improvements (quick actions, drag coordinators, persistence).
- Zero regression risk; 100% backward compatible via typealias.

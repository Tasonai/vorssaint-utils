# Vorssaint Architecture

## Overview
Vorssaint is a native macOS utility combining Dynamic Island (Notch), Shelf (Dropshelf), Command Bar, and quick system tools into a lightweight, high-performance menubar and screen overlay application.

## Layers & Structure

```
+-------------------------------------------------------------+
| UI (SwiftUI Views & AppKit Window Panels)                   |
| - NotchView, NotchCapsuleViews, NotchPrivacyView            |
| - ShelfView, ShelfTilesView                                 |
| - CommandBarView, MenuPanelView                             |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
| Coordination & Services (Observable Models)                 |
| - NotchService, ShelfService, CommandBarService             |
| - CameraMicrophonePrivacyMonitor, MicMuteService            |
| - NotchMusicService, NotchTimerService                      |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
| Pure Engines & Support Models (Stateless, Testable)         |
| - NotchSurfaceGeometryEngine: Island bounds, shifts, sizing |
| - ShelfItem: Core shelf item value type, payloads & piles   |
| - ShelfActionsEngine: File transforms, OCR, ZIP, metadata   |
| - NotchLayout, NotchCapsuleLayout: SF Font & drop metrics   |
| - MicMuteSupport: Claims, device volume levels              |
+-------------------------------------------------------------+
                               |
                               v
+-------------------------------------------------------------+
| Hardware HAL, System APIs & Core Frameworks                 |
| - CoreAudio (HAL listeners, input devices, aggregate taps)  |
| - AVFoundation (AVCaptureDevice in-use detection)           |
| - Vision, PDFKit, Cocoa, IOKit                              |
+-------------------------------------------------------------+
```

## Key Architectural Seams

1. **NotchSurfaceGeometryEngine (`Sources/Vorssaint/Services/Notch/NotchSurfaceGeometryEngine.swift`)**:
   - Decouples island surface size, horizontal shift, and compact activity strip widths from `NotchService` state.
   - Evaluated as pure functions given immutable geometry and state flags.
   - Fully testable in headless test suites without window or hardware dependencies.

2. **Privacy Monitoring (`Sources/Vorssaint/Services/Notch/CameraMicrophonePrivacyMonitor.swift`)**:
   - Isolates real-time CoreAudio and AVFoundation device in-use event monitoring.
   - Provides published states to Dynamic Island views without coupling audio HAL to UI layout.

3. **Shelf Engine (`Sources/Vorssaint/Services/Shelf/ShelfActionsEngine.swift`)**:
   - Isolates non-UI file actions (ZIP compression, image format conversion, Vision OCR, EXIF stripping) behind static utility methods.

4. **Shelf Item Domain Model (`Sources/Vorssaint/Services/Shelf/ShelfItem.swift`)**:
   - Promotes the shelf item entity out of the 2,700-line `ShelfService` into an independent value type.
   - Provides recursive leaf counts, payload discrimination (file, text, link, batch), and content equality.
   - Preserves 100% backward compatibility via `typealias ShelfService.Item = ShelfItem`.

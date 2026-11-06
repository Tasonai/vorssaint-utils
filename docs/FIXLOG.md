# Architecture Fix Log

## 2026-11-06: Dynamic Island Surface Geometry Extraction
- **Issue**: `NotchService.swift` (5,256 lines) mixed stateful hardware coordination with pure geometric layout math (`surfaceSize`, `surfaceShift`, `compactStripSize`). Tests required source code regex slicing to test surface sizes in isolation.
- **Fix**: Extracted `NotchSurfaceGeometryEngine` as a pure, stateless computation engine. Added direct contract tests in `NotchSurfaceGeometryEngineTests.swift`.
- **Rule**: Pure geometry, layout metrics, and transform calculations must reside in stateless engine types, not inside stateful `@MainActor` services.

## 2026-11-06: Shelf Item Domain Model Promotion
- **Issue**: `ShelfService.Item` was tightly coupled inside `ShelfService.swift` (2,781 lines), requiring all shelf UI and action engines to reference the monolithic service.
- **Fix**: Extracted `ShelfItem` into an independent domain model file `Sources/Vorssaint/Services/Shelf/ShelfItem.swift` with `typealias ShelfService.Item = ShelfItem`. Added unit tests in `Tests/ShelfItemTests.swift`.
- **Rule**: Core domain entities and payload models must be declared as standalone value types rather than nested types within service coordinators.

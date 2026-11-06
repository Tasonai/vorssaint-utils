# Architecture Fix Log

## 2026-11-06: Dynamic Island Surface Geometry Extraction
- **Issue**: `NotchService.swift` (5,256 lines) mixed stateful hardware coordination with pure geometric layout math (`surfaceSize`, `surfaceShift`, `compactStripSize`). Tests required source code regex slicing to test surface sizes in isolation.
- **Fix**: Extracted `NotchSurfaceGeometryEngine` as a pure, stateless computation engine. Added direct contract tests in `NotchSurfaceGeometryEngineTests.swift`.
- **Rule**: Pure geometry, layout metrics, and transform calculations must reside in stateless engine types, not inside stateful `@MainActor` services.

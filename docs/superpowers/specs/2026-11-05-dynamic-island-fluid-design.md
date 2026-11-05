# Dynamic Island Ultra: Fluid Morphing, Split Island & Haptic Acoustics

**Date:** 2026-11-05  
**Status:** Approved by User  
**Target:** Vorssaint macOS Dynamic Island  

---

## 1. Intent & The "Why"
Make Vorssaint Dynamic Island feel more organic, tactile, and technologically refined than Apple's native macOS interface. Rather than rigid geometric window transitions, the Island morphs elastically like a living drop of liquid (squash & stretch), supports true dual-activity split presentation (e.g. Music on the left + Antigravity/Timer on the right), and provides subtle physical acoustic and Force Touch haptic confirmation upon expansion and interaction.

---

## 2. Goals, Non-Goals & Anti-Goals

### Goals
- **Elastic Squash & Stretch**: Natural spring dynamics on open/close with a subtle overshoot and settling bounce at 120 FPS ProMotion.
- **Split Island in Resting State**: When two live activities run concurrently (e.g. music playing and an AI agent active, or timer counting down), the capsule organically splits into two distinct visual pills separated by a clean gap.
- **Tactile Feedback & Micro-Acoustics**: Haptic clicks via `NSHapticFeedbackManager` (on trackpads with Force Touch) and subtle sound clicks upon snap/toggle, with user preference control in Dynamic Island settings.

### Non-Goals
- Replacing the standard section views or gallery layouts.
- Heavy 3D mesh rendering that causes GPU battery drain.

### Anti-Goals
- Never cause perceptible latency or lag (>16ms per frame) during morphing.
- Never drain CPU or battery while the Island is resting (0% CPU impact).
- Never break existing notch geometry tests or unit test suites.

---

## 3. Constraints
- **Operating System**: macOS 14+ through macOS 26.
- **Display Compatibility**: Both notch displays (MacBook Pro) and non-notch displays (simulated island).
- **Quality Standard**: All 67,229 tests in `build.sh --test-suite=notch` must remain green.

---

## 4. Approaches Considered

### Approach 1: Native CoreAnimation Springs + NSHapticFeedback + Split Capsule (Chosen)
- Uses `CASpringAnimation` and SwiftUI `.spring(response: 0.38, dampingFraction: 0.72)` for true physical spring behavior.
- Renders Split Island natively in `NotchCapsuleViews.swift` using dual capsule subviews when secondary activity is detected.
- Emits haptic events using macOS native `NSHapticFeedbackManager.defaultPerformer` and gentle system sound feedback.
- **Decision**: Chosen for 0% idle overhead, high battery efficiency, and native Cocoa/SwiftUI feel.

### Approach 2: Metal Shader Mesh Deformation (Dismissed)
- Rendering fluid metaballs with custom Metal fragment shaders.
- **Dismissed**: High power consumption, risk of frame drops, unnecessary complexity for desktop utility.

---

## 5. Architecture & Implementation Specifics

### A. Fluid Spring Dynamics (`NotchWindowHost.swift` & `NotchView.swift`)
- Morphing transition with responsive spring curves:
  - Open response: `0.38s`, damping: `0.72`, initial velocity scale.
  - Close response: `0.30s`, damping: `0.82`.
- Squash & stretch factor: during expansion, vertical expansion slightly leads horizontal expansion by 5–8% before settling to the target frame.

### B. Split Island Multi-Activity Layout (`NotchCapsuleViews.swift`)
- When primary activity (e.g., Music playing) and secondary activity (e.g., active AI agent or running Timer) are active simultaneously:
  - Left Pill: Music cover art / mini equalizer bars (width: ~68–74pt).
  - Gap: Transparent spacer (width: ~10pt).
  - Right Pill: Agent pulsing atom glyph or timer remaining time (width: ~48–56pt).
- Clicking either pill expands into the respective section directly.

### C. Haptic & Acoustic Feedback Engine (`NotchFeedbackService.swift`)
- `NotchFeedbackService`:
  - `performHaptic(.alignment)` on snap open/close.
  - `performHaptic(.levelChange)` on quick-access / section switch.
  - `playSubtleClick()`: Plays light click sound if enabled in settings (`DefaultsKey.notchAcousticFeedbackEnabled`, default `true`).
  - Added toggle in Dynamic Island Settings controls.

---

## 6. What's Next
Proceed to execution planning with `superpowers:writing-plans`.

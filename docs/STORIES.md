# Project Stories & Backlog

## Milestone 1: Dynamic Island & Motion Polish

- [x] **Story 1.1**: Haptic & acoustic micro-feedback on Island open/close (`NotchFeedbackService`)
  - **UX**: Subtle Force Touch click and audio click when Island expands/retracts.
  - **Status**: done

- [x] **Story 1.2**: Privacy Indicators for Camera & Microphone in Dynamic Island
  - **UX**: Green glowing dot for camera, orange dot for microphone on notch wings and floating capsule. 1-click mute toggle.
  - **Status**: done

- [x] **Story 1.3**: Extract `NotchSurfaceGeometryEngine` from `NotchService`
  - **Arch**: Pure stateless surface sizing, shift and bounds calculation.
  - **Status**: done

- [x] **Story 1.4**: Extract `ShelfItem` domain value model from `ShelfService`
  - **Arch**: Independent value model with recursive leaf counts and payload kinds.
  - **Status**: done

- [x] **Story 1.5**: Spring physics tuning and fluid morphing in `NotchWindowHost`
  - **UX**: Natural spring curve (`response: 0.38`, `dampingFraction: 0.72`) with squash-and-stretch vertical momentum during open/close.
  - **Status**: done

- [x] **Story 1.6**: Split Island dual-pill presentation for concurrent activities
  - **UX**: When music and timer/agent are active simultaneously, island renders as dual pills with central gap.
  - **Status**: done

- [x] **Story 1.7**: Edge peek gesture detector extraction from `ShelfService`
  - **Arch**: Decouple global mouse drag monitoring and dock proximity math into `ShelfEdgeDragMonitor`.
  - **Status**: done

## Milestone 2: App Volume Mixer Architecture & Polish

- [x] **Story 2.1**: Extract `MixerOutputDevice` and `MixerApp` domain models from `AppVolumeMixer`
  - **Arch**: Standalone domain models with identity hashing, equality, and persistence mapping.
  - **Status**: done

- [x] **Story 2.2**: App audio mute shortcuts and individual volume presets
  - **UX**: 1-click quick-mute on mixer app rows, volume presets (0%, 25%, 50%, 75%, 100%, 150%, 200%) and global toggle per focused app.
  - **Status**: done

- [x] **Story 2.3**: Dynamic Island Audio Level Visualizer in expanded notch view
  - **UX**: Visual audio equalizer reflects live app mixer activity in expanded island.
  - **Status**: done

- [x] **Story 2.4**: Extract `MixerTapEngine` audio tap state and lifecycle from `AppVolumeMixer`
  - **Arch**: Isolate AudioServerPlugIn tap registration, active tap map, and device routing logic into dedicated service.
  - **Status**: done

- [todo] **Story 2.5**: Quick app audio routing menu in Dynamic Island & Menu Bar
  - **UX**: Redirect audio of specific apps to different audio output devices (Headphones, External Display, Built-in Speakers) with 1 click.
  - **Status**: todo

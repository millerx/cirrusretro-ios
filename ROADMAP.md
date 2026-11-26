# Roadmap

## 1. Feasibility and portable NSF prototype (current)
- Audit upstream engines, dependency versions, licenses and native portability; document potential distribution constraints.
- Define a small C API for loading, metadata, track selection, rendering PCM and cleanup.
- Build a command-line NSF-to-WAV prototype on Linux with a documented reproducible build.
- Test with redistributable fixtures; validate WAV headers, sample count, non-silent output, deterministic reference output where feasible and malformed input handling.
- Document ARM64 iOS build approach, unresolved risks and exact test results.
- Acceptance: successful clean build and automated tests; audible WAV output from a lawful fixture; provenance and licensing documented. No SwiftUI work yet.

## 2. Native iOS playback
- Package the core for iOS device and simulator; create a minimal SwiftUI player and Files import.
- Integrate AVAudioEngine and bounded buffering; test start, pause, stop, track selection and errors.
- Acceptance: hosted macOS build and simulator tests pass; physical iPhone/iPad playback verified by owner.

## 3. Music player MVP
- Add SPC and VGM after individual audits; local library, metadata, playback queue and universal layouts.
- Add background playback, lock-screen controls, interruption and route handling.
- Acceptance: offline playback, stable background behavior and device testing on iPhone and iPad.

## 4. Beta and expansion
- Configure signing and TestFlight via hosted macOS CI; evaluate battery, memory, audio fidelity and accessibility.
- Review licensing, attribution and naming before public distribution.
- Consider additional formats, playlists, channel controls and visualizations after MVP stability.

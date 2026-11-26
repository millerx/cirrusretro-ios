# Engineering instructions for agents

## Scope and architecture
- Target native iPhone and iPad only. Use SwiftUI for the application, portable C/C++ for emulation, and a narrow C-compatible API with opaque handles, explicit ownership and documented error handling.
- Prefer proven upstream emulator implementations over rewriting sound chips. Audit actual dependencies and licenses before incorporating code; pin upstream revisions and retain notices.
- Keep the core independent of Apple frameworks, browser APIs and Emscripten. Use reproducible CMake or equivalent portable builds and Linux tests.
- Plan AVAudioEngine integration with bounded buffering; avoid allocations, blocking, locks and file I/O on the real-time audio callback. Define sample format, rate, channels, lifecycle and thread ownership.
- Offline-first; import through Files and store locally. No backend or analytics by default. Plan background audio, interruptions, route changes and Now Playing controls.
- Treat imported files as untrusted; validate bounds and sizes, handle malformed inputs and use sanitizers where available.

## Workflow
- Read ROADMAP.md before implementation. Keep tasks focused on the current milestone. Use feature branches and pull requests; do not merge automatically.
- Document build commands, dependency provenance, decisions, test results and limitations. Never claim an iOS build or device test passed unless actually executed.
- Develop portable code in Codex Cloud; use hosted macOS CI for Xcode compilation and simulator tests. Prefer Xcode Cloud for TestFlight, with GitHub Actions macOS as an alternative. Do not assume signing or Apple enrollment is configured.
- Do not commit secrets, signing assets, copyrighted game music or ROMs without redistribution rights. Use original synthetic or explicitly redistributable fixtures with provenance.
- Preserve upstream copyright notices. Do not select a project license or publish a release before the owner approves licensing. Flag copyleft and App Store compatibility questions.
- Keep independent-project attribution to Multimedia Mike; do not imply endorsement.

## First task
Audit https://github.com/multimediamike/cirrusretro-players and its actual dependencies, identify a viable NSF engine, propose the C API and implement a portable NSF-to-WAV CLI with automated tests and reproducible build instructions. Document native ARM64 iOS feasibility and unresolved risks. Do not implement SwiftUI yet. If licensing is unclear, stop before importing the affected code and report the blocker.

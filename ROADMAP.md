# Roadmap

The primary objective is personal installation and ongoing use on the owner's iPhone. Limited sharing with a friend through TestFlight is optional. Public App Store release and monetization are out of scope. Prefer a sustainable remote signing and installation workflow; account for provisioning and beta expiration. Public source visibility does not waive dependency licenses; review obligations for any binary sharing, including TestFlight.

## 1. Feasibility and portable NSF prototype (complete)
- Audit upstream engines, dependency versions, licenses and native portability; document potential distribution constraints.
- Define a small C API for loading, metadata, track selection, rendering PCM and cleanup.
- Build a command-line NSF-to-WAV prototype on Linux with a documented reproducible build.
- Test with redistributable fixtures; validate WAV headers, sample count, non-silent output, deterministic reference output where feasible and malformed input handling.
- Document ARM64 iOS build approach, unresolved risks and exact test results.
- Acceptance: successful clean build and automated tests; audible WAV output from a lawful fixture; provenance and licensing documented. No SwiftUI work yet.

Milestone 1 merged via PR #1. Independent review and Linux CI passed; subjective listening and Apple SDK/device validation remain deferred.

## 1.5. Autonomous development workflow (complete)
- Evaluate supported subscription-backed Codex and GitHub orchestration; no paid API or extra credits.
- Prefer existing Linux CI and GitHub PR comments. Establish bounded two-pass independent review and fix handoffs, commit-SHA verification, final CI and owner approval.
- Document supported triggers, quota handling, security boundaries, exception escalation and any unavoidable manual steps.
- Acceptance: demonstrate a safe, low-overhead workflow where feasible; otherwise document the minimal manual fallback. Do not build a bespoke orchestration platform or start native iOS work in this milestone.

## 2. Native iOS playback (complete)
- Package the core for iOS device and simulator; create a minimal SwiftUI player and Files import.
- Integrate AVAudioEngine and bounded buffering; test start, pause, stop, track selection and errors.
- Acceptance: hosted macOS build and simulator tests pass; physical iPhone playback verified by owner.

Owner reports successful TestFlight installation and playback of two tracks from a sample NSF on physical iPhone (version 0.2, build 2 delivered). Milestone 2 merged.

## 3. Music player MVP

### 3A. Additional music formats (current)
- Add SPC first, then VGM, using the existing GME engine where licensing and feasibility permit. Audit enabled components separately; avoid GPL-only optional components unless explicitly approved.
- Generalize the portable interface and format detection as needed while preserving NSF compatibility, bounded rendering, ownership and error recovery.
- Extend iPhone Files import and playback to supported formats. Use lawful fixtures, portable regression tests, hosted iPhone builds and simulator tests.
- Acceptance: independent two-pass review, green CI, owner TestFlight playback of SPC and VGM on iPhone with NSF regression smoke test.

### 3B. Music library
- Persistent offline collection, multiple-file import, metadata, browsing and playback queue; iPhone layouts only.

### 3C. Native music experience
- Background playback, lock-screen controls, interruption and route handling.
- Acceptance: stable offline and background playback on iPhone.

## 4. Beta and expansion
- Establish sustainable personal installation and signing via hosted macOS CI; optionally configure limited TestFlight sharing after licensing review. Evaluate battery, memory, audio fidelity and accessibility.
- Review licensing, attribution and naming before any external binary sharing; public App Store release is not planned.
- Consider additional formats, playlists, channel controls and visualizations after MVP stability.

## Maintenance backlog
- Apple delivery warning ITMS-90725 for 0.2 build 2: iOS 27 SDK / Xcode 27 or later required for App Store Connect uploads starting April 2027, per owner-provided Apple email. Target February 2027 or earlier when stable hosted tooling is available; preserve deployment target and run regression tests.

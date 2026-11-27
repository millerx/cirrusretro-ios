# Cirrus Retro for iOS

An independent, native iPhone retro game music player inspired by Multimedia Mike's Cirrus Retro project. The goal is to play original game-music formats through emulation rather than prerecorded audio, entirely on device.

## Heritage and attribution

This project honors Multimedia Mike and the original Cirrus Retro project. It is not an official successor or affiliated release.

- [Original player engines](https://github.com/multimediamike/cirrusretro-players)
- [Original website](https://cirrusretro.com/) (historical; availability may vary)
- [Things I Have Learned About Emscripten](https://multimedia.cx/eggs/things-i-have-learned-about-emscripten/)
- [Multimedia Mike](https://github.com/multimediamike)

## Distribution objectives

The primary objective is personal installation and ongoing use on the owner's iPhone. Limited sharing with a friend through TestFlight is optional. Public App Store release and monetization are out of scope. Prefer a sustainable remote signing and installation workflow; account for provisioning and beta expiration. Public source visibility does not waive dependency licenses; review obligations for any binary sharing, including TestFlight.

## Direction

Native SwiftUI for iPhone; portable C/C++ emulation behind a C API; AVAudioEngine playback; offline file import and library; eventual background playback and system media controls. The player recognizes raw NSF, SPC and supported Sega VGM streams by their contents.

Development is intended to use Codex Cloud, GitHub and hosted macOS CI, preferably Xcode Cloud for distribution. No backend is planned.

## Render the Milestone 1 prototype

From the repository root on Linux, use CMake 3.20+, Git, a C11/C++ toolchain, a CMake build tool and Python 3.8+ for the tests. The first configure fetches a pinned Game Music Emu revision. Rendering runs offline. In the published Linux environment, activate the existing tools with `source /workspace/.cirrusretro-toolchain/bin/activate` if CMake is outside your PATH.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure --no-tests=error
build/nsf-to-wav build/pulse.nsf build/pulse.wav 3 1
```

The tests generate an original two-track NSF. The last command renders its lower pulse tone to a new stereo WAV. For another input, use `nsf-to-wav INPUT.nsf NEW.wav [SECONDS [TRACK]]`. Duration defaults to three seconds (range 1–3600). Tracks are numbered from one on the CLI and default to the file's starting track. Use a fresh output path each time.

## Status and licensing

The original CLI handles raw NSF v1 with the base NES APU. The portable music API and iPhone player also handle SPC and VGM. The project license awaits owner approval. The dependency audit permits private builds and personal device use with the patched engine. Sharing a binary with a friend through TestFlight requires a separate licensing review. Upstream components retain their licenses and notices. Use music or ROMs only with appropriate rights.

See the [Milestone 1 audit, design and test record](docs/milestone-1.md), [roadmap](ROADMAP.md), [milestone workflow](docs/milestone-workflow.md) and [engineering instructions](AGENTS.md).

## Native iPhone player

Milestone 2 is merged; the owner confirmed TestFlight installation and playback of two NSF tracks on iPhone. iPad-specific development is deferred.

In Library, tap **+** to import one or more NSF, SPC or supported VGM files from Files. The app saves local copies for offline use and detects duplicates by file contents. Existing installations automatically bring their previous saved recording into the library. Search by title, artist, copyright, filename or format. Open a recording to play a track or add it to the queue. In Playback, use **Play Next** to start the queue or skip ahead. Tracks also advance automatically when playback finishes. The queue lasts for the current app session. Swipe a recording in Library to remove the app’s copy and its queued tracks. See the [supported formats, dependency audit and personal iPhone checks](docs/milestone-3a.md). The hosted macOS workflow builds for device and runs simulator tests without Apple signing credentials. See the [native build, playback design and personal installation guide](docs/milestone-2.md).

### Manual steps for a personal TestFlight build

1. In GitHub Actions, open the **Owner TestFlight** run. Confirm the commit matches the reviewed revision and that only the owner will receive the build. Select **Review deployments → owner-testflight → Approve and deploy**. The workflow then signs and uploads the app.
2. After Apple processes the upload, open **App Store Connect → Apps → Cirrus Retro → TestFlight** and select the new version and build number. If it shows **Missing Compliance**, answer the export-compliance question and save. For **0.3.0 (3)**, the owner selected **None of the above**. Answer for the encryption used by the build being delivered.

GitHub can show **Delivered** while the iPhone still shows the previous build. Once the build is available to the **Owner** internal group, open TestFlight on the iPhone and tap **Update**. Verify the version and build number before testing.

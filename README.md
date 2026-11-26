# Cirrus Retro for iOS

An independent, native iPhone and iPad retro game music player inspired by Multimedia Mike's Cirrus Retro project. The goal is to play original game-music formats through emulation rather than prerecorded audio, entirely on device.

## Heritage and attribution

This project honors Multimedia Mike and the original Cirrus Retro project. It is not an official successor or affiliated release.

- [Original player engines](https://github.com/multimediamike/cirrusretro-players)
- [Original website](https://cirrusretro.com/) (historical; availability may vary)
- [Things I Have Learned About Emscripten](https://multimedia.cx/eggs/things-i-have-learned-about-emscripten/)
- [Multimedia Mike](https://github.com/multimediamike)

## Distribution objectives

The primary objective is personal installation and ongoing use on the owner's iPhone and iPad. Limited sharing with a friend through TestFlight is optional. Public App Store release and monetization are out of scope. Prefer a sustainable remote signing and installation workflow; account for provisioning and beta expiration. Public source visibility does not waive dependency licenses; review obligations for any binary sharing, including TestFlight.

## Direction

Native SwiftUI for iPhone and iPad; portable C/C++ emulation behind a C API; AVAudioEngine playback; offline file import and library; eventual background playback and system media controls. Initial target: NSF, followed by SPC and VGM subject to feasibility and licensing.

Development is intended to use Codex Cloud, GitHub and hosted macOS CI, preferably Xcode Cloud for distribution. No backend is planned.

## Render the Milestone 1 prototype

From the repository root on Linux, use CMake 3.20+, Git, a C11/C++ toolchain, a CMake build tool and Python 3.8+ for the tests. The first configure fetches a pinned Game Music Emu revision. Rendering runs offline. In the published Linux environment, activate the existing tools with `source /workspace/.cirrusretro-toolchain/bin/activate` if CMake is outside your PATH.

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
ctest --test-dir build --output-on-failure
build/nsf-to-wav build/pulse.nsf build/pulse.wav 3 1
```

The tests generate an original two-track NSF. The last command renders its lower pulse tone to a new stereo WAV. For another input, use `nsf-to-wav INPUT.nsf NEW.wav [SECONDS [TRACK]]`. Duration defaults to three seconds (range 1–3600). Tracks are numbered from one on the CLI and default to the file's starting track. Use a fresh output path each time.

## Status and licensing

The portable prototype handles raw NSF v1 with the base NES APU. The project license awaits owner approval. The dependency audit permits local development with the pinned engine. Binary distribution, including TestFlight and the App Store, requires a separate licensing review. Upstream components retain their licenses and notices. Use music or ROMs only with appropriate rights.

See the [Milestone 1 audit, design and test record](docs/milestone-1.md), [roadmap](ROADMAP.md) and [engineering instructions](AGENTS.md).

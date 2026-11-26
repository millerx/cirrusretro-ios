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

## Status and licensing

Planning stage; no working player yet. The first milestone is a portable NSF-to-WAV proof of concept. See [ROADMAP.md](ROADMAP.md) and [AGENTS.md](AGENTS.md).

Project licensing is pending a dependency audit. Public visibility does not grant a general license to reuse original project code. Upstream components retain their respective licenses and notices. Do not distribute copyrighted music or ROMs without authorization.

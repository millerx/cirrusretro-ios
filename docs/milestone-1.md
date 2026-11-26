# Milestone 1 feasibility record

An NSF contains a 6502 program that initializes the NES audio hardware and advances it at a specified interval. On Linux the prototype can execute that program, export its metadata and render a selected track into a playable WAV. The source tree contains original integration code and a synthetic test-signal generator. The engine comes from an unmodified upstream checkout at configure time.

## Historical dependency audit

Inspected Multimedia Mike's Cirrus Retro Players at `49755633938bbc3d9099c6dc8f585c8b162b6f3d`. The Python/Ninja generator is the documented build. The older Makefiles also identify engines whose sources or build paths differ from that generator. [Upstream snapshot](https://github.com/multimediamike/cirrusretro-players/tree/49755633938bbc3d9099c6dc8f585c8b162b6f3d)

| Component in that revision | Evidence and disposition |
| --- | --- |
| Browser player, C/JS interfaces, harness and archive support | `gme_interface.cpp` includes Emscripten, handles XZ and archive entries and calls GME. `play.js` and the HTML demo handle playback in the browser. No repository-wide license grant was found. Reimplemented the host interface independently. |
| Game Music Emu 0.6.1 | The Ninja generator names `gme-source-0.6.1` and builds AY, GBS, GYM, HES, KSS, NSF, SAP, SPC and VGM targets. The NSF configuration enables NSF and NSFE. The old Makefile still points to 0.6.0. NSF uses Shay Green's NES CPU, APU and Blip_Buffer code with LGPL-2.1-or-later notices. Selected the maintained upstream for a versioned build with its full license text. |
| XZ Embedded | Bundled C decoder for CRC32/LZMA2 streams. The import is identifiable by the repository revision (commit `4ca2261` introduced it), with no release number in the build. The inspected decoder sources have public-domain notices. The separate `xzdec.c` wrapper falls under the unresolved project-level grant. Raw NSF needs neither component. |
| vio2sf 0.16 | The legacy 2SF target uses `vio2sf-0.16`. Its DeSmuME ARM sources carry GPL-2.0-or-later notices, the directory ships GPLv2 COPYING, and its Audio Overload `corlett.c` carries a BSD three-clause notice. Excluded. |
| Audio Overload SDK | Legacy SSF and DSF rules reference `aosdk/eng_ssf` and `aosdk/eng_dsf`. The full SDK tree is absent. Its revision and complete terms cannot be established from this snapshot. The grant on the bundled Corlett file covers that file alone. Excluded. |
| Build tools and content | Emscripten, Ninja, Python/ninja-syntax, optional Zopfli compression and Node/browser tests belong to the historical toolchain. The bundled game-derived music samples have no identified redistribution grant here. None are inputs to this prototype. |

Build and license evidence: [Ninja generator](https://github.com/multimediamike/cirrusretro-players/blob/49755633938bbc3d9099c6dc8f585c8b162b6f3d/build-ninja-build-file.py) · [NSF configuration](https://github.com/multimediamike/cirrusretro-players/tree/49755633938bbc3d9099c6dc8f585c8b162b6f3d/gme-source-0.6.1/config-headers/nsf) · [2SF sources and notices](https://github.com/multimediamike/cirrusretro-players/tree/49755633938bbc3d9099c6dc8f585c8b162b6f3d/vio2sf-0.16) · [SSF build rules](https://github.com/multimediamike/cirrusretro-players/blob/49755633938bbc3d9099c6dc8f585c8b162b6f3d/Makefile-aossf).

## Selected engine and distribution decision

CMake pins Game Music Emu 0.6.5 at `9e23d10f9fd2a6a2f33b10912dd8dc7153258995`. Its changelog includes fixes to earlier releases and improved NES CPU support. CMake enables only the NSF format, disables zlib, examples and upstream demo tests, and links the CLI to the built shared GME library. Linux dependencies observed with `ldd` were the local libgme, libc, libstdc++, libm, libgcc_s and the system loader. The GPL MAME YM2612 option belongs to GYM/VGM and is excluded. [Release source and notices](https://github.com/libgme/game-music-emu/tree/9e23d10f9fd2a6a2f33b10912dd8dc7153258995) · [Build source lists](https://github.com/libgme/game-music-emu/blob/9e23d10f9fd2a6a2f33b10912dd8dc7153258995/gme/CMakeLists.txt)

The GME library credits Shay Green and contributors. The core NSF modules specify LGPL-2.1-or-later. The NSF target also compiles the VRC7 implementation and Mitsutaka Okazaki's MIT-licensed emu2413 v1.5.9, even though this prototype rejects expansion flags at its API. Fetching the original tree preserves the root license, file-level notices and `gme/ext/LICENSE`. The original GME test music is outside our build and test inputs. [LGPL text](https://github.com/libgme/game-music-emu/blob/9e23d10f9fd2a6a2f33b10912dd8dc7153258995/license.txt) · [NSF source notice](https://github.com/libgme/game-music-emu/blob/9e23d10f9fd2a6a2f33b10912dd8dc7153258995/gme/Nsf_Emu.cpp) · [emu2413 MIT notice](https://github.com/libgme/game-music-emu/blob/9e23d10f9fd2a6a2f33b10912dd8dc7153258995/gme/ext/LICENSE)

Local compilation and evaluation can proceed under these grants. Before shipping binaries, the owner must choose a project license and review LGPL sections 4 and 6 against the actual delivery method. Plan to supply the license and copyright notices, corresponding library source including modifications, and a supported means to replace or relink the library. Review reverse-engineering rights for debugging modifications, App Store terms, DRM and signing restrictions. Static linking can require relinkable application object files. A shared library on Linux demonstrates an engineering choice and gives no assurance that a signed iOS package satisfies those obligations.

## Interface and limits

- The caller opens an in-memory raw NSF v1 and owns an opaque handle. The engine copies the program. Metadata is a value copy of title, artist, copyright, track count and starting track. The three strings preserve the original header bytes with a trailing NUL. Consumers must choose a display encoding.
- Select a zero-based track explicitly before rendering. Selecting it again restarts it. Render 1–4096 stereo frames per call into caller-owned signed 16-bit interleaved PCM at 44,100 Hz. The CLI converts to little-endian PCM, streams 1024 frames at a time and writes the requested duration including the final short block. A render error invalidates the block. Close frees the handle. The public header specifies ownership and error lifetimes. [C API](../include/cirrus_nsf.h)
- The parser checks the 128-byte header, magic, version, track range, ROM addresses, expansion byte and payload bounds before passing the file to GME. A flat image must fit from its load address to the end of the 64 KiB address space. Banked ROM is limited to 256 4 KiB banks including initial alignment. The CLI bounds input size before allocation, bounds duration to one hour and creates output exclusively. GME executes guest instructions from accepted files. Header validation and bounded buffers cannot establish that every guest program terminates its routines, plays correctly or is cheap to emulate.
- The fixture generator assembles two original constant-pitch pulse signals using NES register writes. The second track is the header default to exercise track numbering. The generator includes permission to redistribute the generated fixture and rendered signal. It contains no game music or third-party ROM bytes. [Fixture and permission](../tests/fixture.py)

## Linux verification

Use the clean release commands in the [README](../README.md). For a first build without network, provide an existing clean checkout of the exact GME commit via `-DFETCHCONTENT_SOURCE_DIR_GAME_MUSIC_EMU=/absolute/path/to/game-music-emu` and verify its HEAD with `git rev-parse HEAD` beforehand. To repeat the sanitizer run on GCC/Linux:

```sh
flags="-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer"
cmake -S . -B build-san -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_C_FLAGS="$flags" -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_EXE_LINKER_FLAGS=-no-pie
cmake --build build-san --parallel
ctest --test-dir build-san --output-on-failure
```

Linux x86-64, GCC/G++ 14.2.0, glibc 2.41, CMake 3.31.10, Python 3.12.14:

| Configuration | Results |
| --- | --- |
| Clean Release | 3/3 CTest entries passed: fixture generation, C API and WAV CLI. |
| ASan + UBSan, including GME | 3/3 CTest entries passed. No sanitizer findings in these cases. |

The C test covers ownership after the caller overwrites input, full-width metadata, error paths, track restart and PCM equivalence across block sizes. CLI tests check flat and banked inputs, all RIFF/PCM header fields, exact duration, both channel signals, distinct pitches, default track selection, repeatability, malformed input, numeric limits and file errors.

For one second of track 1, ffprobe identified `pcm_s16le`, two channels, 44,100 Hz and 44,100 frames. Left-channel extrema were −6,805 and +10,949 with RMS 5,128 (full scale 32,768). The two tracks produced 443 and 883 positive-going zero crossings in their first second, consistent with their nominal 440 Hz and 881 Hz pitches including the initial transient. The track 1 PCM payload SHA-256 was `8407fc4dea4d00151864e534abed6416772a160964762a0999703eda95d4dbdd`. The test uses this reference on Linux x86-64/glibc and tests signal and repeatability on other platforms. These are decoded-signal measurements. Listening quality, a broader lawful corpus, expansion audio, NSF2/NSFe and compressed inputs remain outside the verified scope.

## Native ARM64 feasibility and risks

GME interprets the NES CPU in portable C++ and exposes a C interface. The adapter uses fixed-width samples and separates byte-oriented file handling from frame-oriented rendering. No JIT, browser runtime, Apple framework or audio device is needed for this path. A future hosted macOS build can compile the core and the same pinned GME with Apple Clang/libc++ for the iPhoneOS arm64 SDK and separately for the iPhoneSimulator SDK, then compare the fixture metadata, frame count and pitch across targets. Device and simulator ARM64 builds require different SDK slices. Packaging and signing depend on the distribution review.

For native playback, keep each handle on a single producer thread. That thread owns loading, selection, rendering and cleanup. Feed a preallocated bounded PCM ring and have the AVAudioEngine callback only consume available frames and supply silence on underrun. Keep locks, allocations, file access and emulation off that callback. Output route format conversion, interruption recovery, buffer sizing, real-time deadlines, CPU/battery cost and fidelity need measurement with a native host. No Apple SDK build, simulator run, device playback or subjective listening test was performed for this milestone.

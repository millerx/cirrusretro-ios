# Milestone 3A · Additional music formats

The iPhone player identifies raw files by signature, so a renamed file or the existing offline slot works across app upgrades. Loading and saving a replacement complete on the worker before the current handle and audio output are released. Playback uses the existing bounded PCM queue and AVAudioSourceNode callback.

## Playback coverage

| Format | Accepted inputs | Limits and metadata |
| --- | --- | --- |
| NSF | Raw v1, base APU, banked and flat images | Original size limit, metadata, default track, guest-work limit, CLI and C ABI. |
| SPC | v0.30 snapshot with the complete CPU, 64 KiB RAM and DSP state | One track. Reads the fixed ID666 title and artist when present. Optional extended tags and timing are ignored. The artist offset uses the usual text/binary ID666 heuristic. |
| VGM | Uncompressed v1.00–1.71 streams using Sega SN76489 PSG, Game Gear stereo and single YM2612 register writes. Supports one type-0 PCM bank, absolute PCM seeks, DAC waits, standard waits, END and a timed loop. | One track. Finite streams stop after their command-derived duration. Reads bounded GD3 song and artist fields using GME's legacy text conversion. Unsupported chip clocks, extended header features, commands and compressed VGZ return errors. |

The new API accepts at most 8 MiB and retains the original 44,100 Hz signed 16-bit stereo format, 4,096-frame block limit and one-hour selection limit. Generic metadata includes a format and frame limit. The player drains the final queued block before stopping. NSF callers can continue using the original header and symbols. [C interface](../include/cirrus_music.h)

VGM validation scans once before opening the engine. It bounds offsets, command operands and PCM reads, checks that a loop lands on a command and advances time, and requires a fresh PCM seek before a loop reads the bank. Up to 1,024 commands can run in a burst. Each elapsed sample replenishes eight commands of credit, and each full loop must sustain its own command rate. File size bounds validation work and the command budget bounds playback work even for short loops. SPC uses the engine's clocked CPU/DSP and a fixed-size resampler. Neither decoder runs on the audio callback. [VGM validator](../src/vgm.c)

## Dependency and license audit

GME 0.6.5 remains pinned at `9e23d10f9fd2a6a2f33b10912dd8dc7153258995`. The Linux compile database showed the following translation units in addition to the common GME core, buffers and resamplers. iPhone builds use the same CMake source selection in a static archive for each SDK. [Upstream build list](https://github.com/libgme/game-music-emu/blob/9e23d10f9fd2a6a2f33b10912dd8dc7153258995/gme/CMakeLists.txt) · [Upstream component notices](https://github.com/libgme/game-music-emu/blob/9e23d10f9fd2a6a2f33b10912dd8dc7153258995/readme.txt)

| Format | Compiled components | License evidence and selections |
| --- | --- | --- |
| NSF | Nsf_Emu, NES CPU/APU/oscillators, FDS, FME7, Namco, VRC6 and VRC7, including ext/emu2413.c | GME LGPL-2.1-or-later and emu2413 MIT, including expansion modules compiled into the library. The adapter accepts the base APU. [NSF audit](milestone-1.md) |
| SPC | Spc_Emu, Snes_Spc, Spc_Cpu, Spc_Dsp and Spc_Filter | Shay Green's LGPL-2.1-or-later modules. Standard shared APU RAM with isolated echo disabled. A hash-checked local patch wraps DSP sample-directory addresses to 16 bits on reads, including when a running track changes its registers. [Patch](../cmake/gme-patches.cmake) |
| VGM | Vgm_Emu, Vgm_Emu_Impl, Sms_Apu, Ym2612_GENS and the upstream Ym2413_Emu stub | GME and Stéphane Dallongeville's GENS 2.10 adapter carry LGPL-2.1-or-later. CMake forces GENS. MAME (GPL-2.0-or-later), Nuked, zlib and VGZ decompression are excluded. The stub provides no YM2413 playback. [GENS source notice](https://github.com/libgme/game-music-emu/blob/9e23d10f9fd2a6a2f33b10912dd8dc7153258995/gme/Ym2612_GENS.cpp) |

Linux dynamic linkage showed the local shared GME and system C/C++, math, compiler runtime and loader. No additional third-party dependency was introduced. The upstream notices and license text remain in the pinned source. The owner's personal build and the existing LGPL/MIT obligations for any future sharing are described in the [distribution decision](milestone-1.md#selected-engine-and-distribution-decision).

## Verification and personal installation

Run the [Linux build commands](../README.md#render-the-milestone-1-prototype) and [sanitizer configuration](milestone-1.md#linux-verification). CTest generates pulse.nsf, pulse.spc, pulse.vgm and dac.vgm in the build directory. The tests check tone crossings, restart after freeing the input, split renders, finite end, loop playback, rejected inputs and allocation recovery. Both generators grant permission to redistribute their original tones and rendered output. [NSF generator](../tests/fixture.py) · [SPC and VGM generator](../tests/format_fixtures.py)

The standard GitHub-hosted ARM64 `xcode-27` image lists release Xcode 27.x, iPhoneOS SDKs and simulator runtimes. GitHub labels this runner image a public preview. The archive script checks the SDK major version and the built app's minimum OS (16.0). The PR workflow builds both slices, archives unsigned, and selects an available iPhone for app-hosted XCTest. The tag-triggered owner workflow uses the same image. [Runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

After owner approval and personal TestFlight delivery, copy the generated files into Files on the iPhone. Import pulse.spc and listen for a steady tone. Import pulse.vgm and confirm it stops after one second. With dac.vgm, check looping, pause, resume and stop. Reopen the app and verify the last import plays offline. Finally import pulse.nsf and listen to both pitches. Version 0.2 build 2 already passed the owner's physical NSF test. The new formats need their own physical playback check. [Personal installation guide](milestone-2.md)

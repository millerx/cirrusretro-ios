"""Original synthesized test tones. Permission is granted to use, modify,
copy and redistribute these fixtures and their rendered audio for any purpose.
No third-party music, sample, boot ROM or driver is used.
"""
from pathlib import Path
import struct
import sys


def spc():
    snapshot = bytearray(0x10200)
    header = b"SNES-SPC700 Sound File Data v0.30\x1a\x1a\x1a\x1e"
    snapshot[:len(header)] = header
    struct.pack_into("<H", snapshot, 0x25, 0x200)  # SPC700 PC
    snapshot[0x2e:0x37] = b"BRR pulse"
    snapshot[0xb1:0xbc] = b"Cirrus test"
    ram = memoryview(snapshot)[0x100:0x10100]
    ram[0x200:0x202] = b"\x2f\xfe"  # BRA to self
    struct.pack_into("<HH", ram, 0x300, 0x400, 0x400)  # source 0 start/loop
    ram[0x400:0x409] = bytes([0xb3] + [0x44] * 4 + [0xcc] * 4)
    dsp = memoryview(snapshot)[0x10100:]
    for reg, value in {0: 90, 1: 90, 2: 0, 3: 4, 7: 127, 0x0c: 90,
                       0x1c: 90, 0x5d: 3, 0x6c: 0x20, 0x4c: 1}.items():
        dsp[reg] = value
    return snapshot


def vgm(commands, *, loop=None, fm=False, tagged=False):
    header = bytearray(0x40)
    header[:4] = b"Vgm "
    struct.pack_into("<II", header, 8, 0x150, 3579545)
    struct.pack_into("<I", header, 0x34, 12)
    if loop is not None:
        struct.pack_into("<I", header, 0x1c, 0x40 + loop - 0x1c)
    if fm:
        struct.pack_into("<I", header, 0x2c, 7670454)
    data = header + commands
    if tagged:
        fields = ["PSG pulse", "", "", "", "", "", "Cirrus test", "", "", "", ""]
        tag = ("\0".join(fields) + "\0").encode("utf-16-le")
        struct.pack_into("<I", data, 0x14, len(data) - 0x14)
        data += b"Gd3 " + struct.pack("<II", 0x100, len(tag)) + tag
    struct.pack_into("<I", data, 4, len(data) - 4)
    return data


def psg():
    # Square 0 clock divider 224 (~499 Hz), full volume, wait one second.
    return vgm(bytes.fromhex("50 80 50 0E 50 90 61 44 AC 66"), tagged=True)


def dac():
    # A looping 16-sample YM2612 DAC square wave. Rewind PCM on each lap.
    bank = bytes.fromhex("67 66 00 10 00 00 00") + bytes([192]*8 + [64]*8)
    enable = bytes.fromhex("52 2B 80")
    # One PCM sample every 5 output frames (551.25 Hz).
    return vgm(bank + enable + bytes.fromhex("E0 00 00 00 00") +
               bytes([0x85]*16) + b"\x66", loop=len(bank + enable), fm=True)


if __name__ == "__main__":
    (Path(sys.argv[1]) / "pulse.spc").write_bytes(spc())
    (Path(sys.argv[1]) / "pulse.vgm").write_bytes(psg())
    (Path(sys.argv[1]) / "dac.vgm").write_bytes(dac())

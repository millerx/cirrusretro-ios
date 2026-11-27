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


if __name__ == "__main__":
    (Path(sys.argv[1]) / "pulse.spc").write_bytes(spc())

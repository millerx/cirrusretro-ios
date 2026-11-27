"""Format-boundary and work-budget regressions using original fixture bytes."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

from format_fixtures import dac, psg, spc, vgm


def field(data, offset, value):
    data = bytearray(data)
    struct.pack_into("<I", data, offset, value)
    return data


def inputs():
    snapshot = spc()
    yield snapshot[:0x1017f]
    yield snapshot[:0x23] + b"?" + snapshot[0x24:]
    yield bytes(8 * 1024 * 1024 + 1)
    yield b"\x1f\x8b" + bytes(80)  # gzip/VGZ
    tone = psg()
    yield tone[:0x40]
    yield field(field(tone, 8, 0x101), 0x10, 7670454)  # legacy shared FM clock
    for offset in (4, 0x10, 0x14, 0x1c, 0x2c, 0x34):
        yield field(tone, offset, 0xffffffff)
    yield field(tone, 0x28, 0x00ff0009)  # invalid shift-register width
    for stream in ("50", "52 2B", "61 FF", "67 66 00 FF FF FF 7F", "E0 FF FF FF FF",
                   "67 66 00 01 00 00 00 00 E0 00 00 00 00 81 81 66", "54 00 00 66"):
        yield vgm(bytes.fromhex(stream), fm=True)
    yield vgm(bytes.fromhex("62 50 90 66"), loop=2)  # target inside a command
    yield vgm(bytes.fromhex("62 50 90 66"), loop=1)  # zero-time loop
    yield vgm(bytes([0x70]) + bytes([0x50, 0x90])*8 + bytes([0x66]), loop=0)
    yield vgm(bytes([0x50, 0x90])*1025 + bytes([0x62, 0x66]))
    burst = bytes([0x50, 0x90]) * 600
    yield vgm(burst + b"\x62" + burst + b"\x66", loop=0)
    yield field(dac(), 0x1c, 0x40 + 7 + 16 + 3 + 5 - 0x1c)  # loop bypasses PCM seek


with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "input"
    for i, case in enumerate(inputs()):
        path.write_bytes(case)
        result = subprocess.run([sys.argv[1], str(path), "reject"], timeout=3)
        if result.returncode:
            raise SystemExit(f"case {i} failed: {result.returncode}")

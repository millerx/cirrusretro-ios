"""Write an original two-pitch NES pulse-channel test signal.

The authors grant permission to use, copy, modify and redistribute the generated
fixture and its rendered audio for any purpose, with or without attribution.
The grant is limited to this synthetic fixture and its output.
"""

from pathlib import Path
import struct
import sys


def fixture():
    # NSF passes the zero-based subsong in A. Save it in X and use a timer
    # table for two pitches. Pulse 1 is enabled before its length counter loads.
    init = bytearray.fromhex(
        "AA "            # TAX
        "A9 01 8D 15 40 "  # enable pulse 1 at $4015
        "A9 BF 8D 00 40 "  # 50% duty, halt length counter, constant volume 15
        "A9 00 8D 01 40 "  # sweep disabled
    )
    init.append(0xbd)  # LDA periods,X (fill in the address after assembly)
    operand = len(init)
    init += bytes(2)
    init += bytes.fromhex("8D 02 40 A9 00 8D 03 40 60")
    play = 0x8000 + len(init)
    struct.pack_into("<H", init, operand, play + 1)
    program = init + bytes([0x60, 253, 126])  # PLAY returns; ~440 and ~881 Hz

    header = bytearray(128)
    header[:8] = b"NESM\x1a\x01\x02\x02"  # v1, two tracks, second is default
    struct.pack_into("<HHH", header, 8, 0x8000, 0x8000, play)
    for offset, label in [(14, b"Pulse pair"), (46, b"Cirrus Retro test"), (78, b"Synthetic fixture")]:
        header[offset:offset + len(label)] = label
    struct.pack_into("<H", header, 110, 16639)  # NTSC play interval in us
    return header + program


def append_routine(data, entry_offset, code):
    """Redirect INIT (offset 10) or PLAY (12) to a new routine in the flat ROM."""
    address = 0x8000 + len(data) - 128
    struct.pack_into("<H", data, entry_offset, address)
    data.extend(code)


def warning_fixture():
    data = fixture()
    # Track 1 runs the original INIT. Track 2 executes a halt opcode that
    # GME reports as an emulation warning during the first render.
    append_routine(data, 10, bytes.fromhex("C9 00 F0 02 02 60 4C 00 80"))
    return data


def scheduled_fixture(region, period_us):
    data = fixture()
    data[122] = region
    struct.pack_into("<H", data, 110, period_us)
    struct.pack_into("<H", data, 120, 20000)
    # Initialize the call counter in zero page before entering the tone INIT.
    append_routine(data, 10, bytes.fromhex("A2 00 86 00 4C 00 80"))
    append_routine(data, 12, bytes.fromhex(
        "E6 00 A5 00 C9 18 "  # INC counter; LDA counter; CMP #24
        "D0 05 A9 7E 8D 02 40 60"  # BNE done; update pulse timer; RTS
    ))
    return data


if __name__ == "__main__":
    Path(sys.argv[1]).write_bytes(fixture())
    if len(sys.argv) > 2:
        Path(sys.argv[2]).write_bytes(warning_fixture())

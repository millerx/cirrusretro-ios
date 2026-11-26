"""Exercise the shipped converter through its command line and read its output independently."""
import hashlib
from pathlib import Path
import platform
import struct
import subprocess
import sys
import tempfile
import unittest
import wave


CLI, FIXTURE = map(Path, sys.argv[1:])
REFERENCE = "8407fc4dea4d00151864e534abed6416772a160964762a0999703eda95d4dbdd"


class Converter(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.output = self.root / "result.wav"

    def convert(self, *args, success=True, source=FIXTURE, dest=None):
        result = subprocess.run([CLI, source, dest or self.output, *args],
                                capture_output=True, timeout=10)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        else:
            self.assertIn(result.returncode, (1, 2), result.stderr)
            self.assertTrue(result.stderr.startswith((b"nsf-to-wav:", b"Usage:")), result.stderr)
            self.assertNotIn(b"Sanitizer", result.stderr)

    def read_wave(self, seconds):
        raw = self.output.read_bytes()
        fields = struct.unpack_from("<4sI4s4sIHHIIHH4sI", raw)
        frames = 44100 * seconds
        self.assertEqual(fields, (b"RIFF", 36 + 4 * frames, b"WAVE", b"fmt ", 16,
                                  1, 2, 44100, 176400, 4, 16, b"data", 4 * frames))
        self.assertEqual(len(raw), 44 + 4 * frames)
        with wave.open(str(self.output)) as audio:
            self.assertEqual(audio.getnframes(), frames)
            pcm = audio.readframes(frames)
        self.output.unlink()
        return pcm

    def check_tone(self, pcm, hz, seconds):
        stereo = list(struct.iter_unpack("<hh", pcm))
        self.assertTrue(all(left == right for left, right in stereo))
        samples = [left for left, _ in stereo]
        self.assertGreater(sum(s*s for s in samples) / len(samples), 1000**2)
        crossings = sum(a <= 0 < b for a, b in zip(samples, samples[1:]))
        self.assertAlmostEqual(crossings / seconds, hz, delta=6)

    def test_pcm_and_reference(self):
        self.convert("1", "1")
        first = self.read_wave(1)
        self.check_tone(first, 440, 1)
        self.convert("1", "1")
        self.assertEqual(self.read_wave(1), first)
        # Floating-point filter construction can vary with architecture/libm.
        if sys.platform == "linux" and platform.machine() == "x86_64" and platform.libc_ver()[0] == "glibc":
            self.assertEqual(hashlib.sha256(first).hexdigest(), REFERENCE)

    def test_header_start_track_and_default_duration(self):
        self.convert()
        default = self.read_wave(3)
        self.check_tone(default, 881, 3)
        self.convert("3", "2")
        self.assertEqual(self.read_wave(3), default)

    def test_banked_rom(self):
        data = bytearray(FIXTURE.read_bytes())
        data[112] = 1  # At $8000 map bank 1, which contains our original code.
        data[128:128] = bytes(4096)
        source = self.root / "banked.nsf"
        source.write_bytes(data)
        self.convert("1", "1", source=source)
        banked = self.read_wave(1)
        self.convert("1", "1")
        self.assertEqual(banked, self.read_wave(1))

    def test_rejects_bad_input(self):
        data = FIXTURE.read_bytes()
        cases = [b"", data[:4], data[:127], data[:128], b"x" * len(data)]
        for offset, value in [(4, 0), (5, 2), (6, 0), (7, 0), (7, 3),
                              (9, 0x40), (11, 0), (13, 0), (123, 1)]:
            cases.append(data[:offset] + bytes([value]) + data[offset+1:])
        cases.extend([data + bytes(32768), data + bytes(1024 * 1024)])
        source = self.root / "broken.nsf"
        for i, content in enumerate(cases):
            with self.subTest(case=i):
                source.write_bytes(content)
                self.convert(source=source, success=False)
                self.assertFalse(self.output.exists())

    def test_arguments_and_file_errors(self):
        for args in [("0",), ("-1",), ("3601",), ("1.5",), ("99999999999999999999",),
                     ("1", "0"), ("1", "3"), ("1", "256"), ("1", "1", "extra")]:
            with self.subTest(args=args):
                self.convert(*args, success=False)
                self.assertFalse(self.output.exists())
        self.convert(source=self.root / "missing", success=False)
        self.convert(dest=self.root / "missing" / "out.wav", success=False)
        self.assertFalse(self.output.exists())
        self.output.write_bytes(b"keep")
        self.convert(success=False)
        self.assertEqual(self.output.read_bytes(), b"keep")


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]], verbosity=2)

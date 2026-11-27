"""Opt-in Linux Release measurement. Uses a temporary 606 MiB WAV.

Run after CTest generates pulse.nsf: python3 tests/playback_soak.py build
"""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import wave


def measure(build):
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "hour.wav"
        command = [build / "nsf-to-wav", build / "pulse.nsf", output, "3600", "1"]
        samples = []
        start = time.monotonic()
        with subprocess.Popen(command) as child:
            while child.poll() is None:
                try:
                    status = Path(f"/proc/{child.pid}/status").read_text()
                except FileNotFoundError:
                    break
                for line in status.splitlines():
                    if line.startswith("VmRSS:") and output.exists():
                        samples.append((output.stat().st_size, int(line.split()[1])))
                time.sleep(0.05)
            if child.wait():
                raise RuntimeError("Render failed")
        elapsed = time.monotonic() - start
        with wave.open(str(output)) as audio:
            rate = 44100
            if (audio.getnframes(), audio.getframerate(), audio.getnchannels(),
                audio.getsampwidth()) != (3600 * rate, rate, 2, 2):
                raise ValueError("Unexpected PCM format or duration")
            for second in [0, 1800, 3599]:
                audio.setpos(second * rate)
                pcm = list(struct.iter_unpack("<hh", audio.readframes(rate)))
                if len(pcm) != rate or any(left != right for left, right in pcm):
                    raise ValueError("Incomplete or mismatched stereo")
                hz = sum(a[0] <= 0 < b[0] for a, b in zip(pcm, pcm[1:]))
                if abs(hz - 440) > 6:
                    raise ValueError(f"Unexpected tone at {second}s: {hz} Hz")
                print(f"{second}s: {hz} Hz")
        warm = [rss for size, rss in samples if size >= 60 * rate * 4]
        print(f"3600s rendered in {elapsed:.2f}s; sampled RSS after minute one "
              f"{min(warm)}–{max(warm)} KiB ({len(warm)} samples)")


if __name__ == "__main__":
    measure(Path(sys.argv[1]).resolve())

#!/usr/bin/env python3
"""Regenerate public speech fixtures with CMU Flite 2.2 (optional authoring tool).

Normal MATLAB use only needs the committed WAVs, not Python or Flite.
No input recordings, network requests, or third-party Python packages are used.
"""

import argparse
import array
from pathlib import Path
import subprocess
import sys
import tempfile
import wave


def generate(flite, output_dir):
    samples_dir = Path(__file__).resolve().parents[1] / "samples"
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, voice in [("demo_speech", "slt"), ("demo_speech_alt", "rms")]:
        with tempfile.TemporaryDirectory() as temp_dir:
            raw = Path(temp_dir) / "speech.wav"
            subprocess.run(
                [flite, "-voice", voice, "-f", str(samples_dir / (name + ".txt")),
                 "-o", str(raw)], check=True,
            )
            with wave.open(str(raw), "rb") as source:
                if source.getnchannels() != 1 or source.getsampwidth() != 2:
                    raise ValueError("Expected Flite mono 16-bit PCM output")
                rate = source.getframerate()
                data = array.array("h", source.readframes(source.getnframes()))
            if sys.byteorder != "little":
                data.byteswap()
            peak = max(abs(value) for value in data)
            if not peak:
                raise ValueError("Flite produced silent output")
            # Normalize to 0.8 peak for safe processing headroom.
            normalized = array.array("h", (round(value * (0.8 * 32767) / peak)
                                           for value in data))
            if sys.byteorder != "little":
                normalized.byteswap()
            target = output_dir / (name + ".wav")
            with wave.open(str(target), "wb") as result:
                result.setnchannels(1)
                result.setsampwidth(2)
                result.setframerate(rate)
                result.writeframes(normalized.tobytes())
            print(f"{target.name}: {rate} Hz, {len(data) / rate:.2f} s")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flite", default="flite", help="Flite executable path")
    parser.add_argument("--output-dir", type=Path,
                        default=Path(__file__).resolve().parents[1] / "samples")
    args = parser.parse_args()
    generate(args.flite, args.output_dir)

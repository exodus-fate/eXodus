"""
Checks the encoded banks the way the game will play them: decodes each .ogg,
cuts out every sound's region and fails on clipping, DC offset, silence, a
region outside its bank, or a loop whose end doesn't flow into its start.

    python3 scripts/audio/check_banks.py [--table]
"""

import json
import os
import subprocess
import sys

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")


def decode(path):
    raw = subprocess.run(
        ["ffmpeg", "-loglevel", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
        capture_output=True,
        check=True,
    ).stdout
    return np.frombuffer(raw, "<i2").astype(float) / 32768


def main():
    meta = json.load(open(os.path.join(AUDIO, "banks.json")))
    banks = {name: decode(os.path.join(AUDIO, info["file"])) for name, info in meta["banks"].items()}
    problems = []
    rows = []
    for name, r in sorted(meta["sounds"].items()):
        audio = banks[r["bank"]]
        a, b = int(round(r["start"] * SR)), int(round((r["start"] + r["length"]) * SR))
        if a < 0 or b > len(audio):
            problems.append("%s: region outside %s" % (name, r["bank"]))
            continue
        s = audio[a:b]
        peak = np.max(np.abs(s))
        rms = np.sqrt(np.mean(s ** 2))
        dc = np.mean(s)
        if np.sum(np.abs(s) > 0.985) > 0:
            problems.append("%s: clips (peak %.3f)" % (name, peak))
        if abs(dc) > 0.005:
            problems.append("%s: DC offset %.4f" % (name, dc))
        if 20 * np.log10(rms + 1e-12) < -50:
            problems.append("%s: nearly silent" % name)
        if r["loop"]:
            # The sample after the region's end must match the region's start.
            after = audio[b:b + 64]
            start = audio[a:a + 64]
            # Relative to the sound's own level: lossy coding never reproduces
            # noise sample-for-sample, but a real seam error is far louder.
            err = np.sqrt(np.mean((after - start) ** 2)) / (rms + 1e-6) if len(after) == 64 else 9
            if err > 0.6:
                problems.append("%s: loop seam mismatch (%.2f of its level)" % (name, err))
        rows.append((name, r["length"], 20 * np.log10(peak + 1e-12), 20 * np.log10(rms + 1e-12), r["loop"]))
    if "--table" in sys.argv:
        for row in rows:
            print("%-20s %7.2fs  peak %6.1f dB  rms %6.1f dB%s" % (row[0], row[1], row[2], row[3], "  loop" if row[4] else ""))
    total = sum(len(a) for a in banks.values()) / SR
    print("%d sounds, %d banks, %.0f s of audio" % (len(rows), len(banks), total))
    if problems:
        print("PROBLEMS:\n  " + "\n  ".join(problems))
        sys.exit(1)
    print("all sounds OK")


if __name__ == "__main__":
    main()

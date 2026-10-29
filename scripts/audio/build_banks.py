"""
Renders every sound, packs them into a few "bank" files and writes the map the
game uses to find each sound inside its bank.

    python3 scripts/audio/build_banks.py            # writes assets/audio/*.ogg
                                                     # and src/shared/Config/AudioBank.luau

Why banks: Roblox limits how many audio files an account can upload each month.
Packing ~80 sounds into 4 files keeps the whole game within that limit. The game
plays a slice of a bank with Sound.PlaybackRegion, and loops a slice with
Sound.LoopRegion.

Loops are written as [last 1 s][the loop][first 1 s] so that the region is
surrounded by its own continuation: a loop jump that lands a few samples early
or late still lands on matching audio.
"""

import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from dsp import SR, circular, highpass, n  # noqa: E402
from loops import LOOPS  # noqa: E402
from music import TRACKS  # noqa: E402
from sfx import LIB  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "audio")
LUAU_OUT = os.path.join(ROOT, "src", "shared", "Config", "AudioBank.luau")
JSON_OUT = os.path.join(OUT_DIR, "banks.json")

GAP = 0.25  # silence between one-shots
MARGIN = 1.0  # loop continuation on each side
MAX_BANK = 300.0  # seconds; Roblox accepts longer, this keeps uploads small

# Loudness targets (RMS dBFS) by category.
TARGET = {"ui": -27, "sfx": -22, "sting": -19, "ambience": -27, "presence": -22, "music": -21}


def level(sig, rms_db, peak_db=-3.0):
    """Match loudness to rms_db, but never push the peak above peak_db (no
    clipping or limiting: punchy one-shots simply come out a little quieter)."""
    rms = np.sqrt(np.mean(sig ** 2)) + 1e-12
    peak = np.max(np.abs(sig)) + 1e-12
    gain = min(10 ** (rms_db / 20) / rms, 10 ** (peak_db / 20) / peak)
    return sig * gain


def check(name, sig):
    if not np.all(np.isfinite(sig)):
        raise ValueError(name + " produced NaN/inf")
    if len(sig) == 0:
        raise ValueError(name + " is empty")


def render_oneshots():
    out = []
    for name in sorted(LIB):
        category, fn = LIB[name]
        sig = np.asarray(fn(), dtype=np.float64)
        check(name, sig)
        target = TARGET["ui"] if category == "ui" else TARGET.get(category, TARGET["sfx"])
        if name.startswith("Step_"):
            target = -24
        sig = highpass(sig, 25, 1)  # no DC or sub-sonic rumble
        sig = level(sig, target)
        # Trim trailing near-silence (reverb tails below -60 dB).
        loud = np.nonzero(np.abs(sig) > 10 ** (-60 / 20))[0]
        if len(loud):
            sig = sig[: loud[-1] + n(0.02)]
        out.append((name, category, sig))
    return out


def render_loops(source, kind):
    out = []
    for name in sorted(source):
        if kind == "music":
            period, fn = source[name]
            category = "music"
        else:
            category, period, fn = source[name]
        with circular():
            sig = np.asarray(fn(), dtype=np.float64)
        check(name, sig)
        if len(sig) != n(period):
            raise ValueError("%s is %d samples, expected one period of %d" % (name, len(sig), n(period)))
        sig = sig - np.mean(sig)  # remove DC; keeps the loop periodic
        sig = level(sig, TARGET[category], -2.0)
        seam = abs(sig[-1] - sig[0])
        typical = np.mean(np.abs(np.diff(sig))) * 6 + 1e-4
        if seam > typical:
            raise ValueError("%s does not loop cleanly (seam step %.4f > %.4f)" % (name, seam, typical))
        out.append((name, category, period, sig))
    return out


def pack(entries, bank, loops=False):
    """Concatenate entries; return (audio, regions)."""
    parts, regions, cursor = [], {}, 0.0
    for entry in entries:
        if loops:
            name, category, period, sig = entry
            m = n(MARGIN)
            seg = np.concatenate([sig[-m:], sig, sig[:m]])
            regions[name] = {"bank": bank, "start": round(cursor + MARGIN, 6), "length": round(period, 6), "loop": True, "category": category}
        else:
            name, category, sig = entry
            seg = np.concatenate([np.zeros(n(GAP)), sig, np.zeros(n(GAP))])
            regions[name] = {"bank": bank, "start": round(cursor + GAP, 6), "length": round(len(sig) / SR, 6), "loop": False, "category": category}
        parts.append(seg)
        cursor += len(seg) / SR
    return np.concatenate(parts), regions


def split(entries, loops, prefix):
    """Split entries into banks no longer than MAX_BANK seconds."""
    banks, current, length = [], [], 0.0
    for entry in entries:
        seconds = (entry[2] + 2 * MARGIN) if loops else (len(entry[2]) / SR + 2 * GAP)
        if current and length + seconds > MAX_BANK:
            banks.append(current)
            current, length = [], 0.0
        current.append(entry)
        length += seconds
    if current:
        banks.append(current)
    if len(banks) == 1:
        return [(prefix, banks[0])]
    return [("%s%d" % (prefix, i + 1), b) for i, b in enumerate(banks)]


def write_ogg(path, audio):
    peak = np.max(np.abs(audio))
    if peak > 0.999:
        audio = audio / peak * 0.999
    pcm = (audio * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, "bank.wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(
            ["ffmpeg", "-loglevel", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "4", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact", "-serial_offset", "1", path],
            check=True,
        )


def lua_number(x):
    return ("%.6f" % x).rstrip("0").rstrip(".")


def write_luau(banks, regions):
    lines = [
        "--[[",
        "\tGENERATED by scripts/audio/build_banks.py - do not edit by hand.",
        "",
        "\tWhere every sound lives inside the audio banks (assets/audio/*.ogg).",
        "\tstart/length are seconds into the bank; loop sounds repeat exactly that",
        "\tregion. Upload the banks and put their asset ids in Config/AudioAssets.",
        "]]",
        "",
        "local AudioBank = {}",
        "",
        "AudioBank.Banks = {",
    ]
    for name, info in sorted(banks.items()):
        lines.append('\t%s = { file = "%s", duration = %s },' % (name, info["file"], lua_number(info["duration"])))
    lines += ["}", "", "AudioBank.Sounds = {"]
    for name in sorted(regions):
        r = regions[name]
        lines.append(
            '\t%s = { bank = "%s", start = %s, length = %s, loop = %s },'
            % (name, r["bank"], lua_number(r["start"]), lua_number(r["length"]), "true" if r["loop"] else "false")
        )
    lines += ["}", "", "return AudioBank", ""]
    with open(LUAU_OUT, "w") as f:
        f.write("\n".join(lines))


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("rendering one-shots...")
    oneshots = render_oneshots()
    print("rendering loops...")
    ambience = render_loops(LOOPS, "ambience")
    print("rendering music...")
    music = render_loops(TRACKS, "music")

    banks, regions = {}, {}
    groups = split(oneshots, False, "Sfx") + split(ambience, True, "Ambience") + split(music, True, "Music")
    for bank_name, entries in groups:
        is_loop = len(entries[0]) == 4
        audio, regs = pack(entries, bank_name, loops=is_loop)
        file_name = "DeadAir_%s.ogg" % bank_name
        write_ogg(os.path.join(OUT_DIR, file_name), audio)
        banks[bank_name] = {"file": file_name, "duration": len(audio) / SR}
        regions.update(regs)
        print("  %-10s %6.1fs  %3d sounds  -> %s" % (bank_name, len(audio) / SR, len(entries), file_name))

    write_luau(banks, regions)
    with open(JSON_OUT, "w") as f:
        json.dump({"banks": banks, "sounds": regions}, f, indent=1, sort_keys=True)
    print("%d sounds in %d banks" % (len(regions), len(banks)))


if __name__ == "__main__":
    main()

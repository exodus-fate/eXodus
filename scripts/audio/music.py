"""
The score: eight looping tracks in the voice of a 1960s broadcaster's library
music, played back off worn tape. Organ, music box, vibraphone and strings for
the calm; pulse, bass and metal for the chase.

Each track is rendered into a buffer exactly one loop long, with note tails,
reverb and tape wobble wrapping around the seam, so it loops perfectly.
"""

import numpy as np

from dsp import (
    SR, additive, bandpass, brown, env_ad, env_adsr, highpass, lowpass, midi, n, pink, place, reverb, rng,
    saturate, saw, seamless, sine, sweep_lowpass, time, triangle, white, wow_flutter,
)

TRACKS = {}


def track(name, period):
    def wrap(fn):
        TRACKS[name] = (period, fn)
        return fn
    return wrap


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------


def organ(note, dur, seed=0, bright=1.0):
    f = midi(note)
    t = time(dur + 0.3)
    drawbars = [(0.5, 0.4), (1, 1.0), (2, 0.6 * bright), (3, 0.35 * bright), (4, 0.25 * bright), (6, 0.12 * bright), (8, 0.08 * bright)]
    tone = additive(f, dur + 0.3, [(r, a) for r, a in drawbars if f * r < 9000])
    leslie = 1 + 0.15 * np.sin(2 * np.pi * 5.8 * t + seed)
    return tone * leslie * env_adsr(dur + 0.3, 0.04, 0.1, 0.85, 0.3) * 0.18


def music_box(note, dur=2.0, seed=0):
    f = midi(note)
    t = time(dur)
    tine = np.sin(2 * np.pi * f * t) * np.exp(-t * 2.2) + 0.35 * np.sin(2 * np.pi * f * 3.0 * t) * np.exp(-t * 6)
    tine += 0.15 * np.sin(2 * np.pi * f * 5.98 * t) * np.exp(-t * 10)
    return tine * np.clip(t / 0.002, 0, 1) * 0.3


def vibes(note, dur=2.4, seed=0):
    f = midi(note)
    t = time(dur)
    bar = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 4 * t) * np.exp(-t * 5)
    trem = 1 + 0.3 * np.sin(2 * np.pi * 5.5 * t + seed)
    return bar * trem * np.exp(-t * 1.6) * np.clip(t / 0.003, 0, 1) * 0.22


def piano(note, dur=3.0, seed=0):
    f = midi(note)
    t = time(dur)
    out = np.zeros(len(t))
    for k in range(1, 9):
        inharm = k * np.sqrt(1 + 0.0004 * k * k)
        if f * inharm < 10000:
            out += np.sin(2 * np.pi * f * inharm * t) * np.exp(-t * (1.2 + 0.6 * k)) / k
    hammer = lowpass(white(0.02, seed + 900), 3000) * env_ad(0.02, 0.0005, 0.004) * 0.3
    out[: len(hammer)] += hammer
    return out * np.clip(t / 0.002, 0, 1) * 0.3


def pad(notes, dur, seed=0, cutoff=1400, attack=1.5):
    out = np.zeros(n(dur + 1.5))
    r = rng(seed)
    for note in notes:
        for d in (-0.08, 0.0, 0.09):
            f = midi(note + d)
            out[: n(dur + 1.5)] += saw(f * (1 + r.uniform(-0.001, 0.001)), dur + 1.5, 14)[: n(dur + 1.5)]
    out = lowpass(out, cutoff)
    return out * env_adsr(dur + 1.5, attack, 0.5, 0.8, 1.5) * 0.05


def strings(note, dur, seed=0, attack=0.15):
    f = midi(note)
    t = time(dur + 0.4)
    vib = f * (1 + 0.004 * np.sin(2 * np.pi * 5.2 * t + seed))
    tone = saw(vib, dur + 0.4, 18) + saw(vib * 1.003, dur + 0.4, 18) * 0.8
    tone = bandpass(tone, 180, 3500)
    return tone * env_adsr(dur + 0.4, attack, 0.1, 0.85, 0.4) * 0.12


def bass(note, dur, seed=0, drive=1.0):
    f = midi(note)
    tone = triangle(f, dur) + sine(f / 2, dur) * 0.2 + saw(f * 2, dur, 8) * 0.25
    tone = saturate(tone * drive, 1 + drive)
    return tone * env_adsr(dur, 0.005, 0.08, 0.7, 0.05) * 0.35


def kick(seed=0):
    t = time(0.5)
    body = np.sin(2 * np.pi * (55 + 90 * np.exp(-t * 35)) * t) * np.exp(-t * 9) * 0.5
    beater = bandpass(white(0.5, seed + 700), 1500, 5000) * env_ad(0.5, 0.0005, 0.008) * 0.25
    return body + beater


def tom(note=40, seed=0):
    t = time(0.8)
    f = midi(note)
    return (np.sin(2 * np.pi * f * (1 + 0.5 * np.exp(-t * 20)) * t) * np.exp(-t * 5) + lowpass(white(0.8, seed), 800) * np.exp(-t * 30) * 0.3) * 0.5


def tick(seed=0, freq=2500):
    s = white(0.04, seed) * env_ad(0.04, 0.0005, 0.006)
    return bandpass(s, freq * 0.8, freq * 1.3) * 0.5


def brush(seed=0):
    return bandpass(white(0.18, seed), 3000, 10000) * env_ad(0.18, 0.01, 0.05) * 0.12


def metal(seed=0, freq=520):
    hit = white(0.02, seed) * env_ad(0.02, 0.0003, 0.004)
    t = time(1.2)
    ring = sum(np.sin(2 * np.pi * freq * r * t) * np.exp(-t * (2 + i * 1.5)) / (1 + i) for i, r in enumerate((1, 1.47, 2.09, 2.76, 3.51)))
    ring[: len(hit)] += hit * 2
    return ring * 0.18


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


class Score:
    def __init__(self, period, bpm=60):
        self.period = period
        self.buf = np.zeros(n(period))
        self.beat = 60.0 / bpm

    def at(self, sig, beat_or_seconds, seconds=False):
        start = beat_or_seconds if seconds else beat_or_seconds * self.beat
        place(self.buf, sig, n(start), circular=True)

    def bed(self, sig):
        place(self.buf, sig, 0, circular=True)

    def tape(self, wow=0.004, cutoff=6000, hiss=0.01, seed=0, room=1.8, wet=0.3):
        # Thin out the sub-bass: small speakers can't play it and it masks the rest.
        out = reverb(highpass(self.buf, 45, 2), room, wet, seed + 1, circular=True)
        out = wow_flutter(out, wow, 0.5, 0.0006, 6.5, seed=seed + 2, circular=True)
        out = lowpass(out, cutoff)
        hiss_bed = highpass(seamless(white(self.period + 1, seed + 3), self.period, 1.0), 3000) * hiss
        return saturate(out + hiss_bed, 1.2)


def chord_notes(root, kind):
    shapes = {"m": (0, 3, 7), "M": (0, 4, 7), "m7": (0, 3, 7, 10), "M7": (0, 4, 7, 11), "7": (0, 4, 7, 10), "dim": (0, 3, 6)}
    return [root + i for i in shapes[kind]]


# ---------------------------------------------------------------------------
# Tracks
# ---------------------------------------------------------------------------


@track("MusicMenu", 64)
def music_menu():
    # A broadcaster's sign-off theme, slightly wrong. Am - F - Dm - E, twice.
    s = Score(64, 60)
    progression = [(57, "m"), (53, "M"), (50, "m"), (52, "M")]
    for rep in range(2):
        for i, (root, kind) in enumerate(progression):
            start = rep * 32 + i * 8
            for note in chord_notes(root, kind):
                # Second pass: the organ drifts a little flat.
                s.at(organ(note - (0.15 if rep == 1 else 0), 7.6, seed=i, bright=0.6), start)
            s.at(organ(root - 12, 7.6, seed=i + 5, bright=0.3) * 0.8, start)
    melody = [76, None, 74, 72, 71, None, 72, 74, 72, None, 69, None, 68, None, 71, None,
              76, None, 77, 76, 74, None, 72, 71, 69, None, 72, 71, 68, None, None, None]
    for rep in range(2):
        for i, note in enumerate(melody):
            if note:
                s.at(music_box(note + (0 if rep == 0 else -0.2), 2.4, seed=i), rep * 32 + i)
    s.bed(lowpass(seamless(brown(65, 501), 64, 1), 200) * 0.05)
    return s.tape(wow=0.006, cutoff=5000, hiss=0.012, seed=500, room=2.4, wet=0.35)


@track("MusicLobby", 51.2)
def music_lobby():
    # Field office library music: vibraphone over a soft organ, a touch too slow.
    s = Score(51.2, 75)
    progression = [(60, "M7"), (57, "m7"), (53, "M7"), (55, "7")]
    for cycle in range(4):
        for i, (root, kind) in enumerate(progression):
            bar = cycle * 16 + i * 4
            notes = chord_notes(root, kind)
            for note in notes:
                s.at(organ(note, 3.0, seed=i, bright=0.35) * 0.55, bar)
            s.at(bass(root - 24, 1.4) * 0.6, bar)
            s.at(bass(root - 17, 1.4) * 0.5, bar + 2)
            arp = notes + [notes[1] + 12]
            for k in range(8):
                note = arp[k % len(arp)] + 12
                s.at(vibes(note, 2.0, seed=k) * (0.9 if k % 2 == 0 else 0.6), bar + k * 0.5)
            for k in range(4):
                s.at(brush(510 + cycle * 16 + i * 4 + k), bar + k + 0.5)
    return s.tape(wow=0.004, cutoff=5500, hiss=0.008, seed=510, room=1.6, wet=0.3)


@track("MusicBriefing", 32)
def music_briefing():
    # Low drone under the radio briefing, a slow pulse like a held breath.
    s = Score(32, 60)
    s.bed(pad([38, 45, 50], 32, seed=520, cutoff=700, attack=4) * 1.5)
    for b in range(32):
        s.at(tom(45, 521 + b) * (0.5 if b % 4 == 0 else 0.25), b)
    for k, note in enumerate([62, 63, 62, 60]):
        s.at(strings(note, 6, seed=k, attack=2.5) * 1.0, k * 8 + 1)
    for b in (6.5, 14.25, 22.75, 29.5):
        s.at(sine(1400, 0.08) * env_ad(0.08, 0.002, 0.03) * 0.08, b)
    return s.tape(wow=0.003, cutoff=4000, hiss=0.003, seed=520, room=2.5, wet=0.35)


@track("MusicExplore", 64)
def music_explore():
    # The station at night: a sub drone, a piano in another room, distant swells.
    s = Score(64, 60)
    t = time(64)
    drone = (sine(55, 64) + sine(82.5, 64) * 0.4 + sine(110, 64) * 0.15) * (0.75 + 0.25 * np.sin(2 * np.pi * t / 32))
    s.bed(drone * 0.08)
    r = rng(530)
    phrase = [57, 60, 64, 63, 57, 56, 60, 52]
    for i, note in enumerate(phrase):
        s.at(piano(note, 4.0, seed=i) * 1.3, i * 8 + r.uniform(0, 2.5))
    for start, notes in ((4, [69, 70]), (36, [72, 73])):
        for note in notes:
            s.at(strings(note, 10, seed=start, attack=4) * 0.6, start)
    s.bed(bandpass(seamless(pink(65, 531), 64, 1), 200, 1200) * 0.03)
    return s.tape(wow=0.004, cutoff=4500, hiss=0.0025, seed=530, room=3.5, wet=0.45)


@track("MusicTension", 32)
def music_tension():
    # Something is close. A low string ostinato, a clock, a cluster that swells.
    s = Score(32, 120)
    figure = [45, 45, 46, 45, 45, 45, 46, 48]
    for bar in range(16):
        for k, note in enumerate(figure):
            s.at(strings(note, 0.22, seed=k, attack=0.01) * (1.0 if k == 0 else 0.7), bar * 4 + k * 0.5)
    for b in range(64):
        s.at(tick(540 + b, 3000 if b % 2 == 0 else 2400), b)
    for start in (0, 16, 32, 48):
        for note in (69, 70, 71):
            s.at(strings(note, 7, seed=start, attack=5) * 0.35, start)
    return s.tape(wow=0.003, cutoff=6000, hiss=0.003, seed=540, room=2.0, wet=0.3)


@track("MusicHunt", 25.6)
def music_hunt():
    # The chase: 150 bpm, driven bass in A phrygian, metal and sirens.
    s = Score(25.6, 150)
    pattern = [45, 45, 46, 45, 45, 48, 45, 46, 45, 45, 46, 45, 43, 45, 46, 48]
    for bar in range(16):
        for b in range(4):
            s.at(kick(550 + bar * 4 + b), bar * 4 + b)
        for k, note in enumerate(pattern):
            s.at(bass(note + (12 if bar % 4 == 3 and k >= 12 else 0), 0.14, drive=2.5) * 0.9, bar * 4 + k * 0.25)
        s.at(metal(560 + bar, 520 if bar % 2 == 0 else 466) * 1.6, bar * 4 + 1.5)
        s.at(tick(570 + bar, 6000) * 0.6, bar * 4 + 3.5)
    for start in (0, 8, 16, 24, 32, 40, 48, 56):
        t = time(3.2)
        f = midi(69) * (1 + 0.06 * np.sin(2 * np.pi * 2.5 * t))
        siren = (saw(f, 3.2, 10) + saw(f * 1.059, 3.2, 10) * 0.7) * env_adsr(3.2, 0.4, 0.3, 0.6, 1.0) * 0.14
        s.at(lowpass(siren, 2500), start)
    riser = sweep_lowpass(white(3.2, 580), 300, 9000) * np.linspace(0, 1, n(3.2)) ** 2 * 0.15
    s.at(riser, 28.8)
    s.at(riser, 60.8)
    return s.tape(wow=0.002, cutoff=8000, hiss=0.004, seed=550, room=1.2, wet=0.2)


@track("MusicExtract", 32)
def music_extract():
    # Get out: timpani eighths, rising string chords, a heartbeat kick.
    s = Score(32, 120)
    chords = [(57, "m"), (58, "M"), (60, "M"), (62, "M")]
    for i, (root, kind) in enumerate(chords * 2):
        start = i * 8
        for note in chord_notes(root, kind):
            s.at(strings(note, 3.8, seed=i, attack=0.6) * 0.45, start)
            s.at(strings(note + 12, 3.8, seed=i + 9, attack=0.8) * 0.25, start)
    for b in range(128):
        s.at(tom(45 if b % 4 else 43, 590 + b) * (0.7 if b % 2 == 0 else 0.4), b * 0.5)
    for b in range(0, 64, 2):
        s.at(kick(600 + b) * 0.4, b)
    return s.tape(wow=0.002, cutoff=7500, hiss=0.006, seed=590, room=1.6, wet=0.25)


@track("MusicReport", 48)
def music_report():
    # The case report: a slow organ hymn and a music box, played back too many times.
    s = Score(48, 60)
    progression = [(50, "m"), (46, "M"), (53, "M"), (48, "M")]
    for rep in range(2):
        for i, (root, kind) in enumerate(progression):
            start = rep * 24 + i * 6
            for note in chord_notes(root, kind):
                s.at(organ(note, 5.6, seed=i, bright=0.45) * 0.8, start)
            s.at(organ(root - 12, 5.6, seed=i + 3, bright=0.2) * 0.7, start)
    melody = [74, 72, 70, 69, 70, 72, 74, 77, 76, 74, 72, 69]
    for rep in range(2):
        for i, note in enumerate(melody):
            s.at(music_box(note, 2.6, seed=i) * 0.9, rep * 24 + i * 2)
    return s.tape(wow=0.007, cutoff=4500, hiss=0.012, seed=610, room=2.6, wet=0.4)

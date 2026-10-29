"""
Looping beds: room tones, machinery and the Presenter's presence.

Every loop is returned exactly periodic (its last sample flows into its first),
so the game can loop it with a LoopRegion with no click.
"""

import numpy as np

from dsp import (
    SR, additive, bandpass, brown, crackle, env_ad, highpass, lowpass, n, pink, place, reverb, rng, saturate,
    seamless, sine, sweep_lowpass, time, white, wow_flutter,
)

LOOPS = {}


def loop(name, period, category="ambience"):
    def wrap(fn):
        LOOPS[name] = (category, period, fn)
        return fn
    return wrap


def noise_bed(period, seed, fn):
    """fn(seconds, seed) -> noise; returns a seamless loop of `period`."""
    return seamless(fn(period + 1.0, seed), period, 1.0)


def events(buf, period, seed, count, make):
    """Scatter one-off details through a loop (wrapping at the seam)."""
    r = rng(seed)
    for i in range(count):
        place(buf, make(i, r), r.integers(0, n(period)), circular=True)
    return buf


def tick(seed, freq):
    s = white(0.03, seed) * env_ad(0.03, 0.0005, 0.005)
    return bandpass(s, freq * 0.7, freq * 1.4)


@loop("AmbStation", 40)
def amb_station():
    p = 40
    rumble = lowpass(noise_bed(p, 300, brown), 380) * 0.6
    vent = bandpass(noise_bed(p, 301, pink), 1500, 6000) * 0.07
    hum = (sine(60, p) + sine(120, p) * 0.4) * 0.03
    out = rumble + vent + hum
    # Building settling: ticks, pipe knocks and a far-off door.
    out = events(out, p, 302, 10, lambda i, r: tick(303 + i, r.uniform(1500, 4000)) * r.uniform(0.05, 0.15))
    knock = lambda i, r: lowpass(white(0.3, 320 + i), 700) * env_ad(0.3, 0.002, 0.04) * r.uniform(0.1, 0.2)
    out = events(out, p, 310, 4, knock)
    return reverb(out, 2.5, 0.35, 330, brightness=2500, circular=True)


@loop("AmbDark", 40)
def amb_dark():
    p = 40
    t = time(p)
    rumble = lowpass(noise_bed(p, 340, brown), 160) * (0.8 + 0.2 * np.sin(2 * np.pi * t / p * 2))
    whine = sine(3520, p) * 0.004 * (0.5 + 0.5 * np.sin(2 * np.pi * t / p * 3))
    out = rumble + whine
    thump = lambda i, r: lowpass(white(1.2, 350 + i), 200) * env_ad(1.2, 0.01, 0.3) * r.uniform(0.2, 0.4)
    out = events(out, p, 341, 3, thump)
    return reverb(out, 3.5, 0.45, 360, brightness=1500, circular=True)


@loop("AmbHQ", 30)
def amb_hq():
    p = 30
    aircon = lowpass(noise_bed(p, 370, pink), 1400) * 0.3
    hum = (sine(50, p) + sine(100, p) * 0.5) * 0.015
    out = aircon + hum
    # Distant typing and paper from the next office.
    def typing(i, r):
        burst = np.zeros(n(1.5))
        for k in range(r.integers(4, 9)):
            place(burst, tick(380 + i * 10 + k, 2000) * 0.08, int(r.uniform(0, 1.3) * SR))
        return lowpass(burst, 3000)
    out = events(out, p, 371, 4, typing)
    return reverb(out, 1.2, 0.3, 390, circular=True)


@loop("AmbOutdoor", 40)
def amb_outdoor():
    p = 40
    t = time(p)
    gust = 0.55 + 0.45 * np.sin(2 * np.pi * t / p * 3 + 1) * np.sin(2 * np.pi * t / p * 2)
    wind = lowpass(noise_bed(p, 400, pink), 900) * gust
    whistle = bandpass(noise_bed(p, 401, white), 700, 900) * gust ** 2 * 0.15
    far = lowpass(noise_bed(p, 402, brown), 120) * 0.3
    return wind * 0.6 + whistle + far


@loop("Fluorescent", 4)
def fluorescent():
    p = 4
    t = time(p)
    hum = additive(120, p, [(1, 1), (2, 0.5), (3, 0.3), (5, 0.15), (7, 0.08)]) * 0.25
    buzz = bandpass(noise_bed(p, 410, white), 2000, 7000) * (0.5 + 0.5 * np.abs(np.sin(2 * np.pi * 120 * t))) * 0.12
    return saturate(hum + buzz, 1.3)


@loop("GeneratorLoop", 4)
def generator_loop():
    p = 4
    t = time(p)
    firing = np.zeros(n(p))
    r = rng(420)
    for k in range(100):  # 25 Hz firing, 100 per loop
        pos = int((k / 25 + r.uniform(-0.002, 0.002)) * SR) % n(p)
        place(firing, lowpass(white(0.03, 421 + k), 500) * env_ad(0.03, 0.001, 0.008), pos, circular=True)
    body = lowpass(firing, 350) * 3
    harmonics = additive(25, p, [(1, 0.6), (2, 0.4), (3, 0.3), (4, 0.15)]) * 0.3
    clatter = bandpass(noise_bed(p, 430, white), 1500, 5000) * (0.6 + 0.4 * np.sin(2 * np.pi * 25 * t)) * 0.08
    return saturate(body + harmonics + clatter, 1.5)


@loop("TransmitterLoop", 4)
def transmitter_loop():
    p = 4
    hum = additive(50, p, [(1, 0.5), (2, 0.6), (3, 0.4), (4, 0.3), (6, 0.2), (8, 0.1)]) * 0.35
    whine = sine(2000, p) * 0.03
    arcs = crackle(p, 440, 25) * 0.25
    return saturate(hum + whine + highpass(arcs, 1500), 1.4)


@loop("VanIdle", 4)
def van_idle():
    p = 4
    t = time(p)
    idle = additive(14, p, [(1, 0.5), (2, 0.6), (3, 0.3), (4, 0.2), (6, 0.1)]) * (0.8 + 0.2 * np.sin(2 * np.pi * 14 * t))
    rattle = bandpass(noise_bed(p, 450, white), 800, 3000) * 0.05
    return lowpass(idle * 0.5, 500) + rattle


@loop("PresenterNear", 8, "presence")
def presenter_near():
    p = 8
    t = time(p)
    drone = sine(45, p) * 0.5 + sine(47.5, p) * 0.4 + sine(90, p) * 0.15
    flutter_tone = sine(220, p) * (0.5 + 0.5 * np.sin(2 * np.pi * t * 0.75)) * 0.08
    whisper = bandpass(noise_bed(p, 460, pink), 500, 3000) * (0.5 + 0.5 * np.sin(2 * np.pi * t * 0.5 + 2)) * 0.12
    out = wow_flutter(drone + flutter_tone + whisper, 0.006, 0.5, seed=461, circular=True)
    return reverb(out, 2.0, 0.3, 462, brightness=2000, circular=True)


@loop("PresenterStatic", 4, "presence")
def presenter_static():
    p = 4
    snow = bandpass(noise_bed(p, 470, white), 400, 7000) * 0.4
    sizzle = crackle(p, 471, 80) * 0.3
    line = sine(15625 / 2, p) * 0.01
    return snow + sizzle + line


@loop("RadioBed", 4)
def radio_bed():
    p = 4
    return bandpass(noise_bed(p, 480, white), 400, 3200) * 0.3 + crackle(p, 481, 15) * 0.1


@loop("DeckHum", 4)
def deck_hum():
    p = 4
    hum = (sine(60, p) + sine(180, p) * 0.3) * 0.15
    whine = sine(12000, p) * 0.012
    snow = bandpass(noise_bed(p, 490, white), 2000, 8000) * 0.04
    return hum + whine + snow


@loop("TapeScrub", 2)
def tape_scrub():
    p = 2
    t = time(p)
    whine = sine(900, p) * 0.3 + sine(1800, p) * 0.1
    hiss = bandpass(noise_bed(p, 495, white), 2000, 9000) * 0.12
    return wow_flutter(whine + hiss, 0.006, 6, seed=496, circular=True) * (0.85 + 0.15 * np.sin(2 * np.pi * 8 * t))

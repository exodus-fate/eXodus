"""
One-shot sound effects for DEAD AIR: CHANNEL ZERO, all synthesised here.

Each function returns a mono array. The bank builder normalises loudness by
category, so absolute levels here only matter within a sound.
"""

import numpy as np

from dsp import (
    SR, additive, bandpass, brown, crackle, env_ad, env_adsr, fade, highpass, lowpass, mix, n, peak, pink,
    pitch, ramp, resonators, reverb, rng, saturate, saw, silence, sine, square, sweep_lowpass, tape_stop,
    time, triangle, white, wow_flutter,
)


# ---------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------


def click(seed, freq=3000, length=0.02, q=6):
    """A small mechanical click: a noise tick through a body resonance."""
    s = white(length, seed) * env_ad(length, 0.0005, length / 6)
    return resonators(s, [(freq, q, 6), (freq * 1.7, q, 3)])


def thud(freq=70, length=0.35, seed=1, noise=0.4):
    t = time(length)
    body = np.sin(2 * np.pi * (freq + 40 * np.exp(-t * 30)) * t) * np.exp(-t * 9)
    hit = lowpass(white(length, seed), 900) * np.exp(-t * 40) * noise
    return body + hit


def bell(freq, length, seed=0, ratios=(1, 2.76, 5.4, 8.93), decay=1.6, strike=0.6):
    t = time(length)
    out = np.zeros(len(t))
    r = rng(seed)
    for i, ratio in enumerate(ratios):
        detune = 1 + r.uniform(-0.002, 0.002)
        out += np.sin(2 * np.pi * freq * ratio * detune * t) * np.exp(-t * decay * (1 + i * 0.9)) / (1 + i)
    c = click(seed, freq * 3, 0.01) * strike * 0.2
    out[: len(c)] += c[: len(out)]
    return out


def static_burst(length, seed, band=(300, 7000), crackles=60):
    s = bandpass(white(length, seed), *band) + crackle(length, seed + 1, crackles) * 0.6
    return s


def motor(length, f0, f1, seed=2):
    f = ramp(length, f0, f1)
    s = saw(f, length, 12) * 0.6 + bandpass(white(length, seed), 300, 2500) * 0.2
    return lowpass(s, 1800)


def footstep(kind, variant):
    seed = 100 + variant * 7 + {"tile": 1, "concrete": 2, "carpet": 3, "metal": 4}[kind] * 13
    r = rng(seed)
    if kind == "tile":
        # Hard heel click on ceramic over a short body.
        heel = resonators(white(0.06, seed) * env_ad(0.06, 0.0005, 0.008), [(2600 + r.uniform(-200, 200), 5, 6), (4100, 6, 4)])
        body = lowpass(white(0.12, seed + 1), 900) * env_ad(0.12, 0.002, 0.025) * 0.6
        scuff = bandpass(white(0.09, seed + 2), 2000, 7000) * env_ad(0.09, 0.02, 0.03) * 0.15
        s = mix(heel, body, np.concatenate([silence(0.03), scuff]))
    elif kind == "carpet":
        s = lowpass(white(0.16, seed), 700) * env_ad(0.16, 0.006, 0.04)
        s += bandpass(white(0.16, seed + 1), 900, 2500) * env_ad(0.16, 0.02, 0.05) * 0.12
    elif kind == "metal":
        hit = white(0.03, seed) * env_ad(0.03, 0.0005, 0.006)
        ring = resonators(hit, [(420 + r.uniform(-30, 30), 30, 18), (1130, 40, 12), (2210, 50, 8)])
        ring = np.concatenate([ring, np.zeros(n(0.25))])
        tail = additive(430 + r.uniform(-20, 20), 0.28, [(1, 0.5), (2.63, 0.3), (5.1, 0.15)]) * env_ad(0.28, 0.001, 0.07) * 0.3
        s = mix(ring, tail, lowpass(white(0.1, seed + 2), 600) * env_ad(0.1, 0.001, 0.02) * 0.6)
    else:  # concrete
        s = bandpass(white(0.14, seed), 200, 3200) * env_ad(0.14, 0.001, 0.02)
        s += bandpass(white(0.14, seed + 1), 2500, 8000) * env_ad(0.14, 0.015, 0.035) * 0.25  # grit
        s = mix(s, lowpass(white(0.1, seed + 2), 300) * env_ad(0.1, 0.002, 0.02) * 0.5)
    return fade(pitch(s, r.uniform(0.94, 1.06)), 0.001, 0.02)


# ---------------------------------------------------------------------------
# Library: name -> (category, function)
# category: ui | sfx | sting | voice
# ---------------------------------------------------------------------------

LIB = {}


def sound(name, category="sfx"):
    def wrap(fn):
        LIB[name] = (category, fn)
        return fn
    return wrap


# --- Interface -------------------------------------------------------------

@sound("UIHover", "ui")
def ui_hover():
    return fade(click(11, 4200, 0.015) * 0.5)


@sound("UIClick", "ui")
def ui_click():
    # A relay closing: two contacts, a hint of hum.
    a = click(12, 2400, 0.03)
    b = click(13, 1800, 0.025) * 0.6
    hum = sine(120, 0.05) * env_ad(0.05, 0.001, 0.015) * 0.15
    return fade(mix(a, np.concatenate([silence(0.012), b]), hum))


@sound("UIBack", "ui")
def ui_back():
    return fade(mix(click(14, 1400, 0.03), np.concatenate([silence(0.015), click(15, 1100, 0.03) * 0.7])))


@sound("UIToggle", "ui")
def ui_toggle():
    return fade(mix(click(16, 3000, 0.02), np.concatenate([silence(0.05), click(17, 2200, 0.02)])))


@sound("UISlider", "ui")
def ui_slider():
    return fade(click(18, 5200, 0.01) * 0.4)


@sound("UIError", "ui")
def ui_error():
    s = square(150, 0.28, 10) * env_adsr(0.28, 0.005, 0.05, 0.7, 0.06)
    return fade(lowpass(s, 2500) * 0.6)


@sound("UINotify", "ui")
def ui_notify():
    # Teletype tick-tick-tick then a soft blip.
    out = silence(0.32)
    for i in range(3):
        start = n(0.045 * i)
        out[start:start + n(0.02)] += click(20 + i, 2800, 0.02)[: n(0.02)] * 0.8
    blip = sine(1760, 0.12) * env_ad(0.12, 0.003, 0.04) * 0.4
    return fade(mix(out, np.concatenate([silence(0.16), blip])))


@sound("MenuOpen", "ui")
def menu_open():
    # CRT switching on: thump, rising whine, settling static.
    t = time(0.9)
    thump = thud(55, 0.5, 30, 0.2)
    whine = np.sin(2 * np.pi * (6000 + 3000 * (1 - np.exp(-t * 6))) * t) * env_ad(0.9, 0.05, 0.4) * 0.05
    hiss = bandpass(white(0.9, 31), 1000, 8000) * env_ad(0.9, 0.02, 0.15) * 0.25
    return fade(mix(thump, whine, hiss))


@sound("MenuClose", "ui")
def menu_close():
    t = time(0.4)
    pop = click(33, 900, 0.03) * 1.2
    fall = np.sin(2 * np.pi * (900 * np.exp(-t * 8) + 60) * t) * env_ad(0.4, 0.002, 0.08) * 0.3
    return fade(mix(pop, fall))


@sound("TutorialPage", "ui")
def tutorial_page():
    # Paper sliding across a desk.
    s = bandpass(white(0.35, 40), 1500, 9000) * env_adsr(0.35, 0.08, 0.1, 0.5, 0.15)
    return fade(s * 0.6)


@sound("Countdown", "ui")
def countdown():
    return fade(mix(click(41, 1600, 0.03), sine(880, 0.08) * env_ad(0.08, 0.001, 0.03) * 0.3))


@sound("Ready", "ui")
def ready():
    # A rubber stamp on paper.
    return fade(mix(thud(110, 0.25, 42, 0.8), click(43, 700, 0.04) * 0.5))


@sound("Deploy", "ui")
def deploy():
    # Van door rolling shut and the engine turning over.
    t = time(2.2)
    roll = lowpass(brown(0.6, 44), 900) * env_adsr(0.6, 0.05, 0.1, 0.7, 0.1) * 0.8
    slam = mix(thud(60, 0.5, 45, 0.8), click(46, 500, 0.05) * 0.4)
    crank = np.zeros(len(t))
    for i in range(6):
        pos = n(0.8 + i * 0.11)
        crank[pos:pos + n(0.08)] += lowpass(white(0.08, 47 + i), 500) * env_ad(0.08, 0.004, 0.02)
    engine = saw(ramp(1.0, 18, 32), 1.0, 8) * env_adsr(1.0, 0.2, 0.2, 0.8, 0.3) * 0.5
    out = mix(roll, np.concatenate([silence(0.55), slam]), crank, np.concatenate([silence(1.2), lowpass(engine, 400)]))
    return fade(reverb(out, 0.8, 0.2, 48))


@sound("RewardTick", "ui")
def reward_tick():
    return fade(bell(1568, 0.3, 50, decay=9, strike=0.2) * 0.5)


@sound("Unlock", "ui")
def unlock():
    out = silence(1.4)
    for i, f in enumerate([523, 659, 784, 1047]):
        out = mix(out, np.concatenate([silence(0.09 * i), bell(f, 1.0, 51 + i, decay=3.5)]))
    return fade(reverb(out, 1.0, 0.25, 52))


@sound("ReportKey", "ui")
def report_key():
    # Typewriter type-bar strike.
    return fade(mix(click(53, 1900, 0.025) * 1.2, thud(180, 0.08, 54, 0.3) * 0.5))


@sound("ReportStamp", "ui")
def report_stamp():
    return fade(reverb(mix(thud(90, 0.4, 55, 1.0), click(56, 600, 0.05)), 0.6, 0.2, 57))


@sound("VoteChime", "ui")
def vote_chime():
    return fade(mix(bell(784, 0.9, 58, decay=4), np.concatenate([silence(0.22), bell(1047, 0.9, 59, decay=4)])))


# --- Player ----------------------------------------------------------------

for _kind in ("tile", "concrete", "carpet", "metal"):
    for _v in range(4):
        def _make(kind=_kind, v=_v):
            return footstep(kind, v)
        LIB["Step_%s_%d" % (_kind, _v + 1)] = ("sfx", _make)


@sound("FlashlightOn")
def flashlight_on():
    return fade(mix(click(60, 3400, 0.02), np.concatenate([silence(0.03), click(61, 2100, 0.02) * 0.6])))


@sound("FlashlightOff")
def flashlight_off():
    return fade(mix(click(62, 2900, 0.02), np.concatenate([silence(0.025), click(63, 1700, 0.02) * 0.5])))


@sound("BreathOut")
def breath_out():
    # Winded exhale after running out of stamina.
    s = bandpass(pink(0.9, 64), 350, 2400)
    s = peak(s, 900, 3, 3)
    return fade(s * env_adsr(0.9, 0.08, 0.2, 0.6, 0.4) * 0.7)


@sound("BreathIn")
def breath_in():
    s = bandpass(pink(0.6, 65), 600, 3500)
    return fade(s * env_adsr(0.6, 0.25, 0.1, 0.7, 0.2) * 0.5)


@sound("Heartbeat")
def heartbeat():
    t = time(0.7)
    lub = np.sin(2 * np.pi * (52 + 25 * np.exp(-t * 25)) * t) * np.exp(-t * 18)
    t2 = time(0.5)
    dub = np.sin(2 * np.pi * (44 + 20 * np.exp(-t2 * 25)) * t2) * np.exp(-t2 * 20) * 0.7
    return fade(lowpass(mix(lub, np.concatenate([silence(0.18), dub])), 200))


@sound("ToolEquip")
def tool_equip():
    # Camcorder: lens motor and a latch.
    return fade(mix(motor(0.45, 140, 220, 66) * env_adsr(0.45, 0.03, 0.05, 0.8, 0.1) * 0.5, click(67, 1500, 0.03)))


@sound("ToolUnequip")
def tool_unequip():
    return fade(mix(motor(0.3, 220, 120, 68) * env_adsr(0.3, 0.02, 0.05, 0.8, 0.1) * 0.4, np.concatenate([silence(0.25), click(69, 1300, 0.03)])))


@sound("RecBeep")
def rec_beep():
    beep = sine(2093, 0.07) * env_adsr(0.07, 0.002, 0.01, 0.9, 0.01)
    return fade(mix(beep, np.concatenate([silence(0.11), beep])) * 0.5)


@sound("Inspect")
def inspect():
    return fade(motor(0.25, 300, 420, 70) * env_adsr(0.25, 0.02, 0.05, 0.6, 0.1) * 0.25)


@sound("PromptHold")
def prompt_hold():
    return fade(click(71, 2000, 0.02) * 0.4)


@sound("PickupTape")
def pickup_tape():
    # Plastic VHS shell knocked against a shelf, then lifted.
    a = resonators(white(0.04, 72) * env_ad(0.04, 0.0005, 0.006), [(1800, 8, 8), (3300, 10, 4)])
    b = resonators(white(0.04, 73) * env_ad(0.04, 0.0005, 0.005), [(2100, 8, 6)]) * 0.6
    rattle = bandpass(white(0.25, 74), 2000, 6000) * env_ad(0.25, 0.01, 0.05) * 0.15
    return fade(mix(a, np.concatenate([silence(0.06), b]), np.concatenate([silence(0.08), rattle])))


@sound("PickupMetal")
def pickup_metal():
    hit = white(0.02, 75) * env_ad(0.02, 0.0003, 0.004)
    ring = resonators(np.concatenate([hit, np.zeros(n(0.6))]), [(2150, 80, 30), (3430, 90, 20), (5260, 90, 10)])
    return fade(ring * 0.5)


@sound("PickupKey")
def pickup_key():
    out = silence(0.4)
    for i in range(4):
        hit = white(0.015, 76 + i) * env_ad(0.015, 0.0003, 0.003)
        ring = resonators(np.concatenate([hit, np.zeros(n(0.2))]), [(3600 + i * 300, 60, 20), (5800, 60, 10)])
        out = mix(out, np.concatenate([silence(0.05 * i), ring * 0.4]))
    return fade(out)


# --- Doors and the building -----------------------------------------------

@sound("DoorOpen")
def door_open():
    # Latch, then a hinge creak (stick-slip friction through the door's body).
    r = rng(80)
    length = 1.1
    t = time(length)
    rate = 18 + 30 * np.sin(np.pi * t / length) + r.normal(0, 3, len(t)).cumsum() / 400
    pulses = np.sin(2 * np.pi * np.cumsum(rate) / SR)
    stick = (pulses > 0.97).astype(float)
    creak = resonators(stick * 0.8 + white(length, 81) * 0.02, [(620, 12, 20), (1450, 15, 12), (2700, 20, 6)])
    creak = bandpass(creak, 250, 5000) * env_adsr(length, 0.15, 0.2, 0.8, 0.3) * 0.35
    latch = mix(click(82, 1300, 0.04), np.concatenate([silence(0.05), click(83, 900, 0.04) * 0.6]))
    return fade(reverb(mix(latch, np.concatenate([silence(0.08), creak])), 0.9, 0.2, 84))


@sound("DoorClose")
def door_close():
    s = mix(thud(65, 0.5, 85, 0.6), np.concatenate([silence(0.02), click(86, 1100, 0.04) * 0.7]))
    return fade(reverb(s, 1.0, 0.25, 87))


@sound("DoorLocked")
def door_locked():
    out = silence(0.6)
    for i in range(3):
        rat = mix(click(88 + i, 900, 0.05), thud(140, 0.12, 91 + i, 0.6) * 0.4)
        out = mix(out, np.concatenate([silence(0.13 * i), rat]))
    return fade(out)


@sound("DoorForced")
def door_forced():
    # Something hits the door from the other side.
    bang = mix(thud(48, 0.9, 95, 1.2), lowpass(white(0.4, 96), 2500) * env_ad(0.4, 0.001, 0.05))
    rattle = bandpass(white(0.5, 97), 600, 3000) * env_ad(0.5, 0.01, 0.12) * 0.3
    return fade(reverb(mix(bang, rattle), 1.6, 0.35, 98))


@sound("FreightDoor")
def freight_door():
    length = 3.2
    rumble = lowpass(brown(length, 100), 300) * env_adsr(length, 0.3, 0.3, 0.9, 0.6)
    chain = np.zeros(n(length))
    for i in range(int(length * 9)):
        pos = n(0.1 + i * 0.105)
        c = resonators(white(0.02, 101 + i) * env_ad(0.02, 0.0005, 0.004), [(1900 + (i % 3) * 300, 30, 10)])
        chain = mix(chain, np.concatenate([silence(pos / SR), c * 0.25]))[: n(length)]
    clang = np.concatenate([silence(length - 0.4), thud(55, 0.4, 130, 0.9)])
    return fade(reverb(mix(rumble, chain, clang), 2.0, 0.35, 131))


@sound("KeypadPress")
def keypad_press():
    beep = sine(1209, 0.09) * env_adsr(0.09, 0.002, 0.01, 0.9, 0.02) * 0.5
    return fade(mix(click(132, 2600, 0.015) * 0.6, beep))


@sound("KeypadWrong")
def keypad_wrong():
    s = square(165, 0.5, 12) * env_adsr(0.5, 0.005, 0.05, 0.8, 0.08)
    return fade(lowpass(saturate(s, 2), 3000) * 0.6)


@sound("KeypadRight")
def keypad_right():
    a = sine(880, 0.12) * env_adsr(0.12, 0.002, 0.02, 0.9, 0.02)
    b = sine(1320, 0.18) * env_adsr(0.18, 0.002, 0.02, 0.9, 0.05)
    solenoid = mix(thud(150, 0.2, 133, 0.5), click(134, 800, 0.04))
    return fade(mix(a * 0.5, np.concatenate([silence(0.13), b * 0.5]), np.concatenate([silence(0.35), solenoid])))


@sound("CageOpen")
def cage_open():
    # Wire-mesh door swinging on a dry hinge.
    rattle = bandpass(white(0.9, 135), 1500, 6000) * env_adsr(0.9, 0.02, 0.2, 0.4, 0.4) * 0.3
    creak = door_open()[: n(1.0)] * 0.7
    return fade(mix(rattle, creak))


@sound("Install")
def install():
    # A component seated into its socket: slide, heavy clunk, ratchet.
    slide = bandpass(white(0.3, 136), 800, 4000) * env_adsr(0.3, 0.1, 0.05, 0.6, 0.1) * 0.4
    clunk = mix(thud(80, 0.5, 137, 1.0), click(138, 700, 0.05) * 0.8)
    ratchet = silence(0.5)
    for i in range(5):
        ratchet = mix(ratchet, np.concatenate([silence(0.07 * i), click(139 + i, 2400, 0.02) * 0.5]))
    return fade(reverb(mix(slide, np.concatenate([silence(0.25), clunk]), np.concatenate([silence(0.7), ratchet])), 1.0, 0.2, 145))


@sound("Relay")
def relay():
    # Industrial contactor slamming in, with a brief arc buzz.
    buzz = saturate(sine(100, 0.2) + sine(300, 0.2) * 0.3, 3) * env_ad(0.2, 0.001, 0.05) * 0.4
    return fade(mix(thud(120, 0.3, 146, 1.0), click(147, 1500, 0.04), buzz))


@sound("GeneratorPrime")
def generator_prime():
    # Hand-primed fuel pump strokes then a crank that slows.
    out = silence(2.6)
    for i in range(4):
        stroke = mix(click(148 + i, 700, 0.04), lowpass(white(0.15, 152 + i), 900) * env_ad(0.15, 0.03, 0.04) * 0.6)
        out = mix(out, np.concatenate([silence(0.35 * i), stroke]))
    for i in range(7):
        gap = 1.45 + 0.13 * i + 0.01 * i * i
        chuff = lowpass(white(0.12, 160 + i), 600) * env_ad(0.12, 0.005, 0.03)
        out = mix(out, np.concatenate([silence(gap), chuff]))
    return fade(reverb(out, 1.2, 0.25, 170))


@sound("GeneratorStart")
def generator_start():
    length = 3.5
    t = time(length)
    rate = ramp(length, 4, 26, 0.6)
    firing = (np.sin(2 * np.pi * np.cumsum(rate) / SR) > 0.85).astype(float)
    body = lowpass(firing, 400) * 3 + lowpass(brown(length, 171), 250) * 0.4
    hum = saw(ramp(length, 25, 50), length, 10) * np.clip(t / length, 0, 1) * 0.3
    return fade(reverb(mix(body * env_adsr(length, 0.1, 0.1, 1, 0.3), lowpass(hum, 600)), 1.4, 0.3, 172))


@sound("PowerOn")
def power_on():
    # Breakers thrown, then the tubes strike one by one.
    out = mix(thud(70, 0.5, 173, 1.0), click(174, 900, 0.05))
    hum = (sine(120, 1.6) + sine(240, 1.6) * 0.4) * env_adsr(1.6, 0.4, 0.2, 0.6, 0.5) * 0.25
    out = mix(out, np.concatenate([silence(0.2), hum]))
    for i in range(5):
        ping = mix(click(175 + i, 3500, 0.02) * 0.5, sine(4800 + i * 200, 0.15) * env_ad(0.15, 0.001, 0.04) * 0.08)
        out = mix(out, np.concatenate([silence(0.35 + 0.17 * i + (i % 2) * 0.05), ping]))
    return fade(reverb(out, 1.5, 0.3, 180))


@sound("LightsFail")
def lights_fail():
    # Mains collapsing: a dropping whine and a final clunk.
    length = 1.8
    t = time(length)
    f = 120 * np.exp(-t * 1.6) + 20
    whine = (np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.4 * np.sin(4 * np.pi * np.cumsum(f) / SR)) * env_adsr(length, 0.005, 0.2, 0.8, 0.6)
    fizz = bandpass(white(0.4, 181), 2000, 9000) * env_ad(0.4, 0.001, 0.08) * 0.3
    clunk = np.concatenate([silence(1.2), thud(60, 0.5, 182, 0.8)])
    return fade(reverb(mix(whine * 0.5, fizz, clunk), 1.6, 0.3, 183))


@sound("Alarm")
def alarm():
    # Electric fire bell: a hammer at 18 strikes per second.
    length = 3.0
    out = silence(length + 1.0)
    for i in range(int(length * 18)):
        out = mix(out, np.concatenate([silence(i / 18), bell(1150, 0.5, 184, decay=7, strike=0.4) * 0.3]))
    out = out * np.concatenate([np.ones(n(length)), np.linspace(1, 0.3, len(out) - n(length))])
    return fade(reverb(saturate(out, 1.5), 1.8, 0.3, 185))


@sound("PhoneRing")
def phone_ring():
    # Two-bell 1960s ringer, one double ring.
    out = silence(2.6)
    for burst in (0.0, 0.55):
        for i in range(int(0.4 * 20)):
            t0 = burst + i / 20
            b = mix(bell(1040, 0.35, 186, decay=8, strike=0.3), bell(1300, 0.35, 187, decay=8, strike=0.3)) * 0.25
            out = mix(out, np.concatenate([silence(t0), b]))
    return fade(reverb(out, 1.2, 0.25, 188))


@sound("TransmitterArmed")
def transmitter_armed():
    length = 3.2
    t = time(length)
    f = 70 * (6 ** (t / length))
    s = saw(f, length, 20) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t))
    s = sweep_lowpass(s, 300, 5000)
    zap = crackle(length, 189, 30) * np.clip(t / length, 0, 1)
    return fade(reverb(mix(s * env_adsr(length, 0.3, 0.2, 0.9, 0.4) * 0.6, zap * 0.4), 2.0, 0.3, 190))


@sound("OnAir")
def on_air():
    # The broadcast going out: 1 kHz line-up tone over the carrier.
    tone = sine(1000, 2.4) * env_adsr(2.4, 0.01, 0.1, 0.9, 0.2) * 0.4
    carrier = bandpass(white(2.4, 191), 200, 5000) * 0.12
    thump = thud(50, 0.6, 192, 0.5)
    return fade(mix(thump, tone + carrier))


@sound("EndOfTransmission")
def end_of_transmission():
    tone = sine(1000, 3.0) * 0.45
    return fade(tone, 0.005, 0.002)


@sound("VanDoorSlam")
def van_door_slam():
    s = mix(thud(70, 0.6, 193, 1.0), resonators(white(0.05, 194) * env_ad(0.05, 0.0005, 0.01), [(900, 15, 10), (1700, 20, 6)]) * 0.5)
    return fade(reverb(s, 0.9, 0.2, 195))


# --- The deck --------------------------------------------------------------

@sound("DeckOpen")
def deck_open():
    return menu_open() * 1.0


@sound("DeckClose")
def deck_close():
    return menu_close()


@sound("TapeInsert")
def tape_insert():
    # Cassette pushed in, the carriage drops, the heads thread.
    push = resonators(white(0.06, 196) * env_ad(0.06, 0.001, 0.01), [(1700, 8, 6)])
    drop = mix(thud(130, 0.25, 197, 0.6), click(198, 800, 0.04))
    thread = motor(0.9, 60, 90, 199) * env_adsr(0.9, 0.1, 0.1, 0.7, 0.3) * 0.5
    clunk = mix(click(200, 1100, 0.04), thud(160, 0.15, 201, 0.4) * 0.5)
    return fade(mix(push, np.concatenate([silence(0.2), drop]), np.concatenate([silence(0.45), thread]), np.concatenate([silence(1.35), clunk])))


@sound("TapeEject")
def tape_eject():
    unthread = motor(0.6, 90, 60, 202) * env_adsr(0.6, 0.05, 0.1, 0.7, 0.2) * 0.45
    pop = mix(thud(140, 0.25, 203, 0.6), click(204, 900, 0.04))
    return fade(mix(unthread, np.concatenate([silence(0.55), pop])))


@sound("DeckPlay")
def deck_play():
    return fade(mix(click(205, 1300, 0.03), thud(170, 0.12, 206, 0.3) * 0.4, np.concatenate([silence(0.05), motor(0.3, 70, 80, 207) * env_ad(0.3, 0.02, 0.1) * 0.3])))


@sound("DeckPause")
def deck_pause():
    return fade(mix(click(208, 1100, 0.03), thud(150, 0.12, 209, 0.3) * 0.4))


@sound("FrameStep")
def frame_step():
    return fade(click(210, 2200, 0.02) * 0.6)


@sound("ChannelSwitch")
def channel_switch():
    # Rotary channel selector detent and a flash of snow.
    det = mix(click(211, 1600, 0.03), click(212, 2500, 0.02) * 0.5)
    snow = static_burst(0.22, 213) * env_ad(0.22, 0.005, 0.07) * 0.6
    return fade(mix(det, np.concatenate([silence(0.03), snow])))


@sound("MarkFrame")
def mark_frame():
    # Leaf shutter: two clicks and a spring.
    s = mix(click(214, 2600, 0.02), np.concatenate([silence(0.045), click(215, 3100, 0.02) * 0.8]))
    spring = sine(1800, 0.12) * env_ad(0.12, 0.001, 0.03) * 0.1
    return fade(mix(s, spring))


@sound("EditCommit")
def edit_commit():
    # Heavy transport clunk, a reversed swell, and the picture warping as the
    # future is overwritten.
    swell = (bandpass(white(1.2, 216), 400, 6000) * env_ad(1.2, 1.1, 0.05))
    clunk = mix(thud(60, 0.8, 217, 1.0), click(218, 700, 0.06))
    t = time(1.6)
    warp = np.sin(2 * np.pi * np.cumsum(220 * np.exp(-t * 1.2) + 30) / SR) * env_ad(1.6, 0.01, 0.6) * 0.35
    out = mix(swell * 0.5, np.concatenate([silence(1.15), clunk, ]), np.concatenate([silence(1.2), wow_flutter(warp, 0.01, 3, seed=219)]))
    return fade(reverb(out, 1.8, 0.3, 220))


@sound("EditRejected")
def edit_rejected():
    return ui_error()


@sound("Rewind")
def rewind():
    length = 2.0
    t = time(length)
    f = 500 + 1400 * (1 - np.exp(-t * 2))
    whine = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.3 + np.sin(4 * np.pi * np.cumsum(f) / SR) * 0.1
    hiss = bandpass(white(length, 221), 2000, 9000) * 0.15
    stop = np.concatenate([silence(length - 0.08), click(222, 1000, 0.08)])
    return fade(mix(wow_flutter((whine + hiss) * env_adsr(length, 0.05, 0.1, 0.9, 0.1), 0.004, 5, seed=223), stop))


# --- Static and signal -------------------------------------------------------

@sound("StaticShort")
def static_short():
    return fade(static_burst(0.35, 224) * env_adsr(0.35, 0.002, 0.05, 0.7, 0.1))


@sound("StaticLong")
def static_long():
    s = static_burst(2.6, 225, crackles=120) * env_adsr(2.6, 0.002, 0.2, 0.8, 0.8)
    return fade(saturate(s, 1.5))


@sound("SignalLost")
def signal_lost():
    # The feed cutting out: static, then a dead carrier tone dropping away.
    snow = static_burst(1.6, 226) * env_adsr(1.6, 0.002, 0.1, 0.8, 0.5)
    t = time(2.2)
    tone = np.sin(2 * np.pi * (1000 - 300 * t / 2.2) * t) * env_adsr(2.2, 0.01, 0.1, 0.6, 1.0) * 0.25
    return fade(mix(snow, np.concatenate([silence(0.9), tone])))


@sound("RadioIn")
def radio_in():
    sq = highpass(white(0.18, 227), 1500) * env_ad(0.18, 0.001, 0.05) * 0.8
    return fade(mix(click(228, 1900, 0.02), sq))


@sound("RadioOut")
def radio_out():
    sq = highpass(white(0.12, 229), 1800) * env_ad(0.12, 0.001, 0.03) * 0.6
    return fade(mix(sq, np.concatenate([silence(0.1), click(230, 1500, 0.02) * 0.7])))


@sound("Reentry")
def reentry():
    # Tuning back in: a sweep through the noise that resolves.
    length = 2.2
    t = time(length)
    noise = static_burst(length, 231) * np.linspace(1, 0.05, n(length)) * 0.6
    f = 200 + 1600 * (t / length) ** 2
    sweep = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.linspace(0.1, 0.35, n(length))
    chord = (sine(523, 1.2) + sine(659, 1.2) * 0.7 + sine(784, 1.2) * 0.5) * env_ad(1.2, 0.1, 0.4) * 0.25
    return fade(reverb(mix(noise, sweep, np.concatenate([silence(1.6), chord])), 1.5, 0.3, 232))


# --- The Presenter -----------------------------------------------------------

@sound("PresenterStep")
def presenter_step():
    # Heavy, slightly too slow, with a tape-dragged tail.
    t = time(0.9)
    body = np.sin(2 * np.pi * (38 + 30 * np.exp(-t * 20)) * t) * np.exp(-t * 7)
    hit = lowpass(white(0.9, 233), 1200) * np.exp(-t * 30) * 0.6
    s = wow_flutter(mix(body, hit), 0.01, 2.5, seed=234)
    return fade(reverb(s, 1.4, 0.35, 235, brightness=2500))


@sound("PresenterAppear")
def presenter_appear():
    rev = static_burst(1.0, 236)[::-1] * np.linspace(0, 1, n(1.0)) ** 2
    boom = thud(40, 1.2, 237, 0.5)
    return fade(reverb(mix(rev * 0.7, np.concatenate([silence(0.95), boom])), 2.0, 0.35, 238))


@sound("PresenterVanish")
def presenter_vanish():
    burst = static_burst(0.8, 239) * env_ad(0.8, 0.002, 0.2)
    return fade(tape_stop(burst, 0.6) * 0.8)


@sound("HuntStart", "sting")
def hunt_start():
    # A dissonant chord grinding to a halt, a slam, and a scream of static.
    length = 2.4
    chord = mix(*(saw(f, length, 16) * 0.3 for f in (98, 104, 147, 156, 233)))
    chord = lowpass(chord, 2500) * env_adsr(length, 0.005, 0.2, 0.8, 0.3)
    chord = tape_stop(chord, 1.4)
    slam = thud(42, 1.2, 240, 1.0) * 1.2
    snow = static_burst(0.7, 241) * env_ad(0.7, 0.001, 0.15) * 0.7
    return fade(reverb(saturate(mix(chord, slam, snow), 2), 2.2, 0.35, 242))


@sound("HuntEnd", "sting")
def hunt_end():
    # The signal clears: noise filtering up and away.
    length = 2.4
    s = sweep_lowpass(pink(length, 243), 300, 9000) * env_adsr(length, 0.2, 0.3, 0.6, 1.2) * 0.5
    tone = sine(392, 1.6) * env_ad(1.6, 0.4, 0.5) * 0.15
    return fade(reverb(mix(s, np.concatenate([silence(0.8), tone])), 1.8, 0.3, 244))


@sound("Eliminated", "sting")
def eliminated():
    return mix(static_long(), signal_lost() * 0.6)


@sound("EditorShadow", "sting")
def editor_shadow():
    # A soft, wrong chord swelling behind you.
    length = 2.5
    pad = mix(*(sine(f, length) for f in (233.1, 246.9, 349.2))) * env_adsr(length, 1.2, 0.2, 0.6, 0.9) * 0.3
    breath = bandpass(pink(length, 245), 500, 2500) * env_adsr(length, 1.5, 0.1, 0.5, 0.8) * 0.2
    return fade(reverb(wow_flutter(mix(pad, breath), 0.006, 0.8, seed=246), 2.5, 0.4, 247))


# --- The Loop ----------------------------------------------------------------

@sound("LoopStart", "sting")
def loop_start():
    # The building rewinds: a long rewind whine and a hard reset.
    return mix(rewind(), np.concatenate([silence(1.9), static_short()]))


@sound("LoopReset")
def loop_reset():
    return mix(rewind()[: n(1.0)] * np.linspace(1, 0, n(1.0)), static_short())


@sound("LoopBreak", "sting")
def loop_break():
    # Tape snapping.
    crack = highpass(white(0.05, 248), 1500) * env_ad(0.05, 0.0002, 0.006) * 1.5
    t = time(1.6)
    fall = np.sin(2 * np.pi * np.cumsum(300 * np.exp(-t * 2.5) + 20) / SR) * env_ad(1.6, 0.005, 0.5) * 0.4
    flap = silence(0.8)
    for i in range(10):
        flap = mix(flap, np.concatenate([silence(0.03 * i + 0.1), click(249 + i, 900, 0.02) * (1 - i / 10) * 0.5]))
    return fade(reverb(mix(crack, fall, flap), 1.5, 0.3, 260))


# --- Stingers ------------------------------------------------------------------

@sound("StingDiscovery", "sting")
def sting_discovery():
    # Finding a tape: a music-box figure with a sour last note.
    out = silence(2.4)
    for i, f in enumerate([659.3, 784, 880, 830.6]):
        out = mix(out, np.concatenate([silence(0.22 * i), bell(f, 1.6, 261 + i, ratios=(1, 4.0, 9.2), decay=2.5)]))
    return fade(reverb(wow_flutter(out, 0.004, 1.1, seed=265), 2.0, 0.35, 266))


@sound("StingScare", "sting")
def sting_scare():
    hit = mix(thud(45, 1.4, 267, 1.0), static_burst(0.4, 268) * env_ad(0.4, 0.001, 0.08))
    cluster = mix(*(saw(f, 1.6, 12) for f in (311, 330, 349, 370))) * env_ad(1.6, 0.002, 0.5) * 0.25
    return fade(reverb(saturate(mix(hit, lowpass(cluster, 3500)), 1.8), 2.0, 0.35, 269))


@sound("StingSuccess", "sting")
def sting_success():
    out = silence(4.0)
    for i, (f, d) in enumerate([(523.3, 0), (659.3, 0.25), (784, 0.5), (1046.5, 0.8)]):
        tone = additive(f, 3.0, [(1, 1), (2, 0.4), (3, 0.2), (4, 0.1)]) * env_adsr(3.0, 0.01, 0.4, 0.4, 2.0) * 0.2
        out = mix(out, np.concatenate([silence(d), tone]))
    return fade(reverb(wow_flutter(out, 0.004, 0.7, seed=270), 2.5, 0.35, 271))


@sound("StingFail", "sting")
def sting_fail():
    length = 4.0
    chord = mix(*(additive(f, length, [(1, 1), (2, 0.4), (3, 0.2)]) for f in (110, 130.8, 155.6, 185))) * env_adsr(length, 0.05, 0.5, 0.6, 2.5) * 0.25
    return fade(reverb(tape_stop(wow_flutter(chord, 0.008, 0.9, seed=272), 2.5), 2.5, 0.35, 273))


# --- Sounds named by the case's own subtitles ---------------------------------

def stick_slip(length, seed, rate_lo, rate_hi, modes, threshold=0.96):
    """Friction: a stuttering series of tiny impulses through resonant modes."""
    r = rng(seed)
    t = time(length)
    rate = rate_lo + (rate_hi - rate_lo) * np.sin(np.pi * t / length) + r.normal(0, 2, len(t)).cumsum() / 300
    impulses = (np.sin(2 * np.pi * np.cumsum(np.maximum(rate, 1)) / SR) > threshold).astype(float)
    return resonators(impulses + white(length, seed + 1) * 0.01, modes)


@sound("ChairScrape")
def chair_scrape():
    s = stick_slip(0.9, 280, 60, 140, [(380, 6, 10), (900, 8, 8), (2100, 10, 4)], 0.9)
    s = bandpass(s, 200, 6000) * env_adsr(0.9, 0.05, 0.1, 0.8, 0.2)
    return fade(reverb(s * 0.5, 1.4, 0.35, 281))


@sound("ShelfCreak")
def shelf_creak():
    s = stick_slip(1.6, 282, 8, 26, [(240, 14, 20), (610, 16, 12), (1300, 18, 6)])
    s = bandpass(s, 120, 4000) * env_adsr(1.6, 0.3, 0.2, 0.8, 0.5)
    return fade(reverb(s * 0.4, 1.8, 0.4, 283, brightness=3000))


@sound("MetalCreak")
def metal_creak():
    s = stick_slip(2.2, 284, 5, 14, [(150, 40, 25), (410, 50, 18), (1270, 60, 10), (2980, 60, 5)])
    s = bandpass(s, 80, 6000) * env_adsr(2.2, 0.4, 0.3, 0.8, 0.8)
    return fade(reverb(s * 0.4, 2.6, 0.45, 285, brightness=3500))


@sound("TapeFlutter")
def tape_flutter():
    length = 2.2
    tone = (sine(311, length) + sine(466, length) * 0.5 + sine(622, length) * 0.2) * env_adsr(length, 0.4, 0.2, 0.7, 0.8)
    hiss = bandpass(white(length, 286), 1500, 7000) * env_adsr(length, 0.3, 0.2, 0.6, 0.8) * 0.1
    return fade(reverb(wow_flutter(tone * 0.3 + hiss, 0.02, 4, 0.004, 11, seed=287), 1.8, 0.35, 288))

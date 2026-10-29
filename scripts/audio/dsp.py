"""
Small numpy DSP toolkit for the game's original sound design.

Everything here is deterministic: random sources take an explicit seed so the
generated banks are identical on every run. Signals are mono float64 arrays at
SR samples per second, nominally in [-1, 1].
"""

import numpy as np

SR = 44100


def rng(seed):
    return np.random.default_rng(seed)


def n(seconds):
    return int(round(seconds * SR))


def time(seconds):
    return np.arange(n(seconds)) / SR


def silence(seconds):
    return np.zeros(n(seconds))


# ---------------------------------------------------------------------------
# Oscillators
# ---------------------------------------------------------------------------


def phase_of(freq, length):
    """Phase (radians) for a constant or per-sample frequency."""
    if np.isscalar(freq):
        return 2 * np.pi * freq * np.arange(length) / SR
    return 2 * np.pi * np.cumsum(freq) / SR


def sine(freq, seconds, phase0=0.0):
    length = n(seconds)
    return np.sin(phase_of(freq, length) + phase0)


def additive(freq, seconds, partials):
    """partials: list of (ratio, amplitude). Band-limited by construction."""
    length = n(seconds)
    ph = phase_of(freq, length)
    out = np.zeros(length)
    for ratio, amp in partials:
        out += amp * np.sin(ph * ratio)
    return out


def saw(freq, seconds, harmonics=24):
    f = freq if np.isscalar(freq) else float(np.max(freq))
    count = max(1, min(harmonics, int(SR / 2 / max(f, 1))))
    return additive(freq, seconds, [(k, 1.0 / k) for k in range(1, count + 1)]) * 0.55


def square(freq, seconds, harmonics=24):
    f = freq if np.isscalar(freq) else float(np.max(freq))
    count = max(1, min(harmonics, int(SR / 2 / max(f, 1))))
    return additive(freq, seconds, [(k, 1.0 / k) for k in range(1, count + 1, 2)]) * 0.75


def triangle(freq, seconds):
    return additive(freq, seconds, [(k, ((-1) ** ((k - 1) // 2)) / (k * k)) for k in range(1, 16, 2)]) * 0.8


def white(seconds, seed):
    return rng(seed).uniform(-1, 1, n(seconds))


def coloured(seconds, seed, slope):
    """Noise with a 1/f^slope power spectrum (slope 1 = pink, 2 = brown)."""
    length = n(seconds)
    spec = np.fft.rfft(rng(seed).normal(0, 1, length))
    freqs = np.fft.rfftfreq(length, 1 / SR)
    freqs[0] = freqs[1] if len(freqs) > 1 else 1
    spec /= freqs ** (slope / 2)
    out = np.fft.irfft(spec, length)
    return out / (np.max(np.abs(out)) + 1e-9)


def pink(seconds, seed):
    return coloured(seconds, seed, 1)


def brown(seconds, seed):
    return coloured(seconds, seed, 2)


def crackle(seconds, seed, density=40):
    """Sparse clicks, like dust on a record or arcing contacts."""
    r = rng(seed)
    out = np.zeros(n(seconds))
    count = int(density * seconds)
    for pos in r.integers(0, len(out), count):
        width = r.integers(2, 30)
        end = min(len(out), pos + width)
        out[pos:end] += r.uniform(-1, 1) * np.exp(-np.arange(end - pos) / max(width / 4, 1))
    return out


# ---------------------------------------------------------------------------
# Envelopes
# ---------------------------------------------------------------------------


def env_ad(seconds, attack, decay_tau):
    t = time(seconds)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / max(decay_tau, 1e-4))
    return a * d


def env_adsr(seconds, attack, decay, sustain, release):
    length = n(seconds)
    t = np.arange(length) / SR
    env = np.ones(length) * sustain
    a = t < attack
    env[a] = t[a] / max(attack, 1e-4)
    d = (t >= attack) & (t < attack + decay)
    env[d] = 1 - (1 - sustain) * (t[d] - attack) / max(decay, 1e-4)
    r_start = seconds - release
    r = t >= r_start
    env[r] *= np.clip(1 - (t[r] - r_start) / max(release, 1e-4), 0, 1)
    return env


def fade(sig, fade_in=0.005, fade_out=0.01):
    sig = sig.copy()
    a, b = n(fade_in), n(fade_out)
    if a > 0:
        sig[:a] *= np.linspace(0, 1, a)
    if b > 0:
        sig[-b:] *= np.linspace(1, 0, b)
    return sig


def ramp(seconds, start, end, curve=1.0):
    x = np.linspace(0, 1, n(seconds))
    return start + (end - start) * x ** curve


# ---------------------------------------------------------------------------
# Filters (zero-phase, frequency domain; fine for offline rendering)
# ---------------------------------------------------------------------------


_MODE = {"circular": False}


class circular:
    """Inside this context, frequency-domain filters wrap around (for loops).
    Outside it, signals are zero-padded so a one-shot's ringing can't wrap."""

    def __enter__(self):
        self.previous = _MODE["circular"]
        _MODE["circular"] = True

    def __exit__(self, *exc):
        _MODE["circular"] = self.previous


def _apply(sig, response):
    pad = 0 if _MODE["circular"] else min(n(0.3), max(len(sig), 1))
    padded = np.concatenate([np.zeros(pad), sig, np.zeros(pad)]) if pad else sig
    length = len(padded)
    spec = np.fft.rfft(padded)
    freqs = np.fft.rfftfreq(length, 1 / SR)
    out = np.fft.irfft(spec * response(freqs), length)
    return out[pad:pad + len(sig)] if pad else out


def lowpass(sig, cutoff, order=2):
    return _apply(sig, lambda f: 1 / np.sqrt(1 + (f / cutoff) ** (2 * order)))


def highpass(sig, cutoff, order=2):
    return _apply(sig, lambda f: 1 / np.sqrt(1 + (cutoff / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(sig, low, high, order=2):
    return highpass(lowpass(sig, high, order), low, order)


def peak(sig, freq, q, gain):
    """Resonant boost (gain > 1) or cut around freq."""
    def response(f):
        bw = freq / q
        return 1 + (gain - 1) / (1 + ((f - freq) / (bw / 2)) ** 2)
    return _apply(sig, response)


def resonators(sig, modes):
    """Body resonance: modes = [(freq, q, gain)]."""
    out = np.zeros_like(sig)
    for freq, q, gain in modes:
        out += peak(sig, freq, q, gain) - sig
    return sig + out


def sweep_lowpass(sig, start, end, blocks=64):
    """Time-varying low-pass by overlapping blocks (cutoff moves start->end)."""
    length = len(sig)
    out = np.zeros(length)
    size = max(256, length // blocks)
    hop = size // 2
    window = np.hanning(size)
    pos = 0
    while pos < length:
        chunk = np.zeros(size)
        part = sig[pos:pos + size]
        chunk[:len(part)] = part
        centre = min(1.0, (pos + size / 2) / length)
        cutoff = start * (end / start) ** centre
        filt = lowpass(chunk * window, cutoff)
        end_i = min(length, pos + size)
        out[pos:end_i] += filt[:end_i - pos]
        pos += hop
    return out


# ---------------------------------------------------------------------------
# Effects
# ---------------------------------------------------------------------------


def convolve(sig, ir, circular=False):
    if circular:
        length = len(sig)
        ir_fold = np.zeros(length)
        for start in range(0, len(ir), length):
            seg = ir[start:start + length]
            ir_fold[:len(seg)] += seg
        return np.fft.irfft(np.fft.rfft(sig) * np.fft.rfft(ir_fold), length)
    total = len(sig) + len(ir) - 1
    size = 1 << (total - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(sig, size) * np.fft.rfft(ir, size), size)[:total]


def room_ir(seconds, seed, brightness=4000, predelay=0.01):
    """Exponentially decaying filtered noise: a plausible room."""
    t = time(seconds)
    ir = rng(seed).normal(0, 1, len(t)) * np.exp(-t * 6.9 / seconds)
    ir = lowpass(ir, brightness)
    ir = np.concatenate([np.zeros(n(predelay)), ir])
    ir[0] = 1.0
    return ir / np.sqrt(np.sum(ir ** 2))


def reverb(sig, seconds=1.2, mix=0.3, seed=1, brightness=4000, circular=False):
    ir = room_ir(seconds, seed, brightness)
    wet = convolve(sig, ir, circular)
    if not circular:
        sig = np.concatenate([sig, np.zeros(len(wet) - len(sig))])
    wet *= np.max(np.abs(sig)) / (np.max(np.abs(wet)) + 1e-9)
    return sig * (1 - mix) + wet * mix


def wow_flutter(sig, depth=0.0025, rate=0.6, flutter=0.0004, flutter_rate=7.0, seed=3, circular=False):
    """Old tape: pitch wobble by modulating read position."""
    length = len(sig)
    t = np.arange(length) / SR
    r = rng(seed)
    p1, p2 = r.uniform(0, 2 * np.pi, 2)
    if circular:
        # Whole number of cycles over the loop so the wobble is seamless.
        dur = length / SR
        rate = max(1, round(rate * dur)) / dur
        flutter_rate = max(1, round(flutter_rate * dur)) / dur
    offset = depth * SR / (2 * np.pi * rate) * np.sin(2 * np.pi * rate * t + p1)
    offset += flutter * SR / (2 * np.pi * flutter_rate) * np.sin(2 * np.pi * flutter_rate * t + p2)
    idx = np.arange(length) + offset
    if circular:
        return np.interp(idx % length, np.arange(length + 1), np.concatenate([sig, sig[:1]]))
    return np.interp(np.clip(idx, 0, length - 1), np.arange(length), sig)


def tape_stop(sig, seconds):
    """Playback slowing to a halt over the last `seconds`."""
    length = len(sig)
    stop = min(length, n(seconds))
    speed = np.ones(length)
    speed[-stop:] = np.linspace(1, 0, stop) ** 1.5
    idx = np.cumsum(speed)
    idx -= idx[0]
    return np.interp(np.clip(idx, 0, length - 1), np.arange(length), sig)


def saturate(sig, drive=2.0):
    return np.tanh(sig * drive) / np.tanh(drive)


def bitcrush(sig, bits=8, down=2):
    step = 2 ** (bits - 1)
    held = np.repeat(sig[::down], down)[:len(sig)]
    return np.round(held * step) / step


def pitch(sig, ratio):
    """Resample (changes length): ratio > 1 is higher and shorter."""
    length = int(len(sig) / ratio)
    return np.interp(np.arange(length) * ratio, np.arange(len(sig)), sig)


def mix(*parts):
    length = max(len(p) for p in parts)
    out = np.zeros(length)
    for p in parts:
        out[:len(p)] += p
    return out


def place(buf, sig, start, circular=False):
    """Add sig into buf at sample index start (wrapping for loops)."""
    if circular:
        idx = (np.arange(len(sig)) + start) % len(buf)
        np.add.at(buf, idx, sig)
        return buf
    end = min(len(buf), start + len(sig))
    if end > start:
        buf[start:end] += sig[:end - start]
    return buf


def seamless(sig, period_seconds, crossfade_seconds=1.0):
    """Turn a render of (period + crossfade) into an exactly periodic buffer."""
    p = n(period_seconds)
    x = n(crossfade_seconds)
    out = sig[:p].copy()
    tail = sig[p:p + x]
    w = np.linspace(0, 1, len(tail))
    out[:len(tail)] = out[:len(tail)] * w + tail * (1 - w)
    return out


def normalise(sig, peak_db=-1.0):
    m = np.max(np.abs(sig)) + 1e-12
    return sig / m * 10 ** (peak_db / 20)


def rms_normalise(sig, rms_db, peak_db=-0.5):
    rms = np.sqrt(np.mean(sig ** 2)) + 1e-12
    out = sig * (10 ** (rms_db / 20) / rms)
    m = np.max(np.abs(out))
    limit = 10 ** (peak_db / 20)
    if m > limit:
        out = saturate(out / m * 1.2, 1.2) * limit
    return out


def midi(note):
    return 440.0 * 2 ** ((note - 69) / 12)

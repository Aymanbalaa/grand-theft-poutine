"""Procedural ambience for the Rue Saint-Paul slice (license-free, deterministic).
Run: .venv/Scripts/python -m pipeline.slice_audio  ->  game/assets/slice/audio/*.wav

rain.wav       steady rain hiss + random drips/patter, seamless 12 s loop (stereo)
drips.wav      gutter drips onto metal/puddles, sparse, 9 s loop (stereo)
step_wet.wav   wet cobble footstep: thud + short splash
sfx_*.wav      game cues (order, pickup, cash, fleur, fail, end, whistle, bump, honk, graze, tick)
music_night.wav  late-night jazz loop (Rhodes, upright bass, brushes), 8 bars, mono
"""
from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "slice" / "audio"


def _write(path: Path, x: np.ndarray) -> None:
    x = np.clip(x, -1.0, 1.0)
    ch = 1 if x.ndim == 1 else x.shape[1]
    pcm = (x * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def _one_pole(x: np.ndarray, a: float) -> np.ndarray:
    """y[n] = a*y[n-1] + (1-a)*x[n] (low-pass), vectorised via cumulative filter."""
    from scipy.signal import lfilter  # type: ignore
    return lfilter([1.0 - a], [1.0, -a], x)


def _lp(x: np.ndarray, a: float) -> np.ndarray:
    try:
        return _one_pole(x, a)
    except ImportError:
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc = a * acc + (1.0 - a) * v
            y[i] = acc
        return y


def _loop(x: np.ndarray, fade: int) -> np.ndarray:
    """Crossfade the tail into the head so the clip loops seamlessly."""
    head = x[:fade].copy()
    tail = x[-fade:].copy()
    r = np.linspace(0.0, 1.0, fade)
    shape = (fade,) + (1,) * (x.ndim - 1)
    x = x[:-fade].copy()
    x[:fade] = head * r.reshape(shape) + tail * (1.0 - r).reshape(shape)
    return x


def _drop(rng: np.random.Generator, n: int, f0: float) -> np.ndarray:
    t = np.arange(n) / SR
    f = f0 * (1.0 + 0.6 * np.exp(-t / 0.004))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / rng.uniform(0.006, 0.02))


def rain(seconds: float = 12.0) -> np.ndarray:
    rng = np.random.default_rng(1642)
    n = int(SR * (seconds + 1.0))
    out = np.zeros((n, 2))
    for c in range(2):
        w = rng.standard_normal(n)
        hiss = w - _lp(w, 0.55)              # high-passed noise: the "shhh"
        body = _lp(rng.standard_normal(n), 0.985) * 3.0
        swell = 1.0 + 0.15 * np.sin(2 * np.pi * np.arange(n) / SR / 5.3 + c)
        out[:, c] = (0.22 * hiss + 0.12 * body) * swell
        # dense patter of tiny impacts
        for _ in range(int(seconds * 260)):
            i = rng.integers(0, n - 800)
            out[i:i + 800, c] += 0.05 * rng.uniform(0.2, 1.0) * _drop(rng, 800, rng.uniform(1800, 5200))
    out = _loop(out, SR)
    return 0.8 * out / np.abs(out).max()


def drips(seconds: float = 9.0) -> np.ndarray:
    rng = np.random.default_rng(1535)
    n = int(SR * (seconds + 0.5))
    out = np.zeros((n, 2))
    for _ in range(int(seconds * 3.2)):
        i = rng.integers(0, n - 4000)
        pan = rng.uniform(0.15, 0.85)
        d = _drop(rng, 4000, rng.uniform(600, 1500)) * rng.uniform(0.4, 1.0)
        out[i:i + 4000, 0] += d * (1 - pan)
        out[i:i + 4000, 1] += d * pan
    out = _loop(out, SR // 2)
    return 0.7 * out / np.abs(out).max()


def step_wet(seconds: float = 0.28) -> np.ndarray:
    rng = np.random.default_rng(7)
    n = int(SR * seconds)
    t = np.arange(n) / SR
    thud = _lp(rng.standard_normal(n), 0.93) * np.exp(-t / 0.025)
    w = rng.standard_normal(n)
    splash = (w - _lp(w, 0.7)) * np.exp(-np.maximum(t - 0.012, 0) / 0.05) * (t > 0.012)
    x = 1.0 * thud / np.abs(thud).max() + 0.35 * splash / np.abs(splash).max()
    return 0.9 * x / np.abs(x).max()


# ---------------------------------------------------------------- game cues

def _tone(freq: float, dur: float, decay: float, harm=((1, 1.0), (2, 0.3), (3, 0.12))) -> np.ndarray:
    t = np.arange(int(SR * dur)) / SR
    x = sum(a * np.sin(2 * np.pi * freq * k * t) for k, a in harm)
    env = np.minimum(1.0, t / 0.004) * np.exp(-t / decay)
    return x * env


def _seq(notes, gap: float, dur: float, decay: float) -> np.ndarray:
    n = int(SR * (gap * (len(notes) - 1) + dur))
    out = np.zeros(n)
    for i, f in enumerate(notes):
        s = int(SR * gap * i)
        tone = _tone(f, dur, decay)
        out[s:s + len(tone)] += tone
    return 0.8 * out / np.abs(out).max()


def game_cues() -> dict:
    """Short UI cues: order ping, pickup arpeggio, cash chime, fleur sparkle,
    fail, end-of-shift, police whistle (pickpocket), bag bump."""
    rng = np.random.default_rng(9)
    wt = np.arange(int(SR * 0.9)) / SR
    trill = 1.0 + 0.04 * np.sign(np.sin(2 * np.pi * 22 * wt))
    whistle = np.sin(2 * np.pi * np.cumsum(2900 * trill) / SR) * np.minimum(1, wt / 0.02) * np.exp(-wt / 0.6)
    whistle += 0.15 * rng.standard_normal(len(wt)) * np.exp(-wt / 0.6)
    n = int(SR * 0.25)
    t = np.arange(n) / SR
    bump = _lp(rng.standard_normal(n), 0.97) * np.exp(-t / 0.05)
    # car horn: two detuned buzzy tones a major third apart, short double tap
    ht = np.arange(int(SR * 0.62)) / SR
    def buzz(f):
        ph = 2 * np.pi * f * ht
        return np.tanh(2.5 * (np.sin(ph) + 0.5 * np.sin(2 * ph + 0.3) + 0.25 * np.sin(3 * ph)))
    horn = 0.5 * buzz(392.0) + 0.5 * buzz(494.0)
    gate = ((ht < 0.17) | ((ht > 0.24) & (ht < 0.58))).astype(float)
    gate = _lp(gate, 0.995)
    horn = _lp(horn, 0.55) * gate
    # graze: a quick filtered-noise whoosh rising in pitch
    gn = int(SR * 0.32)
    gt = np.arange(gn) / SR
    w = rng.standard_normal(gn)
    lo = _lp(w, 0.96)
    hi = w - _lp(w, 0.5)
    k = gt / gt[-1]
    whoosh = ((1 - k) * lo * 3.0 + k * hi * 0.6) * np.sin(np.pi * np.minimum(1.0, gt / 0.3)) ** 2
    return {
        "order": _seq([659.3, 880.0], 0.11, 0.35, 0.18),
        "pickup": _seq([523.3, 659.3, 784.0], 0.07, 0.3, 0.12),
        "cash": _seq([1046.5, 1318.5, 1568.0, 2093.0], 0.055, 0.35, 0.1),
        "fleur": _seq([784.0, 987.8, 1174.7, 1568.0, 1975.5], 0.08, 0.6, 0.25),
        "fail": _seq([392.0, 311.1], 0.16, 0.45, 0.22),
        "end": _seq([523.3, 659.3, 784.0, 1046.5], 0.14, 0.9, 0.4),
        "whistle": 0.8 * whistle / np.abs(whistle).max(),
        "bump": 0.9 * bump / np.abs(bump).max(),
        "honk": 0.8 * horn / np.abs(horn).max(),
        "graze": 0.7 * whoosh / np.abs(whoosh).max(),
        "tick": _seq([1760.0], 0.1, 0.09, 0.025),
    }


# ---------------------------------------------------------------- music

def _midi(n: float) -> float:
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


def _rhodes(freq: float, dur: float) -> np.ndarray:
    """Electric-piano-ish note: soft sine body, a little 2nd harmonic, a short
    bell-like tine partial, gentle tremolo."""
    t = np.arange(int(SR * dur)) / SR
    body = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * 2 * freq * t) * np.exp(-t / 0.5)
    tine = 0.18 * np.sin(2 * np.pi * 7.0 * freq * t) * np.exp(-t / 0.06)
    env = np.minimum(1.0, t / 0.008) * np.exp(-t / 1.7)
    trem = 1.0 + 0.12 * np.sin(2 * np.pi * 4.6 * t)
    return (body + tine) * env * trem


def _bass(freq: float, dur: float) -> np.ndarray:
    t = np.arange(int(SR * dur)) / SR
    x = np.sin(2 * np.pi * freq * t) + 0.3 * np.sin(2 * np.pi * 2 * freq * t) + 0.08 * np.sin(2 * np.pi * 3 * freq * t)
    return x * np.minimum(1.0, t / 0.012) * np.exp(-t / 0.55)


def music(bpm: float = 74.0) -> np.ndarray:
    """Slow late-night jazz loop for the courier shift: Rhodes comping over a
    walking upright bass, brushes and a soft kick. 8 bars, seamless (mono)."""
    rng = np.random.default_rng(1642)
    beat = 60.0 / bpm
    bars = 8
    n = int(SR * beat * 4 * bars)
    out = np.zeros(n + SR * 3)
    # D minor ii-V-I-VI turnaround, MIDI voicings (root for the bass first)
    prog = [
        (38, [65, 69, 72, 76]),   # Dm9
        (43, [65, 69, 71, 76]),   # G13
        (36, [64, 67, 71, 74]),   # Cmaj9
        (45, [64, 67, 70, 73]),   # A7(b9-ish)
        (38, [65, 69, 72, 77]),   # Dm9
        (46, [62, 65, 69, 74]),   # Bbmaj7
        (43, [65, 70, 74, 77]),   # Gm9
        (45, [64, 67, 69, 73]),   # A7sus -> A7
    ]

    def add(sig: np.ndarray, at: float, gain: float) -> None:
        s = int(SR * at)
        out[s:s + len(sig)] += gain * sig[: max(0, len(out) - s)]

    for b, (root, chord) in enumerate(prog):
        t0 = b * 4 * beat
        # comping: beat 1 and the "and" of 2, with a lazy strum
        for hit, g in ((0.0, 0.22), (1.5, 0.15)):
            for k, m in enumerate(chord):
                add(_rhodes(_midi(m), beat * 2.8), t0 + hit * beat + k * 0.012 + rng.uniform(0, 0.01), g)
        # walking bass: root, 5th/3rd, approach note into the next bar
        nxt = prog[(b + 1) % bars][0]
        walk = [root, root + 7, root + 12 if b % 2 == 0 else root + 3, nxt + (1 if nxt < root else -1)]
        for k, m in enumerate(walk):
            add(_bass(_midi(m), beat * 1.1), t0 + k * beat, 0.28)
        # soft kick on 1 and 3
        for k in (0, 2):
            kt = np.arange(int(SR * 0.3)) / SR
            kick = np.sin(2 * np.pi * (48 + 40 * np.exp(-kt / 0.03)) * kt) * np.exp(-kt / 0.12)
            add(kick, t0 + k * beat, 0.18)
        # brushes: a swish on 2 and 4, light taps on the swung 8ths
        for k in range(4):
            sw_n = int(SR * beat * 0.9)
            sw_t = np.arange(sw_n) / SR
            w = rng.standard_normal(sw_n)
            swish = (w - _lp(w, 0.6)) * np.sin(np.pi * np.minimum(1.0, sw_t / (beat * 0.9))) ** 1.5
            if k in (1, 3):
                add(swish, t0 + k * beat, 0.05)
            for off in (0.0, 0.66):
                tap_n = int(SR * 0.05)
                tw = rng.standard_normal(tap_n)
                tap = (tw - _lp(tw, 0.3)) * np.exp(-np.arange(tap_n) / SR / 0.012)
                add(tap, t0 + (k + off) * beat, 0.03 if off == 0.0 else 0.022)
    # fold the release tail back onto the head so it loops seamlessly
    tail = out[n:]
    out = out[:n]
    out[: len(tail)] += tail
    out = _lp(out, 0.35)   # take the edge off (lo-fi)
    return 0.6 * out / np.abs(out).max()


def main() -> None:
    for name, x in game_cues().items():
        _write(OUT / f"sfx_{name}.wav", x)
    _write(OUT / "rain.wav", rain())
    _write(OUT / "drips.wav", drips())
    _write(OUT / "step_wet.wav", step_wet())
    _write(OUT / "music_night.wav", music())
    print("slice audio OK ->", OUT)


if __name__ == "__main__":
    main()

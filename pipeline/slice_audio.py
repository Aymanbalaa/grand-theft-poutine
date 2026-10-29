"""Procedural ambience for the Rue Saint-Paul slice (license-free, deterministic).
Run: .venv/Scripts/python -m pipeline.slice_audio  ->  game/assets/slice/audio/*.wav

rain.wav       steady rain hiss + random drips/patter, seamless 12 s loop (stereo)
drips.wav      gutter drips onto metal/puddles, sparse, 9 s loop (stereo)
step_wet.wav   wet cobble footstep: thud + short splash
sfx_*.wav      game cues (order, pickup, cash, fleur, fail, end, whistle, bump)
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
    return {
        "order": _seq([659.3, 880.0], 0.11, 0.35, 0.18),
        "pickup": _seq([523.3, 659.3, 784.0], 0.07, 0.3, 0.12),
        "cash": _seq([1046.5, 1318.5, 1568.0, 2093.0], 0.055, 0.35, 0.1),
        "fleur": _seq([784.0, 987.8, 1174.7, 1568.0, 1975.5], 0.08, 0.6, 0.25),
        "fail": _seq([392.0, 311.1], 0.16, 0.45, 0.22),
        "end": _seq([523.3, 659.3, 784.0, 1046.5], 0.14, 0.9, 0.4),
        "whistle": 0.8 * whistle / np.abs(whistle).max(),
        "bump": 0.9 * bump / np.abs(bump).max(),
    }


def main() -> None:
    for name, x in game_cues().items():
        _write(OUT / f"sfx_{name}.wav", x)
    _write(OUT / "rain.wav", rain())
    _write(OUT / "drips.wav", drips())
    _write(OUT / "step_wet.wav", step_wet())
    print("slice audio OK ->", OUT)


if __name__ == "__main__":
    main()

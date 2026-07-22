"""Deterministic procedural game audio — no downloaded assets, license-free.
Run: .venv/Scripts/python -m pipeline.audio_gen  ->  game/assets/audio/*.wav"""
from __future__ import annotations
import wave
from pathlib import Path
import numpy as np

SAMPLE_RATE = 22050
OUT_DIR = Path(__file__).resolve().parent.parent / "game" / "assets" / "audio"

def _write_wav(path: Path, samples: np.ndarray) -> None:
    pcm = (np.clip(samples, -1.0, 1.0) * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())

def engine_loop(seconds: float = 2.0) -> np.ndarray:
    """Idle-engine hum: harmonic stack on 55 Hz plus 8.5 Hz tremolo. Every
    frequency completes an integer cycle count in `seconds`, so it loops."""
    t = np.arange(int(SAMPLE_RATE * seconds)) / SAMPLE_RATE
    out = np.zeros_like(t)
    for k, amp in ((0.5, 0.5), (1, 1.0), (2, 0.55), (3, 0.35), (4, 0.22), (6, 0.12)):
        out += amp * np.sin(2.0 * np.pi * 55.0 * k * t)
    out *= 1.0 + 0.15 * np.sin(2.0 * np.pi * 8.5 * t)
    return 0.6 * out / np.abs(out).max()

def footstep(seconds: float = 0.16) -> np.ndarray:
    """Low-passed noise burst with exponential decay."""
    rng = np.random.default_rng(7)
    n = int(SAMPLE_RATE * seconds)
    kernel = np.hanning(64)
    thud = np.convolve(rng.standard_normal(n), kernel / kernel.sum(), mode="same")
    thud *= np.exp(-np.arange(n) / (SAMPLE_RATE * 0.03))
    return 0.9 * thud / np.abs(thud).max()

def ambient_loop(seconds: float = 8.0) -> np.ndarray:
    """City rumble: smoothed brown noise, tail crossfaded into the head."""
    rng = np.random.default_rng(11)
    n = int(SAMPLE_RATE * seconds)
    brown = np.cumsum(rng.standard_normal(n + SAMPLE_RATE))
    brown -= np.linspace(brown[0], brown[-1], len(brown))
    kernel = np.hanning(256)
    rumble = np.convolve(brown, kernel / kernel.sum(), mode="same")
    body, tail = rumble[:n].copy(), rumble[n:n + SAMPLE_RATE]
    fade = np.linspace(0.0, 1.0, SAMPLE_RATE)
    body[:SAMPLE_RATE] = body[:SAMPLE_RATE] * fade + tail * (1.0 - fade)
    return 0.5 * body / np.abs(body).max()

def main() -> None:
    _write_wav(OUT_DIR / "engine.wav", engine_loop())
    _write_wav(OUT_DIR / "footstep.wav", footstep())
    _write_wav(OUT_DIR / "ambient.wav", ambient_loop())
    print(f"audio written: {OUT_DIR}")

if __name__ == "__main__":
    main()

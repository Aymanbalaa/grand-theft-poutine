import wave
import numpy as np
from pipeline.audio_gen import SAMPLE_RATE, engine_loop, footstep, ambient_loop, _write_wav

def test_engine_loop_seamless_and_deterministic():
    a = engine_loop()
    assert np.array_equal(a, engine_loop())
    assert abs(a[0] - a[-1]) < 0.05   # integer cycle counts -> continuous loop seam
    assert np.abs(a).max() <= 1.0

def test_footstep_short_decaying():
    s = footstep()
    n = len(s)
    assert n < SAMPLE_RATE // 2
    assert np.abs(s[: n // 4]).max() > np.abs(s[-n // 4:]).max() * 3.0

def test_ambient_loop_seam():
    s = ambient_loop()
    assert abs(s[0] - s[-1]) < 0.15
    assert np.abs(s).max() <= 1.0

def test_write_wav_format(tmp_path):
    p = tmp_path / "t.wav"
    _write_wav(p, np.zeros(1000))
    with wave.open(str(p)) as w:
        assert w.getnchannels() == 1
        assert w.getframerate() == SAMPLE_RATE
        assert w.getsampwidth() == 2
        assert w.getnframes() == 1000

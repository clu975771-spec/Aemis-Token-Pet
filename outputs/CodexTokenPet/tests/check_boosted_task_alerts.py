import array
import math
from pathlib import Path
import wave

root = Path(__file__).resolve().parents[1] / "voice-assets" / "task-alerts"


def inspect(path):
    with wave.open(str(path), "rb") as audio:
        assert audio.getnchannels() == 1 and audio.getsampwidth() == 2 and audio.getframerate() == 24000
        samples = array.array("h")
        samples.frombytes(audio.readframes(audio.getnframes()))
    peak = max(abs(value) for value in samples) / 32768
    rms = math.sqrt(sum(value * value for value in samples) / len(samples)) / 32768
    return len(samples), peak, rms


for kind in ("complete", "problem"):
    original_length, _, original_rms = inspect(root / f"{kind}.wav")
    last_rms = original_rms
    for percent in range(105, 201, 5):
        length, peak, rms = inspect(root / "boosted" / f"{kind}-{percent}.wav")
        assert length == original_length, (kind, percent, "duration changed")
        assert peak <= 0.881, (kind, percent, "peak exceeds limiter ceiling")
        assert rms > last_rms, (kind, percent, "loudness does not increase")
        last_rms = rms
    gain_db = 20 * math.log10(last_rms / original_rms)
    assert gain_db >= 2.8, (kind, gain_db)
    print(f"PASS: {kind} 200% is {gain_db:.2f} dB louder in RMS, peak limited")

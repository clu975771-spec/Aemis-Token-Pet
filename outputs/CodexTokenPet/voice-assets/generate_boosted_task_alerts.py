#!/usr/bin/env python3
"""Build 105–200% task-alert WAVs with a lookahead peak limiter.

The original 100% WAVs stay untouched. AVAudioPlayer.volume cannot provide
gain above unity, so the app selects one of these pre-rendered files instead.
"""

from array import array
from math import exp, log10, sqrt
from pathlib import Path
import sys
import wave


ROOT = Path(__file__).resolve().parent / "task-alerts"
OUTPUT = ROOT / "boosted"
CEILING = 0.88


def read_mono_pcm16(path: Path):
    with wave.open(str(path), "rb") as source:
        params = source.getparams()
        if params.nchannels != 1 or params.sampwidth != 2 or params.comptype != "NONE":
            raise ValueError(f"Expected mono PCM16 WAV: {path}")
        samples = array("h")
        samples.frombytes(source.readframes(params.nframes))
        if sys.byteorder != "little":
            samples.byteswap()
        return params, [sample / 32768.0 for sample in samples]


def limited_boost(samples: list[float], sample_rate: int, multiplier: float):
    # Build a safe gain curve at each sample. A backward pass brings peak
    # reduction forward by up to 10 ms; the forward pass releases over 80 ms.
    attack_step = 1.0 / max(1, int(sample_rate * 0.01))
    safe = [min(1.0, CEILING / (abs(sample) * multiplier)) if sample else 1.0
            for sample in samples]
    for index in range(len(safe) - 2, -1, -1):
        safe[index] = min(safe[index], safe[index + 1] + attack_step)
    release = 1.0 - exp(-1.0 / (sample_rate * 0.08))
    gain = safe[0]
    result = array("h")
    for sample, limit in zip(samples, safe):
        gain = min(limit, gain + (1.0 - gain) * release)
        value = max(-CEILING, min(CEILING, sample * multiplier * gain))
        result.append(round(value * 32767))
    if sys.byteorder != "little":
        result.byteswap()
    return result


def level(samples):
    values = [sample / 32768.0 for sample in samples]
    return (20 * log10(max(abs(sample) for sample in values)),
            20 * log10(sqrt(sum(sample * sample for sample in values) / len(values))))


def main():
    OUTPUT.mkdir(exist_ok=True)
    for kind in ("complete", "problem"):
        params, samples = read_mono_pcm16(ROOT / f"{kind}.wav")
        for percent in range(105, 201, 5):
            processed = limited_boost(samples, params.framerate, percent / 100.0)
            target = OUTPUT / f"{kind}-{percent}.wav"
            with wave.open(str(target), "wb") as result:
                result.setparams(params)
                result.writeframes(processed.tobytes())
            if percent in (105, 150, 200):
                peak, rms = level(processed)
                print(f"{target.name}: peak={peak:.2f} dBFS RMS={rms:.2f} dBFS")


if __name__ == "__main__":
    main()

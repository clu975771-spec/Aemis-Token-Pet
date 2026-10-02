#!/usr/bin/env python3
"""Prepare the two bundled reminder voices for clear local playback.

Run after generate_task_alerts.swift. No network or runtime processing is used.
"""
from pathlib import Path
import math
import struct
import wave


ROOT = Path(__file__).resolve().parent / "task-alerts"
TARGET_PEAK = 10 ** (-0.8 / 20)
THRESHOLD = 10 ** (-45 / 20)


def prepare(name: str) -> None:
    source = ROOT / "raw" / name
    destination = ROOT / name
    with wave.open(str(source), "rb") as sound:
        assert sound.getnchannels() == 1 and sound.getsampwidth() == 2
        rate = sound.getframerate()
        frames = sound.readframes(sound.getnframes())
    samples = struct.unpack(f"<{len(frames) // 2}h", frames)
    block = max(1, rate // 100)
    active = []
    for start in range(0, len(samples), block):
        chunk = samples[start : start + block]
        rms = math.sqrt(sum(value * value for value in chunk) / len(chunk)) / 32768
        if rms >= THRESHOLD:
            active.append(start)
    if not active:
        raise RuntimeError(f"No speech found in {source}")
    first = max(0, active[0] - int(0.10 * rate))
    last = min(len(samples), active[-1] + block + int(0.16 * rate))
    trimmed = samples[first:last]
    gain = TARGET_PEAK * 32767 / max(abs(value) for value in trimmed)
    fade = max(1, int(0.006 * rate))
    output = []
    for index, value in enumerate(trimmed):
        edge = min(1, index / fade, (len(trimmed) - 1 - index) / fade)
        normalized = value * gain * edge / 32767
        # Mild soft compression lifts quiet syllables without clipping consonants.
        softened = TARGET_PEAK * math.tanh(normalized / TARGET_PEAK) / math.tanh(1)
        output.append(max(-32768, min(32767, round(softened * 32767))))
    with wave.open(str(destination), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(rate)
        sound.writeframes(struct.pack(f"<{len(output)}h", *output))
    rms = math.sqrt(sum(value * value for value in output) / len(output)) / 32768
    peak = max(abs(value) for value in output) / 32768
    print(f"{name}: {len(output) / rate:.2f}s, RMS {20 * math.log10(rms):.1f} dBFS, peak {20 * math.log10(peak):.1f} dBFS")


for name in ("complete.wav", "problem.wav"):
    prepare(name)

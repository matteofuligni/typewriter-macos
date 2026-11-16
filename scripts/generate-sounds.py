#!/usr/bin/env python3
"""Generate the app's short original mechanical sounds as PCM WAV files."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 44100
TAU = math.tau
OUTPUT = Path(__file__).resolve().parents[1] / "Sources/Typewriter/Resources/Sounds"

def make(name, length, impacts, seed, bell=None):
    rng = random.Random(seed)
    data = []
    filtered = 0
    for index in range(int(RATE * length)):
        t = index / RATE
        noise = rng.uniform(-1, 1)
        filtered = filtered * .66 + noise * .34
        sample = 0
        for at, force, base, decay in impacts:
            x = t - at
            if x >= 0:
                edge = min(1, x * 3000)
                sample += edge * force * (
                    .62 * filtered * math.exp(-x / (decay * .34))
                    + .26 * math.sin(TAU * base * x) * math.exp(-x / decay)
                    + .14 * math.sin(TAU * base * 2.49 * x) * math.exp(-x / (decay * .47))
                    + .33 * math.sin(TAU * base * .39 * x) * math.exp(-x / (decay * .82))
                )
        if bell:
            at, strike = bell
            x = t - at
            if x >= 0:
                sample += strike * min(1, x * 1700) * (
                    .7 * math.sin(TAU * 1346 * x) * math.exp(-x / .095)
                    + .16 * math.sin(TAU * 2169 * x) * math.exp(-x / .05)
                )
        sample *= min(1, (length - t) * 135)
        data.append(int(math.tanh(sample * 1.9) * 30000))
    with wave.open(str(OUTPUT / f"{name}.wav"), "wb") as track:
        track.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        track.writeframes(struct.pack(f"<{len(data)}h", *data))

OUTPUT.mkdir(parents=True, exist_ok=True)
for index in range(8):
    make(f"key-{index}", .092, [(0, .98, 735 + index * 27, .007),
        (.007, .64, 1175 + index * 35, .005), (.029 + index * .0008, .27, 431, .01)], 100 + index)
make("backspace", .11, [(0, .74, 560, .012), (.021, .38, 840, .013), (.04, .19, 600, .008)], 7)
make("carriage", .34, [(0, .44, 460, .016), (.037, .57, 520, .012),
    (.052, .36, 570, .007), (.072, .36, 526, .01), (.101, .74, 365, .015),
    (.119, .30, 900, .017)], 29, bell=(.015, .34))

for index in range(8):
    make(f"crisp-key-{index}", .054, [
        (0, .89, 1090 + 41 * index, .0035), (.006, .52, 1685 - 23 * index, .003),
        (.018 + .0004 * index, .29, 685 + 15 * index, .004)
    ], 203 + index)
    make(f"soft-key-{index}", .071, [
        (0, .60, 345 + 19 * index, .0070), (.011, .22, 503 - 8 * index, .007),
        (.022, .15, 284, .009)
    ], 311 + index)
make("crisp-backspace", .065, [(0, .82, 1008, .0045), (.018, .38, 584, .006)], 41)
make("soft-backspace", .094, [(0, .55, 309, .011), (.019, .28, 222, .0085)], 52)
make("crisp-carriage", .24, [
    (0, .69, 1010, .009), (.027, .45, 710, .006), (.048, .49, 815, .008),
    (.08, .73, 530, .013), (.095, .24, 1040, .009)
], 69, bell=(.012, .26))
make("soft-carriage", .20, [
    (0, .40, 380, .014), (.030, .27, 288, .011), (.046, .26, 323, .009),
    (.077, .44, 234, .018)
], 83)

"""Generate the game's background loop: a quiet, original synth track, so no music license applies.

    pip install numpy soundfile
    python tools/make_music.py

Writes assets/audio/music/circuit_loop.ogg. The loop is 16 bars in A minor (pad, arpeggio,
bass, and soft ticks). Notes that ring past the end wrap to the start, so it loops without a seam.
"""

from pathlib import Path

import numpy as np
import soundfile

RATE = 32000
BPM = 96
BEAT = 60 / BPM
BARS = 16
LENGTH = int(round(BARS * 4 * BEAT * RATE))
# (pad voicing, bass root) for each two-bar chord: Am F C G Am F G Em, as MIDI note numbers.
CHORDS = [([57, 60, 64], 45), ([53, 57, 60], 41), ([55, 60, 64], 48), ([55, 59, 62], 43),
          ([57, 60, 64], 45), ([53, 57, 60], 41), ([55, 59, 62], 43), ([55, 59, 64], 40)]
ARPEGGIO = [0, 1, 2, 3, 2, 1, 0, 1]  # indexes into the chord tones plus the octave, one per eighth note

rng = np.random.default_rng(311)


def hz(note: float) -> float:
    return 440.0 * 2 ** ((note - 69) / 12)


def place(track: np.ndarray, sound: np.ndarray, start: float) -> None:
    """Mix a sound in at `start` seconds, wrapping past the end so the loop is seamless."""
    index = (int(start * RATE) + np.arange(len(sound))) % LENGTH
    np.add.at(track, index, sound)


def envelope(length: float, attack: float, release: float) -> np.ndarray:
    t = np.arange(int(length * RATE)) / RATE
    return np.minimum(1.0, t / attack) * np.clip((length - t) / release, 0.0, 1.0)


def pad(note: int, length: float) -> np.ndarray:
    t = np.arange(int(length * RATE)) / RATE
    tone = sum(np.sin(2 * np.pi * hz(note) * detune * t) for detune in (0.998, 1.0, 1.002)) / 3
    tone += 0.15 * np.sin(4 * np.pi * hz(note) * t)
    return tone * envelope(length, 0.6, 0.9)


def pluck(note: int, length: float = 0.5) -> np.ndarray:
    t = np.arange(int(length * RATE)) / RATE
    tone = sum(np.sin(2 * np.pi * hz(note) * n * t) / n for n in range(1, 7))
    return tone * np.exp(-t / 0.16) * np.minimum(1.0, t / 0.004)


def bass(note: int, length: float) -> np.ndarray:
    t = np.arange(int(length * RATE)) / RATE
    tone = np.sin(2 * np.pi * hz(note) * t) + 0.3 * np.sin(4 * np.pi * hz(note) * t)
    return np.tanh(1.5 * tone) * envelope(length, 0.01, 0.25) * (0.75 + 0.25 * np.exp(-t / 0.3))


def tick() -> np.ndarray:
    noise = np.diff(rng.standard_normal(int(0.06 * RATE) + 1))
    return noise * np.exp(-np.arange(len(noise)) / RATE / 0.012)


def render() -> np.ndarray:
    track = np.zeros(LENGTH)
    chord_length = 8 * BEAT
    for index, (tones, root) in enumerate(CHORDS):
        start = index * chord_length
        for note in tones:
            place(track, 0.05 * pad(note, chord_length + 0.8), start)
        for half in range(4):
            place(track, 0.11 * bass(root, 2 * BEAT - 0.05), start + half * 2 * BEAT)
        notes = [note + 12 for note in tones] + [tones[0] + 24]
        for eighth in range(16):
            at = start + eighth * BEAT / 2
            sound = 0.07 * pluck(notes[ARPEGGIO[eighth % 8]])
            place(track, sound, at)
            place(track, 0.3 * sound, at + 1.5 * BEAT)  # a dotted-eighth echo for some space
            if eighth % 2:
                place(track, 0.025 * tick(), at)
    return 0.7 * track / np.abs(track).max()


if __name__ == "__main__":
    out = Path(__file__).resolve().parents[1] / "assets/audio/music/circuit_loop.ogg"
    out.parent.mkdir(parents=True, exist_ok=True)
    soundfile.write(out, render().astype(np.float32), RATE, format="OGG", subtype="VORBIS")
    print(f"wrote {out} ({LENGTH / RATE:.1f} s)")

#!/usr/bin/env python3
"""gen_sfx.py — synthesize the Jarvis UI sound set for the AccessAI app.

Additive synthesis only (numpy + stdlib wave): each cue is a small chord of
sine partials with exponential decays, a soft attack to avoid clicks, and a
touch of detune "shimmer" so it reads as designed audio, not a beeper.

Cues (44.1 kHz, mono, 16-bit PCM, peak ~-6 dBFS):
  jarvis_wake.wav     rising cyan arpeggio   — "Jarvis is awake"
  jarvis_listen.wav   single soft high blip  — "listening"
  jarvis_success.wav  major-third confirm    — command done
  jarvis_error.wav    low falling minor buzz — command failed
  jarvis_thinking.wav gentle double pulse    — processing
  doorbell.wav        two-tone ding-dong     — visitor alert signature

Run:  cd mobile && ../.venv/bin/python tool/gen_sfx.py
Writes into mobile/assets/audio/ (registered in pubspec.yaml).
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def env(n, attack=0.008, decay=4.0):
    """Soft attack + exponential decay envelope of n samples."""
    t = np.arange(n) / SR
    a = np.minimum(t / max(attack, 1e-4), 1.0)
    return a * np.exp(-decay * t)


def tone(freq, dur, decay=4.0, attack=0.008, harmonics=((1, 1.0), (2, 0.25), (3, 0.08)),
         detune=0.0015, start=0.0, total=None, vibrato=0.0):
    """One note: stacked harmonics + a detuned twin for shimmer, placed at `start`
    seconds inside a buffer of `total` seconds (defaults to start+dur)."""
    total = total if total is not None else start + dur
    buf = np.zeros(int(SR * total))
    n = int(SR * dur)
    t = np.arange(n) / SR
    vib = 1.0 + vibrato * np.sin(2 * np.pi * 5.5 * t) if vibrato else 1.0
    note = np.zeros(n)
    for mult, amp in harmonics:
        f = freq * mult * vib
        note += amp * np.sin(2 * np.pi * f * t)
        note += amp * 0.6 * np.sin(2 * np.pi * f * (1 + detune) * t)
    note *= env(n, attack=attack, decay=decay)
    i = int(SR * start)
    buf[i:i + n] += note[: len(buf) - i]
    return buf


def write(name, sig, peak=0.5):
    sig = sig / (np.max(np.abs(sig)) or 1.0) * peak
    pcm = (sig * 32767).astype(np.int16)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print(f"  {name:22s} {len(sig)/SR:0.2f}s  {os.path.getsize(path)} bytes")


def main():
    os.makedirs(OUT, exist_ok=True)
    print(f"[gen_sfx] writing to {os.path.normpath(OUT)}")

    # Wake — A4→E5→A5 rising arpeggio, airy partials, long soft tail.
    wake = (
        tone(440.0, 0.50, decay=6, start=0.00, total=0.85)
        + tone(659.3, 0.50, decay=5, start=0.10, total=0.85)
        + tone(880.0, 0.60, decay=4, start=0.20, total=0.85,
               harmonics=((1, 1.0), (2, 0.30), (4, 0.06)))
    )
    write("jarvis_wake.wav", wake, peak=0.5)

    # Listen — one soft high blip (E6), fast decay. Unmissable but tiny.
    write("jarvis_listen.wav", tone(1318.5, 0.16, decay=18, attack=0.004), peak=0.42)

    # Success — C6→E6 quick major-third confirm.
    ok = tone(1046.5, 0.16, decay=12, total=0.40) + tone(1318.5, 0.26, decay=9, start=0.10, total=0.40)
    write("jarvis_success.wav", ok, peak=0.45)

    # Error — E4→A3 falling minor pair with a rough 2nd harmonic.
    err = (
        tone(329.6, 0.22, decay=8, total=0.50, harmonics=((1, 1.0), (2, 0.5), (3, 0.2)))
        + tone(220.0, 0.30, decay=7, start=0.14, total=0.50,
               harmonics=((1, 1.0), (2, 0.5), (3, 0.2)))
    )
    write("jarvis_error.wav", err, peak=0.45)

    # Thinking — two gentle vibrato pulses at C5. Calm, non-urgent.
    think = (
        tone(523.3, 0.30, decay=8, total=0.80, vibrato=0.004)
        + tone(523.3, 0.35, decay=7, start=0.35, total=0.80, vibrato=0.004)
    )
    write("jarvis_thinking.wav", think, peak=0.35)

    # Doorbell — classic E5→C5 ding-dong, bell-like inharmonic partials, long ring.
    bell_h = ((1, 1.0), (2.76, 0.35), (5.40, 0.12), (8.93, 0.04))
    door = (
        tone(659.3, 1.00, decay=3.0, total=1.40, harmonics=bell_h)
        + tone(523.3, 1.10, decay=2.6, start=0.30, total=1.40, harmonics=bell_h)
    )
    write("doorbell.wav", door, peak=0.55)

    print("[gen_sfx] done.")


if __name__ == "__main__":
    main()

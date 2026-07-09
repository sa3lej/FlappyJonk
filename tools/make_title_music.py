#!/usr/bin/env python3
"""Generate title_music.wav — an 8-bar NES-style chiptune loop for the
Flappy Jonk title screen. Four classic channels: pulse lead (50% duty),
pulse arpeggio (25% duty), triangle bass, noise drums. A minor, 112 BPM,
seamless loop (the echo wraps around the loop boundary on purpose).

Run from the repo root:  python3 tools/make_title_music.py
"""
import wave, struct, math, random

RATE = 22050
BPM = 112
SPB = 60.0 / BPM                 # seconds per beat
BARS = 8
TOTAL = int(BARS * 4 * SPB * RATE)

NOTE_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

def freq(name):
    letter = name[0]
    rest = name[1:]
    sharp = rest.startswith("#")
    octave = int(rest[1:] if sharp else rest)
    midi = 12 * (octave + 1) + NOTE_OFFSETS[letter] + (1 if sharp else 0)
    return 440.0 * 2 ** ((midi - 69) / 12)

buf = [0.0] * TOTAL

def add_tone(t0, dur, f, amp, duty=None, vibrato=False):
    """duty=None → triangle, else pulse with that duty cycle."""
    n0 = int(t0 * RATE)
    n1 = min(TOTAL, int((t0 + dur * 0.92) * RATE))   # small gap = staccato chip feel
    phase = 0.0
    for i in range(n0, n1):
        t = (i - n0) / RATE
        fr = f
        if vibrato and t > 0.12:
            fr *= 1.0 + 0.004 * math.sin(2 * math.pi * 5.5 * t)
        phase += fr / RATE
        p = phase % 1.0
        if duty is None:
            s = 4.0 * abs(p - 0.5) - 1.0
        else:
            s = 1.0 if p < duty else -1.0
        env = min(1.0, t / 0.003) * (1.0 - 0.25 * t / max(dur, 0.001))
        tail = (n1 - i) / (0.012 * RATE)
        buf[i] += s * amp * env * min(1.0, tail)

def add_noise(t0, dur, amp, bright):
    n0 = int(t0 * RATE)
    n1 = min(TOTAL, int((t0 + dur) * RATE))
    prev = 0.0
    for i in range(n0, n1):
        t = (i - n0) / RATE
        r = random.uniform(-1, 1)
        s = (r - prev) if bright else r      # difference ≈ high-passed hiss
        prev = r
        buf[i] += s * amp * (1.0 - t / dur) ** 2

random.seed(19920708)  # fixed seed — same song every run

# --- the song -------------------------------------------------------------
CHORDS = [  # (bass root, arpeggio notes) per bar
    ("A2", ["A3", "C4", "E4", "A4"]),   # Am
    ("F2", ["F3", "A3", "C4", "F4"]),   # F
    ("C3", ["C4", "E4", "G4", "C5"]),   # C
    ("G2", ["G3", "B3", "D4", "G4"]),   # G
    ("A2", ["A3", "C4", "E4", "A4"]),   # Am
    ("F2", ["F3", "A3", "C4", "F4"]),   # F
    ("D3", ["D4", "F4", "A4", "D5"]),   # Dm
    ("E2", ["E3", "G#3", "B3", "E4"]),  # E — pulls the loop back home to Am
]
LEAD = [  # eight eighth-notes per bar
    "A4 C5 E5 A5 G5 E5 C5 E5",
    "F5 E5 F5 A5 G5 F5 E5 C5",
    "E5 G5 C6 G5 E5 C5 D5 E5",
    "D5 B4 G4 B4 D5 G5 F5 D5",
    "A4 C5 E5 A5 G5 E5 C5 E5",
    "F5 A5 C6 A5 G5 F5 E5 F5",
    "D5 F5 A5 F5 E5 D5 C5 B4",
    "E5 D5 B4 G#4 B4 E5 G#5 B5",
]

for bar in range(BARS):
    bar_t = bar * 4 * SPB
    root, arp = CHORDS[bar]
    # lead: pulse 50%, with vibrato
    for i, name in enumerate(LEAD[bar].split()):
        add_tone(bar_t + i * SPB / 2, SPB / 2, freq(name), 0.30, duty=0.5, vibrato=True)
    # arpeggio: pulse 25%, twice through the chord per bar
    for i in range(8):
        add_tone(bar_t + i * SPB / 2, SPB / 2, freq(arp[i % 4]), 0.15, duty=0.25)
    # bass: triangle, root with a fifth bounce
    fifth = freq(root) * 1.5
    pattern = [0, 0, 1, 0, 0, 1, 0, 1]
    for i in range(8):
        f = fifth if pattern[i] else freq(root)
        add_tone(bar_t + i * SPB / 2, SPB / 2, f, 0.34)
    # drums: kick thump on 1 & 3, snare on 2 & 4, hats on the eighths
    for beat in range(4):
        t = bar_t + beat * SPB
        if beat % 2 == 0:
            add_tone(t, 0.09, 55.0, 0.5)             # triangle kick thump
            add_noise(t, 0.03, 0.10, False)
        else:
            add_noise(t, 0.09, 0.16, False)          # snare
        add_noise(t, 0.02, 0.05, True)               # hat
        add_noise(t + SPB / 2, 0.02, 0.05, True)     # off-beat hat

# space echo: half-beat delay, wrapping the loop boundary so it loops clean
delay = int(SPB / 2 * RATE)
dry = list(buf)
for i in range(TOTAL):
    buf[i] += 0.22 * dry[(i - delay) % TOTAL]

peak = max(abs(s) for s in buf)
scale = 0.82 * 32767 / peak
w = wave.open("title_music.wav", "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
w.writeframes(struct.pack("<%dh" % TOTAL, *(int(s * scale) for s in buf)))
w.close()
print("title_music.wav: %.1fs, %d bars at %d BPM" % (TOTAL / RATE, BARS, BPM))

#!/usr/bin/env python3
"""Generate title_music.wav — a 16-bar voodoo-funk chiptune loop for the
Flappy Jonk title screen. Four channels: pulse lead (50% duty, sparse and
bluesy), pulse chord stabs on the off-beats (25% duty, the wah-skank),
a fat syncopated triangle bass with ghost notes and slides, and swung
noise drums with a break bar. A dorian, 108 BPM, swung 16ths, seamless
loop (the echo wraps the loop boundary on purpose).

Run from the repo root:  python3 tools/make_title_music.py
Then reimport:           godot --path . --headless --import
"""
import wave, struct, math, random

RATE = 22050
BPM = 108
SPB = 60.0 / BPM                  # seconds per beat
STEP = SPB / 4.0                  # sixteenth note
SWING = 0.24                      # off-sixteenths land late = shuffle
BARS = 16
TOTAL = int(BARS * 4 * SPB * RATE)

NOTE_OFFSETS = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}

def freq(name):
    letter = name[0]
    rest = name[1:]
    sharp = rest.startswith("#")
    octave = int(rest[1:] if sharp else rest)
    midi = 12 * (octave + 1) + NOTE_OFFSETS[letter] + (1 if sharp else 0)
    return 440.0 * 2 ** ((midi - 69) / 12)

def t_of(bar, step):
    t = bar * 4 * SPB + step * STEP
    if step % 2 == 1:
        t += SWING * STEP
    return t

buf = [0.0] * TOTAL

def add_tone(t0, dur, f0, amp, duty=None, vibrato=False, f1=None):
    """duty=None → triangle. f1 set → glide from f0 to f1 over the note."""
    n0 = int(t0 * RATE)
    n1 = min(TOTAL, int((t0 + dur * 0.9) * RATE))   # staccato chip feel
    if n1 <= n0:
        return
    phase = 0.0
    span = max(1, n1 - n0)
    for i in range(n0, n1):
        t = (i - n0) / RATE
        fr = f0 if f1 is None else f0 + (f1 - f0) * ((i - n0) / span)
        if vibrato and t > 0.10:
            fr *= 1.0 + 0.005 * math.sin(2 * math.pi * 5.5 * t)
        phase += fr / RATE
        p = phase % 1.0
        s = (4.0 * abs(p - 0.5) - 1.0) if duty is None else (1.0 if p < duty else -1.0)
        env = min(1.0, t / 0.003) * (1.0 - 0.22 * t / max(dur, 0.001))
        tail = (n1 - i) / (0.010 * RATE)
        buf[i] += s * amp * env * min(1.0, tail)

def add_noise(t0, dur, amp, bright):
    n0 = int(t0 * RATE)
    n1 = min(TOTAL, int((t0 + dur) * RATE))
    prev = 0.0
    for i in range(n0, n1):
        t = (i - n0) / RATE
        r = random.uniform(-1, 1)
        s = (r - prev) if bright else r
        prev = r
        buf[i] += s * amp * (1.0 - t / dur) ** 2

def kick(t0, amp=0.5):
    add_tone(t0, 0.11, 95.0, amp, f1=44.0)          # pitch-dropping thump
    add_noise(t0, 0.02, 0.08, False)

random.seed(19920708)

# --- the groove ------------------------------------------------------------
# bass patterns: (step, len_in_16ths, note[, slide_target])
BASS = {
    "A": [(0, 3, "A1"), (4, 1, "C2"), (6, 1, "A1"), (7, 1, "G1"),
          (8, 2, "E1"), (11, 1, "G1"), (12, 2, "A1"), (14, 2, "A1", "A2")],
    "D": [(0, 3, "D2"), (4, 1, "F#2"), (6, 1, "D2"), (7, 1, "C2"),
          (8, 2, "A1"), (11, 1, "C2"), (12, 2, "D2"), (14, 2, "D2", "D1")],
    "E": [(0, 2, "E1"), (3, 1, "E2"), (4, 2, "E1"), (7, 1, "G#1"),
          (8, 2, "B1"), (11, 1, "D2"), (12, 2, "E2"), (14, 2, "E1")],
    "C": [(0, 3, "C2"), (4, 1, "E2"), (6, 1, "C2"), (7, 1, "B1"),
          (8, 2, "G1"), (11, 1, "B1"), (12, 2, "C2"), (14, 2, "C2")],
    "BRK": [(0, 2, "A1"), (6, 2, "G1", "A1"), (10, 5, "A1", "A2")],
}
STAB = {
    "A": ["C4", "E4", "G4"],            # Am7
    "D": ["F#4", "A4", "C5"],           # D9
    "E": ["G#4", "B4", "D5"],           # E7
    "V": ["G#4", "D5", "G5"],           # E7#9 — the voodoo chord
    "C": ["E4", "G4", "B4"],            # Cmaj7
}
# 16 bars: A A D A | A A D E | C D A V | A D A break
CHORDS = ["A", "A", "D", "A", "A", "A", "D", "E",
          "C", "D", "A", "V", "A", "D", "A", "BRK"]

# THE THEME — Raiders-style phrasing you can hum: a two-bar motif
# ("da-da-DAAA ... da-da" then a big held hero note), stated, restated
# with a higher second ending, then soaring; a simple B melody for
# contrast; the motif returns and resolves home right before the break
# so the loop relaunches it. (step, len, note)
M1 = [(0, 2, "A4"), (2, 2, "B4"), (4, 8, "C5"), (12, 2, "A4"), (14, 2, "B4")]
LEAD = {
    0:  M1,                                   # da-da-DAAA... da-da
    1:  [(0, 12, "E5")],                      # ...DAAAAA (the hero note)
    2:  M1,
    3:  [(0, 8, "G5"), (8, 8, "E5")],         # second ending, higher
    4:  M1,
    5:  [(0, 12, "E5")],
    6:  M1,
    7:  [(0, 4, "G5"), (4, 4, "A5"), (8, 8, "E5")],   # soaring climb
    # B theme — calmer answer, same singable simplicity
    8:  [(0, 4, "G5"), (4, 4, "E5"), (8, 4, "C5"), (12, 2, "D5"), (14, 2, "E5")],
    9:  [(0, 4, "F#5"), (4, 4, "D5"), (8, 8, "A5")],
    10: [(0, 4, "C5"), (4, 4, "A4"), (8, 8, "E5")],
    11: [(0, 4, "G5"), (4, 4, "G#5"), (8, 8, "B5")],  # voodoo tension climb
    # the theme returns and walks home
    12: M1,
    13: [(0, 12, "E5")],
    14: [(0, 2, "A4"), (2, 2, "B4"), (4, 6, "C5"), (10, 2, "B4"), (12, 4, "A4")],
}

for bar in range(BARS):
    ch = CHORDS[bar]
    # --- bass: the star of the show ---
    for ev in BASS.get(ch, BASS["E"]):   # the voodoo bar rides the E bass
        step, ln, note = ev[0], ev[1], ev[2]
        slide = freq(ev[3]) if len(ev) > 3 else None
        add_tone(t_of(bar, step), ln * STEP, freq(note), 0.44, f1=slide)
    # --- off-beat chord stabs (skip the break bar — let the bass talk) ---
    if ch != "BRK":
        for step in (3, 11):
            for n in STAB[ch]:
                add_tone(t_of(bar, step), STEP * 0.9, freq(n), 0.085, duty=0.25)
    # --- lead ---
    for step, ln, note in LEAD.get(bar, []):
        add_tone(t_of(bar, step), ln * STEP, freq(note), 0.26, duty=0.5, vibrato=True)
    # --- drums, swung ---
    if ch == "BRK":
        kick(t_of(bar, 0))
        kick(t_of(bar, 8), 0.4)
        for j, step in enumerate((10, 12, 13, 14, 15)):     # snare fill, rising
            add_noise(t_of(bar, step), 0.07, 0.08 + j * 0.03, False)
    else:
        for step in (0, 6, 10):
            kick(t_of(bar, step))
        for step in (4, 12):
            add_noise(t_of(bar, step), 0.09, 0.16, False)   # snare on 2 & 4
        if bar % 2 == 1:
            add_noise(t_of(bar, 15), 0.05, 0.06, False)     # ghost snare
        for step in range(0, 16, 2):
            add_noise(t_of(bar, step), 0.02, 0.045, True)   # hats
        if bar % 4 == 3:
            add_noise(t_of(bar, 14), 0.10, 0.07, True)      # open hat push

# swampy slapback: dotted-16th delay, wrapping the loop so the seam is clean
delay = int(3 * STEP * RATE)
dry = list(buf)
for i in range(TOTAL):
    buf[i] += 0.18 * dry[(i - delay) % TOTAL]

peak = max(abs(s) for s in buf)
scale = 0.85 * 32767 / peak
w = wave.open("title_music.wav", "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
w.writeframes(struct.pack("<%dh" % TOTAL, *(int(s * scale) for s in buf)))
w.close()
print("title_music.wav: %.1fs, %d bars at %d BPM, swung & funky" % (TOTAL / RATE, BARS, BPM))

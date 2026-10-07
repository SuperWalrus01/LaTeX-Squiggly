"""Synthesises the soundtrack from out/events.json: a soft pad, plus a sound for
each key press, tap and transition. Writes out/audio.wav (48 kHz stereo)."""
import json, sys, wave
import numpy as np

SR = 48000
rng = np.random.default_rng(7)
spec = json.load(open(sys.argv[1]))
dur = spec["duration"] + 0.2
n = int(dur * SR)
mix = np.zeros((n, 2))


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def env(length, attack, decay):
    t = np.arange(length) / SR
    return np.minimum(1, t / max(attack, 1e-4)) * np.exp(-t / decay)


def add(at, sig, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= n:
        return
    sig = sig[: n - i] * gain
    mix[i : i + len(sig), 0] += sig * (1 - pan) ** 0.5
    mix[i : i + len(sig), 1] += sig * (1 + pan) ** 0.5


def tone(freq, length, attack=0.002, decay=0.05, harm=(1.0,)):
    t = np.arange(int(length * SR)) / SR
    s = sum(a * np.sin(2 * np.pi * freq * (k + 1) * t) for k, a in enumerate(harm))
    return s * env(len(t), attack, decay)


def noise(length, cutoff, decay, attack=0.0005):
    m = int(length * SR)
    x = rng.standard_normal(m)
    x = x - lowpass(x, 900) if cutoff > 3000 else x
    return lowpass(x, cutoff) * env(m, attack, decay)


# One-shots, made once and reused with small variations.
def over(*parts):
    out = np.zeros(max(len(p) for p in parts))
    for p in parts:
        out[: len(p)] += p
    return out

def key():
    return over(noise(0.04, 3600, 0.007) * 0.9, tone(rng.uniform(1700, 1900), 0.03, decay=0.006) * 0.25)

def space():
    return over(noise(0.06, 2400, 0.014) * 1.2, tone(420, 0.05, decay=0.012) * 0.3)

def tap():
    return over(tone(880, 0.12, decay=0.035, harm=(1, 0.3)) * 0.5, noise(0.03, 4000, 0.006) * 0.4)

def whoosh(length=0.55, soft=False):
    m = int(length * SR)
    x = rng.standard_normal(m)
    t = np.linspace(0, 1, m)
    # A filter that opens and closes, done in three bands for speed.
    lo, mid, hi = lowpass(x, 500), lowpass(x, 1800), lowpass(x, 5000)
    shape = np.sin(np.pi * t) ** 2
    y = lo * (1 - t) + mid * np.sin(np.pi * t) + (hi - mid) * shape * 0.6
    return y * shape * (0.5 if soft else 0.9)

def send():
    t = np.arange(int(0.22 * SR)) / SR
    f = 600 + 900 * (t / t[-1]) ** 0.6
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.004, 0.07)
    return over(s * 0.55, whoosh(0.25, soft=True) * 0.6)

def chime(freqs, gap=0.07):
    out = np.zeros(int((0.6 + gap * len(freqs)) * SR))
    for k, f in enumerate(freqs):
        s = tone(f, 0.6, attack=0.003, decay=0.18, harm=(1, 0.25, 0.08))
        i = int(k * gap * SR)
        out[i : i + len(s)] += s
    return out * 0.32

def pop():
    t = np.arange(int(0.12 * SR)) / SR
    f = 380 + 500 * np.exp(-t * 40)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * env(len(t), 0.002, 0.04) * 0.6

KEYS = [key() for _ in range(6)]
SPACES = [space() for _ in range(3)]
for i, e in enumerate(spec["events"]):
    k, at = e["kind"], e["t"]
    pan = rng.uniform(-0.15, 0.15)
    if k == "key":
        add(at, KEYS[i % 6], 0.28 * rng.uniform(0.8, 1.0), pan)
    elif k == "mod":
        add(at, KEYS[i % 6], 0.24, pan)
    elif k == "delete":
        add(at, KEYS[i % 6], 0.22, pan)
    elif k == "space":
        add(at, SPACES[i % 3], 0.35, pan)
    elif k == "tap":
        add(at, tap(), 0.7)
    elif k == "send":
        add(at, send(), 0.8)
    elif k == "copy":
        add(at, chime([1318.5, 1975.5]), 0.9)
    elif k == "pop":
        add(at, pop(), 0.8)
    elif k == "whoosh":
        add(at - 0.18, whoosh(), 0.55)
    elif k == "whoosh-soft":
        add(at - 0.05, whoosh(0.4, soft=True), 0.5)
    elif k == "end":
        add(at, chime([523.25, 659.25, 783.99, 1046.5], 0.09), 1.1)

# The pad: four chords, soft triangles through a low-pass, slow swells.
chords = [[261.63, 329.63, 392.0, 493.88], [220.0, 261.63, 329.63, 392.0],
          [174.61, 220.0, 261.63, 329.63], [196.0, 246.94, 293.66, 392.0]]
bar = 2.4
t = np.arange(n) / SR
pad = np.zeros(n)
for b in range(int(dur / bar) + 1):
    notes = chords[b % 4]
    i0 = int(b * bar * SR)
    m = min(int((bar + 1.2) * SR), n - i0)
    if m <= 0:
        break
    tt = np.arange(m) / SR
    sw = np.minimum(1, tt / 0.6) * np.clip((bar + 1.2 - tt) / 1.2, 0, 1)
    seg = np.zeros(m)
    for f in notes:
        ph = 2 * np.pi * f * tt
        seg += (2 / np.pi) * np.arcsin(np.sin(ph)) * 0.6 + np.sin(ph * 0.5) * 0.25
    pad[i0 : i0 + m] += seg * sw
pad = lowpass(pad, 1100)
# A gentle pulse on the beat keeps it moving without drums.
beat = 0.6
pulse = 0.82 + 0.18 * np.cos(2 * np.pi * (t % beat) / beat)
# A soft bass on each bar.
bass = np.zeros(n)
for b in range(int(dur / bar) + 1):
    f = chords[b % 4][0] / 2
    s = tone(f, bar, attack=0.02, decay=1.2, harm=(1, 0.2))
    i0 = int(b * bar * SR)
    bass[i0 : i0 + len(s)] += s[: max(0, n - i0)]
music = pad * pulse * 0.30 + bass * 0.40
fade = np.minimum(1, t / 0.8) * np.clip((dur - t) / 1.5, 0, 1)
music *= fade
mix[:, 0] += music
mix[:, 1] += music

# Level it like the site videos: about -17 dB mean, peaks under -3 dB.
mix = np.tanh(mix * 1.0)
rms = np.sqrt(np.mean(mix ** 2))
mix *= 10 ** (-17 / 20) / rms
peak = np.max(np.abs(mix))
if peak > 10 ** (-3 / 20):
    mix = np.tanh(mix / peak * 1.4) / np.tanh(1.4) * 10 ** (-3 / 20)
data = (np.clip(mix, -1, 1) * 32767).astype("<i2")
with wave.open(sys.argv[2], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data.tobytes())
print("wrote", sys.argv[2], f"{dur:.2f}s")

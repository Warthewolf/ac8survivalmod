"""Distort voice WAVs into THE TANACORN's crew (the user's exception of 2026-11-17: AC7's Alicorn crew lines, distorted
and horrific, her dev install only; she hears every one before it goes in).

    python -I tools/ac7_voice_fx.py IN.wav [IN.wav ...] --style A|B|C|all [--out DIR]

numpy only (no ffmpeg / sox on the build machine). Styles:
  A  dying transmission: band-limited to a radio's 300-3400 Hz, crushed to 5 bits at 8 kHz, crackle bursts, dropouts that
     stutter the last few milliseconds
  B  possessed: down 5 semitones, a ring modulator at 47 Hz, the voice doubled an octave lower under it, saturated, a
     long cavernous reverb
  C  drowned ghost: a reversed reverb swelling into each word, a slow wavering pitch, a reversed whisper under it, muffled
     as if under water; repeating echoes after it and a long reverb tail (the user: "more echoey")
Writes <out>/<name>__<style>.wav (16-bit, the input's rate, mono).
"""
import argparse, os, sys, wave
import numpy as np

sys.stdout.reconfigure(encoding='utf-8')
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read(path):
    with wave.open(path, 'rb') as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    a = np.frombuffer(raw, dtype=np.int16 if sw == 2 else np.uint8).astype(np.float32)
    if sw != 2:
        a = (a - 128) * 256
    a = a.reshape(-1, ch).mean(axis=1) / 32768.0
    return a, sr


def write(path, x, sr):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = np.clip(x / peak * 0.89, -1, 1)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def resample(x, ratio):                                   # (ratio < 1: lower and longer; by linear interpolation)
    n = int(len(x) / ratio)
    t = np.arange(n) * ratio
    return np.interp(t, np.arange(len(x)), x)


def fftconv(x, h):
    n = len(x) + len(h) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(h, m), m)[:n]


def biquad_band(x, sr, lo, hi):                           # (a band by FFT masking, soft edges)
    m = 1 << (len(x) - 1).bit_length()
    X = np.fft.rfft(x, m)
    f = np.fft.rfftfreq(m, 1.0 / sr)
    g = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) / (1 + (f / hi) ** 4)
    return np.fft.irfft(X * g, m)[:len(x)]


def lowpass(x, sr, hi):
    return biquad_band(x, sr, 1, hi)


def reverb_ir(sr, secs, seed, bright=1.0):
    rng = np.random.default_rng(seed)
    n = int(sr * secs)
    t = np.arange(n) / sr
    ir = rng.standard_normal(n) * np.exp(-t * 6.9 / secs)
    ir = lowpass(ir, sr, 6000 * bright)
    ir[0] = 1.0
    return ir / np.max(np.abs(ir))


def style_a(x, sr, seed):
    rng = np.random.default_rng(seed)
    y = biquad_band(x, sr, 300, 3400)
    hold = max(1, sr // 8000)                             # (8 kHz sample-and-hold)
    y = np.repeat(y[::hold], hold)[:len(y)]
    y = np.round(y * 16) / 16                             # (5 bits)
    y = np.tanh(y * 3.0)
    for _ in range(int(len(y) / sr * 3)):                 # (dropouts that stutter: a few ms repeated)
        s = rng.integers(0, max(1, len(y) - sr // 5))
        seg = y[s:s + sr // 60].copy()
        reps = rng.integers(2, 6)
        end = min(len(y), s + len(seg) * reps)
        y[s:end] = np.tile(seg, reps)[:end - s]
    crackle = (rng.random(len(y)) < 0.002) * rng.standard_normal(len(y)) * 0.6
    hiss = rng.standard_normal(len(y)) * 0.03
    return y + crackle + biquad_band(hiss, sr, 1000, 6000)


def style_b(x, sr, seed):
    down = resample(x, 2 ** (-5 / 12))                    # (down 5 semitones)
    octv = resample(x, 0.5)[:len(down)]                   # (an octave lower, under it)
    octv = np.pad(octv, (0, len(down) - len(octv)))
    t = np.arange(len(down)) / sr
    ring = down * np.sin(2 * np.pi * 47 * t)
    y = 0.65 * down + 0.45 * ring + 0.5 * lowpass(octv, sr, 900)
    y = np.tanh(y * 2.6)
    wet = fftconv(y, reverb_ir(sr, 3.2, seed, 0.6))
    y = np.pad(y, (0, len(wet) - len(y)))
    return 0.7 * y + 0.35 * wet / (np.max(np.abs(wet)) or 1)


def style_c(x, sr, seed):
    rng = np.random.default_rng(seed)
    t = np.arange(len(x)) / sr
    warp = 1 + 0.035 * np.sin(2 * np.pi * 0.7 * t)        # (a slow wavering pitch)
    pos = np.cumsum(warp)
    pos = pos / pos[-1] * (len(x) - 1)
    y = np.interp(pos, np.arange(len(x)), x)
    ir = reverb_ir(sr, 2.4, seed, 0.8)
    swell = fftconv(y[::-1], ir)[::-1]                    # (the reversed reverb: it swells into each word)
    whisper = biquad_band(resample(y[::-1], 0.92), sr, 1800, 7000)
    whisper = whisper * (rng.standard_normal(len(whisper)) * 0.5 + 0.5)
    n = len(swell)
    pad = lambda a: np.pad(a, (n - len(a), 0)) if len(a) < n else a[-n:]
    mix = 0.75 * pad(lowpass(y, sr, 2200)) + 0.45 * swell / (np.max(np.abs(swell)) or 1) + 0.18 * pad(whisper)
    mix = np.tanh(mix * 1.6)
    # ((2026-11-17) the user: "can you make C more echoey?") repeating echoes (ECHO_S apart, each ECHO_FB of the last,
    # darker each time) and a long reverb tail after it
    tail = int(sr * (ECHO_S * ECHO_N + REVERB_S))
    out = np.pad(mix, (0, tail))
    d = int(sr * ECHO_S)
    tap = mix.copy()
    for k in range(1, ECHO_N + 1):
        tap = lowpass(tap, sr, 3000 - 500 * k) * ECHO_FB
        out[k * d:k * d + len(tap)] += tap
    wet = fftconv(out, reverb_ir(sr, REVERB_S, seed + 1, 0.7))[:len(out)]
    out = out + REVERB_WET * wet / (np.max(np.abs(wet)) or 1)
    return np.tanh(out * 1.2)


ECHO_S, ECHO_N, ECHO_FB = 0.34, 3, 0.55               # (style C's echoes: apart, how many, each of the last)
REVERB_S, REVERB_WET = 3.0, 0.5                         # (style C's reverb tail)
STYLES = {'A': style_a, 'B': style_b, 'C': style_c}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inputs', nargs='+')
    ap.add_argument('--style', default='all')
    ap.add_argument('--out', default=os.path.join(ROOT, 'build', 'ac7', 'voice_fx'))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    styles = list(STYLES) if a.style == 'all' else [a.style]
    for i, p in enumerate(a.inputs):
        x, sr = read(p)
        name = os.path.splitext(os.path.basename(p))[0]
        for s in styles:
            y = STYLES[s](x, sr, 7 + i)
            o = os.path.join(a.out, '%s__%s.wav' % (name, s))
            write(o, y, sr)
            print('%s -> %s (%.1f s)' % (name, os.path.basename(o), len(y) / sr))


if __name__ == '__main__':
    main()

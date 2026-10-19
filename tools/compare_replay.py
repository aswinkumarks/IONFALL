#!/usr/bin/env python3
"""Compare two ReplayCheck logs (PLAN §3.2 cross-platform bound: <= 1 cm).

Usage: tools/compare_replay.py a.log b.log
Logs can be raw stdout or `adb logcat` output; only "REPLAY t=" lines count.
Prints the first checkpoint over the bound and the max divergence over time.
"""
import math
import re
import sys

BOUND_M = 0.01
LINE = re.compile(r"REPLAY t=(\d+) (.*)$")


def load(path):
    out = {}
    with open(path, errors="replace") as f:
        for raw in f:
            m = LINE.search(raw.rstrip())
            if not m:
                continue
            players = {}
            for part in m.group(2).split():
                pid, xyz = part.split(":")
                players[int(pid)] = tuple(float(v) for v in xyz.split(","))
            out[int(m.group(1))] = players
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    a, b = load(sys.argv[1]), load(sys.argv[2])
    ticks = sorted(set(a) & set(b))
    if not ticks:
        sys.exit("no common checkpoints")
    first_over = None
    worst = 0.0
    for t in ticks:
        d = max(math.dist(a[t][p], b[t][p]) for p in a[t] if p in b[t])
        worst = max(worst, d)
        if d > BOUND_M and first_over is None:
            first_over = (t, d)
        if t % 600 == 0:
            print(f"t={t:5d}  max divergence {d * 100:.4f} cm")
    print(f"checkpoints {len(ticks)}  worst {worst * 100:.4f} cm  bound {BOUND_M * 100:.1f} cm")
    if first_over:
        print(f"FIRST OVER BOUND at t={first_over[0]}: {first_over[1] * 100:.3f} cm")
        sys.exit(1)
    print("PASS")


if __name__ == "__main__":
    main()

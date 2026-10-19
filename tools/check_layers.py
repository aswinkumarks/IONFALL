#!/usr/bin/env python3
"""Enforces the simulation/presentation split (PLAN §3.1, §3.20 rule 11).

Simulation and networking code must not reference presentation, UI, audio or
rendering, and must not call OS APIs directly (those go through `Platform`).
Exits non-zero and lists offending lines when a rule is broken.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECKED_DIRS = ["sim", "net", "modes", "bots"]

FORBIDDEN = [
    (re.compile(r'res://(presentation|ui|art|audio)/'), "references a presentation/UI/asset path"),
    (re.compile(r'\b(MeshInstance3D|AudioStreamPlayer\w*|GPUParticles\w*|CPUParticles\w*|Camera3D|AnimationPlayer|Control|CanvasLayer)\b'),
     "uses a presentation node type"),
    (re.compile(r'\bRenderingServer\b|\bAudioServer\b'), "uses a rendering/audio server"),
    (re.compile(r'\bOS\.(?!has_feature)\w+'), "calls OS directly (use the Platform service)"),
    (re.compile(r'\bInput\.(?!is_action)\w+|\bInputEvent\w*'), "reads input devices (use PlayerCommand)"),
]


def main() -> int:
    problems = []
    for d in CHECKED_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for path in sorted(base.rglob("*.gd")):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("#", 1)[0]
                for pattern, why in FORBIDDEN:
                    if pattern.search(code):
                        problems.append(f"{path.relative_to(ROOT)}:{n}: {why}: {line.strip()}")
    for p in problems:
        print(p)
    if problems:
        print(f"\n{len(problems)} layer violation(s). See PLAN §3.1.")
        return 1
    print("Layer check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

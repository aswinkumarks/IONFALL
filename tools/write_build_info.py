#!/usr/bin/env python3
"""Writes res://build_info.json before an export (PLAN §3.14).

Usage:
  tools/write_build_info.py --platform linux --arch x86_64 --config release

Prints the artifact ID. The compatibility hash covers everything that affects
the simulation, so two builds can only play together when their simulation
code, data and physics settings are identical.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROTOCOL_VERSION = 1

# Directories whose contents define simulation behaviour.
COMPAT_DIRS = ["sim", "net", "modes", "bots", "data"]
# Map gameplay scenes (collision, spawns) also define simulation behaviour.
COMPAT_GLOBS = ["maps/*/gameplay.tscn", "maps/*/gameplay.gd", "maps/*/*_layout.gd", "maps/*/*.res"]
COMPAT_IGNORE_SUFFIXES = {".import", ".uid", ".gitkeep", ".md"}


def project_setting(name: str) -> str:
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    m = re.search(rf'^{re.escape(name)}="([^"]*)"', text, re.M)
    if not m:
        sys.exit(f"project.godot has no {name}")
    return m.group(1)


def physics_section() -> bytes:
    text = (ROOT / "project.godot").read_text(encoding="utf-8")
    m = re.search(r"^\[physics\]\n(.*?)(?=^\[|\Z)", text, re.M | re.S)
    return (m.group(1).strip() if m else "").encode()


def compat_files() -> list[Path]:
    files: set[Path] = set()
    for d in COMPAT_DIRS:
        base = ROOT / d
        if base.is_dir():
            files.update(p for p in base.rglob("*") if p.is_file())
    for pattern in COMPAT_GLOBS:
        files.update(p for p in ROOT.glob(pattern) if p.is_file())
    return sorted(p for p in files if p.suffix not in COMPAT_IGNORE_SUFFIXES and p.name != ".gitkeep")


def compat_hash() -> str:
    h = hashlib.sha256()
    h.update(b"physics\0" + physics_section() + b"\0")
    for p in compat_files():
        rel = p.relative_to(ROOT).as_posix()
        data = p.read_bytes().replace(b"\r\n", b"\n")
        h.update(rel.encode() + b"\0" + hashlib.sha256(data).digest())
    return h.hexdigest()[:16]


def git_hash() -> str:
    try:
        out = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, check=True)
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
        return out.stdout.strip() + ("-dirty" if dirty else "")
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "unknown"


def version_code(version: str, build: int) -> int:
    """major*1,000,000 + minor*10,000 + patch*100 + build (PLAN §3.14)."""
    major, minor, patch = (int(x) for x in version.split("."))
    for name, value in (("minor", minor), ("patch", patch), ("build", build)):
        if not 0 <= value <= 99:
            sys.exit(f"{name}={value} is out of range 0-99 for the Android versionCode scheme")
    return major * 1_000_000 + minor * 10_000 + patch * 100 + build


def sync_android_version_code(code: int) -> None:
    """Sets `version/code` in every Android export preset to `code`.

    Godot reads the Android versionCode from the preset, so it's kept in sync
    with the versioning scheme here. The value is deterministic (version +
    IONFALL_BUILD_NUMBER), so re-running this doesn't change the file.
    """
    path = ROOT / "export_presets.cfg"
    text = path.read_text(encoding="utf-8")
    # Each chunk holds one `[preset.N]` block followed by its `[preset.N.options]`.
    sections = re.split(r"(?m)^(?=\[preset\.\d+\]$)", text)
    for i, section in enumerate(sections):
        if 'platform="Android"' not in section:
            continue
        if re.search(r"(?m)^version/code=", section):
            section = re.sub(r"(?m)^version/code=.*$", f"version/code={code}", section)
        else:
            section = re.sub(r"(?m)^(\[preset\.\d+\.options\]\n\n)", rf"\g<1>version/code={code}\n", section, count=1)
        sections[i] = section
    new_text = "".join(sections)
    if new_text != text:
        path.write_text(new_text, encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--platform", required=True)
    ap.add_argument("--arch", required=True)
    ap.add_argument("--config", choices=["debug", "release"], required=True)
    ap.add_argument("--print", choices=["artifact_id", "version_code", "compat_hash"], default="artifact_id")
    args = ap.parse_args()

    version = project_setting("config/version")
    build = int(os.environ.get("IONFALL_BUILD_NUMBER", "0"))
    ci_run = os.environ.get("GITHUB_RUN_NUMBER", "local")
    sha = git_hash()
    info = {
        "version": version,
        "version_code": version_code(version, build),
        "git_hash": sha,
        "compat_hash": compat_hash(),
        "protocol_version": PROTOCOL_VERSION,
        "artifact_id": f"ionfall-{version}-{args.platform}-{args.arch}-{args.config}-ci{ci_run}+{sha[:7]}",
    }
    (ROOT / "build_info.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    sync_android_version_code(info["version_code"])
    print(info[args.print])


if __name__ == "__main__":
    main()

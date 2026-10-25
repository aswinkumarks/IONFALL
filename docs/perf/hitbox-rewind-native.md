# Native hitbox rewind prototype (2026-10-25)

PLAN §3.17 names hitbox rewind as a likely GDExtension candidate. This is a
prototype of it with a benchmark, to decide whether wiring it into the
simulation is worth the native build cost. **It isn't used by the game yet**:
nothing loads it until `native/build.sh` is run, and `SimWorld` still calls
the GDScript code.

## What it is

`HitboxRewindNative` (`native/src/hitbox_rewind.*`) holds the lag-compensation
history of `sim/hitbox_history.gd` for every player and the capsule ray tests
of `sim/hitbox.gd`. Its `trace()` replaces the player loop of
`SimWorld._trace` (sample each candidate at the view tick, check `life_gen`,
intersect three capsules, keep the nearest) with one call:

```gdscript
var r: PackedFloat64Array = native.trace(ids, life_gens, view_tick, origin, dir, max_dist)
# [] on a miss, else [index into ids, distance, part]
```

It follows the GDScript arithmetic step for step (Vector3 in float, scalars
in double, built with `-ffp-contract=off`), so hits are **bit-for-bit the
same**. `tests/unit/test_hitbox_native.gd` checks that for `sample()`,
`intersect()` and `trace()` on histories with deaths, respawns and teleports
(about 32,000 asserts). Without the extension those tests pass as skipped, so
CI is unchanged.

## Results

Exported Linux **release** template (Godot 4.7.2), extension built
`template_release`, Intel Xeon @ 2.1 GHz (4 vCPUs, shared cloud VM).
Microseconds per call, median of 7 rounds; the ranges are three separate
runs. Before timing, each run checks that both paths give the same hits on
2,000 random rays.

| Case | Players | GDScript (µs) | Native (µs) | Speed-up |
|---|---|---|---|---|
| `record` one player, one tick | 16 | 0.60–0.66 | 0.48–0.51 | ×1.2 |
| `sample` one player | 16 | 1.7–2.1 | 0.41–0.44 | ×4 |
| Hitscan ray vs the others | 4 | 13–23 | 1.6–2.7 | ×8–9 |
| | 8 | 35–46 | 2.6–4.3 | ×11–14 |
| | 16 | 66–70 | 4.1–6.4 | ×11–17 |
| Scatter Gun shot (10 pellets) | 4 | 134–226 | 7.5–12 | ×17–30 |
| | 8 | 354–521 | 11–17 | ×30–37 |
| | 16 | 764–991 | 15–20 | ×50 |

The native times include building the candidate arrays in GDScript (once per
shot, as `SimWorld` would). The pellet case gains the most because the arrays
are built once and reused for all ten pellets.

## What it means

- Recording history is already cheap in GDScript; that part doesn't need C++.
- Tracing does. At 16 combatants one Scatter Gun shot costs **~0.8–1 ms** of
  GDScript on this CPU, about 15% of the 6 ms server tick p99 budget
  (§3.10). Two in the same tick take a quarter of it. A phone host has a 4 ms
  budget and a slower CPU. Native code brings a shot down to ~0.02 ms.
- The benchmark only covers the player loop. `SimWorld._trace` also casts a
  world ray per pellet (already native, in Jolt) and per candidate runs
  `_can_hurt` and `_rewind_tick`. So the real GDScript cost is if anything
  higher than measured here.
- This is a microbenchmark. Whether it moves **tick p99** in a real match
  depends on how often hitscan shots land in the same tick. That needs the
  integration below and a host soak (the `host-caps.md` setup).

## Not done yet

- **Wiring into `SimWorld`**: build `ids`/`life_gens` once per shot in
  `_resolve_shot`, call `trace()` per pellet, keep the GDScript path when
  `ClassDB.class_exists("HitboxRewindNative")` is false. The web build
  always takes that fallback (§3.17 browser rule).
- **Builds for other platforms**: only Linux x86_64 was built and run.
  Windows and Android (arm64, pinned NDK, 16 KB alignment, §3.18) need
  `native/build.sh` entries and CI jobs.
- **ARM parity**: on x86_64 the native path and GDScript agree bit for bit.
  On Android the engine is built with clang, which may fuse multiply-adds in
  the engine's own Vector3 maths; the native library doesn't. Hits are
  resolved only on the host, so a difference would only move a capsule edge
  by rounding error, not desync anyone. Run the parity test on a phone
  before shipping there.

## Reproduce

```bash
pip install scons                       # once
native/build.sh template_release        # fetches pinned godot-cpp, builds native/bin/
native/build.sh template_debug          # the library the editor binary loads
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json -gselect=test_hitbox_native.gd
godot --headless -s tools/bench/bench_hitbox_rewind.gd -- --players 16
```

The editor runs GDScript slower than a release export (at 16 players: ray
83 µs vs 7.6 native, shot 945 µs vs 18.6), so its numbers overstate the gain
a little. Export templates ignore `-s`, so for release numbers,
export a pack whose main scene calls
`preload("res://tools/bench/bench_hitbox_rewind.gd").run(OS.get_cmdline_user_args())`.
Include `tools/` and `tests/rewind_fixture.gd`, which the presets exclude.

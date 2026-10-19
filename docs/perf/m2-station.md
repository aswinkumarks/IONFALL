# M2: Meridian Station on target hardware (2026-10-19)

Offline bot match on map 1 (baked lightmap with shadowmask, Dynamic sun with
realtime character shadows, skinned characters). One-minute PERF lines from
`game/match.gd`.

| Device | Build | Combatants | fps avg | Frame p50 / p95 / p99 (ms) | Tick p99 (ms) |
|---|---|---|---|---|---|
| Laptop, Intel Xe (TGL GT2), 1080p, Vulkan Mobile | editor run | 8 | 60.0 | 16.7 / 16.7 / 16.7 | 1.51 |
| Mi 11X, Adreno 650, Vulkan Mobile, scale 0.75 | debug APK | 4 | 59.7 | 16.7 / 16.7 / 18.2 | 2.97 |
| Chrome on the laptop, web export (Compatibility) | release | 4 | 59.0 | 16.7 / 16.7 / 16.7 | 1.60 |

All runs are vsync-bound; thermal status 0 on the phone. Draw calls ~34 on the
laptop. Bake: ~2–16 s on the laptop GPU (138 s on software Vulkan).

Web smoke test (M2h): Chrome passes (menu and a local bot match; the only console
output is a warning about converting the RGTC shadowmask texture). Firefox is
still to be checked by hand.

Still to measure: a release APK, 8 combatants on the phone (the phone host is
capped at 4), and a 20-minute sustained run (M4).

## After the look-and-feel pass (2026-10-19)

Same scenario on the Mi 11X (debug APK, 4 combatants, autopilot), now with
the themed HUD, weapon viewmodels, particles, Quaternius astronauts and the
3D menu backdrop:

| Minute | fps avg | Frame p50 / p95 / p99 (ms) | Tick p99 (ms) |
|---|---|---|---|
| 1 (includes first-use shader compiles) | 57.6 | 16.7 / 16.7 / 25.0 | 1.82 |
| 2 | 59.0 | 16.7 / 16.7 / 18.1 | 1.82 |

Steady state matches the M2 baseline. The first-minute p99 comes from effects
and materials compiling on first use; a shader warm-up during the countdown
belongs to the M4 cold-start stutter work.

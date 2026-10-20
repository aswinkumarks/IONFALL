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

## Sentinel, first-person arms and the Medium preset (2026-10-20)

Mi 11X, debug APK, 4 combatants, autopilot; minute 2+ (minute 1 includes
first-use shader compiles). The Sentinel itself is not the cost: the
8-runner bench gives GPU p50 12.9 ms (Sentinel), 12.1 ms (Vanguard),
10.9 ms (Operative).

| Video settings | fps avg | Frame p50 / p95 / p99 (ms) |
|---|---|---|
| Medium as shipped (0.85 scale, FSR, soft shadows, sun shadows) | 54.7–57.6 | 16.7 / 23–25 / 29–31 |
| Medium extras at 0.75 scale | 58.3 | 16.7 / 22.2 / 28.9 |
| 0.75, soft shadows off, FSR | 57.8 | 16.7 / 22.2 / 29.2 |
| same, bilinear instead of FSR | 57.9 | 16.7 / 22.9 / 27.8 |
| same, sun shadows off | 55.8 → 59.4 | 16.7 / 25.0 → 16.7 / 27.5 → 25.0 |
| Low | 59.2 | 16.7 / 18.1 / 23.8 |

Sun shadows (every character drawn twice) are the main remaining cost.
Medium (the phone default) was then: 0.75 render scale, FXAA, glow, no
soft shadows and no sun shadows; baked lighting still shadows the map.
FSR1 needs the Forward+ renderer; the project uses Mobile, so the FSR rows
above were bilinear in practice (hence the identical numbers). `apply_video`
now only asks for FSR under Forward+.

### Halcyon Spire (2026-10-20)

Spire on the Mi 11X, 3 bots, autopilot, minutes 2–3. The larger map is
fill-rate bound at 0.75 render scale; glow costs almost nothing.

| Video settings | fps avg | Frame p50 / p95 / p99 (ms) |
|---|---|---|
| Medium (0.75 scale) | 55.9–57.1 | 16.7 / 24–25 / 31–32 |
| Medium without glow | 56.9–57.7 | 16.7 / 23–24 / 30–31 |
| Medium at 0.6 scale | 58.6–59.3 | 16.7 / 16.7–18.1 / 22–27 |
| Low | 59.2–59.5 | 16.7 / 16.7 / 18–23 |

Medium now uses a 0.6 render scale (on a 2400×1080 screen the 3D view is
1440×648; the HUD stays at full resolution). Players who want a sharper
image can raise the render scale in Settings.

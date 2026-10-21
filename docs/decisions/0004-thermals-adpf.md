# 0004: Thermals: adaptive quality, thermal headroom, ADPF

- **Status:** accepted (M4)
- **Context:** PLAN §3.10 asks for an automatic quality step-down when
  sustained frame time rises, and an M4 spike on how well Godot exposes
  Android's thermal (ADPF) APIs.

## What Godot 4.7 gives us

No engine API. Godot's `AndroidRuntime` singleton plus `JavaClassWrapper`
reach the Java APIs directly from GDScript, with no plugin:

| API | Use | Works from GDScript |
|---|---|---|
| `PowerManager.getCurrentThermalStatus()` (API 29) | 0 none … 6 shutdown | Yes (`Platform.thermal_status()`, in PERF lines since M1c) |
| `PowerManager.getThermalHeadroom(forecast s)` (API 30) | 0 cool … 1.0 = throttling starts | Yes (`Platform.thermal_headroom()`); rate-limited by Android to about 1 call/s, so cached for 5 s; NaN when unsupported |
| `PerformanceHintManager.createHintSession(tids, target ns)` (API 31) | tell the CPU governor the frame target and each frame's work | See the phone results below (`--adpf`, `Platform.start_performance_hints()`) |

## Decision

- **AdaptiveQuality** (`core/adaptive_quality.gd`), on by default (setting
  *Adaptive quality*): every 10 s window it checks frame p95 and the thermal
  readings. 3 slow windows in a row (p95 above 1.2× the target frame time),
  thermal status ≥ SEVERE, or headroom ≥ 0.95 → one step down, then 2
  windows of cooldown. Order: render scale −0.1 down to 0.5, effects
  density 0.4, sun shadows off. Glow is not stepped: toggling it
  changes pipeline specializations, and on the Mi 11X the compile burst
  cost more than glow saved. Session only, never saved;
  changing any video setting clears it. It never steps back up.
- **Headroom** is used because it rises well before the status changes, so
  the step-down can happen before the SoC throttles.
- **ADPF hint session:** see below.

## Phone results

Mi 11X (Android 13, MIUI), 20-minute soaks in docs/perf/m4.md:

- **Thermal status** stayed 0 (NONE) in every run, including runs that
  ended at 41–42 °C battery with the SoC visibly slower (frame p50 16.7 →
  18–20 ms at unchanged GPU time). MIUI throttles without reporting it.
- **Thermal headroom** returns NaN (unsupported) on this phone.
- So on the Mi 11X adaptive quality reacts only to frame time. Its render
  scale step (0.6 → 0.5) fired in each soak but bought nothing, because the
  misses there are main-thread time, not GPU.
- **ADPF:** `getPreferredUpdateRateNanos()` returns −1 and
  `createHintSession` returns null: the phone doesn't support hint
  sessions. `--adpf` stays an opt-in dev flag; nothing ships on by default.

Consequence: on phones like this one, thermal handling can't be predictive;
the remaining lever is CPU work per frame (see m4.md).

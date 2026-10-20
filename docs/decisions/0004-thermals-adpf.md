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
  density 0.4, glow off, sun shadows off. Session only, never saved;
  changing any video setting clears it. It never steps back up.
- **Headroom** is used because it rises well before the status changes, so
  the step-down can happen before the SoC throttles.
- **ADPF hint session:** see below.

## Phone results

_Pending: the Mi 11X runs of M4 (docs/perf/m4.md)._

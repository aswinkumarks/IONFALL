# M1c platform proof: measurements (Mi 11X)

Device: Xiaomi Mi 11X (Snapdragon 870, Adreno 650), release build, home
Wi-Fi to the dev PC (192.168.0.x). Logs: one `PERF` line per minute
(`adb logcat -s godot | grep PERF`), driven by the overlay's autopilot.
Targets from PLAN §3.10.

## Sustained tests

| Test | Duration | Frame p95 / p99 | Other | Target | Result |
|---|---|---|---|---|---|
| Phone **host**, 4 combatants (phone + 3 PC test clients) | 21 min | 16.7 / 18–24.5 ms, 60 fps every minute | thermal status 0; clients 0 visible corrections | p95 ≤ 18.2 ms | ✅ |
| Phone host server tick (before optimization) | 21 min | — | tick p50 ~2.0 ms, **p99 ~5.2 ms** | tick p99 ≤ 4 ms | ❌ → optimized |
| Phone host server tick (after) | 6 min | — | tick p50 ~2.3 ms, **p99 3.9–4.2 ms** (sim p99 ~1.9 ms) | ≤ 4 ms | ⚠️ marginal |
| Phone **client**, 8 combatants (dedicated PC server + 7 test clients) | 21 min | 16.7 / 18–22 ms | thermal 0; **6.6 visible corrections/min** | ≤ 1/min | ❌ → fixed |
| Phone client after "wait for late commands" | 10 min | 16.7 / 18–21 ms (one minute p95 19.0) | **0 visible corrections**, 1 correction total | ≤ 1/min | ✅ |

Server-tick optimizations: snapshots staggered across ticks (each client
still gets one every 2 ticks), players quantized once per tick and shared by
all clients, view-error diagnostics in a ring buffer. Further headroom
(GDExtension for hot paths) is an M2+ item; the phone-host cap stays at 4.

Correction fix: Wi-Fi power saving delivers commands in bursts. The server
used to guess a late command (repeat the last input) and the phone's
prediction disagreed. Now a player waits up to 8 ticks for its real command
(`ServerSession.MAX_STALL_TICKS`), the adaptive command buffer grows with
the measured jitter (2–6 ticks; ~4–6 on this Wi-Fi), and view-tick
validation uses the client's median arrival offset so bursts don't trip it.
Covered by `test_command_bursts_cause_no_visible_corrections`.

## Lifecycle and discovery (home router)

| Check | Result |
|---|---|
| LAN discovery: PC dedicated server listed on the phone | ✅ ("Dev PC · test_arena · 0/16") |
| Multicast lock via `AndroidRuntime` (no native plugin) | ✅ acquired while browsing/hosting |
| `ionfall://join?host=…&port=…` while the app runs | ✅ joined |
| App in background 15 s during a match → resume | ✅ server timed it out, client rejoined as the same player (token) |
| Back to menu with a reason on host shutdown | ✅ "Disconnected from the host" |
| Incoming phone call during a session | app paused correctly; immersive fullscreen was lost after the call → fixed (re-applied on focus) |
| Phone hotspot, AP isolation, Ethernet + Wi-Fi PC, Windows firewall prompt | not tested yet (needs other networks/devices) |
| Local-network permission denied | n/a until target SDK 37 |

## Lighting (PLAN §3.9)

Scene: `maps/lighting_test` (baked floor/walls, two Static accent lights,
Dynamic sun with 2-split shadows ≤ 30 m, 4 moving characters). Baked with
`tools/bake_lightmaps.sh`.

- **Format**: lightmaps import as VRAM-compressed HDR: **BC6H** on desktop,
  **ASTC 4×4 HDR** on the Mi 11X, 1 byte/texel. A 2048² page is 4 MiB
  (≈ 5.3 MiB with mips), so the 32 MiB budget allows ~6 pages.
- **Static shadows**: a Dynamic sun bakes only indirect light. Static
  geometry's sun shadows come from the **shadowmask** (`shadowmask_mode =
  Overlay`), and static meshes use `cast_shadow = Off`; realtime shadow
  casters are characters only. Checked visually: no double shadows,
  characters lit by the sun and the probe grid.
- **GPU cost** (Mi 11X, render scale 0.75, `viewport_get_measured_render_time_gpu`):

| Configuration | GPU p50 |
|---|---|
| All on, bicubic lightmap filter (engine default) | 11.1 ms |
| Bicubic off (**now the mobile default**) | **7.8 ms** |
| Bicubic off, shadowmask off | 7.5 ms |
| Lightmap off | 5.8 ms |
| Sun shadows off (bicubic on) | 9.9 ms (shadow pass ≈ 1.2 ms) |
| Render scale 1.0, bicubic on | 13.4 ms |

- Found on the way: the `video/render_scale` setting (0.75) was never applied;
  `Settings.apply_video()` now sets bilinear 3D scaling at startup.

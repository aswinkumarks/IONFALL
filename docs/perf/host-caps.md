# Host caps: PC host to 16 combatants (2026-10-24)

Exported Linux **release** build (branch `perf/host-caps`, on top of the
jump pads work), Intel Core i5-1135G7 with Iris Xe (Ubuntu 22.04, mains
power), 1920×1080 window, 60 fps cap. Halcyon Spire, FFA, the host player on
autopilot, bots filling the rest and headless test clients
(`--test-clients N --join 127.0.0.1 --map spire`, full client stack) joined
over ENet on the same laptop, so the clients' CPU use counts against the
host here. 21 minutes each, PERF lines once a minute (PLAN §3.10 method).

PC host targets: frame p95 ≤ 16.7 ms (laptop row of §3.10), no minute below
54 fps, server tick p99 ≤ 6 ms (the dedicated server budget; the phone
host's 4 ms comes from the phone's tighter frame budget).

| Run | Combatants (bots / test clients) | Frame p95 (ms) | Frame p99 (ms) | GPU p95 (ms) | Slowest minute | Tick p50 / p99 (ms) | Clients | Result |
|---|---|---|---|---|---|---|---|---|
| High (desktop default) | 12 (6 / 5) | 16.7 in 8 of 21 minutes, else 17.6–22.2 | 16.7–26.7 | 12.6–19.1 | 57.3 fps | 1.5–2.3 / 3.9–4.5 | 5/5 connected, 0 visible corrections | frames GPU-bound on this iGPU at High (adaptive quality stepped to 0.9 at minute 10); ticks fine |
| **Medium** | **16 (8 / 7)** | **16.7 in 20 of 21 minutes** (18.2 once) | 16.7–20.8 | 8.2–10.5 | 59.0 fps | 1.8–2.2 / 4.5–5.6 | 7/7 connected, test clients PASS | **pass** |

**Decision:** PC hosts take **16 combatants on LAN** (`MatchConfig.PC_HOST_CAP`).
Online PC hosts stay at 8 (`PC_ONLINE_HOST_CAP`): 16 players through the EOS
relays hasn't been measured (upstream from the host is about 600 B × 30 Hz
per client). The phone host stays at 4 until its own test (PLAN §3.5.1).

Found on the way:

- **Results with more than 16 participants broke the match end.** Bots that
  give way to joining players keep their stats lines, so the 12-combatant run
  had 17; the results message refused more than `MAX_PEERS` rows, the host's
  results screen errored and the release build crashed (segfault) at the
  first match end. Results now carry up to `Protocol.MAX_RESULT_ROWS` (32),
  keeping every human. Regression test in `test_scoring.gd`.
- 16-row scoreboards ran off a 720 px screen and the lobby list pushed the
  page down; the score table goes compact past 10 rows and the lobby list
  scrolls.
- Unattended soaks on this laptop stall after 5 minutes if the host crashes,
  which looked like a screen-blank stall at first (it wasn't: the VNC display
  has the screen saver and DPMS off).

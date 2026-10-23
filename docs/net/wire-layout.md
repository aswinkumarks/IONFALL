# Wire layout & bandwidth (measured)

Authoritative version of PLAN §3.3.5, updated from measurements. "Wire" adds
about 40 bytes per packet (IPv4 + UDP + ENet). Sizes come from encoding real
messages (`Snapshot.encode`, `Protocol.encode_commands`); rates from the
diagnostics overlay, the dedicated server's status line and the test clients.

## Messages

| Message | Layout | Bytes |
|---|---|---|
| Snapshot header | type 1, id 4, match_id 4, phase_seq 1, baseline_id 4, last_cmd_tick 4, buffer_delta 1, entity count 1, owner flag 1, projectile count 1, event count 1 | 23 |
| Remote player, full | id 2, gen 1, mask 1, pos 9 (i24 mm), vel 6 (i16 cm/s), yaw/pitch 4, flags+move/stance 2, shield/health 2, weapon 1, disc 1 | 29 |
| Remote player, moving delta | id 2, gen 1, mask 1, pos 9, vel 6, look 4 | 23 |
| Remote player, unchanged | id 2, gen 1, mask 1 | 4 |
| Owner block (exact floats, for reconciliation) | gen 1 + `Snapshot.write_owner` (2 weapons) | 98 |
| Projectile | owner 2, gen 1, action 4, pos 9, vel 6 | 22 |
| Fire event (hitscan) | type 1, shooter 2, gen 1, action 4, weapon 1, flags 1, origin 9, end 9 | 28 |
| Command packet (4 commands) | type, match_id, ack, interp, count + 4 × command | 91 |
| Flag block (protocol 7, after the pickup spots) | count 1 + per flag (CTF: 2): team 1, carrier 2, pos 9, return ticks 2 | 1 (+28 in CTF) |
| Wave block (protocol 7) | present 1 (+ co-op: wave 1, fighting 1, left 1, next 2) | 1 (+5 in co-op) |
| Flag event (reliable) | type 1, action 1, team 1, player 2, tick 4, pos 9 | 18 |
| Wave event (reliable) | type 1, action 1, wave 1, tick 4, enemies 1 | 8 |

Deviations from the PLAN worksheet:
- The owner block is 98 bytes, not ~48: positions, velocity and floor normal
  are sent as exact f32 so the client restores bit-identical state.
- Fire events are 28 bytes, not ~12 (two absolute positions).
- Deltas use **one acknowledged baseline per snapshot** (the newest snapshot
  the client acked) rather than per-entity baselines. Lost snapshots never
  break decoding (tested at 30 % loss); the cost is a slightly larger delta
  after loss.
- Command packets are 91 bytes, not ~85.

## Snapshot sizes

| Case | Application bytes |
|---|---|
| 8 players, measured (7 remote + owner + events), max over a 25 s run | 382 |
| 16 combatants: 15 moving deltas + owner | 466 |
| 16 combatants: 15 idle + owner | 181 |
| 16 combatants, typical: moving + 2 fire events + 4 projectiles | ~610 |
| 16 combatants, worst: 15 full + owner + 8 events + 24 projectiles | ~1,310 |

## Rates (measured)

| Setup | Client down (wire) | Client up (wire) | Server out (wire) |
|---|---|---|---|
| Localhost, dedicated server + 8 test clients (moving, firing) | 6.8 kB/s per client | 8.0 kB/s | 55 kB/s |
| Mi 11X over Wi-Fi, server + 1 dummy | 5.5 kB/s | 8.2 kB/s | — |

Server step time (simulation + snapshots), dedicated server on the dev PC:
p50 1.2 ms, p99 7.3 ms with 8 clients.

## Against the budget

- **Up to 8 players** (listen-host cap): within budget (down < 16 kB/s).
- **Upstream** is 8.0–8.2 kB/s on the wire, about the 8 kB/s budget. Before
  internet play, drop to 3 redundant commands or delta-encode them.
- **16 combatants**: typical (~19.5 kB/s down) is over the 16 kB/s target,
  and the worst case (~1.3 kB) exceeds the 1,100-byte packet cap.
  Priority-based splitting (PLAN §3.3.3) is **not implemented yet**; it is
  required before dedicated servers run 16-player matches (M2). Cheaper fire
  events (end point as an i16 offset from the origin) and dropping velocity
  from deltas when it is derivable would also bring the typical case under
  budget.

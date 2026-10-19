# IONFALL: Project Plan

**Premise:** in orbit above a ruined Earth, the Ion Trials pit soldiers against each other in hard-light arenas aboard a research station. Combatants "fall" into each round as ion-charged teleports, which is also the in-game respawn effect.

**Plan status:** revision 2. All findings from the Codex review are addressed. The numbers marked *(provisional)* are starting points that get measured and fixed during the vertical slice (M1). The milestones have no time estimates until M1 is finished (see §6).

---

## 1. Locked decisions

| Area | Decision |
|---|---|
| Engine | **Godot 4.7.2-stable**, pinned exactly (editor, export templates, addons). Upgrade policy in §3.18 |
| Language | GDScript; C++ GDExtension only for hot paths that profiling proves slow (§3.17) |
| Platforms | Android, Linux, Windows; cross-play in the same LAN match. **Web browser client** is a post-v1.0 target, and the architecture keeps it possible from day one (§3.20) |
| Single-player | Bot matches on the multiplayer maps/modes |
| Modes | FFA (internal MVP) → TDM (v1.0) → CTF, Co-op Waves (post-v1.0) |
| Hosting | **Listen host**: PC up to 8 combatants, phone up to 4 *(provisional, raised only after the phone-host test passes)*. **Dedicated server** (Linux/Windows headless): 8 by default, up to 16 combatants. "Combatants" counts humans + bots |
| Movement | Sprint, slide, double-jump, mantle (wall-run post-v1.0). No portals/abilities. No hard player-player collision (§3.2) |
| Health | Shield + health, both regenerate (§2.2) |
| Weapons | Loadout (primary + sidearm + grenades) + power weapons at fixed map spots (§2.3) |
| Art | Stylized low-poly sci-fi with baked lighting; CC0-first assets under a written license policy (§4) |
| Test devices | **For now: the devices already on hand**: Xiaomi Mi 11X (Snapdragon 870 / Adreno 650, 120 Hz) + the dev Linux PC (+ a second device if available). A dedicated min-spec phone and iGPU laptops are added later (§3.10) |
| Distribution | PC builds + Android now; Google Play later (signed AAB built from M0 onward) |
| Persistence | Local profile: name, settings, stats, XP, cosmetic unlocks (§3.13) |
| Controls | Keyboard/mouse and touch (with aim assist). Gamepad is deferred, with no cost promise; the input abstraction keeps it possible |
| Language support | English at launch; localization-ready from the first UI (§3.16) |
| Perf targets | Defined per device and preset in §3.10 (no blanket "60 fps everywhere" claim) |

---

## 2. Gameplay design

### 2.1 Movement
Quake/Titanfall-inspired acceleration model. All values live in a `MovementConfig` resource and are part of the content hash (§3.14).
- Walk ~6 m/s, sprint ~8.5 m/s (sprinting lowers the weapon, so you can't fire)
- **Slide**: sprint + crouch → speed boost that decays over ~1 s and keeps momentum on slopes. Uses a low hitbox
- **Double jump**: second jump in the air with a small directional redirect
- **Mantle**: automatically climbs ledges up to ~1.8 m when holding forward + jump. Runs as a fixed-duration, tick-counted state with a server-validated target
- Limited air control, coyote time (6 ticks ≈ 100 ms), jump buffer (6 ticks)
- All timers count **ticks** rather than seconds, so client replays are exact (§3.2)
- Post-v1.0: wall-run, maybe grapple

### 2.2 Health / shield
| Stat | Value *(provisional)* |
|---|---|
| Shield | 100. Recharge starts **3.5 s** after the last damage, at 50/s |
| Health | 100. Regen starts **6 s** after the last damage, at 25/s |
| Damage order | Shield first; overflow carries into health in the same hit |
| Headshots | Multiplier applies **only to damage dealt to health**, except for *precision* weapons (Rail Sniper), whose multiplier also applies through shields |
| Regen interruption | Any damage (including self-damage) resets both timers |
| Feedback | Shield-break flash + sound, shield crackle on the character, low-health vignette (intensity setting, §3.16), recharge sound |

### 2.3 Combat & balance table
Effective HP = 200. Values are *(provisional)*; the table is the source of truth and lives in the `WeaponData` resources.

| Weapon | Slot | Fire | Damage | HS mult | Mag / reserve | Reload | Body shots to kill | TTK body / optimal |
|---|---|---|---|---|---|---|---|---|
| Pulse Rifle | Primary | Auto 600 RPM | 18 | ×1.5 (health only) | 36 / 180 | 2.0 s | 12 | 1.10 s / 0.90 s (6 body + 4 head) |
| Burst Rifle | Primary | 3-round burst, 0.33 s cycle | 18 × 3 | ×2 (health only) | 36 / 144 | 2.2 s | 4 bursts | 1.09 s / 0.76 s (3 bursts) |
| Scatter Gun | Primary | Pump 0.8 s | 10 pellets × 12 (≤ 5 m), falls off to 30% at 15 m | ×1 | 6 / 24 | 0.5 s per shell | 2 point-blank | 0.8 s |
| Mag Pistol | Sidearm | Semi, max 5 shots/s | 25 | ×2 (health only) | 12 / 60 | 1.5 s | 8 | 1.4 s / 1.0 s |
| Rail Sniper | Power | Bolt 1.2 s | 110 | ×2 (**precision**, through shield) | 4 / 8 | 2.5 s | 2 body / **1 head** | 1.2 s / instant |
| Arc Launcher | Power | Projectile 40 m/s, 1.0 s | 200 direct; splash ≤ 120, falls off to 0 at 4 m | — | 2 / 4 | 2.5 s | 1 direct | — |
| Frag grenade | Grenade | 2.5 s fuse | ≤ 130, falls off to 0 at 5 m | — | 2 | — | — | — |
| Melee | — | 0.9 s cooldown | 70 front, 200 back | — | — | — | 3 front / 1 back | — |

- **Range falloff**: Pulse/Burst/Pistol deal full damage to 30 m, falling linearly to 70% at 60 m
- **Spread & recoil**: deterministic; each shot's spread is seeded from `hash(player_id, shot_seq)` (§3.2)
- **Reload**: switching weapons cancels a reload. Sprinting allows the reload to continue. You can't fire until the reload finishes
- **Weapon switch**: 0.4 s raise; power weapons 0.6 s
- **Friendly fire**: off by default in TDM (host setting). **Self-damage** is on for explosives at 50%
- **Power weapons**: picking one up replaces your primary; your loadout primary drops and despawns after 20 s. If you die, the power weapon drops with its remaining ammo and despawns after 20 s. A spawn point's 60–120 s timer starts only when its previous instance no longer exists (so there is never more than one instance per spot). The HUD shows the countdown
- **Pickup contention**: the server resolves pickups in tick order; ties go to the player closest to the item
- **Grenades**: you get 2 per life. Grenade pickups at fixed spots give +1 (cap 2)
- **Extensibility**: new *variants* of existing firing types (hitscan auto/burst/semi, pellet, projectile) need only data plus a model. A genuinely new mechanic needs a checklist: sim state, prediction, replication, hit validation, presentation, audio, bot usage, balance-table entry

### 2.4 Scoring & modes
| Rule | FFA | TDM |
|---|---|---|
| Win | First to 25 kills or best at 10 min | First team to 50 kills or best at 10 min |
| Kill | +1 | +1 team |
| Suicide / fall | −1 | −1 player stat, not team |
| Team kill (FF on) | — | −1 team, offender's stat −1 |
| Environmental death | Credit goes to the last enemy who did damage within 5 s | same |
| Assist | ≥ 40 damage within 5 s before the kill → assist (stat + XP only) | same |
| Ties at time limit | Sudden death: next kill wins (max 2 min, then a draw) | same |

Post-v1.0: **CTF** (map 2 is built symmetric and CTF-ready) and **Co-op Waves**.

### 2.5 Spawn system
- **Server-side spawn scoring** for each spawn point: + distance to nearest enemy, − enemy line of sight (1 raycast per enemy, cached per tick), − recent deaths nearby (last 5 s), − occupied (another player within 2 m). TDM adds a bonus near teammates and a penalty for the enemy half. Pick randomly among the top 3. **Fallback**: the least-bad point, never blocked
- **Respawn delay**: FFA 3 s, TDM 5 s
- **Spawn protection**: 2 s of damage immunity with a visible shimmer. It is **cancelled** when the player fires, throws, melees or picks up a power weapon
- **Life generation ID**: each life gets a new `life_gen`. Damage, projectiles and lag-compensated hits aimed at an earlier `life_gen` are discarded, so delayed damage can't hit the new life
- **Reset on spawn**: full shield/health, loadout re-issued (switching loadout applies on the next spawn), 2 grenades

### 2.6 Combat feedback & match UX
- **Kill feed**: server-authored, max 5 visible rows, entries expire after 6 s. Shows killer, weapon icon, victim, plus headshot/assist markers
- **Death summary + death cam**: 3 s camera looking at the killer from the death position, killer name, killer's remaining shield/health, damage dealt/taken
- **Respawn countdown**, loadout change during the countdown
- **Hit markers**: shown optimistically on the client, then confirmed by the server (unconfirmed markers fade differently); a distinct kill marker
- **Scoreboard**, end-of-match results (stats, XP gained)
- **Spectator mode**: deferred to post-v1.0 (it needs slot rules, team restrictions and replication permissions; designed then)

### 2.7 Bots
- Run **only on the server**. Each bot is a normal player entity driven by a `BotBrain` that **outputs the same `PlayerCommand` stream** a human produces (§3.2), so bots use the same movement, validation and replication code
- **Navigation**: baked navmesh. Navigation links are tagged with the **traversal capability** they need (`jump`, `double_jump`, `mantle`, `drop`). When the bot reaches a link, a traversal action issues the matching inputs (e.g. jump at the edge, jump again at apex). Godot's links only describe connectivity; our code performs the move
- **Stuck recovery**: no progress for 1.5 s → jump, then sidestep, then re-path, then teleport to the nearest navmesh point (last resort, logged)
- **Budget**: perception at 10 Hz, re-pathing ≤ 2 Hz, staggered across bots. Movement still runs at 60 Hz through commands. Server cost is counted in §3.10
- **Brain**: utility AI choosing between attack / chase / retreat-to-regen / grab power weapon / roam / objective
- **Aim**: reaction delay + tracking error + target-speed penalty. **No difficulty gets wallhacks or perfect aim.** Higher difficulties only reduce delay and error
- **Difficulties**: Normal in the internal MVP; Easy/Normal/Hard/Insane in v1.0
- **Presentation**: `[BOT]` tag in nameplates, scoreboard and kill feed
- **Progression**: bot matches award 50% XP; stats are recorded separately as "vs bots"

---

## 3. Technical architecture

### 3.1 Code architecture: simulation vs presentation
Two layers, separated from **M0** onward (not retrofitted later):

| Layer | Contains | Runs on |
|---|---|---|
| **Simulation** | Player movement, weapon state, projectiles, damage, regen, spawns, mode rules, bots. Pure, tick-driven, no rendering/audio/UI references | Server (authoritative); client (prediction of the local player only) |
| **Presentation** | Meshes, animation, VFX, audio, HUD, camera smoothing, interpolation of remote entities | Clients only |

- Map scenes are split into a **gameplay scene** (collision, spawn points, pickup spots, navmesh) and a **presentation scene** (visual meshes, lights, lightmaps, audio). The dedicated server loads only the gameplay scene
- Presentation reacts to **simulation events** (shot fired, hit, death, footstep) keyed by `(entity_id, event_seq)`. An event seen before is ignored, so client replays never duplicate sounds or effects
- **Roles**: *Listen host* = server + local client in one process. The local client sends its commands through the same command path and validation as remote clients, and there is exactly **one authoritative simulation**. *Client* = presentation + local prediction. *Dedicated server* = simulation only

### 3.2 Simulation contract (what makes prediction replayable)
- **Fixed tick** of 60 Hz (`TICK = 1/60 s`). Tick IDs are `uint32`. No simulation code reads frame delta time
- **`PlayerCommand`** (one per tick): `tick`, `move` (2 × int8), `view_yaw`/`view_pitch` (quantized 16-bit), `held` buttons bitfield (fire, sprint, crouch, aim), **press counters** (uint8, wrap-around) for one-shot actions (jump, reload, switch, grenade, melee, interact), `weapon_slot`, `view_time` for lag compensation (§3.3.4)
  - Counters instead of edge flags: if a packet is lost, the next one still shows that "jump count went 4→5", so the action is never lost
- **`PlayerSimState`** (everything the replay needs): position, velocity, movement state enum, all state timers (ticks), jumps remaining, coyote and jump-buffer counters, stance, mantle target + progress, weapon slot, per-weapon {mag, reserve, cooldown ticks, reload ticks, burst counter, `shot_seq`}, grenade count, shield/health and regen timers, spawn-protection ticks, `life_gen`, last-processed press counters
- **Deterministic randomness**: spread/recoil seeded from `hash(player_id, shot_seq)`; no global RNG in the simulation
- **Per-tick order** (identical on server and in client prediction): apply command → movement → mantle/slide state → weapon state machine → spawn shots/projectiles → advance projectiles → resolve damage → regen → mode rules → emit events
- **Collision during replay**: players don't physically block each other (no player-player collision). This keeps replay independent of other players' predicted positions. A soft server-side separation push avoids stacking
- **Projectiles & shots** carry stable IDs `(owner_id, shot_seq)`, so a predicted projectile and the server's projectile are matched instead of duplicated
- **Prediction scope**: only the local player's movement, weapon state and cosmetic projectiles are predicted. Damage, kills and pickups are never predicted (only the optimistic hit marker is)

### 3.3 Netcode
#### 3.3.1 Model and the netfox decision
- **Target model**: forward-simulated authoritative server + client-side prediction/reconciliation for the local player + snapshot interpolation for remote entities + **hitbox-rewind lag compensation** for hitscan (Source/Overwatch style). **The server does not roll back the world.**
- **netfox** is evaluated in M1 (vertical slice), not later. It is adopted only if it passes these criteria:
  1. It supports mantle, slide, crouch hitboxes and projectile spawning without desync over 10 min at 100 ms RTT / 2% loss
  2. It runs headless and on Android
  3. It can be configured to match the target model. If its server-side rollback is used instead, then hitbox rewind is **not** applied as well, so there is no double compensation
  4. The phone-host CPU cost fits the budget in §3.10
  5. It works over the composite multi-transport peer (§3.20), i.e. it uses only the generic `MultiplayerPeer` API and makes no ENet-specific assumptions
  
  Otherwise the custom implementation below is built; that path is budgeted separately in the M1 estimate. The choice is recorded as a decision note in `docs/decisions/`.
- Transport: `ENetMultiplayerPeer` behind our own `Net` layer, so gameplay never calls ENet directly

#### 3.3.2 Clock sync & commands
- **Clock sync**: ping/pong every 1 s carrying the server tick; RTT and offset are smoothed (median of the last 8 samples)
- The client runs its simulation **ahead** of the server by `RTT/2 + command buffer`, so its commands arrive just in time
- **Sending**: the client sends one packet per tick containing the **last 4 commands** (redundancy) plus `ack_snapshot_id`
- **Server command queue** per client:
  - Target buffer of 2 ticks
  - Duplicates (an already-processed tick) are dropped
  - Commands older than the current tick are dropped; commands more than 8 ticks in the future are dropped and counted
  - **Missing command**: the server repeats the last held state with **no** new presses (press counters unchanged)
  - **Time abuse**: the server consumes at most one command per tick per client, so clients cannot gain extra simulation time. If a client's buffer stays too full or empty, the server tells it to run its tick clock 2% faster or slower (time dilation) instead of hard-resyncing

#### 3.3.3 Snapshots & events
- Snapshots are sent at 30 Hz (every 2nd tick), with `snapshot_id = server tick`
- **Delta encoding against an acknowledged baseline**: the server deltas against the most recent snapshot the client has **acked**. A full snapshot is sent if there's no ack for 1 s, the baseline is older than 32 snapshots, or on join/map change
- Entities have `net_id` + `generation` (a reused `net_id` with a new generation is a new entity; stale ones are dropped)
- **Gameplay events** (kill, hit confirm, pickup, spawn, power-weapon timer) are **tick-stamped and carried inside snapshots**. They are repeated until acked, so they always stay consistent with the state they describe
- **Channels**: 0 = unreliable (commands, snapshots); 1 = reliable ordered (match control, map change, join/leave); 2 = reliable ordered (chat). Chat can never block game control
- Every message carries `match_gen` (§3.4). Messages from an older match/map are dropped. Packets with an older `snapshot_id` than the newest applied are dropped
- **Join in progress**: full snapshot + current match state + all active timers on the control channel; the client acks once it is loaded (§3.4)
- **Quantization**: position 1 mm in map-local fixed point (int32 → delta-coded), velocity 1 cm/s, yaw/pitch 16-bit, health/shield 8-bit

#### 3.3.4 Interpolation & lag compensation
- **Remote entities** are rendered at `server_time − interp_delay`. `interp_delay` = 2 snapshot intervals (≈ 67 ms) + jitter margin, adaptive within 50–150 ms
  - **Underrun**: extrapolate for up to 100 ms, then hold the last state. Interpolation resets on teleport/respawn (`life_gen` change)
  - This snapshot interpolation is the only smoothing for remote entities; Godot physics interpolation is **off** for remote proxies, so smoothing is never applied twice
- **Local player**: the predicted state is rendered with sub-tick interpolation for high-refresh displays. Reconciliation errors are blended out visually over 100 ms, or snapped if > 1 m
- **Camera look** is applied every render frame (120 Hz phone / 144+ Hz PC) from the latest input, independent of the 60 Hz simulation; the next command carries the latest angles
- **Lag compensation (hitscan only)**:
  - Each command includes `view_time` = the interpolated server time the client was rendering
  - The server validates `view_time ∈ [now − 250 ms, now]`; out-of-range values are clamped (above 250 ms of total rewind, the shooter has to lead the target)
  - **Hitbox history**: ring buffer of 0.5 s (30 ticks) per player, storing position, stance (stand/crouch/slide hitbox sets), aim pitch, alive flag and `life_gen`
  - The server rewinds **only player hitboxes**; world geometry is static, so obstruction is checked against the current world. No rewind across a respawn or teleport (a `life_gen` mismatch counts as a miss)
  - **Listen host fairness**: the host's local client renders remotes with the same interpolation delay and uses the same lag-compensation path. The host's remaining advantage (0 RTT) is accepted and documented
- **Projectiles** (rockets, grenades) are **not** lag-compensated. The server spawns them at the command tick; the client spawns a predicted cosmetic copy with the same `(owner_id, shot_seq)`, which is replaced by the server's copy when it arrives
- **Simulated network conditions** are always specified as **RTT** (e.g. "100 ms RTT" = 50 ms each way) plus jitter and loss

#### 3.3.5 Bandwidth & packet budget *(provisional; measured in M1)*
| Item | Budget |
|---|---|
| Max UDP payload per packet | 1,100 bytes (below typical MTU after ENet/IP/UDP/DTLS overhead) |
| Player entity in a full snapshot | ~24 bytes quantized |
| 16-combatant full snapshot | ~450 bytes incl. header and events → fits in 1 packet |
| Client downstream | ≤ 20 kB/s (16 combatants, 30 Hz, worst case with full snapshots) |
| Client upstream | ≤ 6 kB/s (60 packets/s × 4 redundant commands) |
| Server outbound, 16 clients | ≤ 320 kB/s (~2.6 Mbit/s) worst case |

If a snapshot exceeds the payload budget (heavy explosions, many projectiles), entities are prioritized by distance and relevance and the rest are spread over following snapshots. A net graph (bytes/s, packets/s, loss, corrections/min, snapshot size max/p99) is in the debug overlay from M1.

### 3.4 Match state machine & connection lifecycle
Server-owned states. Every transition increments `match_gen`:

```
LOBBY ──start──▶ LOADING ──all acked / 30 s timeout──▶ COUNTDOWN (5 s) ──▶ PLAYING ──win/time──▶ POST_MATCH (15 s) ──▶ LOADING (next in rotation) or LOBBY
```
- **LOBBY**: join, choose team (TDM, with auto-balance) and loadout. No damage
- **LOADING**: the server sends `{map_id, mode, match_gen, content_hash}`. Clients load and ack. Clients that don't ack within 30 s return to the lobby with a reason. A wrong `content_hash` is rejected before loading (§3.14)
- **Late join** during PLAYING is allowed: load → ack → full snapshot → spawn. In TDM the player joins the smaller team
- **Reconnect**: within 60 s, a client presenting its `reconnect_token` (issued at join) gets its score, team and stats back. After that, it is treated as a new join
- **Disconnect cleanup**: the player entity is removed. Projectiles/grenades it already fired still resolve, and kills are credited. Held power weapons drop. Bots may backfill the slot (if enabled)
- **Warmup**: optional; damage on, no score
- **Match end**: the server sends final results with a `match_result_id` on the control channel. Clients save them atomically (§3.13)

### 3.5 Hosting
#### 3.5.1 Listen host
- "Host Game" from the menu. Single-player bot matches are a listen host with networking disabled
- **PC host**: up to 8 combatants
- **Phone host**: up to **4 combatants by default** *(provisional)*. It is raised to 8 only after the Mi 11X passes a 20-minute host test: render ≥ 55 fps p95, server tick p99 ≤ 4 ms, and no thermal drop below 50 fps
- **Android lifecycle** (host and client):
  - Screen stays on during matches
  - **Backgrounding, a phone call or screen lock** on a *host*: an on-screen warning appears first ("Leaving ends the match"). If the app stays in the background for over 5 s, the server ends the match with reason `host_left`, sends results and saves its own results
  - The same events on a *client*: the connection may time out (10 s). The player can reconnect within 60 s (§3.4)
  - **Wi-Fi change/loss**: back to the menu with a clear reason. Results already received are saved
- **No host migration.** Clients always get an explicit "match ended: host left" message plus partial results

#### 3.5.2 Dedicated server
- **Detection**: server mode starts when the build has the `dedicated_server` feature tag, or when the user argument `--server` is passed after `--`. `--headless` alone does not select server logic
- **Launch**: `ionfall_server --headless -- --server --config server.cfg [--port N --name X --max-combatants N --map M --mode M]`
- **Export**: Godot *dedicated server* export presets for Linux x86_64 and Windows (Linux arm64 is a stretch goal). Visual resources use **Strip Visuals** placeholders. Audio and presentation are kept out of the server by the gameplay/presentation scene split (§3.1) rather than relying on automatic stripping. The **exported** server is tested with every map, weapon and mode, not just the editor in headless mode
- **`server.cfg`**: name, port, max combatants (2–16), password, map/mode rotation, score/time limits, bot fill (count + difficulty), team balance, idle kick, admin password. The tick rate is **fixed at 60** (not configurable in v1.0)
- **Two run modes**:
  - `--standalone`: loops through the rotation by itself; idles at near-0% CPU with no humans connected (bots paused)
  - `--managed`: runs **one match**, then exits; controlled by the Manager (§3.5.3)
- **Output**: logs → stderr + rotating log file. In managed mode, stdout carries **only versioned JSON lines** (§3.5.3)
- **Admin console** (stdin in standalone mode; in-game for authenticated admins): `status, kick, ban, map, mode, bots, restart, say`. Security rules in §3.7
- **Profiles**: clients keep their own profiles. The server stores only its config, ban list (by IP + self-declared UUID; host-trust only, §3.7) and logs
- Operations: graceful shutdown on SIGTERM/Ctrl+C; Windows `.bat` launcher. systemd unit and Docker image come post-v1.0

#### 3.5.3 Central multi-match server (Manager), LAN first
- One **Manager** process (`--manager`) plus one `--managed` match process per match, each on its own port from a pool
- **Client flow**: the server browser shows the Manager as one entry → its match list → *Join* or *Create* → the Manager returns `{address, port, match_id, server_id}` → the client connects directly to the match. Gameplay traffic never goes through the Manager
- **Manager ↔ match protocol** (JSON lines, `"v":1`):
  - The match sends `hello{proto, pid, port}` → Manager `ack` → match loads → `ready`
  - `heartbeat` every 1 s; 5 missed heartbeats → the Manager kills and restarts the match
  - Commands carry an `id`; the match replies with `result{id, ok, error}`
  - Startup timeout 20 s. Restart backoff 1, 2, 4 … 60 s, at most 5 restarts per 10 min per playlist slot
  - On exit the Manager reaps the process and returns the port to the pool
  - **Manager lost** (stdin EOF): the match finishes its current match (max 15 min), sends results to clients, then exits
- **Manager duties**: on-demand matches + persistent playlists from `manager.cfg`, health watching, idle shutdown, admin console covering all matches
- **Capacity**: matches are admitted by **measured headroom** (keep ≥ 25% CPU and ≥ 1 GB RAM free; reject new matches while any match's tick p99 is above budget), not by core count. The density estimate (~6–8 matches on 8 cores, 150–300 MB each) is *provisional* until benchmarked (§5)

### 3.6 Discovery & ports
| Port (UDP) | Use |
|---|---|
| 47700 | Manager request/response |
| 47710 | Default game port (listen host / standalone server) |
| 47711–47799 | Manager match pool |
| 47777 | LAN discovery beacons |

- **Beacon** (≤ 512 bytes, binary): magic, beacon version, build ID, protocol version, content hash prefix, name, mode, map, combatants/max, flags (dedicated / manager / password), game port
- Sent every 1 s with `set_broadcast_enabled(true)`, both to `255.255.255.255` and to each interface's directed broadcast address (this covers phone hotspots and PCs with several network adapters). The advertised endpoint is the address of the interface the beacon left from
- **Client**: entries expire after 3.5 s. Parsing is bounded and rejects bad magic, oversize packets or invalid fields
- **Android**: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`. A multicast lock is held **only** while the server browser is open or while hosting. Newer Android versions add a runtime **local-network permission** (`ACCESS_LOCAL_NETWORK`, reported for target SDK 37+; *to be verified* when that target becomes required). The UI must handle the permission being denied
- **Fallbacks**: manual IP:port entry and **join links** (`ionfall://join?host=…&port=…`; on the web, `?join=host:port`). Discovery is always optional, and every join path works without it; the host shows its IP and a **QR join code**. Manual IP works only when routing and firewalls allow it: AP/client isolation, guest Wi-Fi and different subnets without routing will block it, and the UI says so on failure
- **Test matrix**: home router, phone hotspot (phone as host and as client), AP isolation on, PC with Ethernet + Wi-Fi, permission denied, firewall prompts on Windows

### 3.7 Security (LAN threat model)
**Trust levels:** the server trusts no client. Clients trust their host, and a listen host *can* cheat; LAN stats and bans are therefore **host-trust features**. A self-generated player UUID is a label, not an identity.

**Validation rules (from M1):**
- **Sender ownership**: every client→server RPC checks `get_remote_sender_id()` against the entity it touches. Only a whitelist of client entry points is callable by clients (`command`, `ack`, `chat`, `lobby_request`, `admin_auth`); everything else is server→client only
- **Bounded values**: floats must be finite and within range, enums in range, slots valid, `view_time` within the window, angle change per tick capped (anti-spinbot sanity check)
- **Size and rate limits**: command packet ≤ 256 bytes; chat ≤ 140 characters, 1 message/s (burst 3); names 3–16 graphemes, Unicode NFC-normalized, control characters stripped; lobby requests ≤ 5/s
- **Gameplay checks**: fire rate, ammo, reload, cooldowns, movement speed per state, mantle target validity, pickup distance
- **Connections**: handshake timeout 5 s, max 4 pending connections per IP, connection-rate limit per IP, malformed packets → disconnect + log
- **Admin**: disabled unless an admin password (≥ 8 characters) is configured. 3 failed attempts → 60 s lockout. All admin actions are logged
- **Fuzz tests** for all client entry points (§5)

### 3.8 Internet path (after LAN v1.0)
**Rule: no internet exposure until O1 is complete.** Accounts, encryption and baseline hardening ship together, so a login token is never sent over an unencrypted connection.

| Phase | Content |
|---|---|
| **O1 Secure identity & transport** | Accounts backend (HTTPS REST, e.g. Go/Node + PostgreSQL). **Short-lived, match-scoped join tickets** (signed; contain account ID, match ID, server ID, expiry ≤ 60 s, nonce; replay-checked by the match server). **DTLS** on client↔match and client↔Manager connections, via explicit `ENetConnection` DTLS setup, certificate validation and hostname checks, with per-server credentials. If DTLS or the ticket check fails, the join is refused with a clear error. Baseline hardening (§3.7 limits) required |
| **O2 Hosted servers** | **Public dedicated servers only** (no internet player-hosting at first). Managers on VPS nodes register with the backend. Join responses carry `{hostname/address, port, server_id, match_id}`. Documented firewall port ranges; IPv4 + IPv6 |
| **O3 Trusted progression** | Online stats/XP/unlocks stored on the backend in a separate profile namespace from LAN profiles. Results are accepted **only from registered, trusted servers** and applied idempotently by `match_result_id` |
| **O4 Matchmaking & operations** | Mode/region queue, reporting, account bans, chat moderation obligations, account deletion, Play Data Safety update |
| Later (separately budgeted) | Internet player-hosting via NAT traversal or a relay |

**DTLS prototype early**: a small DTLS spike runs in M1 on the pinned engine, so problems surface long before O1.

**Internet-ready rules from day one:** player UUID + per-match result records with `match_result_id`; a join handshake with `protocol_version, build_id, content_hash, player_uuid, auth_ticket` (ticket empty on LAN); server never trusts the client (§3.7); all networking goes through the `Net` layer; netcode is tested at 50–150 ms **RTT** with jitter and loss.

### 3.9 Rendering & lighting pipeline
- **Renderers**:
  - **Mobile renderer (Vulkan)** is the reference on Android and the default on PC. One shared art target, **validated per platform** (no "tuned once" assumption)
  - **Forward+ "High" preset** on PC adds SSAO, SSR, volumetric fog and FSR2
- **Resolution scaling**: the Mobile renderer gets **bilinear** render-scale only, since FSR1/FSR2 are Forward+ only in current Godot. Forward+ offers FSR2
- **Non-Vulkan Android devices are excluded** in v1.0, filtered via a required-Vulkan `uses-feature` in the manifest. A Compatibility (GLES3) preset is post-v1.0 and would get its own test pass
- **Supported on Mobile and used**: LightmapGI, glow, height/depth fog, decals, ReflectionProbes, tonemapping, per-map color grading LUT. **Not used on Mobile**: SSAO, SSR, volumetric fog
- **Lightmap pipeline**:
  1. Greybox in CSG → **convert to meshes** before baking
  2. Generate **UV2** (Godot's lightmap UV2 import option or a Blender unwrap). Triplanar materials remove the need for *UV1* texturing work, not the need for UV2
  3. Texel size per map *(provisional 0.2 m; 0.1 m on hero surfaces)*
  4. **Lightmap budget per map**: ≤ 32 MB GPU memory, ≤ 4 atlas pages of 2048². This is separate from the 1024² rule for regular textures
  5. Bake on the dev PC; bakes are committed via Git LFS. Whoever changes level geometry rebakes (part of the map checklist)
  6. **Static geometry** is fully baked. The **directional light** is "dynamic" only for character shadows (≤ 30 m, 2 cascades, toggleable); the Low preset uses blob shadows
  7. **Dynamic objects** (players, pickups, projectiles) are lit by the LightmapGI probe grid, so probe coverage is checked along all walkable space
  8. **ReflectionProbes** use update mode *Once* (baked at load)
  9. On-device check of every bake on the Mi 11X and the min-spec phone
- **Shaders**: triplanar panel material, hologram, shield crackle, hard-light surfaces. **Shader warm-up**: a warm-up pass at map load renders every material/VFX variant off-screen, plus the engine's pipeline pre-compilation where the pinned version provides it. Cold-start stutter is tested (§5)

### 3.10 Performance budgets & test devices *(all provisional until M1 measurements)*
**Performance promises** (each states resolution, combatants and preset):

| Device | Preset / resolution | Scenario | Target |
|---|---|---|---|
| Mi 11X (client) | Medium, render scale 0.75 of 2400×1080 | 8 combatants, worst-case map spot, 20 min sustained | ≥ 60 fps p95, no throttling below 55 fps |
| Mi 11X (phone host) | Medium, 0.75 | 4 combatants (8 after passing the test), 20 min | ≥ 55 fps p95, server tick p99 ≤ 4 ms |
| Min-spec Android (*deferred*, no device yet) | Low, 0.6 | 8 combatants, 20 min | ≥ 30 fps p95 (stretch: 45). **Unverified until a device is added** |
| Intel Iris Xe / AMD Vega 8 laptop (*deferred*) | Medium, 1080p | 8 combatants | ≥ 60 fps p95. **Unverified until tested** |
| Dedicated GPU PC | High (Forward+), 1080p–1440p | 16 combatants | ≥ 144 fps p95 |
| Dedicated server (reference: 4-core desktop CPU, recorded in `docs/perf/`) | — | 16 combatants incl. bots | tick p50 ≤ 2 ms, p99 ≤ 6 ms, ≤ 300 MB RSS |

The Mi 11X at lower render scale only tests **scalable GPU settings**. It doesn't simulate a weaker phone's CPU, memory bandwidth, drivers or thermals. **Current decision:** test only on devices already on hand for now. Min-spec and iGPU targets stay documented but *unverified*, and the store listing / README makes no claims about them until a real low-end device and an iGPU machine have been tested (required before the public Play release in M6).

**Frame budget (16.67 ms at 60 fps), mobile:** main thread ≤ 8 ms (sim + prediction replay ≤ 2 ms, bots/server on host ≤ 3 ms), render thread ≤ 6 ms, GPU ≤ 12 ms (leaves thermal headroom).

**Content budgets (mobile Medium):**
| Item | Budget |
|---|---|
| Draw calls | ≤ 250 |
| Visible triangles | ≤ 300k |
| Shadowed lights | 1 directional (characters only); dynamic omni lights unshadowed, ≤ 4 at once, short-lived |
| Textures | ≤ 1024², ETC2/ASTC, total texture memory ≤ 256 MB |
| Lightmaps | ≤ 32 MB per map (§3.9) |
| Transparent overdraw | ≤ 2 full-screen layers; particle quads capped per effect |
| Particles | GPU, ≤ 2,000 live, per-effect caps |
| Shader complexity | No more than 1 material variant per surface type; screen-space effects only via the preset |
| Memory | App RSS ≤ 1.2 GB on Android |
| Physics | Simple convex/box collision for the world; ≤ 16 active ragdoll bodies |

- **Scalable settings**: render scale, glow, shadows, particles density, decals, LOD bias, 30/60/90/120 fps cap
- **Thermals**: 20-minute sustained tests are mandatory. An automatic quality step-down when sustained frame time rises; evaluate Android ADPF thermal APIs via a plugin (*unsure* how well Godot exposes them, so a spike is needed)
- All performance numbers are measured on **release exports**, not editor/debug builds

### 3.11 Input, touch & aim assist
- **Input adapter layer**: device events (mouse, keyboard, touch, later gamepad) → normalized **`PlayerCommand`**. Gameplay never reads devices
- **Active input class** = the last-used device, which can switch live (e.g. a mouse plugged into an Android phone counts as KBM). It is reported to the server only as a label for the lobby
- **Touch layout**: floating left joystick (push to edge = sprint), right-side drag to look, buttons for fire (also drag-to-look), jump, crouch/slide, reload, swap, grenade, melee
  - Respects **safe areas** (notches, rounded corners)
  - Multitouch rules: a finger that started on a button never becomes a look finger. Move, look and fire work at the same time, and touch cancellation releases held actions
  - Layout editor (position/size/opacity) arrives in v1.0; fixed layout in the internal MVP
- **Aim assist** (touch only; the gamepad later gets its own tuning):
  - Target must be within a cone of 6° *(provisional)*, within the weapon's effective range, and **visible** (1 line-of-sight ray, 10 Hz)
  - Selection: smallest angular distance, weighted by distance
  - **Slowdown**: look sensitivity × 0.6 while the crosshair is over the target
  - **Magnetism**: while firing, follows ≤ 25% of the target's angular velocity. No snapping, no aiming through walls
  - **Auto-fire** (optional setting): automatic/burst weapons fire 120 ms after the crosshair lands on a target; disabled for the sniper, launcher and grenades
- **Server sanity** applies to all inputs: maximum view rotation per tick and impossible aim snaps are logged/flagged
- **Input-based lobbies**: a lobby can declare "touch only" or "mixed". This is a declared preference and is **not** enforced as anti-cheat

### 3.12 Audio
- **Buses**: Master → Music, SFX (Weapons, Footsteps, World, UI), with separate volume sliders
- **Voices**: ≤ 32 total, per-category caps (e.g. 8 gunfire, 6 footsteps). Priority: nearby enemy gunfire/footsteps > own weapon > world > ambience
- **Occlusion v1**: for each audible gameplay sound, 1 ray from listener to source every 100 ms (≤ 16 rays per frame overall). Occluded sounds get −6 dB and a 2 kHz low-pass. Reverb and propagation are deferred
- **Footsteps** are driven by the movement state (walk/sprint/slide/land) with distinct enemy vs. friendly sounds. Vertical position comes from 3D panning plus a subtle up/down filter cue
- Sounds come from simulation events, de-duplicated by `(entity_id, event_seq)` so prediction replays never double-play them (§3.1)
- **Dynamic range** setting: Full / Night (compressed)

### 3.13 Persistence: profile, stats, unlocks
- `user://profile.save` (versioned schema) and `user://settings.cfg`
- **Atomic writes**: write `*.tmp` → flush → rename. The previous file is kept as `*.bak`. If the main file fails to load or fails its checksum → use `*.bak` → else start a new profile and keep the corrupt file for diagnostics
- **Migrations**: every schema version has a migration function plus a test that loads a fixture save from each older version
- **Checksum** detects corruption only; it doesn't prove results are honest (LAN progression is local-trust)
- **Idempotent results**: each `match_result_id` is applied once. The last 200 applied IDs are stored
- **Stats**: kills, deaths, assists, K/D, wins, matches, accuracy, headshots, per-weapon kills, longest streak, time played (separately "vs players" and "vs bots")
- **XP formula** *(provisional)*: 10 per kill + 5 per assist + 1 per 10 s played + 100 per win + 30 per match completed; bot matches ×0.5
- **Incomplete matches** (quit or host left): XP for time played and kills, no win/completion bonus; stats recorded
- **Unlocks are cosmetic only** (armor colors/patterns, visors, weapon skins, emblems). LAN profiles and future online profiles stay in separate namespaces

### 3.14 Versioning & compatibility
| Identifier | Example | Purpose |
|---|---|---|
| Release version | `0.4.2` (semver) | Shown to players |
| Android `versionCode` | `major*10000 + minor*100 + patch` (+ build suffix scheme) | Play ordering |
| Build ID | `0.4.2+abc1234` (git hash) | Diagnostics, exact artifact |
| Protocol version | integer, bumped on any wire change | Network compatibility |
| **Content hash** | hash of gameplay data: maps' gameplay scenes, collision, `WeaponData`, `MovementConfig`, mode rules | Prevents playing on mismatched maps/rules |

- Joining requires an **equal protocol version and content hash**. Otherwise the error is clear, e.g. "Host runs 0.4.2 (abc1234), you have 0.4.1"
- The build records engine version, export templates and addon revisions (netfox etc.) in `build_info.json`
- Debug symbols are kept for every release artifact (desktop + Android native libraries)

### 3.15 Diagnostics
- **In-game overlay** (F3 / three-finger tap): FPS, frame time CPU/GPU, render-thread time, server tick time, RTT, loss, net graph, corrections/min, snapshot size, thermal status
- **Local logs** in a ring buffer (last 3 sessions)
- **"Export diagnostics"** button: zips logs, `build_info.json`, device/GPU/driver info and recent perf stats for the user to share manually
- **No remote telemetry or crash-reporting SDK in v1.0.** This is a deliberate decision, so the "no data collected" claim stays true. If added later, the data, retention and opt-in get documented and the Play Data Safety form is updated *before* release. After the Play release, Android crashes/ANRs are visible in Play Console vitals

### 3.16 Accessibility & localization
**Accessibility (basic-play items are in the M1/M2 slice):**
- Full key remapping; hold/toggle for crouch, aim and sprint
- Separate horizontal/vertical sensitivity, invert Y, FOV slider
- HUD and text scale (80–150%), subtitles/captions for important audio cues (power-weapon spawn, shield break)
- **Team identification not by color alone**: shapes/icons on nameplates and markers plus colorblind-friendly palettes
- Reduce screen shake, flashes, motion blur (none by default) and the low-health vignette
- Visual equivalents for key audio cues (damage direction indicator, nearby-gunfire indicator)
- Separate audio volume sliders (§3.12)

**Localization:**
- English at launch; every UI string uses `tr()` keys from day one (CSV/PO); locale-aware number/time formatting
- UI layout allows **+40% text expansion**; fallback fonts (Noto) for non-Latin names
- Player/server names in Unicode with the limits from §3.7
- A **pseudolocalization** test build is run before each release

### 3.17 C++ GDExtension policy
Start with 100% GDScript. Move a system to GDExtension only when profiling on a release export shows it over budget (likely candidates: hitbox rewind, bot perception, snapshot encoding). When the first one is introduced:
- Build every target (Linux x86_64, Windows x86_64, Android arm64-v8a; Android x86_64 for emulators) in **both debug and release** variants
- Use a `.gdextension` file with explicit per-platform library entries
- Pin the NDK, run CI builds for all targets, and verify 16 KB page alignment of the Android libraries (§3.18)

### 3.18 Android & Play Store
- **Engine version policy**: pinned to **4.7.2-stable**. At the M1 gate, consider 4.8.x only if it is stable with at least one bugfix release and fixes something we need; upgrade on a branch, re-run the M1 test suite, then merge. Never change engine versions mid-milestone
- **Toolchain pinned in M0**: Godot version + export templates, JDK, Android SDK platform/build-tools, Gradle/AGP from Godot's Gradle template, NDK (when GDExtension arrives). Versions are recorded in `docs/toolchain.md`
- **Gradle build** export from M0 (needed for the multicast-lock plugin and AAB)
- arm64-v8a (x86_64 optional for emulators); landscape-locked; immersive mode
- **A signed release AAB from M0**: install it on the Mi 11X via bundletool, run `zipalign -c -P 16` / the APK analyzer to check **16 KB page-size** alignment of all native libraries, and run on a 16 KB-page emulator image. This applies even with pure GDScript, since Godot itself is native code
- **Target SDK**: whatever Play requires at submission time (reported as API 36+ for new apps/updates as of Oct 2026; *re-verify at submission*)
- **Application ID: `io.github.aswinkumarks.ionfall`** (fixed; it can never change after the first Play upload). Name/trademark clearance for "IONFALL" happens **before** final logo/store art
- **Signing**: an **upload key** (ours) plus the **Play App Signing** key (Google's). The upload key and its passwords go in a password manager **plus** an encrypted offline backup in a second location, never in the repo. CI uses secrets only for release builds. One named owner holds the developer account credentials
- **Play checklist (before the first test release, M6)**:
  - Current target-SDK policy met
  - **Testing gate**: new personal developer accounts may need a closed test with **12 opted-in testers for 14 continuous days** before production access. Plan the closed-testing track early
  - **Data Safety form** (required even when no data is collected; declare "no data collected/shared" for v1.0)
  - SDK inventory (none beyond Godot + our plugins)
  - Privacy policy URL
  - Content rating questionnaire, target audience & content declarations (violence; not designed for children)
  - Store listing art
  - Later: account deletion and chat moderation obligations when O1/O4 add accounts and public chat

### 3.19 Project structure
```
game/
  project.godot
  addons/                 # pinned third-party addons (netfox if adopted, test framework)
  core/                   # autoloads: Net, GameState, Settings, Audio, Events, Diagnostics
  sim/                    # simulation layer: tick loop, commands, player/weapon/projectile sim, damage, spawns
  net/                    # transport wrapper, clock sync, snapshots, deltas, lag comp, discovery
  server/                 # dedicated/standalone/managed bootstrap, config, admin, rotation
  manager/                # (M7) multi-match manager
  presentation/           # player visuals, viewmodels, VFX, audio emitters, interpolation
  bots/                   # BotBrain, perception, traversal actions
  modes/                  # match state machine, FFA, TDM (later CTF, Waves)
  maps/<name>/            # gameplay.tscn, presentation.tscn, navmesh, lightmaps
  ui/                     # menus, HUD, touch overlay, scoreboard, settings, kill feed
  data/                   # WeaponData, MovementConfig, balance tables
  art/  audio/            # assets (Git LFS) + per-asset license records
  locale/                 # translation files
  native/                 # (later) GDExtension sources + build scripts
  tests/                  # unit, replay, fuzz, save-migration tests
  tools/                  # export scripts, CI, net test harness (netem scripts, headless test clients)
  docs/                   # decisions/, toolchain.md, perf/
```

### 3.20 Web client readiness (extensibility rules)
**Goal:** a browser **client** that can join dedicated/Manager servers can be added later without restructuring the game. Hosting a match and LAN discovery can't work in a browser and are out of scope for the web client. Bot matches running locally in the browser tab are possible but optional.

**Browser constraints the design accounts for:** no raw UDP (only **WebSocket**, which is TCP-based, or **WebRTC data channels**, UDP-like and encrypted, needing a signaling step); no UDP broadcast; the **Compatibility renderer** (WebGL 2) only; threads only with cross-origin isolation (unavailable over plain `http://` on a LAN IP); audio starts only after a user gesture; pages served over HTTPS can't open unencrypted `ws://`.

**Rules enforced from M0:**
1. **Transport-agnostic networking**: all networking goes through the `Net` layer, which exposes one `MultiplayerPeer` to the game. Gameplay never touches ENet APIs. The server's peer will later become a **composite peer** (`MultiplayerPeerExtension`) that accepts ENet clients and WebRTC/WebSocket clients into a single peer-ID space, so `@rpc`, snapshots and netfox (if adopted) work unchanged
2. **Channel and reliability mapping is explicit**: our 3 channels (§3.3.3) map to ENet channels today and to 3 WebRTC data channels later (unreliable/unordered; reliable/ordered; reliable/ordered). The packet budget (≤ 1,100 bytes) already fits WebRTC limits. The netcode must *degrade gracefully* over an all-reliable WebSocket link (stale-snapshot dropping and baseline acks already handle this)
3. **Discovery is optional**: every join path works from an address or a join link (§3.6)
4. **No threads required for correctness**: the game must run correctly with threading disabled (single-threaded web export). Threads are used only as optional speedups (e.g. background loading)
5. **Renderer-independent gameplay readability**: no gameplay-critical information depends on Mobile/Forward+-only features (glow, specific post-processing). Team markers, pickups, hit feedback and hazards must be readable in the Compatibility renderer. Custom shaders get a Compatibility-safe variant or fallback
6. **Platform services behind interfaces**: storage (`user://`, which maps to IndexedDB on the web), Android plugins (multicast lock, thermal), file dialogs and OS calls go through a `Platform` service with no-op/web implementations. No OS-specific calls in `sim/` or `net/`
7. **Input & lifecycle**: the input adapter (§3.11) handles pointer lock and its loss (Esc), browser-reserved keys, and tab focus loss (treated like Android backgrounding, §3.5.1). Audio starts after the first click
8. **Security path**: WebRTC is always encrypted; signaling and WebSocket fall back to `wss://` with certificates when served over HTTPS. This fits the O1 rule in §3.8
9. **Compatibility checks**: the web client sends the same handshake (`protocol_version`, `build_id`, `content_hash`), so §3.14 applies unchanged
10. **Download size**: keep the client `.pck` small enough for a browser load (target ≤ 150 MB *(provisional)*). Web exports need desktop (S3TC/BPTC) and mobile (ETC2/ASTC) texture formats

**Enforcement (so the rules don't rot):**
- **M0**: a **web export preset** (Compatibility renderer, single-threaded) exists and CI builds it on every commit
- **Every milestone**: a smoke test that opens the web build in Chrome and Firefox, reaches the main menu and renders the current test map with the Compatibility preset
- **M5**: a **spike** proving the composite peer: one dedicated server accepting an ENet client and a WebSocket client in the same match

**Web client milestone (post-v1.0):** composite peer + WebRTC transport (WebSocket as the simpler first step), signaling via the dedicated server/Manager, web UI flow (join by link/address), Compatibility visual preset, a page served by the dedicated server or Manager.

---

## 4. Art, audio & asset licensing
**License policy:** **CC0 preferred.** Non-CC0 assets are allowed only under licenses on an approved list that permit commercial use and redistribution inside a game binary. Approved so far: CC0, CC-BY 4.0 (with attribution) and the Sonniss GDC bundle license. **Every asset** has a row in `art/ASSETS.csv` / `audio/ASSETS.csv` recording source URL, author, download date, license, required attribution, modifications and redistribution limits. A copy of each license text goes in `licenses/`, and `CREDITS.md` is generated from the CSVs.

**Sources:** Quaternius (sci-fi kits, **rigged + animated characters**, guns; CC0), Kenney (space/blaster kits, UI, sounds; CC0), Poly Haven / ambientCG (HDRIs, textures; CC0), Sonniss GDC bundle (Sonniss license), sfxr-generated sounds (ours).

All assets are restyled with shared materials (team color, emissive trims, palette) so mixed packs read as one game. Anything missing is built in code/shaders.

- **Environments**: CSG greybox → modular mesh kit (floor/wall/trim/pillar/ramp) with triplanar materials + emissive strips, following the lightmap pipeline (§3.9). Theme: orbital research station (white panels, ion-cyan accents; teams cyan vs orange, plus shape markers)
- **Characters**: **decided by an on-device comparison in M1**: (a) one skinned CC0 rigged character (1 draw per material, uses existing animations) vs (b) rigid parts (≥ 10 draws each; 16 characters ≈ 160 draws before weapons and world). Default expectation: skinned wins
  - **Hitboxes** are authoritative simple shapes (head, torso, legs per stance) driven by the simulation state, independent of the animation pose
  - Ragdolls are cosmetic only: ≤ 4 at once, removed after 3 s
- **Weapons**: low-poly hard-surface models with emissive accents; procedural viewmodel sway/recoil/reload motion
- **VFX**: GPU particles within the budgets in §3.10
- **Audio**: as in §3.12; an ambient synth music loop

---

## 5. Testing strategy
| Layer | What | When |
|---|---|---|
| **Unit** (GUT or gdUnit4, chosen in M0; runs in **GitHub Actions**) | Damage/regen math, scoring edge cases, spawn scoring, balance-table checks, save migration + corrupt-save recovery, idempotent results | Every commit (CI) |
| **Replay determinism** | Record command streams, re-simulate, compare `PlayerSimState` every tick (movement incl. mantle/slide, weapon state, spread) | Every commit |
| **Netcode correctness** | Lost and duplicated commands (no lost/duplicated shots or jumps), snapshot baseline loss, out-of-order packets, `match_gen`/`life_gen` staleness, reconnect, map change mid-session | Every commit (headless) |
| **Fuzz** | Malformed and oversize packets, out-of-range values and wrong-sender RPCs against every client entry point | Nightly |
| **Simulation load** | Headless server + 16 server-side bots: tick time p50/p99 | Nightly |
| **Real-peer load** | 16 **headless test clients** (`--test-client`) running the full client network stack (prediction, reconciliation, acks, encoding) over real ENet connections; measures bandwidth and server CPU. Server-side bots alone don't count as a capacity test | Nightly from M5 |
| **Network conditions** | Linux `tc netem`: RTT 0/50/100/150 ms, ±20 ms jitter, reordering, 1–3% random + burst loss, bandwidth caps (2 Mbit/s client) | Per milestone |
| **Rendered cross-play** | Mixed Android/Linux/Windows **release** builds in one match | Per milestone |
| **Soak** | Dedicated server 60 min with 16 test clients; phone host 20 min; Mi 11X client 20 min (thermal) | Per milestone from M1 |
| **Capacity benchmark** | Manager: all-human (test clients), all-bot and mixed matches; tick percentiles, RAM, CPU headroom | M5 and M7 |
| **Cold start** | First match after install: shader stutter, load time | Per release |
| **Human playtests** | Feel (movement, TTK), touch usability, UI clarity, accessibility options | Every milestone |
| **Pseudolocalization** | Text expansion, missing keys | Per release |
| **Web smoke test** | Web export loads in Chrome + Firefox, reaches the menu, renders the test map with the Compatibility preset | Every milestone from M0 |
| **Multi-transport spike** | One server, one ENet client and one WebSocket client in the same match | M5 |

---

## 6. Milestones
Each milestone has exit criteria. **No durations are estimated until M1 is complete.** After M1, the remaining milestones are estimated and the cut lines confirmed.

| # | Milestone | Exit criteria |
|---|---|---|
| **M0** | Foundations & pipelines | Toolchain pinned + documented; git + LFS; application ID and upload key (backed up); versioning/build ID/content hash; export presets for Linux, Windows, Android (Gradle) **and the dedicated server**; **signed release AAB installed on the Mi 11X** with 16 KB check passing; CI builds; project skeleton with the `sim/` vs `presentation/` split; test framework; diagnostics overlay skeleton; `tr()` keys in the first menu; **web export preset (Compatibility, single-threaded) built in CI** (§3.20) |
| **M1** | **Vertical slice: prove the hard parts** | One greybox arena. Movement (sprint/slide/double-jump/mantle) built on the simulation contract. Pulse Rifle (hitscan) + Arc Launcher (projectile). Shield/health + spawn system. Minimal FFA match state machine. **Basic touch controls**. Listen host on **PC and phone**, headless **exported** dedicated server. Prediction, reconciliation, interpolation, lag compensation. **netfox decision** recorded. **DTLS spike**. LAN discovery + manual IP + QR. Character approach decided on device. **Measured**: bandwidth vs §3.3.5, correction rate, Mi 11X 20 min sustained as client (4 players) and as host. Cross-play PC↔Android at 100 ms RTT / 2% loss with no lost or duplicated actions. Replay determinism tests green |
| **Gate** | Go/no-go + estimate | Review M1 numbers; adjust budgets marked provisional; estimate M2–M6; confirm cut lines |
| **M2** | **Internal MVP** (playable game) | 1 map with first art pass, FFA, 2 weapons from M1 + Mag Pistol, bots (Normal) with traversal + stuck recovery, kill feed, death cam, HUD, results screen, profile/stats/XP with atomic saves + migration tests, settings, basic accessibility items, basic audio (buses, footsteps, occlusion v1). Playtested by humans |
| **M3** | Release content | Remaining weapons per the balance table, grenades, melee, power-weapon pickups + loadouts, **TDM** + teams + balance, **map 2** (symmetric, CTF-ready), 4 bot difficulties, cosmetic unlocks, touch layout editor + aim assist + auto-fire option, reconnect |
| **M4** | Art, audio & performance pass | Full lightmap pipeline on both maps, characters, VFX, audio pass, quality presets; all §3.10 targets met on the Mi 11X, min-spec phone, Iris Xe/Vega and a dedicated GPU (release builds, 20-min sustained); cold-start stutter test; phone host cap finalized |
| **M5** | Dedicated server complete | `server.cfg`, standalone + managed modes, rotation, bot fill, admin console with security rules, logs, Linux + Windows server exports; **16 real test clients** soak 60 min within tick/bandwidth budgets; fuzz tests green; **multi-transport spike** (ENet + WebSocket client in one match) |
| **M6** | **v1.0 LAN release** | Polish, full accessibility list, pseudoloc pass, desktop release builds (Linux, Windows), Play **closed testing track** started (14-day gate if required), Play checklist (§3.18) complete, Android release |
| **M7** | Central server (LAN), **only if v1.0 is stable** | Manager, match list/create/join UI, port pool, playlists, lifecycle protocol, restart backoff, admission by headroom; capacity benchmark (§5) published in `docs/perf/` |
| **O1–O4** | Internet play | As in §3.8, with O1 (secure identity + transport) before any internet exposure |
| Post-v1.0 | Expansion | **Web browser client** (§3.20), CTF, Co-op Waves, wall-run, spectator mode, gamepad, map 3+, Compatibility (GLES3) preset for non-Vulkan Android, systemd/Docker, more weapons/cosmetics |

**Cut lines if the estimate after M1 is too large** (cut in this order): 4 bot difficulties → 2; touch layout editor; map 2 (ship TDM on map 1); M7. The internal MVP (M2) is never cut.

---

## 7. Risks & mitigations
| Risk | Mitigation |
|---|---|
| Netcode feel (rubber-banding, unfair hits) | Simulation contract (§3.2) + measured vertical slice (M1) before any content work; replay determinism tests in CI; netem testing |
| netfox doesn't fit or needs a model change | Evaluated with written criteria in M1; custom path budgeted separately |
| Android performance and thermals | Real Mi 11X now (min-spec phone before public release), release builds, 20-min sustained tests from M1, scalable presets, conservative phone-host cap |
| Phone-host instability (backgrounding, Wi-Fi) | Lifecycle rules (§3.5.1), explicit match-ended messages, results saved, PC/dedicated hosting recommended in the UI |
| Discovery blocked (AP isolation, hotspots, permissions) | Directed broadcasts per interface, manual IP + QR, clear failure messages, test matrix (§3.6) |
| Touch vs mouse fairness | Defined aim-assist rules (§3.11), touch-only lobbies as an option |
| Server/client logic getting tangled | `sim/` vs `presentation/` split from M0; gameplay/presentation scene split; CI runs the exported headless server |
| Art scope creep | Modular kit + shared shaders; lock the style on map 1 in M2/M4 before map 2 gets art |
| Scope too large for a small team | Internal MVP (M2) defined small; estimate after M1; explicit cut lines |
| Play Store surprises (SDK level, 16 KB pages, testing gate) | Signed AAB + 16 KB checks from M0; Play checklist; closed testing started early |
| Losing the signing key | Upload key + Play App Signing, two encrypted backups, named owner |
| Asset license problems | Written license policy, per-asset records, license copies |
| GDExtension build complexity | Only when profiling demands it; full target/variant matrix in CI |
| Web client becomes impossible without a rewrite | Rules in §3.20 enforced from M0: web export built in CI, smoke test every milestone, multi-transport spike in M5 |
| Internet security later | O1 rule: no exposure before encrypted, ticketed, hardened joins; DTLS spike in M1 |

---

## 8. Resolved decisions & remaining items
| Item | Decision |
|---|---|
| Test devices | Use the 1–2 devices on hand for now (Mi 11X + dev PC). Min-spec phone and iGPU laptop are needed before the public Play release (M6) |
| Application ID | `io.github.aswinkumarks.ionfall` |
| Repository / CI | https://github.com/aswinkumarks/IONFALL (GitHub Actions for CI and export builds) |
| Visual identity | Approved: white/gray station panels, ion-cyan accents, teams cyan vs orange + shape markers; logo = falling ion streak |

**Remaining:** name the second test device if one is available; trademark/name check for "IONFALL" before final store art.

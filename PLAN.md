# IONFALL: Project Plan

**Premise:** in orbit above a ruined Earth, the Ion Trials pit soldiers against each other in hard-light arenas aboard a research station. Combatants "fall" into each round as ion-charged teleports, which is also the in-game respawn effect.

**Plan status:** revision 5 (2026-10-23): the owner dropped all further dedicated-server work (M7: `server.cfg`, rotation, admin console, Manager, systemd/Docker), our own hosted servers (O1–O4), gamepad support and wall-run; the existing LAN dedicated server ships as is. Revision 4 (2026-10-22): M0–M4 done; internet play (player-hosted over Epic Online Services), the multiplayer lobby and the menu and touch-control redesigns were added after M4 (§6 "Post-M4"); M5 slimmed to what v1.0 needs (§3.5.2, §6). Revision 3 addressed both Codex reviews: the original findings (C1–C2, H1–H19, M1–M17, L1–L3) and the re-review findings (NH1–NH14, NM1–NM10, NL1–NL2). Numbers marked *(provisional)* are starting points that get measured and fixed during the vertical slice (M1). Milestones have no time estimates until M1 is finished (§6).

**Conventions:** all gameplay timings are defined in **integer ticks at 60 Hz**. Seconds shown next to them are derived for readability. Network conditions are always given as **RTT** (round-trip time).

---

## 1. Locked decisions

| Area | Decision |
|---|---|
| Engine | **Godot 4.7.2-stable**, pinned exactly (editor, export templates, addons, physics backend). Upgrade policy in §3.18 |
| Language | GDScript. C++ GDExtension only for (a) hot paths that profiling proves slow, or (b) required **transport dependencies** such as `webrtc-native` (§3.17) |
| Platforms | Android, Linux, Windows; cross-play in the same LAN match. A **web browser client** is a post-v1.0 target; the architecture is designed to keep it feasible, subject to a transport prototype (§3.20). **v1.0 does not depend on browser support** |
| Single-player | Bot matches on the multiplayer maps/modes |
| Modes | FFA (internal MVP) → TDM (v1.0) → CTF, Co-op Waves (post-v1.0) |
| Hosting | **Listen host**: PC up to 16 combatants on LAN and 8 online (raised from 8 after the 16-combatant host test, `docs/perf/host-caps.md`), phone up to 4 *(raised only after the phone-host test passes)*. **Dedicated server**: the desktop game run headless with `--server` (no separate download since 0.9.2), up to 16 combatants. "Combatants" counts humans + bots |
| Simulation | Authoritative **forward-simulated server** (the server never rolls back the world) + client prediction for the local player (§3.3). Changing this needs a formal architecture revision |
| Movement | Sprint, slide, double-jump, mantle (wall-run was dropped in revision 5). No portals/abilities. **Players block each other** (added after 0.9.1, §3.2: the server pushes overlapping players apart; clients predict it against the players they see) |
| Health | Shield + health, both regenerate (§2.2) |
| Weapons | Loadout (primary + sidearm + grenades) + power weapons at fixed map spots (§2.3) |
| Art | Stylized low-poly sci-fi with baked lighting; CC0-first assets under a written license policy (§4) |
| Test devices | **For now: the devices already on hand**: Xiaomi Mi 11X (Snapdragon 870 / Adreno 650, 120 Hz) + the dev Linux PC (+ a second device if available). A min-spec phone and an iGPU laptop are required before the public Play release (§3.10) |
| Distribution | PC builds + Android now; Google Play later (signed AAB built from M0 onward) |
| Persistence | Local profile: name, settings, stats, XP, cosmetic unlocks (§3.13) |
| Controls | Keyboard/mouse and touch (with aim assist). Gamepad is not planned (dropped in revision 5) |
| Language support | English at launch; localization-ready from the first UI (§3.16) |
| Perf targets | Defined per device, preset and combatant count as frame-time percentiles (§3.10) |

---

## 2. Gameplay design

### 2.1 Movement
Quake/Titanfall-inspired acceleration model. All values live in a `MovementConfig` resource and are part of the compatibility hash (§3.14).
- Walk ~6 m/s, sprint ~8.5 m/s (sprinting lowers the weapon, so you can't fire)
- **Slide**: sprint + crouch → speed boost that decays over 60 ticks and keeps momentum on slopes. Uses a low hitbox
- **Double jump**: second jump in the air with a small directional redirect
- **Mantle**: automatically climbs ledges up to ~1.8 m when holding forward + jump. Runs as a fixed-duration, tick-counted state with a server-validated target
- Limited air control, coyote time 6 ticks (100 ms), jump buffer 6 ticks
- Players block each other: each tick the server pushes overlapping living players apart, the one moving into the other taking the push (`SimWorld._separate_players`); a client predicts it against the remote players as rendered (`SimWorld.push_out_of`), so walking into someone standing still isn't corrected. The spawn system (§2.5) prevents stacking at spawn
- **Jump pads** (added after 0.9.1; Halcyon Spire and Vesper Foundry): a trigger zone on the floor (`JumpPads`, an Area3D on its own physics layer in the gameplay scene) throws a grounded player on a fixed arc to the pad's landing point, peaking 2.5 m above it. It's part of movement, so prediction and replays include it; bots get a one-way navigation link over each pad
- No wall-run or grapple (wall-run was dropped in revision 5)

### 2.2 Health / shield
| Stat | Value *(provisional)* |
|---|---|
| Shield | 100. Recharge starts **300 ticks (5 s)** after the last damage, at 10/s |
| Health | 100. Regen starts once the shield is full (so at least 5 s after the last damage), at 5/s |
| Damage order | Shield first; overflow carries into health in the same hit |
| Headshots | Multiplier applies **only to damage dealt to health**, except for *precision* weapons (Rail Sniper), whose multiplier also applies through shields |
| Regen interruption | Any damage (including self-damage) resets both timers |
| Feedback | Shield-break flash + sound, shield crackle on the character, low-health vignette (intensity setting, §3.16), recharge sound |

### 2.3 Combat & balance table
Effective HP = 200. Values are *(provisional)*; the table is generated from the `WeaponData` resources (the resources are the source of truth). **TTK** = time from the first shot (t = 0) to the killing hit, assuming every shot hits and there's no travel time. "Optimal" means body shots until the shield breaks, then headshots.

| Weapon | Slot | Timing (ticks) | Damage | HS mult | Mag / reserve | Reload | Shots to kill (body) | TTK body / optimal |
|---|---|---|---|---|---|---|---|---|
| Pulse Rifle | Primary | Auto, 6 between shots (600 RPM) | 18 | ×1.5 (health only) | 36 / 180 | 120 | 12 | 66 t = **1.10 s** / 54 t = **0.90 s** (6 body + 4 head) |
| Burst Rifle | Primary | 3-round burst, 3 between rounds, 20-tick cycle | 18 per round | ×2 (health only) | 36 / 144 | 132 | 4 bursts | 66 t = **1.10 s** / 46 t = **0.77 s** (2 body bursts + 3 head rounds) |
| Scatter Gun | Primary | Pump, 48 between shots | 10 pellets × 12 (≤ 5 m), falls off to 30% at 15 m | ×1 | 6 / 24 | 30 per shell | 2 point-blank | 48 t = **0.80 s** |
| Flux SMG | Primary | Auto, 4 between shots (900 RPM) | 13; full to 12 m, 45% from 30 m | ×1.5 (health only) | 45 / 225 | 105 | 16 | 60 t = **1.00 s** / 48 t = **0.80 s** (8 body + 5 head) |
| Mag Pistol | Sidearm | Semi, min 12 between shots | 25 | ×2 (health only) | 12 / 60 | 90 | 8 | 84 t = **1.40 s** / 60 t = **1.00 s** (4 body + 2 head) |
| Rail Sniper | Power | Bolt, 72 between shots | 110 | ×2 (**precision**, through shield) | 4 / 8 | 150 | 2 body / **1 head** | 72 t = **1.20 s** / instant |
| Arc Launcher | Power | Projectile 40 m/s, 60 between shots | 200 direct; splash ≤ 120, falls off to 0 at 4 m | — | 2 / 4 | 150 | 1 direct | — |
| Frag grenade | Grenade | Fuse 150 | ≤ 130, falls off to 0 at 5 m | — | 2 | — | — | — |
| Melee | — | Cooldown 54 | 70 front, 200 back | — | — | — | 3 front / 1 back | — |

- **Range falloff**: Pulse/Burst/Pistol deal full damage to 30 m, falling linearly to 70% at 60 m
- **Spread & recoil**: deterministic, seeded from the shot's action ID (§3.2)
- **Reload**: switching weapons cancels a reload. Sprinting allows the reload to continue. You can't fire until the reload finishes
- **Weapon switch**: 24 ticks to raise; power weapons 36 ticks
- **Friendly fire**: off by default in TDM and CTF, chosen with the bot count and difficulty on the Single Player screen or in the lobby (moved out of Settings after 0.9.1). **Self-damage** is on for explosives at 50%
- **Power weapons**: picking one up replaces your primary; your loadout primary drops and despawns after 1,200 ticks (20 s). If you die, the power weapon drops with its remaining ammo and despawns after 20 s. A spawn point's 60–120 s timer starts only when its previous instance no longer exists (never more than one instance per spot). The HUD doesn't show the timers (removed on request: players learn the spots)
- **Pickup contention**: the server resolves pickups in tick order; ties go to the player closest to the item
- **Taking items**: walking over a power weapon takes it unless you already hold one; any other swap (a dropped primary, a second power weapon) needs Interact. Walking over a weapon you carry tops up its reserve. Spot timers: Rail Sniper 120 s, Arc Launcher 90 s, grenades 20 s
- **Grenades**: 2 per life. Grenade pickups at fixed spots give +1 (cap 2)
- **Extensibility**: new *variants* of existing firing types (hitscan auto/burst/semi, pellet, projectile) need only data plus a model. A genuinely new mechanic needs a checklist: sim state, prediction, replication, hit validation, presentation, audio, bot usage, balance-table entry

### 2.4 Scoring & modes
Victory is decided by an explicit **score** value (a player's score in FFA, a team's in the team modes), not by a kill count.

| Rule | FFA (player score) | TDM (team score) |
|---|---|---|
| Win | Score reaches **25**, or highest score at 10 min | Team score reaches **50**, or highest at 10 min |
| Kill of an enemy | +1 | +1 team |
| Suicide | −1 | No team change; −1 to the player's personal score |
| Team kill (FF on) | — | −1 team; −1 to the offender's personal score |
| Ties at time limit | Sudden death: the next score change decides (max 2 min, then a draw) | same |

**Death attribution precedence** (applied in this order):
1. Killed by an enemy's weapon, grenade or melee → kill for that enemy
2. Killed by **your own** explosive → suicide, even if an enemy damaged you earlier
3. Environmental death (fall, hazard) and an enemy damaged you within 300 ticks (5 s) → kill for the **last** enemy who did damage
4. Otherwise → suicide

**Assist**: ≥ 40 damage within 300 ticks before an enemy's death, by someone other than the killer → assist (stat + XP only, no score).

**Capture the flag** (both maps; each has a base per team, `flag_bases()`):

| Rule | CTF |
|---|---|
| Win | **3 captures**, or the most at the time limit (ties: sudden death as above) |
| Take | Touch the enemy flag (at its base or on the ground) |
| Capture | Bring it to your own base **while your own flag is home**: +1 team, +5 personal |
| Carrier dies or leaves | The flag drops where they were. The owners touching it return it (+1 personal); otherwise it goes home after 1800 ticks (30 s) |
| Kills | +1 personal only (no team score) |

**Co-op waves** (humans on team 0 against bot waves on team 1, no friendly fire, no clock):

| Rule | Co-op waves |
|---|---|
| Waves | 10. The first comes after 8 s; wave *n* has 2 + (*n* − 1) bots, +1 per extra human, capped by the match size; one difficulty step harder every 3 waves |
| Wave bots | Hunt the nearest human; don't respawn (they leave 2 s after dying) |
| Falling | A fallen human waits for the end of the wave and comes back when it's cleared |
| Win / lose | Clear wave 10 to win; everyone down at once loses. The team score is the waves cleared |

### 2.5 Spawn system
- **Server-side spawn scoring** for each spawn point: + distance to nearest enemy, − enemy line of sight (1 raycast per enemy, cached per tick), − recent deaths nearby (last 5 s), − occupied (another player within 2 m). TDM adds a bonus near teammates and a penalty for the enemy half. Pick randomly among the top 3. **Fallback**: the least-bad point, never blocked
- **Respawn delay**: FFA 180 ticks (3 s), TDM 300 ticks (5 s)
- **Spawn protection**: 120 ticks of damage immunity with a visible shimmer. It is **cancelled** when the player fires, throws, melees or picks up a power weapon
- **Generations**: each new life increments `life_gen`. Each respawn **or teleport** increments `discontinuity_gen` (§3.3.4). Damage, projectiles and lag-compensated hits aimed at an earlier `life_gen` are discarded
- **Reset on spawn**: full shield/health, loadout re-issued (switching loadout applies on the next spawn), 2 grenades

### 2.6 Combat feedback & match UX
- **Kill feed**: server-authored, max 5 visible rows, entries expire after 6 s. Shows killer, weapon icon, victim, plus headshot/assist markers
- **Death summary + death cam**: 3 s camera looking at the killer from the death position, killer name, killer's remaining shield/health, damage dealt/taken
- **Respawn countdown**, loadout change during the countdown
- **Hit markers**: shown optimistically on the client, then confirmed by the server (unconfirmed markers fade differently); a distinct kill marker
- **Scoreboard**, end-of-match results (stats, XP gained)
- **Spectator mode**: single player can **Watch** a bots-only match from any combatant's eyes (click/tap/Space for the next player). Network matches already playing can be joined as a spectator (Join Game → "Watch games already playing", or `--join ADDR --spectate`): the HELLO carries a spectate flag; the server gives the spectator an id but no player, ignores its commands, and sends it the usual snapshots, in which every combatant is a remote entity. Spectators don't take combatant slots (up to 4 on top, `MAX_SPECTATORS`) and don't start a match on their own; lobby members always play. Snapshots don't carry ammo, so a watched player's magazine shows full and the respawn timer counts from when the death was seen

### 2.7 Bots
- Run **only on the server**. Each bot is a normal player entity driven by a `BotBrain` that **outputs the same `PlayerCommand` stream** a human produces (§3.2), so bots use the same movement, validation and replication code
- **Navigation**: baked navmesh. Navigation links are tagged with the **traversal capability** they need (`jump`, `double_jump`, `mantle`, `drop`, `pad`). When the bot reaches a link, a traversal action issues the matching inputs (e.g. jump at the edge, jump again at apex). Godot's links only describe connectivity; our code performs the move
- **Stuck recovery**: no progress for 90 ticks → jump, then sidestep, then re-path, then teleport to the nearest navmesh point (last resort, logged; increments `discontinuity_gen`)
- **Budget**: perception at 10 Hz, re-pathing ≤ 2 Hz, staggered across bots. Movement still runs at 60 Hz through commands. Server cost is counted in §3.10
- **Brain**: utility AI choosing between attack / chase / retreat-to-regen / grab power weapon / roam / objective
- **Aim**: reaction delay + tracking error + target-speed penalty. **No difficulty gets wallhacks or perfect aim.** Higher difficulties only reduce delay and error
- **Difficulties**: Normal in the internal MVP; Easy/Normal/Hard/Insane in v1.0
- **Presentation**: `[BOT]` tag in nameplates, scoreboard and kill feed
- **Stats & XP classification** is **per event**: kills/deaths/assists involving a bot go to the "vs bots" stats and give 50% XP; those involving humans go to "vs players". Match-completion and win bonuses are halved if fewer than 2 humans were in the match

---

## 3. Technical architecture

### 3.1 Code architecture: simulation vs presentation
Two layers, separated from **M0** onward (not retrofitted later):

| Layer | Contains | Runs on |
|---|---|---|
| **Simulation** | Player movement, weapon state, projectiles, damage, regen, spawns, mode rules, bots. Pure, tick-driven, no rendering/audio/UI references | Server (authoritative); client (prediction of the local player only) |
| **Presentation** | Meshes, animation, VFX, audio, HUD, camera smoothing, interpolation of remote entities | Clients only |

- Map scenes are split into a **gameplay scene** (collision, spawn points, pickup spots, navmesh) and a **presentation scene** (visual meshes, lights, lightmaps, audio). The dedicated server loads only the gameplay scene
- Presentation reacts to **simulation events** (shot fired, hit, death, footstep), each keyed by a unique **action/event ID** (§3.2). An ID seen before is ignored, so client replays never duplicate sounds or effects
- **Roles**: *Listen host* = server + local client in one process. The local client sends its commands through the same command path and validation as remote clients, and there is exactly **one authoritative simulation**. *Client* = presentation + local prediction. *Dedicated server* = simulation only

### 3.2 Simulation contract (what makes prediction replayable)
- **Fixed tick** of 60 Hz. Tick IDs are `uint32`. No simulation code reads frame delta time
- **Physics backend** (Godot Physics or Jolt) is chosen and pinned in M0. It is part of the compatibility hash (§3.14). Player movement collides with **static world geometry**; player-player collision is a separate server step, which a client predicts only approximately (against remote players as rendered), so a replay of the local player alone matches exactly only when nobody is bumped
- **`PlayerCommand`** (one per tick):
  - `tick`
  - `move` (2 × int8)
  - `view_yaw` / `view_pitch` (quantized 16-bit)
  - `held` bitfield: fire (for automatic weapons), sprint, crouch, aim
  - **Press counters** (uint8, wrap-around) for one-shot actions: **fire** (semi-auto shots and burst starts), jump, reload, switch, grenade, melee, interact
  - `weapon_slot`
  - `view_tick` (fractional) and `interp_ticks` for lag compensation (§3.3.4)
- **Press-counter rules**:
  - The server compares each counter with the last value it processed. The difference is the number of new presses
  - **At most one execution per action type per tick**. Extra pending presses carry over to the following ticks
  - Deltas are capped at 2. Anything above that is discarded and counted as an anomaly
  - A press first seen in a command that arrived late (its tick already passed) executes on the **next processed tick**, if it's at most 9 ticks (150 ms) old. Older presses are dropped
- **Guarantee (tested)**: with commands sent as the last 4 per packet (§3.3.2), up to **3 consecutive lost packets lose no actions**. Longer outages may drop actions. The tests in §5 verify this bound. There's no "never lost" promise
- **`PlayerSimState`** (everything the replay needs): position, velocity, movement state enum, all state timers (ticks), jumps remaining, coyote and jump-buffer counters, stance, mantle target + progress, weapon slot, per-weapon {mag, reserve, cooldown ticks, reload ticks, burst counter}, grenade count, shield/health and regen timers, spawn-protection ticks, `life_gen`, `discontinuity_gen`, `action_seq`, last-processed press counters
- **Action IDs** (collision-free):
  - Each player entity has one **`action_seq`** (uint32) that increments for **every** shot, burst round, projectile, grenade and melee, across all weapons and lives
  - Action ID = `(entity_net_id, entity_gen, action_seq)`. `entity_gen` changes only when a new entity is created (new join), so IDs never repeat within a match. At 60 actions/s, a uint32 sequence won't wrap within any match
  - The same ID is used for predicted-projectile matching, spread/recoil seeds (`hash(match_id, action ID)`) and event de-duplication
- **Per-tick order** (identical on server and in client prediction): apply command → movement → mantle/slide state → weapon state machine → spawn shots/projectiles → advance projectiles → resolve damage → regen → mode rules → emit events
- **Reconciliation**: each snapshot carries the owner's full authoritative `PlayerSimState` for tick T. The client **restores that state at T** and **re-simulates its stored commands T+1 … now**. The visual difference is blended out (§3.3.4)
- **Prediction scope**: only the local player's movement, weapon state and cosmetic projectiles are predicted. Damage, kills and pickups are never predicted (only the optimistic hit marker is)
- **Determinism expectations**:
  - **Same build, same platform**: replay must reproduce the state **exactly** (CI test)
  - **Across platforms** (Android vs desktop, later WebAssembly): floating-point results may differ slightly, so the requirement is **bounded error**: ≤ 1 cm position difference after a 30-tick replay window
  - **Correction acceptance** at 100 ms RTT / 2% loss in normal play: visible corrections (> 5 cm) ≤ 1 per minute per player; snaps (> 1 m) never happen outside respawn/teleport

### 3.3 Netcode
#### 3.3.1 Model and the netfox decision
- **Required model**: forward-simulated authoritative server + client-side prediction/reconciliation for the local player + snapshot interpolation for remote entities + **hitbox-rewind lag compensation** for hitscan (Source/Overwatch style). **The server does not roll back the world.** Switching to server-side rollback would need a formal architecture revision (decision note + a re-plan of §3.3, §3.10 and §5). It is **not** an option inside the netfox evaluation
- **netfox evaluation in M1b**, limited to the components that fit the required model: `NetworkTime` / tick loop (clock sync, fixed tick) and its client-prediction helpers. Its server-side rollback (`RollbackSynchronizer` resimulating on the server) is out of scope. netfox is adopted only if:
  1. It supports mantle, slide, crouch hitboxes and projectile spawning without desync over 10 min at 100 ms RTT / 2% loss, within the correction limits in §3.2
  2. It runs headless and on Android
  3. It works without server rollback
  4. The phone-host CPU cost fits the budget in §3.10
  5. **Transport-API inspection**: it uses only the generic `MultiplayerPeer` / RPC API with no ENet-specific assumptions. This is a code inspection in M1b; the real multi-transport proof comes later in the transport prototype (§3.20)
  6. **RPC audit**: every RPC the addon registers is listed and checked against the client-callable whitelist in §3.7, so the addon opens no unreviewed client-callable paths
- Otherwise the custom implementation below is built (budgeted separately in the M1 estimate). The choice is recorded in `docs/decisions/`
- Transport: `ENetMultiplayerPeer` behind our own `Net` layer, so gameplay never calls ENet directly

#### 3.3.2 Clock sync & commands
- **Clock domains**: the *server tick* is the authoritative time. The client keeps an *estimated server time* (from clock sync) and a *prediction tick*, which runs ahead of the estimate by `RTT/2 + command buffer`, so commands arrive just in time. Messages always say which domain a time value is in
- **Clock sync**: ping/pong every 1 s carrying the server tick; RTT and offset are smoothed (median of the last 8 samples)
- **Sending**: the client sends one packet per tick containing the **last 4 commands** (redundancy) plus `ack_snapshot_id`. Over a WebSocket transport it sends at 30 Hz without redundancy instead (§3.20)
- **Server command queue** per client:
  - Target buffer of 2 ticks
  - Duplicates (an already-processed tick) are dropped
  - Commands for ticks already simulated are dropped, but **their new presses still count** (late-press rule, §3.2)
  - Commands more than 8 ticks in the future are dropped and counted
  - **Missing command**: the server repeats the last held state with **no** new presses for at most **6 ticks**. After that it applies a **neutral command** (no movement, no fire) until real commands resume
  - **Time abuse**: the server consumes at most one command per tick per client, so clients cannot gain extra simulation time. If a client's buffer stays too full or empty, the server tells it to run its tick clock 2% faster or slower (time dilation) instead of hard-resyncing

#### 3.3.3 Snapshots & events
- Snapshots are sent at 30 Hz (every 2nd tick), with `snapshot_id = server tick`
- **Per-entity baselines**: each entity in a snapshot is delta-encoded against the last **acked** snapshot that **contained that entity**. An ack of snapshot S confirms exactly the entities and events S contained. A full entity state is sent if the entity has no acked baseline, its baseline is older than 32 snapshots, or after join/map change
- **Prioritization without starvation**: if a snapshot would exceed the packet budget (§3.3.5), entities are sent by priority (distance, visibility, relevance). Every skipped entity's priority grows each snapshot, so each entity is guaranteed an update at least **every 4th snapshot**. The owner's own state is always included
- Entities have `net_id` + `entity_gen` (a reused `net_id` with a new generation is a new entity; stale ones are dropped)
- **Gameplay events** (kill, hit confirm, pickup, spawn, power-weapon timer) are tick-stamped, carried inside snapshots, and **repeated until a snapshot containing them is acked**
  - Bounded: ≤ 8 events per snapshot and ≤ 32 unacked events per client
  - On overflow, cosmetic events (hit confirms) are dropped first. **Critical events** (kills, score changes) move to the reliable control channel so they're never lost
- **Channels** (logical): 0 = unreliable (commands, snapshots); 1 = reliable ordered (match control, transitions, join/leave); 2 = reliable ordered (chat). Chat can never block game control. Transport mappings are in §3.20
- **Epochs**: every message carries the `match_id` (§3.4). Messages for a different `match_id` are dropped. Packets with an older `snapshot_id` than the newest applied are dropped
- **Join in progress**: full snapshot + current match state + all active timers on the control channel; the client acks once it is loaded (§3.4)
- **Quantization** (map-relative fixed point): position 1 mm (3 × int24, ±8.3 km range), velocity 1 cm/s (3 × int16), yaw/pitch 16-bit each, health/shield 8-bit each

#### 3.3.4 Interpolation & lag compensation
- **Remote entities** are rendered at `estimated_server_time − interp_delay`. `interp_delay` = 2 snapshot intervals (4 ticks ≈ 67 ms) + jitter margin, adaptive within **3–9 ticks (50–150 ms)**. The client reports its current value as `interp_ticks` in every command
  - **Underrun**: extrapolate for up to 6 ticks (100 ms), then hold the last state. Interpolation never crosses a `discontinuity_gen` change (respawn/teleport): it snaps instead
  - This snapshot interpolation is the only smoothing for remote entities; Godot physics interpolation is **off** for remote proxies, so smoothing is never applied twice
- **Local player**: the predicted state is rendered with sub-tick interpolation for high-refresh displays. Reconciliation differences are blended out visually over 6 ticks, or snapped if > 1 m
- **Camera look** is applied every render frame (120 Hz phone / 144+ Hz PC) from the latest input, independent of the 60 Hz simulation; the next command carries the latest angles
- **Lag compensation (hitscan only)**:
  - Each command includes `view_tick`: the estimated server time the client was rendering remotes at, in ticks (fractional)
  - The server computes the **expected view tick** from what it knows: `expected = server_tick_at_execution − (measured_one_way_latency + server_known_interp_ticks)`, where `interp_ticks` is clamped to 3–9
  - If the client's `view_tick` is within **±2 ticks** of the expected value, it's used. Otherwise the server **rejects the client's timestamp**, uses the expected value instead, and counts an anomaly (repeated anomalies are logged/flagged). A client therefore can't pick an older, more favorable moment
  - Total rewind is capped at **15 ticks (250 ms)**. Beyond that, the shooter has to lead the target
  - **Hitbox history**: ring buffer of 30 ticks per player, storing position, stance (stand/crouch/slide hitbox sets), aim pitch, alive flag, `life_gen` and `discontinuity_gen`
  - The server rewinds **only player hitboxes**. World geometry is static, so obstruction is checked against the current world. No rewind across a `discontinuity_gen` change (respawn or teleport): the target is treated as missing at that time
  - **Listen host fairness**: the host's local client renders remotes with the same interpolation delay and uses the same lag-compensation path. The host's remaining advantage (0 RTT) is accepted and documented
- **Projectiles** (rockets, grenades) are **not** lag-compensated. The server spawns them at the command tick; the client spawns a predicted cosmetic copy with the same action ID, which is replaced by the server's copy when it arrives

#### 3.3.5 Wire layout & bandwidth budget *(provisional; measured in M1b)*
The worksheet separates **application bytes** (our payload) from **on-wire bytes** (≈ 40 bytes of IPv4 + UDP + ENet overhead per packet, more with DTLS or IPv6). The authoritative version lives in `docs/net/wire-layout.md` and is updated from measurements.

**Downstream: one snapshot**

| Part | Bytes |
|---|---|
| Header: `snapshot_id` 4, `match_id` 4, `phase_seq` 1, acked command tick 4, flags/counts 3 | 16 |
| Remote player, full: `net_id` 2, `entity_gen` 1, position 9, velocity 6, yaw/pitch 4, state/stance flags 2, health/shield 2, weapon 1, `discontinuity_gen` 1 | 28 |
| Remote player, typical delta: field mask 2 + position, velocity, angles | ~21 |
| Owner's own full `PlayerSimState` (for reconciliation) | ~48 |
| Event | ~12 each, ≤ 8 per snapshot |
| Projectile entity | ~16 each |

| Snapshot case (16 combatants) | Application bytes | Per client at 30 Hz (on-wire) |
|---|---|---|
| Typical (15 remote deltas + owner + 2 events + 4 projectiles) | ~460 | ~15 kB/s |
| Worst full (15 full + owner + 8 events + 24 projectiles) | ~1,000 | ~31 kB/s (only during recovery) |
| Above 1,000 bytes (more than 24 projectiles, etc.) | split by priority over the following snapshots (§3.3.3) | ≤ 33 kB/s |

**Upstream: one command packet**

| Part | Bytes |
|---|---|
| Header: `match_id` 4, base tick 4, `ack_snapshot_id` 4, `interp_ticks` 1 | 13 |
| One command: move 2, angles 4, held 1, 7 press counters 7, slot 1, `view_tick` 3 | 18 |
| Packet with 4 commands | ~85 → at 60 packets/s ≈ 5.1 kB/s application, **≈ 7.5 kB/s on-wire** |

**Budgets:**
| Item | Budget |
|---|---|
| Max UDP payload per packet | 1,100 bytes |
| Client downstream (on-wire) | typical ≤ 16 kB/s; worst ≤ 33 kB/s |
| Client upstream (on-wire) | ≤ 8 kB/s |
| Server outbound, 16 clients (on-wire) | typical ≈ 240 kB/s (1.9 Mbit/s); worst ≈ 530 kB/s (4.2 Mbit/s) |
| Live projectiles per match | above 24, the oldest/farthest are prioritized out of single snapshots, never removed from the simulation |

The net graph (bytes/s, packets/s, loss, corrections/min, snapshot size max/p99) is in the debug overlay from M1b.

### 3.4 Match state machine & connection lifecycle
**Two separate identifiers:**
- **`match_id`** (uint32, random): a stable epoch for one whole match, from LOADING through POST_MATCH. It changes only when a new match or map starts. Commands, snapshots, events and final results all belong to a `match_id`
- **`phase_seq`** (uint8): increments on every phase transition **within** a match. It never invalidates commands or events. The server decides what each phase allows (e.g. no damage in COUNTDOWN)

```
LOBBY ──start──▶ LOADING ──all acked / 30 s timeout──▶ COUNTDOWN (5 s) ──▶ PLAYING ──score/time──▶ POST_MATCH (15 s) ──▶ next match (new match_id) or LOBBY
```
- **Transitions** are sent on the reliable control channel as `{match_id, phase_seq, phase, server_tick, ends_tick, match_seed}` (the seed since protocol 9: a rematch gets a new spread seed, and clients need it to predict shots), and clients ack them. A client that missed transitions (e.g. after reconnecting) gets the current phase in the join/resync message
- **Kills and events at the boundary**: anything that happened at or before the tick of the PLAYING → POST_MATCH transition counts toward that match's result. Damage stops at that tick
- **LOBBY**: join, choose team (TDM, with auto-balance) and loadout. No damage
- **LOADING**: the server sends `{map_id, mode, match_id, compat_hash}`. Clients load and ack. Clients that don't ack within 30 s return to the lobby with a reason. A wrong `compat_hash` is rejected before loading (§3.14)
- **Warmup**: none in v1.0 (removed to keep the state machine small). Players and bots can move during COUNTDOWN, so at COUNTDOWN → PLAYING everyone respawns at a fresh spawn point with spawn protection (added after 0.9.1: bots used to start the match mid-fight next to you)
- **Late join** during PLAYING is allowed: load → ack → full snapshot → spawn. In TDM the player joins the smaller team
- **Reconnect**: within 60 s, a client presenting its `reconnect_token` (issued at join) gets its score, team and stats back. After that, it is treated as a new join
- **Disconnect cleanup**: the player entity is removed. Projectiles/grenades it already fired still resolve, and kills are credited. Held power weapons drop. Bots may backfill the slot (if enabled)
- **Match end**: the server sends final results with a `match_result_id` on the control channel. Clients save them atomically (§3.13)

### 3.5 Hosting
#### 3.5.1 Listen host
- "Host Game" from the menu. Single-player bot matches are a listen host with networking disabled
- **PC host**: up to **16 combatants on LAN** (`docs/perf/host-caps.md`: 21 minutes at 60 fps on the Iris Xe laptop on Medium, tick p99 ≤ 5.6 ms), **8 online** until 16 is measured through the EOS relays
- **Phone host**: up to **4 combatants by default** *(provisional)*. It is raised to 8 only after the Mi 11X passes a 20-minute host test meeting the §3.10 targets
- **Lifecycle** (Android, and later browser tabs). The OS can suspend or kill the app without notice, so these are **best-effort** behaviors, not guarantees:
  - **User-initiated exit** (Leave/Quit button, back gesture in a match): a confirmation dialog warns "Leaving ends the match" (host) or "You'll leave the match" (client)
  - **Backgrounding, calls or screen lock**: on the pause notification, the host makes a best-effort attempt to tell clients it paused and checkpoints its own results. If the app resumes before clients time out, the match continues
  - **Clients detect host loss themselves**: no server packets for 3 s → "Host not responding"; 10 s → "Host disconnected", back to the menu
  - **Partial results**: clients keep a local tally of the match. If no final results arrive, the tally is saved and marked **unconfirmed** (XP for time played and kills only)
  - **Client-side suspension**: the server times the client out after 10 s; the client can reconnect within 60 s (§3.4)
  - **Wi-Fi change/loss**: back to the menu with a clear reason
- **No host migration**

#### 3.5.2 Dedicated server
**v1.0 scope (revision 4):** players host their own matches on LAN and over the internet (§3.8), so the dedicated server ships in v1.0 as the **exported command-line server that exists today** (`server/server_main.gd`: `--port --name --map --mode --bots --bot-difficulty --friendly-fire --no-discovery`, status lines on stderr, LAN beacons), plus graceful shutdown. Each match restarts on the same map and mode. **Revision 5: no further dedicated-server work is planned.** **After 0.9.1** the owner dropped the separate server downloads: releases ship only the game, and `--server` runs the same server from the Linux or Windows game build (`docs/server.md`); CI smoke-tests the exported Linux game that way on every map and mode. The rest of this section (`server.cfg`, rotation, standalone/managed modes, admin console, rotating logs, systemd/Docker) is kept only as a record of the earlier design.

- **Detection**: server mode starts when the build has the `dedicated_server` feature tag, or when the user argument `--server` is passed after `--`. `--headless` alone does not select server logic
- **Launch**: `ionfall_server --headless -- --server --config server.cfg [--port N --name X --max-combatants N --map M --mode M]`
- **Export** *(superseded after 0.9.1: no server presets, the game build runs `--server`)*: Godot *dedicated server* export presets for Linux x86_64 and Windows (Linux arm64 is a stretch goal). Visual resources use **Strip Visuals** placeholders. Audio and presentation are kept out of the server by the gameplay/presentation scene split (§3.1) rather than relying on automatic stripping. The **exported** server is tested with every map, weapon and mode, not just the editor in headless mode
- **`server.cfg`**: name, port, max combatants (2–16), password, map/mode rotation, score/time limits, bot fill (count + difficulty), team balance, idle kick. The tick rate is **fixed at 60** (not configurable in v1.0)
- **Two run modes**:
  - `--standalone`: loops through the rotation by itself; idles at near-0% CPU with no humans connected (bots paused)
  - `--managed`: runs **one match**, then exits; controlled by the Manager (§3.5.3)
- **Output**: logs → stderr + rotating log file. In managed mode, stdout carries **only versioned JSON lines** (§3.5.3)
- **Admin (v1.0)**: **local only**. The stdin console on the dedicated server and the host's own UI on a listen host offer `status, kick, ban, map, mode, bots, restart, say`. **Remote admin over the network is disabled** until it runs over an encrypted, authenticated transport (after O1, §3.8)
- **Profiles**: clients keep their own profiles. The server stores only its config, ban list (by IP + self-declared UUID; host-trust only, §3.7) and logs
- Operations: graceful shutdown on SIGTERM/Ctrl+C; Windows `.bat` launcher. systemd unit and Docker image come post-v1.0

#### 3.5.3 Central multi-match server (Manager), LAN first
*Dropped in revision 5 (with M7); kept as a record of the design.*

- One **Manager** process (`--manager`) plus one `--managed` match process per match, each on its own port from the pool (§3.6)
- **Client flow**: the server browser shows the Manager as one entry → its match list → *Join* or *Create* → the Manager returns an **endpoint description** `{server_id, match_id, transports: [{type: "enet", host, port}, …]}` → the client connects directly to the match. Gameplay traffic never goes through the Manager. (Browser transports add entries here later, §3.20)
- **Port allocation**: from the pool, skipping reserved ports (§3.6). If binding fails, the port is marked bad for 10 min and the next one is tried. Allocator tests cover reserved-port exclusion and failed binds
- **Manager ↔ match protocol** (JSON lines, `"v":1`):
  - The match sends `hello{proto, pid, port}` → Manager `ack` → match loads → `ready`
  - `heartbeat` every 1 s; 5 missed heartbeats → the Manager kills and restarts the match
  - Commands carry an `id`; the match replies with `result{id, ok, error}`
  - Startup timeout 20 s. Restart backoff 1, 2, 4 … 60 s, at most 5 restarts per 10 min per playlist slot
  - On exit the Manager reaps the process and returns the port to the pool
  - **Manager lost** (stdin EOF): the match finishes its current match (max 15 min), sends results to clients, then exits
- **Manager duties**: on-demand matches + persistent playlists from `manager.cfg`, health watching, idle shutdown, local admin console covering all matches
- **Capacity**: matches are admitted by **measured headroom** (keep ≥ 25% CPU and ≥ 1 GB RAM free; reject new matches while any match's tick p99 is above budget), not by core count. The density estimate (~6–8 matches on 8 cores, 150–300 MB each) is *provisional* until the M7 benchmark

### 3.6 Discovery & ports
| Port (UDP) | Use |
|---|---|
| 47700 | Manager request/response |
| 47701 | LAN discovery beacons |
| 47710 | Default game port (listen host / standalone server) |
| 47711–47799 | Manager match pool (contains no other reserved port) |

- **Beacon** (≤ 512 bytes, binary): magic, beacon version, build ID, protocol version, compat-hash prefix, name, mode, map, combatants/max, flags (dedicated / manager / password), game port
- Sent every 1 s with `set_broadcast_enabled(true)`, both to `255.255.255.255` and to each interface's directed broadcast address (this covers phone hotspots and PCs with several network adapters). The advertised endpoint is the address of the interface the beacon left from
- **Client**: entries expire after 3.5 s. Parsing is bounded and rejects bad magic, oversize packets or invalid fields
- **Android**: `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`. A multicast lock is held **only** while the server browser is open or while hosting. Newer Android versions add a runtime **local-network permission** (`ACCESS_LOCAL_NETWORK`, reported for target SDK 37+; *to be verified* when that target becomes required). The UI must handle the permission being denied
- **Fallbacks**: manual IP:port entry and **join links** (`ionfall://join?host=…&port=…`; on the web, `?join=host:port`). Discovery is always optional, and every join path works without it. The host shows its IP and (from M3) a **QR join code**. Manual IP works only when routing and firewalls allow it: AP/client isolation, guest Wi-Fi and different subnets without routing will block it, and the UI says so on failure
- **Test matrix**: home router, phone hotspot (phone as host and as client), AP isolation on, PC with Ethernet + Wi-Fi, permission denied, firewall prompts on Windows

### 3.7 Security (LAN threat model)
**Trust levels:** the server trusts no client. Clients trust their host, and a listen host *can* cheat; LAN stats and bans are therefore **host-trust features**. A self-generated player UUID is a label, not an identity.

**Accepted risk (stated explicitly):** on a LAN in v1.0, traffic is **unencrypted**. Someone on the same network can passively read gameplay data, names and chat. That is accepted for LAN play. Because of it, nothing sensitive goes over the LAN: there is **no remote admin** and no passwords other than the optional match password, which only keeps casual players out.

**Validation rules (from M1b):**
- **Ingress limits before decoding**: the `Net` layer counts packets and bytes per peer **before** any parsing. Per peer: ≤ 120 packets/s and ≤ 16 kB/s inbound. Excess packets are dropped unparsed; 5 s of sustained violation → disconnect + log
- **Sender ownership**: every client→server RPC checks `get_remote_sender_id()` against the entity it touches. Only a whitelist of client entry points is callable by clients (`command`, `ack`, `chat`, `lobby_request`). Everything else is server→client only. Addon RPCs are audited against this list (§3.3.1)
- **Bounded values**: floats must be finite and within range, enums in range, slots valid, press-counter deltas ≤ 2, `view_tick` checked as in §3.3.4, angle change per tick capped (anti-spinbot sanity check)
- **Size and rate limits**: command packet ≤ 256 bytes; chat ≤ 140 characters, 1 message/s (burst 3); names 3–16 graphemes, Unicode NFC-normalized, control characters stripped; lobby requests ≤ 5/s
- **Gameplay checks**: fire rate, ammo, reload, cooldowns, movement speed per state, mantle target validity, pickup distance
- **Connections**: handshake timeout 5 s, max 4 pending connections per IP, connection-rate limit per IP, malformed packets → disconnect + log
- **Fuzz tests** for all client entry points (§5)

### 3.8 Internet path (after LAN v1.0)
**Update (2026-10-22, decision 0005):** internet play ships first as **player-hosted matches over Epic Online Services P2P** (invite codes, anonymous device-ID login, Epic relays; Linux, Windows, Android), with no game server of ours; see `docs/online.md`. WebRTC follows for the web build. The phases below were the plan for hosted servers and trusted online progression; **revision 5 drops them**, since the owner doesn't plan to run game servers. They stay as a record.

**Rule: no internet exposure until O1 is complete.** Accounts, encryption and baseline hardening ship together, so a login token is never sent over an unencrypted connection.

| Phase | Content |
|---|---|
| **O1 Secure identity & transport** | Accounts backend (HTTPS REST, e.g. Go/Node + PostgreSQL). **Account deletion** ships with account creation: an in-app deletion path plus an external web request page, with the disclosures Play requires. **Short-lived, match-scoped join tickets** (signed; contain account ID, match ID, server ID, expiry ≤ 60 s, nonce; replay-checked by the match server). **DTLS** on client↔match and client↔Manager connections, via explicit `ENetConnection` DTLS setup, certificate validation and hostname checks, with per-server credentials. If DTLS or the ticket check fails, the join is refused with a clear error. Baseline hardening (§3.7 limits) required. Remote admin becomes possible over this transport |
| **O2 Hosted servers** | **Public dedicated servers only** (no internet player-hosting at first). Managers on VPS nodes register with the backend. Join responses carry the endpoint description (§3.5.3) with hostnames. Documented firewall port ranges; IPv4 + IPv6 |
| **O3 Trusted progression** | Online stats/XP/unlocks stored on the backend in a separate profile namespace from LAN profiles. Results are accepted **only from registered, trusted servers** and applied idempotently by `match_result_id` |
| **O4 Matchmaking & operations** | Mode/region queue, reporting, account bans, chat moderation obligations, Play Data Safety update |
| ~~Later: internet player-hosting via NAT traversal or a relay~~ | **Done early** with EOS P2P (decision 0005): NAT traversal and Epic relays, lobbies, invite codes |

**DTLS prototype**: a small DTLS spike runs at the start of O1 (moved from M5 in revision 4: EOS P2P is already encrypted, so DTLS is only needed for our own hosted servers).

**Internet-ready rules from day one:** player UUID + per-match result records with `match_result_id`; a join handshake with `protocol_version, build_id, compat_hash, player_uuid, auth_ticket` (ticket empty on LAN); server never trusts the client (§3.7); all networking goes through the `Net` layer; netcode is tested at 50–150 ms RTT with jitter and loss.

### 3.9 Rendering & lighting pipeline
- **Renderers**:
  - **Mobile renderer (Vulkan)** is the reference on Android and the default on PC. One shared art target, **validated per platform**
  - **Forward+ "High" preset** on PC adds SSAO, SSR, volumetric fog and FSR2
  - **Compatibility renderer** (WebGL 2 / GLES3) is used only by the future web client and a possible non-Vulkan Android preset (§3.20)
- **Resolution scaling**: the Mobile renderer gets **bilinear** render-scale only, since FSR1/FSR2 are Forward+ only. Forward+ offers FSR2
- **Lightmap filtering**: bicubic lightmap sampling is **off on mobile** (`use_bicubic_filter.mobile = false`); on the Mi 11X it cost ~3.3 ms GPU (M1c)
- **Non-Vulkan Android devices are excluded** in v1.0, filtered via a required-Vulkan `uses-feature` in the manifest
- **Used on Mobile**: LightmapGI, glow, height/depth fog, decals, ReflectionProbes, tonemapping, per-map color grading LUT. **Not used on Mobile**: SSAO, SSR, volumetric fog
- **Lighting configuration** (per light):
  - **Interior/accent lights** (omni/spot, emissive): bake mode **Static**. Fully baked direct + indirect, no realtime cost
  - **Sun/key directional light**: bake mode **Dynamic**. Indirect light is baked; direct light and shadows are realtime, so characters get direct light and cast shadows onto the baked floor. Shadows ≤ 30 m, 2 cascades; casters = characters and pickups. Static geometry's sun shadows come from the LightmapGI **shadowmask** (`shadowmask_mode = Overlay`), and static meshes use `cast_shadow = Off` so they stay out of the realtime shadow pass. *(Validated in M1c: a Dynamic light alone bakes only indirect light, so without the shadowmask static geometry would need realtime shadows; see `docs/perf/m1c-platform.md`.)* Off in the Low preset, which uses blob shadows
  - **Dynamic objects** (players, pickups, projectiles) get **indirect** light from the LightmapGI probe grid plus **direct** light from the sun. Maps are designed so play spaces receive the key light (station domes, windows, hard-light skylights). Areas without it get a placed Dynamic fill light only if testing shows characters look flat there
  - **Validation before art production** (M1c/M2): this setup is tested on the real baked floor on the Mi 11X: character shadows on baked surfaces, no double shadows, correct character brightness, cost of the shadow pass
- **Lightmap pipeline**:
  1. Greybox in CSG → **convert to meshes** before baking
  2. Generate **UV2** (Godot's lightmap UV2 import option or a Blender unwrap). Triplanar materials remove the need for *UV1* texturing work, not the need for UV2
  3. Texel size per map *(provisional 0.2 m; 0.1 m on hero surfaces)*
  4. **Lightmap budget per map: ≤ 32 MiB of measured GPU memory**, mipmaps included. The atlas format is fixed after measuring what Godot 4.7 uses for lightmaps on the Mobile renderer (in M1c). For reference: one uncompressed RGBA8 2048² page is 16 MiB (~21 MiB with mips), so uncompressed allows only 1 page, while a ~4:1 compressed format allows several. The page count follows from the measured format, not the other way round
  5. Bake on the dev PC; bakes are committed via Git LFS. Whoever changes level geometry rebakes (part of the map checklist)
  6. **ReflectionProbes** use update mode *Once* (baked at load)
  7. On-device check of every bake on the Mi 11X (and the min-spec phone once available)
- **Shaders**: triplanar panel material, hologram, shield crackle, hard-light surfaces. Each custom shader is written with a Compatibility-safe variant or fallback (§3.20). **Shader warm-up**: a warm-up pass at map load renders every material/VFX variant off-screen, plus the engine's pipeline pre-compilation where 4.7 provides it. Cold-start stutter is tested (§5)

### 3.10 Performance budgets & test devices *(all provisional until M1 measurements)*
**How targets are measured:** as **frame-time percentiles** over a 20-minute sustained window on **release exports**, after the device reaches thermal steady state. "p95 ≤ 16.7 ms" means 95% of frames take at most 16.7 ms (60 fps). Every target also requires **no 1-minute window averaging below 90% of the target fps**.

| Device | Preset / resolution | Scenario | Target |
|---|---|---|---|
| Mi 11X (client) | Medium, render scale 0.6 of 2400×1080 (adaptive down to 0.5) | 8 combatants, in combat | p95 ≤ 25 ms (40 fps), p99 ≤ 33.3 ms *(revised in M4)* |
| Mi 11X (client) | Low, 0.6 (adaptive down to 0.5) | **16 combatants** (dedicated server), in combat | p95 ≤ 25 ms (40 fps), p99 ≤ 33.3 ms *(revised in M4)* |
| Mi 11X (phone host) | Medium, 0.6 | **4 combatants (final, M4)** | p95 ≤ 18.2 ms (55 fps), server tick p99 ≤ 4 ms |
| Intel Iris Xe laptop (PC host, *verified 2026-10-24*, `docs/perf/host-caps.md`) | Medium, 1080p | **16 combatants** (LAN cap) | p95 ≤ 16.7 ms, server tick p99 ≤ 6 ms: met (20 of 21 minutes at 16.7, tick p99 ≤ 5.6) |
| Min-spec Android (*deferred, unverified*) | Low, 0.6 | 8 combatants (16 also supported on Low, unverified) | p95 ≤ 33.3 ms (30 fps); stretch 22.2 ms (45 fps) |
| Intel Iris Xe laptop (*verified in M6*, `docs/perf/m6.md`; AMD Vega 8 unverified) | Medium, 1080p | 8 combatants (16 on Low) | p95 ≤ 16.7 ms: met (also on High) |
| Dedicated GPU PC (*deferred to M6: none on hand in M4*) | High (Forward+), 1080p–1440p | 16 combatants | p95 ≤ 6.9 ms (144 fps) |
| Dedicated server (reference: 4-core desktop CPU, recorded in `docs/perf/`) | — | 16 combatants incl. bots | tick p50 ≤ 2 ms, p99 ≤ 6 ms, ≤ 300 MB RSS |

**M4 revision of the Mi 11X client targets** (docs/perf/m4.md): the original p95 ≤ 16.7 ms is met in quiet play and for the first minutes of a fight on a cool phone, but not over 20 minutes of combat. There the GPU stays inside its 12 ms budget, while main-thread work and MIUI's unreported thermal slowdown hold frames at 17–25 ms (p95). The measured 20-minute combat soaks sit at p95 ≈ 18–25 ms with single bad minutes; the revised target is what the phone sustains. Getting back to 60 fps in combat (on-device CPU profiling, animation LOD for distant characters) is later performance work, not an M4 gate. An 8-combatant phone host failed (p95 ≈ 26 ms, tick p99 up to 5 ms), so phone hosts stay at 4.

The Mi 11X at lower render scale only tests **scalable GPU settings**. It doesn't simulate a weaker phone's CPU, memory bandwidth, drivers or thermals. **Current decision:** test only on devices already on hand for now. Min-spec and iGPU targets stay documented but *unverified*, and the store listing / README makes no claims about them until a real low-end phone and an iGPU machine have been tested (required before the public Play release in M6).

**Frame budget (16.67 ms at 60 fps), mobile:** main thread ≤ 8 ms (sim + prediction replay ≤ 2 ms, bots/server on host ≤ 3 ms), render thread ≤ 6 ms, GPU ≤ 12 ms (leaves thermal headroom).

**Content budgets (mobile Medium)**, each with how it's measured:
| Item | Budget | Measured with |
|---|---|---|
| Draw calls | ≤ 250 | Godot `RENDER_TOTAL_DRAW_CALLS_IN_FRAME` monitor, worst map spot |
| Visible primitives | ≤ 300k triangles | `RENDER_TOTAL_PRIMITIVES_IN_FRAME` monitor |
| Shadowed lights | 1 directional (Dynamic sun, characters/pickups as casters); unshadowed dynamic omni lights ≤ 4 at once, short-lived | Scene review + light-count monitor |
| Textures | ≤ 1024², ETC2/ASTC, total texture memory ≤ 256 MiB | `RENDER_TEXTURE_MEM_USED` monitor |
| Lightmaps | ≤ 32 MiB per map (§3.9) | Same monitor, map with/without lightmaps |
| Transparent overdraw | Worst on-screen spot ≤ 3 overlapping transparent layers; particle quads capped per effect | Editor overdraw debug view + GPU frame time on device |
| Particles | GPU, ≤ 2,000 live, per-effect caps | Particle counters in the debug overlay |
| Shader variants | ≤ 1 material per surface type in the shared library; screen-space effects only via presets | Material library review |
| Memory | App RSS ≤ 1.2 GB on Android | `dumpsys meminfo` / OS monitor |
| Physics | Simple convex/box collision for the world; ≤ 16 active ragdoll bodies | Physics monitors |

- **Scalable settings**: render scale, glow, shadows, particle density, decals, LOD bias, 30/60/90/120 fps cap
- **Thermals**: 20-minute sustained tests are mandatory. An automatic quality step-down when sustained frame time rises. Android thermal status and headroom are read through `AndroidRuntime` + `JavaClassWrapper` with no plugin; on the Mi 11X headroom is unsupported, the status stays 0 while MIUI throttles, and ADPF hint sessions are unsupported, so the step-down reacts to frame time (decision 0004)

### 3.11 Input, touch & aim assist
- **Input adapter layer**: device events (mouse, keyboard, touch) → normalized **`PlayerCommand`**. Gameplay never reads devices
- **Active input class** = the last-used device, which can switch live (e.g. a mouse plugged into an Android phone counts as KBM). It is reported to the server only as a label for the lobby
- **Touch layout**: floating left joystick (push to edge = sprint), right-side drag to look, buttons for fire, jump, crouch/slide, reload, swap, grenade, melee
  - **Finger ownership classes**: (1) the **move finger** (joystick); (2) **look fingers** (started on empty right-side space); (3) the **fire finger**, an explicit **combined fire + look** class: touching the fire button starts firing, and dragging that same finger also turns the camera; (4) **button fingers** for all other buttons, which are exclusive and never turn into look fingers
  - Respects **safe areas** (notches, rounded corners). Move, look and fire work at the same time; touch cancellation releases held actions
  - Fixed layout in the internal MVP; layout editor (position/size/opacity) in v1.0
- **Aim assist** (touch only):
  - **Candidate selection** (10 Hz, cached): targets within a cone of 6° *(provisional)* and the weapon's effective range, nearest to the crosshair weighted by distance
  - **Visibility is rechecked at the moment assist is applied** (1 ray per assisted frame, only while assist is active), so the cache can never make it aim through walls
  - **Slowdown**: look sensitivity × 0.6 while the crosshair is over the target
  - **Magnetism**: while firing, follows ≤ 25% of the target's angular velocity. No snapping
  - **Auto-fire** (optional setting): automatic/burst weapons fire 7 ticks (~120 ms) after the crosshair lands on a visible target (visibility rechecked at that moment); disabled for the sniper, launcher and grenades
- **Server sanity** applies to all inputs: maximum view rotation per tick and impossible aim snaps are logged/flagged
- **Input-based lobbies**: a lobby can declare "touch only" or "mixed". This is a declared preference and is **not** enforced as anti-cheat

### 3.12 Audio
- **Buses**: Master → Music, SFX (Weapons, Footsteps, World, UI), with separate volume sliders
- **Voices**: ≤ 32 total, per-category caps (e.g. 8 gunfire, 6 footsteps). Priority: nearby enemy gunfire/footsteps > own weapon > world > ambience
- **Occlusion v1**: for each audible gameplay sound, 1 ray from listener to source every 100 ms (≤ 16 rays per frame overall). Occluded sounds get −6 dB and a 2 kHz low-pass. Reverb and propagation are deferred
- **Footsteps** are driven by the movement state (walk/sprint/slide/land) with distinct enemy vs. friendly sounds. Vertical position comes from 3D panning plus a subtle up/down filter cue
- Sounds come from simulation events, de-duplicated by action/event ID so prediction replays never double-play them (§3.1)
- **Dynamic range** setting: Full / Night (compressed)
- **Web fallback** (future web client): browsers use Godot's *Sample* playback by default, which doesn't support AudioEffects. The web client therefore uses **volume-only occlusion** (−6 dB, no low-pass) and implements the Night setting as a volume curve instead of a compressor. Godot's *Stream* playback mode is evaluated against its latency cost in the web milestone

### 3.13 Persistence: profile, stats, unlocks
- `user://profile.save` (versioned schema) and `user://settings.cfg`
- **Atomic writes**: write `*.tmp` → flush → rename. The previous file is kept as `*.bak`. If the main file fails to load or fails its checksum → use `*.bak` → else start a new profile and keep the corrupt file for diagnostics
- **Migrations**: every schema version has a migration function plus a test that loads a fixture save from each older version
- **Checksum** detects corruption only; it doesn't prove results are honest (LAN progression is local-trust)
- **Idempotent results**: each `match_result_id` is applied once. The last 200 applied IDs are stored
- **Unconfirmed results** (no final results from the host, §3.5.1) are stored with a flag and shown as such in the stats screen
- **Stats**: kills, deaths, assists, K/D, wins, matches, accuracy, headshots, per-weapon kills, longest streak, time played, split "vs players" / "vs bots" per event (§2.7)
- **XP formula** *(provisional)*: 10 per kill + 5 per assist + 1 per 10 s played + 100 per win + 30 per match completed; bot-related values halved as in §2.7
- **Incomplete matches** (quit or host left): XP for time played and kills, no win/completion bonus; stats recorded
- **Unlocks are cosmetic only** (armor colors/patterns, visors, weapon skins, emblems). LAN profiles and future online profiles stay in separate namespaces. v1.0 unlocks by level: characters (Vanguard 2, Operative 3) and armour colours (levels 2, 4, 6, 8); locked picks fall back to the defaults
- **Storage availability** (web, and any platform where writing fails): at startup the game test-writes `user://`. If storage is unavailable or not persistent (e.g. a private browser window), a banner warns "Your profile won't be saved". On the web, saves report success only after the browser storage sync completes

### 3.14 Versioning & compatibility
| Identifier | Example | Purpose |
|---|---|---|
| Release version | `0.4.2` (semver) | Shown to players |
| **Artifact ID** | `ionfall-0.4.2-android-arm64-release-ci1287+abc1234` | Unique per built file: version, platform, architecture, configuration, CI run number, git hash |
| Android `versionCode` | `major×1,000,000 + minor×10,000 + patch×100 + build` (minor, patch, build each 0–99) | Monotonic Play ordering, fits Android's limit |
| Protocol version | integer, bumped on any wire change | Network compatibility |
| **Compatibility hash** (`compat_hash`) | hash over: simulation and net scripts (`sim/`, `net/`, `modes/`, `bots/`), addons they use, physics settings and backend, `WeaponData`, `MovementConfig`, mode rules, maps' gameplay scenes and collision | Prevents playing with different simulation code or data |

- Joining requires an **equal protocol version and `compat_hash`**. Otherwise the error is clear, e.g. "Host runs 0.4.2 (abc1234), you have 0.4.1"
- `compat_hash` is computed from source files at export time, so it is the **same on every platform** for the same commit
- The build records engine version, export templates and addon revisions (netfox etc.) in `build_info.json`
- Debug symbols are kept for every release artifact (desktop + Android native libraries)

### 3.15 Diagnostics
- **In-game overlay** (F3 / three-finger tap): frame time (p50/p95/p99), CPU/GPU, render-thread time, server tick time, RTT, loss, net graph, corrections/min, snapshot size, thermal status
- **Local logs** in a ring buffer (last 3 sessions)
- **"Export diagnostics"** button: zips logs, `build_info.json`, device/GPU/driver info and recent perf stats for the user to share manually
- **No remote telemetry or crash-reporting SDK in v1.0.** If added later, the data, retention and opt-in get documented and the Play Data Safety form is updated *before* release. After the Play release, Android crashes/ANRs are visible in Play Console vitals

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
**Two reasons to use native code:**
1. **Performance**: move a system to GDExtension only when profiling on a release export shows it over budget (likely candidates: hitbox rewind, bot perception, snapshot encoding)
2. **Transport dependencies**: required functionality, not an optimization. The known case is **`webrtc-native`**, which native (desktop/server) builds need to speak WebRTC to browsers (§3.20). Pinned, built and tested on Linux and Windows **headless exports**

**Rules:**
- Build every target the extension is used on (Linux x86_64, Windows x86_64, Android arm64-v8a; Android x86_64 for the 16 KB emulator test) in **both debug and release** variants
- Use a `.gdextension` file with explicit per-platform library entries; pin the NDK; CI builds all targets; verify 16 KB alignment of Android libraries (§3.18)
- **Browser rule**: any extension code that the **client** needs must keep a **GDScript fallback**, so the web client never needs native extensions. Extension-enabled web exports have their own cross-origin isolation requirements, which we avoid. **Server-only** extensions need no browser counterpart

### 3.18 Android & Play Store
- **Engine version policy**: pinned to **4.7.2-stable**. At the M1 gate, consider 4.8.x only if it is stable with at least one bugfix release and fixes something we need; upgrade on a branch, re-run the M1 test suite, then merge. Never change engine versions mid-milestone
- **Toolchain pinned in M0**: Godot version + export templates, JDK, Android SDK platform/build-tools, Gradle/AGP from Godot's Gradle template, NDK (when GDExtension arrives). Versions are recorded in `docs/toolchain.md`
- **Gradle build** export from M0 (needed for the multicast-lock plugin and AAB)
- **ABIs**: the release AAB ships arm64-v8a. A **test build also includes x86_64**, because the 16 KB-page emulator image on an x86_64 Linux dev machine needs it. Landscape-locked; immersive mode
- **16 KB page-size verification** (from M0, on every release build). Two separate checks are needed, even with pure GDScript (Godot itself is native code):
  1. **ELF alignment**: for every `.so`, `llvm-readelf -l` shows each `LOAD` segment aligned to ≥ 16 KB (`0x4000`)
  2. **ZIP alignment**: generate the device APKs from the AAB with `bundletool build-apks`, then check each with `zipalign -c -P 16 -v 4 <apk>`
  3. **Runtime**: install and run on a 16 KB-page environment (Android 15+ 16 KB emulator image with the x86_64 test build, or a real 16 KB-capable device)
- **Target SDK**: whatever Play requires at submission time (reported as API 36+ for new apps/updates as of Oct 2026; *re-verify at submission*)
- **Application ID: `io.github.aswinkumarks.ionfall`** (fixed; it can never change after the first Play upload). Name/trademark clearance for "IONFALL" happens **before** final logo/store art
- **Signing**: an **upload key** (ours) plus the **Play App Signing** key (Google's). The upload key and its passwords go in a password manager **plus** an encrypted offline backup in a second location, never in the repo. CI uses secrets only for release builds. One named owner holds the developer account credentials
- **Play checklist (before the first test release, M6)**:
  - Current target-SDK policy met
  - **Testing gate**: new personal developer accounts may need a closed test with **12 opted-in testers for 14 continuous days** before production access. Plan the closed-testing track early
  - **Data Safety form**: the declaration comes from a **review of the actual data flows** in the release build (LAN discovery beacons, player names sent to other players, chat, local saves, diagnostics export), not just from the absence of telemetry SDKs. The expected result for v1.0 is "no data collected/shared", but that's confirmed by the review, not assumed
  - SDK inventory (Godot + our plugins)
  - Privacy policy URL
  - Content rating questionnaire, target audience & content declarations (violence; not designed for children)
  - Store listing art
  - **Epic Online Services** (internet play, decision 0005): name Epic as a processor in the Data Safety form and the privacy policy (device-ID login, lobby attributes with player-chosen game names, P2P traffic through Epic relays); list the EOS SDK in the SDK inventory; review Epic's developer terms for release requirements; release credentials (client secret) kept out of the repository and injected at build time
  - Later: account deletion (with O1) and chat moderation obligations (O4)

### 3.19 Project structure
```
game/
  project.godot
  addons/                 # pinned third-party addons (netfox if adopted, test framework)
  core/                   # autoloads: Net, GameState, Settings, Audio, Events, Diagnostics, Platform
  sim/                    # simulation layer: tick loop, commands, player/weapon/projectile sim, damage, spawns
  net/                    # transport adapters, composite peer (later), clock sync, snapshots, lag comp, discovery
  server/                 # dedicated/standalone/managed bootstrap, config, local admin, rotation
  presentation/           # player visuals, viewmodels, VFX, audio emitters, interpolation
  bots/                   # BotBrain, perception, traversal actions
  modes/                  # match state machine, FFA, TDM (later CTF, Waves)
  maps/<name>/            # gameplay.tscn, presentation.tscn, navmesh, lightmaps
  ui/                     # menus, HUD, touch overlay, scoreboard, settings, kill feed
  data/                   # WeaponData, MovementConfig, balance tables
  art/  audio/            # assets (Git LFS) + per-asset license records
  locale/                 # translation files
  native/                 # (later) GDExtension sources + build scripts
  tests/                  # unit, replay, netcode, fuzz, save-migration tests
  tools/                  # export scripts, CI, net test harness (netem scripts, headless test clients)
  docs/                   # decisions/, toolchain.md, perf/, net/wire-layout.md
```

### 3.20 Web client readiness (extensibility rules)
**Goal:** a browser **client** that joins matches hosted by native players (revision 5: no dedicated/Manager servers of ours) can be added later. The architecture is **designed to preserve this feasibility, subject to a transport prototype**. It is not a promise that nothing will need restructuring. **Browser hosting is intentionally unsupported** (technically a browser could act as an authoritative WebRTC endpoint after signaling, but that isn't worth its cost). LAN discovery isn't possible in a browser. Bot matches running locally in the tab are possible but optional.

**Browser constraints the design accounts for:**
- No raw UDP: only **WebSocket** (TCP-based) or **WebRTC data channels** (UDP-like, always encrypted, need signaling)
- No UDP broadcast
- The **Compatibility renderer** (WebGL 2) only
- Threads only with cross-origin isolation (unavailable over plain `http://` on a LAN IP)
- Audio starts only after a user gesture; the default *Sample* playback has no AudioEffects (§3.12)
- Pages served over HTTPS can't open unencrypted `ws://`
- Browser storage can be unavailable or non-persistent (§3.13)

**Rules enforced from M0:**
1. **Transport-agnostic networking**: all networking goes through the `Net` layer, which exposes one `MultiplayerPeer` to the game. Gameplay never touches ENet APIs
2. **Composite peer contract** (prototyped and implemented in the web milestone; moved from M5 in revision 4). The server's peer becomes a `MultiplayerPeerExtension` that wraps one adapter per transport (ENet, WebRTC, WebSocket). Polling the built-in peers and concatenating their packets is **not enough**; the contract is:
   - **ID allocation**: the server is always ID 1. One composite allocator owns the ID space. For ENet clients, the ID ENet's server already assigned is adopted and reserved. For WebRTC/WebSocket clients, the composite allocates an ID that's unused across all transports, and the adapter makes sure the client's own `get_unique_id()` equals it (WebRTC clients are created with that ID; the WebSocket handshake delivers it). Collisions → the connection is rejected and the client reconnects
   - **Admission**: a connection stays in a pre-admission state, invisible to `SceneMultiplayer`, until the handshake (protocol version, `compat_hash`, and later the auth ticket) succeeds. Only then is `peer_connected` emitted
   - **Packet metadata**: every received packet keeps its sender ID, logical channel and transfer mode
   - **Routing**: targeted (one ID), broadcast (0) and exclusion (negative ID) follow Godot's semantics across all transports
   - **Lifecycle signals**: exactly one `peer_connected` / `peer_disconnected` per composite peer, regardless of transport
   - **Relay**: `SceneMultiplayer.server_relay` is **disabled**. Clients never exchange packets with each other through the server; all client-to-client information flows through server simulation
   - **Status**: `net/composite_peer.gd` (ENet + WebSocket adapters) runs on LAN hosts with Settings → Game → "Allow browser players" (or `--web-port N`); the web build's Join Game connects to `ws://host:47711`. Verified with a real Chrome client through a desktop host's lobby into its match and joining a match in progress, plus in-process tests. Admission is SceneMultiplayer's auth on top of the composite. WebSocket adapters get no channel tag: the protocol dispatches by message type. Rule 4 is implemented: snapshots coalesce while more than 4 kB is queued for a WebSocket client, a backlog over 500 ms forces a full state and over 3 s drops the client; browsers send commands at 30 Hz without redundancy. TCP loss (netem on loopback in a user network namespace, `test_browser_stays_playable_under_tcp_loss`): 2% loss + 40 ms delay and 5% loss + 60 ms delay each ran 10 s with 0 corrections and no drops (the server stalled 18 and 43 ticks waiting for late commands; RTT 116 and 250 ms). Not yet done: WebRTC (rule 6, #14: needs a signaling service)
3. **Transport channel mappings** (decided per transport, not assumed identical):
   - **ENet**: logical channels 0/1/2 map to ENet channels 0/1/2
   - **WebRTC** (built-in `WebRTCMultiplayerPeer`): logical channel 0 uses its **three default data channels** (reliable for system traffic, unreliable ordered, unreliable unordered, selected by transfer mode), and logical channels 1 and 2 are two extra **reliable** entries in `channels_config`. That's **5 physical data channels**, configured identically on both ends
   - **WebSocket**: one ordered reliable stream. The built-in peer reports every packet as reliable channel 0, so our protocol header carries a **1-byte logical-channel tag** and the adapter restores it. **No channel isolation** is promised over WebSocket
4. **WebSocket is a separately qualified fallback**, not equivalent to UDP. TCP stalls delivery behind lost data, so:
   - **Bounded send queue** per client (≤ 200 ms or 64 kB of data)
   - **Snapshot coalescing before sending**: only the newest unsent snapshot is queued; older unsent ones are replaced
   - Queue age is monitored via the buffered-amount API. Queue older than 500 ms → switch to a full-state resync; older than 3 s → disconnect with a reason
   - Commands are sent at 30 Hz without redundancy (§3.3.2)
   - Tested under TCP loss (netem). **Competitive responsiveness may require WebRTC**; WebSocket is for "it works" play
5. **Endpoint descriptions** list every transport a server offers (§3.5.3), e.g. `{type: "webrtc", signaling_url: "wss://…"}`, `{type: "ws", url: "ws(s)://…"}`. The client picks the best one it supports
6. **Native WebRTC support** on desktop/server builds comes from the pinned `webrtc-native` extension (§3.17). **ICE policy**: LAN host candidates only for LAN play; internet play needs STUN, and optionally a TURN relay (budgeted with O2)
7. **HTTPS on a LAN**: browsers have no trusted certificates for LAN IPs. The LAN web client is therefore **served over plain HTTP by the dedicated server/Manager itself**: a non-secure, single-threaded page that may use `ws://`. Whether WebRTC data channels work from a non-secure page is *to be verified* in the prototype; if not, LAN web play uses WebSocket. Internet web play uses HTTPS + `wss://` + WebRTC (fits the O1 rule in §3.8)
8. **Discovery is optional**: every join path works from an address or a join link (§3.6)
9. **No threads required for correctness**: the game must run correctly with threading disabled (single-threaded web export). Threads are only optional speedups (e.g. background loading)
10. **Renderer-independent gameplay readability**: no gameplay-critical information depends on features the Compatibility renderer lacks. **Unavailable in Compatibility**: SSAO, SSR, volumetric fog, SDFGI, FSR2, compute-shader effects, decals, some advanced GPU particle features. **Available but possibly disabled for performance**: glow, fog, shadows, lightmaps (prebaked LightmapGI renders; baking happens on the dev PC). Team markers, pickups, hit feedback and hazards must stay readable without the unavailable features. Custom shaders get Compatibility-safe variants
11. **Platform services behind interfaces**: storage, Android plugins (multicast lock, thermal), file dialogs and OS calls go through the `Platform` service with web/no-op implementations. No OS-specific calls in `sim/` or `net/`
12. **Input & lifecycle**: the input adapter (§3.11) handles pointer lock and its loss (Esc), browser-reserved keys, and tab suspension (the same best-effort timeout and resume model as Android, §3.5.1). Audio starts after the first click
13. **Compatibility checks**: the web client sends the same handshake (`protocol_version`, `build_id`, `compat_hash`), so §3.14 applies unchanged
14. **Download size**: client `.pck` target ≤ 150 MB *(provisional)*. Web exports need desktop (S3TC/BPTC) and mobile (ETC2/ASTC) texture formats

**Enforcement (so the rules don't rot):**
- **M0**: a **web export preset** (Compatibility renderer, single-threaded, no extensions) exists and CI builds it on every commit
- **From M2, every milestone**: a browser smoke test in Chrome and Firefox that reaches the menu and runs a **local bot match** in the browser: move, fire, take shield/health damage, die and respawn (Compatibility preset). This checks single-threaded performance and renderer readability on real gameplay, not just a menu
- **Web-milestone transport prototype** (first step of the web milestone, moved from M5 in revision 4): one dedicated server with the composite peer accepting an ENet client and a **real browser client** in the same match. It covers bidirectional RPCs, disconnect/reconnect, ID collisions, control-channel traffic and the WebSocket queue rules, plus WebRTC if `webrtc-native` works headless. Its findings feed the web milestone estimate

**Web client milestone (post-v1.0, separately budgeted):** composite peer on the native player host, WebRTC transport (WebSocket fallback), signaling through a small third-party or serverless signaling service (revision 5: not our own game servers), endpoint descriptions with web transports, web UI flow (join by link/address), Compatibility visual preset, web audio and storage fallbacks, a page served by the dedicated server or Manager.

---

## 4. Art, audio & asset licensing
**License policy:** **CC0 preferred.** Non-CC0 assets are allowed only under licenses on an approved list that permit commercial use and redistribution inside a game binary. Approved so far: CC0, CC-BY 4.0 (with attribution) and the Sonniss GDC bundle license. **Every asset** has a row in `art/ASSETS.csv` / `audio/ASSETS.csv` recording source URL, author, download date, license, required attribution, modifications and redistribution limits. A copy of each license text goes in `licenses/`, and `CREDITS.md` is generated from the CSVs.

**Sources:** Quaternius (sci-fi kits, **rigged + animated characters**, guns; CC0), Kenney (space/blaster kits, UI, sounds; CC0), Poly Haven / ambientCG (HDRIs, textures; CC0), Sonniss GDC bundle (Sonniss license), sfxr-generated sounds (ours).

All assets are restyled with shared materials (team color, emissive trims, palette) so mixed packs read as one game. Anything missing is built in code/shaders.

- **Environments**: CSG greybox → modular mesh kit (floor/wall/trim/pillar/ramp) with triplanar materials + emissive strips, following the lighting and lightmap pipeline (§3.9). Theme: orbital research station (white panels, ion-cyan accents; teams cyan vs orange, plus shape markers)
- **Characters**: **one skinned CC0 rigged character** (1 draw per material, uses existing animations). *(Decided in M2 by the on-device comparison against rigid parts: on the Mi 11X, 16 skinned characters cost 80 draws vs 432 for rigid parts and ~1 ms less GPU time; see `docs/decisions/0003-character-rig.md`.)*
  - **Hitboxes** are authoritative simple shapes (head, torso, legs per stance) driven by the simulation state, independent of the animation pose
  - Ragdolls are cosmetic only: ≤ 4 at once, removed after 3 s
- **Weapons**: low-poly hard-surface models with emissive accents; procedural viewmodel sway/recoil/reload motion
- **VFX**: GPU particles within the budgets in §3.10
- **Audio**: as in §3.12; an ambient synth music loop

---

## 5. Testing strategy
"From" dates refer to the milestones in §6.

| Layer | What | From |
|---|---|---|
| **Unit** (GUT or gdUnit4, chosen in M0; runs in **GitHub Actions**) | Damage/regen math, balance-table generation (TTKs from tick data), scoring and death-attribution precedence, spawn scoring, save migration + corrupt-save recovery, idempotent results, port allocator (reserved ports, failed binds) | M0, every commit |
| **Replay determinism** | Same build/platform: record command streams, re-simulate, compare `PlayerSimState` **exactly** every tick (movement incl. mantle/slide, weapon state, spread). Cross-platform: Android vs Linux replays within the **≤ 1 cm** bound | M1a every commit; cross-platform per milestone from M1b |
| **Netcode correctness** | Lost/duplicated/late commands (the 3-packet loss guarantee; press-counter rules), snapshot baseline loss, per-entity baselines, prioritization starvation (update ≤ every 4th snapshot), out-of-order packets, `match_id`/`phase_seq`/generation handling, `view_tick` validation, reconnect, map change | M1b, every commit (headless) |
| **Correction limits** | Measured at 100 ms RTT / 2% loss: visible corrections ≤ 1/min/player, no snaps outside respawn/teleport (§3.2) | M1b, per milestone |
| **Fuzz** | Malformed and oversize packets, out-of-range values, wrong-sender RPCs and ingress floods against every client entry point | M1b nightly |
| **Simulation load** | Headless server + 16 server-side bots: tick time p50/p99 | M2 nightly |
| **Real-peer load** | **Headless test clients** (`--test-client`) running the full client network stack (prediction, reconciliation, acks, encoding) over real connections. **v1 (8 clients) in M1b**; **16 clients from M5**. Server-side bots alone don't count as a capacity test | M1b (8), M5 (16) |
| **Network conditions** | Linux `tc netem`: RTT 0/50/100/150 ms, ±20 ms jitter, reordering, 1–3% random + burst loss, bandwidth caps (2 Mbit/s client) | M1b, per milestone |
| **Bandwidth** | Measured bytes vs the worksheet (§3.3.5), typical and worst case | M1b, per milestone |
| **Rendered cross-play** | Mixed Android/Linux/Windows **release** builds in one match | M1b, per milestone |
| **Soak** | Mi 11X client and phone host 20 min (M1c); dedicated server 60 min with 8 test clients (M1b) → 16 test clients (M5) | M1b/M1c |
| **Dedicated server capacity** | One match process: all-human (test clients), all-bot and mixed; tick percentiles, RAM | Dropped (revision 5) |
| **Manager capacity benchmark** | Several matches on one machine; headroom-based admission | Dropped (revision 5) |
| **Cold start** | First match after install: shader stutter, load time | Per release |
| **Human playtests** | Feel (movement, TTK), touch usability, UI clarity, accessibility options | Every milestone |
| **Pseudolocalization** | Text expansion, missing keys | Per release |
| **Web build** | Web export builds in CI | M0, every commit |
| **Web smoke test** | Chrome + Firefox: menu + local bot match (move, fire, damage, death, respawn) on the Compatibility preset | M2, every milestone |
| **Transport prototype** | Composite peer: ENet client + real browser client in one match, reconnects, ID collisions, WebSocket queue rules | Web milestone (informational) |
| **16 KB checks** | ELF alignment, ZIP alignment, runtime on a 16 KB environment (§3.18) | M0, every release build |

---

## 6. Milestones
Each milestone has exit criteria. **No durations are estimated until M1 is complete.** M1 is split into three ordered sub-gates; each must pass before the next starts.

| # | Milestone | Exit criteria |
|---|---|---|
| **M0** | Foundations & pipelines | Toolchain and physics backend pinned + documented; git + LFS; application ID and upload key (backed up); versioning, artifact IDs, `compat_hash`; export presets for Linux, Windows, Android (Gradle), **dedicated server** and **web** (Compatibility, single-threaded); **signed release AAB installed on the Mi 11X** with all 16 KB checks passing; CI builds all presets; project skeleton with the `sim/` vs `presentation/` split and the `Platform` service; test framework; diagnostics overlay skeleton; `tr()` keys in the first menu |
| **M1a** | Simulation & feel (offline) | One greybox arena. Movement (sprint/slide/double-jump/mantle) on the simulation contract (§3.2); Pulse Rifle (hitscan) + Arc Launcher (projectile); shield/health; basic spawn system; **basic touch controls** with the finger-ownership classes; same-build replay determinism tests green; movement feels good to human testers on PC and the Mi 11X |
| **M1b** | Networking core | netfox evaluated (criteria §3.3.1, including transport-API inspection and RPC audit) and the decision recorded; prediction, reconciliation, interpolation, lag compensation with `view_tick` validation; minimal FFA match state machine with `match_id`/`phase_seq`; ingress limits and validation (§3.7); **exported** headless dedicated server and PC listen host; PC↔PC then PC↔Android cross-play; test clients v1 (8); bandwidth measured vs §3.3.5; correction limits met at 100 ms RTT / 2% loss; 3-packet loss guarantee tested; cross-platform replay bound met; 60-min server soak with 8 test clients |
| **M1c** | Platform proof | **Phone host** on the Mi 11X (4 combatants) and 20-min client/host soaks against §3.10; Android lifecycle behaviors (§3.5.1); LAN discovery + manual IP + join link on the test matrix (§3.6); lighting configuration validated on a baked floor and the lightmap format measured (§3.9) |
| **Gate** | Go/no-go + estimate | Review M1 numbers; fix the provisional budgets; estimate M2–M6; confirm cut lines |
| **M2** | **Internal MVP** (playable game) | 1 map with first art pass, FFA, Pulse Rifle + Arc Launcher + Mag Pistol, bots (Normal) with traversal + stuck recovery, kill feed, death cam, HUD, results screen, profile/stats/XP with atomic saves + migration tests, settings, basic accessibility items, basic audio (buses, footsteps, occlusion v1); **character approach decided on device**; web smoke test passes; playtested by humans |
| **M3** | Release content | Remaining weapons per the balance table, grenades, melee, power-weapon pickups + loadouts, **TDM** + teams + balance, **map 2** (symmetric, CTF-ready), 4 bot difficulties, cosmetic unlocks, touch layout editor + aim assist + auto-fire option, reconnect, QR join code |
| **M4** | Art, audio & performance pass | Full lightmap pipeline on both maps, characters, VFX, audio pass, quality presets; §3.10 targets met on the Mi 11X (8 and 16 combatants; targets revised in M4 after measurement), release builds, 20-min sustained; ADPF/thermal spike; cold-start stutter test; phone host cap finalized (4). *Done: docs/perf/m4.md. The dedicated-GPU PC target moved to M6* |
| **Post-M4** | **Done, off-plan** (2026-10-22) | **Internet play** over EOS P2P: anonymous device-ID login, invite codes, online game list, Epic relays; Linux, Windows, Android (decision 0005, `docs/online.md`). **Lobby**: host picks map, mode and length (5–20 min) and sees who joined; players read-only; Start sends everyone in; everyone returns to the lobby after each match. **Menus**: full-screen home with Single Player / Host / Join cards, map picture cards, a combined LAN + online game browser. **Touch controls**: one thumb cluster around Fire anchored to the bottom-right corner, picture icons. Verified laptop↔laptop and Mi 11X↔laptop in both directions; not yet on mobile data or Windows (M5) |
| **M5** | **v1.0 server & online readiness** (slimmed in revision 4) | Exported Linux + Windows dedicated server boots and runs every map and mode (CI smoke test per map/mode); graceful shutdown on SIGTERM/Ctrl+C; **16 real test clients** soak 60 min within tick/bandwidth budgets; fuzz tests green (handshake, LOBBY/START, commands; malformed and oversized packets); **online checks**: a phone on mobile data joins and hosts through Epic relays, Windows build hosts and joins online, lobby → match → lobby cycles hold for 30 min; release builds get EOS credentials from CI secrets instead of a local file. *Moved out: `server.cfg`, rotation, standalone/managed modes, admin console, log rotation, capacity measurement → M7; DTLS spike → O1; composite-peer browser prototype → Web milestone* |
| **M6** | **v1.0 LAN release** | Polish, full accessibility list, pseudoloc pass; min-spec phone, iGPU laptop and a dedicated-GPU PC tested (or claims removed); desktop release builds (Linux, Windows); Play **closed testing track** started (14-day gate if required); Play checklist (§3.18) including the data-flow review; Android release |
| ~~**M7**~~ | ~~Central server (LAN)~~ **Dropped in revision 5** | The deferred dedicated-server features (§3.5.2: `server.cfg`, rotation, standalone/managed modes, local admin console, log rotation, single-match capacity measurement); Manager, match list/create/join UI, port allocator, playlists, lifecycle protocol, restart backoff, admission by headroom; Manager capacity benchmark (§5) published in `docs/perf/` |
| **Web** | Web browser client (post-v1.0, separately budgeted) | As in §3.20, starting with the composite-peer prototype with a real browser client (moved from M5). Internet play for web players over **WebRTC** (decision 0005); a native host then serves EOS and WebRTC peers at once |
| ~~**O1–O4**~~ | ~~Internet play on hosted servers~~ **Dropped in revision 5** | Player-hosted internet play over EOS (Post-M4) covers internet play; §3.8 keeps the old design as a record |
| Post-v1.0 | Expansion | Done: CTF, Co-op Waves, spectator mode (offline and network), map 3 (Vesper Foundry), Compatibility fallback for non-Vulkan Android, Flux SMG, Spacer character and colours. Wall-run was dropped |

**Cut lines if the estimate after M1 is too large** (cut in this order): 4 bot difficulties → 2; touch layout editor; QR join code; map 2 (ship TDM on map 1); M7. *(Revision 4: all of these shipped except M7. Revision 5: M7 is dropped.)* The internal MVP (M2) is never cut. Browser work never blocks v1.0.

---

## 7. Risks & mitigations
| Risk | Mitigation |
|---|---|
| Netcode feel (rubber-banding, unfair hits) | Simulation contract (§3.2) + measured sub-gates M1a/M1b before content work; replay determinism and correction-limit tests; netem testing |
| netfox doesn't fit | Evaluated in M1b against written criteria, limited to components that fit the forward-simulation model; custom path budgeted separately |
| Cross-platform float differences | Bounded-error requirement (≤ 1 cm) instead of exact cross-platform replay; reconciliation absorbs small differences |
| Android performance and thermals | Mi 11X now (min-spec phone before public release), release builds, 20-min sustained frame-time tests from M1c, scalable presets, conservative phone-host cap |
| Phone-host instability (backgrounding, Wi-Fi) | Best-effort lifecycle rules (§3.5.1), client-side timeout detection, unconfirmed results saved, PC/dedicated hosting recommended in the UI |
| Discovery blocked (AP isolation, hotspots, permissions) | Directed broadcasts per interface, manual IP + join links + QR, clear failure messages, test matrix (§3.6) |
| Touch vs mouse fairness | Defined aim-assist rules (§3.11), touch-only lobbies as an option |
| Server/client logic getting tangled | `sim/` vs `presentation/` split from M0; gameplay/presentation scene split; CI runs the exported headless server |
| Lighting setup doesn't work on mobile | Per-light configuration tested on a baked floor in M1c before art production; lightmap format measured |
| Art scope creep | Modular kit + shared shaders; lock the style on map 1 in M2/M4 before map 2 gets art |
| Scope too large for a small team | M1 split into sub-gates; internal MVP (M2) small; estimate after M1; explicit cut lines; browser work off the critical path |
| Play Store surprises (SDK level, 16 KB pages, testing gate, Data Safety) | Signed AAB + both 16 KB checks from M0; Play checklist with a data-flow review; closed testing started early |
| Losing the signing key | Upload key + Play App Signing, two encrypted backups, named owner |
| Asset license problems | Written license policy, per-asset records, license copies |
| GDExtension build complexity | Only when profiling demands it or for transport dependencies; full target/variant matrix in CI; GDScript fallbacks for client code |
| Web client becomes impossible without a rewrite | Rules in §3.20 enforced from M0: web build in CI, gameplay smoke test from M2, transport prototype at the start of the web milestone |
| Composite peer or WebRTC proves hard | Prototype first in the web milestone; WebSocket fallback; web client separately budgeted after v1.0 |
| Internet security later | Player-hosted internet play runs over EOS P2P (encrypted, reachable only by product user ID, same handshake and ingress limits); fuzz tests in M5. Our own hosted servers still follow the O1 rule: no exposure before encrypted, ticketed, hardened joins with account deletion |
| Dependence on Epic Online Services | Online play is behind the `Online` autoload and `Transport.host_peer/join_peer`; LAN never needs EOS; WebRTC is the planned second backend; Epic terms reviewed before release (M6) |

---

## 8. Resolved decisions & remaining items
| Item | Decision |
|---|---|
| Engine | Godot 4.7.2-stable (upgrade policy §3.18) |
| Test devices | Use the 1–2 devices on hand for now (Mi 11X + dev PC). Min-spec phone and iGPU laptop are needed before the public Play release (M6) |
| Application ID | `io.github.aswinkumarks.ionfall` |
| Repository / CI | https://github.com/aswinkumarks/IONFALL (GitHub Actions for CI and export builds) |
| Visual identity | Approved: white/gray station panels, ion-cyan accents, teams cyan vs orange + shape markers; logo = falling ion streak |
| Web support | Post-v1.0 web client; architecture kept feasible (§3.20) |

**Remaining:** name the second test device if one is available; trademark/name check for "IONFALL" before final store art.

# Characters on the main thread (2026-10-26)

m4.md left an open question: in combat the phone's frames sit at 17–25 ms
while the GPU needs only 8–12 ms, and the per-section timers don't explain
the rest. This measures it: most of it was the remote characters' animation,
and in particular GDScript posing their bones every frame, all outside the
timed sections.

All numbers are from a 4-vCPU Xeon @ 2.1 GHz cloud VM (headless, so CPU
only), the editor build of Godot 4.7.2. A phone core is several times slower;
the on-device check is still to do (below).

## What it cost

16 MeshyRig characters holding weapons, animated every frame
(`Performance.TIME_PROCESS`, interleaved blocks; lowest block median):

| | ms per frame |
|---|---|
| As shipped (AnimationTree + HoldWeapon + HeadLevel modifiers) | 3.5–4.7 |
| Without the HoldWeapon modifier | 2.2 (one run) |
| Without either modifier | 1.1–2.0 |
| Without the AnimationTree (rest pose) | 0.6–0.8 |
| No characters | 0.3–0.4 |

The HoldWeapon modifier (arm IK, plus the finger curl) was over half of it.
The curl alone formatted ~120 strings and wrote 60 bones per character per
frame (`MeshyRig._curl`), because a modifier's pose is discarded every frame.
Everything ran for every character, every frame: off screen, far away and
dead ones included.

## Changes

- **Finger curl baked into the finger bones' rests** (`MeshyRig._curl`),
  once at setup: no clip has finger tracks, so every pose reset leaves them
  curled. Nothing per frame.
- **Bone indices and arm rest data cached** (`ArmoredRig._cache_bones`)
  instead of `find_bone(String)` and rest lookups every frame; the weapon's
  Grip/Support markers read once per weapon.
- **One modifier instead of two**: HoldWeapon also levels the head. Each
  active modifier costs the skeleton a pass (~30 µs per character here),
  far more than the GDScript inside it (~9 µs for the whole IK).
- **The weapon is a child of the rig** (it was `top_level`, placed in world
  space on every skeleton update) and the unused hand BoneAttachment3D is
  gone, so skipped animation frames can't leave the weapon behind.
- **Animation level of detail** (`PlayerVisual._update_detail`,
  `CharacterRig.set_detail`): the AnimationTree is advanced by script
  (`callback_mode_process = MANUAL`).

  | Where the character is | IK and head levelling | Clips advance |
  |---|---|---|
  | On screen, within 15 m (±1 m hysteresis) | yes | every frame |
  | On screen, 15–30 m | no (the weapon still follows the aim) | every 2nd frame |
  | On screen, past 30 m | no | every 3rd frame |
  | Off screen | no | every 6th frame |
  | Dead | no | paused |

  Reduced-rate frames are spread across characters.

Also in this change: `PlayerSimState.copy()` written out by hand (22–31 µs
→ 11–13 µs; `test_player_sim_state.gd` keeps it complete), the scoreboard
table reuses its labels instead of rebuilding ~85 of them every frame it
shows (`test_score_table.gd`), and phones no longer keep the reflection
probe on Medium (m4.md said it was off; `Settings.MOBILE_EXTRAS`).

## Results

Same 16-character benchmark, before and after:

| | Before | After |
|---|---|---|
| All at full detail (paired runs) | 4.5–4.7 ms | 2.1–2.3 ms |
| Mixed: 4 near, 6 at mid range, 6 off screen | — | 1.2–1.5 ms |

A whole match (`--play --autopilot --bots 15`, headless, so the host's
simulation, bots and every client visual; PERF `main_p50`/`main_p95`, three
minutes each):

| | main p50 | main p95 |
|---|---|---|
| Before | 12.3–13.4 ms | 18.4–23.8 ms |
| After | 8.9–9.8 ms | 15.2–18.8 ms |

With these changes, freezing every remote character entirely saves almost
nothing more: characters are no longer a main-thread cost on this host. What
is left is about 4.5–5 ms of physics-process time (the host's simulation,
bots and Jolt) and about 4.5 ms of process time spread over the rest
(HUD drawing ~0.25 ms, effects ~0.1 ms, events ~0.35 ms, visuals ~0.75 ms;
the remainder needs a native profiler to place).

Close-ups rendered with Mesa llvmpipe show the same poses before and after
at full detail. At reduced detail the arms keep the clips' two-handed pose
under the shouldered weapon, visible up close but not at 15 m+.

## Still to do

- **On the Mi 11X**: a 20-minute combat soak (m4.md setup) with 8 and 16
  combatants, to see how much of the 17–25 ms p95 this returns.
- Phone host (4 and 8 combatants): host tick plus the remaining physics time.

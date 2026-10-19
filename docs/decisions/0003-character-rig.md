# 0003: Character approach: one skinned character

**Status:** accepted (M2, 2026-10-19)

## Context

PLAN §4 left the third-person character open between (a) one skinned CC0
rigged character and (b) rigid parts, to be decided by an on-device
comparison on the Mi 11X.

## Measurement

Lighting test scene (baked lightmap with shadowmask, Dynamic sun with
realtime character shadows, render scale 0.75), runners moving through every
clip, 2 s warm-up and then 10 s measured. Run it with the "Rig bench" button,
`--lighting-test --rig-bench` on desktop, or on Android (debug build):

    adb shell "run-as io.github.aswinkumarks.ionfall sh -c 'echo --lighting-test --rig-bench > files/launch_args.txt'"

Mi 11X (Adreno 650, Vulkan Mobile), thermal status 0, two runs:

| Rig | Runners | GPU p50 / p95 (ms) | Draw calls |
|---|---|---|---|
| skinned (Kenney characterMedium, 1 material) | 8 | 7.98–8.01 / 8.14–9.11 | 57 |
| skinned | 16 | 7.83–8.38 / 8.84–9.31 | 80 |
| rigid parts (12 boxes) | 8 | 8.25–8.64 / 8.81–9.14 | 231 |
| rigid parts | 16 | 8.97–9.55 / 9.88–10.12 | 432 |

Frame time was vsync-bound at 16.67 ms for all four configurations. The
scene without runners costs ~7.75 ms GPU (M1c), so 16 skinned characters add
roughly 0.1–0.6 ms; 16 rigid-parts characters add ~1.2–1.8 ms and 350 draws
(main and shadow passes), about 5x more draws.

## Decision

Use one skinned character (`SkinnedRig`), as PLAN §4 expected. `PartsRig` and
`CapsuleRig` stay as fallbacks and for the bench. Hitboxes stay
simulation-driven and independent of the pose.

## Consequences

- The Kenney Animated Characters 3 model (CC0) is the M2 stand-in. It has only
  idle, run and jump clips: strafing twists the legs up to 50° and
  backpedalling plays run in reverse. A sci-fi character with
  strafe/crouch/aim clips (e.g. Quaternius, CC0) replaces it in M4.
- Each character has its own AnimationPlayer; the clips are shared through one
  AnimationLibrary.

## Update (2026-10-19)

The stand-in is now the Quaternius Ultimate Space Kit astronauts (CC0, four
variants, one skinned mesh each) with gun-ready clips (Idle_Gun, Walk_Gun,
Run_Gun, Jump_Idle, Duck), as `AstronautRig`. The player's weapon model is
attached to the right-hand bone. Same approach (one skinned mesh per
character), so the measurement above still applies.

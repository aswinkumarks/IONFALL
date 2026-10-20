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

## Update 2 (2026-10-19): armoured soldier

Feedback: the animal astronauts read too cute; the target is a Halo-like
armoured soldier. The default is now `ArmoredRig`: the Quaternius Universal
Animation Library mannequin (CC0, 43 clips) as a dark undersuit plus armour
plates generated from the skeleton rest pose (helmet with gold visor, chest,
pauldrons, gauntlets, thigh/shin plates, boots, backpack), skinned rigidly to
their bones in one mesh with two surfaces (armour in the player's colour,
visor). An AnimationTree layers upper-body aim (blended by pitch) and a
shoot one-shot over lower-body locomotion. Cost: 3 draws per character
(body, armour, visor) plus the held weapon.

## Update 3 (2026-10-19): superhero body

The undersuit body is now the Quaternius Universal Base Characters
"Superhero" male (CC0, same 65-bone skeleton as the animation library) for
a bulkier silhouette. Animation-library clips are retargeted at load
(rotation tracks only; the pelvis position is scaled to this body's hip
height) and the armour plates are sized up to match.

## Update 4 (2026-10-19): Cybernetic Sentinel

The default is now `SentinelRig`: the Meshy community model "Cybernetic
Sentinel" by tborcen (CC0). The source is 2M triangles; local decimation
broke its fragmented UV atlas (blotchy texture), so it was reduced to
15,593 triangles / 22,561 vertices inside Meshy (which re-bakes the
texture) and auto-rigged with `meshy_rig` (5 credits; 24-bone humanoid in
centimetres, A-pose, no fingers). Textures are 2048 px (baked down from 4K).

Animation reuses ArmoredRig's AnimationTree and the same Universal
Animation Library clips, retargeted at load in model space: for each
mapped bone, target global = (source global pose x source global rest^-1)
x rest correction x target global rest, where the rest correction turns the
Sentinel's bone direction into the library's (A-pose to T-pose). Hips
position is scaled by the hip-height ratio. Clips are baked at 30 fps once
per process. The weapon grip is carried into the Sentinel's hand space the
same way.

Player colour: `sentinel.gdshader` swaps the hue of the blue/cyan panels and
light strips to the player's colour (keeping value) and makes the strips
emissive; hit flash and spawn glow are shader parameters. One draw per
character plus the weapon.

Budget: ~78k triangles for five characters with shadows (PLAN §3.10 caps
the frame at 300k on the Mi 11X). Laptop, 8 characters, shadows on: GPU
p50 6.96 ms (armoured rig 6.59 ms). Mi 11X measurement pending.

## Update 5 (2026-10-20): Sentinel finger bones

Meshy's auto-rig has no finger bones, so the Sentinel's hands couldn't close
on a weapon. `tools/rig_sentinel_fingers.gd` adds them in Godot, without
Blender or Mixamo: three bones per finger and thumb on each hand (30 in
all), placed from the hand mesh. In the hand bone's space the fingers run
along +Y; past the knuckles the thumb's tip sits across a gap from the
four fingers, which split into four bands across the hand. Each finger's
joints come from the centre of its band at the knuckle, 42 % and 72 % of
its length and the tip. Vertices on the hand are re-skinned by inverse
distance (⁴) to the bone segments, the palm included, with finger weights
fading out just below the knuckles so the palm stays rigid. The tool
writes the re-weighted mesh (LODs regenerated) and a skin whose extra
binds name the new bones; `SentinelRig` adds those bones at load, taking
their rests from the bind poses.

The clips have no finger tracks, so the curl is set once: the right hand
closed around the grip, the left cupped for the fore-end. In first person
the right palm goes against the weapon's handle (the middle of the lowest
third of the model, the "Grip" marker) and the IK's forearm takes the
hand's roll, so the wrist only bends.

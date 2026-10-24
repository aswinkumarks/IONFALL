# Map 2: Halcyon Spire

An open-air research platform on a moon, 72 × 56 m (about 2.1× Meridian
Station), mirror-symmetric in X and Z for free-for-all.

- **Central plaza** (top 4 m) round the spire, open underneath: a dark
  under-croft for close fights, reached from all sides; ramps on its north
  and south faces.
- **Bases** east and west: ground-floor rooms with three doors and an inner
  ramp to the roof; bridges join the roofs to the plaza.
- **Corridors** along the north and south hulls (indoor flank routes, three
  doors each) whose roofs are walkways with a parapet; ramps down at their
  ends.
- **Cover**: half walls, crates, barrels, lockers, desks and columns across
  the lanes, courtyards and bases; the satellite dishes mark the corners.

- **Jump pads**: one in each side lane by the lane half wall, throwing
  you 12 m up onto the plaza corner (`SpireLayout.jump_pads()`, see
  PLAN §2.1). They're drawn at runtime (`JumpPadVisuals`), so they aren't
  part of the baked presentation.

## Build

`maps/spire/spire_layout.gd` is the single source: collision boxes
(gameplay scene, what the dedicated server loads), kit pieces, decor,
lights and spawns. `tools/build_spire.sh` generates the presentation
(kit pieces merged per material and quadrant so quadrants cull, boxes for
slabs, walls, cover and light strips) and bakes the lightmap; a test fails
if the presentation is older than the layout.

Art: Quaternius Modular Sci-Fi MegaKit and Sci-Fi Essentials Kit (CC0),
`art/environment/scifi/`; red trims swapped for the kit's blue/plain
variants, crate textures 1024 px. Sky: Meridian Station's space sky shader.

## Budgets

- 133.9k triangles in 34 meshes (crates 50k; walls and floors the rest).
- Lightmap baked in ~20 s on the laptop; atlas ~3.9 MB.
- Laptop (Xe, 1600×720, Medium, 4 combatants, autopilot): 60 fps,
  p99 16.7 ms, same as Meridian Station. High: 57.8 fps in minute 1
  (shader compiles), p99 26.7 ms.
- Mi 11X: not measured yet.

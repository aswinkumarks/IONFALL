# Map 3: Vesper Foundry

An ore refinery yard on a volcanic moon, 56 × 40 m (smaller than Halcyon
Spire, about 1.2× Meridian Station), mirror-symmetric in X and Z for
free-for-all, with team sides east and west.

- **Crucible** in the middle (a 3 m column with a molten top), ringed by low
  cover walls and crates: the close-range centre.
- **Catwalks** (top 4 m) along its north and south sides, a rail on the
  inner edge, with ramps down at both ends towards the bays. The Rail Sniper
  sits on the north catwalk, a grenade on the south one.
- **Loading bays** east and west: ground-floor rooms with a front door
  facing the crucible and two side doors, roofs reached by ramps along the
  hull. They hold the team spawns and the capture-the-flag bases.
- **Flank lanes** along the north and south hulls: crates, tarps and barrels;
  the Arc Launcher in the south lane. A jump pad in each lane throws you up
  onto the catwalk above it (`FoundryLayout.jump_pads()`, PLAN §2.1).

## Build

`maps/foundry/foundry_layout.gd` is the single source (collision boxes,
kit pieces, decor, lights, spawns, pickups, flag bases). It reuses Halcyon
Spire's piece helpers and builder:

    tools/build_spire.sh foundry

generates `maps/foundry/presentation.tscn` and bakes its lightmap; a test
fails if the presentation is older than the layout. The look (warm ambient,
low orange sun, ember fog and grade) lives in the builder's `MAPS` table.

Art: Quaternius Modular Sci-Fi MegaKit and Sci-Fi Essentials Kit (CC0),
`art/environment/scifi/`, as for Halcyon Spire.

## Budgets

- 98.3k triangles in 34 meshes; 17 baked accent lights.
- Lightmap baked in ~3 min on the laptop; atlas ~2.7 MB.
- Laptop (Xe, 1280×720, Medium, 4 combatants): 60 fps in the first match
  seconds.
- Mi 11X: not measured yet.

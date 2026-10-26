# Rendering, assets and size pass (2026-10-26)

The GPU, asset and download items from the performance review that followed
characters-main-thread.md. Nothing here could be measured on a phone yet:
the container this was done in has no GPU. Changes were checked by
rendering with the game's own Mobile renderer on Mesa lavapipe (software
Vulkan), before and after, from the same views, plus tests. The on-device
check is listed at the end.

## GPU work

The mesh changes are stored as assets (Git LFS), each with the tool that
rebuilds it:
- the maps' meshes carry the material fixes. `tools/bake_map_materials.gd`
  converted them in place, and the map builders now convert as they save;
- the weapon stand-ins are `art/weapons/ionfall/<model>_far.res`, built by
  `tools/bake_weapon_proxies.gd`;
- the characters' third-person meshes are
  `art/characters/meshy/<c>/<c>_reduced_mesh.res`, built by
  `tools/bake_reduced_characters.gd`.

Nothing is converted at load. Renders of the three maps from the saved
meshes match the earlier load-time conversion to within 0.035% of pixels.

| Change | Where | Effect |
|---|---|---|
| Reflection probe off on phone Medium | `Settings.MOBILE_EXTRAS` (previous commit) | ~0.9 ms GPU on the Mi 11X (m4.md) |
| Triplanar → planar UVs on map panels | `MapMaterials`, baked into `maps/*/meshes/*.res` | 1 texture fetch per pixel instead of 3 on 13 Station surfaces and the slabs, walls and cover of Spire and Foundry. Every converted face is axis-aligned, so the image is unchanged; geometry and lightmap UVs are untouched, so no rebake |
| Back-face culling on 5 kit materials | same | crates (~50k triangles per map), floor trims, trims, cables, decals; MI_Trim_01/02 stay double-sided (below) |
| Weapon stand-ins past 5 m | `<model>_far.res` (`tools/bake_weapon_proxies.gd`), `WeaponModels.FAR_RANGE` | other players' guns and pickups: 6–8k → ~1k triangles each; same material and vertex format, so no new pipelines |
| Character textures 2048² → 1024² | `.import` size limits | ¼ of the VRAM for the 12 character textures |
| Baked accent lights off moving things on phones | `RenderLayers` | characters, weapons, the first-person arms, pickups and flags take the accents from the lightmap probes instead of a real-time omni pass where effect lights are off (Low, Medium); desktops keep the coloured rim light |
| CTF flag light only with effect lights | `FlagVisuals` | no moving omni (and its pipeline compiles) on phones |
| Nameplates in 2D | `Nameplates` | about 4 draw calls per player (text, outline, bar, team mark) → a few for all of them; still hidden behind walls (a line-of-sight ray per player every 0.1 s) and faded past 30 m |

**Character and weapon triangles, measured.** The review estimated 16
players at ~470k triangles from the models' full detail (21k per
character, 8k per gun). Drawn triangles for one character with a pulse
rifle (Mobile renderer, `RENDER_TOTAL_PRIMITIVES_IN_FRAME`):

| Distance | Medium (scale 0.6, LOD threshold 2) | High (scale 1.0, threshold 1) |
|---|---|---|
| 2 m | 12,848 | 17,962 |
| 4 m | 12,848 | 12,848 |
| 6 m and on | 6,208 | 6,208 |

The character is already at its coarsest LOD (vanguard: 5,277 of 20,783)
from 2 m on Medium and from 4 m on High: the mesh's own LODs do the work,
so it needs no further decimation, and a lower LOD bias changed nothing
past 2 m. The gun was the excess: 7,571 triangles at any distance before;
its stand-in drops it to 931 past 5 m (the step at 6 m). Sixteen players
at play distances now draw about 100k triangles, not 470k.

**Character decimation.** Mesh LODs only trim indices, so every remote
character still skinned all 26–31k vertices of its full mesh each frame,
at any distance. In third person, characters now use the saved reduced mesh (`ReducedMesh`): the
mesh's own first LOD becomes the base level (about 10.4k triangles,
down from 20.7k), the coarser LODs stay, and the vertices none of them use
are dropped (sentinel 26,156 → 10,763, vanguard 28,758 → 11,593, operative
26,896 → 11,235, spacer 30,547 → 12,647). It is about 0.6 MB per
character (the Linux pack goes from 82 to 84 MB), and loads with the others
(`MeshyRig.paths`). First
person (the arms) and the character screen keep the full mesh. With 16
characters running on Medium (`build/shots/char_bench.gd`, software
Vulkan, three runs each) GPU time went from 70.3–72.9 ms to 62.1–64.3 ms,
about −12%. Renders at 1.5 m, at 3 m and of the crowd differ in at most
0.03% of pixels.

**Culling check.** The kit's glTFs mark every material double-sided.
`tools/cull_check` rendered every spawn in four directions (64 views per
map) with culling as built and with back faces culled per material:

| Material | Spire views changed | Foundry views changed |
|---|---|---|
| MI_Trim_01 | 20 | 11 (up to 0.3 % of the pixels) |
| MI_Trim_02 | 3 | 0 (0.05 %) |
| Crates, floor trims, trims, cables, decals | 0 | 0 |

(View 0 changes in every run whatever is culled: its first frames differ.)
Culling MI_Trim_01 opened a gap in a Foundry doorway, so it and MI_Trim_02
stay double-sided.

**Software-renderer GPU time** (lavapipe, 960×540, three views per map,
medians of 12 frames; a CPU emulation, so only the direction is meaningful):

| Map | High: before → after | Medium: before → after |
|---|---|---|
| Station | 3435 → 1297 ms (−62 %) | 946 → 487 ms (−49 %) |
| Spire | 1929 → 1059 ms (−45 %) | 603 → 452 ms (−25 %) |
| Foundry | 1483 → 907 ms (−39 %) | 501 → 404 ms (−19 %) |

Station gains most: nearly all of it was triplanar. A software rasterizer
pays far more per texture fetch than a GPU, so expect a smaller share on a
phone. The same renders show the visual changes: the planar UVs match
triplanar exactly, the 2D nameplates hide behind walls as before, blob
shadows sit under the characters on Medium, and on High the characters
keep the accent lights' coloured rim light (without it, in Spire's cyan
corridor they turned grey).

## Looks

| Change | Where |
|---|---|
| AgX tonemapper instead of Filmic: bright cyan and orange keep their colour instead of clipping to white | the three maps and both map builders |
| `glow_bloom` 0: only emissives past the HDR threshold glow; the whole frame no longer hazes | same |
| Debanding | `project.godot` |
| Specular anti-aliasing: roughness raised where the normal map varies within a texel (less shimmer at 0.6 render scale), baked at import | the ORM / metal-rough textures of the kit, characters and weapons |
| Anti-aliasing setting: Auto (the preset's) / Off / FXAA / MSAA 2× / MSAA 4× | `Settings.anti_aliasing_for`, Video tab |
| Phone Medium uses 2× MSAA on Auto (tile-based GPUs resolve it in tile memory). The adaptive governor's first step-down turns it off, before render scale, so a phone that can't afford it loses it after 30 s of slow frames or on thermal pressure. A mode the player picked stays | `Settings.MOBILE_EXTRAS`, `AdaptiveQuality.step_down` |
| Blob shadows under characters when realtime shadows are off (Low, phone Medium) | `BlobShadows`: one MultiMesh draw, a floor ray per character, fading with height; compiled in the warm-up |

## Download and memory

| Change | Where |
|---|---|
| A match no longer preloads the legacy rigs (UBC, UAL, Quaternius, Kenney); the selectable characters' clips are baked | `MatchPreload.paths` |
| Release presets leave out the legacy character art, the kit's glTF sources and the lighting test map (Android Test keeps everything) | `export_presets.cfg`; SkinnedRig loads its art lazily so the exclusion can't break compilation |
| Web: desktop texture formats only (the README already says desktop browsers) | Web preset |
| Menus and the lobby at 30 fps on phones; matches restore the cap | `Settings.set_menu_mode` |

**Export size** (`--export-pack`, before → after): Linux 121 → 82 MB,
Android 121 → 82 MB, Web 211 → 82 MB. Most of it is the character
textures at 1024² (about 34 MB per pack); the legacy art is about 5 MB; the
web pack also drops its duplicate mobile texture formats. The exported
Linux release build plays a bot match on each map with no missing files
or script errors (warm-up 0.5–0.7 s).

## On the phone

1. Mi 11X, Medium, 16 combatants: a 20-minute combat soak (m4.md setup),
   comparing PERF `gpu_p50`/`gpu_p95` and the hitch count with m4.md.
2. MSAA against FXAA on Adreno: launch with
   `--play --autopilot --aa-bench --perf-log --aa-bench-quit` (AaBench).
   After 20 s it runs each anti-aliasing mode for 20 s, twice, with the
   adaptive governor held still, and logs one `AA_BENCH` line per mode
   (GPU and frame p50/p95). Phone Medium now defaults to MSAA 2×, with
   the governor as a safety net. If the bench shows MSAA 2× costing much
   more than FXAA did (0.5 ms, m4.md), remove `"msaa": 1` from
   `Settings.MOBILE_EXTRAS`. The run works end to end here on software
   Vulkan, but those numbers say nothing about a phone GPU, and no
   on-device run has been made yet.
3. Check that the blob shadows read well at the phone's brightness, and
   the AgX grade on the phone's panel.

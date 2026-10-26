# Rendering, assets and size pass (2026-10-26)

The GPU, asset and download items from the performance review that followed
characters-main-thread.md. Nothing here could be measured on a phone yet:
the container this was done in has no GPU. Changes were checked by
rendering with the game's own Mobile renderer on Mesa lavapipe (software
Vulkan), before and after, from the same views, plus tests. The on-device
check is listed at the end.

## GPU work

Both mesh changes are made from the shipped assets rather than stored as
new ones (this branch couldn't upload Git LFS objects): the map material
fixes when a map loads (`MapMaterials`, a few milliseconds, cached), the
weapon stand-ins by the weapon models' import script.

| Change | Where | Effect |
|---|---|---|
| Reflection probe off on phone Medium | `Settings.MOBILE_EXTRAS` (previous commit) | ~0.9 ms GPU on the Mi 11X (m4.md) |
| Triplanar → planar UVs on map panels | `MapMaterials`, as the map loads | 1 texture fetch per pixel instead of 3 on 13 Station surfaces and the slabs, walls and cover of Spire and Foundry. Every converted face is axis-aligned, so the image is unchanged; geometry and lightmap UVs are untouched, so no rebake |
| Back-face culling on 5 kit materials | same | crates (~50k triangles per map), floor trims, trims, cables, decals; MI_Trim_01/02 stay double-sided (below) |
| Weapon stand-ins past 5 m | `tools/weapon_import.gd` (the weapons' import script), `WeaponModels.FAR_RANGE` | other players' guns and pickups: 6–8k → ~1k triangles each; same material and vertex format, so no new pipelines |
| Character textures 2048² → 1024² | `.import` size limits | ¼ of the VRAM for the 12 character textures (the in-game mesh already has LODs down to 4–5k triangles) |
| Baked accent lights off moving things on phones | `RenderLayers` | characters, weapons, the first-person arms, pickups and flags take the accents from the lightmap probes instead of a real-time omni pass where effect lights are off (Low, Medium); desktops keep the coloured rim light |
| CTF flag light only with effect lights | `FlagVisuals` | no moving omni (and its pipeline compiles) on phones |
| Nameplates in 2D | `Nameplates` | about 4 draw calls per player (text, outline, bar, team mark) → a few for all of them; still hidden behind walls (a line-of-sight ray per player every 0.1 s) and faded past 30 m |

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
2. 2× MSAA instead of nothing on Adreno: launch with
   `--quality medium,msaa=1` and compare `gpu_p95` and edges against
   `--quality medium` (FXAA cost 0.5 ms in m4.md).
3. Check that the blob shadows read well at the phone's brightness, and
   the AgX grade on the phone's panel.

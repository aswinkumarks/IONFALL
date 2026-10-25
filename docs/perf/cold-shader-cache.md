# Cold shader cache: first-match freeze and join deadlock (2026-10-25)

Report: the Linux build "gets stuck" joining an online game. Reproduced on two
machines with a cold driver cache (`MESA_SHADER_CACHE_DISABLE=true`, fresh
`XDG_CACHE_HOME` and `XDG_DATA_HOME`: a fresh install or a driver update):

| Machine | v0.9.2 cold join | Cause |
|---|---|---|
| Intel Iris Xe (ANV), 8 pool threads | the lobby frozen on screen for 25-40 s, then playable | one frame compiling every pipeline the map and the warm-up set draw |
| AMD Renoir (RADV), 6 pool threads | frozen for good (4 of 4 runs, LAN and online, over 4 min, about 2% CPU) | engine deadlock, below |

**Deadlock** ([godotengine/godot#123060](https://github.com/godotengine/godot/issues/123060),
fixed for 4.8 by [#123312](https://github.com/godotengine/godot/pull/123312), not yet in a
4.7.x release). The official templates are stripped, so frames were labelled by the error
strings near their return addresses:

- main thread: GDScript `load()` → `ArrayMesh::_set_surfaces` → Forward Mobile
  `ShaderData::set_code` → `ShaderRD::version_set_code` →
  `WorkerThreadPool::wait_for_group_task_completion`, holding
  `SceneShaderForwardMobile::singleton_mutex`;
- every pool thread: `ShaderData::_create_pipeline`, waiting for that mutex.

A load that compiles a shader the baker didn't cover waits for a compile queued behind
pipeline compiles, and those wait for the lock the load holds. A cold client goes
menu → lobby → match within seconds of launch, so the menu backdrop's pipelines are still
compiling when the match loads the map. Reproduced on the Iris Xe laptop with an
`override.cfg` (`threading/worker_pool/max_threads=3`) and `taskset -c 0,1`: v0.9.2 hung
2 of 2 cold LAN joins and a cold offline start.

**Changes**

- Loading screen (`ui/match/loading_cover.gd`): put up by the menu or lobby before the
  scene change and taken over by the match, so a long frame shows it rather than a frozen
  lobby. It shows the map art, the mode, a progress bar, a spinner and tips, plus a
  first-run note when frames are slow.
- `MatchPreload`: behind the cover, with the menu's 3D off, it waits until the worker pool
  runs a posted no-op within 3 ms, then loads the match's mesh files one at a time (the
  map's pieces, then the map, weapons and characters). The match then finds them in the
  resource cache.
- `Warmup`: the map and the warm-up set are held on render layer 20 and shown a few
  materials per frame under an overhead orthographic camera, so the whole map is drawn
  (only what is in view compiles), not just what the start view sees. Batches
  double while frames stay under 250 ms, so a warm cache finishes in a few frames. The set
  then stays, hidden, until the match ends: freeing it right away froze the first frame of
  play for 8-15 s on a cold cache (not a pipeline the monitors count, just two workers
  compiling). Looking around from spawn points or turning the reflection probe off didn't
  change that freeze; keeping the set did (3 of 3 runs).
- Hitch log: uses the wall-clock frame time, since the engine clamps `delta` at about
  150 ms.

**Results** (Iris Xe, release export)

| Run | v0.9.2 | This change |
|---|---|---|
| Cold LAN join, 3-thread repro | hung (2 of 2) | playable after 45 s of loading screen (3 of 3) |
| Cold offline start, 3-thread repro | hung | playable after 26-33 s (2 of 2) |
| Cold join, default pool | lobby frozen 25-40 s, then a 9-15 s freeze in play | loading screen (longest frame about 9 s, behind it); no frame over 3 s once playing |
| Warm start, launch to playable | 3.5-3.6 s | 3.4-3.7 s |

Once a Godot 4.7.x release includes #123312, the preload is only a safety net. Keep it
until the RADV machine passes a cold join on the new engine.

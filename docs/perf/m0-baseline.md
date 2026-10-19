# M0 device baseline (2026-10-19)

Build `0.0.1`, versionCode 100, signed release AAB installed via bundletool.

| Device | OS | Renderer | Scene | FPS | Frame ms p50 / p95 / p99 | Draw calls | Primitives | Video mem |
|---|---|---|---|---|---|---|---|---|
| Xiaomi Mi 11X (M2012K11AI, Adreno 650) | Android 13 (API 33) | Vulkan 1.1.128, Forward Mobile | Main menu | 60 | 16.7 / 16.7 / 18.7 | 12 | 660 | 39 MiB |

Notes:
- Capped at 60 fps by vsync even though the display runs at 120 Hz; the fps-cap setting (PLAN §3.10) isn't wired up yet.
- Android 16 KB-page emulator (API 36): installs and starts; rendering can't be verified on the VNC dev desktop (see `docs/toolchain.md`).

## M1a test arena (2026-10-19)

| Device | Scene | FPS | Frame ms p50 / p95 / p99 | Draw calls | Primitives | Video mem |
|---|---|---|---|---|---|---|
| Mi 11X (Adreno 650) | Test arena, 3 dummies, moving + firing, sun shadows + glow | 60 | 16.7 / 16.7 / 16.7 | 56 | 1,714 | 125 MiB |

Release build, Mobile renderer, native resolution (render scale not applied yet), 60 fps vsync cap.

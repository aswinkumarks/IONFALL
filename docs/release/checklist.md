# v1.0 release checklist (M5 + M6)

Status as of 2026-10-23. ✅ done · ⏳ in progress · 👤 needs the owner
(accounts, hardware or decisions only the owner can make).

## M5: server & online readiness

| Item | Status |
|---|---|
| Exported Linux + Windows dedicated server; CI boots it on every map × mode | ✅ CI smoke test loops station/spire/foundry × ffa/tdm/ctf/waves |
| Graceful shutdown (players told "The server was shut down") | ✅ stop file + `ionfall_server.sh` (Ctrl+C/SIGTERM) / `stop_server.bat`; verified with test clients |
| Server guide shipped with the server builds | ✅ `docs/server.md` → `README.md` in both server folders |
| 16 test clients, 60 min, within tick/bandwidth budgets | ✅ PASS: 16/16 for 60 min, tick p99 4.4 ms (median window), 96 MiB, 0 visible corrections; `docs/perf/m5.md` |
| Fuzz tests: decoders, snapshots, beacons, lobby, handshakes, ingress floods | ✅ `tests/unit/test_fuzz.gd` (+ the existing server message fuzz) |
| Lobby → match → lobby cycles hold for 30 min (online) | ✅ 21 cycles in 30 min, 0 failures (after adding handover retries: an Epic stall had failed 1 reconnect in 14 earlier); `docs/online.md` |
| EOS credentials from CI secrets for release builds | ✅ secrets set; CI run 39772215576 logs "EOS credentials written: online play enabled" |
| Phone on **mobile data** hosts and joins online | ✅ Mi 11X on LTE (Wi-Fi off, adb over USB) with the laptop on home broadband: phone hosts → laptop joins, and laptop hosts → phone joins; lobby → match → results → same lobby, twice each way. RTT ~180–200 ms, 0 visible corrections; phone host 60 fps, tick p99 1.7 ms |
| **Windows** build hosts and joins online | 👤 needs a Windows PC |

## M6: v1.0 release

| Item | Status |
|---|---|
| Accessibility list (PLAN §3.16) | ✅ remapping, hold/toggle, sensitivities, invert Y, FOV, HUD scale, captions, damage/gunfire indicators, volumes, shake/vignette, **team shapes** (◆ cyan / ▲ orange on nameplates and scores), **reduce flashes** |
| Pseudolocalization pass (`--pseudoloc`) | ✅ every screen checked; fixed untranslated HUD labels and weapon tags, card text fitting, lobby overflow |
| Intel Iris Xe laptop (Medium, 1080p, 8 combatants, p95 ≤ 16.7 ms, 20 min) | ✅ 60 fps, p95 16.7 ms for 21 min on Medium; High also holds 60 fps (`docs/perf/m6.md`) |
| Min-spec Android phone | 👤 none on hand → no min-spec claims in the store listing (PLAN §3.10) |
| Dedicated-GPU PC | 👤 none on hand → no high-refresh claims |
| Version 1.0.0 (versionCode 1000000 + build) | ✅ `project.godot`; tag `v1.0.0-rc1` |
| Desktop release builds (Linux, Windows) | ✅ `tools/package_release.sh` → `build/release/ionfall-1.0.0-{linux,windows,server-linux,server-windows}.zip` + `SHA256SUMS`, with online play; Linux package smoke-tested. CI built everything for `v1.0.0-rc1` but its upload hit the Actions storage quota. 👤 decide where to publish (GitHub release, itch.io, …) |
| Signed release AAB with all 16 KB checks | ✅ `tools/android_release.sh`: 1.0.0 (code 1000000), 56 MB, ELF + ZIP 16 KB checks pass, upload-key signature verified. **Runtime:** the same build as an x86_64 test APK on the Android 16 16 KB-page emulator (`getconf PAGE_SIZE` = 16384): Godot and EOS libraries load, engine starts, app stays up |
| App icon, adaptive icons, feature graphic, screenshots | ✅ `docs/release/art/`: icon 512, feature graphic 1024×500, four 1920×1080 screenshots (home, single player, match, lobby) |
| Store listing text, content-rating answers | ✅ draft: `docs/release/store-listing.md` |
| Data flows review (Data Safety) | ✅ `docs/release/data-safety.md` |
| Privacy policy | ✅ text: `docs/release/privacy-policy.md`; 👤 fill in publisher/contact; the repo is public now, so it can then be published on the GitHub Pages site |
| Credits for third-party assets (CC BY icons need visible credit) | ✅ Settings → About lists every asset group with its license |
| Epic: developer terms reviewed, Epic named as processor | 👤 review Epic's terms; privacy policy and Data Safety already name Epic |
| Name/trademark check for "IONFALL" (PLAN §8) | 👤 |
| Play Console: app created, closed testing track (12 testers × 14 days if required), Data Safety form, content rating, listing | 👤 |

## What only the owner can do (in order)

1. **Windows test:** the CI Windows build hosts and joins an internet game.
2. **Privacy policy:** fill in publisher and contact in
   `docs/release/privacy-policy.md`; it can then go on the public GitHub Pages site.
3. **Epic terms** and a **name check** for "IONFALL".
4. **Play Console:** create the app (`io.github.aswinkumarks.ionfall`),
   upload `build/android/ionfall.aab` to **closed testing**, fill in the
   listing (`store-listing.md`, `art/`), Data Safety (`data-safety.md`),
   content rating and target audience; 12 testers for 14 days if Play asks.
5. After closed testing: promote to production, tag `v1.0.0`.

# v1.0 release checklist (M5 + M6)

Status as of 2026-10-22. ✅ done · ⏳ in progress · 👤 needs the owner
(accounts, hardware or decisions only the owner can make).

## M5: server & online readiness

| Item | Status |
|---|---|
| Exported Linux + Windows dedicated server; CI boots it on every map × mode | ✅ CI smoke test loops station/spire × ffa/tdm |
| Graceful shutdown (players told "The server was shut down") | ✅ stop file + `ionfall_server.sh` (Ctrl+C/SIGTERM) / `stop_server.bat`; verified with test clients |
| Server guide shipped with the server builds | ✅ `docs/server.md` → `README.md` in both server folders |
| 16 test clients, 60 min, within tick/bandwidth budgets | ✅ PASS: 16/16 for 60 min, tick p99 4.4 ms (median window), 96 MiB, 0 visible corrections; `docs/perf/m5.md` |
| Fuzz tests: decoders, snapshots, beacons, lobby, handshakes, ingress floods | ✅ `tests/unit/test_fuzz.gd` (+ the existing server message fuzz) |
| Lobby → match → lobby cycles hold for 30 min (online) | ✅ 21 cycles in 30 min, 0 failures (after adding handover retries: an Epic stall had failed 1 reconnect in 14 earlier); `docs/online.md` |
| EOS credentials from CI secrets for release builds | ✅ CI step; 👤 add the five `EOS_*` repository secrets |
| Phone on **mobile data** hosts and joins online | 👤 needs the phone off Wi-Fi |
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
| Privacy policy | ✅ text: `docs/release/privacy-policy.md`; 👤 publish at a public URL (the repo is private) and fill in publisher/contact |
| Epic: developer terms reviewed, Epic named as processor | 👤 review Epic's terms; privacy policy and Data Safety already name Epic |
| Name/trademark check for "IONFALL" (PLAN §8) | 👤 |
| Play Console: app created, closed testing track (12 testers × 14 days if required), Data Safety form, content rating, listing | 👤 |

## What only the owner can do (in order)

1. **EOS secrets** in GitHub (Settings → Secrets → Actions): `EOS_PRODUCT_ID`,
   `EOS_SANDBOX_ID`, `EOS_DEPLOYMENT_ID`, `EOS_CLIENT_ID`, `EOS_CLIENT_SECRET`
   (values from `eos_credentials.cfg`), so CI release builds include online
   play. From this machine: `gh secret set EOS_CLIENT_SECRET` (it prompts for
   the value), and the same for the other four.
2. **Mobile data test:** phone on mobile data (Wi-Fi off) hosts an internet
   game and joins one hosted by the laptop.
3. **Windows test:** the CI Windows build hosts and joins an internet game.
4. **Privacy policy:** fill in publisher and contact in
   `docs/release/privacy-policy.md` and publish it at a public URL.
5. **Epic terms** and a **name check** for "IONFALL".
6. **Play Console:** create the app (`io.github.aswinkumarks.ionfall`),
   upload `build/android/ionfall.aab` to **closed testing**, fill in the
   listing (`store-listing.md`, `art/`), Data Safety (`data-safety.md`),
   content rating and target audience; 12 testers for 14 days if Play asks.
7. After closed testing: promote to production, tag `v1.0.0`.

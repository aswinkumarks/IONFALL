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
| Lobby → match → lobby cycles hold for 30 min (online) | ⏳ |
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
| Version 1.0.0 (versionCode 1000000 + build) | ⏳ at tagging |
| Desktop release builds (Linux, Windows) | ⏳ CI on the `v1.0.0` tag; 👤 approve publishing a GitHub release |
| Signed release AAB with all 16 KB checks | ⏳ `tools/android_install.sh` (upload key in `~/.local/share/ionfall-keys/`) |
| App icon, adaptive icons, feature graphic, screenshots | ✅ icon and feature graphic (`tools/store_art.tscn`); ⏳ screenshots |
| Store listing text, content-rating answers | ✅ draft: `docs/release/store-listing.md` |
| Data flows review (Data Safety) | ✅ `docs/release/data-safety.md` |
| Privacy policy | ✅ text: `docs/release/privacy-policy.md`; 👤 publish at a public URL (the repo is private) and fill in publisher/contact |
| Epic: developer terms reviewed, Epic named as processor | 👤 review Epic's terms; privacy policy and Data Safety already name Epic |
| Name/trademark check for "IONFALL" (PLAN §8) | 👤 |
| Play Console: app created, closed testing track (12 testers × 14 days if required), Data Safety form, content rating, listing | 👤 |

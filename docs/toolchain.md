# Toolchain (pinned)

Every version here is pinned (PLAN §3.18). Change one only on a branch, then re-run the full test suite before merging. Never change engine versions mid-milestone.

| Component | Version | Source / notes |
|---|---|---|
| Godot editor | **4.7.2-stable** (`4.7.2.stable.official.ed1daf0bf`) | `Godot_v4.7.2-stable_linux.x86_64.zip`, SHA-512 verified against the release's `SHA512-SUMS.txt` |
| Export templates | 4.7.2.stable | `Godot_v4.7.2-stable_export_templates.tpz`, SHA-512 verified |
| Physics backend | Jolt Physics (built into 4.7) | `physics/3d/physics_engine`; see `docs/decisions/0001-physics-backend.md` |
| JDK | Temurin 17.0.20.1+1 | Godot 4.7.2's Android build uses Java 17 (`config.gradle`: `javaVersion`) |
| Android compile/target SDK | 36 | From Godot 4.7.2 `platform/android/java/app/config.gradle` |
| Android min SDK | 29 | Godot's Vulkan default (`VULKAN_MIN_SDK_VERSION`) |
| Android build-tools | 36.1.0 | Same `config.gradle` |
| Android NDK | 29.0.14206865 | Same `config.gradle`; also provides `llvm-readelf` for the 16 KB checks |
| Android cmdline-tools | 16111833 | SHA-1 verified against Google's `repository2-3.xml` |
| bundletool | 1.18.3 | 16 KB ZIP-alignment check (`tools/check_16kb.sh`) |
| GUT (unit tests) | 9.7.1 | Vendored in `addons/gut` |
| godot-cpp (native extension) | `godot-4.5-stable` (`e83fd09`) | Fetched by `native/build.sh`; 4.5 bindings load in 4.7.2. Not part of release builds yet (`docs/perf/hitbox-rewind-native.md`) |
| SCons | 4.x | `pip install scons`, only for `native/build.sh` |
| Python | 3.10+ | Build tooling in `tools/` |

## Local install layout (Linux dev machine)

| Path | Contents |
|---|---|
| `~/.local/bin/godot` | Symlink to the pinned editor |
| `~/.local/share/ionfall-toolchain/` | Godot editor, JDK 17, bundletool, verified downloads |
| `~/.local/share/godot/export_templates/4.7.2.stable/` | Export templates |
| `~/Android/Sdk/` | Android SDK (`cmdline-tools/latest`, platform, build-tools, NDK) |
| `~/.local/share/ionfall-keys/` | **Upload keystore + passwords. Never in the repo.** Back up to a password manager and an encrypted offline copy |

## Common commands

```bash
godot --headless --import                                              # import assets
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json   # unit tests
python3 tools/check_layers.py                                          # simulation/presentation split
python3 tools/write_build_info.py --platform linux --arch x86_64 --config release
godot --headless --export-release "Linux" build/linux/ionfall.x86_64

# Dedicated server
godot --headless --export-release "Linux" build/linux/ionfall.x86_64
build/linux/ionfall.x86_64 --headless -- --server --smoke-test

# Signed release AAB for Play, with the 16 KB checks (no install):
#   tools/android_release.sh
# Signed release AAB (loads the upload key from outside the repo)
set -a; source ~/.local/share/ionfall-keys/upload-key.env; set +a
godot --headless --export-release "Android" build/android/ionfall.aab
tools/check_16kb.sh build/android/ionfall.aab
```

## Installing on the Mi 11X (wireless debugging)

1. Phone: Developer options → **Wireless debugging** on, **Install via USB** on (MIUI requires it even for wireless installs).
2. Wireless debugging → *Pair device with pairing code*, then on the PC: `adb pair <ip>:<pairing-port> <code>` (once per PC).
3. Connect: `adb mdns services` shows the `_adb-tls-connect` address; `adb connect <ip>:<port>`.
4. Install the signed release AAB with one command: `tools/android_install.sh` (exports, signs with the upload key, installs and launches; `--no-export` reuses the last AAB). Manual equivalent:
   ```bash
   set -a; source ~/.local/share/ionfall-keys/upload-key.env; set +a
   PF=$(mktemp); chmod 600 $PF; printf '%s' "$GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD" > $PF
   java -jar ~/.local/share/ionfall-toolchain/bundletool.jar build-apks --bundle=build/android/ionfall.aab \
     --output=build/android/ionfall.apks --connected-device --device-id=<ip>:<port> \
     --ks="$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" --ks-key-alias="$GODOT_ANDROID_KEYSTORE_RELEASE_USER" \
     --ks-pass=file:$PF --key-pass=file:$PF; rm -f $PF
   java -jar ~/.local/share/ionfall-toolchain/bundletool.jar install-apks --apks=build/android/ionfall.apks --device-id=<ip>:<port>
   ```
   Approve MIUI's install prompt on the phone. `INSTALL_FAILED_USER_RESTRICTED` means the prompt was declined or "Install via USB" is off.
5. If the adb server restarts, the wireless connection drops: re-run step 3 (no re-pairing needed). Godot kills adb after every export unless the editor setting `export/android/shutdown_adb_on_exit` is `false` (set on this machine).

## Android emulator (16 KB runtime check)

- AVD `ionfall_api36_16k`: `system-images;android-36;google_apis_ps16k;x86_64` (Android 16, 16 KB pages, `PAGE_SIZE=16384`), Pixel 7 profile (2400×1080). Uses the **Android Test** build (includes x86_64).
- Start: `~/Android/Sdk/emulator/emulator -avd ionfall_api36_16k -no-snapshot -gpu swiftshader_indirect`
- **What it verifies:** the signed APK installs, its native libraries load on a 16 KB-page kernel, and Godot's main loop starts. That's the 16 KB runtime check (PLAN §3.18).
- **What it can't verify on this dev machine:** rendering. The desktop runs over TigerVNC, so:
  - `-gpu host` crashes the emulator (`kvm run failed Bad address`) when Vulkan starts.
  - `-gpu swiftshader_indirect` + Vulkan: Godot starts, then stalls after `Couldn't present to Vulkan queue`.
  - SwiftShader + OpenGL: Godot's scene shader exceeds `GL_MAX_FRAGMENT_UNIFORM_VECTORS (261)`.
  Visual checks need a real device (Mi 11X), or possibly `-gpu host` from a local (non-VNC) desktop session.
- Release builds ignore the `command_line_params` launch extra, so renderer overrides can't be passed at launch.

## Compatibility (OpenGL) fallback on Android

- `rendering/rendering_device/fallback_to_opengl3=true`: on a device without usable Vulkan, Godot switches the Mobile renderer to Compatibility (OpenGL ES 3.0) instead of failing to start. `Settings.default_quality()` then starts on **Low**, as in browsers.
- Verified 2026-10-23 on the emulator with Vulkan disabled (`-feature -Vulkan -gpu swiftshader_indirect`): logcat shows "Your device does not seem to support Vulkan, switching to OpenGL 3" and the game runs on OpenGL ES 3.0. SwiftShader's uniform limits (261 fragment / 256 vertex vectors, close to the ES 3.0 minimum) are below what Godot's own scene, sky, canvas and particle shaders need, so the picture stays white there; lowering `limits/opengl/max_lights_per_object` doesn't change that.
- The same renderer is exercised by the web build and by desktop runs with `--rendering-method gl_compatibility --rendering-driver opengl3` (both maps render at 60 fps on Iris Xe). A real non-Vulkan phone is still untested (no such device on hand).

## Known engine quirks

- **Dedicated-server exports and CSV translations:** with the `customized` / `strip` export mode, Godot 4.7.2 logs "Failed loading resource: res://locale/strings.csv" (multi-locale CSV imports have no single import path). Server presets therefore exclude `locale/*`, and `project.godot` sets `locale/translations.dedicated_server` to an empty list.
- **First import on a fresh checkout** logs `Cannot open file 'res://locale/strings.en.translation'`. `project.godot` references the translation that the CSV import generates (it's gitignored as a build artifact), so the very first project load can't find it yet. It's harmless: the import creates it, and every later load is clean.
- **ENet server bandwidth bug:** `ENetMultiplayerPeer.create_server(port, peers, channels)` passes `channels` as the incoming bandwidth limit, so clients throttle their unreliable packets. `Transport.host()` calls `peer.host.bandwidth_limit(0, 0)` right after creating the server. See decision 0002.
- **New `class_name` scripts** aren't visible to command-line runs until the global class cache is refreshed: run `godot --headless --import` after adding one.
- **Automated runs over VNC with a free cursor** (spectator mode, menus): when the Godot window doesn't hold the pointer, Vulkan's vsync present can block for good and the game stops at 0% CPU. Pass `--disable-vsync` for such `--ui`/`--shot` runs; captured-mouse gameplay runs aren't affected. Also, stdout is block-buffered when redirected and lost when `timeout` kills Godot: print debug lines with `printerr`.
- **Android launch arguments:** exported activities drop intent command-line extras, so device-only checks are started from the diagnostics overlay (F3 / three-finger tap), e.g. the replay check. Results go to `adb logcat -s godot`.

## Multiplayer testing

```bash
godot -- --host                          # PC: host from the menu flow
godot -- --join 192.168.0.9 --name Alice # PC: join a host
godot --headless -- --server --bots 2    # dedicated server (port 47710)
godot --headless -- --test-clients 8 --join 127.0.0.1 --duration 600
godot --headless -- --replay-check > linux.log   # then compare:
tools/compare_replay.py linux.log android.log    # android.log from adb logcat
```

On the phone: Join Game, type the host's address (shown at the bottom of the
host's screen). The overlay's NET rows show RTT, interpolation, time
dilation, prediction lead, bandwidth and corrections.

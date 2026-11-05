# Logging

Every run writes a session log: timestamped, tagged lines in one file per
session. The game keeps the last 10 sessions. A session that ended normally
finishes with `=== session end`. When it doesn't, the next start logs a
warning that names the file, so a crash or kill can be told apart from a
normal close.

```
13:04:19.415 +16.478 INFO  [server] Pilot730 loaded: player 3 enters (rtt 100 ms)
```

Each line has the wall clock, the seconds since start, the level, the
subsystem and the message.

## Where the logs are

| Platform | Folder |
|---|---|
| Linux | `~/.local/share/godot/app_userdata/IONFALL/logs/` |
| Windows | `%APPDATA%\Godot\app_userdata\IONFALL\logs\` |
| macOS | `~/Library/Application Support/Godot/app_userdata/IONFALL/logs/` |
| Android | `Android/data/io.github.aswinkumarks.ionfall/files/logs/` (USB file transfer, or `adb pull /storage/emulated/0/Android/data/io.github.aswinkumarks.ionfall/files/logs`) |

There are two more ways to get them:

- **The diagnostics screen** (F3 on desktop, a three-finger tap on touch): shows this session's log file. **Copy log** puts this session's log on the clipboard, along with the previous one if it didn't close normally. **Open log folder** opens the folder (desktop only).
- **Editor runs:** `godot.log` sits next to the session logs. It is the engine's own log and includes lines from before the game's scripts start.

## What's in a log

- **Session header (`sys`):** build and commit, debug or release, OS, device, CPU, RAM, GPU (integrated or dedicated), driver, renderer, display, command-line arguments and all settings.
- **Engine output (`engine`):** every `print`, warning and error, including engine and script errors with their GDScript backtraces.
- **Settings (`settings`):** load and save, every change, the applied video state, adaptive quality step-downs and renderer restarts.
- **Scenes and app (`scene`, `app`):** scene changes, focus, pause and resume (Android backgrounding), low-memory warnings and the crash notification.
- **UI (`ui`):** every button press, with its text and node path.
- **Networking (`net`, `lobby`, `client`, `server`):**
  - Hosting and joining, handshakes (accepted or rejected, and why), peers connecting and dropping, and ingress-limit kicks.
  - Lobby joins, leaves, kicks and start.
  - Match phases, players loading and leaving, reconnects, bots and results.
  - Slow server ticks (at most one line every 5 s), prediction snaps and resyncs.
- **Match (`match`):** the match config, map load time, start, connection loss, rejoin attempts and leaving.
- **Simulation (`sim`, debug level):** kills, flags and waves.
- **Online (`online`, `eos`):** sign-in, hosting, the listing, joins, and the EOS SDK's warnings and errors (everything down to Info with `--eos-log`).
- **Profile (`profile`):** load, save, results and XP, and corrupt-save recovery.
- **Performance (`perf`):**
  - A line every minute with fps, frame-time percentiles, GPU and CPU time, draw calls, objects, nodes and memory.
  - The network summary (rtt, bandwidth, corrections).
  - The match's `PERF` line, `HITCH` lines (frames over 50 ms, with their section times and pipeline compilations, capped at 40 per session), and the warm-up time.

## Options

- `--log-level debug|info|warn|error` sets the minimum level. The default is `debug`, which includes the click trail, settings changes and kills.
- Code logs with `Log.d/i/w/e("tag", "message")` (`core/log.gd`). It works from any script, including tools that run without the autoloads; those only print to the console.

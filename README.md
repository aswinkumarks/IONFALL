# IONFALL

A fast sci-fi arena FPS for Android, Linux and Windows: single player against bots, LAN cross-play, and
player-hosted internet games (Epic Online Services). Built with Godot 4.7.2.

- **Plan:** [PLAN.md](PLAN.md) (design, architecture, milestones)
- **Toolchain:** [docs/toolchain.md](docs/toolchain.md) (pinned versions and common commands)
- **Status:** M0–M4 complete, plus internet play, lobby and menu redesign; finishing M5–M6 for v1.0
  ([release checklist](docs/release/checklist.md))
- **Online play:** [docs/online.md](docs/online.md) · **Dedicated server:** [docs/server.md](docs/server.md)

## Quick start

```bash
godot --headless --import
godot --headless -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json   # run tests
godot                                                                  # open the editor
```

Open the project only with Godot **4.7.2-stable**.

## Layout

| Folder | Contents |
|---|---|
| `core/` | Autoload services: Platform, Events, BuildInfo, Settings, Diagnostics |
| `sim/` | Simulation layer (tick-driven, no rendering/audio/UI) |
| `net/` | Networking (`Net` layer, transports, snapshots) |
| `server/` | Dedicated-server bootstrap |
| `presentation/` | Visuals, audio, interpolation |
| `ui/` | Menus, HUD, overlays |
| `tests/` | GUT unit tests |
| `tools/` | Build info, layer check, 16 KB check |

`sim/`, `net/`, `modes/` and `bots/` must never reference presentation code; `tools/check_layers.py` enforces this in CI.

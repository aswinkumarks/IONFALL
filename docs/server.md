# Running IONFALL as a LAN server

The desktop game doubles as a headless server for LAN matches of up to 16
players (PLAN §3.5.2). There's no separate server download any more (since
0.9.2): run the Linux or Windows game build with `--server`. Players find
it in **Join Game** on the same network, or join by the machine's IP
address. Each match restarts on the same map and mode when it ends.
Hosting from the menu does the same with a player at the host, so a server
is only needed for a machine nobody plays on. Internet play doesn't need a
server: players host online games from the game itself (Host Game →
Internet).

## Start

Linux (from the unzipped `ionfall-<version>-linux.zip`):

```sh
./ionfall.x86_64 --headless -- --server --name "Office LAN" --map spire --mode tdm --bots 6
```

Windows (from `ionfall-<version>-windows.zip`; `--headless` keeps the window away):

```bat
IONFALL.exe --headless -- --server --name "Office LAN" --map spire --mode tdm --bots 6
```

| Option | Meaning | Default |
|---|---|---|
| `--name NAME` | shown in players' game lists | `IONFALL server` |
| `--port N` | UDP game port (also allow UDP 47701 for LAN discovery) | `47710` |
| `--map ID` | `station` (Meridian Station), `spire` (Halcyon Spire) or `foundry` (Vesper Foundry) | `station` |
| `--mode ID` | `ffa`, `tdm`, `ctf` or `waves` | `ffa` |
| `--bots N` | bots fill the match up to N combatants and leave as players join | `0` |
| `--bot-difficulty D` | `easy`, `normal`, `hard`, `insane` | `normal` |
| `--friendly-fire` | team damage in TDM | off |
| `--no-discovery` | don't announce the server on the LAN | announce |
| `--status-interval S` | seconds between status lines | `10` |

Status lines (players, bandwidth, tick times, memory) and joins/leaves go to
the console (stderr).

## Stop

Pass `--stop-file PATH`: creating that file shuts the server down
gracefully, and players see "The server was shut down" instead of waiting
for a timeout (for systemd or Docker, touch the file from a stop hook).
Ctrl+C or killing the process also stops the server, but players only
notice when their connection times out.

## Firewall

Allow inbound **UDP 47710** (or your `--port`) for the game and **UDP 47701**
for LAN discovery. Players on guest Wi-Fi or behind access-point isolation
can't reach LAN servers.

## Measured capacity

One match with 16 players on Meridian Station: see `docs/perf/m5.md`.

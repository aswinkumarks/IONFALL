# IONFALL dedicated server

A headless server for LAN matches of up to 16 players (PLAN §3.5.2, v1.0
scope). Players find it in **Join Game** on the same network, or join by
the machine's IP address. Each match restarts on the same map and mode
when it ends. Internet play doesn't need a server: players host online
games from the game itself (Host Game → Internet).

## Start

Linux:

```sh
./ionfall_server.sh --name "Office LAN" --map spire --mode tdm --bots 6
```

Windows:

```bat
ionfall_server.bat --name "Office LAN" --map spire --mode tdm --bots 6
```

| Option | Meaning | Default |
|---|---|---|
| `--name NAME` | shown in players' game lists | `IONFALL server` |
| `--port N` | UDP game port (also allow UDP 47701 for LAN discovery) | `47710` |
| `--map ID` | `station` (Meridian Station), `spire` (Halcyon Spire) or `foundry` (Vesper Foundry) | `station` |
| `--mode ID` | `ffa` or `tdm` | `ffa` |
| `--bots N` | bots fill the match up to N combatants and leave as players join | `0` |
| `--bot-difficulty D` | `easy`, `normal`, `hard`, `insane` | `normal` |
| `--friendly-fire` | team damage in TDM | off |
| `--no-discovery` | don't announce the server on the LAN | announce |
| `--status-interval S` | seconds between status lines | `10` |

Status lines (players, bandwidth, tick times, memory) and joins/leaves go to
the console (stderr).

## Stop

- **Linux:** Ctrl+C, or `kill <launcher pid>` / `systemctl stop` / `docker
  stop`. The launcher turns the signal into a graceful shutdown.
- **Windows:** run `stop_server.bat` in the same folder (or create the file
  `ionfall_server.stop` there).

Players then see "The server was shut down" instead of waiting for a
timeout. Closing the window or killing the process directly also stops the
server, but players only notice when their connection times out.

## Firewall

Allow inbound **UDP 47710** (or your `--port`) for the game and **UDP 47701**
for LAN discovery. Players on guest Wi-Fi or behind access-point isolation
can't reach LAN servers.

## Measured capacity

One match with 16 players on Meridian Station: see `docs/perf/m5.md`.

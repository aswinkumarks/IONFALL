# Online play (Epic Online Services P2P)

Decision: [0005](decisions/0005-internet-play-eos.md). Player-hosted matches
over the internet, no game server of ours. Linux, Windows and Android; not
web or dedicated servers.

## Playing

Home screen: three cards, **Single Player** (map cards, mode and length
chips, Start), **Host Game** and **Join Game**.

- **Host Game** → *Local network* or *Internet* opens a **lobby**. The
  host picks map, mode and length (5–20 min) and sees every player in the
  slot list; **Start match** sends everybody into the match. When the match
  ends (after the results), everyone returns to the same lobby. Without
  the EOS backend, Host opens a LAN lobby directly.
- **Join Game** lists LAN games (beacons) and online games (EOS lobby
  search, this build only, refreshed every 5 s) as cards, green *In lobby*
  or orange *Playing*. A lobby card joins the lobby (settings read-only); a
  *Playing* card joins the match. *Join directly* takes an IP address or an
  invite code (case, spaces and dashes don't matter); it goes to the lobby,
  or straight into the match if the host already started.
- Host caps online: 4 combatants on a phone host, 8 on a PC host (16 on
  LAN; 16 through the EOS relays hasn't been measured).
- The code stops working when the host leaves the lobby or the match.

## Lobby

`net/lobby_session.gd` (`LobbySession`) runs on the match's `Transport`
(same handshake, whitelist and ingress limits). Only the host sends:
`LOBBY` (settings + members) on every change, `START` once. On Start the
host closes the lobby connections and opens the match on the same port or
EOS socket; clients wait 1.5 s, then connect to it (online: straight to the
host's product user ID, no new search). A client whose lobby connection
reaches a running match (a `WELCOME`) joins that match instead. When a
lobby match's results have been shown, the host sends `NOTICE
RETURN_TO_LOBBY`, closes the match and reopens the lobby (same port, or
the same online game and code); clients wait 1.5 s and reconnect. Online, the
EOS lobby's attributes (name, map, mode, players, max, state) feed the
browser; LAN lobbies set `Discovery.FLAG_LOBBY` in their beacon.

## How it works

| Step | Code |
|---|---|
| Anonymous sign-in with this device's ID (EOS Connect), once per session | `net/online/eos_backend.gd` `sign_in_async` |
| Host: EOS P2P server peer + a public lobby with the code and `compat_hash` | `host_async` |
| Join: lobby search by code (same build only) → owner's product user ID → P2P client peer | `join_async` |
| The peers plug into `Transport.host_peer` / `join_peer`; handshake, whitelist and ingress limits are the LAN ones | `net/transport.gd` |

`core/online.gd` (autoload `Online`) is the only entry point; the EOS script
is loaded only when the EOSG extension and `eos_credentials.cfg` exist, so
web and dedicated-server builds never touch it.

## Setup (developers)

- `eos_credentials.cfg` at the project root (git-ignored, exported with
  client builds): product, sandbox, deployment and client IDs plus the
  client secret from the Epic Developer Portal (product IONFALL, client
  `ionfall-client`, policy `p2p-client`). Without it online play is hidden.
- The EOSG addon is vendored in `addons/epic-online-services-godot/`; see its
  `VENDORED.md` for local changes. Its Linux libraries are rebuilt to run on
  glibc 2.34+ (Ubuntu 22.04).
- Android: `addons/ionfall_android` adds the EOS AAR and its androidx
  dependencies and patches the generated Gradle project at export (core
  library desugaring, login scheme, `EOSSDK.init`), marked `IONFALL-EOS`.

## Laptop end-to-end test

Two instances on one machine need different EOS device IDs, so each gets its
own `HOME` and `XDG_DATA_HOME`:

```sh
HOME=/tmp/eos-a XDG_DATA_HOME=/tmp/eos-a/data godot --path . -- --host --online --name Host --bots 2
# read "ONLINE hosting with invite code XXXXXX" from its output, then:
HOME=/tmp/eos-b XDG_DATA_HOME=/tmp/eos-b/data godot --path . -- --join XXXXXX --name Joiner --autopilot
```

Add `--headless --no-warmup` to run both without windows. Results on the
Intel Xe laptop, 2026-10-22:

| Check | Result |
|---|---|
| Host signs in, creates the lobby, gets a code | yes (sign-in and lobby in a few seconds) |
| Join by code, windowed and headless | connected; host `clients=1 players=3` |
| Netcode over EOS (3 minutes, same machine) | RTT 49–66 ms, 16–18 corrections (3–4 visible) per minute, client p95 16.7 ms |
| Exported Linux release builds (host and joiner), twice | connected; RTT 49 and 66 ms |
| Joiner starts ~3 s after the host | the new lobby isn't searchable yet; the search retries for up to 10 s, then connects |
| Unknown code | after ~10 s of retries: "No online game with code ABCDEF", back to the menu |
| Host on another build (`compat_hash`) | "That game runs a different version of IONFALL" |
| Host quits | client: "Host disconnected", back to the menu |

`--eos-log` prints the EOS SDK's own log (Info level) for debugging.

**Through the menu UI** (`--ui` sends real mouse and key events; see
`core/diagnostics.gd`; `click:~text` matches part of a label, for game
cards; drawn cards match by their `ui_key` meta): the host clicks through to an online lobby and starts once the
joiner, who picked the game from the list, is in:

```sh
HOME=/tmp/eos-a XDG_DATA_HOME=/tmp/eos-a/data godot --path . -- --ui "wait:6,click:MENU_HOST,click:MENU_HOST_ONLINE,wait:30,click:LOBBY_START,wait:30,shot:/tmp/host.png"
HOME=/tmp/eos-b XDG_DATA_HOME=/tmp/eos-b/data godot --path . -- --ui "wait:6,click:MENU_JOIN,wait:18,click:~Online,wait:40,shot:/tmp/joined.png"
```

(Before the lobby, the same check ran with the old single-page menu:
*Host Online*, then a typed code; host `clients=1`, 59.8 fps.)

**Nested menu and lobby** (2026-10-22, same machine, `--ui`):

| Check | Result |
|---|---|
| LAN: Host Game → LAN lobby; joiner Join Game → clicks the LAN row | in lobby, sees host's map/mode/duration changes live; Start → both in the match (TDM, Halcyon Spire, 15:00 timer), host `clients=1` |
| Online: Host Game → Internet; joiner clicks the Online row | lobby over EOS; Start → match reconnect over EOS, RTT 49 ms, host `clients=1` |
| Online by typed code (`6gn-6sd`), then host leaves the lobby | joined; then "The host closed the lobby", back to the menu |
| Join a host that already started: LAN by address / online *Playing* row | redirected into the match / joined it directly; host `clients=1` |
| Single Player: duration 15 min, Start | offline match with a 15:00 timer |
| Exported Linux release builds: `--lobby --online --autostart 2` and `--join CODE` | lobby → match over EOS, RTT 49 ms |

| Lobby match ends (`--time-limit 20`), LAN and online | results, then host and player back in the same lobby (online: same code); two LAN cycles in a row |

**Phone (Mi 11X, release-template APK) with the laptop**, 2026-10-22, both
on home Wi-Fi, driven by `--ui` through `launch_args.txt`:

| Check | Result |
|---|---|
| Phone hosts online (cap 4), laptop joins from the online list | lobby → match → results → same lobby (code kept) |
| Laptop hosts online, phone joins from its online list | lobby → match → results → same lobby |
| Laptop host quits mid-match | phone: "Host disconnected", back to the menu |
| Laptop host leaves the lobby | phone: "The host closed the lobby" |
| Menu, lobby and game list at 2400×1080 | large cards fit; lobby lists only joined players |

**Phone on mobile data (Mi 11X on LTE, Wi-Fi off, adb over USB) with the
laptop on home broadband**, 2026-10-22, 1.0.0 test APK:

| Check | Result |
|---|---|
| Phone hosts online, laptop joins by code | lobby → match → results → same lobby, then a second match; phone host 60 fps, tick p99 1.7 ms, `clients=1` |
| Laptop hosts online, phone joins by code | lobby → match → results → same lobby, then a second match |
| Latency | RTT 180–200 ms (carrier NAT, likely an Epic relay), 0 visible corrections |

**Long run (2026-10-22, laptop, two headless instances, 60 s matches):**
lobby → match → lobby cycles for 30 min. The first run failed one reconnect
after 13 cycles: Epic's lobby service stalled for a few seconds ("lobby
update: TimedOut" on the host) and the joiner's P2P connection hung until
the timeout. Handover connections (lobby → match and back) now retry up to
5 times, and a hung attempt counts as a failure after 15 s. Re-run: 21
cycles in 30 min, 0 failures. Retry path checked with a host that opens its
lobby 20 s late: the joiner's first attempt fails, the second gets in.

A 0–0 (or tied TDM) result at the time limit goes to sudden death for up
to 2 minutes before the lobby returns; that is the normal tie rule.

Dev flags: `--lobby [--online]` opens a hosted lobby, `--autostart N`
starts it once N players are in; `--host` still goes straight to a match.

The 49–66 ms RTT on one machine suggests the traffic went through Epic's
relays rather than directly; that's the worst case for real players.

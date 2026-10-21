# Online play (Epic Online Services P2P)

Decision: [0005](decisions/0005-internet-play-eos.md). Player-hosted matches
over the internet, no game server of ours. Linux, Windows and Android; not
web or dedicated servers.

## Playing

- **Host Online** (main menu) starts a match like *Host Game* and shows an
  invite code, e.g. `KFS7WQ`, in the status line and the pause menu.
- Friends open **Join**, type the code in the address field (case, spaces
  and dashes don't matter) and connect. IP addresses still join LAN games.
- Host caps are unchanged: 4 combatants on a phone host, 8 on a PC host.
- The code stops working when the host leaves the match.

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

The 49–66 ms RTT on one machine suggests the traffic went through Epic's
relays rather than directly; that's the worst case for real players.

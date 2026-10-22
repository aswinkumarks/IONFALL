# Data flows review (Play Data Safety, PLAN §3.18)

Reviewed against the v1.0 code on 2026-10-22. IONFALL has no accounts of
its own, no analytics, ads, crash reporting or HTTP requests. Everything
that leaves the device is listed here.

## What leaves the device

| Data | Sent to | When | Code |
|---|---|---|---|
| Player name (chosen by the player, 3–16 characters), character and colour picks | Other players in the same match (host and clients) | Joining a LAN or online game | `Protocol.encode_hello`, roster |
| Per-install random ID (`profile/uuid`, 16 hex characters; not derived from the device) | The host of a match | Joining | `MatchConfig.profile_uuid` |
| Host's game name ("Name's game"), map, mode, player count | Everyone on the local network (UDP broadcast) | Hosting on LAN | `Discovery` |
| Gameplay traffic (movement, shots) | The host / other players, directly or through Epic relays | Playing | `Transport` |
| **Epic Online Services** (internet play only): an anonymous device credential created by the EOS SDK, the device model string (e.g. "Android M2012K11AI"), the player name as display name, and the resulting EOS product user ID | Epic Games (service provider) | Signing in to play online (first use of Host → Internet or Join Game) | `net/online/eos_backend.gd` |
| EOS lobby attributes: invite code, game name, map, mode, player count, build compatibility hash | Epic Games; visible to every IONFALL player browsing online games | Hosting online | `host_async`, `update_async` |
| IP address | Epic (sign-in, relays); other players on direct P2P or LAN connections | Online / LAN play | network layer |

## What stays on the device

Profile (name, level, XP, stats, unlocks), settings, last joined address,
match results. Stored in the app's private storage; removed when the app is
uninstalled. The diagnostics overlay and `--perf-log` (dev builds) write
only locally.

## Play Data Safety answers (proposed)

- **Data collected:** yes, because of internet play through Epic:
  - *Device or other IDs*: the EOS device credential and product user ID.
    Purpose: app functionality (online play). Not shared for advertising.
    Collected only when the player uses internet play.
  - *App activity → Other user-generated content* (or *Personal info →
    other info*, see note): the player-chosen name sent to Epic as a
    display name and shown in lobbies. Purpose: app functionality.
  - Processed by **Epic Games as a service provider**: per Play's
    definitions, transfers to a service provider are not "sharing".
- **Encrypted in transit:** yes for Epic (TLS to Epic services; EOS P2P
  encryption). LAN play goes directly between players' devices on the local
  network and is not collected by us.
- **Optional:** internet play is optional; LAN and single player send
  nothing to Epic.
- **Deletion:** no account is created by the player. The EOS device
  credential is anonymous and tied to the install; uninstalling removes the
  local credential. Document in the privacy policy how to ask for deletion
  of EOS data (Epic's process).

Note: the name is a gamer tag chosen in-game, not the person's real name;
whether Play classes it as "Name" or "User-generated content" is the
publisher's call when filling in the form.

## Before submitting

- Re-run this review if any SDK, HTTP call or new data field is added.
- The privacy policy (`privacy-policy.md`) must match this table.

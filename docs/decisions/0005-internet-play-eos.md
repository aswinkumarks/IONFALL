# 0005: Internet play: player-hosted matches over Epic Online Services P2P

- **Status:** accepted and implemented (2026-10-22); see [docs/online.md](../online.md)
- **Context:** PLAN §3.8 planned internet play as public dedicated servers
  behind our own accounts backend (O1–O2). The owner wants internet play
  without running any game server: players host, as on LAN.

## Options considered

| Option | Server needed | Web | Notes |
|---|---|---|---|
| VPN overlay (Tailscale/ZeroTier) | none | no | no code; every player installs a VPN |
| UPnP + IPv6 + join codes | none | no | fails behind carrier NAT (most mobile data) |
| UDP hole punching | rendezvous | no | fails on symmetric NAT |
| **EOS P2P (chosen now)** | Epic's (free) | **no** | NAT traversal + relay fallback, lobbies, anonymous device-ID login |
| WebRTC everywhere | signaling + TURN (Cloudflare free tier: 1,000 GB/month TURN) | yes | chosen **later, for the web build** |

## Decision

- Internet matches are **player-hosted over EOS P2P**, using the community
  GDExtension EOSG (MIT; bundles the EOS SDK). Linux, Windows, Android.
- Identity: EOS Connect **device-ID login** (anonymous, per device). No
  accounts backend of our own.
- Joining: the host creates an **EOS lobby**; friends join with its short
  invite code. The lobby carries the host's product user ID; clients then
  open an EOS P2P connection to it.
- The game protocol is unchanged: `Transport` takes any `MultiplayerPeer`
  (`host_peer` / `join_peer`), so the handshake, whitelist and ingress
  limits (§3.7) apply to EOS peers exactly as to ENet. The host stays
  authoritative; host caps stay (phone 4, PC 8).
- **Web:** EOS has no browser SDK, so the web build gets no internet play
  yet. A WebRTC backend comes later behind the same `Transport` seam
  (signaling Worker + Cloudflare TURN). For web players to join a native
  host, the host will need to accept EOS and WebRTC peers at once (the
  composite peer of §3.20).

## How this meets the §3.8 rule ("no internet exposure until O1")

- Transport is encrypted and authenticated by EOS P2P; a host is reachable
  only through EOS by product user ID, never on an open port.
- Identity comes from EOS Connect instead of our own accounts. There is no
  login token of ours to protect, and no progression is trusted online yet
  (profiles stay local, as on LAN; O3 still applies before any online
  progression).
- Account deletion: device-ID users hold no personal data of ours; the
  Play listing must still name Epic as a processor (Data Safety, privacy
  policy) before release.

## Consequences and limits

- Depends on Epic (terms, availability, free pricing) and on a
  community plugin that must keep pace with Godot.
- Device-ID identity is lost on reinstall; no cross-device identity.
- Players can see each other's IP on direct connections unless relays are
  forced (an EOS relay-control setting).
- Netcode tests (100 ms RTT, 2% loss) must be re-run over EOS; packets are
  capped at 1,170 bytes (largest snapshot so far: 719 B).
- Automated tests can't cover EOS offline; the ENet path keeps all
  existing tests.

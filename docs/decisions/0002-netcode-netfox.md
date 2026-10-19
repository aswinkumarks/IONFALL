# 0002: Custom netcode instead of netfox

- **Status:** accepted (M1b)
- **Context:** PLAN §3.3.1 requires evaluating netfox in M1b against six criteria, limited to the components that fit the required model (forward-simulated authoritative server, client prediction for the local player only, hitbox-rewind lag compensation; the server never rolls back the world).
- **Evaluated:** netfox v1.35.3 (latest release), by source inspection.

| # | Criterion | Result | Evidence |
|---|---|---|---|
| 1 | Mantle/slide/crouch hitboxes + projectiles without desync | Not evaluated (moot, see 3) | — |
| 2 | Headless + Android | Plausible | Pure GDScript, no native code |
| 3 | Works without server rollback | **Fails** | `rollback/network-rollback.gd` runs a rollback loop that resimulates past ticks on every peer, including the server, when inputs for past ticks arrive (`notify_resimulation_start`, `history_limit` "regardless of inputs received"). `RollbackSynchronizer` is built on it. Only `NetworkTime` could be used alone, and it drives its own tick loop |
| 4 | Phone-host CPU within budget | Not evaluated | Server resimulation multiplies host CPU per late input, the opposite of what the phone host needs |
| 5 | Generic `MultiplayerPeer` only (transport inspection) | Passes | No ENet-specific calls, no threads |
| 6 | RPC audit vs PLAN §3.7 whitelist | 15 `@rpc("any_peer")` endpoints | `network-time-synchronizer.gd` (4), `network-time.gd` (1), `network-tickrate-handshake.gd` (1), `rollback-history-transmitter.gd` (5), `state-synchronizer.gd` (4). Handlers check `get_remote_sender_id()`, but each is another client-callable path |

- **Decision:** build the custom implementation (PLAN §3.3.2–3.3.5). Adopting netfox's rollback would need the formal architecture revision §3.3.1 forbids inside this evaluation; using only `NetworkTime` would bring 5 extra client-callable RPCs for a clock sync that's ~100 lines.
- **Design consequences:**
  - No `@rpc` methods anywhere. All traffic is raw `SceneMultiplayer.send_bytes()` messages decoded by one bounds-checked decoder (`net/protocol.gd`). The client-callable surface is exactly the message types the server accepts from clients: `CMD`, `PING`, `PONG`, `LOADED` (§3.7).
  - Admission uses SceneMultiplayer's auth step (`auth_callback`): a peer stays invisible to the game until the handshake (magic, protocol version, compat hash) succeeds (§3.20 rule 2, admission).
  - `server_relay` is disabled.
- **Ideas borrowed:** median-of-samples clock offset (also in the plan).

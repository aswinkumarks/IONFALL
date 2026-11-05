class_name Transport
extends Node
## The `Net` layer (PLAN §3.3.1, §3.20 rule 1): one SceneMultiplayer + ENet
## peer per session node, raw byte messages only (no RPCs), a pre-admission
## handshake via SceneMultiplayer auth, and ingress limits applied before any
## decoding (PLAN §3.7). Gameplay code never touches ENet directly.

signal peer_joined(id: int)
signal peer_left(id: int)
signal message(id: int, data: PackedByteArray)
signal connected
signal connection_failed(reason: String)
signal disconnected

const CHANNELS := 3
const MAX_PACKETS_PER_S := 120
const MAX_BYTES_PER_S := 16000
const VIOLATION_SECONDS_TO_KICK := 5
const TIMEOUT_MS := 10000

var api := SceneMultiplayer.new()
var stats := NetStats.new()
var conditioner := NetConditioner.new()
var is_server: bool = false
## Server: func(id: int, hello: Dictionary) -> String. Return "" to accept,
## otherwise the rejection reason sent to the client.
var auth_validator: Callable
var ingress_drops: int = 0

var _hello := PackedByteArray()
var _limits: Dictionary = {}  ## id -> [window_start_ms, packets, bytes, violation_seconds]
var _reject_reason: String = ""
var _authenticating: Dictionary = {}  ## peer id -> true while its handshake runs


func _enter_tree() -> void:
	get_tree().set_multiplayer(api, get_path())
	api.server_relay = false
	api.auth_timeout = 5.0
	api.auth_callback = _on_auth
	api.peer_authenticating.connect(_on_peer_authenticating)
	api.peer_connected.connect(_on_peer_connected)
	api.peer_disconnected.connect(_on_peer_disconnected)
	api.peer_authentication_failed.connect(func(id: int) -> void: _authenticating.erase(id))
	api.peer_packet.connect(_on_peer_packet)
	api.connected_to_server.connect(func() -> void:
		Log.i("net", "connected to the server as peer %d" % api.get_unique_id())
		connected.emit())
	# Deferred: these come from inside the multiplayer poll, and listeners
	# close the peer (leaving the lobby), which crashes the engine mid-poll.
	api.connection_failed.connect(func() -> void:
		Log.w("net", "connection failed (no answer from the server)")
		connection_failed.emit.call_deferred("connection failed"))
	api.server_disconnected.connect(func() -> void:
		Log.w("net", "disconnected from the server")
		disconnected.emit.call_deferred())


func _exit_tree() -> void:
	close()
	get_tree().set_multiplayer(null, get_path())


## LAN and dedicated servers: ENet over UDP and, when `web_port` > 0, also
## WebSocket for browser clients on that TCP port (CompositePeer). -1: the
## `--web-port` argument, else Protocol.DEFAULT_WEB_PORT when the host
## allows browser players (Settings, off by default; PLAN §3.20).
var web_port: int = -1


## The WebSocket port host() opens (0: none).
func host_web_port() -> int:
	if web_port >= 0:
		return web_port
	if Platform.user_args.has("--web-port"):
		return Platform.get_user_arg("--web-port", "0").to_int()
	return Protocol.DEFAULT_WEB_PORT if Settings.get_value("profile", "browser_players") else 0


## Server: peer `id` is on a stream transport (WebSocket: one ordered TCP
## stream, PLAN §3.20 rule 4) rather than ENet.
func is_stream(id: int) -> bool:
	var mp := api.multiplayer_peer
	return mp is CompositePeer and (mp as CompositePeer).adapter_of(id) is WebSocketMultiplayerPeer


## Server: bytes queued for stream peer `id` that the OS hasn't taken yet.
func buffered_bytes(id: int) -> int:
	var ws := (api.multiplayer_peer as CompositePeer).adapter_of(id) as WebSocketMultiplayerPeer \
			if api.multiplayer_peer is CompositePeer else null
	var peer := ws.get_peer(id) if ws != null else null
	return peer.get_current_outbound_buffered_amount() if peer != null else 0


## Client: connected over a stream transport (a browser).
func is_stream_client() -> bool:
	return api.multiplayer_peer is WebSocketMultiplayerPeer


func host(port: int, max_peers: int = Protocol.MAX_PEERS) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_peers, CHANNELS)
	if err != OK:
		Log.e("net", "can't host on UDP %d: %s" % [port, error_string(err)])
		return err
	# Godot 4.7.2 bug: create_server() passes the channel count as ENet's
	# incoming bandwidth (bytes/s), so clients throttle their unreliable
	# packets to ~1/32 once per second. Remove the bogus limit before anyone
	# connects.
	peer.host.bandwidth_limit(0, 0)
	var ws_port := host_web_port()
	if ws_port > 0:
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_server(ws_port)
		if err != OK:
			Log.e("net", "can't open the browser port TCP %d: %s" % [ws_port, error_string(err)])
			peer.close()
			return err
		var adapters: Array[MultiplayerPeer] = [peer, ws]
		Log.i("net", "hosting on UDP %d and WebSocket %d (max %d peers)" % [port, ws_port, max_peers])
		return host_peer(CompositePeer.new(adapters))
	Log.i("net", "hosting on UDP %d (max %d peers)" % [port, max_peers])
	return host_peer(peer)


## Browsers have no UDP: they join a host's WebSocket port instead (the
## default game port means its default web port).
func join(address: String, port: int, hello: PackedByteArray) -> Error:
	if OS.has_feature("web"):
		var ws := WebSocketMultiplayerPeer.new()
		var url := "ws://%s:%d" % [address, Protocol.DEFAULT_WEB_PORT if port == Protocol.DEFAULT_PORT else port]
		var werr := ws.create_client(url)
		Log.i("net", "joining %s: %s" % [url, error_string(werr)])
		return werr if werr != OK else join_peer(ws, hello)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, CHANNELS)
	Log.i("net", "joining %s:%d: %s" % [address, port, error_string(err)])
	if err != OK:
		return err
	return join_peer(peer, hello)


## Any server-mode MultiplayerPeer that is already listening (ENet, or an
## online backend such as Epic P2P; decision 0005). The handshake, message
## whitelist and ingress limits are the same for every backend.
func host_peer(peer: MultiplayerPeer) -> Error:
	Log.d("net", "server peer %s" % peer.get_class())
	is_server = true
	api.multiplayer_peer = peer
	return OK


## Any client-mode MultiplayerPeer that is already connecting to a server.
func join_peer(peer: MultiplayerPeer, hello: PackedByteArray) -> Error:
	Log.d("net", "client peer %s, hello %d bytes" % [peer.get_class(), hello.size()])
	is_server = false
	_hello = hello
	api.multiplayer_peer = peer
	return OK


func close() -> void:
	if api.multiplayer_peer != null and not api.multiplayer_peer is OfflineMultiplayerPeer:
		Log.i("net", "closing the %s connection" % ("server" if is_server else "client"))
		api.multiplayer_peer.close()
	api.multiplayer_peer = null


func local_id() -> int:
	return api.get_unique_id() if api.multiplayer_peer != null else 0


## A peer that already left (a rejected client closes on its own) is ignored.
func kick(id: int) -> void:
	if api.multiplayer_peer != null and (api.get_peers().has(id) or _authenticating.has(id)):
		Log.i("net", "disconnecting peer %d" % id)
		api.disconnect_peer(id)


func send(id: int, data: PackedByteArray, channel: int, reliable: bool) -> void:
	if conditioner.is_active():
		if conditioner.push("out", id, data, reliable, channel):
			stats.on_out(data.size())
		return
	_send_now(id, data, channel, reliable)


func _send_now(id: int, data: PackedByteArray, channel: int, reliable: bool) -> void:
	if api.multiplayer_peer == null or api.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not api.get_peers().has(id):
		return  # gone, or still authenticating: ENet would log an error
	var mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	if api.send_bytes(data, id, mode, channel) == OK and not conditioner.is_active():
		stats.on_out(data.size())


func _process(_delta: float) -> void:
	for item in conditioner.pop_due():
		if item[1] == "out":
			_send_now(item[2], item[3], item[5], item[4])
		else:
			_deliver(item[2], item[3])


# --- Handshake ---

func _on_peer_authenticating(id: int) -> void:
	Log.d("net", "peer %d authenticating%s" % [id, " (%s)" % _peer_address(id) if is_server else ""])
	_authenticating[id] = true
	_configure_peer(id)
	if not is_server:
		api.send_auth(id, _hello)


## ENet throttles unreliable packets (drops them) when RTT fluctuates, e.g.
## during frame hitches or Wi-Fi spikes. Our protocol has its own rate control
## (fixed send rates, command redundancy, time dilation), so ENet's throttle
## must not drop commands or snapshots. The config is also sent to the remote.
## Peers time out after 10 s of silence (PLAN §3.5.1).
func _configure_peer(id: int) -> void:
	var mp := api.multiplayer_peer
	if mp is CompositePeer:
		mp = (mp as CompositePeer).adapter_of(id)
	var enet := mp as ENetMultiplayerPeer
	if enet == null or enet.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return
	var peer := enet.get_peer(id)
	if peer != null:
		# Full throttle, never decelerate.
		peer.throttle_configure(100, 32, 0)
		peer.set_timeout(32, TIMEOUT_MS, TIMEOUT_MS)


func _on_auth(id: int, data: PackedByteArray) -> void:
	if is_server:
		var hello := Protocol.decode_hello(data)
		var reason := "malformed handshake"
		if not hello.is_empty():
			reason = auth_validator.call(id, hello) if auth_validator.is_valid() else ""
		api.send_auth(id, Protocol.encode_hello_reply(reason == "", reason))
		if reason == "":
			Log.i("net", "peer %d accepted: %s" % [id, _hello_summary(hello)])
			api.complete_auth(id)
		else:
			Log.w("net", "peer %d rejected (%s): %s" % [id, reason, _hello_summary(hello)])
			# Let the rejection reach the client before dropping it.
			get_tree().create_timer(0.3).timeout.connect(kick.bind(id))
	else:
		var reply := Protocol.decode_hello_reply(data)
		if reply.is_empty() or not reply.accepted:
			_reject_reason = reply.get("reason", "bad server reply")
			Log.w("net", "the server rejected us: %s" % _reject_reason)
			# Out of the auth callback first: a listener closing the peer from
			# in here crashed the game (rejoining a lobby you were removed from).
			connection_failed.emit.call_deferred(_reject_reason)
			close.call_deferred()
		else:
			Log.d("net", "the server accepted our handshake")
			api.complete_auth(id)


func _on_peer_connected(id: int) -> void:
	Log.i("net", "peer %d connected (%d peers)" % [id, api.get_peers().size()])
	_authenticating.erase(id)
	_configure_peer(id)
	if is_server:
		_limits[id] = [Time.get_ticks_msec(), 0, 0, 0]
		peer_joined.emit(id)


func _on_peer_disconnected(id: int) -> void:
	Log.i("net", "peer %d disconnected (%d peers left)" % [id, api.get_peers().size()])
	_limits.erase(id)
	if is_server:
		peer_left.emit(id)


# --- Receiving ---

func _on_peer_packet(id: int, data: PackedByteArray) -> void:
	if is_server and not _within_limits(id, data.size()):
		ingress_drops += 1
		return
	if conditioner.is_active():
		var reliable := Protocol.message_type(data) in [Protocol.Msg.WELCOME, Protocol.Msg.PHASE,
				Protocol.Msg.ROSTER, Protocol.Msg.EVENT, Protocol.Msg.LOADED]
		conditioner.push("in", id, data, reliable, 0)
		return
	_deliver(id, data)


func _deliver(id: int, data: PackedByteArray) -> void:
	stats.on_in(data.size())
	message.emit(id, data)


## Per-peer packet and byte limits, checked before decoding (PLAN §3.7).
func _within_limits(id: int, size: int) -> bool:
	if size > Protocol.MAX_CLIENT_PACKET:
		return false
	var l: Array = _limits.get(id, [])
	if l.is_empty():
		return false
	var now := Time.get_ticks_msec()
	if now - l[0] >= 1000:
		var violated: bool = l[1] > MAX_PACKETS_PER_S or l[2] > MAX_BYTES_PER_S
		l[3] = l[3] + 1 if violated else 0
		if l[3] >= VIOLATION_SECONDS_TO_KICK:
			Log.w("net", "peer %d exceeded ingress limits for %d s (%d packets, %d bytes in the last second), disconnecting"
					% [id, l[3], l[1], l[2]])
			kick.call_deferred(id)
		l[0] = now
		l[1] = 0
		l[2] = 0
	l[1] += 1
	l[2] += size
	return l[1] <= MAX_PACKETS_PER_S and l[2] <= MAX_BYTES_PER_S


## Peer `id`'s address and port, for the log ("" if unknown).
func _peer_address(id: int) -> String:
	var mp := api.multiplayer_peer
	if mp is CompositePeer:
		mp = (mp as CompositePeer).adapter_of(id)
	var peer := (mp as ENetMultiplayerPeer).get_peer(id) if mp is ENetMultiplayerPeer else null
	return "%s:%d" % [peer.get_remote_address(), peer.get_remote_port()] if peer != null else ""


## A handshake for the log: name, version and build.
static func _hello_summary(hello: Dictionary) -> String:
	var shown := {}
	for k: String in hello:
		if k not in ["uuid", "token", "magic"]:
			shown[k] = hello[k]
	return str(shown)

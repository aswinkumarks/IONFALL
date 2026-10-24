class_name LobbySession
extends Node
## Pre-match lobby: who is in, and the host's map, mode, duration and bots. Uses
## the match's Transport (same handshake, whitelist and ingress limits) over
## ENet or an online peer. Only the host sends: LOBBY on every change, START
## when the match begins. Then everyone leaves the lobby and joins the match,
## which the host serves on the same port or online socket.

signal changed
signal started(settings: Dictionary)  ## {map, mode, minutes}
signal closed(reason: String)  ## client: rejected, or lost the host
signal in_match(map_id: String)  ## client: the host is already playing

const DURATIONS := [5, 10, 15, 20]  ## match length choices (minutes)
const DEFAULT_MINUTES := 10

var transport := Transport.new()
var is_host: bool = false
var map_id: String = Maps.DEFAULT
var game_mode: int = GameMode.FFA
var minutes: int = DEFAULT_MINUTES
## The host's bot settings, shown to everyone (bot count up to the cap,
## BotBrain.Difficulty); bots make room as players join.
var bots: int = 0
var bot_difficulty: int = 1
var friendly_fire: bool = false
var max_players: int = Protocol.MAX_PEERS
## [{name, host}], the host first, then in join order.
var members: Array = []
var _host_name: String = ""
var _names: Dictionary = {}  ## host: peer id -> name, in join order
var _accepted: Dictionary = {}  ## host: authenticated peer id -> name
var _done: bool = false  ## client: started, redirected or closed; later signals are ignored


## Host: listens on `port` (ENet), or on `peer` when online.
func host(host_name: String, p_max: int, port: int, peer: MultiplayerPeer = null) -> Error:
	is_host = true
	_host_name = host_name
	max_players = clampi(p_max, 2, Protocol.MAX_PEERS)
	add_child(transport)
	transport.auth_validator = _validate_hello
	transport.peer_joined.connect(_on_peer_joined)
	transport.peer_left.connect(_on_peer_left)
	var err := transport.host_peer(peer) if peer != null else transport.host(port, max_players)
	if err == OK:
		_update_members()
	return err


## Client: connects to a host at `address`, or through `peer` when online.
func join(address: String, port: int, player_name: String, uuid: String, peer: MultiplayerPeer = null) -> Error:
	is_host = false
	add_child(transport)
	transport.connection_failed.connect(_finish.bind(closed))
	transport.disconnected.connect(func() -> void: _finish("disconnected", closed))
	transport.message.connect(_on_message)
	var hello := Protocol.encode_hello(BuildInfo.compat_hash, BuildInfo.artifact_id, uuid, player_name)
	return transport.join_peer(peer, hello) if peer != null else transport.join(address, port, hello)


## Host: changes the settings everyone sees.
func configure(p_map: String, p_mode: int, p_minutes: int, p_bots: int = bots, p_difficulty: int = bot_difficulty,
		p_friendly_fire: bool = friendly_fire) -> void:
	map_id = p_map if Maps.has(p_map) else Maps.DEFAULT
	game_mode = p_mode if p_mode >= 0 and p_mode < GameMode.IDS.size() else GameMode.FFA
	minutes = p_minutes if DURATIONS.has(p_minutes) else DEFAULT_MINUTES
	bots = clampi(p_bots, 0, Protocol.MAX_PEERS - 1)
	bot_difficulty = clampi(p_difficulty, 0, BotBrain.DIFFICULTY_IDS.size() - 1)
	friendly_fire = p_friendly_fire
	_broadcast()


## Host: tells everyone to load the map and join the match.
func start() -> void:
	var msg := Protocol.encode_start(map_id, game_mode, minutes)
	for id in _accepted:
		transport.send(id, msg, Protocol.CH_CONTROL, true)
	started.emit({"map": map_id, "mode": game_mode, "minutes": minutes})


func leave() -> void:
	transport.close()


## LAN discovery beacon for this lobby (Discovery.FLAG_LOBBY).
func beacon(display_name: String, port: int) -> Discovery.Beacon:
	var b := Discovery.Beacon.new()
	b.build = BuildInfo.display_string()
	b.compat_prefix = BuildInfo.compat_hash.left(8)
	b.name = display_name
	b.map = map_id
	b.mode = GameMode.IDS[game_mode]
	b.combatants = members.size()
	b.max_combatants = max_players
	b.flags = Discovery.FLAG_LOBBY
	b.game_port = port
	return b


func _validate_hello(id: int, hello: Dictionary) -> String:
	if hello.magic != Protocol.MAGIC:
		return "not an IONFALL client"
	if hello.version != Protocol.VERSION:
		return "protocol mismatch (server %d, client %d)" % [Protocol.VERSION, hello.version]
	if hello.compat != BuildInfo.compat_hash:
		return "version mismatch: server runs %s" % BuildInfo.display_string()
	if 1 + _names.size() >= max_players:
		return "server full"
	_names[id] = ServerSession.sanitize_name(hello.name)
	return ""


func _on_peer_joined(id: int) -> void:
	if not _names.has(id):
		transport.kick(id)
		return
	_accepted[id] = _names[id]
	_update_members()


func _on_peer_left(id: int) -> void:
	_names.erase(id)
	_accepted.erase(id)
	_update_members()


func _update_members() -> void:
	members = [{"name": _host_name, "host": true}]
	for id in _accepted:
		members.append({"name": _accepted[id], "host": false})
	_broadcast()


func _broadcast() -> void:
	if is_host:
		var msg := Protocol.encode_lobby(map_id, game_mode, minutes, max_players, members, bots, bot_difficulty, friendly_fire)
		for id in _accepted:
			transport.send(id, msg, Protocol.CH_CONTROL, true)
	changed.emit()


func _on_message(_id: int, data: PackedByteArray) -> void:
	match Protocol.message_type(data):
		Protocol.Msg.LOBBY:
			var l := Protocol.decode_lobby(data)
			if not l.is_empty():
				map_id = l.map if Maps.has(l.map) else Maps.DEFAULT
				game_mode = l.mode
				minutes = l.minutes
				max_players = l.max
				members = l.members
				bots = l.bots
				bot_difficulty = l.bot_difficulty
				friendly_fire = l.friendly_fire
				changed.emit()
		Protocol.Msg.START:
			var s := Protocol.decode_start(data)
			if not s.is_empty():
				_finish(s, started)
		Protocol.Msg.WELCOME:
			# A match server answered: the host has already started.
			_finish(Protocol.decode_welcome(data).get("map", ""), in_match)


## Client: emits `sig` with `arg` once, then closes the connection.
func _finish(arg: Variant, sig: Signal) -> void:
	if _done:
		return
	_done = true
	transport.close.call_deferred()
	sig.emit(arg)

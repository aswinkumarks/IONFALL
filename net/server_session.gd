class_name ServerSession
extends Node
## Authoritative match server (PLAN §3.3, §3.4): dedicated server, listen host
## and offline play all run this. Steps the simulation at 60 Hz, consumes one
## command per client per tick, validates view ticks for lag compensation and
## sends delta snapshots at 30 Hz.

signal phase_changed(phase: int)
## Emitted after every simulation step.
signal stepped
## The match ended and its results were shown; with `lobby_after_match`
## the host takes everyone back to the lobby instead of starting again.
signal match_over

const SNAPSHOT_INTERVAL := 2
## Command buffer target per client, in ticks: the minimum on a clean
## network; on jittery links (Wi-Fi power saving bunches packets) it grows
## with the measured arrival jitter, up to MAX_TARGET_BUFFER.
const TARGET_BUFFER := 2
const MAX_TARGET_BUFFER := 6.0
const MAX_FUTURE_TICKS := 8
const REPEAT_LIMIT := 6
## A client's player waits this many ticks for a late command (Wi-Fi bursts)
## before the server starts guessing it (PLAN §3.3.2).
const MAX_STALL_TICKS := 8
const VIEW_TOLERANCE_TICKS := 2.0
## Largest steady per-client timing bias the validator will learn. Frame
## quantization on both ends (and clock-sync error) gives every client a
## stable offset between its claimed and our expected view time; validation is
## ±VIEW_TOLERANCE around that learned bias, so a client can gain at most this
## much extra rewind (still capped at 250 ms in total).
const MAX_VIEW_BIAS_TICKS := 3.0
## The first commands of a client only learn its bias (running mean); claims
## are still bounded by tolerance + max bias meanwhile.
const VIEW_BIAS_LEARN_SAMPLES := 60
const MAX_PENDING_EVENTS := 32
const PING_INTERVAL_TICKS := 60
const BASELINE_HISTORY_TICKS := 64
const LOCAL_PLAYER_ID := 1
## A client that drops can come back with its reconnect token within this
## time and gets its player id and score back (PLAN §3.4).
const RECONNECT_WINDOW_MS := 60000
## WebSocket clients (PLAN §3.20 rule 4): while more than this is still
## queued for one, its snapshots are skipped, so only the newest goes out
## once the stream drains (coalescing; keeps its queue near 200 ms).
const STREAM_BACKLOG_BYTES := 4096
## A backlog older than this: the next snapshot is a full state (resync);
const STREAM_RESYNC_MS := 500
## older than this: the client is dropped.
const STREAM_DROP_MS := 3000
## Remote spectators allowed on top of the combatants.
const MAX_SPECTATORS := 4

var transport := Transport.new()
var world: SimWorld
var movement: MovementConfig
var loadout: Array[WeaponData] = []
## Players choose their primary (Loadouts.make); off: everyone gets `loadout`.
var use_primaries: bool = false
## GameMode.FFA or TDM (set before start()); friendly fire is a host setting.
var game_mode: int = GameMode.FFA
var friendly_fire: bool = false
var bot_difficulty: int = BotBrain.Difficulty.NORMAL
var match_id: int = 0
var phase: int = MatchPhase.WAITING
var phase_seq: int = 0
var phase_ends_tick: int = 0
var clients: Dictionary = {}  ## peer id -> Client
var bots: Dictionary = {}  ## net id -> BotBrain (or TargetDummyDriver without navigation)
## Set by the owner once the map's navigation is built; bots need it.
var bot_nav: BotNavigation
## Listen host / offline: the local player's id and this tick's command.
var local_player_id: int = 0
## The host watches without playing (spectator mode): it keeps the match
## running like a human would but takes no combatant slot.
var local_spectating: bool = false
var local_command: PlayerCommand
var anomalies: int = 0
var networked: bool = false
## Most combatants (humans + bots) this session admits: 16 dedicated,
## 8 PC listen host, 4 phone host (PLAN §3.5.1).
var map_id: String = Maps.DEFAULT  ## sent in WELCOME and beacons
var time_limit_ticks: int = Balance.MODES.default_time_limit_ticks
var max_combatants: int = Protocol.MAX_PEERS
var lobby_after_match: bool = false
## Team modes: the teams picked in the lobby, profile uuid -> team. Players
## not in it join the smaller team.
var team_plan: Dictionary = {}
## Bots fill the match up to this many combatants and leave as humans join.
var bot_fill: int = 0
## When 0 or more (the host's bot count): this many bots play alongside
## however many humans join, giving way only when the match is full.
var bot_count: int = -1
## Co-op waves: spawns and clears the waves (null in other modes).
var waves: WaveDirector
## Recent (claimed - expected) view tick errors, for diagnostics and tests.
var view_errors := FrameStats.new(600)
## Wall time of the last tick (simulation + snapshots), in microseconds.
var last_step_usec: int = 0
var last_sim_usec: int = 0  ## of which world.step()

var _host_events: Array[Dictionary] = []
var _next_player_id: int = 2
var stats := MatchStats.new()
## Winner of the last finished match (0 = draw), for presentation.
var last_winner: int = 0
var _play_started_tick: int = 0
var _instance_id: int = 0  ## makes match_result_ids unique across server runs
var _departed: Dictionary = {}  ## reconnect token -> {player_id, score, expires_ms}
var _bot_seq: int = 0
var _rng := RandomNumberGenerator.new()


class Client:
	var id: int = 0  ## transport peer id
	var player_id: int = 0  ## small server-assigned id used on the wire and in the world
	var name: String = ""
	var uuid: String = ""
	var character: int = 0
	var color: int = 0
	var loaded: bool = false
	var queue: Dictionary = {}  ## tick -> PlayerCommand
	var arrival: Dictionary = {}  ## tick -> server time (ticks) of first arrival
	var last_processed: int = -1
	var last_cmd: PlayerCommand
	var repeats: int = 0
	var ack: int = 0
	var rtt_ms: float = 100.0
	var sent: Dictionary = {}  ## snapshot id -> {entity id -> NetEntity}
	var pending: Array = []  ## [event bytes, first snapshot id or -1]
	var buffer_avg: float = TARGET_BUFFER
	var target_buffer: float = TARGET_BUFFER
	var arrival_median: float = NAN  ## median (arrival - command tick), refreshed every 30 ticks
	var arrival_offsets := FrameStats.new(120)  ## (arrival time - command tick) of new commands
	var view_bias: float = 0.0
	var view_samples: int = 0
	var view_anomalies: int = 0
	var synthesized: int = 0
	var stalled: int = 0  ## ticks spent waiting for late commands (total)
	var stall_run: int = 0
	var token: int = 0
	var restored_score: int = 0
	var restored_team: int = -1  ## TDM: the team to rejoin after a reconnect
	var primary: int = 0  ## Loadouts.PRIMARIES index
	var backlog_since_ms: int = 0  ## WebSocket: when its send queue last went over STREAM_BACKLOG_BYTES
	var resync: bool = false  ## WebSocket: send the next snapshot as a full state
	var coalesced: int = 0  ## WebSocket: snapshots skipped behind a backlog
	## Watches without playing: gets snapshots and events, has no player.
	var spectator: bool = false


## `port` < 0 runs without networking (offline play) unless `peer` is given:
## an already listening MultiplayerPeer (internet play over EOS, decision
## 0005). `spots`: the map's pickup spots (SimWorld.pickup_spots).
## `flag_bases`: CTF only, [team 0's base, team 1's base].
func start(port: int, movement_config: MovementConfig, weapons: Array[WeaponData], spawns: Array[Transform3D],
		spots: Array = [], peer: MultiplayerPeer = null, flag_bases: Array = []) -> Error:
	movement = movement_config
	loadout = weapons
	_rng.randomize()
	_instance_id = _rng.randi()
	match_id = _rng.randi() | 1
	world = SimWorld.new()
	world.name = "ServerWorld"
	world.lag_compensation = true
	world.pickups_enabled = true
	world.teams_enabled = GameMode.is_team_mode(game_mode)
	world.kills_score_for_team = game_mode == GameMode.TDM
	world.friendly_fire = friendly_fire and game_mode != GameMode.WAVES
	world.respawn_ticks = GameMode.respawn_ticks(game_mode)
	world.configure(_rng.randi(), movement, spawns, spots)
	if game_mode == GameMode.CTF:
		world.configure_flags(flag_bases)
	if game_mode == GameMode.WAVES:
		waves = WaveDirector.new(self)
	add_child(world)
	add_child(transport)
	if port >= 0 or peer != null:
		transport.auth_validator = _validate_hello
		transport.peer_joined.connect(_on_peer_joined)
		transport.peer_left.connect(_on_peer_left)
		transport.message.connect(_on_message)
		var err := transport.host_peer(peer) if peer != null else transport.host(port)
		if err != OK:
			return err
		networked = true
	_set_phase(MatchPhase.WAITING, 0)
	return OK


func add_local_player(player_name: String, character: int = 0, color: int = 0, primary: int = 0,
		uuid: String = "") -> SimPlayer:
	local_player_id = LOCAL_PLAYER_ID
	var p := world.add_player(local_player_id, _loadout_for(primary), player_name, false)
	_join_team(p, team_plan.get(uuid, -1))
	p.character = character
	p.color = color
	stats.add_player(local_player_id, player_name, false, world.tick)
	update_bot_fill()
	_on_humans_changed()
	return p


## Watch the match instead of playing (see local_spectating).
func add_local_spectator() -> void:
	local_spectating = true
	update_bot_fill()
	_on_humans_changed()


const BOT_NAMES := ["Kestrel", "Vanta", "Ordo", "Lumen", "Rook", "Sable", "Quill", "Echo", "Halcyon", "Tarsus",
		"Wren", "Corvid", "Nyx", "Brant", "Ivo"]


## `driver`: anything with command_for(tick, player) -> PlayerCommand.
func add_bot(bot_name: String, driver: RefCounted) -> SimPlayer:
	var id := 1000 + _bot_seq
	_bot_seq += 1
	bots[id] = driver
	var p := world.add_player(id, _loadout_for(_rng.randi_range(0, Loadouts.PRIMARIES.size() - 1)), bot_name, true)
	_join_team(p)
	p.character = _bot_seq - 1  # bots cycle through the characters
	stats.add_player(id, bot_name, true, world.tick)
	_broadcast_roster()
	return p


## Co-op: one bot of the current wave, hunting the humans.
func add_wave_bot(difficulty: int) -> SimPlayer:
	var bot_name: String = BOT_NAMES[_bot_seq % BOT_NAMES.size()]
	var id := 1000 + _bot_seq
	if bot_nav == null:
		return add_bot(bot_name, TargetDummyDriver.new(_bot_seq * 50))
	var brain := BotBrain.new(world, bot_nav, id, _rng.randi(), difficulty)
	brain.hunt = true
	return add_bot(bot_name, brain)


func remove_bot(id: int) -> void:
	bots.erase(id)
	world.remove_player(id)
	stats.remove_player(id, world.tick)
	_broadcast_roster()


## The spawn loadout for primary choice `primary`. Matches started with a
## fixed loadout (tests, test clients) keep it.
func _loadout_for(primary: int) -> Array[WeaponData]:
	return Loadouts.make(primary) if use_primaries else loadout


## The primary `player_id` gets from its next spawn (PLAN §2.5).
func set_primary(player_id: int, primary: int) -> void:
	var p := world.get_player(player_id)
	if p != null:
		p.loadout = _loadout_for(primary)


func combatants() -> int:
	return _humans() + bots.size()


## TDM: a new player joins the smaller team (ties: the one behind), and
## respawns there so it starts on its own side.
func _join_team(p: SimPlayer, team: int = -1) -> void:
	if not GameMode.is_team_mode(game_mode):
		return
	if game_mode == GameMode.WAVES:  # humans against the waves
		team = GameMode.WAVE_TEAM if p.is_bot else GameMode.HUMANS
	if team < 0 or team > 1:
		var counts := team_counts(p.net_id)
		team = 0 if counts[0] < counts[1] or (counts[0] == counts[1] and world.team_scores[0] <= world.team_scores[1]) else 1
	p.team = team
	world.respawn(p)


## Players per team, leaving out `except`.
func team_counts(except: int = 0) -> PackedInt32Array:
	var counts := PackedInt32Array([0, 0])
	for other: SimPlayer in world.players.values():
		if other.net_id != except:
			counts[clampi(other.team, 0, 1)] += 1
	return counts


## Adds or removes bots to match _bots_wanted().
func update_bot_fill() -> void:
	if waves != null:  # co-op: the waves bring their own bots
		_broadcast_roster()
		return
	var wanted := _bots_wanted()
	while bots.size() > wanted:
		var id: int = bots.keys().max()
		if GameMode.is_team_mode(game_mode):
			# Make room on the larger team.
			var counts := team_counts()
			var big := 0 if counts[0] > counts[1] else 1
			var on_big := bots.keys().filter(func(b: int) -> bool: return world.players[b].team == big)
			if not on_big.is_empty():
				id = on_big.max()
		bots.erase(id)
		world.remove_player(id)
		stats.remove_player(id, world.tick)
	while bots.size() < wanted:
		var bot_name: String = BOT_NAMES[_bot_seq % BOT_NAMES.size()]
		var id := 1000 + _bot_seq
		if bot_nav != null:
			add_bot(bot_name, BotBrain.new(world, bot_nav, id, _rng.randi(), bot_difficulty))
		else:
			add_bot(bot_name, TargetDummyDriver.new(_bot_seq * 50))
	_broadcast_roster()


## How many bots the match should have now: bot_count beside the humans
## (fewer once the match is full), else enough to make bot_fill combatants.
func _bots_wanted() -> int:
	var room := maxi(max_combatants - _humans(), 0)
	if bot_count >= 0:
		return mini(bot_count, room)
	return clampi(bot_fill - _humans(), 0, room)


## LAN discovery beacon describing this session (PLAN §3.6).
func beacon(display_name: String, dedicated: bool, port: int) -> Discovery.Beacon:
	var b := Discovery.Beacon.new()
	b.build = BuildInfo.display_string()
	b.compat_prefix = BuildInfo.compat_hash.left(8)
	b.name = display_name
	b.map = map_id
	b.mode = GameMode.IDS[game_mode]
	b.combatants = _humans()
	b.max_combatants = max_combatants
	b.flags = Discovery.FLAG_DEDICATED if dedicated else 0
	b.game_port = port
	return b


## Best-effort hint to clients when the listen host is suspended or resumed
## (PLAN §3.5.1).
func notify_clients(code: int) -> void:
	if not networked:
		return
	var msg := Protocol.encode_notice(code)
	for c: Client in clients.values():
		transport.send(c.id, msg, Protocol.CH_CONTROL, true)


func drain_host_events() -> Array[Dictionary]:
	var out := _host_events
	_host_events = []
	return out


## The last completed tick plus the fraction towards the next one. Snapshot
## ids, pongs, lag-compensation history and view ticks all use this one time
## domain: "tick T" means the state after step T (PLAN §3.3.4).
func completed_tick() -> int:
	return world.tick - 1


func server_time() -> float:
	return completed_tick() + Engine.get_physics_interpolation_fraction()


func roster() -> Array:
	var out := []
	var ids := world.players.keys()
	ids.sort()
	for id in ids:
		var p: SimPlayer = world.players[id]
		var l: MatchStats.Line = stats.lines.get(id)
		out.append({"id": id, "name": p.display_name, "bot": p.is_bot, "character": p.character, "color": p.color,
				"score": world.scores.get(id, 0), "team": p.team if GameMode.is_team_mode(game_mode) else GameMode.NO_TEAM,
				"kills": l.kills if l else 0, "deaths": l.deaths if l else 0, "assists": l.assists if l else 0})
	return out


# --- Tick ---

func _physics_process(_delta: float) -> void:
	if world == null:
		return
	var t0 := Time.get_ticks_usec()
	var commands := {}
	var stalled := {}
	for c: Client in clients.values():
		if c.loaded and world.players.has(c.player_id):
			var cmd := _next_command(c)
			if cmd != null:
				commands[c.player_id] = cmd
			elif c.stall_run > 0:
				stalled[c.player_id] = true
	if local_player_id != 0 and local_command != null:
		commands[local_player_id] = local_command
	for id in bots:
		commands[id] = bots[id].command_for(world.tick, world.get_player(id))
	var t_sim := Time.get_ticks_usec()
	world.step(commands, stalled)
	last_sim_usec = Time.get_ticks_usec() - t_sim
	var score_changed := false
	for e in world.drain_events():
		_host_events.append(e)
		stats.on_event(e)
		if e.type == "hit":
			var brain: Variant = bots.get(e.target)
			if brain is BotBrain:
				brain.on_event(e)
		if e.type in ["death", "spawn", "flag", "wave"]:
			score_changed = score_changed or e.type != "spawn"
			_send_reliable_event(e)
		else:
			_queue_cosmetic(e)
	if score_changed:
		_broadcast_roster()
	_update_phase()
	stepped.emit()
	if networked:
		# Each client gets a snapshot every SNAPSHOT_INTERVAL ticks, staggered
		# by player id so the encoding work is spread over ticks.
		var tick_entities := {}
		for c: Client in clients.values():
			if c.loaded and (world.tick + c.player_id) % SNAPSHOT_INTERVAL == 0:
				if tick_entities.is_empty():
					for id in world.players:
						tick_entities[id] = NetEntity.from_player(world.players[id])
				_send_snapshot(c, tick_entities)
		if world.tick % PING_INTERVAL_TICKS == 0:
			var ping := Protocol.encode_ping(Time.get_ticks_msec() & 0xFFFFFFFF)
			for c: Client in clients.values():
				transport.send(c.id, ping, Protocol.CH_GAME, false)
	last_step_usec = Time.get_ticks_usec() - t0


## One command per client per tick (PLAN §3.3.2). A missing command first
## stalls the player for up to MAX_STALL_TICKS (returns null with stall_run
## > 0): the late command is then used as sent, so prediction stays exact
## and the client's time dilation drains the extra buffer. After that the
## last held input repeats (no new presses) for up to 6 ticks, then neutral.
func _next_command(c: Client) -> PlayerCommand:
	var next_tick := -1
	for t in c.queue:
		if t > c.last_processed and (next_tick < 0 or t < next_tick):
			next_tick = t
	c.buffer_avg = lerpf(c.buffer_avg, c.queue.size(), 0.05)
	if world.tick % 30 == 0 and c.arrival_offsets.count() >= 30:
		c.arrival_median = c.arrival_offsets.percentile(50.0)
		var jitter := c.arrival_offsets.percentile(95.0) - c.arrival_offsets.percentile(5.0)
		var wanted := clampf(TARGET_BUFFER + jitter, TARGET_BUFFER, MAX_TARGET_BUFFER)
		# Grow at once, shrink slowly.
		c.target_buffer = wanted if wanted > c.target_buffer else lerpf(c.target_buffer, wanted, 0.1)
	if next_tick < 0:
		if c.last_cmd == null:
			return null
		if c.stall_run < MAX_STALL_TICKS:
			c.stall_run += 1
			c.stalled += 1
			return null
		c.synthesized += 1
		var cmd: PlayerCommand
		if c.repeats < REPEAT_LIMIT:
			cmd = c.last_cmd.copy()
			c.repeats += 1
		else:
			cmd = PlayerCommand.neutral_from(c.last_cmd, 0)
		cmd.tick = c.last_processed + 1
		cmd.view_tick = 0.0
		c.last_processed = cmd.tick
		return cmd
	var cmd: PlayerCommand = c.queue[next_tick]
	for t in c.queue.keys():
		if t <= next_tick:
			c.queue.erase(t)
	# Where this command would arrive without packet bunching: its tick plus
	# the client's typical offset. Bursts (Wi-Fi) don't skew view validation.
	var arrived: float = next_tick + c.arrival_median if not is_nan(c.arrival_median) \
			else c.arrival.get(next_tick, server_time())
	for t in c.arrival.keys():
		if t <= next_tick:
			c.arrival.erase(t)
	c.last_processed = next_tick
	c.last_cmd = cmd
	c.repeats = 0
	c.stall_run = 0
	cmd.view_tick = validate_view_tick(cmd.view_tick, arrived, c.rtt_ms, cmd.interp_ticks, c)
	return cmd


## Lag-compensation timestamp check (PLAN §3.3.4): the client may only claim
## the view time we expect from what the server knows (arrival time, measured
## latency, interpolation delay), within ±2 ticks. Otherwise the expected
## value is used and an anomaly is counted.
func validate_view_tick(claimed: float, arrived: float, rtt_ms: float, interp_ticks: int, c: Client = null) -> float:
	if claimed <= 0.0:
		return 0.0
	var one_way := rtt_ms * 0.5 / 1000.0 * Sim.TICK_RATE
	var expected := arrived - one_way - clampi(interp_ticks, 3, 9)
	var bias := c.view_bias if c != null else 0.0
	var error := claimed - expected
	view_errors.add(error)
	if c != null and c.view_samples < VIEW_BIAS_LEARN_SAMPLES \
			and absf(error) <= VIEW_TOLERANCE_TICKS + MAX_VIEW_BIAS_TICKS:
		c.view_samples += 1
		c.view_bias = clampf(lerpf(c.view_bias, error, 1.0 / c.view_samples), -MAX_VIEW_BIAS_TICKS, MAX_VIEW_BIAS_TICKS)
		return claimed
	# Arrival times on jittery links (measured as the buffer growth) blur the
	# expected value by the same amount.
	var tolerance := VIEW_TOLERANCE_TICKS + (c.target_buffer - TARGET_BUFFER if c != null else 0.0)
	if absf(error - bias) <= tolerance:
		if c != null:
			c.view_bias = clampf(lerpf(c.view_bias, error, 0.05), -MAX_VIEW_BIAS_TICKS, MAX_VIEW_BIAS_TICKS)
		return claimed
	anomalies += 1
	if c != null:
		c.view_anomalies += 1
		# Learn slowly from outliers too (bounded), so a real shift in the
		# client's timing is adopted while a one-off forged claim is not.
		c.view_bias = clampf(lerpf(c.view_bias, error, 0.01), -MAX_VIEW_BIAS_TICKS, MAX_VIEW_BIAS_TICKS)
	return expected + bias


# --- Phases (PLAN §3.4) ---

func _set_phase(p: int, ends: int) -> void:
	phase = p
	phase_seq = (phase_seq + 1) & 0xFF
	phase_ends_tick = ends
	world.damage_enabled = MatchPhase.allows_damage(p)
	if networked:
		var msg := Protocol.encode_phase(match_id, phase_seq, phase, world.tick, ends, world.match_seed)
		for c: Client in clients.values():
			transport.send(c.id, msg, Protocol.CH_CONTROL, true)
	phase_changed.emit(p)


func _humans() -> int:
	var n := 1 if local_player_id != 0 else 0
	for c: Client in clients.values():
		if c.loaded and not c.spectator:
			n += 1
	return n


## Humans the match runs for: players plus spectators.
func _audience() -> int:
	return _humans() + (1 if local_spectating else 0)


func _on_humans_changed() -> void:
	if phase == MatchPhase.WAITING and _audience() > 0:
		_set_phase(MatchPhase.COUNTDOWN, world.tick + Balance.MODES.countdown_ticks)
	elif _audience() == 0 and phase != MatchPhase.WAITING:
		_set_phase(MatchPhase.WAITING, 0)


func _update_phase() -> void:
	match phase:
		MatchPhase.COUNTDOWN:
			if world.tick >= phase_ends_tick:
				_play_started_tick = world.tick
				# Players and bots roam freely in the countdown; the match
				# itself starts from fresh spawns, with spawn protection, so
				# nobody is mid-fight (or next to an enemy) at GO.
				world.reset_match(world.match_seed)
				_set_phase(MatchPhase.PLAYING, world.tick + time_limit_ticks)
				if waves != null:
					waves.reset(world.tick)
		MatchPhase.PLAYING:
			if waves != null:  # co-op: the waves decide, there is no time limit
				var decided := waves.step()
				if decided != 0:
					_end_match(decided)
				return
			var scores := _victory_scores()
			var top := -999
			for id in scores:
				top = maxi(top, scores[id])
			var lead := MatchPhase.leader(scores)
			if top >= GameMode.score_limit(game_mode):
				_end_match(lead)
			elif world.tick >= phase_ends_tick:
				if lead != 0:
					_end_match(lead)
				else:
					_set_phase(MatchPhase.SUDDEN_DEATH, world.tick + Balance.MODES.sudden_death_ticks)
		MatchPhase.SUDDEN_DEATH:
			var lead := MatchPhase.leader(_victory_scores())
			if lead != 0:
				_end_match(lead)
			elif world.tick >= phase_ends_tick:
				_end_match(0)  # draw
		MatchPhase.POST_MATCH:
			if world.tick >= phase_ends_tick and lobby_after_match:
				phase_ends_tick = 0x7FFFFFFF  # once
				match_over.emit()
			elif world.tick >= phase_ends_tick:
				match_id = _rng.randi() | 1
				phase_seq = 0
				if waves != null:  # the last wave's bots go
					for id: int in bots.keys():
						remove_bot(id)
				world.reset_match(_rng.randi())
				stats.reset(world.tick)
				for d: Dictionary in _departed.values():
					d.score = 0  # scores belong to the finished match
				_set_phase(MatchPhase.COUNTDOWN, world.tick + Balance.MODES.countdown_ticks)
				_broadcast_roster()


## What decides the match: player scores (FFA) or team scores keyed by
## team + 1 (TDM), so MatchPhase.leader's 0 still means "nobody".
func _victory_scores() -> Dictionary:
	if not GameMode.is_team_mode(game_mode):
		return world.scores
	return {1: world.team_scores[0], 2: world.team_scores[1]}


## PLAN §2.6: results go to every client (reliable) and to the host's own
## presentation; each carries a unique result id for idempotent profiles.
## `lead`: the winning player id (FFA) or team + 1 (team modes); 0 = draw.
func _end_match(lead: int) -> void:
	var teams := GameMode.is_team_mode(game_mode)
	var winner := lead if not teams else 0
	var winner_team := lead - 1 if teams and lead > 0 else GameMode.NO_TEAM
	last_winner = winner
	_set_phase(MatchPhase.POST_MATCH, world.tick + Balance.MODES.post_match_ticks)
	var rows := []
	for id in stats.lines:
		var l: MatchStats.Line = stats.lines[id]
		rows.append({"id": l.id, "bot": l.bot, "name": l.name, "score": world.scores.get(id, 0),
				"ticks_played": l.ticks_played(world.tick), "kills": l.kills, "kills_vs_bots": l.kills_vs_bots,
				"deaths": l.deaths, "deaths_vs_bots": l.deaths_vs_bots, "assists": l.assists,
				"assists_vs_bots": l.assists_vs_bots, "suicides": l.suicides, "headshot_kills": l.headshot_kills,
				"shots": l.shots, "hits": l.hits, "damage_dealt": l.damage_dealt, "damage_taken": l.damage_taken,
				"best_streak": l.best_streak, "weapon_kills": l.weapon_kills,
				"team": world.players[id].team if teams and world.players.has(id) else GameMode.NO_TEAM})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	# Every human keeps a row (their profile reads it); bots fill what's left.
	if rows.size() > Protocol.MAX_RESULT_ROWS:
		var humans := rows.filter(func(r: Dictionary) -> bool: return not r.bot)
		var bots := rows.filter(func(r: Dictionary) -> bool: return r.bot)
		rows = humans + bots.slice(0, maxi(Protocol.MAX_RESULT_ROWS - humans.size(), 0))
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var result_id := "%08x-%08x" % [_instance_id, match_id]
	var msg := Protocol.encode_results(match_id, result_id, winner, world.tick - _play_started_tick, _humans(), rows,
			game_mode, winner_team, world.team_scores)
	# The host reads the same decoded form clients get.
	var results := Protocol.decode_results(msg)
	results["type"] = "results"
	results["id"] = "r:" + result_id
	_host_events.append(results)
	if networked:
		for c: Client in clients.values():
			transport.send(c.id, msg, Protocol.CH_CONTROL, true)


# --- Networking ---

func _validate_hello(id: int, hello: Dictionary) -> String:
	if hello.magic != Protocol.MAGIC:
		return "not an IONFALL client"
	if hello.version != Protocol.VERSION:
		return "protocol mismatch (server %d, client %d)" % [Protocol.VERSION, hello.version]
	if hello.compat != BuildInfo.compat_hash:
		return "version mismatch: server runs %s" % BuildInfo.display_string()
	# A client back from suspension before its old connection timed out:
	# drop the stale connection and hand its player over.
	if hello.token != 0:
		for old: Client in clients.values():
			if old.token == hello.token and old.id != id:
				_on_peer_left(old.id)
				transport.kick(old.id)
				break
	# Bots give way to humans, so only humans count against the limit;
	# spectators have their own.
	var watching := 0
	for other: Client in clients.values():
		watching += 1 if other.spectator else 0
	if hello.spectate:
		if watching >= MAX_SPECTATORS:
			return "server full"
	elif clients.size() - watching + (1 if local_player_id != 0 else 0) >= max_combatants:
		return "server full"
	var c := Client.new()
	c.id = id
	c.spectator = hello.spectate
	c.name = sanitize_name(hello.name)
	c.uuid = hello.uuid
	c.character = hello.character
	c.color = hello.color
	c.primary = clampi(hello.primary, 0, Loadouts.PRIMARIES.size() - 1)
	_expire_departed()
	var back: Dictionary = _departed.get(hello.token, {})
	if not back.is_empty() and _player_id_free(back.player_id):
		_departed.erase(hello.token)
		c.player_id = back.player_id
		c.restored_score = back.score
		c.restored_team = back.get("team", -1)
		c.token = hello.token
	else:
		c.player_id = _allocate_player_id()
		c.token = ((_rng.randi() & 0x3FFFFFFF) << 32) | _rng.randi() | 1
	clients[id] = c
	return ""


## Player ids are allocated by the server, independent of the transport's
## peer ids (PLAN §3.20 composite peer contract: one id space owned here).
func _allocate_player_id() -> int:
	for i in 998:
		var candidate := _next_player_id
		_next_player_id = 2 + (_next_player_id - 1) % 998
		var reserved := false
		for d: Dictionary in _departed.values():
			reserved = reserved or d.player_id == candidate
		if _player_id_free(candidate) and not reserved:
			return candidate
	return 0


func _player_id_free(candidate: int) -> bool:
	if world.players.has(candidate):
		return false
	for c: Client in clients.values():
		if c.player_id == candidate:
			return false
	return true


func _expire_departed() -> void:
	var now := Time.get_ticks_msec()
	for t in _departed.keys():
		if now > _departed[t].expires_ms:
			_departed.erase(t)


## Player names: control characters removed, 3-16 characters (PLAN §3.7).
static func sanitize_name(raw: String) -> String:
	var out := ""
	for ch in raw.strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	out = out.left(16)
	return out if out.length() >= 3 else "Player"


func _on_peer_joined(id: int) -> void:
	var c: Client = clients.get(id)
	if c == null:
		transport.kick(id)
		return
	transport.send(id, Protocol.encode_welcome(c.player_id, match_id, phase, phase_seq, completed_tick(), world.match_seed, map_id, c.token),
			Protocol.CH_CONTROL, true)
	transport.send(id, Protocol.encode_phase(match_id, phase_seq, phase, world.tick, phase_ends_tick, world.match_seed),
			Protocol.CH_CONTROL, true)
	transport.send(id, Protocol.encode_roster(match_id, roster(), game_mode, world.team_scores), Protocol.CH_CONTROL, true)


func _on_peer_left(id: int) -> void:
	var c: Client = clients.get(id)
	clients.erase(id)
	if c != null and not c.spectator:
		if c.loaded:
			var gone: SimPlayer = world.players.get(c.player_id)
			_departed[c.token] = {"player_id": c.player_id, "score": world.scores.get(c.player_id, 0),
					"team": gone.team if gone != null else -1, "expires_ms": Time.get_ticks_msec() + RECONNECT_WINDOW_MS}
		world.remove_player(c.player_id)
		stats.remove_player(c.player_id, world.tick)
	update_bot_fill()
	_on_humans_changed()


func _on_message(id: int, data: PackedByteArray) -> void:
	var c: Client = clients.get(id)
	var type := Protocol.message_type(data)
	if c == null or not type in Protocol.CLIENT_MESSAGES:
		anomalies += 1
		return
	if c.spectator and type == Protocol.Msg.CMD:
		return  # spectators have no player to command
	match type:
		Protocol.Msg.CMD:
			_on_commands(c, data)
		Protocol.Msg.PING:
			var ping := Protocol.decode_ping(data)
			if not ping.is_empty():
				transport.send(id, Protocol.encode_pong(ping.time, completed_tick(), Engine.get_physics_interpolation_fraction()),
						Protocol.CH_GAME, false)
		Protocol.Msg.PONG:
			var pong := Protocol.decode_pong(data)
			if not pong.is_empty():
				var rtt := float((Time.get_ticks_msec() - pong.echo) & 0xFFFFFFFF)
				if rtt < 5000.0:
					c.rtt_ms = lerpf(c.rtt_ms, rtt, 0.3)
		Protocol.Msg.LOADOUT:
			var primary := Protocol.decode_loadout(data)
			if primary < 0 or c.spectator:
				anomalies += 1
			else:
				c.primary = primary
				set_primary(c.player_id, primary)
		Protocol.Msg.LOADED:
			var loaded := Protocol.decode_loaded(data)
			if loaded.is_empty():
				anomalies += 1
			elif not c.loaded and c.spectator:
				c.loaded = true  # snapshots and events from now on; no player
			elif not c.loaded:
				c.loaded = true
				var joined := world.add_player(c.player_id, _loadout_for(c.primary), c.name, false)
				_join_team(joined, c.restored_team if c.restored_team >= 0 else team_plan.get(c.uuid, -1))
				joined.character = c.character
				joined.color = c.color
				stats.add_player(c.player_id, c.name, false, world.tick)
				if c.restored_score != 0:
					world.scores[c.player_id] = c.restored_score
				update_bot_fill()
				_on_humans_changed()


func _on_commands(c: Client, data: PackedByteArray) -> void:
	var msg := Protocol.decode_commands(data)
	if msg.is_empty():
		anomalies += 1
		return
	if msg.match_id != match_id:
		return  # stale match: drop (PLAN §3.3.3)
	if msg.ack > c.ack and msg.ack <= world.tick:
		c.ack = msg.ack
		c.pending = c.pending.filter(func(p: Array) -> bool: return p[1] < 0 or p[1] > c.ack)
	var now := server_time()
	for cmd: PlayerCommand in msg.cmds:
		if c.last_processed < 0:
			c.last_processed = cmd.tick - 1
		if cmd.tick <= c.last_processed or c.queue.has(cmd.tick):
			continue  # duplicate or late: later commands carry its presses
		if cmd.tick > c.last_processed + MAX_TARGET_BUFFER + MAX_FUTURE_TICKS:
			anomalies += 1
			continue
		c.queue[cmd.tick] = cmd
		c.arrival[cmd.tick] = now
		c.arrival_offsets.add(now - cmd.tick)


## `tick_entities`: every player quantized once this tick, shared by all clients.
func _send_snapshot(c: Client, tick_entities: Dictionary) -> void:
	if transport.is_stream(c.id) and not _stream_ready(c):
		return
	var snap := Snapshot.new()
	snap.id = completed_tick()
	snap.match_id = match_id
	snap.phase_seq = phase_seq
	snap.baseline_id = c.ack if c.sent.has(c.ack) else 0
	snap.last_cmd_tick = c.last_processed if c.last_processed >= 0 else Snapshot.NO_COMMAND
	snap.buffer_delta = clampi(roundi((c.buffer_avg - c.target_buffer) * 10.0), -127, 127)
	for id in tick_entities:
		if id != c.player_id:
			snap.entities[id] = tick_entities[id]
	var me: SimPlayer = world.players.get(c.player_id)
	if me != null:
		snap.owner_state = me.state
		snap.owner_gen = me.entity_gen & 0xFF
	for it in world.items:
		snap.items.append({"id": it.id, "weapon": it.weapon, "position": it.position})
	for f in world.flags:
		snap.flags.append({"team": f.team, "carrier": f.carrier, "position": f.position,
				"return_ticks": maxi(f.return_tick - world.tick, 0) if f.return_tick > 0 else 0})
	if waves != null:
		snap.wave = {"wave": waves.wave, "fighting": waves.fighting, "left": waves.enemies_left(),
				"next": waves.ticks_to_next()}
	snap.spot_ticks.resize(world.pickup_spots.size())
	for i in world.pickup_spots.size():
		snap.spot_ticks[i] = world.spot_ticks_left(i)
	for proj in world.projectiles:
		snap.projectiles.append({"owner": proj.owner_id, "gen": proj.owner_gen & 0xFF, "action": proj.action_seq,
				"weapon": Protocol.weapon_index(proj.weapon.id),
				"position": proj.position, "velocity": proj.velocity})
	var events: Array[PackedByteArray] = []
	for p in c.pending:
		if events.size() >= Snapshot.MAX_EVENTS:
			break
		if p[1] < 0:
			p[1] = snap.id
		events.append(p[0])
	var bytes := snap.encode(c.sent.get(snap.baseline_id, {}) if snap.baseline_id != 0 else {}, events)
	c.sent[snap.id] = snap.entities
	for t in c.sent.keys():
		if t < snap.id - BASELINE_HISTORY_TICKS:
			c.sent.erase(t)
	transport.send(c.id, bytes, Protocol.CH_GAME, false)
	transport.stats.on_snapshot(bytes.size())


## WebSocket clients (PLAN §3.20 rule 4): false while the stream is backed
## up (this snapshot is dropped; a newer one replaces it). A long backlog
## makes the next snapshot a full state, a very long one drops the client.
func _stream_ready(c: Client) -> bool:
	var now := Time.get_ticks_msec()
	if transport.buffered_bytes(c.id) > STREAM_BACKLOG_BYTES:
		if c.backlog_since_ms == 0:
			c.backlog_since_ms = now
		var age := now - c.backlog_since_ms
		if age > STREAM_DROP_MS:
			Platform.perf_log("NET dropping %s: WebSocket backlog for %d ms" % [c.name, age])
			transport.kick(c.id)
		elif age > STREAM_RESYNC_MS:
			c.resync = true
		c.coalesced += 1
		return false
	c.backlog_since_ms = 0
	if c.resync:
		c.sent.clear()  # no baseline: a full state
		c.resync = false
	return true


## Cosmetic events ride in snapshots until acked; the oldest are dropped
## first on overflow (PLAN §3.3.3).
func _queue_cosmetic(e: Dictionary) -> void:
	if not networked:
		return
	var w := Wire.Writer.new()
	if not Protocol.write_event(w, e):
		return
	for c: Client in clients.values():
		if not c.loaded:
			continue
		c.pending.append([w.data(), -1])
		while c.pending.size() > MAX_PENDING_EVENTS:
			c.pending.pop_front()


## Deaths and spawns can't be lost: reliable control channel.
func _send_reliable_event(e: Dictionary) -> void:
	if not networked:
		return
	var msg := Protocol.encode_event_message(match_id, e)
	for c: Client in clients.values():
		if c.loaded:
			transport.send(c.id, msg, Protocol.CH_CONTROL, true)


func _broadcast_roster() -> void:
	if not networked:
		return
	var msg := Protocol.encode_roster(match_id, roster(), game_mode, world.team_scores)
	for c: Client in clients.values():
		transport.send(c.id, msg, Protocol.CH_CONTROL, true)

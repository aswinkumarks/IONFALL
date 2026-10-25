extends Node3D
## One match on screen (PLAN §2.4, §3.3): offline, listen host or client.
## Offline and host run a ServerSession in this process (offline without
## networking) and render its world directly, interpolated between ticks. A
## client runs a ClientSession: the local player is predicted, everyone else
## is interpolated from snapshots. Input, HUD and effects are shared.

const MOVEMENT := preload("res://data/movement_config.tres")
const HUD_SCENE := preload("res://ui/hud/hud.tscn")
const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const LOBBY := "res://ui/lobby/lobby.tscn"
## A client suspended this long reconnects instead of waiting for the old
## connection (the server times it out after 10 s).
const RECONNECT_AFTER_MS := 5000
const DEATH_CAM_SECONDS := 3.0
## Touch auto-melee reach (the melee weapon reaches 2.2 m from the eye).
const TOUCH_MELEE_RANGE := 2.0
## Clients from a lobby wait this long for the host's match to listen.
const LOBBY_HANDOVER_SECONDS := 1.5
## Joining the match from the lobby is retried this often (the host's socket
## may still be switching from the lobby to the match).
const HANDOVER_ATTEMPTS := 5

var config: MatchConfig
var server: ServerSession  ## offline and host
var client: ClientSession  ## client
var _stats_at: float = 0.0  ## _time of the next FPS/latency refresh
var _touch_melee_at: float = 0.0  ## no touch auto-melee press before this _time
var input := InputAdapter.new()
var view := FirstPersonView.new()
var effects := Effects.new()
var pickups := PickupVisuals.new()
var flag_visuals := FlagVisuals.new()
var pad_visuals := JumpPadVisuals.new()
var _flag_bases: Array = []  ## CTF: the map's flag bases
var _aim_assist := AimAssist.new()
var audio := GameAudio.new()
var hud: Hud
var touch := TouchControls.new()

var _visuals: Dictionary = {}  ## net id -> PlayerVisual
var _prev: Dictionary = {}  ## host: net id -> PlayerSimState at the previous tick
var _started: bool = false
var _paused: bool = false
var _leaving: bool = false
var _pause_panel: Control
var _banner: Label
var _info: Label
var _time: float = 0.0
var _loadout: Array[WeaponData] = []
var _spawns: Array[Transform3D] = []
var _paused_at_ms: int = 0  ## when the app was last suspended (0: not suspended)
var _reconnect_until_ms: int = 0  ## reconnecting while non-zero
var _online_code: String = ""  ## hosting online: the invite code (decision 0005)
var _to_lobby: bool = false  ## going back to the lobby: the online game stays open
var _join_attempt: int = 0
var _confirm_panel: Control
var _settings_menu: SettingsMenu
var _autopilot: WanderInput
var _kill_feed: KillFeed
var _scoreboard: MatchPanel
var _results: MatchPanel
var _death_label: Label
var _loadout_bar: HBoxContainer  ## primary choice while respawning (PLAN §2.6)
## The scoreboard on the pause menu, right of its buttons.
var _pause_scores: MatchPanel
## Spectator mode: the player we watch (0 until one is picked).
var _spec_target: int = 0
var _spec_dead_since: Dictionary = {}  ## networked spectator: id -> server tick its death was seen
var _results_until: float = 0.0
## Death cam (PLAN §2.6): {pos, killer, until} while active.
var _death_cam: Dictionary = {}
var _arms_ready: bool = false  ## first-person arms built (see _ensure_arms)
var _arms_color := Color.WHITE
var _life_dealt: float = 0.0
var _life_taken: float = 0.0
var _remote_cache: Dictionary = {}  ## client: latest remote render states
## Our own tally of the current match, for partial results if the match
## never sends RESULTS (we quit or the host vanished, PLAN §3.13).
var _last_slot: int = -1
var _last_reload: int = 0
var _last_shield: float = 100.0
var _shield_rising: bool = false
var _tally := MatchStats.new()
var _tally_match: int = 0
var _results_applied: bool = false
var _perf_ms := FrameStats.new(7200)  ## frame times of the current minute
var _perf_gpu := FrameStats.new(7200)  ## GPU time per frame (ms)
var _perf_cpu := FrameStats.new(7200)  ## main thread: process + physics time (ms)
var _perf_render_cpu := FrameStats.new(7200)  ## rendering CPU time (ms)
var _perf_minute_start_ms: int = 0
var _perf_frames: int = 0
var _tick_ms := FrameStats.new(3600)  ## host: server tick times of the current minute
var _sim_ms := FrameStats.new(3600)  ## host: of which simulation
var _banner_phase: int = -1
var _go_until: float = 0.0
var _adaptive := AdaptiveQuality.new()
var _perf_hitches: int = 0  ## frames over HITCH_MS this minute (cold-start stutter, PLAN §5)
var _warming: bool = false
var _perf_peaks := Vector3i.ZERO  ## this minute's most draw calls, primitives, live particles


func _ready() -> void:
	config = MatchConfig.pending if MatchConfig.pending != null else MatchConfig.new()
	MatchConfig.pending = null
	if not Maps.has(config.map):
		config.map = Maps.DEFAULT
	var gameplay := Maps.gameplay(config.map)
	add_child(gameplay)
	pickups.spots = gameplay.pickup_spots()
	_flag_bases = gameplay.flag_bases() if gameplay.has_method("flag_bases") else []
	if gameplay.has_method("jump_pads"):
		pad_visuals.build(gameplay.jump_pads())
	var presentation := Maps.presentation(config.map)
	add_child(presentation)
	_apply_shadows(presentation)
	Settings.apply_environment(presentation)
	Events.settings_changed.connect(func(section: String, _key: String, _value: Variant) -> void:
		if section == "video":
			_apply_shadows(presentation)
			Settings.apply_environment(presentation))
	add_child(input)
	add_child(view)
	add_child(effects)
	add_child(pickups)
	add_child(flag_visuals)
	add_child(pad_visuals)
	add_child(audio)
	audio.launched.connect(pad_visuals.launched)
	audio.listener = view.camera
	_build_ui()
	audio.caption.connect(hud.show_caption)
	if not Platform.user_args.has("--no-warmup"):  # dev: cold-start comparison
		_warm_up()
	else:
		LoadingCover.take(self, config).queue_free()
		MatchPreload.release()
	get_tree().root.get_window().focus_exited.connect(_on_focus_lost)
	Diagnostics.net_info = _net_info
	if Platform.user_args.has("--adpf"):  # ADPF spike (docs/decisions/0004-thermals-adpf.md)
		Platform.start_performance_hints(1000.0 / maxf(float(Settings.get_value("video", "fps_cap")), 1.0))
	# Static world bodies become queryable after the first physics step.
	await get_tree().physics_frame
	var loadout := Loadouts.ffa()
	var spawns: Array[Transform3D] = gameplay.spawn_points()
	_loadout = loadout
	_spawns = spawns
	if config.mode == MatchConfig.Mode.JOIN:
		if config.spectate:
			input.enabled = false
			touch.visible = false
		if config.online:
			_info.text = tr("NET_ONLINE_JOINING") % config.online_code
		if not await _start_client(config.reconnect_token):
			return
		if not config.online:
			_info.text = tr("NET_CONNECTING") % config.address
	else:
		server = ServerSession.new()
		server.name = "Server"
		server.map_id = config.map
		if Platform.get_user_arg("--time-limit").is_valid_int():  # dev: short matches
			server.time_limit_ticks = Platform.get_user_arg("--time-limit").to_int() * Sim.TICK_RATE
		elif config.minutes > 0:
			server.time_limit_ticks = config.minutes * 60 * Sim.TICK_RATE
		server.use_primaries = true
		server.game_mode = config.game_mode
		server.friendly_fire = config.friendly_fire
		server.bot_difficulty = config.bot_difficulty
		add_child(server)
		var port := config.port if config.mode == MatchConfig.Mode.HOST and not config.online else -1
		var online_peer: MultiplayerPeer = null
		if config.online:
			_info.text = tr("NET_ONLINE_SIGNING_IN")
			var info := {"name": tr("NET_GAME_OF") % config.player_name, "map": config.map,
					"mode": GameMode.IDS[config.game_mode], "max": config.max_combatants(), "state": "playing"}
			# From a lobby the game (and its code) already exists; its peer
			# was closed and the match listens on a new one.
			var hosted: Dictionary = Online.serve() if config.from_lobby \
					else await Online.host(config.player_name, config.max_combatants(), info)
			if hosted.has("error"):
				_fail(tr("NET_ONLINE_ERROR") % hosted.error)
				return
			online_peer = hosted.peer
			_online_code = Online.hosting_code
			Online.update_info(info)
		var err := server.start(port, MOVEMENT, loadout, spawns, gameplay.pickup_spots(), online_peer,
				gameplay.flag_bases())
		if err != OK:
			_fail(tr("NET_HOST_ERROR") % [config.port, error_string(err)])
			return
		var nav := BotNavigation.new()
		nav.name = "BotNavigation"
		add_child(nav)
		nav.build(gameplay)  # async: bots wait until it's ready
		server.bot_nav = nav
		server.max_combatants = config.max_combatants()
		# The host's bots stay as players join; a spectator's place goes to one more.
		server.bot_count = config.bots + (1 if config.spectate else 0)
		server.lobby_after_match = config.from_lobby
		server.team_plan = config.team_plan
		server.team_names = config.team_names
		server.team_colors = config.team_colors
		GameMode.team_names = config.team_names
		GameMode.team_colors = config.team_colors
		server.match_over.connect(_back_to_lobby)
		if config.spectate:
			server.add_local_spectator()
			input.enabled = false
			touch.visible = false
		else:
			var me := server.add_local_player(config.player_name, config.character, config.color, config.primary,
					MatchConfig.profile_uuid())
			input.look_yaw = me.state.yaw
		if config.online:
			_info.text = tr("NET_ONLINE_HOSTING") % _online_code
			Platform.perf_log("ONLINE hosting with invite code %s" % _online_code)
		elif config.mode == MatchConfig.Mode.HOST:
			_info.text = tr("NET_HOSTING") % [", ".join(Discovery.lan_addresses()), config.port]
			var advertiser := Discovery.Advertiser.new()
			advertiser.beacon_source = server.beacon.bind(tr("NET_GAME_OF") % config.player_name, false, config.port)
			add_child(advertiser)
		_snapshot_prev()
	if config.mode != MatchConfig.Mode.OFFLINE:
		Platform.set_low_latency_network(true)
	if not Platform.is_mobile() and not spectating():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_started = true


func _exit_tree() -> void:
	Platform.set_low_latency_network(false)
	if not _online_code.is_empty() and not _to_lobby:
		Online.stop_hosting()
	if Diagnostics.net_info == _net_info:
		Diagnostics.net_info = Callable()


## Creates the ClientSession and starts joining. `token` != 0 reconnects as
## the same player (PLAN §3.4).
func _start_client(token: int) -> bool:
	if client != null:
		client.leave()
		client.queue_free()
		effects.reset_seen()  # event ids restart with the new session
	client = ClientSession.new()
	client.name = "Client"
	client.player_name = config.player_name
	client.character = config.character
	client.color = config.color
	client.primary = config.primary
	client.spectate = config.spectate
	client.uuid = MatchConfig.profile_uuid()
	client.reconnect_token = token
	client.input_source = _local_command
	add_child(client)
	client.joined.connect(func() -> void:
		# Clients load the map before joining (prediction needs its collision).
		if client.map_id != config.map:
			client.leave()
			if Maps.has(client.map_id) and not config.map_retried:
				# Load the host's map and join again (manual address joins
				# don't know it beforehand).
				config.map = client.map_id
				config.map_retried = true
				MatchConfig.pending = config
				get_tree().reload_current_scene.call_deferred()
			else:
				_fail(tr("NET_MAP_MISMATCH") % client.map_id))
	client.lobby_called.connect(_back_to_lobby)
	client.failed.connect(_on_client_lost)
	client.left.connect(_on_client_lost)
	if config.from_lobby and token == 0:
		# The host leaves the lobby and opens the match at the same moment.
		await get_tree().create_timer(LOBBY_HANDOVER_SECONDS).timeout
	var online_peer: MultiplayerPeer = null
	if config.online:
		var joined: Dictionary = await Online.connect_to(config.player_name, config.online_host) \
				if not config.online_host.is_empty() else await Online.join(config.player_name, config.online_code)
		if joined.has("error"):
			match joined.error:
				"not_found": _fail(tr("NET_ONLINE_NOT_FOUND") % config.online_code)
				"version": _fail("NET_ONLINE_VERSION")
				_: _fail(tr("NET_ONLINE_ERROR") % joined.error)
			return false
		online_peer = joined.peer
		config.online_host = joined.host_id  # the lobby reconnects to it after the match
	var err := client.join(config.address, config.port, MOVEMENT, _loadout, _spawns, online_peer)
	if config.from_lobby and token == 0:
		# An online connection can hang instead of failing: retry it too.
		var attempt := _join_attempt
		var joining := client
		get_tree().create_timer(15.0).timeout.connect(func() -> void:
			if client == joining and client.local_id == 0 and attempt == _join_attempt and not _leaving:
				_on_client_lost("connection failed"))
	if err != OK:
		_fail(tr("NET_CONNECT_ERROR") % error_string(err))
		return false
	return true


func _on_client_lost(reason: String) -> void:
	if _reconnect_until_ms != 0:
		return  # the reconnect loop retries
	# Dropped mid-match (our network blipped, or the server timed us out):
	# rejoin with our token while the server keeps our place.
	if reason == "disconnected" and _started and not _leaving and client.reconnect_token != 0:
		_reconnect_until_ms = Time.get_ticks_msec() + ServerSession.RECONNECT_WINDOW_MS
		_reconnect_step.call_deferred()
		return
	if reason == "connection failed" and config.from_lobby and client.local_id == 0 \
			and _join_attempt + 1 < HANDOVER_ATTEMPTS and not _leaving:
		_join_attempt += 1
		Platform.perf_log("MATCH join attempt %d failed, retrying" % _join_attempt)
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if not _leaving:
				_start_client(0))
		return
	match reason:
		"disconnected":
			_fail("NET_DISCONNECTED")
		"connection failed":
			_fail("NET_ONLINE_UNREACHABLE" if config.online else "NET_UNREACHABLE")
		"server_shutdown":
			_fail("NET_SERVER_SHUTDOWN")
		_:
			_fail(reason)


## After the app was suspended: rejoin with our token until the window closes.
func _reconnect_step() -> void:
	if Time.get_ticks_msec() > _reconnect_until_ms:
		_reconnect_until_ms = 0
		_fail("NET_RECONNECT_FAILED")
		return
	var token := client.reconnect_token
	_start_client(token)
	get_tree().create_timer(4.0).timeout.connect(func() -> void:
		if _reconnect_until_ms != 0 and not _leaving and not client.is_live():
			_reconnect_step())


## Shader warm-up behind a loading cover (Warmup).
func _warm_up() -> void:
	var cover := LoadingCover.take(self, config)
	# A kill-feed row too: its fonts' first glyphs cost up to ~0.6 s on the
	# Mi 11X (m4.md), which used to land on the first kill.
	var glyphs := "ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz 0123456789_-.,+"
	_kill_feed.add_death({"killer": -1, "victim": -2, "weapon": &"rail_sniper", "suicide": false,
			"headshot": true, "assists": [-3]}, func(_id: int) -> String: return glyphs, -1)
	var warm := Warmup.new()
	add_child(warm)
	_warming = true
	warm.progress.connect(cover.set_progress)
	warm.slow.connect(cover.show_slow_note)
	warm.finished.connect(func() -> void:
		_warming = false
		_kill_feed.clear()
		Diagnostics.hitch_log = Platform.user_args.has("--perf-log")
		MatchPreload.release()
		cover.queue_free())
	var started := Time.get_ticks_msec()
	warm.finished.connect(func() -> void: Platform.perf_log("Warmup: %d ms" % (Time.get_ticks_msec() - started)))
	warm.start(view.camera, effects)


## The sun's realtime shadows and the map's reflection probe (PLAN §3.10
## scalable settings).
func _apply_shadows(root: Node) -> void:
	var on: bool = Settings.video("shadows")
	for light in root.find_children("*", "DirectionalLight3D", true, false):
		(light as DirectionalLight3D).shadow_enabled = on
	for probe in root.find_children("*", "ReflectionProbe", true, false):
		(probe as ReflectionProbe).visible = Settings.video("probe") != false


## First-person arms in the player's character and colour, once the local
## id (for the "auto" colour) is known.
## First-person arms in our colour (our team's in TDM); rebuilt if it changes.
func _ensure_arms() -> void:
	var character := config.character
	var pick := config.color
	if spectating() and server != null:  # the watched player's arms
		var p: SimPlayer = server.world.players.get(_spec_target)
		character = p.character if p != null else 0
		pick = p.color if p != null else 0
	elif spectating():
		character = 0
		pick = 0
		for p in client.roster:
			if p.id == _spec_target:
				character = p.character
				pick = p.color
	var team := _team_of(local_id())
	var color: Color = GameMode.team_color(team) if team < 2 else PlayerVisual.color_for(local_id(), pick)
	if _arms_ready and color == _arms_color:
		return
	_arms_ready = true
	_arms_color = color
	view.set_character(CharacterRig.selectable_style(character), color)


func _game_mode() -> int:
	return server.game_mode if server != null else client.game_mode


## TDM team of player `id`; GameMode.NO_TEAM in FFA.
## A teammate of the local player (TDM).
func _is_ally(id: int) -> bool:
	var team := _team_of(id)
	return team != GameMode.NO_TEAM and team == _team_of(local_id())


func _team_of(id: int) -> int:
	if not GameMode.is_team_mode(_game_mode()):
		return GameMode.NO_TEAM
	if server != null:
		var p: SimPlayer = server.world.players.get(id)
		return p.team if p != null else GameMode.NO_TEAM
	return client.team_of(id)


func _team_scores() -> PackedInt32Array:
	return server.world.team_scores if server != null else client.team_scores


## Whose eyes the match is seen through: our player, or the watched one
## while spectating (so hit markers, damage and the death cam follow them).
func local_id() -> int:
	if spectating():
		return _spec_target
	return client.local_id if client != null else ServerSession.LOCAL_PLAYER_ID


func spectating() -> bool:
	return (server != null and server.local_spectating) or (client != null and client.spectate)


# --- Simulation (host / offline) ---

## Runs before the ServerSession steps (parents process first): records the
## previous tick for interpolation and hands it the local player's command.
func _physics_process(_delta: float) -> void:
	if not _started or server == null:
		return
	_snapshot_prev()
	if server.last_step_usec > 0:
		_tick_ms.add(server.last_step_usec / 1000.0)  # the previous tick
		_sim_ms.add(server.last_sim_usec / 1000.0)
	server.local_command = _local_command(server.world.tick)


## The local player's command: from input, or from a bot while the overlay's
## autopilot is on (soak tests).
func _local_command(tick: int) -> PlayerCommand:
	if not Diagnostics.autopilot:
		return input.build_command(tick)
	if _autopilot == null:
		_autopilot = WanderInput.new(randi())
	var cmd := _autopilot.command_for(tick)
	input.look_yaw = cmd.yaw_radians()
	return cmd


func _snapshot_prev() -> void:
	for id in server.world.players:
		_prev[id] = server.world.get_player(id).state.copy()


# --- Rendering ---

func _process(delta: float) -> void:
	if not _started:
		return
	_time += delta
	_log_perf(delta)
	var t0 := Time.get_ticks_usec()
	var events: Array[Dictionary] = server.drain_host_events() if server != null else client.drain_events()
	for e in events:
		var te := Time.get_ticks_usec()
		_handle_event(e)
		Diagnostics.time_section("ev_" + str(e.type), te)
	Diagnostics.time_section("events", t0)
	t0 = Time.get_ticks_usec()
	if server != null:
		_render_host(delta)
	else:
		_watch_connection()
		if client.is_predicting():
			_render_client(delta)
		elif client.spectate and client.latest_snapshot != null:
			_render_client_spectator(delta)
	Diagnostics.time_section("visuals", t0)
	t0 = Time.get_ticks_usec()
	_update_aim_assist(delta)
	_touch_melee()
	_update_stats()
	_update_banner()
	_update_match_ui(delta)
	Diagnostics.time_section("ui", t0)


## Touch aim assist (PLAN §3.11): slowdown, magnetism and optional
## auto-fire on visible enemies, as rendered.
func _update_aim_assist(delta: float) -> void:
	var me := _local_player()
	if not touch.visible or not Settings.get_value("input", "aim_assist") or me == null or not me.state.alive:
		touch.assist_scale = 1.0
		input.assist_fire = false
		return
	var my_team := _team_of(local_id())
	var targets := {}
	for id: int in _visuals:
		var v: PlayerVisual = _visuals[id]
		if v.visible and (my_team == GameMode.NO_TEAM or _team_of(id) != my_team):
			targets[id] = v.global_position + Vector3(0.0, 1.2, 0.0)
	var firing := (input.touch_held & PlayerCommand.Held.FIRE) != 0
	var pull := _aim_assist.update(delta, view.camera.global_transform, me.current_weapon(), firing,
			Settings.get_value("input", "auto_fire"), targets, view.camera.get_world_3d().direct_space_state)
	input.add_look(pull.x, pull.y)
	touch.assist_scale = _aim_assist.slowdown
	input.assist_fire = _aim_assist.wants_fire


## Host-loss detection on the client (PLAN §3.5.1): 3 s without packets shows
## a warning, 10 s goes back to the menu. Not while reconnecting.
func _watch_connection() -> void:
	if _reconnect_until_ms != 0:
		if client.is_live():
			_reconnect_until_ms = 0
			_info.text = ""
		else:
			_info.text = tr("NET_RECONNECTING") % ceili((_reconnect_until_ms - Time.get_ticks_msec()) / 1000.0)
		return
	if client.local_id == 0:
		return  # still connecting: ENet reports failure
	var silent := client.seconds_silent()
	if silent >= 10.0:
		_fail("NET_HOST_LOST")
	elif silent >= 3.0:
		_info.text = tr("NET_HOST_PAUSED") if client.host_paused else tr("NET_HOST_NOT_RESPONDING")
	elif client.is_live() and not spectating():
		_info.text = ""


func _render_host(delta: float) -> void:
	if spectating():
		_render_spectator(delta)
		return
	var world := server.world
	var alpha := Engine.get_physics_interpolation_fraction()
	var me := world.get_player(ServerSession.LOCAL_PLAYER_ID)
	var s := me.state
	var prev: PlayerSimState = _prev.get(me.net_id)
	var from := prev if prev != null and prev.discontinuity_gen == s.discontinuity_gen else s
	_ensure_arms()
	_update_scope(s)
	if s.alive:
		input.confirm_slot(s.weapon_slot)
	view.update_view(from.position.lerp(s.position, alpha), me.config.eye_for(s.stance), input.look_yaw,
			input.look_pitch, s, me.current_weapon(), delta)
	var seen := {}
	for id in world.players:
		if id == me.net_id:
			continue
		var p: SimPlayer = world.players[id]
		seen[id] = true
		_visual_for(id, p.display_name, p.is_bot, p.character, p.color).update_from(_prev.get(id), p.state, alpha, _time)
		audio.update_player(id, p.state, false, _is_ally(id))
	audio.update_player(me.net_id, s, true)
	_prune_visuals(seen)
	effects.sync_projectiles(world.projectiles, alpha)
	var spot_ticks := PackedInt32Array()
	for i in world.pickup_spots.size():
		spot_ticks.append(world.spot_ticks_left(i))
	pickups.sync(world.items, spot_ticks)
	if _game_mode() == GameMode.CTF:
		flag_visuals.sync(world.flags, _flag_bases, _flag_carrier_at)
	_update_pickup_hud(s, world.items, spot_ticks)
	hud.update_state(s, me.current_weapon(), world.scores.get(me.net_id, 0), s.respawn_tick - world.tick)


## Spectator mode: the watched player's own view (camera, weapon, HUD), with
## everyone else drawn as usual.
func _render_spectator(delta: float) -> void:
	var world := server.world
	if not world.players.has(_spec_target):
		_cycle_spectator(1)
		if not world.players.has(_spec_target):
			return  # no one to watch yet
	var alpha := Engine.get_physics_interpolation_fraction()
	var p: SimPlayer = world.players[_spec_target]
	var s := p.state
	var prev: PlayerSimState = _prev.get(p.net_id)
	var from := prev if prev != null and prev.discontinuity_gen == s.discontinuity_gen else s
	_ensure_arms()
	view.set_scope(null)
	hud.set_scope(0.0, false)
	view.update_view(from.position.lerp(s.position, alpha), p.config.eye_for(s.stance),
			lerp_angle(from.yaw, s.yaw, alpha), lerpf(from.pitch, s.pitch, alpha), s, p.current_weapon(), delta)
	var seen := {}
	for id in world.players:
		if id == p.net_id:
			continue
		var other: SimPlayer = world.players[id]
		seen[id] = true
		_visual_for(id, other.display_name, other.is_bot, other.character, other.color).update_from(_prev.get(id), other.state, alpha, _time)
		audio.update_player(id, other.state, false, _is_ally(id))
	audio.update_player(p.net_id, s, true)
	_prune_visuals(seen)
	effects.sync_projectiles(world.projectiles, alpha)
	var spot_ticks := PackedInt32Array()
	for i in world.pickup_spots.size():
		spot_ticks.append(world.spot_ticks_left(i))
	pickups.sync(world.items, spot_ticks)
	var names := PackedStringArray()
	for i in s.weapons.size():
		var w := s.weapon(i)
		names.append(KillFeed.weapon_tag(w.id) if KillFeed.WEAPON_TAGS.has(w.id) else tr(w.display_name))
	hud.set_slots(names, s.weapon_slot)
	hud.update_state(s, p.current_weapon(), world.scores.get(p.net_id, 0), s.respawn_tick - world.tick)
	_info.text = tr("SPECTATE_WATCHING") % _display_name(p.net_id) + "\n" + tr(
			"SPECTATE_HINT_TOUCH" if DisplayServer.is_touchscreen_available() else "SPECTATE_HINT")


## A networked spectator (PLAN §2.7): the watched player as the server sent
## them (interpolated like every remote player), seen from their eyes.
func _render_client_spectator(delta: float) -> void:
	var states := client.remote_states()
	_remote_cache = states
	if not states.has(_spec_target):
		_cycle_spectator(1)
		if not states.has(_spec_target):
			return  # no one to watch yet
	var s: PlayerSimState = states[_spec_target].copy()
	var weapon: WeaponData = Weapons.at(s.weapons[0]) if Weapons.at(s.weapons[0]) != null else _loadout[0]
	# Snapshots carry the held weapon but not its ammo: show a full magazine.
	s.mag = PackedInt32Array([weapon.mag_size])
	s.reserve = PackedInt32Array([0])
	s.reload = PackedInt32Array([0])
	_ensure_arms()
	view.set_scope(null)
	hud.set_scope(0.0, false)
	view.update_view(s.position, MOVEMENT.eye_for(s.stance), s.yaw, s.pitch, s, weapon, delta)
	var names := {}
	for p in client.roster:
		names[p.id] = p
	var seen := {}
	for id in states:
		if id == _spec_target:
			continue
		var info: Dictionary = names.get(id, {"name": "?", "bot": false, "character": 0, "color": 0})
		seen[id] = true
		_visual_for(id, info.name, info.bot, info.character, info.color).update_from(null, states[id], 1.0, _time)
		audio.update_player(id, states[id], false, _is_ally(id))
	audio.update_player(_spec_target, s, true)
	_prune_visuals(seen)
	var ahead := (client.clock.server_time() - client.latest_snapshot.id) * Sim.TICK_DT
	var rockets := []
	for proj in client.projectiles:
		rockets.append({"id": proj.id, "weapon": proj.weapon, "position": proj.position + proj.velocity * ahead,
				"velocity": proj.velocity})
	effects.sync_projectiles(rockets, 1.0)
	pickups.sync(client.items, client.spot_ticks)
	hud.set_slots(PackedStringArray([KillFeed.weapon_tag(weapon.id) if KillFeed.WEAPON_TAGS.has(weapon.id) \
			else tr(weapon.display_name)]), 0)
	# The respawn timer isn't sent: count from when the death was seen.
	var now := client.clock.server_time()
	var respawn := 0
	if s.alive:
		_spec_dead_since.erase(_spec_target)
	else:
		var since: float = _spec_dead_since.get_or_add(_spec_target, now)
		respawn = ceili(GameMode.respawn_ticks(_game_mode()) - (now - since))
	hud.update_state(s, weapon, client.score_of(_spec_target), respawn)
	_info.text = tr("SPECTATE_WATCHING") % _display_name(_spec_target) + "\n" + tr(
			"SPECTATE_HINT_TOUCH" if DisplayServer.is_touchscreen_available() else "SPECTATE_HINT")


## Spectator mode: watch the next (`step` 1) or previous (-1) combatant.
func _cycle_spectator(step: int) -> void:
	var ids: Array = server.world.players.keys() if server != null else \
			(client.latest_snapshot.entities.keys() if client.latest_snapshot != null else [])
	if ids.is_empty():
		return
	ids.sort()
	var i := ids.find(_spec_target)
	_spec_target = ids[posmod(i + step, ids.size()) if i >= 0 else 0]
	_death_cam = {}
	_arms_ready = false


## The interact prompt for the nearest item that needs one, and the power
## weapon timers (PLAN §2.3: the HUD shows the countdown).
func _update_pickup_hud(s: PlayerSimState, items: Array, spot_ticks: PackedInt32Array) -> void:
	var prompt := ""
	var best := Balance.PLAYER.pickup_radius + 0.3
	for it in items:
		var weapon: int = it.weapon
		var pos: Vector3 = it.position
		var d := Vector2(pos.x - s.position.x, pos.z - s.position.z).length()
		if s.alive and d < best and absf(pos.y - s.position.y) < SimWorld.PICKUP_HEIGHT \
				and SimWorld.needs_interact(s, weapon):
			best = d
			prompt = tr("HUD_PICKUP_SWAP") % [InputAdapter.key_name("interact"), tr(Weapons.at(weapon).display_name).to_upper()]
	hud.set_prompt(prompt)
	touch.show_interact = not prompt.is_empty()
	var timers := PackedStringArray()
	for i in pickups.spots.size():
		var def: Dictionary = pickups.spots[i]
		if def.weapon == &"grenade":
			continue
		var tag: String = KillFeed.weapon_tag(def.weapon)
		var ticks: int = spot_ticks[i] if i < spot_ticks.size() else 0
		var secs := ceili(ticks / float(Sim.TICK_RATE))
		timers.append("%s %s" % [tag, tr("HUD_PICKUP_READY") if ticks == 0 else "%d:%02d" % [floori(secs / 60.0), secs % 60]])
	hud.set_pickup_timers(" · ".join(timers))


## Touch has no melee button: holding fire on an enemy within arm's reach,
## in front of us, melees instead.
func _touch_melee() -> void:
	var me := _local_player()
	if not touch.visible or me == null or not me.state.alive or me.state.melee_cooldown > 0 \
			or (input.touch_held & PlayerCommand.Held.FIRE) == 0 or _time < _touch_melee_at:
		return
	var eye := view.camera.global_position
	var ahead := -view.camera.global_basis.z
	var my_team := _team_of(local_id())
	for id: int in _visuals:
		var v: PlayerVisual = _visuals[id]
		if not v.visible or (my_team != GameMode.NO_TEAM and _team_of(id) == my_team):
			continue
		var to := v.global_position + Vector3(0.0, 1.0, 0.0) - eye
		if to.length() <= TOUCH_MELEE_RANGE and ahead.dot(to.normalized()) > 0.6:
			input.press(PlayerCommand.Action.MELEE)
			_touch_melee_at = _time + 0.3
			return


## The HUD's FPS and latency readout, refreshed twice a second.
func _update_stats() -> void:
	if _time < _stats_at:
		return
	_stats_at = _time + 0.5
	var rtt := roundi(client.clock.rtt_ms) if client != null else -1
	hud.set_stats(roundi(Engine.get_frames_per_second()), rtt)


## Scope (PLAN §2.3): the sim tightens the spread while aim is held; the view
## zooms, the HUD shows the scope and look slows down to match the zoom.
func _update_scope(s: PlayerSimState) -> void:
	if not s.alive:
		touch.scope_on = false
	var scoped := input.aim_held() and WeaponSim.can_scope(s)
	view.set_scope(s.weapon() if scoped else null)
	hud.set_scope(view.scope_amount, view.scope_overlay_visible())
	var weapon := s.weapon()
	var zoom := lerpf(1.0, weapon.scope_zoom, view.scope_amount) if weapon != null else 1.0
	input.look_scale = 1.0 / maxf(zoom, 1.0)


func _render_client(delta: float) -> void:
	var me := client.pred
	var s := me.state
	var prev := client.prev_state
	var from := prev if prev != null and prev.discontinuity_gen == s.discontinuity_gen else s
	var feet := from.position.lerp(s.position, client.alpha()) + client.correction_offset
	_ensure_arms()
	_update_scope(s)
	if s.alive:
		input.confirm_slot(s.weapon_slot)
	view.update_view(feet, me.config.eye_for(s.stance), input.look_yaw, input.look_pitch, s, me.current_weapon(), delta)
	var names := {}
	for p in client.roster:
		names[p.id] = p
	var seen := {}
	var states := client.remote_states()
	_remote_cache = states
	for id in states:
		var info: Dictionary = names.get(id, {"name": "?", "bot": false, "character": 0, "color": 0})
		seen[id] = true
		_visual_for(id, info.name, info.bot, info.character, info.color).update_from(null, states[id], 1.0, _time)
		audio.update_player(id, states[id], false, _is_ally(id))
	audio.update_player(client.local_id, s, true)
	_prune_visuals(seen)
	# Snapshot projectiles, moved along their velocity to the current server time.
	var ahead := (client.clock.server_time() - client.latest_snapshot.id) * Sim.TICK_DT
	var rockets := []
	for proj in client.projectiles:
		rockets.append({"id": proj.id, "weapon": proj.weapon, "position": proj.position + proj.velocity * ahead,
				"velocity": proj.velocity})
	effects.sync_projectiles(rockets, 1.0)
	pickups.sync(client.items, client.spot_ticks)
	if _game_mode() == GameMode.CTF:
		flag_visuals.sync(client.flags, _flag_bases, _flag_carrier_at)
	_update_pickup_hud(s, client.items, client.spot_ticks)
	var server_state := client.server_state if client.server_state != null else s
	# Health, shield and death come from the server; movement and ammo are predicted.
	var shown := s.copy()
	shown.shield = server_state.shield
	shown.health = server_state.health
	shown.alive = server_state.alive
	shown.spawn_protection_ticks = server_state.spawn_protection_ticks
	hud.update_state(shown, me.current_weapon(), client.score_of(client.local_id),
			ceili(server_state.respawn_tick - client.clock.server_time()))


## One line per minute in the log (`adb logcat -s godot`) for sustained
## tests against PLAN §3.10: frame-time percentiles, minute average fps,
## host tick time, network health and thermal status.
const HITCH_MS := 50.0


func _log_perf(delta: float) -> void:
	if _warming:
		return
	Platform.report_frame_work((Performance.get_monitor(Performance.TIME_PROCESS) \
			+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0 + RenderingServer.get_frame_setup_time_cpu())
	if Settings.get_value("video", "adaptive_quality") and not _paused:
		var step := _adaptive.add_frame(delta, int(Settings.get_value("video", "fps_cap")))
		if not step.is_empty():
			Platform.perf_log("QUALITY step-down %s" % step)
	var now := Time.get_ticks_msec()
	if _perf_minute_start_ms == 0:
		_perf_minute_start_ms = now
	_perf_ms.add(delta * 1000.0)
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	_perf_gpu.add(RenderingServer.viewport_get_measured_render_time_gpu(vp))
	_perf_cpu.add((Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	_perf_render_cpu.add(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
	_perf_frames += 1
	if delta * 1000.0 > HITCH_MS:
		_perf_hitches += 1
	_perf_peaks = _perf_peaks.max(Vector3i(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), effects.live_particles))
	if now - _perf_minute_start_ms < 60000:
		return
	var seconds := (now - _perf_minute_start_ms) / 1000.0
	var line := "PERF mode=%s fps_avg=%.1f p50=%.1f p95=%.1f p99=%.1f hitches=%d" % [
		["offline", "host", "client"][config.mode], _perf_frames / seconds,
		_perf_ms.percentile(50.0), _perf_ms.percentile(95.0), _perf_ms.percentile(99.0), _perf_hitches]
	_perf_hitches = 0
	line += " spec_total=%d" % Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
	line += " " + Diagnostics.section_report()
	line += " gpu_p50=%.1f gpu_p95=%.1f main_p50=%.1f main_p95=%.1f render_cpu_p50=%.1f render_cpu_p95=%.1f" % [
			_perf_gpu.percentile(50.0), _perf_gpu.percentile(95.0), _perf_cpu.percentile(50.0), _perf_cpu.percentile(95.0),
			_perf_render_cpu.percentile(50.0), _perf_render_cpu.percentile(95.0)]
	if server != null:
		line += " tick_p50=%.2f tick_p99=%.2f sim_p99=%.2f players=%d clients=%d" % [_tick_ms.percentile(50.0),
				_tick_ms.percentile(99.0), _sim_ms.percentile(99.0), server.world.players.size(), server.clients.size()]
		_tick_ms = FrameStats.new(3600)
		_sim_ms = FrameStats.new(3600)
	if client != null:
		line += " rtt=%.0f corrections=%d visible=%d snaps=%d" % [client.clock.rtt_ms, client.corrections,
				client.visible_corrections, client.snaps]
	line += " draws_max=%d prims_max=%d particles_max=%d tex_mib=%.0f" % [_perf_peaks.x, _perf_peaks.y, _perf_peaks.z,
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0]
	line += " thermal=%d headroom=%.2f scale=%.2f autopilot=%s" % [Platform.thermal_status(), Platform.thermal_headroom(),
			get_tree().root.scaling_3d_scale, Diagnostics.autopilot]
	_perf_peaks = Vector3i.ZERO
	Platform.perf_log(line)
	_perf_ms = FrameStats.new(7200)
	_perf_gpu = FrameStats.new(7200)
	_perf_cpu = FrameStats.new(7200)
	_perf_render_cpu = FrameStats.new(7200)
	_perf_frames = 0
	_perf_minute_start_ms = now


# --- Profile: results and partial tallies ---

func _track_tally(e: Dictionary) -> void:
	var match_id: int = server.match_id if server != null else client.match_id
	if match_id != _tally_match:
		_tally = MatchStats.new()
		_tally_match = match_id
		_results_applied = false
	for p in _roster():
		if not _tally.lines.has(p.id):
			_tally.add_player(p.id, p.name, p.bot, 0)
	_tally.on_event(e)


## Leaving (or losing the host) before RESULTS: save what we saw ourselves
## as an incomplete match; unconfirmed when the host vanished.
func _save_partial(confirmed: bool) -> void:
	var phase := server.phase if server != null else client.phase
	if spectating() or _results_applied or not (phase == MatchPhase.PLAYING or phase == MatchPhase.SUDDEN_DEATH):
		return
	var me := local_id()
	var l: MatchStats.Line = _tally.lines.get(me)
	if l == null:
		return
	var row := {"id": me, "bot": false, "name": l.name, "score": 0,
			"ticks_played": roundi(_time * Sim.TICK_RATE), "weapon_kills": l.weapon_kills}
	for k in Protocol.RESULT_COUNTERS:
		row[k] = l.get(k)
	var partial := {"result_id": "partial-%08x-%d" % [_tally_match, me], "winner": 0, "humans": 2, "players": [row]}
	Profile.apply_results(partial, me, false, confirmed)
	_results_applied = true


# --- Match UI: kill feed, death cam, scoreboard, results, timer ---

func _roster() -> Array:
	return server.roster() if server != null else client.roster


func _display_name(id: int) -> String:
	for p in _roster():
		if p.id == id:
			return ("[BOT] " if p.bot else "") + p.name
	return "?"


## Where another player is rendered right now (Vector3.INF if unknown).
func _position_of(id: int) -> Vector3:
	if server != null:
		var p: SimPlayer = server.world.players.get(id)
		return p.state.position if p != null else Vector3.INF
	var st: PlayerSimState = _remote_cache.get(id)
	return st.position if st != null else Vector3.INF


func _vitals_of(id: int) -> Vector2:
	if server != null:
		var p: SimPlayer = server.world.players.get(id)
		return Vector2(p.state.shield, p.state.health) if p != null else Vector2.ZERO
	var st: PlayerSimState = _remote_cache.get(id)
	return Vector2(st.shield, st.health) if st != null else Vector2.ZERO


## Where a flag carrier is drawn: us at our view, others as rendered.
func _flag_carrier_at(id: int) -> Vector3:
	if id == local_id():
		var me := _local_player()
		return me.state.position if me != null else Vector3.INF
	var v: PlayerVisual = _visuals.get(id)
	return v.global_position if v != null else _position_of(id)


## The mode's objective line (PLAN §2.4): CTF flag status, co-op wave.
func _update_objective() -> void:
	var mode := _game_mode()
	if mode == GameMode.CTF:
		var flags: Array = server.world.flags if server != null else client.flags
		var my_team := _team_of(local_id())
		if flags.size() < 2 or my_team > 1:
			hud.set_objective("")
			return
		var own: Variant = flags[my_team]
		var enemy: Variant = flags[1 - my_team]
		if enemy.carrier == local_id():
			hud.set_objective(tr("CTF_CARRYING"), GameMode.team_color(1 - my_team))
		elif own.carrier != 0:
			hud.set_objective(tr("CTF_OUR_FLAG_TAKEN") % _display_name(own.carrier), UiStyle.WARN)
		elif _flag_dropped(own):
			hud.set_objective(tr("CTF_OUR_FLAG_DROPPED") % ceili(_flag_return_ticks(own) / float(Sim.TICK_RATE)), UiStyle.WARN)
		elif enemy.carrier != 0:
			hud.set_objective(tr("CTF_WE_HAVE_FLAG") % _display_name(enemy.carrier), GameMode.team_color(my_team))
		else:
			hud.set_objective(tr("CTF_GOAL"), UiStyle.TEXT_DIM)
	elif mode == GameMode.WAVES:
		var w: Dictionary = {}
		if server != null and server.waves != null:
			w = {"wave": server.waves.wave, "fighting": server.waves.fighting, "left": server.waves.enemies_left(),
					"next": server.waves.ticks_to_next()}
		elif client != null:
			w = client.wave
		if w.is_empty():
			hud.set_objective("")
		elif w.fighting:
			hud.set_objective(tr("WAVES_FIGHTING") % [w.wave, Balance.MODES.wave_count, w.left], UiStyle.WARN)
		else:
			hud.set_objective(tr("WAVES_NEXT") % [w.wave + 1, ceili(w.next / float(Sim.TICK_RATE))], UiStyle.ACCENT)
	else:
		hud.set_objective("")


func _flag_dropped(f: Variant) -> bool:
	return f.carrier == 0 and (f.return_tick > 0 if f is SimWorld.Flag else f.return_ticks > 0)


func _flag_return_ticks(f: Variant) -> int:
	return maxi(f.return_tick - server.world.tick, 0) if f is SimWorld.Flag else int(f.return_ticks)


func _update_match_ui(delta: float) -> void:
	hud.set_view(view.global_position, input.look_yaw)
	var phase := server.phase if server != null else client.phase
	var ends := server.phase_ends_tick if server != null else client.phase_ends_tick
	var now := float(server.world.tick) if server != null else client.clock.server_time()
	var playing := phase == MatchPhase.PLAYING or phase == MatchPhase.SUDDEN_DEATH
	# Co-op has no clock: the waves end it.
	hud.set_timer(maxi(ceili((ends - now) / Sim.TICK_RATE), 0), playing and _game_mode() != GameMode.WAVES)
	_update_objective()
	var my_team := _team_of(local_id())
	# Co-op shows the wave instead (_update_objective).
	hud.set_teams(my_team, _team_scores() if my_team < 2 and _game_mode() != GameMode.WAVES else PackedInt32Array())
	var me := _local_player()
	if me != null:
		var names := PackedStringArray()
		for i in me.state.weapons.size():
			var w := me.state.weapon(i)
			names.append(KillFeed.weapon_tag(w.id) if KillFeed.WEAPON_TAGS.has(w.id) else tr(w.display_name))
		hud.set_slots(names, me.state.weapon_slot)
		_local_sounds(me.state)
	# Death cam: 3 s looking at the killer from where we died.
	var dead := me != null and not me.state.alive
	if dead and not _death_cam.is_empty() and _time < _death_cam.until:
		var killer_pos := _position_of(_death_cam.killer)
		if not _death_cam.suicide and killer_pos != Vector3.INF:
			view.death_cam(_death_cam.pos, killer_pos + Vector3(0.0, 1.3, 0.0), delta)
			var v := _vitals_of(_death_cam.killer)
			_death_label.text = "%s\n%s\n%s" % [tr("DEATH_KILLED_BY") % _display_name(_death_cam.killer),
					tr("DEATH_KILLER_STATUS") % [ceili(v.x), ceili(v.y)],
					tr("DEATH_DAMAGE") % [roundi(_life_dealt), roundi(_life_taken)]]
		else:
			_death_label.text = tr("DEATH_SUICIDE")
		_death_label.visible = true
	else:
		_death_label.visible = false
	var choosing := dead and not _results.visible
	input.keep_cursor = choosing
	if choosing != _loadout_bar.visible:
		_loadout_bar.visible = choosing
		if not Platform.is_mobile() and not _paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if choosing else Input.MOUSE_MODE_CAPTURED
			# Firing when we died: that button's release may land on the
			# loadout bar, so don't carry the held trigger into the respawn.
			input.release_mouse()
	_banner.visible = not _results.visible
	# Results until the next match starts; the scoreboard while held.
	if _results.visible:
		if phase != MatchPhase.POST_MATCH:
			_results.visible = false
		else:
			_results.footer.text = (_results.footer_extra + "\n" if not _results.footer_extra.is_empty() else "") \
					+ tr("RESULTS_NEXT_MATCH") % maxi(ceili(_results_until - _time), 0)
	var subtitle := tr(MatchPhase.label_key(phase)) if phase != MatchPhase.PLAYING else ""
	# Co-op waves has teams but no team score race (its progress is on the HUD).
	var team_scores := _team_scores() if GameMode.is_team_mode(_game_mode()) and _game_mode() != GameMode.WAVES \
			else PackedInt32Array()
	if Input.is_action_pressed("scoreboard") and not _results.visible and not _paused:
		_scoreboard.show_scoreboard(_roster(), local_id(), subtitle, team_scores)
	else:
		_scoreboard.visible = false
	# The pause menu shows the scores too (the way to see them on touch).
	if _paused:
		_pause_scores.show_scoreboard(_roster(), local_id(), subtitle, team_scores)


## Our own reload, weapon switch and shield recharge sounds, from state changes.
func _local_sounds(s: PlayerSimState) -> void:
	if s.weapon_slot != _last_slot and _last_slot >= 0 and s.alive:
		audio.play_ui("switch", -4.0)
	_last_slot = s.weapon_slot
	var reloading: int = s.reload[s.weapon_slot]
	var held := s.weapon()
	var shells := held != null and held.reload_per_round
	# Shell-by-shell reloads restart the timer for each shell.
	if reloading > 0 and (_last_reload == 0 or (shells and reloading > _last_reload)):
		audio.play_at("reload_shell" if shells else "reload", view.global_position, "UI", 2, -6.0)
	_last_reload = reloading
	var rising := s.shield > _last_shield + 0.01
	if rising and not _shield_rising and s.shield < Balance.PLAYER.max_shield * 0.5:
		audio.cue("shield_recharge", "CAPTION_SHIELD_RECHARGING")
	_shield_rising = rising
	_last_shield = s.shield


func _local_player() -> SimPlayer:
	if server != null:
		return server.world.get_player(ServerSession.LOCAL_PLAYER_ID)
	return client.pred


## `character`, `color`: the player's picks (CharacterRig.SELECTABLE and
## PlayerVisual.PALETTE indices); the visual is rebuilt if they change (a
## client may see a player before the roster arrives).
func _visual_for(id: int, display_name: String, is_bot: bool, character: int, color_pick: int) -> PlayerVisual:
	var v: PlayerVisual = _visuals.get(id)
	var style := CharacterRig.selectable_style(character)
	var team := _team_of(id)
	var color: Color = GameMode.team_color(team) if team < 2 else PlayerVisual.color_for(id, color_pick, is_bot)
	if v != null and (v.rig_style != style or v.color != color):
		v.queue_free()
		v = null
	if v == null:
		v = PlayerVisual.new()
		add_child(v)
		v.setup(display_name, is_bot, color, id, style)
		if team < 2:
			v.set_label_color(color.lightened(0.35))
			v.set_team(team, color.lightened(0.35))
		_visuals[id] = v
	return v


func _prune_visuals(seen: Dictionary) -> void:
	for id in _visuals.keys():
		if not seen.has(id):
			_visuals[id].queue_free()
			_visuals.erase(id)
			audio.forget_player(id)


func _update_banner() -> void:
	var phase := server.phase if server != null else client.phase
	var ends := server.phase_ends_tick if server != null else client.phase_ends_tick
	var now := float(server.world.tick) if server != null else client.clock.server_time()
	var text := ""
	match phase:
		MatchPhase.WAITING:
			text = tr("PHASE_WAITING")
		MatchPhase.COUNTDOWN:
			text = tr("PHASE_COUNTDOWN") % maxi(ceili((ends - now) / Sim.TICK_RATE), 1)
		MatchPhase.POST_MATCH:
			text = tr("PHASE_POST_MATCH")
		MatchPhase.PLAYING:
			if _banner_phase == MatchPhase.COUNTDOWN:
				_go_until = _time + 1.2
			if _time < _go_until:
				text = tr("PHASE_GO")
	_banner_phase = phase
	text = text.to_upper()
	if text != _banner.text:
		_banner.text = text
		# Each new line (countdown numbers, FIGHT) pops in.
		_banner.pivot_offset = _banner.size * 0.5
		_banner.scale = Vector2(1.35, 1.35)
		_banner.modulate = UiStyle.ACCENT if phase == MatchPhase.PLAYING else Color.WHITE
		create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).tween_property(_banner, "scale", Vector2.ONE, 0.3)
		if phase == MatchPhase.COUNTDOWN or phase == MatchPhase.PLAYING:
			audio.play_ui("go" if phase == MatchPhase.PLAYING else "countdown", -6.0)


func _handle_event(e: Dictionary) -> void:
	if not effects.first_time(e):
		return
	_track_tally(e)
	var me := local_id()
	match e.type:
		"fire":
			var local: bool = e.shooter == me
			var sound := "arc_launch" if e.weapon == &"arc_launcher" else String(e.weapon)
			audio.play_at(sound, e.origin, "Weapons", 2 if local else 4, -4.0 if local else 0.0)
			if not local and e.origin.distance_to(view.global_position) < 25.0:
				hud.on_gunfire_from(e.origin)
			var muzzle := Vector3.INF
			if not local and _visuals.has(e.shooter):
				var shooter: PlayerVisual = _visuals[e.shooter]
				shooter.on_fire()
				muzzle = shooter.muzzle_position()
				if muzzle != Vector3.INF and e.weapon not in [&"melee", &"frag_grenade"]:
					effects.muzzle_flash(muzzle)
			if local and e.weapon == &"melee":
				view.melee()
			elif local and e.weapon == &"frag_grenade":
				view.throw()
			elif local:
				var heavy: bool = e.weapon in [&"arc_launcher", &"rail_sniper", &"scatter_gun"]
				view.kick(2.0 if heavy else 1.0)
				hud.on_fired(2.0 if heavy else 1.0)
				if e.get("predicted_hit", false):
					hud.on_hit_marker(false, false)
			if e.has("end"):
				var from: Vector3 = view.muzzle_position() if local else (muzzle if muzzle != Vector3.INF else e.origin)
				effects.tracer(from, e.end, e.weapon == &"rail_sniper")
				if e.hit_world or e.hit_player:
					effects.impact(e.end, e.hit_player)
		"explosion":
			effects.explosion(e.position, 4.0)
			audio.play_at("explosion", e.position, "World", 3)
		"hit":
			if _visuals.has(e.target) and e.target != me:
				(_visuals[e.target] as PlayerVisual).flash_hit(e.shield_broken, _position_of(e.attacker))
			if e.attacker == me and e.target != me:
				hud.on_hit_marker(true, e.killed)
				audio.play_ui("kill_confirm" if e.killed else "hit_marker", -2.0)
				if view.meleeing():  # hits don't name the weapon; our bash is in flight
					view.melee_impact()
					audio.play_ui("melee_hit", 0.0)
				_life_dealt += e.amount
			if e.target == me:
				_life_taken += e.amount
				if e.attacker != me and _position_of(e.attacker) != Vector3.INF:
					hud.on_damaged_from(_position_of(e.attacker))
				else:
					hud.on_damaged()
				if e.shield_broken:
					hud.on_shield_broken()
					audio.cue("shield_break", "CAPTION_SHIELD_BROKEN")
		"death":
			_kill_feed.add_death(e, _display_name, me)
			if e.victim != me and _visuals.has(e.victim):
				effects.derez(e.position, (_visuals[e.victim] as PlayerVisual).color)
			if e.victim == me:
				_death_cam = {"pos": e.position + Vector3(0.0, 1.6, 0.0), "killer": e.killer,
						"until": _time + DEATH_CAM_SECONDS, "suicide": e.suicide}
		"results":
			_results.show_results(e, -1 if spectating() else me)
			_results_applied = true
			_results.footer_extra = ""
			if not spectating():  # watching earns nothing
				var gained := Profile.apply_results(e, me)
				_results.show_xp(gained, Profile.data.xp())
			_results_until = _time + Balance.MODES.post_match_ticks / float(Sim.TICK_RATE)
		"spawn":
			if e.player == me:
				input.look_yaw = e.yaw
				input.look_pitch = 0.0
				_death_cam = {}
				_life_dealt = 0.0
				_life_taken = 0.0
				audio.play_ui("spawn", -6.0)
			elif _visuals.has(e.player):
				effects.spawn_in(e.position, (_visuals[e.player] as PlayerVisual).color)
				audio.play_at("spawn", e.position, "World", 1, -4.0)
		"flag":
			_on_flag_event(e, me)
		"wave":
			if e.action == "start":
				_kill_feed.add_note(tr("WAVES_WAVE") % e.wave, tr("WAVES_INCOMING") % e.enemies, UiStyle.WARN)
				audio.cue("countdown", tr("CAPTION_WAVE_START") % e.wave)
			else:
				_kill_feed.add_note(tr("WAVES_WAVE") % e.wave, tr("WAVES_CLEARED"), UiStyle.GOOD)
				audio.cue("go", "CAPTION_WAVE_CLEARED")
		"pickup":
			effects.pickup_burst(e.position + Vector3(0.0, 0.6, 0.0), PickupVisuals.color_of(e.weapon))
			if e.player == me:
				audio.play_ui("pickup", -4.0)
			else:
				audio.play_at("pickup", e.position, "World", 1, -6.0)


## CTF events: a kill-feed line, a caption and a cue for the ones about us.
func _on_flag_event(e: Dictionary, me: int) -> void:
	var team: int = e.team
	var who := _display_name(e.player) if e.player != 0 else tr("CTF_NOBODY")
	var mine := team == _team_of(me)
	var keys := {"take": "CTF_FEED_TAKE", "drop": "CTF_FEED_DROP", "return": "CTF_FEED_RETURN", "capture": "CTF_FEED_CAPTURE"}
	var what: String = tr(keys[e.action]) % GameMode.team_name(team)
	var carrier_team: int = 1 - team if e.action in ["take", "drop", "capture"] else team
	_kill_feed.add_note(who, what, GameMode.team_color(carrier_team), e.player == me)
	if e.action == "take":
		audio.cue("shield_break", "CAPTION_OUR_FLAG_TAKEN" if mine else "CAPTION_FLAG_TAKEN")
	elif e.action == "capture":
		audio.cue("kill_confirm", "CAPTION_FLAG_LOST" if mine else "CAPTION_FLAG_CAPTURED")
	elif e.action == "return":
		audio.cue("pickup", "CAPTION_FLAG_RETURNED")
	effects.pickup_burst(e.position + Vector3(0.0, 0.8, 0.0), GameMode.team_color(team))


func _net_info() -> String:
	if client != null:
		var st := client.transport.stats
		var last_cmd := client.latest_snapshot.last_cmd_tick if client.latest_snapshot != null else 0
		return "NET client id %d  rtt %.0f ms  interp %d  rate %.3f\nlead %.1f ticks (pred %d, server %.1f, last cmd %d)  clock samples %d\nin %.1f kB/s  out %.1f kB/s (wire)  snapshot p50 %d max %d B\ncorrections %d  visible %d  snaps %d  bad snapshots %d" % [
			client.local_id, client.clock.rtt_ms, client.interp_ticks, client.rate(),
			client.pred_tick - client.clock.server_time(), client.pred_tick, client.clock.server_time(), last_cmd,
			client.clock.sample_count(),
			st.wire_bytes_in_per_s() / 1000.0, st.wire_bytes_out_per_s() / 1000.0,
			st.snapshot_sizes.percentile(50.0), st.max_snapshot,
			client.corrections, client.visible_corrections, client.snaps, client.undecodable_snapshots]
	if server != null and server.networked:
		var st := server.transport.stats
		var rtts := PackedStringArray()
		for c: ServerSession.Client in server.clients.values():
			rtts.append("%d:%.0fms" % [c.player_id, c.rtt_ms])
		return "NET host  clients %d [%s]\nin %.1f kB/s  out %.1f kB/s (wire)  snapshot p50 %d max %d B\nanomalies %d  ingress drops %d" % [
			server.clients.size(), " ".join(rtts), st.wire_bytes_in_per_s() / 1000.0, st.wire_bytes_out_per_s() / 1000.0,
			st.snapshot_sizes.percentile(50.0), st.max_snapshot, server.anomalies, server.transport.ingress_drops]
	return "NET offline"


# --- UI, pause, leaving ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD_SCENE.instantiate()
	layer.add_child(hud)
	hud.pause_requested.connect(_set_paused.bind(true))
	_banner = _make_label(44, UiStyle.TEXT)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 120.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_banner)
	_info = _make_label(18, UiStyle.TEXT_DIM)
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_info.offset_top = -40.0
	_info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_info)
	_kill_feed = KillFeed.new()
	_kill_feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_kill_feed.offset_left = -560.0
	_kill_feed.offset_right = -24.0
	_kill_feed.offset_top = 176.0 if DisplayServer.is_touchscreen_available() else 24.0
	_kill_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_kill_feed)
	_death_label = _make_label(28, UiStyle.TEXT)
	_death_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_death_label.offset_top = -250.0
	_death_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_death_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_death_label.visible = false
	layer.add_child(_death_label)
	_loadout_bar = HBoxContainer.new()
	_loadout_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_loadout_bar.offset_top = -190.0
	_loadout_bar.offset_bottom = -120.0
	_loadout_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loadout_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_loadout_bar.add_theme_constant_override("separation", 12)
	_loadout_bar.visible = false
	var caption := _make_label(18, UiStyle.TEXT_DIM)
	caption.text = "LOADOUT_PRIMARY"
	_loadout_bar.add_child(caption)
	for i in Loadouts.PRIMARIES.size():
		var b := Button.new()
		b.text = Loadouts.PRIMARIES[i].display_name
		b.toggle_mode = true
		b.button_pressed = i == config.primary
		b.custom_minimum_size = Vector2(170, 56)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_choose_primary.bind(i))
		_loadout_bar.add_child(b)
	layer.add_child(_loadout_bar)
	_scoreboard = MatchPanel.new()
	layer.add_child(_scoreboard)
	_results = MatchPanel.new()
	layer.add_child(_results)
	touch.input = input
	touch.hud_target = hud.touch_target
	layer.add_child(touch)
	_pause_panel = _make_pause_panel()
	layer.add_child(_pause_panel)
	_confirm_panel = _make_confirm_panel()
	layer.add_child(_confirm_panel)
	_settings_menu = SettingsMenu.new()
	layer.add_child(_settings_menu)


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiStyle.font_display_bold)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_pause_panel() -> Control:
	var parts := UiStyle.menu_overlay()
	var root: Control = parts[0]
	var box: VBoxContainer = parts[1]
	root.visible = false
	box.add_child(UiStyle.label("PAUSE_TITLE", &"HeaderLabel"))
	var bar := ColorRect.new()
	bar.color = UiStyle.ACCENT
	bar.custom_minimum_size = Vector2(72, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(bar)
	box.add_child(Control.new())
	var resume := UiStyle.menu_button("PAUSE_RESUME", &"PrimaryButton")
	resume.pressed.connect(_set_paused.bind(false))
	box.add_child(resume)
	root.visibility_changed.connect(func() -> void:
		if root.visible:
			resume.grab_focus())
	var settings := UiStyle.menu_button("MENU_SETTINGS")
	settings.pressed.connect(func() -> void: _settings_menu.open())
	box.add_child(settings)
	var leave := UiStyle.menu_button("PAUSE_LEAVE", &"GhostButton")
	leave.pressed.connect(_ask_leave)
	box.add_child(leave)
	var hint := UiStyle.label("PAUSE_CONTROLS_HINT", &"DimLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.visible = not DisplayServer.is_touchscreen_available()
	box.add_child(Control.new())
	box.add_child(hint)
	if config.mode == MatchConfig.Mode.HOST:
		box.add_child(_make_join_code())
	_pause_scores = MatchPanel.new()
	# Centred in the space right of the button column.
	_pause_scores.anchor_left = 0.68
	_pause_scores.anchor_right = 0.68
	root.add_child(_pause_scores)
	return root


## Hosts show their join code under the pause buttons: the online invite
## code, or a LAN QR code (PLAN §3.6) that a phone camera opens as an
## ionfall://join link, which starts the game and joins.
func _make_join_code() -> Control:
	var addresses := Discovery.lan_addresses()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	if not _online_code.is_empty():
		box.add_child(UiStyle.label("PAUSE_INVITE_CODE", &"DimLabel", HORIZONTAL_ALIGNMENT_LEFT))
		var code := UiStyle.label(_online_code, &"TitleLabel", HORIZONTAL_ALIGNMENT_LEFT)
		box.add_child(code)
		return box
	if addresses.is_empty():
		return box
	var link := "ionfall://join?host=%s&port=%d" % [addresses[0], config.port]
	var qr := QrCode.encode(link)
	if qr == null:
		return box
	box.add_child(UiStyle.label("PAUSE_SCAN_TO_JOIN", &"DimLabel", HORIZONTAL_ALIGNMENT_LEFT))
	var tex := TextureRect.new()
	tex.texture = ImageTexture.create_from_image(qr.to_image(8))
	tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tex.custom_minimum_size = Vector2(170, 170)
	tex.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(tex)
	box.add_child(UiStyle.label("%s:%d" % [addresses[0], config.port], &"DimLabel", HORIZONTAL_ALIGNMENT_LEFT))
	return box


## Leaving an online match asks first (PLAN §3.5.1); offline just leaves.
func _ask_leave() -> void:
	if config.mode == MatchConfig.Mode.OFFLINE:
		_leave()
		return
	var label: Label = _confirm_panel.find_child("Text", true, false)
	label.text = tr("LEAVE_CONFIRM_HOST") if config.mode == MatchConfig.Mode.HOST else tr("LEAVE_CONFIRM_CLIENT")
	_confirm_panel.visible = true


func _make_confirm_panel() -> Control:
	var parts := UiStyle.menu_overlay()
	var root: Control = parts[0]
	var box: VBoxContainer = parts[1]
	box.name = "Box"
	root.visible = false
	var text := UiStyle.label("", &"HeaderLabel")
	text.name = "Text"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.add_theme_font_size_override("font_size", 30)
	box.add_child(text)
	var no := UiStyle.menu_button("LEAVE_CONFIRM_NO", &"PrimaryButton")
	no.pressed.connect(func() -> void: root.visible = false)
	box.add_child(no)
	var yes := UiStyle.menu_button("LEAVE_CONFIRM_YES")
	yes.pressed.connect(_leave)
	box.add_child(yes)
	return root


## Offline, pausing stops the simulation. Online matches can't pause: the
## panel only stops local input (PLAN §3.5.1).
func _set_paused(paused: bool) -> void:
	_paused = paused
	_pause_panel.visible = paused
	_kill_feed.visible = not paused  # on touch it sits where the pause scoreboard opens
	if not paused:
		_confirm_panel.visible = false
	input.enabled = not paused and not spectating()
	input.reset_held()
	touch.release_all()
	if server != null and config.mode == MatchConfig.Mode.OFFLINE:
		server.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	if paused or spectating():
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not Platform.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Primary for the next spawn, saved to the profile (PLAN §2.5).
func _choose_primary(i: int) -> void:
	config.primary = i
	Settings.set_value("profile", "primary", i)
	Settings.save_settings()
	if server != null:
		server.set_primary(server.local_player_id, i)
	elif client != null:
		client.send_loadout(i)
	for k in Loadouts.PRIMARIES.size():
		(_loadout_bar.get_child(k + 1) as Button).button_pressed = k == i


## The lobby match is over (results shown): everyone goes back to the
## host's lobby. The host tells the clients first, then reopens the lobby on
## the same port or online game.
func _back_to_lobby() -> void:
	if _leaving:
		return
	_leaving = true
	_to_lobby = true
	Platform.perf_log("MATCH over: back to the lobby")
	if server != null:
		server.notify_clients(Protocol.Notice.RETURN_TO_LOBBY)
		await get_tree().create_timer(0.5).timeout
	else:
		client.leave()
	config.mode = MatchConfig.Mode.HOST if server != null else MatchConfig.Mode.JOIN
	config.from_lobby = true
	config.reconnect_token = 0
	config.map_retried = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	MatchConfig.pending = config
	get_tree().change_scene_to_file.call_deferred(LOBBY)


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	_save_partial(MatchConfig.last_error.is_empty())  # host gone: unconfirmed
	if client != null:
		client.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU)


## Back to the menu, which shows `reason` (a translation key or text).
func _fail(reason: String) -> void:
	if _to_lobby:
		return  # the host closed the match on purpose
	MatchConfig.last_error = reason
	Platform.perf_log("MATCH left: %s" % tr(reason))
	# Lost to the network after joining: the menu offers to rejoin while the
	# server would still take our token back.
	if client != null and client.reconnect_token != 0 and reason.begins_with("NET_"):
		MatchConfig.rejoin = {"config": config, "token": client.reconnect_token,
				"until_ms": Time.get_ticks_msec() + ServerSession.RECONNECT_WINDOW_MS - 10000}
	_leave()


## Escape / Android back (Platform turns it into ui_cancel): dismiss the
## leave question, else toggle the pause menu.
func _unhandled_input(event: InputEvent) -> void:
	if spectating() and not _paused and _spectator_switch(event) != 0:
		_cycle_spectator(_spectator_switch(event))
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _confirm_panel.visible:
			_confirm_panel.visible = false
		else:
			_set_paused(not _paused)
		get_viewport().set_input_as_handled()


## Spectator controls: click, Space or → for the next player; right click
## or ← for the previous one. A tap arrives as a click (unless a button took
## it). 0: not a switch.
func _spectator_switch(event: InputEvent) -> int:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			return 1
		if event.button_index == MOUSE_BUTTON_RIGHT:
			return -1
	elif event.is_action_pressed("jump") or event.is_action_pressed("ui_right"):
		return 1
	elif event.is_action_pressed("ui_left"):
		return -1
	return 0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_paused_at_ms = Time.get_ticks_msec()
			if server != null:
				server.notify_clients(Protocol.Notice.HOST_PAUSED)
			if _started:
				_set_paused(true)
		NOTIFICATION_APPLICATION_RESUMED:
			_on_resumed()


## Best effort after a suspension (PLAN §3.5.1): a host tells its clients it
## is back; a client away long enough for the server to drop it rejoins with
## its reconnect token for up to 60 s.
func _on_resumed() -> void:
	var away_ms := Time.get_ticks_msec() - _paused_at_ms if _paused_at_ms != 0 else 0
	_paused_at_ms = 0
	if server != null:
		server.notify_clients(Protocol.Notice.HOST_RESUMED)
	elif client != null and _started and not _leaving and away_ms > RECONNECT_AFTER_MS:
		_reconnect_until_ms = Time.get_ticks_msec() + ServerSession.RECONNECT_WINDOW_MS - away_ms
		_reconnect_step()


func _on_focus_lost() -> void:
	if _started and not _paused:
		_set_paused(true)

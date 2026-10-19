extends Node3D
## One match on screen (PLAN §2.4, §3.3): offline, listen host or client.
## Offline and host run a ServerSession in this process (offline without
## networking) and render its world directly, interpolated between ticks. A
## client runs a ClientSession: the local player is predicted, everyone else
## is interpolated from snapshots. Input, HUD and effects are shared.

const MOVEMENT := preload("res://data/movement_config.tres")
const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const ARENA_GAMEPLAY := preload("res://maps/test_arena/gameplay.tscn")
const ARENA_PRESENTATION := preload("res://maps/test_arena/presentation.tscn")
const HUD_SCENE := preload("res://ui/hud/hud.tscn")
const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const BOT_COLOR := Color(0.95, 0.5, 0.2)
const PLAYER_COLORS := [Color(0.55, 0.45, 1.0), Color(0.3, 0.85, 0.5), Color(0.95, 0.4, 0.6), Color(0.9, 0.85, 0.3)]

var config: MatchConfig
var server: ServerSession  ## offline and host
var client: ClientSession  ## client
var input := InputAdapter.new()
var view := FirstPersonView.new()
var effects := Effects.new()
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


func _ready() -> void:
	config = MatchConfig.pending if MatchConfig.pending != null else MatchConfig.new()
	MatchConfig.pending = null
	var gameplay := ARENA_GAMEPLAY.instantiate()
	add_child(gameplay)
	add_child(ARENA_PRESENTATION.instantiate())
	add_child(input)
	add_child(view)
	add_child(effects)
	_build_ui()
	get_tree().root.get_window().focus_exited.connect(_on_focus_lost)
	Diagnostics.net_info = _net_info
	# Static world bodies become queryable after the first physics step.
	await get_tree().physics_frame
	var loadout: Array[WeaponData] = [PULSE, ARC]
	var spawns: Array[Transform3D] = gameplay.spawn_points()
	if config.mode == MatchConfig.Mode.JOIN:
		client = ClientSession.new()
		client.name = "Client"
		client.player_name = config.player_name
		client.input_source = input.build_command
		add_child(client)
		client.failed.connect(_fail)
		client.left.connect(func(_reason: String) -> void: _fail("NET_DISCONNECTED"))
		var err := client.join(config.address, config.port, MOVEMENT, loadout, spawns)
		if err != OK:
			_fail(tr("NET_CONNECT_ERROR") % error_string(err))
			return
		_info.text = tr("NET_CONNECTING") % config.address
	else:
		server = ServerSession.new()
		server.name = "Server"
		add_child(server)
		var port := config.port if config.mode == MatchConfig.Mode.HOST else -1
		var err := server.start(port, MOVEMENT, loadout, spawns)
		if err != OK:
			_fail(tr("NET_HOST_ERROR") % [config.port, error_string(err)])
			return
		var me := server.add_local_player(config.player_name)
		input.look_yaw = me.state.yaw
		for i in config.bots:
			server.add_bot("Dummy %d" % (i + 1), TargetDummyDriver.new(i * 50))
		if config.mode == MatchConfig.Mode.HOST:
			_info.text = tr("NET_HOSTING") % [", ".join(lan_addresses()), config.port]
		_snapshot_prev()
	if not Platform.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_started = true


func _exit_tree() -> void:
	if Diagnostics.net_info == _net_info:
		Diagnostics.net_info = Callable()


func local_id() -> int:
	return client.local_id if client != null else ServerSession.LOCAL_PLAYER_ID


## Private IPv4 addresses other devices on the LAN can join (PLAN §3.6).
static func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.match("172.1[6-9].*") \
				or a.match("172.2?.*") or a.match("172.3[01].*"):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out


# --- Simulation (host / offline) ---

## Runs before the ServerSession steps (parents process first): records the
## previous tick for interpolation and hands it the local player's command.
func _physics_process(_delta: float) -> void:
	if not _started or server == null:
		return
	_snapshot_prev()
	server.local_command = input.build_command(server.world.tick)


func _snapshot_prev() -> void:
	for id in server.world.players:
		_prev[id] = server.world.get_player(id).state.copy()


# --- Rendering ---

func _process(delta: float) -> void:
	if not _started:
		return
	_time += delta
	var events: Array[Dictionary] = server.drain_host_events() if server != null else client.drain_events()
	for e in events:
		_handle_event(e)
	if server != null:
		_render_host(delta)
	elif client.is_predicting():
		_render_client(delta)
	_update_banner()


func _render_host(delta: float) -> void:
	var world := server.world
	var alpha := Engine.get_physics_interpolation_fraction()
	var me := world.get_player(ServerSession.LOCAL_PLAYER_ID)
	var s := me.state
	var prev: PlayerSimState = _prev.get(me.net_id)
	var from := prev if prev != null and prev.discontinuity_gen == s.discontinuity_gen else s
	view.update_view(from.position.lerp(s.position, alpha), me.config.eye_for(s.stance), input.look_yaw,
			input.look_pitch, s, me.current_weapon(), delta)
	var seen := {}
	for id in world.players:
		if id == me.net_id:
			continue
		var p: SimPlayer = world.players[id]
		seen[id] = true
		_visual_for(id, p.display_name, p.is_bot).update_from(_prev.get(id), p.state, alpha, _time)
	_prune_visuals(seen)
	effects.sync_projectiles(world.projectiles, alpha)
	hud.update_state(s, me.current_weapon(), world.scores.get(me.net_id, 0), s.respawn_tick - world.tick)


func _render_client(delta: float) -> void:
	_info.text = ""
	var me := client.pred
	var s := me.state
	var prev := client.prev_state
	var from := prev if prev != null and prev.discontinuity_gen == s.discontinuity_gen else s
	var feet := from.position.lerp(s.position, client.alpha()) + client.correction_offset
	view.update_view(feet, me.config.eye_for(s.stance), input.look_yaw, input.look_pitch, s, me.current_weapon(), delta)
	var names := {}
	for p in client.roster:
		names[p.id] = p
	var seen := {}
	var states := client.remote_states()
	for id in states:
		var info: Dictionary = names.get(id, {"name": "?", "bot": false})
		seen[id] = true
		_visual_for(id, info.name, info.bot).update_from(null, states[id], 1.0, _time)
	_prune_visuals(seen)
	# Snapshot projectiles, moved along their velocity to the current server time.
	var ahead := (client.clock.server_time() - client.latest_snapshot.id) * Sim.TICK_DT
	var rockets := []
	for proj in client.projectiles:
		rockets.append({"id": proj.id, "position": proj.position + proj.velocity * ahead, "velocity": proj.velocity})
	effects.sync_projectiles(rockets, 1.0)
	var server_state := client.server_state if client.server_state != null else s
	# Health, shield and death come from the server; movement and ammo are predicted.
	var shown := s.copy()
	shown.shield = server_state.shield
	shown.health = server_state.health
	shown.alive = server_state.alive
	shown.spawn_protection_ticks = server_state.spawn_protection_ticks
	hud.update_state(shown, me.current_weapon(), client.score_of(client.local_id),
			ceili(server_state.respawn_tick - client.clock.server_time()))


func _visual_for(id: int, display_name: String, is_bot: bool) -> PlayerVisual:
	var v: PlayerVisual = _visuals.get(id)
	if v == null:
		v = PlayerVisual.new()
		add_child(v)
		v.setup(display_name, is_bot, BOT_COLOR if is_bot else PLAYER_COLORS[id % PLAYER_COLORS.size()])
		_visuals[id] = v
	return v


func _prune_visuals(seen: Dictionary) -> void:
	for id in _visuals.keys():
		if not seen.has(id):
			_visuals[id].queue_free()
			_visuals.erase(id)


func _update_banner() -> void:
	var phase := server.phase if server != null else client.phase
	var ends := server.phase_ends_tick if server != null else client.phase_ends_tick
	var now := float(server.world.tick) if server != null else client.clock.server_time()
	match phase:
		MatchPhase.WAITING:
			_banner.text = tr("PHASE_WAITING")
		MatchPhase.COUNTDOWN:
			_banner.text = tr("PHASE_COUNTDOWN") % maxi(ceili((ends - now) / Sim.TICK_RATE), 1)
		MatchPhase.POST_MATCH:
			_banner.text = tr("PHASE_POST_MATCH")
		_:
			_banner.text = ""


func _handle_event(e: Dictionary) -> void:
	if not effects.first_time(e):
		return
	var me := local_id()
	match e.type:
		"fire":
			var local: bool = e.shooter == me
			if local:
				view.kick(2.0 if e.weapon == &"arc_launcher" else 1.0)
			if e.has("end"):
				var from: Vector3 = view.muzzle_position() if local else e.origin
				effects.tracer(from, e.end)
				if e.hit_world or e.hit_player:
					effects.impact(e.end, e.hit_player)
		"explosion":
			effects.explosion(e.position, 4.0)
		"hit":
			if e.attacker == me and e.target != me:
				hud.on_hit_confirmed(e.killed)
			if e.target == me:
				hud.on_damaged()
		"spawn":
			if e.player == me:
				input.look_yaw = e.yaw
				input.look_pitch = 0.0


func _net_info() -> String:
	if client != null:
		var st := client.transport.stats
		return "NET client id %d  rtt %.0f ms  interp %d  rate %.3f\nin %.1f kB/s  out %.1f kB/s (wire)  snapshot p50 %d max %d B\ncorrections %d  visible %d  snaps %d  bad snapshots %d" % [
			client.local_id, client.clock.rtt_ms, client.interp_ticks, client.rate(),
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
	_banner = _make_label(32, Color(0.35, 0.9, 1.0))
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_top = 70.0
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	layer.add_child(_banner)
	_info = _make_label(16, Color(0.7, 0.75, 0.8))
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_info.offset_top = -40.0
	_info.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer.add_child(_info)
	touch.input = input
	layer.add_child(touch)
	_pause_panel = _make_pause_panel()
	layer.add_child(_pause_panel)


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _make_pause_panel() -> Control:
	var root := ColorRect.new()
	root.color = Color(0.02, 0.03, 0.05, 0.75)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position = Vector2(-260, -140)
	box.add_theme_constant_override("separation", 14)
	root.add_child(box)
	var title := Label.new()
	title.text = "PAUSE_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	box.add_child(title)
	var resume := Button.new()
	resume.text = "PAUSE_RESUME"
	resume.custom_minimum_size = Vector2(0, 56)
	resume.pressed.connect(_set_paused.bind(false))
	box.add_child(resume)
	var leave := Button.new()
	leave.text = "PAUSE_LEAVE"
	leave.custom_minimum_size = Vector2(0, 56)
	leave.pressed.connect(_leave)
	box.add_child(leave)
	var hint := Label.new()
	hint.text = "PAUSE_CONTROLS_HINT"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	hint.visible = not DisplayServer.is_touchscreen_available()
	box.add_child(hint)
	return root


## Offline, pausing stops the simulation. Online matches can't pause: the
## panel only stops local input (PLAN §3.5.1).
func _set_paused(paused: bool) -> void:
	_paused = paused
	_pause_panel.visible = paused
	input.enabled = not paused
	input.reset_held()
	touch.release_all()
	if server != null and config.mode == MatchConfig.Mode.OFFLINE:
		server.process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not Platform.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	if client != null:
		client.leave()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file.call_deferred(MAIN_MENU)


## Back to the menu, which shows `reason` (a translation key or text).
func _fail(reason: String) -> void:
	MatchConfig.last_error = reason
	_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not _paused)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_set_paused(not _paused)
		NOTIFICATION_APPLICATION_PAUSED:
			if _started:
				_set_paused(true)


func _on_focus_lost() -> void:
	if _started and not _paused:
		_set_paused(true)

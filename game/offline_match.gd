extends Node3D
## Offline match (M1a): local player + training dummies in the test arena.
## Runs one simulation tick per physics step and renders between ticks using
## the physics interpolation fraction. In M1b the same pieces get driven by
## the network layer instead.

const MOVEMENT := preload("res://data/movement_config.tres")
const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const ARENA_GAMEPLAY := preload("res://maps/test_arena/gameplay.tscn")
const ARENA_PRESENTATION := preload("res://maps/test_arena/presentation.tscn")
const HUD_SCENE := preload("res://ui/hud/hud.tscn")
const MAIN_MENU := "res://ui/main_menu/main_menu.tscn"
const LOCAL_ID := 1
const DUMMY_COUNT := 3
const DUMMY_COLORS := [Color(0.95, 0.5, 0.2), Color(0.9, 0.35, 0.35), Color(0.85, 0.75, 0.3)]

var world: SimWorld
var input := InputAdapter.new()
var view := FirstPersonView.new()
var effects := Effects.new()
var hud: Hud
var touch := TouchControls.new()

var _drivers: Dictionary = {}  ## net_id -> TargetDummyDriver
var _visuals: Dictionary = {}  ## net_id -> PlayerVisual
var _prev: Dictionary = {}  ## net_id -> PlayerSimState (previous tick)
var _started: bool = false
var _paused: bool = false
var _pause_panel: Control
var _time: float = 0.0


func _ready() -> void:
	var gameplay := ARENA_GAMEPLAY.instantiate()
	add_child(gameplay)
	add_child(ARENA_PRESENTATION.instantiate())
	world = SimWorld.new()
	world.name = "SimWorld"
	world.configure(randi(), MOVEMENT, gameplay.spawn_points())
	add_child(world)
	add_child(input)
	add_child(view)
	add_child(effects)
	_build_ui()
	get_tree().root.get_window().focus_exited.connect(_on_focus_lost)
	# Static world bodies become queryable after the first physics step.
	await get_tree().physics_frame
	var loadout: Array[WeaponData] = [PULSE, ARC]
	var me := world.add_player(LOCAL_ID, loadout, "You", false)
	input.look_yaw = me.state.yaw
	for i in DUMMY_COUNT:
		var id := 2 + i
		var p := world.add_player(id, loadout, "Dummy %d" % (i + 1), true)
		_drivers[id] = TargetDummyDriver.new(i * 50)
		var v := PlayerVisual.new()
		add_child(v)
		v.setup(p.display_name, true, DUMMY_COLORS[i % DUMMY_COLORS.size()])
		_visuals[id] = v
	for e in world.drain_events():
		_handle_event(e)
	_snapshot_prev()
	if not Platform.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_started = true


func _physics_process(_delta: float) -> void:
	if not _started or _paused:
		return
	_snapshot_prev()
	var commands := {LOCAL_ID: input.build_command(world.tick)}
	for id in _drivers:
		commands[id] = _drivers[id].command_for(world.tick, world.get_player(id))
	world.step(commands)
	for e in world.drain_events():
		_handle_event(e)


func _process(delta: float) -> void:
	if not _started:
		return
	_time += delta
	var alpha := Engine.get_physics_interpolation_fraction()
	var me := world.get_player(LOCAL_ID)
	var s := me.state
	var prev: PlayerSimState = _prev.get(LOCAL_ID)
	var from := prev if prev != null and prev.discontinuity_gen == s.discontinuity_gen else s
	var feet := from.position.lerp(s.position, alpha)
	view.update_view(feet, me.config.eye_for(s.stance), input.look_yaw, input.look_pitch, s, me.current_weapon(), delta)
	for id in _visuals:
		_visuals[id].update_from(_prev.get(id), world.get_player(id).state, alpha, _time)
	effects.sync_projectiles(world.projectiles, alpha)
	hud.update_state(s, me.current_weapon(), world.scores[LOCAL_ID], s.respawn_tick - world.tick)


func _snapshot_prev() -> void:
	for id in world.players:
		_prev[id] = world.get_player(id).state.copy()


func _handle_event(e: Dictionary) -> void:
	if not effects.first_time(e):
		return
	match e.type:
		"fire":
			var local: bool = e.shooter == LOCAL_ID
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
			if e.attacker == LOCAL_ID and e.target != LOCAL_ID:
				hud.on_hit_confirmed(e.killed)
			if e.target == LOCAL_ID:
				hud.on_damaged()
		"spawn":
			if e.player == LOCAL_ID:
				input.look_yaw = e.yaw
				input.look_pitch = 0.0


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = HUD_SCENE.instantiate()
	layer.add_child(hud)
	hud.pause_requested.connect(_set_paused.bind(true))
	touch.input = input
	layer.add_child(touch)
	_pause_panel = _make_pause_panel()
	layer.add_child(_pause_panel)


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


## Offline, pausing really stops the simulation. Online matches can't pause;
## there the panel will only stop local input (PLAN §3.5.1).
func _set_paused(paused: bool) -> void:
	_paused = paused
	_pause_panel.visible = paused
	input.enabled = not paused
	input.reset_held()
	touch.release_all()
	if paused:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif not Platform.is_mobile():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _leave() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MAIN_MENU)


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

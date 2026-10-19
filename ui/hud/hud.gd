class_name Hud
extends Control
## In-match HUD (greybox): crosshair, hit markers (optimistic, then confirmed
## by the server, PLAN §2.6), damage direction indicator (PLAN §3.16),
## shield/health with a shield-break flash, ammo, weapon slots, score, match
## timer, respawn countdown and damage vignette. Text uses translation keys.

signal pause_requested

const CYAN := Color(0.35, 0.9, 1.0)

var _shield: float = 100.0
var _health: float = 100.0
var _alive: bool = true
var _hit_marker: float = 0.0
var _hit_kill: bool = false
var _hit_confirmed: bool = true
var _damage_flash: float = 0.0
var _shield_flash: float = 0.0
var _protected: bool = false
## [source position, seconds left] for the damage direction indicator.
var _damage_sources: Array = []
var _view_pos := Vector3.ZERO
var _view_yaw: float = 0.0
var _slots: PackedStringArray = []
var _slot: int = 0
var _timer: Label
var _slots_label: Label

@onready var _ammo: Label = %Ammo
@onready var _weapon: Label = %Weapon
@onready var _score: Label = %Score
@onready var _center: Label = %CenterMessage
@onready var _pause_button: Button = %PauseButton


func _ready() -> void:
	_pause_button.pressed.connect(pause_requested.emit)
	_pause_button.visible = DisplayServer.is_touchscreen_available()
	if DisplayServer.is_touchscreen_available():
		# Touch buttons occupy the bottom right; show weapon and ammo top right.
		for label in [_weapon, _ammo]:
			label.anchor_top = 0.0
			label.anchor_bottom = 0.0
		_weapon.offset_top = 16.0
		_weapon.offset_bottom = 46.0
		_ammo.offset_top = 44.0
		_ammo.offset_bottom = 92.0


func _enter_tree() -> void:
	_timer = Label.new()
	_timer.add_theme_font_size_override("font_size", 22)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_timer.offset_top = 46.0
	_timer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_timer)
	_slots_label = Label.new()
	_slots_label.add_theme_font_size_override("font_size", 16)
	_slots_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
	add_child(_slots_label)


## Optimistic markers (our own prediction) are drawn thinner and grey; the
## server's confirmation turns them white, or red for a kill.
func on_hit_marker(confirmed: bool, killed: bool) -> void:
	if not confirmed and _hit_marker > 0.0 and _hit_confirmed:
		return  # a confirmation is already showing
	_hit_marker = 0.25
	_hit_kill = killed
	_hit_confirmed = confirmed


func on_hit_confirmed(killed: bool) -> void:
	on_hit_marker(true, killed)


func on_damaged_from(source: Vector3) -> void:
	on_damaged()
	_damage_sources.append([source, 1.2])
	while _damage_sources.size() > 6:
		_damage_sources.pop_front()


func on_shield_broken() -> void:
	_shield_flash = 1.0


## Camera position and yaw, for the damage direction indicator.
func set_view(pos: Vector3, yaw: float) -> void:
	_view_pos = pos
	_view_yaw = yaw


func set_timer(seconds_left: int, show: bool) -> void:
	_timer.visible = show
	_timer.text = "%d:%02d" % [floori(seconds_left / 60.0), seconds_left % 60]


func set_slots(names: PackedStringArray, current: int) -> void:
	if names == _slots and current == _slot:
		return
	_slots = names
	_slot = current
	var parts := PackedStringArray()
	for i in names.size():
		parts.append(("[%d %s]" if i == current else " %d %s ") % [i + 1, names[i]])
	_slots_label.text = "  ".join(parts)
	_slots_label.position = Vector2(_weapon.position.x - 260.0, _ammo.position.y + _ammo.size.y)


func on_damaged() -> void:
	_damage_flash = 1.0


func update_state(s: PlayerSimState, weapon: WeaponData, score: int, ticks_to_respawn: int) -> void:
	_shield = s.shield
	_health = s.health
	_alive = s.alive
	_protected = s.spawn_protection_ticks > 0
	var w := s.weapon_slot
	_weapon.text = weapon.display_name
	if s.reload[w] > 0:
		_ammo.text = tr("HUD_RELOADING")
	else:
		_ammo.text = "%d / %d" % [s.mag[w], s.reserve[w]]
	_score.text = tr("HUD_SCORE") % score
	if not s.alive:
		_center.text = tr("HUD_RESPAWN_IN") % ceili(ticks_to_respawn / float(Sim.TICK_RATE))
	elif _protected:
		_center.text = tr("HUD_SPAWN_PROTECTED")
	else:
		_center.text = ""
	queue_redraw()


func _process(delta: float) -> void:
	_hit_marker = maxf(0.0, _hit_marker - delta)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.5)
	_shield_flash = maxf(0.0, _shield_flash - delta * 3.0)
	for d in _damage_sources:
		d[1] -= delta
	_damage_sources = _damage_sources.filter(func(d: Array) -> bool: return d[1] > 0.0)
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var scale: float = Settings.get_value("accessibility", "hud_scale")
	# Damage vignette: edges flash red when hit, stay tinted at low health.
	var low := clampf(1.0 - _health / 40.0, 0.0, 1.0) * 0.35 if _alive else 0.0
	var alpha := maxf(_damage_flash * 0.45, low)
	if alpha > 0.0:
		var edge := size.y * 0.12
		var col := Color(0.9, 0.1, 0.1, alpha)
		draw_rect(Rect2(0, 0, size.x, edge), col)
		draw_rect(Rect2(0, size.y - edge, size.x, edge), col)
		draw_rect(Rect2(0, 0, edge, size.y), col)
		draw_rect(Rect2(size.x - edge, 0, edge, size.y), col)
	if not _alive:
		return
	# Damage direction: an arc around the crosshair pointing at each source.
	var reduce: bool = Settings.get_value("accessibility", "reduce_screen_shake")
	for d in _damage_sources:
		var to: Vector3 = d[0] - _view_pos
		var world_angle := atan2(-to.x, -to.z)
		var rel := wrapf(world_angle - _view_yaw, -PI, PI)
		# Screen angle: 0 = up (ahead), clockwise to the right.
		var screen := -rel - PI * 0.5
		var r := 90.0 * scale
		draw_arc(c, r, screen - 0.35, screen + 0.35, 12, Color(1.0, 0.3, 0.25, clampf(d[1], 0.0, 1.0) * 0.9),
				6.0 * scale if not reduce else 4.0 * scale)
	if _shield_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.9, 1.0, _shield_flash * 0.18))
	# Crosshair
	var g := 6.0 * scale
	var l := 10.0 * scale
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * g, c + d * (g + l), Color(1, 1, 1, 0.9), 2.0)
	if _hit_marker > 0.0:
		var hc := Color(1.0, 0.25, 0.25) if _hit_kill else (Color.WHITE if _hit_confirmed else Color(0.7, 0.7, 0.7, 0.8))
		var width := 2.5 if _hit_confirmed else 1.5
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 8.0 * scale, c + d * 16.0 * scale, hc, width)
	# Shield and health bars (bottom left)
	var w := 260.0 * scale
	var h := 14.0 * scale
	var origin := Vector2(32.0, size.y - 64.0 * scale)
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(origin, Vector2(w * _shield / Health.MAX_SHIELD, h)), CYAN)
	var origin2 := origin + Vector2(0, h + 6.0)
	draw_rect(Rect2(origin2, Vector2(w, h * 0.7)), Color(0, 0, 0, 0.45))
	draw_rect(Rect2(origin2, Vector2(w * _health / Health.MAX_HEALTH, h * 0.7)),
			Color(1.0, 0.35, 0.3) if _health < 40.0 else Color(0.95, 0.95, 0.95))

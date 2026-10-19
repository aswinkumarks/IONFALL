class_name Hud
extends Control
## In-match HUD (greybox): crosshair, hit markers, shield/health, ammo,
## score, respawn countdown and damage vignette. All text uses translation keys.

signal pause_requested

const CYAN := Color(0.35, 0.9, 1.0)

var _shield: float = 100.0
var _health: float = 100.0
var _alive: bool = true
var _hit_marker: float = 0.0
var _hit_kill: bool = false
var _damage_flash: float = 0.0
var _protected: bool = false

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


func on_hit_confirmed(killed: bool) -> void:
	_hit_marker = 0.25
	_hit_kill = killed


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
	# Crosshair
	var g := 6.0 * scale
	var l := 10.0 * scale
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * g, c + d * (g + l), Color(1, 1, 1, 0.9), 2.0)
	if _hit_marker > 0.0:
		var hc := Color(1.0, 0.25, 0.25) if _hit_kill else Color.WHITE
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d * 8.0 * scale, c + d * 16.0 * scale, hc, 2.5)
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

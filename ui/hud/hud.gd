class_name Hud
extends Control
## In-match HUD: crosshair with fire bloom and reload ring, hit markers
## (optimistic, then confirmed by the server, PLAN §2.6), damage direction
## and nearby-gunfire indicators (PLAN §3.16), segmented shield/health bars
## with a shield-break flash, weapon card (ammo, magazine pips, slots),
## timer and score, respawn countdown, damage vignette and captions.
## Drawn in `_draw` with the UiStyle fonts; sizes follow the HUD scale
## setting. Text uses translation keys.

signal pause_requested

const BAR_SEGMENTS := 10

var _shield: float = 100.0
var _health: float = 100.0
var _shield_shown: float = 100.0  ## eased value; the gap shows recent loss
var _health_shown: float = 100.0
var _shield_rising: bool = false
var _alive: bool = true
var _hit_marker: float = 0.0
var _hit_kill: bool = false
var _hit_confirmed: bool = true
var _damage_flash: float = 0.0
var _shield_flash: float = 0.0
var _bloom: float = 0.0
var _protected: bool = false
## [source position, seconds left] for the damage direction indicator.
var _damage_sources: Array = []
## [source position, seconds left]: unseen gunfire nearby (visual audio cue).
var _gunfire_sources: Array = []
var _view_pos := Vector3.ZERO
var _view_yaw: float = 0.0
var _slots: PackedStringArray = []
var _slot: int = 0
var _weapon_name: String = ""
var _mag: int = 0
var _mag_size: int = 1
var _reserve: int = 0
var _grenades: int = 0
var _prompt: String = ""
var _pickup_timers: String = ""
var _reload: float = 0.0  ## 0 = not reloading, else progress 0..1
var _score: int = 0
var _respawn_ticks: int = 0
var _timer_seconds: int = 0
var _timer_shown: bool = false
var _caption_text: String = ""
var _caption_time: float = 0.0
var _time: float = 0.0
var _scale: float = 1.0
var _touch: bool = false
var _vignette: TextureRect

@onready var _pause_button: Button = %PauseButton


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()
	apply_text_scale()
	Events.settings_changed.connect(func(section: String, key: String, _value: Variant) -> void:
		if section == "accessibility" and key == "hud_scale":
			apply_text_scale())
	_pause_button.pressed.connect(pause_requested.emit)
	_pause_button.visible = _touch
	_vignette = TextureRect.new()
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	g.colors = PackedColorArray([Color(0.9, 0.08, 0.12, 0.0), Color(0.9, 0.08, 0.12, 0.0), Color(0.9, 0.08, 0.12, 1.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 1.0)
	tex.width = 128
	tex.height = 128
	_vignette.texture = tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	move_child(_vignette, 0)


## HUD and text scale 80–150% (PLAN §3.16).
func apply_text_scale() -> void:
	_scale = Settings.get_value("accessibility", "hud_scale")
	queue_redraw()


## Optimistic markers (our own prediction) are drawn thinner and grey; the
## server's confirmation turns them white, or red for a kill.
func on_hit_marker(confirmed: bool, killed: bool) -> void:
	if not confirmed and _hit_marker > 0.0 and _hit_confirmed:
		return  # a confirmation is already showing
	_hit_marker = 0.3 if killed else 0.22
	_hit_kill = killed
	_hit_confirmed = confirmed


func on_hit_confirmed(killed: bool) -> void:
	on_hit_marker(true, killed)


## The local weapon fired: the crosshair blooms.
func on_fired(strength: float = 1.0) -> void:
	_bloom = minf(_bloom + 0.45 * strength, 1.0)


func on_damaged_from(source: Vector3) -> void:
	on_damaged()
	_damage_sources.append([source, 1.2])
	while _damage_sources.size() > 6:
		_damage_sources.pop_front()


## Captions for important sounds (PLAN §3.16).
func show_caption(text: String) -> void:
	_caption_text = text
	_caption_time = 2.5


## Visual equivalent of nearby gunfire you may not hear or see.
func on_gunfire_from(source: Vector3) -> void:
	for g in _gunfire_sources:
		if (g[0] as Vector3).distance_to(source) < 2.0:
			g[1] = 0.8
			return
	_gunfire_sources.append([source, 0.8])
	while _gunfire_sources.size() > 6:
		_gunfire_sources.pop_front()


func on_shield_broken() -> void:
	_shield_flash = 1.0


func on_damaged() -> void:
	_damage_flash = 1.0


## Camera position and yaw, for the damage direction indicator.
func set_view(pos: Vector3, yaw: float) -> void:
	_view_pos = pos
	_view_yaw = yaw


func set_timer(seconds_left: int, show: bool) -> void:
	_timer_seconds = seconds_left
	_timer_shown = show


## "Press E: swap for RAIL SNIPER", or "" for none.
func set_prompt(text: String) -> void:
	_prompt = text


## Power weapon spawn timers, one line.
func set_pickup_timers(text: String) -> void:
	_pickup_timers = text


func set_slots(names: PackedStringArray, current: int) -> void:
	_slots = names
	_slot = current


func update_state(s: PlayerSimState, weapon: WeaponData, score: int, ticks_to_respawn: int) -> void:
	_shield_rising = s.shield > _shield + 0.01
	_shield = s.shield
	_health = s.health
	if not _alive and s.alive:
		_shield_shown = _shield
		_health_shown = _health
	_alive = s.alive
	_protected = s.spawn_protection_ticks > 0
	var w := s.weapon_slot
	_weapon_name = tr(weapon.display_name).to_upper()
	_mag = s.mag[w]
	_mag_size = maxi(weapon.mag_size, 1)
	_reserve = s.reserve[w]
	_grenades = s.grenades
	_reload = 1.0 - float(s.reload[w]) / weapon.reload_ticks if s.reload[w] > 0 else 0.0
	_score = score
	_respawn_ticks = ticks_to_respawn


func _process(delta: float) -> void:
	_time += delta
	_hit_marker = maxf(0.0, _hit_marker - delta)
	_damage_flash = maxf(0.0, _damage_flash - delta * 2.5)
	_shield_flash = maxf(0.0, _shield_flash - delta * 3.0)
	_bloom = maxf(0.0, _bloom - delta * 3.5)
	# Bars: drop quickly to the real value after a short hold (the "lost" chunk).
	_shield_shown = _shield if _shield >= _shield_shown else move_toward(_shield_shown, _shield, delta * 160.0)
	_health_shown = _health if _health >= _health_shown else move_toward(_health_shown, _health, delta * 120.0)
	for d in _damage_sources:
		d[1] -= delta
	_damage_sources = _damage_sources.filter(func(d: Array) -> bool: return d[1] > 0.0)
	for g in _gunfire_sources:
		g[1] -= delta
	_gunfire_sources = _gunfire_sources.filter(func(g: Array) -> bool: return g[1] > 0.0)
	_caption_time = maxf(0.0, _caption_time - delta)
	var intensity: float = Settings.get_value("accessibility", "vignette")
	var low := clampf(1.0 - _health / 45.0, 0.0, 1.0) * (0.55 + 0.15 * sin(_time * 5.0)) if _alive else 0.0
	_vignette.modulate.a = maxf(_damage_flash * 0.45, low * 0.8) * intensity
	queue_redraw()


# --- Drawing ---

func _text(pos: Vector2, text: String, size: float, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
		font: Font = null, width: float = -1.0) -> void:
	var f := font if font != null else UiStyle.font_display
	var px := roundi(size * _scale)
	if align != HORIZONTAL_ALIGNMENT_LEFT and width < 0.0:
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		pos.x -= tw if align == HORIZONTAL_ALIGNMENT_RIGHT else tw * 0.5
	draw_string(f, pos + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, width, px, Color(0, 0, 0, color.a * 0.55))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, px, color)


## Parallelogram slanted like the UI's buttons.
func _skew_rect(r: Rect2, color: Color) -> void:
	if r.size.x < 0.5 or r.size.y < 0.5:
		return
	var k := r.size.y * UiStyle.SKEW
	draw_colored_polygon(PackedVector2Array([
		r.position + Vector2(k, 0), r.position + Vector2(r.size.x + k, 0),
		r.position + Vector2(r.size.x, r.size.y), r.position + Vector2(0, r.size.y)]), color)


func _segmented_bar(origin: Vector2, w: float, h: float, value: float, shown: float, color: Color, lost: Color) -> void:
	var gap := 3.0 * _scale
	var seg := (w - gap * (BAR_SEGMENTS - 1)) / BAR_SEGMENTS
	for i in BAR_SEGMENTS:
		var x := origin.x + i * (seg + gap)
		var r := Rect2(Vector2(x, origin.y), Vector2(seg, h))
		_skew_rect(r, Color(0.02, 0.04, 0.07, 0.55))
		var lo := float(i) / BAR_SEGMENTS
		var lost_f := clampf((shown - lo) * BAR_SEGMENTS, 0.0, 1.0)
		var fill_f := clampf((value - lo) * BAR_SEGMENTS, 0.0, 1.0)
		if lost_f > 0.0:
			_skew_rect(Rect2(r.position, Vector2(seg * lost_f, h)), lost)
		if fill_f > 0.0:
			_skew_rect(Rect2(r.position, Vector2(seg * fill_f, h)), color)


func _draw() -> void:
	var c := size * 0.5
	var s := _scale
	if _shield_flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiStyle.SHIELD, _shield_flash * 0.16))
	_draw_top()
	if not _alive:
		_draw_respawn(c)
		_draw_caption()
		return
	_draw_indicators(c)
	_draw_crosshair(c)
	_draw_vitals()
	_draw_weapon()
	if _protected:
		_text(c + Vector2(0, 70 * s), tr("HUD_SPAWN_PROTECTED").to_upper(), 18, Color(UiStyle.ACCENT, 0.9), HORIZONTAL_ALIGNMENT_CENTER)
	if not _prompt.is_empty():
		_text(c + Vector2(0, 110 * s), _prompt, 22, UiStyle.WARN, HORIZONTAL_ALIGNMENT_CENTER)
	_draw_caption()


func _draw_top() -> void:
	var s := _scale
	var x := size.x * 0.5
	var y := 14.0 * s
	var w := 150.0 * s
	if _timer_shown:
		_skew_rect(Rect2(Vector2(x - w * 0.5, y), Vector2(w, 40 * s)), Color(0.02, 0.04, 0.07, 0.6))
		draw_rect(Rect2(Vector2(x - w * 0.5 + 6 * s, y + 40 * s), Vector2(w - 6 * s, 2 * s)), Color(UiStyle.ACCENT, 0.7))
		var urgent := _timer_seconds <= 30
		_text(Vector2(x, y + 31 * s), "%d:%02d" % [floori(_timer_seconds / 60.0), _timer_seconds % 60], 32,
				UiStyle.WARN if urgent else UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, UiStyle.font_display_bold)
		y += 48 * s
	_text(Vector2(x, y + 20 * s), tr("HUD_SCORE") % _score, 20, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	if not _pickup_timers.is_empty():
		_text(Vector2(x, y + 44 * s), _pickup_timers, 15, Color(1.0, 0.65, 0.3, 0.9), HORIZONTAL_ALIGNMENT_CENTER)


func _draw_crosshair(c: Vector2) -> void:
	var s := _scale
	var gap := (7.0 + 12.0 * _bloom) * s
	var l := 9.0 * s
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + d * gap, c + d * (gap + l), Color(0, 0, 0, 0.45), 4.0 * s)
		draw_line(c + d * gap, c + d * (gap + l), Color(1, 1, 1, 0.92), 2.0 * s)
	draw_circle(c, 1.6 * s, Color(1, 1, 1, 0.9))
	if _reload > 0.0:
		draw_arc(c, 26 * s, -PI * 0.5, -PI * 0.5 + TAU, 40, Color(1, 1, 1, 0.15), 3.0 * s)
		draw_arc(c, 26 * s, -PI * 0.5, -PI * 0.5 + TAU * _reload, 40, UiStyle.ACCENT, 3.0 * s)
	if _hit_marker > 0.0:
		var t := _hit_marker / (0.3 if _hit_kill else 0.22)
		var hc := UiStyle.DANGER if _hit_kill else (Color.WHITE if _hit_confirmed else Color(0.7, 0.7, 0.7, 0.8))
		hc.a *= clampf(t * 2.0, 0.0, 1.0)
		var width := (3.0 if _hit_kill else 2.5 if _hit_confirmed else 1.5) * s
		var r0 := (9.0 + (1.0 - t) * 4.0) * s
		var r1 := r0 + (12.0 if _hit_kill else 8.0) * s
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			draw_line(c + d.normalized() * r0, c + d.normalized() * r1, hc, width)


func _draw_indicators(c: Vector2) -> void:
	var s := _scale
	var reduce: bool = Settings.get_value("accessibility", "reduce_screen_shake")
	for d in _damage_sources:
		var to: Vector3 = d[0] - _view_pos
		var rel := wrapf(atan2(-to.x, -to.z) - _view_yaw, -PI, PI)
		var screen := -rel - PI * 0.5  # 0 = up (ahead), clockwise to the right
		draw_arc(c, 95.0 * s, screen - 0.38, screen + 0.38, 16, Color(UiStyle.DANGER, clampf(d[1], 0.0, 1.0) * 0.9),
				(4.0 if reduce else 7.0) * s)
	for g in _gunfire_sources:
		var to: Vector3 = g[0] - _view_pos
		var rel := wrapf(atan2(-to.x, -to.z) - _view_yaw, -PI, PI)
		var screen := -rel - PI * 0.5
		draw_arc(c, 118.0 * s, screen - 0.12, screen + 0.12, 6, Color(UiStyle.WARN, clampf(g[1], 0.0, 1.0) * 0.8), 4.0 * s)


func _draw_vitals() -> void:
	var s := _scale
	var w := 300.0 * s
	var origin := Vector2(40.0 * s, size.y - 74.0 * s) if not _touch else Vector2(40.0 * s, 96.0 * s)
	var pulse := 0.75 + 0.25 * sin(_time * 8.0)
	var shield_col := UiStyle.SHIELD if not _shield_rising else Color(UiStyle.SHIELD, pulse)
	if _shield_flash > 0.0:
		shield_col = shield_col.lerp(Color.WHITE, _shield_flash)
	_text(origin + Vector2(0, -8 * s), "SHIELD", 15, UiStyle.TEXT_DIM)
	_text(origin + Vector2(w, -8 * s), str(ceili(_shield)), 22, UiStyle.SHIELD, HORIZONTAL_ALIGNMENT_RIGHT, UiStyle.font_display_bold)
	_segmented_bar(origin, w, 16 * s, _shield / Health.MAX_SHIELD, _shield_shown / Health.MAX_SHIELD, shield_col,
			Color(1, 1, 1, 0.55))
	var o2 := origin + Vector2(0, 26 * s)
	var low := _health < 40.0
	var health_col := Color(UiStyle.DANGER, pulse) if low else UiStyle.HEALTH
	_segmented_bar(o2, w, 10 * s, _health / Health.MAX_HEALTH, _health_shown / Health.MAX_HEALTH, health_col,
			Color(UiStyle.DANGER, 0.7))
	_text(o2 + Vector2(0, 32 * s), "HEALTH", 15, UiStyle.TEXT_DIM)
	_text(o2 + Vector2(w, 32 * s), str(ceili(_health)), 22, UiStyle.DANGER if low else UiStyle.TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT, UiStyle.font_display_bold)


func _draw_weapon() -> void:
	var s := _scale
	var right := size.x - 40.0 * s
	var base := size.y - 40.0 * s if not _touch else 150.0 * s
	# Slots row
	var chip_w := 84.0 * s
	var chip_h := 24.0 * s
	var x := right - _slots.size() * (chip_w + 6 * s) + 6 * s
	var top := base - 132.0 * s
	for i in _slots.size():
		var r := Rect2(Vector2(x, top), Vector2(chip_w, chip_h))
		var active := i == _slot
		_skew_rect(r, Color(UiStyle.ACCENT, 0.85) if active else Color(0.02, 0.04, 0.07, 0.55))
		_text(r.position + Vector2(10 * s, 18 * s), "%d  %s" % [i + 1, _slots[i]], 15,
				UiStyle.BG if active else UiStyle.TEXT_DIM)
		x += chip_w + 6 * s
	_text(Vector2(right, base - 88 * s), _weapon_name, 20, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_text(Vector2(right - 230 * s, base - 88 * s), tr("HUD_GRENADES") % _grenades, 18,
			UiStyle.TEXT if _grenades > 0 else Color(UiStyle.TEXT_DIM, 0.5))
	if _reload > 0.0:
		_text(Vector2(right, base - 30 * s), tr("HUD_RELOADING").to_upper(), 34, UiStyle.ACCENT,
				HORIZONTAL_ALIGNMENT_RIGHT, UiStyle.font_display_bold)
	else:
		var reserve := " / %d" % _reserve
		var rf := UiStyle.font_display
		var rw := rf.get_string_size(reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(26 * s)).x
		_text(Vector2(right, base - 24 * s), reserve, 26, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
		var low := _mag <= ceili(_mag_size * 0.25)
		_text(Vector2(right - rw - 4 * s, base - 22 * s), str(_mag), 60,
				UiStyle.DANGER if _mag == 0 else (UiStyle.WARN if low else UiStyle.TEXT), HORIZONTAL_ALIGNMENT_RIGHT,
				UiStyle.font_display_bold)
	# Magazine pips
	var pip_w := 220.0 * s
	var n := mini(_mag_size, 40)
	var gap := 2.0 * s if n > 12 else 4.0 * s
	var pw := (pip_w - gap * (n - 1)) / n
	var shown := roundi(float(_mag) / _mag_size * n)
	for i in n:
		var px := right - pip_w + i * (pw + gap)
		draw_rect(Rect2(Vector2(px, base - 8 * s), Vector2(pw, 5 * s)),
				Color(UiStyle.TEXT, 0.85) if i < shown else Color(1, 1, 1, 0.12))


func _draw_respawn(c: Vector2) -> void:
	var s := _scale
	var secs := ceili(_respawn_ticks / float(Sim.TICK_RATE))
	_text(c + Vector2(0, 90 * s), tr("HUD_RESPAWN_LABEL").to_upper(), 20, UiStyle.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_text(c + Vector2(0, 150 * s), str(maxi(secs, 0)), 64, UiStyle.TEXT, HORIZONTAL_ALIGNMENT_CENTER, UiStyle.font_display_bold)


func _draw_caption() -> void:
	if _caption_time <= 0.0:
		return
	var s := _scale
	var a := clampf(_caption_time / 0.4, 0.0, 1.0)
	var text := "[%s]" % _caption_text
	var f := UiStyle.font_body_bold
	var px := roundi(19 * s)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var pos := Vector2(size.x * 0.5, size.y - 150 * s)
	draw_rect(Rect2(pos - Vector2(tw * 0.5 + 12 * s, 24 * s), Vector2(tw + 24 * s, 34 * s)), Color(0, 0, 0, 0.6 * a))
	draw_string(f, pos - Vector2(tw * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(1.0, 0.95, 0.75, a))

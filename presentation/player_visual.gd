class_name PlayerVisual
extends Node3D
## Third-person view of another player: a CharacterRig body and a nameplate,
## interpolated between the previous and current simulation ticks.

## Body style for visuals set up without one (CharacterRig.STYLES); the
## character comparison bench sets it.
static var style: String = "sentinel"
## Colours a player can pick (profile "color"); index 0 is "auto", one of
## AUTO_COLORS by player id. Sent as an index in the handshake and roster.
const PALETTE := [Color(0, 0, 0, 0), Color(0.31, 0.89, 1.0), Color(1.0, 0.55, 0.2), Color(0.36, 0.95, 0.5),
		Color(0.62, 0.45, 1.0), Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.25), Color(1.0, 0.45, 0.8),
		Color(0.92, 0.95, 1.0)]
const AUTO_COLORS := [Color(0.55, 0.45, 1.0), Color(0.3, 0.85, 0.5), Color(0.95, 0.4, 0.6), Color(0.9, 0.85, 0.3)]
const BOT_COLOR := Color(0.95, 0.5, 0.2)


## The colour of player `id` with palette pick `pick` (0 = auto).
static func color_for(id: int, pick: int, is_bot: bool = false) -> Color:
	if is_bot:
		return BOT_COLOR
	if pick > 0 and pick < PALETTE.size():
		return PALETTE[pick]
	return AUTO_COLORS[posmod(id, AUTO_COLORS.size())]

var rig: CharacterRig
var rig_style: String = ""
var color := Color.WHITE
var _label: Label3D
var _height: float = 1.8
var _last_time: float = -1.0


## `variant` picks the character model (e.g. one astronaut per player);
## `p_style` the body (CharacterRig.STYLES), else `style`.
func setup(display_name: String, is_bot: bool, p_color: Color, variant: int = 0, p_style: String = "") -> void:
	color = p_color
	rig_style = p_style if not p_style.is_empty() else style
	rig = CharacterRig.create(rig_style, variant)
	add_child(rig)
	rig.setup(p_color)
	_label = Label3D.new()
	_label.text = ("[BOT] " if is_bot else "") + display_name
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.outline_size = 8
	_label.no_depth_test = false
	add_child(_label)


## `prev`/`cur` are the states at the last two ticks; `alpha` is the fraction
## between them (render frames run faster than the 60 Hz simulation).
func update_from(prev: PlayerSimState, cur: PlayerSimState, alpha: float, time: float) -> void:
	var delta := clampf(time - _last_time, 0.0, 0.1) if _last_time >= 0.0 else 0.0
	_last_time = time
	visible = cur.alive
	if not cur.alive:
		return
	# Never interpolate across a respawn or teleport (PLAN §3.3.4).
	var from := prev if prev != null and prev.discontinuity_gen == cur.discontinuity_gen else cur
	position = from.position.lerp(cur.position, alpha)
	rotation.y = lerp_angle(from.yaw, cur.yaw, alpha)
	var target_h := 1.8 if cur.stance == PlayerSimState.Stance.STAND else 1.2
	_height = lerpf(_height, target_h, 0.3)
	var held := cur.weapon()
	if held != null:
		rig.set_weapon(held.id)
	rig.animate(cur, delta, _height)
	_label.position.y = _height + 0.45
	var shimmer := 0.0
	if cur.spawn_protection_ticks > 0:
		shimmer = 0.6 + 0.6 * sin(time * 18.0)
	rig.set_glow(shimmer)


## Hit feedback: a white flash on the body (brighter when the shield breaks).
func flash_hit(shield_broken: bool) -> void:
	rig.flash(1.0 if shield_broken else 0.6)


func on_fire() -> void:
	rig.on_fire()

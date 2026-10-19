class_name PlayerVisual
extends Node3D
## Third-person view of another player: a CharacterRig body and a nameplate,
## interpolated between the previous and current simulation ticks.

## Body style for new visuals (CharacterRig.STYLES); set by the character
## comparison bench and the diagnostics overlay.
static var style: String = "sentinel"

var rig: CharacterRig
var color := Color.WHITE
## Weapons by slot, to show the held weapon (FFA loadout until per-player
## loadouts exist).
var loadout: Array[WeaponData] = Loadouts.ffa()
var _label: Label3D
var _height: float = 1.8
var _last_time: float = -1.0


## `variant` picks the character model (e.g. one astronaut per player).
func setup(display_name: String, is_bot: bool, p_color: Color, variant: int = 0) -> void:
	color = p_color
	rig = CharacterRig.create(style, variant)
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
	if cur.weapon_slot >= 0 and cur.weapon_slot < loadout.size():
		rig.set_weapon(loadout[cur.weapon_slot].id)
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

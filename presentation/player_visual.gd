class_name PlayerVisual
extends Node3D
## Third-person view of another player: a CharacterRig body, interpolated
## between the previous and current simulation ticks, and its nameplate's
## contents (drawn in 2D by Nameplates).

## Body style for visuals set up without one (CharacterRig.STYLES); the
## character comparison bench sets it.
static var style: String = "sentinel"
## Colours a player can pick (profile "color"); index 0 is "auto", one of
## AUTO_COLORS by player id. Sent as an index in the handshake and roster.
const PALETTE := [Color(0, 0, 0, 0), Color(0.31, 0.89, 1.0), Color(1.0, 0.55, 0.2), Color(0.36, 0.95, 0.5),
		Color(0.62, 0.45, 1.0), Color(1.0, 0.3, 0.35), Color(1.0, 0.85, 0.25), Color(1.0, 0.45, 0.8),
		Color(0.92, 0.95, 1.0), Color(0.2, 0.95, 0.8), Color(0.55, 0.6, 0.7), Color(1.0, 0.36, 0.1)]
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
## The nameplate (Nameplates draws it): name, its tint, the TDM team shape
## (-1: none) and the bar under it, the shield while it holds, then health.
var nameplate_text := ""
var nameplate_color := Color.WHITE
var nameplate_team := -1
var nameplate_shown := true
var bar_fraction := 1.0
var bar_on_shield := true
var _height: float = 1.8
var _last_time: float = -1.0
var shield: float = 0.0  ## at the latest update
var _shell: MeshInstance3D
var _shell_mat: ShaderMaterial
var _shell_t: float = 0.0
var _near := true
var _detail := Vector2i(1, 1)  ## [ik, anim_every] last sent to the rig
var _phase := 0

const SHIELD_SHADER := preload("res://presentation/shield.gdshader")
## Past this nameplates fade out: unreadable on a phone anyway.
const NAMEPLATE_RANGE := 30.0  ## metres
const SHELL_SECONDS := 0.3
## Animation detail (CharacterRig.set_detail), by distance from the camera:
## the arms hold the weapon by IK within IK_RANGE (a metre either side
## before switching, so it doesn't flicker at the edge); past it the clips
## advance every 2nd frame, past FAR_RANGE every 3rd, and off screen every
## OFFSCREEN_EVERY (shadows can still show them).
const IK_RANGE := 15.0
const FAR_RANGE := 30.0
const OFFSCREEN_EVERY := 6
## Half the body's extent, for the on-screen test (metres).
const BODY_RADIUS := 1.2


## `variant` picks the character model (e.g. one astronaut per player);
## `p_style` the body (CharacterRig.STYLES), else `style`.
func setup(display_name: String, is_bot: bool, p_color: Color, variant: int = 0, p_style: String = "") -> void:
	color = p_color
	rig_style = p_style if not p_style.is_empty() else style
	rig = CharacterRig.create(rig_style, variant)
	add_child(rig)
	rig.setup(p_color)
	_phase = get_instance_id() % 12  # spreads reduced-rate frames; not the shared RNG
	nameplate_text = ("[BOT] " if is_bot else "") + display_name
	set_bar(Balance.PLAYER.max_shield, Balance.PLAYER.max_health)
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.55
	capsule.height = 2.1
	capsule.radial_segments = 16
	capsule.rings = 6
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHIELD_SHADER
	_shell_mat.set_shader_parameter("color", Color(0.45, 0.9, 1.0).lerp(p_color, 0.25))
	_shell = MeshInstance3D.new()
	_shell.mesh = capsule
	_shell.material_override = _shell_mat
	_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shell.position.y = 0.95
	_shell.visible = false
	add_child(_shell)
	RenderLayers.mark_dynamic(self)


## `prev`/`cur` are the states at the last two ticks; `alpha` is the fraction
## between them (render frames run faster than the 60 Hz simulation).
func update_from(prev: PlayerSimState, cur: PlayerSimState, alpha: float, time: float) -> void:
	var delta := clampf(time - _last_time, 0.0, 0.1) if _last_time >= 0.0 else 0.0
	_last_time = time
	visible = cur.alive
	shield = cur.shield
	if _shell_t > 0.0:
		_shell_t = maxf(_shell_t - delta, 0.0)
		_shell_mat.set_shader_parameter("strength", _shell_t / SHELL_SECONDS * 1.4)
		_shell.visible = _shell_t > 0.0
	if not cur.alive:
		_set_detail(false, 0)
		return
	# Never interpolate across a respawn or teleport (PLAN §3.3.4).
	var from := prev if prev != null and prev.discontinuity_gen == cur.discontinuity_gen else cur
	position = from.position.lerp(cur.position, alpha)
	rotation.y = lerp_angle(from.yaw, cur.yaw, alpha)
	_update_detail()
	var target_h := 1.8 if cur.stance == PlayerSimState.Stance.STAND else 1.2
	_height = lerpf(_height, target_h, 0.3)
	var held := cur.weapon()
	if held != null:
		rig.set_weapon(held.id)
	rig.animate(cur, delta, _height)
	set_bar(cur.shield, cur.health)
	var shimmer := 0.0
	if cur.spawn_protection_ticks > 0:
		shimmer = 0.6 + 0.6 * sin(time * 18.0)
	rig.set_glow(shimmer)


## Picks the rig's animation detail from where the camera sees it.
func _update_detail() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		_set_detail(true, 1)
		return
	var centre := global_position + Vector3(0.0, 0.9, 0.0)
	var d := camera.global_position.distance_to(centre)
	_near = d < IK_RANGE + (1.0 if _near else -1.0)
	for plane: Plane in camera.get_frustum():
		if plane.distance_to(centre) > BODY_RADIUS:
			_set_detail(false, OFFSCREEN_EVERY)
			return
	_set_detail(_near, 1 if _near else (2 if d < FAR_RANGE else 3))


func _set_detail(ik: bool, anim_every: int) -> void:
	var detail := Vector2i(1 if ik else 0, anim_every)
	if detail != _detail:
		_detail = detail
		rig.set_detail(ik, anim_every, _phase)


## The bar under the nameplate: the shield in the HUD's shield colour while
## it holds, else health in red.
func set_bar(p_shield: float, health: float) -> void:
	bar_on_shield = p_shield > 0.0
	bar_fraction = clampf((p_shield / Balance.PLAYER.max_shield) if bar_on_shield
			else (health / Balance.PLAYER.max_health), 0.0, 1.0)


## Where the nameplate sits: above the head, lower when crouched.
func nameplate_anchor() -> Vector3:
	return global_position + Vector3(0.0, _height + 0.45, 0.0)


## No name or bar (the menu's runners).
func hide_nameplate() -> void:
	nameplate_shown = false


## Nameplate tint (TDM team colour).
func set_label_color(c: Color) -> void:
	nameplate_color = c


## TDM: the team's shape above the nameplate, in its colour (PLAN §3.16:
## teams are never told apart by colour alone).
func set_team(team: int, c: Color) -> void:
	if team < 0 or team >= GameMode.TEAM_SHAPES.size():
		return
	nameplate_team = team
	nameplate_color = c


## Hit feedback: a white flash on the body (brighter when the shield breaks)
## and, while the shield held, the shield crackle on the side facing `from`.
func flash_hit(shield_broken: bool, from: Vector3 = Vector3.INF) -> void:
	rig.flash(1.0 if shield_broken else 0.6)
	if shield > 0.0 or shield_broken:
		var dir := Vector3.BACK if from == Vector3.INF else global_basis.inverse() * (from - global_position)
		_shell_mat.set_shader_parameter("hit_dir", dir.normalized() if dir.length() > 0.01 else Vector3.BACK)
		_shell_t = SHELL_SECONDS
		_shell_mat.set_shader_parameter("strength", 1.4)
		_shell.scale.y = _height / 1.8
		_shell.visible = true


func muzzle_position() -> Vector3:
	return rig.muzzle_position()


func on_fire() -> void:
	rig.on_fire()

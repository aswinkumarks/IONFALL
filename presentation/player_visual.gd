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
var _label: Label3D
static var _shape_textures: Dictionary = {}  ## team -> ImageTexture
var _height: float = 1.8
var _last_time: float = -1.0
var shield: float = 0.0  ## at the latest update
var _shell: MeshInstance3D
var _shell_mat: ShaderMaterial
var _shell_t: float = 0.0

const SHIELD_SHADER := preload("res://presentation/shield.gdshader")
const NAMEPLATE_RANGE := 30.0  ## metres
const SHELL_SECONDS := 0.3


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
	# Two draw calls each (text and outline): past this range nameplates are
	# unreadable on a phone anyway, and 16 of them broke the draw budget (m4.md).
	_label.visibility_range_end = NAMEPLATE_RANGE
	_label.visibility_range_end_margin = 4.0
	_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_label)
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


## Nameplate tint (TDM team colour).
func set_label_color(c: Color) -> void:
	_label.modulate = c


## TDM: the team's shape above the nameplate, in its colour (PLAN §3.16:
## teams are never told apart by colour alone).
func set_team(team: int, c: Color) -> void:
	if team < 0 or team >= GameMode.TEAM_SHAPES.size():
		return
	if not _shape_textures.has(team):
		_shape_textures[team] = UiStyle.team_shape_texture(team)
	var marker := Sprite3D.new()
	marker.texture = _shape_textures[team]
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.pixel_size = 0.0045
	marker.modulate = c
	marker.position = Vector3(0, 0.3, 0)  # above the name; follows it when crouching
	marker.no_depth_test = false
	marker.visibility_range_end = NAMEPLATE_RANGE
	marker.visibility_range_end_margin = 4.0
	marker.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_label.add_child(marker)


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

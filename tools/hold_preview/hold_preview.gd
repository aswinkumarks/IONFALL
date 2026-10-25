@tool
extends Node3D
## Editor preview for how characters hold each weapon (open
## tools/hold_preview/hold_preview.tscn). Pick a character and a weapon in
## the Inspector, then drag the Muzzle, Handle and Support markers on the
## big copy of the weapon (Edit): the character on the left holds the
## weapon with those points as you move them. "Save to weapon_models.gd"
## writes them into WeaponModels.MODELS.
##
## Edit shows the source model as Meshy made it (muzzle at -x, ±0.95 long),
## so a marker's x gives the fraction from the muzzle and its y the height.

const MODELS_FILE := "res://presentation/weapon_models.gd"
const MARKERS := ["Muzzle", "Handle", "Support"]

@export_enum("sentinel", "vanguard", "operative", "spacer") var character := "sentinel":
	set(v):
		character = v
		_rebuild_rig()
@export_enum("pulse_rifle", "burst_rifle", "scatter_gun", "flux_smg", "mag_pistol", "rail_sniper", "arc_launcher")
var weapon := "pulse_rifle":
	set(v):
		weapon = v
		_load_points()
		_rebuild_weapon()
## Look up (+) or down (-), radians.
@export_range(-1.2, 1.2, 0.05) var look_pitch := 0.0
## Running speed, m/s (0 stands).
@export_range(0.0, 7.5, 0.1) var speed := 0.0
@export var crouch := false
@export_tool_button("Save to weapon_models.gd", "Save") var save_button := _save
@export_tool_button("Reset markers", "Reload") var reset_button := _reset

var _rig: ArmoredRig
var _points := {}  ## weapon id -> [muzzle, handle, support] being edited
var _held := []  ## the points the held model was built from
var _state := PlayerSimState.new()


func _ready() -> void:
	_load_points()
	_rebuild_rig()


func _process(delta: float) -> void:
	if _rig == null:
		return
	var p := _read_markers()
	if p != _held:
		_points[weapon] = p
		_rebuild_weapon()
	_state.alive = true
	_state.move_state = PlayerSimState.Move.GROUND
	_state.stance = PlayerSimState.Stance.CROUCH if crouch else PlayerSimState.Stance.STAND
	_state.pitch = look_pitch
	_state.velocity = Vector3(0.0, 0.0, -speed)
	_rig.animate(_state, delta, 1.8)


func _rebuild_rig() -> void:
	if not is_inside_tree():
		return
	if _rig != null:
		_rig.free()
	_rig = CharacterRig.create(character) as ArmoredRig
	_rig.name = "Rig"
	_rig.rotation.y = PI * 0.5  # faces -X, like the source model under Edit
	add_child(_rig)  # no owner: not saved with the scene
	_rig.setup(Color(0.31, 0.89, 1.0))
	_held = []
	_rebuild_weapon()


func _rebuild_weapon() -> void:
	if _rig == null or not is_inside_tree():
		return
	var p: Array = _points.get(weapon, [])
	if p.size() != 3:
		return
	_rig.hold_model(WeaponModels.instantiate_with(StringName(weapon), p[0], p[1], p[2]))
	_held = p.duplicate()
	_show_source()


## The source model under Edit, at its own scale, for the markers.
func _show_source() -> void:
	var edit := get_node_or_null("Edit") as Node3D
	if edit == null:
		return
	var old := edit.get_node_or_null("Model")
	if old != null and old.get_meta("weapon", "") == weapon:
		return
	if old != null:
		old.free()
	var model: Node3D = (load(WeaponModels.DIR + weapon + ".glb") as PackedScene).instantiate()
	model.name = "Model"
	model.set_meta("weapon", weapon)
	edit.add_child(model)


## MODELS' points for the weapon (unless already being edited), onto the markers.
func _load_points() -> void:
	if not _points.has(weapon):
		var def: Array = WeaponModels.MODELS[StringName(weapon)]
		_points[weapon] = [def[2], def[3], def[4]]
	_write_markers(_points[weapon])


func _reset() -> void:
	_points.erase(weapon)
	_load_points()


func _write_markers(p: Array) -> void:
	for i in MARKERS.size():
		var m := get_node_or_null("Edit/" + MARKERS[i]) as Node3D
		if m != null:
			m.position = _to_source(p[i])


func _read_markers() -> Array:
	var out := []
	for name: String in MARKERS:
		var m := get_node_or_null("Edit/" + name) as Node3D
		if m == null:
			return _held
		out.append(_from_source(m.position))
	return out


## (fraction from the muzzle, height) <-> the source model's space.
static func _to_source(p: Vector2) -> Vector3:
	return Vector3(-WeaponModels.SOURCE_HALF + p.x * WeaponModels.SOURCE_HALF * 2.0, p.y, 0.0)


static func _from_source(v: Vector3) -> Vector2:
	var frac := (v.x + WeaponModels.SOURCE_HALF) / (WeaponModels.SOURCE_HALF * 2.0)
	return Vector2(snappedf(frac, 0.005), snappedf(v.y, 0.005))


## Writes every edited weapon's points into MODELS in weapon_models.gd.
func _save() -> void:
	var text := FileAccess.get_file_as_string(MODELS_FILE)
	var changed := PackedStringArray()
	for id: String in _points:
		var p: Array = _points[id]
		var re := RegEx.create_from_string("(\\t&\"%s\": \\[[^,]+, Vector3\\([^)]*\\)), Vector2\\([^)]*\\), Vector2\\([^)]*\\), Vector2\\([^)]*\\)\\]" % id)
		var found := re.search(text)
		if found == null:
			push_error("hold_preview: no MODELS line for %s" % id)
			continue
		var line := "%s, %s, %s, %s]" % [found.get_string(1), _v2(p[0]), _v2(p[1]), _v2(p[2])]
		if line != found.get_string():
			text = text.replace(found.get_string(), line)
			changed.append(id)
	if changed.is_empty():
		print("hold_preview: nothing changed")
		return
	var f := FileAccess.open(MODELS_FILE, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	print("hold_preview: saved %s to %s" % [", ".join(changed), MODELS_FILE])


static func _v2(v: Vector2) -> String:
	return "Vector2(%s, %s)" % [_num(v.x), _num(v.y)]


static func _num(x: float) -> String:
	var s := "%.3f" % x
	while s.ends_with("0"):
		s = s.left(-1)
	if s.ends_with("."):
		s += "0"
	return "0.0" if s == "-0.0" else s

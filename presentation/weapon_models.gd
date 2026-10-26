@tool
class_name WeaponModels
extends RefCounted
## Weapon meshes (generated for IONFALL with Meshy, packed by
## tools/pack_meshy_glb.py) and how each sits in the first-person view.
## Presentation only.
##
## Meshy models come normalised to ±0.95 along their length (x), muzzle at
## -x, top +y. instantiate() turns them to point down -Z, scales them to
## LENGTH and moves them so every handle sits at REFERENCE_GRIP: the rigs and
## the first-person view hold all weapons the same way.

const DIR := "res://art/weapons/ionfall/"
const SOURCE_HALF := 0.95  ## half the source models' length
## Where every model's handle sits, in its root's space (the old Kenney pulse
## rifle's, which the rigs' grips were tuned on).
const REFERENCE_GRIP := Vector3(0.0, -0.048, 0.023)
## id -> [length, hip offset from the camera, muzzle, handle, support];
## muzzle, handle and support (where the other hand's wrist goes: under the
## handguard or pump, on a front grip, or by the gun hand for the pistol) are
## (fraction of the length from the muzzle end, height) in the source
## model's units.
const MODELS := {
	&"pulse_rifle": [0.38, Vector3(0.2, -0.175, -0.495), Vector2(0.0, 0.09), Vector2(0.697, -0.18), Vector2(0.4, -0.11)],
	&"mag_pistol": [0.14, Vector3(0.17, -0.16, -0.36), Vector2(0.0, 0.36), Vector2(0.85, -0.31), Vector2(0.8, -0.68)],
	&"arc_launcher": [0.41, Vector3(0.21, -0.2, -0.46), Vector2(0.0, 0.17), Vector2(0.69, -0.19), Vector2(0.27, -0.22)],
	&"burst_rifle": [0.39, Vector3(0.2, -0.2, -0.46), Vector2(0.0, 0.03), Vector2(0.625, -0.2), Vector2(0.38, -0.08)],
	&"rail_sniper": [0.58, Vector3(0.19, -0.19, -0.48), Vector2(0.0, 0.04), Vector2(0.72, -0.17), Vector2(0.47, -0.13)],
	&"scatter_gun": [0.41, Vector3(0.2, -0.19, -0.44), Vector2(0.0, 0.16), Vector2(0.71, -0.15), Vector2(0.28, -0.07)],
	&"flux_smg": [0.3, Vector3(0.2, -0.2, -0.458), Vector2(0.0, 0.26), Vector2(0.665, -0.15), Vector2(0.3, 0.08)],
}
const GRENADE := "frag_grenade"
## Past this distance (metres) a model shows its stand-in (far_path, built
## by tools/bake_weapon_proxies.gd: ~1k triangles instead of 6-8k), for
## other players' weapons and pickups; a held rifle is ~40 px across there
## on a phone. Only one of the two draws at a time.
const FAR_RANGE := 5.0
const FAR_MARGIN := 0.5


## Every model file, for loading ahead of a match.
static func paths() -> PackedStringArray:
	var out := PackedStringArray()
	for id: StringName in MODELS:
		out.append(DIR + String(id) + ".glb")
	out.append(DIR + GRENADE + ".glb")
	for p in out.duplicate():
		out.append(far_path(p))
	return out


## The low-detail stand-in of the model at `model_path`.
static func far_path(model_path: String) -> String:
	return model_path.get_basename() + "_far.res"


static func has(id: StringName) -> bool:
	return MODELS.has(id)


## A ready-to-add model for `id` (markers as children "Muzzle", "Grip", the
## middle of the handle, and "Support", for the other hand), or null.
static func instantiate(id: StringName) -> Node3D:
	if not MODELS.has(id):
		return null
	var def: Array = MODELS[id]
	return instantiate_with(id, def[2], def[3], def[4])


## instantiate() with the muzzle, handle and support points given (as in
## MODELS) rather than taken from MODELS: tools/hold_preview tries them out.
static func instantiate_with(id: StringName, p_muzzle: Vector2, p_handle: Vector2, p_support: Vector2) -> Node3D:
	var s: float = float(MODELS[id][0]) / (SOURCE_HALF * 2.0)
	var root := Node3D.new()
	var model := _load(String(id))
	model.rotation.y = -PI * 0.5  # source -x (muzzle) to -Z
	model.scale = Vector3.ONE * s
	model.position = REFERENCE_GRIP - model.basis * _source_point(p_handle)
	root.add_child(model)
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = model.transform * _source_point(p_muzzle)
	root.add_child(muzzle)
	var grip := Node3D.new()
	grip.name = "Grip"
	grip.position = REFERENCE_GRIP
	root.add_child(grip)
	var support := Node3D.new()
	support.name = "Support"
	support.position = model.transform * _source_point(p_support)
	root.add_child(support)
	RenderLayers.mark_dynamic(root)
	return root


## The frag grenade, `height` metres tall, standing on its origin.
static func grenade(height: float) -> Node3D:
	var root := Node3D.new()
	var model := _load(GRENADE)
	model.scale = Vector3.ONE * height / (SOURCE_HALF * 2.0)
	model.position.y = height * 0.5
	root.add_child(model)
	RenderLayers.mark_dynamic(root)
	return root


static func _load(name: String) -> Node3D:
	var model: Node3D = (load(DIR + name + ".glb") as PackedScene).instantiate()
	var far_mesh: Mesh = load(far_path(DIR + name + ".glb")) if ResourceLoader.exists(far_path(DIR + name + ".glb")) else null
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if far_mesh == null:
			continue
		var far := MeshInstance3D.new()
		far.name = String(mi.name) + "Far"
		far.mesh = far_mesh
		far.transform = mi.transform
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.set_surface_override_material(0, mi.get_active_material(0))
		far.visibility_range_begin = FAR_RANGE
		far.visibility_range_begin_margin = FAR_MARGIN
		mi.visibility_range_end = FAR_RANGE
		mi.visibility_range_end_margin = FAR_MARGIN
		mi.add_sibling(far)
	return model


## (fraction from the muzzle end, height) -> source model space.
static func _source_point(p: Vector2) -> Vector3:
	return Vector3(-SOURCE_HALF + p.x * SOURCE_HALF * 2.0, p.y, 0.0)


## How far to move model `w` (from instantiate) so its handle sits where the
## pulse rifle's does. Every model is built that way, so this is zero; the
## rigs that hold a weapon by its origin still ask.
static func grip_shift(w: Node3D) -> Vector3:
	return reference_grip() - (w.get_node("Grip") as Node3D).position


## The pulse rifle's Grip in its model root's space.
static func reference_grip() -> Vector3:
	return REFERENCE_GRIP


static func hip_offset(id: StringName) -> Vector3:
	return MODELS[id][1] if MODELS.has(id) else Vector3(0.17, -0.16, -0.5)

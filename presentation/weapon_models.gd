class_name WeaponModels
extends RefCounted
## Weapon meshes (Kenney Blaster Kit, CC0, recoloured to IONFALL's palette by
## tools/recolor_colormap.py) and how each sits in the first-person view.
## Presentation only.

const DIR := "res://art/weapons/kenney/"
## id -> [model, scale, hip offset from the camera, muzzle (model space)]
const MODELS := {
	&"pulse_rifle": ["blaster-n", 0.42, Vector3(0.2, -0.2, -0.46), Vector3(0, 0.03, -0.33)],
	&"mag_pistol": ["blaster-a", 0.34, Vector3(0.19, -0.17, -0.42), Vector3(0, 0.08, -0.38)],
	&"arc_launcher": ["blaster-h", 0.48, Vector3(0.21, -0.2, -0.46), Vector3(0, 0.03, -0.34)],
	&"burst_rifle": ["blaster-g", 0.42, Vector3(0.2, -0.2, -0.46), Vector3(0, 0.03, -0.36)],
	&"rail_sniper": ["blaster-e", 0.4, Vector3(0.19, -0.19, -0.8), Vector3(0, 0.02, -0.02)],
	&"scatter_gun": ["blaster-l", 0.44, Vector3(0.2, -0.19, -0.44), Vector3(0, 0.02, -0.29)],
	&"flux_smg": ["blaster-j", 0.4, Vector3(0.2, -0.2, -0.44), Vector3(0, 0.02, -0.31)],
}

static var _material: StandardMaterial3D
static var _reference_grip = null  ## the pulse rifle's Grip, once measured


static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_texture = load(DIR + "colormap_ion.png")
		_material.emission_enabled = true
		_material.emission_texture = load(DIR + "colormap_ion_emission.png")
		_material.emission_energy_multiplier = 2.0
		_material.roughness = 0.45
		_material.metallic = 0.35
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return _material


static func has(id: StringName) -> bool:
	return MODELS.has(id)


## A ready-to-add model for `id` (markers as children "Muzzle" and "Grip",
## the middle of the handle), or null.
static func instantiate(id: StringName) -> Node3D:
	if not MODELS.has(id):
		return null
	var def: Array = MODELS[id]
	var root := Node3D.new()
	var model: Node3D = (load(DIR + def[0] + ".glb") as PackedScene).instantiate()
	model.scale = Vector3.ONE * float(def[1])
	root.add_child(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var muzzle := Node3D.new()
	muzzle.name = "Muzzle"
	muzzle.position = (def[3] as Vector3) * float(def[1])
	root.add_child(muzzle)
	var grip := Node3D.new()
	grip.name = "Grip"
	grip.position = _handle(model)
	root.add_child(grip)
	return root


## How far to move model `w` (from instantiate) so its handle sits where the
## pulse rifle's does. The rigs that hold a weapon by its origin were placed
## with that rifle; the Rail Sniper's origin is 37 cm ahead of its handle, so
## other players saw it float in front of the hands.
static func grip_shift(w: Node3D) -> Vector3:
	return reference_grip() - (w.get_node("Grip") as Node3D).position


## The pulse rifle's Grip in its model root's space.
static func reference_grip() -> Vector3:
	if _reference_grip == null:
		var ref := instantiate(&"pulse_rifle")
		_reference_grip = (ref.get_node("Grip") as Node3D).position
		ref.free()
	return _reference_grip


## The handle: the middle of the lowest third of the model (the pistol grip
## hangs lowest on every blaster), in the model's parent's space.
static func _handle(model: Node3D) -> Vector3:
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var xf := model.transform * _local_to(model, mi)
		for s in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				pts.append(xf * v)
	if pts.is_empty():
		return Vector3.ZERO
	var lo := INF
	var hi := -INF
	for p in pts:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var c := Vector3.ZERO
	var count := 0
	for p in pts:
		if p.y < lerpf(lo, hi, 0.35):
			c += p
			count += 1
	return c / count


static func _local_to(ancestor: Node3D, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != ancestor:
		xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


static func hip_offset(id: StringName) -> Vector3:
	return MODELS[id][2] if MODELS.has(id) else Vector3(0.17, -0.16, -0.5)

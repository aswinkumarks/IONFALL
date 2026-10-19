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
}

static var _material: StandardMaterial3D


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


## A ready-to-add model for `id` (muzzle marker as child "Muzzle"), or null.
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
	return root


static func hip_offset(id: StringName) -> Vector3:
	return MODELS[id][2] if MODELS.has(id) else Vector3(0.17, -0.16, -0.5)

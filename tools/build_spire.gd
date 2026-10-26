extends SceneTree
## Builds a kit map's presentation scene from its layout (SpireLayout,
## FoundryLayout; PLAN §3.9, §4): kit pieces merged into one
## lightmap-unwrapped mesh per material and map quadrant (so whole quadrants
## can be culled), the layout's slabs, walls, cover and trims as merged
## boxes, baked accent lights, the Dynamic sun, LightmapGI (shadowmask) and
## the environment. Full pipeline:
##
##   tools/build_spire.sh [spire|foundry]

const MAP_LOOK := preload("res://tools/map_look.gd")
const TEXEL_SIZE := 0.25  ## lightmap texel size in metres
const Kind := SpireLayout.Kind
## Box kinds drawn as boxes; the rest are drawn by kit pieces or are invisible.
const BOX_KINDS := [Kind.SLAB, Kind.WALL, Kind.COVER, Kind.TRIM_CYAN, Kind.TRIM_ORANGE, Kind.SPIRE_GLOW]
## Per map: layout, output folder, colour grade (ColorGrade), environment
## and sun.
const MAPS := {
	"spire": {
		"layout": preload("res://maps/spire/spire_layout.gd"), "dir": "res://maps/spire/", "root": "SpirePresentation",
		"grade": {"shadows": Color(0.02, 0.0, 0.06), "highlights": Color(-0.01, 0.025, 0.04), "contrast": 0.2},
		"ambient": Color(0.32, 0.37, 0.48), "ambient_energy": 0.9, "fog": Color(0.25, 0.33, 0.46), "fog_density": 0.004,
		"sun_rotation": Vector3(-48.0, -30.0, 0.0), "sun_color": Color(1.0, 0.95, 0.88), "sun_energy": 1.3,
		"lightmap_color": Color(0.34, 0.38, 0.5), "lightmap_energy": 1.1, "glow": Color(0.4, 0.92, 1.0),
	},
	"foundry": {
		"layout": preload("res://maps/foundry/foundry_layout.gd"), "dir": "res://maps/foundry/", "root": "FoundryPresentation",
		"grade": {"shadows": Color(0.02, 0.0, 0.03), "highlights": Color(0.03, 0.01, -0.02), "contrast": 0.18},
		"ambient": Color(0.4, 0.38, 0.4), "ambient_energy": 1.0, "fog": Color(0.45, 0.3, 0.24), "fog_density": 0.005,
		"sun_rotation": Vector3(-38.0, 60.0, 0.0), "sun_color": Color(1.0, 0.84, 0.68), "sun_energy": 1.45,
		"lightmap_color": Color(0.44, 0.4, 0.42), "lightmap_energy": 1.15, "glow": Color(1.0, 0.42, 0.1),
		"sky": {"space_color": Color(0.03, 0.012, 0.012), "nebula_color": Color(0.32, 0.1, 0.06),
				"planet_color": Color(0.5, 0.18, 0.08), "rim_color": Color(1.0, 0.55, 0.25)},
	},
}

var _map: Dictionary
var _layout: GDScript
var _dir: String
var _panel: Texture2D = load("res://art/textures/panel_grid.png")
var _models: Dictionary = {}  ## model -> [[Mesh, Transform3D], ...]
var _materials: Dictionary = {}  ## key -> Material


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var id: String = args[0] if not args.is_empty() else "spire"
	_map = MAPS[id]
	_layout = _map.layout
	_dir = _map.dir
	var root := Node3D.new()
	root.name = _map.root
	root.set_meta("layout_hash", _layout.layout_hash())
	_add_environment(root)
	_add_lights(root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir + "meshes"))
	var triangles := 0
	var meshes := 0
	# Boxes, merged per kind.
	var by_kind: Dictionary = {}
	for b in _layout.boxes() + _layout.decor():
		if b[0] in BOX_KINDS:
			if not by_kind.has(b[0]):
				by_kind[b[0]] = SurfaceTool.new()
			var box := BoxMesh.new()
			box.size = b[2]
			by_kind[b[0]].append_from(box, 0, Transform3D(Basis.from_euler(b[3] * (PI / 180.0)), b[1]))
	for kind: int in by_kind:
		var name: String = Kind.keys()[kind].to_lower()
		triangles += _save(root, name, by_kind[kind], _box_material(kind))
		meshes += 1
	# Kit pieces, merged per material and quadrant.
	var groups: Dictionary = {}  ## "material key|quadrant" -> SurfaceTool
	for p in _layout.pieces():
		var xf: Transform3D = p[1]
		var quadrant := "%s%s" % ["e" if xf.origin.x >= 0.0 else "w", "s" if xf.origin.z >= 0.0 else "n"]
		for part in _parts(p[0]):
			var mesh: Mesh = part[0]
			for s in mesh.get_surface_count():
				var key := _material_key(mesh.surface_get_material(s)) + "|" + quadrant
				if not groups.has(key):
					groups[key] = SurfaceTool.new()
				groups[key].append_from(mesh, s, xf * part[1])
	for key: String in groups:
		var mat_key := key.get_slice("|", 0)
		var name := "kit_%s_%s" % [mat_key.get_file().get_basename().to_lower(), key.get_slice("|", 1)]
		triangles += _save(root, name, groups[key], _materials[mat_key])
		meshes += 1
	var lm := LightmapGI.new()
	lm.name = "LightmapGI"
	lm.bounces = 2
	lm.shadowmask_mode = LightmapGIData.SHADOWMASK_MODE_OVERLAY
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	lm.environment_custom_color = _map.lightmap_color
	lm.environment_custom_energy = _map.lightmap_energy
	root.add_child(lm)
	MAP_LOOK.finish(root, _map.grade)
	for n in root.get_children():
		n.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	var err := ResourceSaver.save(scene, _dir + "presentation.tscn")
	print("build_spire %s: %d meshes, %d triangles, save %s" % [id, meshes, triangles, error_string(err)])
	root.free()
	quit(0 if err == OK else 1)


## Commits `st` with `material`, unwraps it for the lightmap, saves it and
## adds a static MeshInstance3D; returns its triangle count.
func _save(root: Node3D, name: String, st: SurfaceTool, material: Material) -> int:
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	mesh.lightmap_unwrap(Transform3D.IDENTITY, TEXEL_SIZE)
	mesh = MapMaterials.converted(mesh)
	ResourceSaver.save(mesh, _dir + "meshes/%s.res" % name)
	mesh = load(_dir + "meshes/%s.res" % name)
	var mi := MeshInstance3D.new()
	mi.name = name.to_pascal_case()
	mi.mesh = mesh
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mesh.surface_get_array_index_len(0) / 3


## A kit model's meshes and their transforms in the model's space.
func _parts(model: String) -> Array:
	if not _models.has(model):
		var scene: Node = (load(_layout.model_path(model)) as PackedScene).instantiate()
		var parts := []
		for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var n: Node = mi
			while n != scene:
				xf = (n as Node3D).transform * xf
				n = n.get_parent()
			parts.append([mi.mesh, xf])
		scene.free()
		_models[model] = parts
	return _models[model]


## Kit materials are shared by texture set: one key per base colour and
## normal map.
func _material_key(source: Material) -> String:
	var m := source as StandardMaterial3D
	var key := "plain"
	if m != null and m.albedo_texture != null:
		key = m.albedo_texture.resource_path + ("+n" if m.normal_texture != null else "")
	if not _materials.has(key):
		var copy: StandardMaterial3D = m.duplicate() if m != null else StandardMaterial3D.new()
		copy.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_materials[key] = copy
	return key


func _box_material(kind: int) -> StandardMaterial3D:
	match kind:
		Kind.SLAB: return _panels(Color(0.2, 0.22, 0.26), 0.5, 0.6, 0.4)
		Kind.WALL: return _panels(Color(0.18, 0.2, 0.24), 0.5, 0.6, 0.4)
		Kind.COVER: return _panels(Color(0.3, 0.34, 0.4), 1.0, 0.55, 0.3)
		Kind.TRIM_CYAN: return _emissive(Color(0.35, 0.9, 1.0), 2.6)
		Kind.TRIM_ORANGE: return _emissive(Color(1.0, 0.6, 0.25), 3.0)
		Kind.SPIRE_GLOW: return _emissive(_map.glow, 6.0)
	return StandardMaterial3D.new()


func _panels(color: Color, scale: float, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _panel
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = roughness
	m.metallic = metallic
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _add_environment(root: Node3D) -> void:
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://maps/station/space_sky.gdshader")
	for param: String in _map.get("sky", {}):
		sky_mat.set_shader_parameter(param, _map.sky[param])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _map.ambient
	env.ambient_light_energy = _map.ambient_energy
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX  # keeps bright cyan and orange from clipping to white
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0  # only emissives past glow_hdr_threshold (1.0) glow; bloom hazed the whole frame
	env.fog_enabled = true
	env.fog_light_color = _map.fog
	env.fog_density = _map.fog_density
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)


func _add_lights(root: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = _map.sun_rotation
	sun.light_energy = _map.sun_energy
	sun.light_color = _map.sun_color
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	root.add_child(sun)
	var i := 0
	for l in _layout.lights():
		var omni := OmniLight3D.new()
		omni.name = "Accent%d" % i
		omni.position = l[0]
		omni.light_color = l[1]
		omni.light_energy = l[2]
		omni.omni_range = l[3]
		omni.light_bake_mode = Light3D.BAKE_STATIC
		root.add_child(omni)
		i += 1

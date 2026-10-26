extends SceneTree
## Builds a map's presentation scene from its layout (PLAN §3.9, §4): static
## boxes merged into one lightmap-unwrapped mesh per material, baked accent
## lights, the Dynamic sun, LightmapGI (shadowmask) and the environment.
## Bake afterwards: tools/bake_lightmaps.sh <scene>. Full pipeline:
##
##   tools/build_station.sh

const MAP_LOOK := preload("res://tools/map_look.gd")
## Colour grade (ColorGrade).
const GRADE := {"shadows": Color(-0.01, 0.025, 0.05), "highlights": Color(0.03, 0.015, -0.015), "contrast": 0.15}
const DIR := "res://maps/station/"
const TEXEL_SIZE := 0.2  ## lightmap texel size in metres
const Kind := StationLayout.Kind

var _panel: Texture2D = load("res://art/textures/panel_grid.png")
var _hazard: Texture2D = load("res://art/textures/hazard.png")


func _init() -> void:
	var root := Node3D.new()
	root.name = "StationPresentation"
	root.set_meta("layout_hash", StationLayout.layout_hash())
	_add_environment(root)
	_add_lights(root)
	var by_kind: Dictionary = {}
	for b in StationLayout.boxes() + StationLayout.decor():
		if not by_kind.has(b[0]):
			by_kind[b[0]] = []
		by_kind[b[0]].append(b)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR + "meshes"))
	var triangles := 0
	for kind: int in by_kind:
		var mesh := _merge(by_kind[kind], _material(kind))
		var kind_name: String = Kind.keys()[kind].to_lower()
		ResourceSaver.save(MapMaterials.converted(mesh), DIR + "meshes/%s.res" % kind_name)
		mesh = load(DIR + "meshes/%s.res" % kind_name)
		var mi := MeshInstance3D.new()
		mi.name = kind_name.capitalize().replace(" ", "")
		mi.mesh = mesh
		mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		triangles += mesh.surface_get_array_index_len(0) / 3
	var lm := LightmapGI.new()
	lm.name = "LightmapGI"
	lm.bounces = 2
	lm.shadowmask_mode = LightmapGIData.SHADOWMASK_MODE_OVERLAY
	lm.environment_mode = LightmapGI.ENVIRONMENT_MODE_CUSTOM_COLOR
	lm.environment_custom_color = Color(0.32, 0.38, 0.5)
	lm.environment_custom_energy = 0.6
	root.add_child(lm)
	MAP_LOOK.finish(root, GRADE)
	for n in root.get_children():
		n.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	var err := ResourceSaver.save(scene, DIR + "presentation.tscn")
	print("build_map: %d meshes, %d triangles, save %s" % [by_kind.size(), triangles, error_string(err)])
	root.free()
	quit(0 if err == OK else 1)


func _merge(boxes: Array, material: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	for b in boxes:
		var box := BoxMesh.new()
		box.size = b[2]
		st.append_from(box, 0, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(b[3])), b[1]))
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, material)
	mesh.lightmap_unwrap(Transform3D.IDENTITY, TEXEL_SIZE)
	return mesh


func _material(kind: int) -> StandardMaterial3D:
	match kind:
		Kind.FLOOR: return _panels(Color(0.2, 0.22, 0.27), 0.25, 0.75, 0.1)
		Kind.HULL: return _panels(Color(0.8, 0.82, 0.86), 0.25, 0.7, 0.0)
		Kind.DECK: return _panels(Color(0.6, 0.63, 0.68), 0.5, 0.7, 0.0)
		Kind.RAMP: return _panels(Color(0.52, 0.55, 0.6), 0.5, 0.7, 0.0)
		Kind.BRIDGE: return _panels(Color(0.42, 0.47, 0.53), 1.0, 0.5, 0.4)
		Kind.CRATE: return _panels(Color(0.9, 0.52, 0.18), 1.0, 0.6, 0.0)
		Kind.COVER: return _panels(Color(0.3, 0.38, 0.48), 1.0, 0.6, 0.1)
		Kind.CORE: return _panels(Color(0.12, 0.14, 0.18), 0.5, 0.35, 0.6)
		Kind.MODULE: return _panels(Color(0.88, 0.89, 0.92), 0.5, 0.6, 0.0)
		Kind.PILLAR, Kind.RIB: return _panels(Color(0.62, 0.65, 0.7), 1.0, 0.5, 0.3)
		Kind.BEAM: return _panels(Color(0.25, 0.28, 0.32), 1.0, 0.45, 0.5)
		Kind.TRIM_CYAN: return _emissive(Color(0.35, 0.9, 1.0), 2.6)
		Kind.TRIM_ORANGE: return _emissive(Color(1.0, 0.6, 0.25), 3.0)
		Kind.CORE_GLOW: return _emissive(Color(0.4, 0.92, 1.0), 6.0)
		Kind.HAZARD:
			var m := _panels(Color.WHITE, 1.0, 0.7, 0.0)
			m.albedo_texture = _hazard
			return m
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
	sky_mat.shader = load(DIR + "space_sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.36, 0.48)
	env.ambient_light_energy = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX  # keeps bright cyan and orange from clipping to white
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.0  # only emissives past glow_hdr_threshold (1.0) glow; bloom hazed the whole frame
	env.fog_enabled = true
	env.fog_light_color = Color(0.25, 0.35, 0.48)
	env.fog_density = 0.003
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)


func _add_lights(root: Node3D) -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.light_bake_mode = Light3D.BAKE_DYNAMIC
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	root.add_child(sun)
	var i := 0
	for l in StationLayout.lights():
		var omni := OmniLight3D.new()
		omni.name = "Accent%d" % i
		omni.position = l[0]
		omni.light_color = l[1]
		omni.light_energy = l[2]
		omni.omni_range = l[3]
		omni.light_bake_mode = Light3D.BAKE_STATIC
		root.add_child(omni)
		i += 1

extends Node3D
## Visual half of the test arena (PLAN §3.1): meshes, lights and environment,
## generated from the same layout as the collision. Clients only.
## Greybox look: white/gray panels, ion-cyan trims, glow and light fog. The
## real lighting pipeline (baked lightmaps) is validated in M1c (PLAN §3.9).

const Kind := TestArenaLayout.Kind

var _materials: Dictionary = {}


func _ready() -> void:
	var grid := _grid_texture()
	_materials = {
		Kind.FLOOR: _panel(Color(0.17, 0.19, 0.23), grid, 0.25),
		Kind.WALL: _panel(Color(0.78, 0.8, 0.84), grid, 0.25),
		Kind.PLATFORM: _panel(Color(0.55, 0.58, 0.63), grid, 0.5),
		Kind.RAMP: _panel(Color(0.5, 0.53, 0.58), grid, 0.5),
		Kind.COVER: _panel(Color(0.32, 0.4, 0.5), grid, 0.5),
		Kind.PILLAR: _panel(Color(0.9, 0.91, 0.93), grid, 0.5),
		Kind.LEDGE: _panel(Color(0.85, 0.55, 0.25), grid, 0.5),
		Kind.TRIM: _emissive(Color(0.35, 0.9, 1.0), 4.0),
	}
	for b in TestArenaLayout.boxes():
		var mesh := BoxMesh.new()
		mesh.size = b[2]
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = _materials[b[0]]
		mi.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(b[3])), b[1])
		if b[0] == Kind.TRIM:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_add_lighting()


func _panel(color: Color, grid: Texture2D, scale: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = grid
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = 0.85
	m.metallic = 0.05
	return m


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


## Panel grid: light seams every 64 px with a faint inner bevel.
func _grid_texture() -> Texture2D:
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGB8)
	for y in size:
		for x in size:
			var v := 1.0
			var ex := mini(x % 64, 63 - x % 64)
			var ey := mini(y % 64, 63 - y % 64)
			var e := mini(ex, ey)
			if e == 0:
				v = 0.55
			elif e == 1:
				v = 0.8
			elif e < 4:
				v = 0.95
			img.set_pixel(x, y, Color(v, v, v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.06, 0.12)
	sky_mat.sky_horizon_color = Color(0.2, 0.3, 0.42)
	sky_mat.ground_horizon_color = Color(0.2, 0.3, 0.42)
	sky_mat.ground_bottom_color = Color(0.05, 0.06, 0.08)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.3, 0.42, 0.55)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

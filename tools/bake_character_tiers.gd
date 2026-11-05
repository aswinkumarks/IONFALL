extends SceneTree
## Saves each selectable character's quality tiers (MeshyRig.TIERS) next to
## its source model, from one detailed source:
## - <c>_rig.scn: the model's skeleton and mesh node with no mesh or
##   material, so loading a character loads no source textures;
## - <c>_mesh_<tier>.res: high = the full mesh (finger binds), medium = its
##   first LOD as the base level (ReducedMesh), low = its second; none
##   carries a material;
## - <c>_mat_<tier>.tres: high = the 2K source textures, medium = 1K copies
##   (<c>_<map>_1k.png), low = one 512 posterized colour texture
##   (<c>_flat.png) on the stylized shader.
## Then import the new textures and bake again (the materials need them):
##
##   xvfb-run godot --rendering-driver vulkan -s tools/bake_character_tiers.gd
##   godot --headless --import
##   xvfb-run godot --rendering-driver vulkan -s tools/bake_character_tiers.gd
##
## Run again after tools/rig_meshy_fingers.gd rebuilds a character's mesh.

const MEDIUM_SIZE := 1024
const FLAT_SIZE := 512
const FLAT_SMOOTH := 512  ## smoothed at this size, then posterized (Meshy UVs are many small islands: smaller bleeds across them)
const HUES := 18
const LEVELS := 5


func _init() -> void:
	var missing := false
	for c: String in CharacterRig.SELECTABLE:
		missing = _bake(c) or missing
	if missing:
		print("New textures written: run `godot --headless --import`, then this tool again for the materials.")
	quit()


## Returns whether textures were written that still need importing.
func _bake(c: String) -> bool:
	var dir := MeshyRig.DIR + c + "/"
	var full: ArrayMesh = load(MeshyRig.finger_mesh_path(c))
	var base := full.surface_get_material(0) as StandardMaterial3D
	var sources := {"albedo": base.albedo_texture.resource_path, "mr": base.metallic_texture.resource_path,
			"normal": base.normal_texture.resource_path}
	# Meshes: the full one without its material, and two reductions.
	_save(_without_materials(full), MeshyRig.tier_mesh_path(c, "high"))
	_save(ReducedMesh.build(full, 1), MeshyRig.tier_mesh_path(c, "medium"))
	_save(ReducedMesh.build(full, 2), MeshyRig.tier_mesh_path(c, "low"))
	_save_rig_scene(c)
	# Textures.
	var pending := false
	for key: String in sources:
		var out := dir + "%s_%s_1k.png" % [c, key]
		if not FileAccess.file_exists(out):
			var img := Image.load_from_file(ProjectSettings.globalize_path(sources[key]))
			img.resize(MEDIUM_SIZE, MEDIUM_SIZE, Image.INTERPOLATE_LANCZOS)
			img.save_png(ProjectSettings.globalize_path(out))
			_write_import(out, key == "normal")
			pending = true
	var flat := dir + c + "_flat.png"
	if not FileAccess.file_exists(flat):
		_flat_texture(ProjectSettings.globalize_path(sources.albedo)).save_png(ProjectSettings.globalize_path(flat))
		_write_import(flat, false)
		pending = true
	if pending:
		return true
	# Materials.
	var shaded := func(shader: Shader, tex: Dictionary) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = shader
		for k: String in tex:
			m.set_shader_parameter(k + "_tex", load(tex[k]))
		return m
	_save(shaded.call(MeshyRig.SHADER, sources), MeshyRig.tier_material_path(c, "high"))
	var medium := {}
	for key: String in sources:
		medium[key] = dir + "%s_%s_1k.png" % [c, key]
	_save(shaded.call(MeshyRig.SHADER, medium), MeshyRig.tier_material_path(c, "medium"))
	_save(shaded.call(MeshyRig.STYLIZED_SHADER, {"albedo": flat}), MeshyRig.tier_material_path(c, "low"))
	return false


func _without_materials(mesh: ArrayMesh) -> ArrayMesh:
	var out: ArrayMesh = mesh.duplicate()
	for s in out.get_surface_count():
		out.surface_set_material(s, null)
	return out


## The model as the rig uses it: skeleton and mesh node, no mesh, no
## material, no Meshy rig-check animation.
func _save_rig_scene(c: String) -> void:
	var model: Node = (load(MeshyRig.scene_path(c)) as PackedScene).instantiate()
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.mesh = null
		mi.material_override = null
		mi.skin = null
	for a: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		a.get_parent().remove_child(a)
		a.free()
	for n in model.find_children("*", "", true, false):
		n.owner = model
	var scene := PackedScene.new()
	scene.pack(model)
	_save(scene, MeshyRig.rig_scene_path(c))
	model.free()


## The colour texture as flat regions: smoothed small (drops the fine
## noise and baked shading), scaled up, then each texel's hue, saturation
## and value snapped to a few steps, which gives crisp region edges.
func _flat_texture(src_path: String) -> Image:
	var img := Image.load_from_file(src_path)
	img.convert(Image.FORMAT_RGB8)
	img.resize(FLAT_SMOOTH, FLAT_SMOOTH, Image.INTERPOLATE_LANCZOS)
	img.resize(FLAT_SIZE, FLAT_SIZE, Image.INTERPOLATE_CUBIC)
	for y in FLAT_SIZE:
		for x in FLAT_SIZE:
			var col := img.get_pixel(x, y)
			var h := snappedf(col.h, 1.0 / HUES)
			var s := snappedf(col.s, 1.0 / 3.0)
			var v := clampf(snappedf(col.v, 1.0 / LEVELS), 0.06, 1.0)
			img.set_pixel(x, y, Color.from_hsv(fposmod(h, 1.0), s, v))
	return img


## Import settings for a baked texture: VRAM-compressed with mipmaps, like
## the source textures.
func _write_import(path: String, normal: bool) -> void:
	var f := FileAccess.open(path + ".import", FileAccess.WRITE)
	f.store_string("""[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/normal_map=%d
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
process/fix_alpha_border=true
process/size_limit=0
detect_3d/compress_to=0
""" % (1 if normal else 2))
	f.close()


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	print("%s%s" % [path, "" if err == OK else " ERROR %d" % err])

extends SceneTree
## Builds each weapon model's low-detail stand-in, saved next to it as
## "<model>_far.res", which WeaponModels shows past FAR_RANGE (other players'
## weapons, pickups). Run again after replacing a model:
##
##   xvfb-run godot --rendering-driver vulkan -s tools/bake_weapon_proxies.gd
##
## The Meshy models are close to triangle soup (about two vertices per
## triangle, split at every UV and normal seam), so the importer's own LOD
## generation finds no edges to collapse: every remote player's gun stayed
## at 6-8k triangles at any distance. Here vertices at the same position are
## welded first (keeping one UV each; at a distance the seams don't show),
## the welded mesh goes through the engine's quadric simplifier
## (ImporterMesh.generate_lods), and the level nearest TARGET triangles gets
## smooth normals and tangents. The stand-in carries no material:
## WeaponModels gives it the model's.

const TARGET := 1000


func _init() -> void:
	for path in WeaponModels.paths():
		if not path.ends_with(".glb"):
			continue
		var scene: Node = (load(path) as PackedScene).instantiate()
		var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
		var far := proxy(mi.mesh)
		var err := ResourceSaver.save(far, WeaponModels.far_path(path))
		print("%s: %d triangles%s" % [WeaponModels.far_path(path), far.surface_get_array_index_len(0) / 3,
				"" if err == OK else " ERROR %d" % err])
		scene.free()
	quit()


static func proxy(mesh: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var welded := _weld(arrays)
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, welded)
		im.generate_lods(180.0, 180.0, [])
		var indices: PackedInt32Array = welded[Mesh.ARRAY_INDEX]
		for l in im.get_surface_lod_count(0):
			var lod := im.get_surface_lod_indices(0, l)
			if absi(lod.size() / 3 - TARGET) < absi(indices.size() / 3 - TARGET):
				indices = lod
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var verts: PackedVector3Array = welded[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = welded[Mesh.ARRAY_TEX_UV]
		for i in indices:
			st.set_uv(uvs[i])
			st.add_vertex(verts[i])
		st.index()
		st.generate_normals()
		if arrays[Mesh.ARRAY_TANGENT] != null:
			st.generate_tangents()
		# Same vertex format as the model (attribute compression included), so
		# the stand-in draws with the pipelines the warm-up already compiled.
		var flags: int = mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, flags)
	return out


## Positions and UVs with every vertex at the same position (to 0.1 mm)
## merged into the first one there.
static func _weld(arrays: Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var at := {}
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	var out_v := PackedVector3Array()
	var out_uv := PackedVector2Array()
	for v in verts.size():
		var key := Vector3i((verts[v] * 10000.0).round())
		if not at.has(key):
			at[key] = out_v.size()
			out_v.append(verts[v])
			out_uv.append(uvs[v])
		remap[v] = at[key]
	var out_i := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var a := remap[indices[t]]
		var b := remap[indices[t + 1]]
		var c := remap[indices[t + 2]]
		if a != b and b != c and a != c:
			out_i.append_array([a, b, c])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_TEX_UV] = out_uv
	out[Mesh.ARRAY_INDEX] = out_i
	return out

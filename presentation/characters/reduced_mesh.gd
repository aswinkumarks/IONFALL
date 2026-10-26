class_name ReducedMesh
extends RefCounted
## The selectable characters' meshes cut down for third person (PLAN §3.10
## GPU budget): the base level becomes the mesh's own first LOD (about half
## the triangles), the coarser LODs stay, and the vertices none of them use
## are dropped. LODs alone only trim indices: every remote player was still
## skinning all 26-31k vertices of the full mesh each frame, at any
## distance. The reduced mesh skins about half that. First person and the
## character screen keep the full mesh (MeshyRig.full_detail).
##
## Built from the mesh's own LODs (no new simplification) and saved by
## tools/bake_reduced_characters.gd as MeshyRig.reduced_mesh_path.


## `mesh` with LOD 1 as its base level, or `mesh` itself where it has no LODs
## (or no CPU-side data).
static func build(mesh: ArrayMesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	out.custom_aabb = mesh.custom_aabb
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var lods := lods_of(mesh, s)
		if lods.is_empty() or (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			return mesh
		var levels: Array[PackedInt32Array] = []
		for l: Array in lods:
			levels.append(l[1])
		var reduced := compact(arrays, levels)
		var coarser := {}
		for i in range(1, lods.size()):
			coarser[lods[i][0]] = reduced[1][i]
		var flags: int = mesh.surface_get_format(s) & (Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, reduced[0], [], coarser, flags)
		out.surface_set_name(s, mesh.surface_get_name(s))
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


## Surface `s`'s LODs, finest first: [edge length, indices] pairs.
static func lods_of(mesh: ArrayMesh, s: int) -> Array:
	var d := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
	var count: int = d.get("index_count", 0)
	var base: PackedByteArray = d.get("index_data", PackedByteArray())
	if count == 0 or base.is_empty():
		return []
	var wide := base.size() / count == 4
	var out := []
	for l: Dictionary in d.get("lods", []):
		var bytes: PackedByteArray = l.index_data
		var idx := PackedInt32Array()
		if wide:
			idx = bytes.to_int32_array()
		else:
			idx.resize(bytes.size() / 2)
			for i in idx.size():
				idx[i] = bytes.decode_u16(i * 2)
		out.append([float(l.edge_length), idx])
	return out


## `arrays` (a surface's, decompressed) keeping only the vertices `levels`
## use, `levels[0]` as the index array. Returns [arrays, levels remapped].
static func compact(arrays: Array, levels: Array[PackedInt32Array]) -> Array:
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := PackedInt32Array()
	remap.resize(count)
	remap.fill(-1)
	var order := PackedInt32Array()
	var out_levels: Array[PackedInt32Array] = []
	for level in levels:
		var mapped := PackedInt32Array()
		mapped.resize(level.size())
		for i in level.size():
			var v := level[i]
			if remap[v] < 0:
				remap[v] = order.size()
				order.append(v)
			mapped[i] = remap[v]
		out_levels.append(mapped)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		if k == Mesh.ARRAY_INDEX or arrays[k] == null:
			continue
		out[k] = _gather(arrays[k], order, count)
	out[Mesh.ARRAY_INDEX] = out_levels[0]
	return [out, out_levels]


## The per-vertex entries of `src` (a packed array, any stride) at `order`.
static func _gather(src: Variant, order: PackedInt32Array, count: int) -> Variant:
	var stride: int = src.size() / count
	var dst: Variant = src.duplicate()
	dst.resize(order.size() * stride)
	if stride == 1:
		for j in order.size():
			dst[j] = src[order[j]]
	else:
		for j in order.size():
			var o := order[j] * stride
			var p := j * stride
			for t in stride:
				dst[p + t] = src[o + t]
	return dst

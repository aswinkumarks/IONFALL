class_name MapMaterials
extends RefCounted
## Cheaper materials on a map's meshes (PLAN §3.10 GPU budget), baked into
## the saved meshes: the map builders (tools/build_map.gd, build_spire.gd)
## convert each mesh as they save it, and tools/bake_map_materials.gd
## converted the maps built before. Geometry and the lightmap UVs (UV2)
## don't change, so the baked lightmaps stay valid.
##
## - World triplanar becomes planar UVs. Triplanar samples every texture
##   three times per pixel; the panels are boxes, so each face takes the one
##   projection triplanar weights fully (its normal's dominant axis),
##   written into UV1, and samples once. Geometry and the lightmap UVs (UV2)
##   stay as baked.
## - Back faces are culled on the kit materials in CULL_BACK. The kit's
##   glTFs mark every material double-sided; tools/cull_check found that
##   only MI_Trim_01 and MI_Trim_02 show back faces anywhere a player
##   stands (open wall panels), so those stay double-sided.

const CULL_BACK := ["MI_Props_Crates", "MI_Trim_02_Floor", "MI_Trim_03", "MI_Trim_03_Dark", "MI_Decal_Grey"]


## `mesh` with planar UVs instead of world triplanar and culled back faces
## where CULL_BACK says; `mesh` itself if nothing changes. `xf` places it in
## the world (map meshes are built at the origin).
static func converted(mesh: ArrayMesh, xf: Transform3D = Transform3D.IDENTITY) -> ArrayMesh:
	var changed := false
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		changed = changed or (m != null and (_triplanar(m) or _culls(m)))
	if not changed:
		return mesh
	var out := ArrayMesh.new()
	out.lightmap_size_hint = mesh.lightmap_size_hint
	out.custom_aabb = mesh.custom_aabb
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i) as BaseMaterial3D
		var arrays := mesh.surface_get_arrays(i)
		if m != null and (_triplanar(m) or _culls(m)):
			m = m.duplicate() as BaseMaterial3D
			if _triplanar(m):
				planar_uvs(arrays, m, xf)
				m.uv1_triplanar = false
				m.uv1_world_triplanar = false
				m.uv1_scale = Vector3.ONE
				m.uv1_offset = Vector3.ZERO
			if _culls(m):
				m.cull_mode = BaseMaterial3D.CULL_BACK
		var flags: int = mesh.surface_get_format(i) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays, [], {}, flags)
		out.surface_set_name(i, mesh.surface_get_name(i))
		out.surface_set_material(i, m)
	return out


## Writes UV1 as world triplanar's dominant projection (BaseMaterial3D's
## triplanar_texture: xy for ±Z faces, xz for ±Y, zy * (-1, 1) for ±X, after
## scale, offset and y flipped). Returns the triangles whose corners pick
## different projections (slopes, which would stretch slightly; the maps
## have none).
static func planar_uvs(arrays: Array, m: BaseMaterial3D, xf: Transform3D = Transform3D.IDENTITY) -> int:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv := PackedVector2Array()
	uv.resize(verts.size())
	var axis := PackedByteArray()
	axis.resize(verts.size())
	for v in verts.size():
		var p := ((xf * verts[v]) * m.uv1_scale + m.uv1_offset) * Vector3(1.0, -1.0, 1.0)
		var n := (xf.basis * normals[v]).abs()
		if n.z >= n.x and n.z >= n.y:
			uv[v] = Vector2(p.x, p.y)
			axis[v] = 2
		elif n.y >= n.x:
			uv[v] = Vector2(p.x, p.z)
			axis[v] = 1
		else:
			uv[v] = Vector2(-p.z, p.y)
			axis[v] = 0
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mixed := 0
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	for t in range(0, idx.size(), 3):
		if axis[idx[t]] != axis[idx[t + 1]] or axis[idx[t]] != axis[idx[t + 2]]:
			mixed += 1
	return mixed


static func _triplanar(m: BaseMaterial3D) -> bool:
	return m.uv1_triplanar and m.uv1_world_triplanar


static func _culls(m: BaseMaterial3D) -> bool:
	return m.cull_mode == BaseMaterial3D.CULL_DISABLED and m.resource_name in CULL_BACK


## `node`'s transform relative to `root` (a scene not in the tree).
static func transform_in(node: Node3D, root: Node) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	if root is Node3D:
		xf = (root as Node3D).transform * xf
	return xf

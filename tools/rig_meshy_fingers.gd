extends SceneTree
## Adds finger bones to a Meshy character (Meshy's auto-rig has none): three
## per finger and thumb on each hand, placed from the hand mesh and skinned by
## distance to the bone segments. Writes a re-weighted mesh and a skin with
## the extra binds next to the model; MeshyRig adds the bones to its skeleton
## from the skin. Then bakes the character's retargeted animation clips
## (MeshyRig.anims_path), so the game doesn't bake them at run time.
##
##   godot --headless -s tools/rig_meshy_fingers.gd -- sentinel
##
## In the hand bone's space (centimetres) the fingers run along +Y; the
## thumb's tip is the cluster across a gap from the four fingers.

const FINGERS := ["Index", "Middle", "Ring", "Pinky"]
const KNUCKLE_Y := 13.0  ## where the fingers leave the palm
const MCP_DEPTH := 1.5  ## knuckle joints sit this far inside the palm
const PALM_FADE := 2.0  ## finger weights fade out over this far below the knuckles
const MIN_HAND := 0.5  ## vertices mostly on the hand place the bones


func _init() -> void:
	var character: String = OS.get_cmdline_user_args()[0]
	var scene: Node = (load(MeshyRig.scene_path(character)) as PackedScene).instantiate()
	var mi: MeshInstance3D = scene.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := mi.mesh.surface_get_arrays(0)
	var skin: Skin = mi.skin.duplicate()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var added := 0
	for side: String in ["Right", "Left"]:
		var hand := _bind(skin, side + "Hand")
		var hand_pose := skin.get_bind_pose(hand)
		var pts := PackedVector3Array()
		for i in verts.size():
			if _weight(bones, weights, i, hand) >= MIN_HAND:
				pts.append(hand_pose * verts[i])
		var chains := _chains(pts)  ## name -> [joint0, joint1, joint2, tip], hand space
		# Bones: each joint, parented to the previous one (the first to the hand).
		var segments := []  ## [bind, from, to, fades]
		for name: String in chains:
			var c: Array = chains[name]
			for k in 3:
				var bind := skin.get_bind_count()
				skin.add_named_bind("%sHand%s%d" % [side, name, k + 1], Transform3D(Basis(), -(c[k] as Vector3)) * hand_pose)
				segments.append([bind, c[k], c[k + 1], name != "Thumb" and k == 0])
				added += 1
		var knuckle := 0.0
		for name: String in FINGERS:
			knuckle += (chains[name][0] as Vector3).y / FINGERS.size()
		var palm_tip := Vector3.ZERO
		for name: String in FINGERS:
			palm_tip += (chains[name][0] as Vector3) / FINGERS.size()
		segments.append([hand, Vector3.ZERO, palm_tip, false])
		# Re-weight: each vertex's hand share goes to the nearest segments.
		for i in verts.size():
			var wh := _weight(bones, weights, i, hand)
			if wh <= 0.0:
				continue
			var p := hand_pose * verts[i]
			var fade := smoothstep(knuckle - PALM_FADE, knuckle, p.y)
			var share := {}
			var total := 0.0
			for s: Array in segments:
				var d := maxf(_seg_dist(p, s[1], s[2]), 0.3)
				var w := 1.0 / pow(d, 4.0)
				if s[3]:
					w *= fade
				share[s[0]] = share.get(s[0], 0.0) + w
				total += w
			var influences := {}
			for k in 4:
				var b := bones[i * 4 + k]
				if b != hand and weights[i * 4 + k] > 0.0:
					influences[b] = influences.get(b, 0.0) + weights[i * 4 + k]
			for b: int in share:
				influences[b] = influences.get(b, 0.0) + wh * share[b] / total
			_write(bones, weights, i, influences)
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mi.mesh.surface_get_material(0))
	im.generate_lods(60.0, 0.0, [])
	var mesh := im.get_mesh()
	var err := ResourceSaver.save(mesh, MeshyRig.finger_mesh_path(character))
	var err2 := ResourceSaver.save(skin, MeshyRig.finger_skin_path(character))
	print("rig_meshy_fingers %s: %d bones added, mesh %s, skin %s" % [character, added, error_string(err), error_string(err2)])
	scene.free()
	var err3 := _bake_anims(character)
	quit(0 if err == OK and err2 == OK and err3 == OK else 1)


func _bake_anims(character: String) -> Error:
	var model: Node3D = (load(MeshyRig.scene_path(character)) as PackedScene).instantiate()
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var lib := MeshyRig._retarget_to(character, sk, String(model.get_path_to(sk)), true)
	var err := ResourceSaver.save(lib, MeshyRig.anims_path(character))
	print("rig_meshy_fingers %s: %d clips baked, %s" % [character, lib.get_animation_list().size(), error_string(err)])
	model.free()
	return err


## Finger and thumb chains from the hand's vertices (hand space).
func _chains(pts: PackedVector3Array) -> Dictionary:
	# Past the knuckles: the thumb's tip and the fingers, split at the widest gap in x.
	var up := []
	for p in pts:
		if p.y > KNUCKLE_Y:
			up.append(p)
	up.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.x < b.x)
	var gap := 0
	for i in up.size() - 1:
		if up[i + 1].x - up[i].x > up[gap + 1].x - up[gap].x:
			gap = i
	var low := up.slice(0, gap + 1)
	var high := up.slice(gap + 1)
	var thumb_low := low.size() < high.size()  ## thumb on -x (right hand) or +x
	var fingers: Array = high if thumb_low else low
	var thumb: Array = low if thumb_low else high
	# Fingers: four equal bands across the finger cluster, index next to the thumb.
	var xs := []
	for p: Vector3 in fingers:
		if p.y > KNUCKLE_Y + 2.0:
			xs.append(p.x)
	xs.sort()
	var lo: float = xs[int(xs.size() * 0.02)]
	var hi: float = xs[int(xs.size() * 0.98)]
	var out := {}
	for k in 4:
		var band := k if thumb_low else 3 - k
		var a := lerpf(lo, hi, band / 4.0)
		var b := lerpf(lo, hi, (band + 1) / 4.0)
		var member := []
		for p: Vector3 in fingers:
			if (p.x >= a or band == 0) and (p.x < b or band == 3):
				member.append(p)
		var top := 0.0
		for p: Vector3 in member:
			top = maxf(top, p.y)
		top -= 0.3
		var length := top - KNUCKLE_Y
		var base := _slice(member, KNUCKLE_Y + 0.3) - Vector3(0.0, MCP_DEPTH, 0.0)
		out[FINGERS[k]] = [base, _slice(member, KNUCKLE_Y + length * 0.42),
				_slice(member, KNUCKLE_Y + length * 0.72), _slice(member, top - 0.3)]
	# Thumb: from the ball of the thumb, through the middle of its tip cluster, to its farthest point.
	var sign := -1.0 if thumb_low else 1.0
	var side := []
	for p in pts:
		side.append(p.x * sign)
	side.sort()
	var edge: float = side[int(side.size() * 0.85)]
	var ball := Vector3.ZERO
	var n := 0
	for p in pts:
		if p.x * sign > edge and p.y > 4.0 and p.y < 11.0:
			ball += p
			n += 1
	ball /= maxi(n, 1)
	var base := Vector3(ball.x * 0.45, 3.0, ball.z)
	var tip: Vector3 = thumb[0]
	for p: Vector3 in thumb:
		if p.distance_to(base) > tip.distance_to(base):
			tip = p
	out["Thumb"] = [base, ball, ball.lerp(tip, 0.55), tip]
	return out


## Centroid of `pts` within a thin slice around height `y`.
func _slice(pts: Array, y: float) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for p: Vector3 in pts:
		if absf(p.y - y) < 0.8:
			c += p
			n += 1
	return c / n if n > 0 else Vector3(0.0, y, 0.0)


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _bind(skin: Skin, name: String) -> int:
	for b in skin.get_bind_count():
		if skin.get_bind_name(b) == name:
			return b
	return -1


func _weight(bones: PackedInt32Array, weights: PackedFloat32Array, i: int, bind: int) -> float:
	var w := 0.0
	for k in 4:
		if bones[i * 4 + k] == bind:
			w += weights[i * 4 + k]
	return w


## The four largest influences, normalised.
func _write(bones: PackedInt32Array, weights: PackedFloat32Array, i: int, influences: Dictionary) -> void:
	var keys := influences.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return influences[a] > influences[b])
	var total := 0.0
	for k in mini(4, keys.size()):
		total += influences[keys[k]]
	for k in 4:
		bones[i * 4 + k] = keys[k] if k < keys.size() else 0
		weights[i * 4 + k] = influences[keys[k]] / total if k < keys.size() else 0.0

class_name BlobShadows
extends MultiMeshInstance3D
## Soft round shadows under the characters when realtime shadows are off
## (Low, and Medium on phones: PLAN §3.9 promises them), so bodies don't
## float over the floor. One MultiMesh: one draw call for all of them.
## Each frame a ray down from every character finds the floor; the blob
## lies on it and fades as the character rises (gone at FADE_HEIGHT).

const SHADER := preload("res://presentation/blob_shadow.gdshader")
const MAX_BLOBS := Protocol.MAX_PEERS + 1
const SIZE := 1.1  ## metres across
const FADE_HEIGHT := 3.0
const LIFT := 0.03  ## above the floor, against z-fighting

## Where there's no collision to find the floor (the menu backdrop): the
## blob goes straight under the feet.
var floor_at_feet := false


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(SIZE, SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	quad.material = mat
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_BLOBS
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	RenderLayers.mark_dynamic(self)
	_apply_setting()
	Events.settings_changed.connect(func(section: String, _key: String, _value: Variant) -> void:
		if section == "video":
			_apply_setting())


func _apply_setting() -> void:
	visible = Settings.video("shadows") == false


## Shadows under `feet` (world positions; Vector3.INF entries are skipped)
## until the next call.
func show_at(feet: PackedVector3Array) -> void:
	if not visible or not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	var n := 0
	for p in feet:
		if p == Vector3.INF or n >= MAX_BLOBS:
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				p + Vector3.UP * 0.3, p + Vector3.DOWN * FADE_HEIGHT, Sim.LAYER_WORLD))
		if hit.is_empty():
			if not floor_at_feet:
				continue
			hit = {"position": p, "normal": Vector3.UP}
		var blob := place(p, hit.position, hit.normal)
		multimesh.set_instance_transform(n, blob[0])
		multimesh.set_instance_custom_data(n, Color(0, 0, 0, blob[1]))
		n += 1
	multimesh.visible_instance_count = n


## [transform, strength] of the blob under `feet`, on the floor at `floor`
## facing `normal` (ramps tilt it), fading out at FADE_HEIGHT above it.
static func place(feet: Vector3, floor: Vector3, normal: Vector3) -> Array:
	var side := Vector3.RIGHT if absf(normal.x) < 0.9 else Vector3.FORWARD
	var z := side.cross(normal).normalized()
	var on_floor := Basis(normal.cross(z).normalized(), normal, z)
	var height := feet.y - floor.y
	return [Transform3D(on_floor, floor + normal * LIFT), clampf(1.0 - height / FADE_HEIGHT, 0.0, 1.0)]

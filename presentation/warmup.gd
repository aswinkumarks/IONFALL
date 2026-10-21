class_name Warmup
extends Node3D
## Shader warm-up (PLAN §3.9; cold-start stutter, §5): at map load, every
## selectable character (with its hit and shield effects), every weapon
## model and every effect is drawn for a few frames in front of the camera,
## behind the loading cover, so their pipelines compile before play instead
## of on first use mid-fight. The release exports also pre-compile shader
## code with the shader baker; pipelines still need a first draw.

signal finished

const FRAMES := 8


## Draws everything in front of `camera`, then frees itself and emits
## `finished`.
func start(camera: Camera3D, effects: Effects) -> void:
	var eye := camera.global_transform
	# Two sets: one lit by an omni light, one not. Moving objects pick up
	# the map's (baked) accent lights at runtime, and on the Mobile renderer
	# an object first lit by an omni light compiles another pipeline
	# specialization (M4 hitch log, docs/perf/m4.md).
	for lit in [true, false]:
		var front := eye * Vector3(-1.6 if lit else 1.6, -0.4, -4.0)
		if lit:
			# Also around the camera, for the first-person arms and weapon.
			for at: Vector3 in [front + Vector3.UP, eye.origin]:
				var light := OmniLight3D.new()
				add_child(light)
				light.omni_range = 2.5
				light.light_bake_mode = Light3D.BAKE_DISABLED
				light.global_position = at
		_draw_set(front, eye.basis.x, effects)
	for f in FRAMES:
		await get_tree().process_frame
	# The arms and weapon unlit too.
	for light in find_children("*", "OmniLight3D", false, false):
		light.queue_free()
	for f in FRAMES:
		await get_tree().process_frame
	finished.emit()
	queue_free()


func _draw_set(front: Vector3, right: Vector3, effects: Effects) -> void:
	var i := 0
	for style: String in CharacterRig.SELECTABLE:
		var v := PlayerVisual.new()
		add_child(v)
		v.setup("", false, GameMode.TEAM_COLORS[i % 2], 0, style)
		v.global_position = front + right * (i - 1) * 0.5 - Vector3.UP
		v.flash_hit(true)
		i += 1
	var w := 0
	for data: WeaponData in Weapons.ALL:
		var model := WeaponModels.instantiate(data.id)
		if model == null:
			continue
		add_child(model)
		model.global_position = front + right * (w - 3) * 0.2 + Vector3.UP * 0.8
		w += 1
	effects.warm_up(front)

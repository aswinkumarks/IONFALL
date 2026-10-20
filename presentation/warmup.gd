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
	var front := eye * Vector3(0.0, -0.4, -4.0)
	var right := eye.basis.x
	var i := 0
	for style: String in CharacterRig.SELECTABLE:
		var v := PlayerVisual.new()
		add_child(v)
		v.setup("", false, GameMode.TEAM_COLORS[i % 2], 0, style)
		v.global_position = front + right * (i - 1) * 1.2 - Vector3.UP
		v.flash_hit(true)
		i += 1
	var w := 0
	for data: WeaponData in Weapons.ALL:
		var model := WeaponModels.instantiate(data.id)
		if model == null:
			continue
		add_child(model)
		model.global_position = front + right * (w - 3) * 0.4 + Vector3.UP * 0.8
		w += 1
	effects.warm_up(front)
	for f in FRAMES:
		await get_tree().process_frame
	finished.emit()
	queue_free()

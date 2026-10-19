class_name CapsuleRig
extends CharacterRig
## Greybox body: capsule plus visor (2 draws).

var _body: MeshInstance3D
var _visor: MeshInstance3D
var _material := StandardMaterial3D.new()


func setup(color: Color) -> void:
	_material.albedo_color = color
	_material.roughness = 0.5
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 0.0
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	_body.mesh = capsule
	_body.material_override = _material
	add_child(_body)
	_visor = MeshInstance3D.new()
	var visor := BoxMesh.new()
	visor.size = Vector3(0.5, 0.14, 0.12)
	_visor.mesh = visor
	var visor_mat := StandardMaterial3D.new()
	visor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	visor_mat.albedo_color = Color(0.35, 0.9, 1.0)
	_visor.material_override = visor_mat
	add_child(_visor)


func animate(_state: PlayerSimState, _delta: float, height: float) -> void:
	_body.scale = Vector3(1.0, height / 1.8, 1.0)
	_body.position.y = height * 0.5
	_visor.position = Vector3(0.0, height - 0.25, -0.33)


func set_glow(amount: float) -> void:
	_material.emission_energy_multiplier = amount

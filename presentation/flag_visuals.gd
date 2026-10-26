class_name FlagVisuals
extends Node3D
## CTF flags (PLAN §2.4): each team's base is a glowing pad in its colour
## with its shape; the flag (pole and banner) stands on it, rides above its
## carrier's head, or lies where it fell. Presentation only: fed from
## SimWorld.flags (host) or snapshot flag dictionaries (client).

const POLE_HEIGHT := 2.2
const CARRIED_LIFT := 1.9  ## above the carrier's feet

var _bases: Array[Node3D] = []
var _flags: Array[Node3D] = []
var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	for f in _flags:
		var banner: Node3D = f.get_node("Banner")
		banner.rotation.y = sin(_time * 2.0 + f.get_index()) * 0.25


## `flags`: SimWorld.Flag objects or {team, carrier, position} dictionaries;
## `bases`: the map's flag bases. `carrier_pos`: Callable(id) -> Vector3
## for where a carrier is drawn right now (INF if unknown).
func sync(flags: Array, bases: Array, carrier_pos: Callable) -> void:
	while _bases.size() < mini(bases.size(), 2):
		var pad := _make_base(_bases.size())
		pad.position = bases[_bases.size()]
		add_child(pad)
		_bases.append(pad)
	while _flags.size() < flags.size():
		var f := _make_flag(_flags.size())
		add_child(f)
		_flags.append(f)
	for i in _flags.size():
		var node := _flags[i]
		if i >= flags.size():
			node.visible = false
			continue
		var f: Variant = flags[i]
		var carrier: int = f.carrier
		var pos: Vector3 = f.position
		var tilt := 0.0
		if carrier != 0:
			var at: Vector3 = carrier_pos.call(carrier)
			if at != Vector3.INF:
				pos = at
			pos += Vector3(0, CARRIED_LIFT - POLE_HEIGHT * 0.5, 0)
			tilt = 0.35
		node.visible = true
		node.position = pos
		node.rotation.z = tilt


func _make_base(team: int) -> Node3D:
	var root := Node3D.new()
	var color: Color = GameMode.team_color(team)
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.3
	disc.bottom_radius = 1.4
	disc.height = 0.08
	pad.mesh = disc
	pad.position.y = 0.04
	pad.material_override = _glow(color, 0.6, 0.35)
	root.add_child(pad)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.25
	torus.outer_radius = 1.4
	ring.mesh = torus
	ring.position.y = 0.1
	ring.material_override = _glow(color, 1.0, 2.5)
	root.add_child(ring)
	# The team's shape (◆ / ▲) floating over the pad: never colour alone.
	var shape := Label3D.new()
	shape.text = "◆" if team == 0 else "▲"
	shape.font_size = 160
	shape.modulate = color
	shape.outline_size = 0
	shape.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	shape.position.y = 3.2
	root.add_child(shape)
	RenderLayers.mark_dynamic(root)
	return root


func _make_flag(team: int) -> Node3D:
	var root := Node3D.new()
	var color: Color = GameMode.team_color(team)
	var pole := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.035
	cyl.bottom_radius = 0.045
	cyl.height = POLE_HEIGHT
	pole.mesh = cyl
	pole.position.y = POLE_HEIGHT * 0.5
	pole.material_override = _glow(Color(0.85, 0.9, 0.95), 1.0, 0.3)
	root.add_child(pole)
	var banner := Node3D.new()
	banner.name = "Banner"
	banner.position.y = POLE_HEIGHT - 0.4
	root.add_child(banner)
	var cloth := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.55, 0.04)
	cloth.mesh = box
	cloth.position.x = 0.47
	cloth.material_override = _glow(color, 1.0, 1.6)
	banner.add_child(cloth)
	# A light where effect lights are on, as for pickups; phones rely on the
	# emissive banner and glow. A moving omni pulls the map's big merged
	# meshes into another lighting pass and compiles their omni-lit
	# pipelines mid-match (m4.md).
	if Settings.video("lights") == true:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.2
		light.omni_range = 4.0
		light.position.y = 1.4
		root.add_child(light)
	RenderLayers.mark_dynamic(root)
	return root


func _glow(color: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if energy > 1.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return m

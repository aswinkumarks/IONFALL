class_name PickupVisuals
extends Node3D
## Pickups on the floor (PLAN §2.3): each weapon item turns and bobs over a
## glowing ring (orange for power weapons, cyan otherwise, green for
## grenades); an empty spot shows its respawn countdown. Presentation only:
## fed from SimWorld.items (host) or snapshot item dictionaries (client).

const POWER_COLOR := Color(1.0, 0.6, 0.25)
const WEAPON_COLOR := Color(0.35, 0.9, 1.0)
const GRENADE_COLOR := Color(0.45, 1.0, 0.55)

var spots: Array = []  ## the map's pickup spots (SimWorld.pickup_spots)
var _items: Dictionary = {}  ## item id -> Node3D
var _labels: Array[Label3D] = []
var _time: float = 0.0


func _process(delta: float) -> void:
	_time += delta
	for node: Node3D in _items.values():
		var model: Node3D = node.get_child(0)
		model.rotation.y = _time * 1.6
		model.position.y = 0.75 + sin(_time * 2.4 + node.get_index()) * 0.08


## `items`: SimWorld.Item objects or {id, weapon, position} dictionaries;
## `spot_ticks`: ticks until each spot respawns (0 = present).
func sync(items: Array, spot_ticks: PackedInt32Array) -> void:
	var alive := {}
	for it in items:
		var id: int = it.id if it is Dictionary else (it as SimWorld.Item).id
		var weapon: int = it.weapon if it is Dictionary else (it as SimWorld.Item).weapon
		var pos: Vector3 = it.position if it is Dictionary else (it as SimWorld.Item).position
		alive[id] = true
		if not _items.has(id):
			_items[id] = _make(weapon)
		(_items[id] as Node3D).position = pos
	for id in _items.keys():
		if not alive.has(id):
			(_items[id] as Node3D).queue_free()
			_items.erase(id)
	while _labels.size() < spots.size():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 56
		label.outline_size = 10
		label.modulate = Color(1, 1, 1, 0.85)
		label.no_depth_test = false
		add_child(label)
		_labels.append(label)
	for i in spots.size():
		var ticks: int = spot_ticks[i] if i < spot_ticks.size() else 0
		var label := _labels[i]
		label.visible = ticks > 0 and spots[i].weapon != &"grenade"
		if label.visible:
			var secs := ceili(ticks / float(Sim.TICK_RATE))
			label.text = "%d:%02d" % [floori(secs / 60.0), secs % 60]
			label.position = (spots[i].position as Vector3) + Vector3(0, 1.1, 0)


## The middle of `node`'s meshes in its parent's space.
## The glow colour of a pickup of weapon `id` (&"grenade" for grenades).
static func color_of(id: StringName) -> Color:
	var data := Weapons.by_id(id) if id != &"grenade" else null
	return GRENADE_COLOR if data == null else (POWER_COLOR if data.is_power_weapon else WEAPON_COLOR)


static func _center(node: Node3D) -> Vector3:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var xf := node.transform
		var n: Node = mi
		var chain := Transform3D.IDENTITY
		while n != node:
			chain = (n as Node3D).transform * chain
			n = n.get_parent()
		var b := (xf * chain) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.get_center() - node.position


func _make(weapon: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var data := Weapons.at(weapon)
	var model: Node3D
	if data == null:
		model = WeaponModels.grenade(0.32)
	else:
		model = WeaponModels.instantiate(data.id)
		model.scale = Vector3.ONE * 1.6
	# Spin about the model's middle: a pivot with the model centred under it.
	var pivot := Node3D.new()
	root.add_child(pivot)
	pivot.add_child(model)
	model.position = -_center(model)
	var color := GRENADE_COLOR if data == null else (POWER_COLOR if data.is_power_weapon else WEAPON_COLOR)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1, 0.3, 1)
	ring.position.y = 0.04
	root.add_child(ring)
	# A small light where effect lights are on; phones rely on the emissive
	# ring and glow.
	if Settings.video("lights") == true:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 0.8
		light.omni_range = 2.2
		light.position.y = 0.6
		root.add_child(light)
	RenderLayers.mark_dynamic(root)
	return root

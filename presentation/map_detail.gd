class_name MapDetail
extends RefCounted
## A map's look by quality (Settings preset "detail", as the characters'
## MeshyRig.TIERS), applied when the map loads and when the quality changes:
## - high: the maps' full materials (normal, occlusion and roughness maps);
## - medium: the same without the occlusion map;
## - low: the clean stylized look: colour and lightmap only, no normal,
##   occlusion or roughness maps (one texture fetch per pixel).
## And each map's exposure (Maps.LIST "exposure"): the kit interiors
## (Spire, Foundry) read too dark at 1.0, Station too bright; and the
## reflection probe's strength by renderer.
## Nothing runs per frame: low and medium are material copies made once
## per material and set as surface overrides.

const PANEL_ALBEDO := "res://art/textures/station_panel_albedo.png"
const PANEL_NORMAL := "res://art/textures/station_panel_normal.png"
const PANEL_ORM := "res://art/textures/station_panel_orm.png"
## The reflection probe's strength under Forward+ (the desktop renderer
## option): its reflections are far stronger than the Mobile renderer's, and
## at full strength the light strips tint every metal surface cyan.
const FORWARD_PLUS_PROBE := 0.35


## Applies the quality tier `detail` (MeshyRig.TIERS) and map `map_id`'s
## exposure to a loaded presentation `root`.
static func apply(root: Node, map_id: String, detail: String) -> void:
	# Loaded, not named: tools run without Maps' autoloads.
	var maps: Dictionary = (load("res://maps/maps.gd") as GDScript).get("LIST")
	var exposure := float((maps.get(map_id, {}) as Dictionary).get("exposure", 1.0))
	for we in root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (we as WorldEnvironment).environment
		if env != null:
			env.tonemap_exposure = exposure
	var forward_plus := RenderingServer.get_current_rendering_method() == "forward_plus"
	for probe: ReflectionProbe in root.find_children("*", "ReflectionProbe", true, false):
		probe.intensity = FORWARD_PLUS_PROBE if forward_plus else 1.0
	var copies := {}  ## source material -> its copy for this tier
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i) as BaseMaterial3D
			if m == null or detail == "high" or not _has_maps(m):
				mi.set_surface_override_material(i, null)
				continue
			if not copies.has(m):
				copies[m] = simplified(m, detail)
			mi.set_surface_override_material(i, copies[m])


## `m` for tier `detail`: medium without the occlusion map, low without
## normal, occlusion and roughness maps.
static func simplified(m: BaseMaterial3D, detail: String) -> BaseMaterial3D:
	var out := m.duplicate() as BaseMaterial3D
	out.ao_enabled = false
	out.ao_texture = null
	if detail == "low":
		out.normal_enabled = false
		out.normal_texture = null
		if out.roughness_texture != null:
			out.roughness_texture = null
			out.roughness = clampf(m.roughness * 0.6, 0.0, 1.0)  # the maps' average
		out.metallic_texture = null
		if out is ORMMaterial3D:
			(out as ORMMaterial3D).orm_texture = null
	return out


static func _has_maps(m: BaseMaterial3D) -> bool:
	return m.normal_enabled or m.ao_enabled or m.roughness_texture != null or m.metallic_texture != null


## Station's hull plating (tools/gen_station_panels.py) on a panel material
## `m` (tools/build_map.gd): colour, normal map, and occlusion and
## roughness from one map (R and G).
static func station_panels(m: StandardMaterial3D) -> void:
	m.albedo_texture = load(PANEL_ALBEDO)
	m.normal_enabled = true
	m.normal_texture = load(PANEL_NORMAL)
	m.normal_scale = 0.8
	var orm: Texture2D = load(PANEL_ORM)
	m.roughness_texture = orm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.roughness = clampf(m.roughness / 0.55, 0.0, 1.0)  # the map averages ~0.55
	m.ao_enabled = true
	m.ao_texture = orm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.ao_light_affect = 0.25

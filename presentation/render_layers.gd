class_name RenderLayers
extends RefCounted
## Render layers (VisualInstance3D.layers). Map geometry stays on the
## default layer; things that move (characters, weapons, first-person arms,
## pickups, flags) go on DYNAMIC, which the map's baked accent lights can
## leave out (where effect lights are off: phones). Those lights are already
## in the lightmap and its probes, and the probes light moving objects too;
## lighting them again in real time costs a per-pixel omni pass on
## characters and the screen-filling first-person arms, and compiles
## omni-lit pipelines mid-match (m4.md). Desktops keep it: the extra direct
## light gives characters their coloured rim light in lit corridors.

const DYNAMIC := 1 << 1


## Puts `root` and every visual under it on DYNAMIC (call after building it).
static func mark_dynamic(root: Node) -> void:
	if root is VisualInstance3D:
		(root as VisualInstance3D).layers = DYNAMIC
	for n in root.find_children("*", "VisualInstance3D", true, false):
		(n as VisualInstance3D).layers = DYNAMIC


## Whether the map's baked (BAKE_STATIC) lights also light DYNAMIC visuals
## in real time: only where effect lights are on (Settings "lights").
static func light_dynamic_with_baked_lights(map_root: Node, on: bool) -> void:
	for n in map_root.find_children("*", "Light3D", true, false):
		var light := n as Light3D
		if light.light_bake_mode == Light3D.BAKE_STATIC:
			light.light_cull_mask = (light.light_cull_mask | DYNAMIC) if on else (light.light_cull_mask & ~DYNAMIC)

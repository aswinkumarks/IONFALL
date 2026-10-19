@tool
extends EditorPlugin
## When the IONFALL_BAKE environment variable names a scene, open it, bake
## its LightmapGI with the editor's own "Bake Lightmaps" action, save and
## quit. LightmapGI has no scripting API for baking, so this presses the
## editor button. Does nothing in normal editor sessions.

var _scene: String = ""


func _enter_tree() -> void:
	_scene = OS.get_environment("IONFALL_BAKE")
	if _scene.is_empty():
		return
	_bake.call_deferred()


func _bake() -> void:
	await get_tree().create_timer(2.0).timeout
	EditorInterface.open_scene_from_path(_scene)
	await get_tree().create_timer(1.0).timeout
	var root := EditorInterface.get_edited_scene_root()
	var lightmaps := root.find_children("*", "LightmapGI", true, false)
	if lightmaps.is_empty():
		_finish("no LightmapGI in %s" % _scene, 1)
		return
	EditorInterface.edit_node(lightmaps[0])
	await get_tree().create_timer(1.0).timeout
	var button := _find_button(EditorInterface.get_base_control(), "Bake Lightmaps")
	if button == null:
		_finish("Bake Lightmaps button not found", 1)
		return
	var lm: LightmapGI = lightmaps[0]
	# A rebake updates the existing data in place: watch its file instead.
	var data_path := _scene.get_basename() + ".lmbake"
	var before := FileAccess.get_modified_time(data_path) if FileAccess.file_exists(data_path) else 0
	button.pressed.emit()
	var waited := 0.0
	while FileAccess.get_modified_time(data_path) == before and waited < 900.0:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	if FileAccess.get_modified_time(data_path) == before:
		_finish("bake timed out", 1)
		return
	EditorInterface.save_scene()
	await get_tree().create_timer(1.0).timeout
	_finish("baked %s in %.0f s" % [_scene, waited], 0)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).text == text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _finish(message: String, code: int) -> void:
	print("BAKE: " + message)
	get_tree().quit(code)

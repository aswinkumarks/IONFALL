extends GutTest
## Touch layout editor (PLAN §3.11): per-button position and size overrides
## and a shared opacity, saved to settings.

var _saved_layout: Variant
var _saved_opacity: Variant


func before_each() -> void:
	_saved_layout = Settings.get_value("input", "touch_layout")
	_saved_opacity = Settings.get_value("input", "touch_opacity")


func after_each() -> void:
	Settings.set_value("input", "touch_layout", _saved_layout)
	Settings.set_value("input", "touch_opacity", _saved_opacity)
	Settings.save_settings()


func test_layout_overrides_and_clamps() -> void:
	var tc := TouchControls.new()
	add_child_autofree(tc)
	tc.apply_layout({"v": TouchControls.LAYOUT_VERSION, "fire": [0.5, 0.5, 1.5], "jump": [2.0, -1.0, 9.0]})
	var l := tc.layout()
	assert_eq(l.fire, [0.5, 0.5, 1.5])
	assert_almost_eq(l.jump[0], 1.7, 0.001, "kept on screen")
	assert_almost_eq(l.jump[1], 0.04, 0.001, "kept on screen")
	assert_almost_eq(l.jump[2], TouchControls.MAX_SCALE, 0.001, "size clamped")
	assert_eq(l.scope[0], TouchControls.DEFAULT_BUTTONS[3].pos.x, "others keep their defaults")
	tc.apply_layout({})
	assert_eq(tc.layout().fire[2], 1.0, "reset")


func test_old_layouts_are_replaced_by_the_cluster() -> void:
	var tc := TouchControls.new()
	add_child_autofree(tc)
	tc.apply_layout({"fire": [0.86, 0.62, 1.2]})  # version 1: screen fractions
	assert_eq(tc.layout().fire, [TouchControls.DEFAULT_BUTTONS[0].pos.x, TouchControls.DEFAULT_BUTTONS[0].pos.y, 1.0])


func test_v2_layouts_with_removed_buttons_are_replaced() -> void:
	var tc := TouchControls.new()
	add_child_autofree(tc)
	tc.apply_layout({"v": 2, "fire": [0.5, 0.5, 1.2], "reload": [0.47, 0.22, 1.0]})
	var l := tc.layout()
	assert_eq(l.fire, [TouchControls.DEFAULT_BUTTONS[0].pos.x, TouchControls.DEFAULT_BUTTONS[0].pos.y, 1.0])
	assert_false(l.has("reload"), "Reload is now a tap on the ammo counter")


func test_scope_button_toggles_aim() -> void:
	var tc := TouchControls.new()
	tc.input = InputAdapter.new()
	add_child_autofree(tc.input)
	add_child_autofree(tc)
	tc.scope_on = true
	assert_true(tc.input.aim_held())
	tc.release_all()
	assert_false(tc.input.aim_held(), "pausing or dying drops the scope")


func test_cluster_buttons_dont_overlap() -> void:
	var b := TouchControls.DEFAULT_BUTTONS
	for i in b.size():
		for j in range(i + 1, b.size()):
			var gap: float = (b[i].pos as Vector2).distance_to(b[j].pos) - b[i].radius - b[j].radius
			assert_gt(gap, 0.02, "%s and %s apart" % [b[i].id, b[j].id])


func test_editor_saves() -> void:
	var editor := TouchLayoutEditor.new()
	add_child_autofree(editor)
	editor.open()
	editor._controls.set_scale_of("scope", 1.4)
	editor._opacity_slider.value = 0.5
	editor._done()
	var saved: Dictionary = Settings.get_value("input", "touch_layout")
	assert_almost_eq(saved.scope[2], 1.4, 0.001)
	assert_almost_eq(float(Settings.get_value("input", "touch_opacity")), 0.5, 0.001)


func test_editor_covers_the_screen_inside_an_offset_page() -> void:
	# The settings page has margins; the editor must still lay buttons out in
	# screen space, exactly where a match draws them.
	var page := Control.new()
	page.position = Vector2(72, 32)
	add_child_autofree(page)
	var editor := TouchLayoutEditor.new()
	page.add_child(editor)
	await wait_process_frames(2)
	assert_eq(editor.get_global_rect().position, Vector2.ZERO)
	assert_eq(editor.get_global_rect().size, editor.get_viewport_rect().size)

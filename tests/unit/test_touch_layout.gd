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
	tc.apply_layout({"fire": [0.5, 0.5, 1.5], "jump": [2.0, -1.0, 9.0]})
	var l := tc.layout()
	assert_eq(l.fire, [0.5, 0.5, 1.5])
	assert_almost_eq(l.jump[0], 0.97, 0.001, "kept on screen")
	assert_almost_eq(l.jump[2], TouchControls.MAX_SCALE, 0.001, "size clamped")
	assert_eq(l.reload[0], TouchControls.DEFAULT_BUTTONS[3].pos.x, "others keep their defaults")
	tc.apply_layout({})
	assert_eq(tc.layout().fire[2], 1.0, "reset")


func test_editor_saves() -> void:
	var editor := TouchLayoutEditor.new()
	add_child_autofree(editor)
	editor.open()
	editor._controls.set_scale_of("reload", 1.4)
	editor._opacity_slider.value = 0.5
	editor._done()
	var saved: Dictionary = Settings.get_value("input", "touch_layout")
	assert_almost_eq(saved.reload[2], 1.4, 0.001)
	assert_almost_eq(float(Settings.get_value("input", "touch_opacity")), 0.5, 0.001)

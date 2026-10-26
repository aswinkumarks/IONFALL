extends GutTest
## Display mode and resolution settings.


func test_parse_resolution() -> void:
	assert_eq(Settings.parse_resolution("1920x1080"), Vector2i(1920, 1080))
	assert_eq(Settings.parse_resolution("native"), Vector2i.ZERO)
	assert_eq(Settings.parse_resolution("12x"), Vector2i.ZERO)
	assert_eq(Settings.parse_resolution(""), Vector2i.ZERO)


func test_resolution_options_start_with_native_and_fit_the_screen() -> void:
	var options := Settings.resolution_options()
	assert_eq(options[0], "native")
	var screen := DisplayServer.screen_get_size()
	for o in options.slice(1):
		var r := Settings.parse_resolution(o)
		if o == Settings.get_value("video", "resolution"):
			continue  # the saved value is always listed
		assert_true(r.x <= screen.x and r.y <= screen.y, "%s fits %s" % [o, screen])


func test_defaults() -> void:
	assert_eq(Settings.DEFAULTS.video.display_mode, "windowed")
	assert_eq(Settings.DEFAULTS.video.resolution, "native")


func test_quality_preset_writes_its_values_and_manual_change_goes_custom() -> void:
	var before := {}
	for k in ["quality", "render_scale", "shadows"]:
		before[k] = Settings.get_value("video", k)
	Settings.set_value("video", "quality", "low")
	assert_eq(Settings.get_value("video", "render_scale"), Settings.QUALITY.low.render_scale)
	assert_false(Settings.get_value("video", "shadows"))
	assert_eq(Settings.quality_preset().msaa, 0)
	Settings.set_value("video", "render_scale", 0.9)
	assert_eq(Settings.get_value("video", "quality"), "custom", "hand-tuned values make it custom")
	Settings.set_value("video", "quality", "ultra")
	assert_eq(Settings.get_value("video", "render_scale"), 1.0)
	assert_eq(Settings.quality_preset().msaa, 2)
	for k in before:
		Settings.set_value("video", k, before[k])


func test_platform_default_quality() -> void:
	assert_true(Settings.QUALITY.has(Settings.default_quality()))


## Phones leave the reflection probe off on Medium (~0.9 ms of GPU on the
## Mi 11X, m4.md); desktops keep it, and other presets are unchanged.
func test_phone_medium_has_no_reflection_probe() -> void:
	assert_false(Settings.preset_for("medium", true).probe)
	assert_true(Settings.preset_for("medium", false).probe)
	assert_true(Settings.QUALITY.medium.probe, "the shared preset isn't changed")
	assert_eq(Settings.preset_for("high", true), Settings.QUALITY.high)
	assert_eq(Settings.preset_for("medium", true).render_scale, Settings.QUALITY.medium.render_scale)


## Menus cap the frame rate only on phones; a match restores the setting.
func test_menu_mode_restores_the_fps_cap() -> void:
	Settings.set_menu_mode(true)
	var in_menu := Engine.max_fps
	Settings.set_menu_mode(false)
	assert_eq(Engine.max_fps, int(Settings.get_value("video", "fps_cap")))
	if Platform.is_mobile():
		assert_lte(in_menu, Settings.MENU_FPS)
	else:
		assert_eq(in_menu, Engine.max_fps, "desktops keep their cap in menus")

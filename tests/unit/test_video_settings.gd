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

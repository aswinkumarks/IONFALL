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

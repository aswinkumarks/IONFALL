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


## Phones' Medium has 2x MSAA (resolved in tile memory); desktops' Medium
## upscales with FSR and has none.
func test_phone_medium_has_msaa_2x() -> void:
	assert_eq(Settings.anti_aliasing_for("auto", Settings.preset_for("medium", true)), Vector2i(1, 0))
	assert_eq(Settings.anti_aliasing_for("auto", Settings.preset_for("medium", false)), Vector2i(0, 0))


## The governor's MSAA step-down reaches the window on "auto".
func test_adaptive_msaa_step_down_applies() -> void:
	var saved: Array = [Settings.get_value("video", "quality"), Settings.get_value("video", "anti_aliasing")]
	Settings.set_value("video", "quality", "high")
	Settings.set_value("video", "anti_aliasing", "auto")
	assert_eq(get_tree().root.msaa_3d, Viewport.MSAA_2X)
	Settings.set_adaptive("msaa", 0)
	assert_eq(get_tree().root.msaa_3d, Viewport.MSAA_DISABLED)
	Settings.set_value("video", "quality", saved[0])
	Settings.set_value("video", "anti_aliasing", saved[1])
	assert_true(Settings.adaptive.is_empty())


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


## The anti-aliasing setting: "auto" follows the preset, the rest override it.
func test_anti_aliasing_choices() -> void:
	assert_eq(Settings.anti_aliasing_for("auto", Settings.QUALITY.high), Vector2i(1, 0), "High: MSAA 2x")
	assert_eq(Settings.anti_aliasing_for("auto", Settings.QUALITY.medium), Vector2i(0, 0), "Medium: none")
	assert_eq(Settings.anti_aliasing_for("off", Settings.QUALITY.ultra), Vector2i(0, 0))
	assert_eq(Settings.anti_aliasing_for("fxaa", Settings.QUALITY.medium), Vector2i(0, 1))
	assert_eq(Settings.anti_aliasing_for("msaa_2x", Settings.QUALITY.low), Vector2i(1, 0))
	assert_eq(Settings.anti_aliasing_for("msaa_4x", Settings.QUALITY.low), Vector2i(2, 0))
	var before: Variant = Settings.get_value("video", "anti_aliasing")
	Settings.set_value("video", "anti_aliasing", "msaa_2x")
	assert_eq(get_tree().root.msaa_3d, Viewport.MSAA_2X, "applied to the window")
	assert_eq(get_tree().root.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	Settings.set_value("video", "anti_aliasing", before)


## AaBench switches the viewport's mode without saving the setting.
func test_aa_bench_switches_modes() -> void:
	var vp := SubViewport.new()
	add_child_autofree(vp)
	AaBench.apply(vp, "fxaa")
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_FXAA)
	assert_eq(vp.msaa_3d, Viewport.MSAA_DISABLED)
	AaBench.apply(vp, "msaa_4x")
	assert_eq(vp.msaa_3d, Viewport.MSAA_4X)
	assert_eq(vp.screen_space_aa, Viewport.SCREEN_SPACE_AA_DISABLED)

extends GutTest
## Adaptive quality (PLAN §3.10): sustained slow frames or thermal pressure
## step video settings down one at a time, for the session only.

var _saved: Dictionary = {}


func before_each() -> void:
	for k in ["quality", "render_scale", "effects", "glow", "shadows", "anti_aliasing"]:
		_saved[k] = Settings.get_value("video", k)
	Settings.set_value("video", "quality", "high")
	Settings.set_value("video", "anti_aliasing", "off")


func after_each() -> void:
	for k in _saved:
		Settings.set_value("video", k, _saved[k])
	Settings.adaptive.clear()


func _feed(aq: AdaptiveQuality, seconds: float, frame_ms: float) -> Array[String]:
	var steps: Array[String] = []
	for i in roundi(seconds * 1000.0 / frame_ms):
		var s := aq.add_frame(frame_ms / 1000.0, 60)
		if not s.is_empty():
			steps.append(s)
	return steps


func test_steady_frames_change_nothing() -> void:
	var aq := AdaptiveQuality.new()
	aq.thermal = func() -> Vector2: return Vector2(0, 0.4)
	assert_eq(_feed(aq, 60.0, 16.7).size(), 0)
	assert_true(Settings.adaptive.is_empty())


func test_sustained_slow_frames_step_down_render_scale_first() -> void:
	var aq := AdaptiveQuality.new()
	aq.thermal = func() -> Vector2: return Vector2(0, NAN)
	var steps := _feed(aq, 25.0, 25.0)
	assert_eq(steps.size(), 0, "a short slow spell is not enough")
	steps = _feed(aq, 10.0, 25.0)
	assert_eq(steps.size(), 1, "30 s of slow frames: one step")
	assert_almost_eq(float(Settings.video("render_scale")), 0.9, 0.001)
	assert_almost_eq(float(Settings.get_value("video", "render_scale")), 1.0, 0.001, "the saved setting is untouched")


func test_heat_steps_down_without_slow_frames_then_order() -> void:
	var aq := AdaptiveQuality.new()
	aq.thermal = func() -> Vector2: return Vector2(3, 0.5)
	_feed(aq, 400.0, 16.7)
	assert_almost_eq(float(Settings.video("render_scale")), AdaptiveQuality.MIN_SCALE, 0.001)
	assert_almost_eq(float(Settings.video("effects")), AdaptiveQuality.LOW_EFFECTS, 0.001)
	assert_true(Settings.video("glow"), "glow is never touched")
	assert_false(Settings.video("shadows"))
	assert_eq(AdaptiveQuality.step_down(), "", "nothing left to lower")


## On "auto", MSAA goes first (phones' Medium has 2x; it is the cheapest
## thing to give up); a chosen anti-aliasing mode is left alone.
func test_msaa_steps_down_first_on_auto() -> void:
	Settings.set_value("video", "anti_aliasing", "auto")
	assert_eq(AdaptiveQuality.step_down(), "msaa=0")
	assert_eq(int(Settings.video("msaa")), 0)
	assert_eq(AdaptiveQuality.step_down(), "render_scale=0.9")
	Settings.set_value("video", "anti_aliasing", "msaa_2x")
	assert_eq(AdaptiveQuality.step_down(), "render_scale=0.9", "the player's choice stays")


func test_headroom_near_throttling_counts_as_hot() -> void:
	var aq := AdaptiveQuality.new()
	aq.thermal = func() -> Vector2: return Vector2(1, 0.97)
	assert_eq(_feed(aq, 10.5, 16.7).size(), 1)


func test_changing_a_video_setting_clears_step_downs() -> void:
	AdaptiveQuality.step_down()
	assert_false(Settings.adaptive.is_empty())
	Settings.set_value("video", "fps_cap", Settings.get_value("video", "fps_cap"))
	assert_true(Settings.adaptive.is_empty())

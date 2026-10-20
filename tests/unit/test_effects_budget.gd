extends GutTest
## Effects stay within the particle budget (PLAN §3.10: ≤ 2,000 live) and
## scale with the effects density setting.

var _saved: Variant


func before_each() -> void:
	_saved = Settings.get_value("video", "effects")


func after_each() -> void:
	Settings.set_value("video", "effects", _saved)


func test_density_scales_and_particles_are_released() -> void:
	var fx := Effects.new()
	add_child_autofree(fx)
	Settings.set_value("video", "effects", 1.0)
	fx.impact(Vector3.ZERO, true)
	var full := fx.live_particles
	assert_gt(full, 0)
	Settings.set_value("video", "effects", 0.5)
	fx.impact(Vector3.ZERO, true)
	assert_eq(fx.live_particles - full, roundi(full * 0.5))
	for i in 3:
		fx._process(1.0)
	assert_eq(fx.live_particles, 0, "expired bursts give their particles back")


func test_budget_caps_live_particles() -> void:
	var fx := Effects.new()
	add_child_autofree(fx)
	Settings.set_value("video", "effects", 1.0)
	for i in 200:
		fx.explosion(Vector3.ZERO, 4.0)
	assert_lte(fx.live_particles, Effects.MAX_PARTICLES)


func test_warm_up_covers_every_kind() -> void:
	var fx := Effects.new()
	add_child_autofree(fx)
	fx.warm_up(Vector3(0, 0, -4))
	assert_gt(fx.get_child_count(), 15)

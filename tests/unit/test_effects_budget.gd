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


func test_effect_nodes_are_reused() -> void:
	var fx := Effects.new()
	add_child_autofree(fx)
	Settings.set_value("video", "effects", 1.0)
	fx.impact(Vector3.ZERO, true)
	fx.tracer(Vector3.ZERO, Vector3(0, 0, -10))
	for i in 3:
		fx._process(1.0)
	var nodes := fx.get_child_count()
	for i in 5:
		fx.impact(Vector3.ZERO, true)
		fx.tracer(Vector3.ZERO, Vector3(0, 0, -10))
		for j in 3:
			fx._process(1.0)
	assert_eq(fx.get_child_count(), nodes, "finished effects go back to their pools")


func test_cosmetic_effects_are_capped_by_density() -> void:
	var fx := Effects.new()
	add_child_autofree(fx)
	Settings.set_value("video", "effects", 0.4)
	for i in 100:
		fx.impact(Vector3.ZERO)
		fx.muzzle_flash(Vector3.ZERO)
	var cap := roundi(Effects.MAX_EFFECT_NODES * 0.4)
	assert_lte(fx._fading.size(), cap + 1, "an effect may add its last node past the cap")
	fx.explosion(Vector3.ZERO, 4.0)
	assert_gt(fx._fading.size(), cap + 1, "explosions always show")


func test_warm_up_ignores_the_cap() -> void:
	var fx := Effects.new()
	add_child_autofree(fx)
	Settings.set_value("video", "effects", 0.0)
	fx.warm_up(Vector3(0, 0, -4))
	assert_gt(fx.get_child_count(), 15)


func test_tracers_keep_the_bolt_and_stop_at_twice_the_cap() -> void:
	var fx := Effects.new()
	add_child_autofree(fx)
	Settings.set_value("video", "effects", 0.4)
	var cap := roundi(Effects.MAX_EFFECT_NODES * 0.4)
	for i in 200:
		fx.tracer(Vector3.ZERO, Vector3(0, 0, -40))
	assert_lte(fx._fading.size(), cap * 2 + 1)
	fx.explosion(Vector3.ZERO, 4.0)
	assert_gt(fx._fading.size(), cap * 2 + 1, "explosions always show")

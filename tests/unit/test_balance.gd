extends GutTest
## Generates time-to-kill from the WeaponData resources and checks it against
## the PLAN §2.3 balance table (the resources are the source of truth; this
## catches accidental changes).


## Tick at which the n-th shot (0-based) fires, given the weapon's timing.
func _shot_tick(w: WeaponData, n: int) -> int:
	if w.fire_mode == WeaponData.FireMode.BURST:
		@warning_ignore("integer_division")
		var burst := n / w.burst_count
		return burst * w.ticks_between_shots + (n % w.burst_count) * w.burst_spacing_ticks
	return n * w.ticks_between_shots


## Returns the tick of the killing shot. `optimal` = body until the shield
## breaks, then headshots.
func _ttk(w: WeaponData, optimal: bool) -> int:
	var s := PlayerSimState.new()
	for n in 1000:
		var head := optimal and s.shield <= 0.0
		if optimal and w.precision:
			head = true
		if Health.apply(s, w.damage, head, w.headshot_multiplier, w.precision).killed:
			return _shot_tick(w, n)
	return -1


func test_pulse_rifle() -> void:
	var w: WeaponData = load("res://data/weapons/pulse_rifle.tres")
	assert_eq(_ttk(w, false), 66, "12 body shots = 1.10 s")
	assert_eq(_ttk(w, true), 54, "6 body + 4 head = 0.90 s")


func test_burst_rifle() -> void:
	var w: WeaponData = load("res://data/weapons/burst_rifle.tres")
	assert_eq(_ttk(w, false), 66, "4 bursts = 1.10 s")
	assert_eq(_ttk(w, true), 46, "2 body bursts + 3 head rounds = 0.77 s")


func test_mag_pistol() -> void:
	var w: WeaponData = load("res://data/weapons/mag_pistol.tres")
	assert_eq(_ttk(w, false), 84, "8 shots = 1.40 s")
	assert_eq(_ttk(w, true), 60, "4 body + 2 head = 1.00 s")


func test_rail_sniper() -> void:
	var w: WeaponData = load("res://data/weapons/rail_sniper.tres")
	assert_eq(_ttk(w, false), 72, "2 body shots = 1.20 s")
	assert_eq(_ttk(w, true), 0, "1 headshot through shield")


func test_arc_launcher_direct_hit_kills() -> void:
	var w: WeaponData = load("res://data/weapons/arc_launcher.tres")
	var s := PlayerSimState.new()
	assert_true(Health.apply(s, w.direct_damage, false, 1.0, false).killed)


func test_scatter_gun() -> void:
	var w: WeaponData = load("res://data/weapons/scatter_gun.tres")
	assert_eq(w.pellets * w.damage, 120.0, "10 pellets × 12 point blank")
	assert_almost_eq(w.damage_at(15.0), 12.0 * 0.3, 0.001, "falls off to 30% at 15 m")
	var s := PlayerSimState.new()
	assert_false(Health.apply(s, w.pellets * w.damage, false, 1.0, false).killed)
	assert_true(Health.apply(s, w.pellets * w.damage, false, 1.0, false).killed, "2 point-blank shots = 0.80 s")
	assert_eq(w.ticks_between_shots, 48)


func test_flux_smg() -> void:
	var w: WeaponData = load("res://data/weapons/flux_smg.tres")
	assert_eq(_ttk(w, false), 60, "16 body shots = 1.00 s up close")
	assert_eq(_ttk(w, true), 48, "8 body + 5 head = 0.80 s")
	assert_almost_eq(w.damage_at(12.0), 13.0, 0.01, "full damage to 12 m")
	assert_almost_eq(w.damage_at(30.0), 13.0 * 0.45, 0.01, "45% from 30 m: a close-range gun")
	assert_true(Loadouts.PRIMARIES.has(w), "a loadout primary")
	assert_true(WeaponModels.has(w.id), "has a model")
	assert_eq(Weapons.index_of(w.id), Weapons.SMG, "appended to the wire order")

extends GutTest
## Bots playing each other (PLAN §2.7), stepped synchronously for simulated
## minutes: they must find each other, fight, use traversal and rarely need
## stuck recovery. Also the 16-bot server load figure (PLAN §5).

var world: SimWorld
var nav: BotNavigation
var brains: Dictionary = {}


func before_each() -> void:
	var arena := SimHarness.make_arena()
	add_child_autofree(arena)
	await wait_physics_frames(2)
	nav = BotNavigation.new()
	add_child_autofree(nav)
	await nav.build(arena)
	world = SimHarness.make_world(5)
	world.lag_compensation = true
	add_child_autofree(world)
	brains = {}


func _add_bots(n: int) -> void:
	for i in n:
		var id := 1000 + i
		world.add_player(id, Loadouts.ffa(), "Bot %d" % i, true)
		brains[id] = BotBrain.new(world, nav, id, 77 + i)


func _run(ticks: int) -> Dictionary:
	var out := {"deaths": 0, "kills": 0, "shots": 0, "hits": 0, "max_height": 0.0, "step_ms": FrameStats.new(ticks),
			"grenades": 0, "melee": 0}
	for t in ticks:
		var commands := {}
		var t0 := Time.get_ticks_usec()
		for id in brains:
			commands[id] = brains[id].command_for(world.tick, world.get_player(id))
		world.step(commands)
		out.step_ms.add((Time.get_ticks_usec() - t0) / 1000.0)
		for e in world.drain_events():
			match e.type:
				"death":
					out.deaths += 1
					out.kills += 0 if e.suicide else 1
				"fire":
					out.shots += 1
					out.grenades += 1 if e.weapon == &"frag_grenade" else 0
					out.melee += 1 if e.weapon == &"melee" else 0
				"hit":
					out.hits += 1
					if brains.has(e.target):
						brains[e.target].on_event(e)
		for id in brains:
			out.max_height = maxf(out.max_height, world.get_player(id).state.position.y)
	return out


func test_four_bots_fight_for_two_minutes() -> void:
	_add_bots(4)
	var r := _run(7200)
	var teleports := 0
	for b: BotBrain in brains.values():
		teleports += b.stuck_teleports
	gut.p("2 min, 4 bots: kills %d deaths %d shots %d hits %d (acc %.0f%%) grenades %d melee %d max height %.1f m, stuck teleports %d, tick p50 %.2f p99 %.2f ms" % [
			r.kills, r.deaths, r.shots, r.hits, 100.0 * r.hits / maxf(r.shots, 1), r.grenades, r.melee, r.max_height,
			teleports, r.step_ms.percentile(50.0), r.step_ms.percentile(99.0)])
	assert_gt(r.grenades, 0, "bots throw grenades")
	assert_gt(r.kills, 4, "bots find and kill each other")
	assert_gt(r.hits, 20)
	assert_lt(float(r.hits) / maxf(r.shots, 1), 0.8, "no perfect aim")
	assert_gt(r.max_height, 1.9, "bots get onto raised areas")
	# Navmesh random points draw from the global RNG, so the count varies with
	# earlier tests (0 when run alone, up to 3 seen in the full suite).
	assert_lte(teleports, 4, "stuck recovery rarely needs to teleport")


func test_bot_reaches_a_ledge_that_needs_a_mantle() -> void:
	_add_bots(1)
	var bot: SimPlayer = world.get_player(1000)
	var brain: BotBrain = brains[1000]
	SimHarness.place(bot, Vector3(-11, 0.05, 17), PI)
	brain.go_to(Vector3(-11, 2.0, 12))  # top of the 1.5 m ledge
	var reached := false
	for t in 600:
		world.step({1000: brain.command_for(world.tick, bot)})
		world.drain_events()
		if bot.state.position.y > 1.4 and Vector2(bot.state.position.x + 11, bot.state.position.z - 12).length() < 1.2:
			reached = true
			break
	assert_true(reached, "bot climbed the 1.5 m ledge (at %s)" % bot.state.position)


func test_bot_reaches_the_double_jump_ledge() -> void:
	_add_bots(1)
	var bot: SimPlayer = world.get_player(1000)
	var brain: BotBrain = brains[1000]
	SimHarness.place(bot, Vector3(-5, 0.05, 17), PI)
	brain.go_to(Vector3(-5, 3.7, 12))  # top of the 3.2 m ledge
	var reached := false
	for t in 900:
		world.step({1000: brain.command_for(world.tick, bot)})
		world.drain_events()
		if bot.state.position.y > 3.0:
			reached = true
			break
	assert_true(reached, "bot double-jumped and mantled onto 3.2 m (at %s)" % bot.state.position)


func test_sixteen_bot_server_load() -> void:
	_add_bots(16)
	var r := _run(1800)
	gut.p("16 bots, 30 s: tick p50 %.2f p99 %.2f ms, kills %d" % [r.step_ms.percentile(50.0), r.step_ms.percentile(99.0), r.kills])
	# PLAN §3.10 dedicated reference: p50 ≤ 2 ms, p99 ≤ 6 ms (release build;
	# tests run the debug build, so only a loose ceiling here).
	assert_lt(r.step_ms.percentile(50.0), 6.0)


func test_bots_fetch_power_weapons() -> void:
	world.pickups_enabled = true
	world.configure(5, SimHarness.MOVEMENT, TestArenaLayout.spawn_points(), [
		{"weapon": &"rail_sniper", "position": Vector3(4, 0, 17), "respawn_ticks": 600},
		{"weapon": &"arc_launcher", "position": Vector3(-4, 0, 17), "respawn_ticks": 600},
	])
	_add_bots(1)  # alone, so it isn't busy fighting
	var picked := 0
	for t in 1800:
		var commands := {}
		for id in brains:
			commands[id] = brains[id].command_for(world.tick, world.get_player(id))
		world.step(commands)
		for e in world.drain_events():
			if e.type == "pickup" and e.weapon in [&"rail_sniper", &"arc_launcher"]:
				picked += 1
	gut.p("power weapon pickups in 30 s: %d" % picked)
	assert_gt(picked, 0, "bots go and get power weapons")


## PLAN §2.7: higher difficulties aim better (less delay and error), and
## none aims perfectly.
func test_difficulty_changes_accuracy() -> void:
	var acc := []
	for level: int in [BotBrain.Difficulty.EASY, BotBrain.Difficulty.INSANE]:
		# A fresh world per level, so one level's leftovers (respawn timers,
		# items, projectiles) can't stall the next; run until there's a sample.
		world.queue_free()
		world = SimHarness.make_world(5)
		world.lag_compensation = true
		add_child_autofree(world)
		await wait_physics_frames(1)
		brains = {}
		for i in 2:
			var id := 2000 + level * 10 + i
			world.add_player(id, Loadouts.ffa(), "Bot %d" % i, true)
			brains[id] = BotBrain.new(world, nav, id, 31 + i, level)
		var shots := 0
		var hits := 0
		for attempt in 3:
			var r := _run(3600)
			shots += r.shots
			hits += r.hits
			if shots >= 40:
				break
		assert_gt(shots, 0, "difficulty %d bots fought (alive: %s)" % [level,
				brains.keys().map(func(id: int) -> bool: return world.get_player(id).state.alive)])
		acc.append(float(hits) / maxf(shots, 1))
		gut.p("difficulty %d: shots %d hits %d accuracy %.0f%%" % [level, shots, hits, 100.0 * acc[-1]])
	assert_gt(acc[1], acc[0], "Insane hits more often than Easy")
	assert_lt(acc[1], 0.9, "Insane still misses")


## Regression: a roaming bot that finished its path picked a new target but
## kept the finished path, so it never re-pathed and stood still for good.
## One bot per round, alone, so it roams the whole time (a fight in the
## window would legitimately keep it near one spot).
func test_roaming_bots_keep_moving() -> void:
	for round in 6:
		for id in brains.keys():
			world.remove_player(id)
		brains = {}
		var bot_id := 3000 + round
		world.add_player(bot_id, Loadouts.ffa(), "Bot %d" % round, true)
		brains[bot_id] = BotBrain.new(world, nav, bot_id, 51 + round * 7)
		# The bug froze a bot for good; a rare short snag (stuck recovery
		# gets it out) is fine, so fail on two still windows in a row.
		var last := world.get_player(bot_id).state.position
		var still := 0
		for window in 6:  # 6 × 10 s
			_run(600)
			var p := world.get_player(bot_id)
			still = still + 1 if p.state.alive and p.state.position.distance_to(last) < 1.0 else 0
			assert_lt(still, 2, "bot %d still for 20 s of roaming (at %s)" % [bot_id, p.state.position])
			last = p.state.position

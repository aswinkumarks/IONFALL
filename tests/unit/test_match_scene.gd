extends GutTest
## The match scene in all three modes (PLAN §2.4): offline, and a listen host
## with a client joining it over localhost in the same process.

const MATCH := preload("res://game/match.tscn")


func _spawn(config: MatchConfig) -> Node:
	MatchConfig.pending = config
	var m := MATCH.instantiate()
	add_child_autofree(m)
	return m


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_offline_match_runs_with_dummies() -> void:
	var m := _spawn(MatchConfig.make(MatchConfig.Mode.OFFLINE, "Solo", 3))
	await wait_seconds(1.0)
	assert_not_null(m.server)
	assert_false(m.server.networked, "offline runs without networking")
	assert_eq(m.server.world.players.size(), 4)
	assert_eq(m._visuals.size(), 3, "one visual per dummy")
	assert_gt(m.server.world.tick, 30)
	assert_eq(m.server.phase, MatchPhase.COUNTDOWN)


func test_host_and_client_see_each_other() -> void:
	var host_cfg := MatchConfig.make(MatchConfig.Mode.HOST, "Hoster", 2)
	host_cfg.port = SimHarness.free_udp_port()
	var host := _spawn(host_cfg)
	await wait_seconds(0.3)
	assert_true(host.server.networked)
	var join_cfg := MatchConfig.make(MatchConfig.Mode.JOIN, "Joiner", 0, "127.0.0.1")
	join_cfg.port = host_cfg.port
	var joiner := _spawn(join_cfg)
	await wait_until(func() -> bool: return joiner.client != null and joiner.client.is_predicting(), 5.0)
	assert_true(joiner.client.is_predicting(), "client joined and predicts")
	await wait_seconds(1.0)
	assert_eq(host.server.world.players.size(), 4, "host + client + both of the host's bots")
	assert_eq(host._visuals.size(), 3, "host sees both bots and the client")
	assert_eq(joiner._visuals.size(), 3, "client sees the host and both bots")
	var names := []
	for p in joiner.client.roster:
		names.append(p.name)
	assert_has(names, "Hoster")
	assert_has(names, "Joiner")
	assert_string_contains(joiner._net_info(), "NET client")
	assert_string_contains(host._net_info(), "clients 1")
	assert_eq(joiner.client.undecodable_snapshots, 0)


func test_leaving_a_hosted_match_asks_first() -> void:
	var cfg := MatchConfig.make(MatchConfig.Mode.HOST, "Hoster", 1)
	cfg.port = SimHarness.free_udp_port()
	var m := _spawn(cfg)
	await wait_seconds(0.3)
	m._set_paused(true)
	m._ask_leave()
	assert_true(m._confirm_panel.visible, "the confirmation opens")
	var label: Label = m._confirm_panel.find_child("Text", true, false)
	assert_eq(label.text, tr("LEAVE_CONFIRM_HOST"))
	assert_true(is_instance_valid(m) and m.is_inside_tree(), "still in the match until confirmed")

extends GutTest
## LAN discovery beacons and join links (PLAN §3.6).


func _beacon() -> Discovery.Beacon:
	var b := Discovery.Beacon.new()
	b.build = "0.0.1 (abc)"
	b.compat_prefix = BuildInfo.compat_hash.left(8)
	b.name = "Alice's game"
	b.map = "test_arena"
	b.combatants = 2
	b.max_combatants = 4
	b.flags = Discovery.FLAG_DEDICATED
	b.game_port = 47712
	return b


func test_beacon_round_trip() -> void:
	var data := Discovery.encode(_beacon())
	assert_lte(data.size(), Discovery.MAX_BEACON)
	var b := Discovery.decode(data)
	assert_not_null(b)
	assert_eq(b.name, "Alice's game")
	assert_eq(b.map, "test_arena")
	assert_eq([b.combatants, b.max_combatants, b.flags, b.game_port], [2, 4, Discovery.FLAG_DEDICATED, 47712])
	assert_true(b.compatible())


func test_bad_beacons_are_rejected() -> void:
	var good := Discovery.encode(_beacon())
	assert_null(Discovery.decode(PackedByteArray()), "empty")
	assert_null(Discovery.decode(good.slice(0, good.size() - 1)), "truncated")
	var bad_magic := good.duplicate()
	bad_magic[0] ^= 0xFF
	assert_null(Discovery.decode(bad_magic), "bad magic")
	var oversize := good.duplicate()
	oversize.resize(Discovery.MAX_BEACON + 1)
	assert_null(Discovery.decode(oversize), "oversize")
	var b := _beacon()
	b.combatants = 9
	b.max_combatants = 4
	assert_null(Discovery.decode(Discovery.encode(b)), "more combatants than slots")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 500:
		var junk := PackedByteArray()
		junk.resize(rng.randi_range(0, 80))
		for j in junk.size():
			junk[j] = rng.randi() & 0xFF
		Discovery.decode(junk)  # must not crash
	assert_true(true)


func test_other_versions_are_listed_but_not_joinable() -> void:
	var b := _beacon()
	b.compat_prefix = "ffffffff" if not BuildInfo.compat_hash.begins_with("ffffffff") else "00000000"
	assert_false(Discovery.decode(Discovery.encode(b)).compatible())


func test_browser_lists_and_expires_games() -> void:
	var browser := Discovery.Browser.new()
	add_child_autofree(browser)
	await wait_physics_frames(1)
	if not browser.listening:
		pending("UDP %d busy on this machine" % Discovery.PORT)
		return
	var udp := PacketPeerUDP.new()
	udp.set_dest_address("127.0.0.1", Discovery.PORT)
	udp.put_packet(Discovery.encode(_beacon()))
	# Real servers on the LAN may be listed too: only look at our entry.
	var key := "127.0.0.1:47712"
	await wait_until(func() -> bool: return browser.games.has(key), 2.0)
	assert_true(browser.games.has(key), "listed, keyed by the packet's source address")
	await wait_seconds(Discovery.EXPIRY_MS / 1000.0 + 0.3)
	assert_false(browser.games.has(key), "expired after 3.5 s without beacons")


func test_join_links() -> void:
	assert_eq(Platform.parse_join_link("ionfall://join?host=192.168.0.9&port=47712"), {"host": "192.168.0.9", "port": 47712})
	assert_eq(Platform.parse_join_link("ionfall://join?host=10.0.0.2"), {"host": "10.0.0.2", "port": 47710})
	assert_eq(Platform.parse_join_link("ionfall://join?host=evil.example.com"), {}, "addresses only")
	assert_eq(Platform.parse_join_link("https://example.com"), {})
	assert_eq(Platform.parse_join_link("ionfall://join?host=10.0.0.2&port=99999")["port"], 65535)

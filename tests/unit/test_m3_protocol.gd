extends GutTest
## M3 wire additions: snapshot items and spot timers, owner weapon slots and
## grenades, pickup events, the loadout message and the primary in HELLO.


func test_snapshot_items_and_owner_slots_round_trip() -> void:
	var snap := Snapshot.new()
	snap.id = 77
	snap.items = [{"id": 5, "weapon": Weapons.RAIL, "position": Vector3(1, 2, 3)}, {"id": 6, "weapon": -1, "position": Vector3(-4, 0, 2)}]
	snap.spot_ticks = PackedInt32Array([0, 1234])
	var s := PlayerSimState.new()
	s.init_weapons(Loadouts.make(2))
	s.set_slot(0, Weapons.ARC, 1, 3)
	s.grenades = 1
	s.melee_cooldown = 12
	snap.owner_state = s
	snap.owner_gen = 3
	snap.projectiles = [{"owner": 2, "gen": 1, "action": 9, "weapon": Weapons.FRAG, "position": Vector3.ONE, "velocity": Vector3.UP}]
	var back := Snapshot.decode(snap.encode({}, []), {})
	assert_not_null(back)
	assert_eq(back.items.size(), 2)
	assert_eq(back.items[0].weapon, Weapons.RAIL)
	assert_eq(back.items[1].weapon, -1, "grenade")
	assert_almost_eq((back.items[0].position as Vector3).distance_to(Vector3(1, 2, 3)), 0.0, 0.02)
	assert_eq(back.spot_ticks, PackedInt32Array([0, 1234]))
	assert_eq(back.owner_state.weapons, PackedInt32Array([Weapons.ARC, Weapons.PISTOL]))
	assert_eq(back.owner_state.grenades, 1)
	assert_eq(back.owner_state.melee_cooldown, 12)
	assert_eq(back.projectiles[0].weapon, &"frag_grenade")


func test_pickup_event_round_trip() -> void:
	var e := {"type": "pickup", "id": "p:12:3456", "player": 4, "weapon": &"rail_sniper", "position": Vector3(1, 0, 2)}
	var w := Wire.Writer.new()
	assert_true(Protocol.write_event(w, e))
	var back := Protocol.read_event(Wire.Reader.new(w.data()))
	assert_eq(back.id, e.id, "same id, so presentation de-duplicates")
	assert_eq(back.weapon, &"rail_sniper")
	assert_eq(back.player, 4)


func test_loadout_message_and_hello_primary() -> void:
	assert_eq(Protocol.decode_loadout(Protocol.encode_loadout(2)), 2)
	assert_eq(Protocol.decode_loadout(Protocol.encode_loadout(9)), -1, "out of range")
	assert_true(Protocol.Msg.LOADOUT in Protocol.CLIENT_MESSAGES)
	var hello := Protocol.decode_hello(Protocol.encode_hello("c", "b", "u", "Name", 0, 1, 2, 2))
	assert_eq(hello.primary, 2)

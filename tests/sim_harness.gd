class_name SimHarness
extends RefCounted
## Test helpers: an arena + SimWorld and a scripted command builder.

const MOVEMENT := preload("res://data/movement_config.tres")
const PULSE := preload("res://data/weapons/pulse_rifle.tres")
const ARC := preload("res://data/weapons/arc_launcher.tres")
const ARENA := preload("res://maps/test_arena/gameplay.tscn")


static func make_arena() -> Node3D:
	return ARENA.instantiate()


static func make_world(seed_value: int = 7) -> SimWorld:
	var w := SimWorld.new()
	w.configure(seed_value, MOVEMENT, TestArenaLayout.spawn_points())
	return w


static func loadout() -> Array[WeaponData]:
	var l: Array[WeaponData] = [PULSE, ARC]
	return l


## Builds commands with persistent press counters, like a real client.
const CommandScript := preload("res://game/command_script.gd")


## Places a player at `feet`, facing `yaw`, standing on the ground.
static func place(p: SimPlayer, feet: Vector3, yaw: float) -> void:
	var s := p.state.copy()
	s.position = feet
	s.velocity = Vector3.ZERO
	s.yaw = yaw
	s.move_state = PlayerSimState.Move.AIR
	s.spawn_protection_ticks = 0
	p.restore(s)


## A UDP port in [lo, hi) that is free right now (checked by binding it), not
## the LAN discovery port: random test ports used to collide now and then.
static func free_udp_port(lo: int = 43000, hi: int = 48000) -> int:
	for attempt in 50:
		var port := lo + randi() % (hi - lo)
		if port == Discovery.PORT:
			continue
		var probe := PacketPeerUDP.new()
		var ok := probe.bind(port) == OK
		probe.close()
		if ok:
			return port
	return lo

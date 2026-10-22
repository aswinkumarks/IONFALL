class_name Discovery
extends RefCounted
## LAN discovery (PLAN §3.6): hosts broadcast a small binary beacon every
## second on UDP 47701; clients list what they hear and expire entries after
## 3.5 s. Discovery is optional: every join path also works by address.

const PORT := 47701
const BEACON_VERSION := 1
const MAX_BEACON := 512
const INTERVAL_S := 1.0
const EXPIRY_MS := 3500

const FLAG_DEDICATED := 1
const FLAG_MANAGER := 2
const FLAG_PASSWORD := 4
const FLAG_LOBBY := 8  ## a pre-match lobby (LobbySession), not a running match


## Everything a server browser row needs. `address` is filled in by the
## receiver from the packet's source (the interface the beacon left from).
class Beacon:
	var build: String = ""
	var protocol: int = Protocol.VERSION
	var compat_prefix: String = ""
	var name: String = ""
	var mode: String = "ffa"
	var map: String = ""
	var combatants: int = 0
	var max_combatants: int = 0
	var flags: int = 0
	var game_port: int = Protocol.DEFAULT_PORT
	var address: String = ""
	var seen_ms: int = 0

	func key() -> String:
		return "%s:%d" % [address, game_port]

	## Same protocol and compat hash as this build: joinable.
	func compatible() -> bool:
		return protocol == Protocol.VERSION and BuildInfo.compat_hash.begins_with(compat_prefix)


static func encode(b: Beacon) -> PackedByteArray:
	return Wire.Writer.new().u32(Protocol.MAGIC).u8(BEACON_VERSION).str8(b.build.left(48)).u16(b.protocol) \
			.str8(b.compat_prefix.left(16)).str8(b.name.left(Protocol.MAX_NAME_BYTES)).str8(b.mode.left(16)) \
			.str8(b.map.left(32)).u8(b.combatants).u8(b.max_combatants).u8(b.flags).u16(b.game_port).data()


## Bounded parse; null for anything that isn't a valid beacon.
static func decode(data: PackedByteArray) -> Beacon:
	if data.size() > MAX_BEACON or data.size() < 8:
		return null
	var r := Wire.Reader.new(data)
	if r.u32() != Protocol.MAGIC or r.u8() != BEACON_VERSION:
		return null
	var b := Beacon.new()
	b.build = r.str8(48)
	b.protocol = r.u16()
	b.compat_prefix = r.str8(16)
	b.name = r.str8(Protocol.MAX_NAME_BYTES)
	b.mode = r.str8(16)
	b.map = r.str8(32)
	b.combatants = r.u8()
	b.max_combatants = r.u8()
	b.flags = r.u8()
	b.game_port = r.u16()
	if not r.ok or r.remaining() != 0 or b.game_port == 0 or b.combatants > b.max_combatants \
			or b.max_combatants > Protocol.MAX_PEERS:
		return null
	return b


## Broadcast targets: the limited broadcast plus each private IPv4
## interface's directed broadcast (covers hotspots and multi-adapter PCs).
## Godot doesn't expose netmasks, so /24 is assumed for directed broadcasts.
static func broadcast_addresses() -> PackedStringArray:
	var out := PackedStringArray(["255.255.255.255"])
	for a in IP.get_local_addresses():
		var parts := a.split(".")
		if parts.size() != 4 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		var directed := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		if not out.has(directed):
			out.append(directed)
	return out


## Private IPv4 addresses other devices on the LAN can join (PLAN §3.6).
static func lan_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.match("172.1[6-9].*") \
				or a.match("172.2?.*") or a.match("172.3[01].*"):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	# Home routers and hotspots first; 172.16-31 is often a VM/container bridge.
	var rank := func(a: String) -> int: return 0 if a.begins_with("192.168.") else 1 if a.begins_with("10.") else 2
	var sorted := Array(out)
	sorted.sort_custom(func(a: String, b: String) -> bool: return rank.call(a) < rank.call(b))
	return PackedStringArray(sorted)


## Host side: sends the beacon once per second while hosting.
class Advertiser:
	extends Node

	## func() -> Beacon with the current state.
	var beacon_source: Callable
	var _udp := PacketPeerUDP.new()
	var _timer: float = 0.0
	var sent: int = 0

	func _ready() -> void:
		_udp.set_broadcast_enabled(true)
		Platform.acquire_multicast_lock()

	func _exit_tree() -> void:
		_udp.close()
		Platform.release_multicast_lock()

	func _process(delta: float) -> void:
		_timer -= delta
		if _timer > 0.0 or not beacon_source.is_valid():
			return
		_timer = INTERVAL_S
		var data := Discovery.encode(beacon_source.call())
		for target in Discovery.broadcast_addresses():
			_udp.set_dest_address(target, PORT)
			if _udp.put_packet(data) == OK:
				sent += 1


## Client side: listens for beacons while the server browser is open.
class Browser:
	extends Node

	signal changed

	var games: Dictionary = {}  ## key -> Beacon
	var listening: bool = false
	var _udp := PacketPeerUDP.new()

	func _ready() -> void:
		Platform.acquire_multicast_lock()
		_udp.set_broadcast_enabled(true)
		listening = _udp.bind(PORT) == OK
		if not listening:
			push_warning("Discovery: UDP %d is busy; LAN games won't be listed" % PORT)

	func _exit_tree() -> void:
		_udp.close()
		Platform.release_multicast_lock()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_msec()
		var dirty := false
		var budget := 64  # bounded work per frame against floods
		while listening and _udp.get_available_packet_count() > 0 and budget > 0:
			budget -= 1
			var data := _udp.get_packet()
			var b := Discovery.decode(data)
			if b == null:
				continue
			b.address = _udp.get_packet_ip()
			b.seen_ms = now
			dirty = dirty or not games.has(b.key())
			games[b.key()] = b
		for k in games.keys():
			if now - (games[k] as Beacon).seen_ms > EXPIRY_MS:
				games.erase(k)
				dirty = true
		if dirty:
			changed.emit()

	func sorted() -> Array:
		var out := games.values()
		out.sort_custom(func(a: Beacon, b: Beacon) -> bool: return a.name < b.name)
		return out

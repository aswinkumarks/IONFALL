class_name NetStats
extends RefCounted
## Rolling traffic statistics for the net graph and bandwidth checks
## (PLAN §3.3.5). Counts application payload bytes; on-wire bytes add roughly
## 40 bytes per packet (IPv4 + UDP + ENet headers).

const WIRE_OVERHEAD := 40

var bytes_in_per_s: int = 0
var bytes_out_per_s: int = 0
var packets_in_per_s: int = 0
var packets_out_per_s: int = 0
var max_snapshot: int = 0
var snapshot_sizes := FrameStats.new(300)

var _bi: int = 0
var _bo: int = 0
var _pi: int = 0
var _po: int = 0
var _window_start: int = 0


func on_in(size: int) -> void:
	_roll()
	_bi += size
	_pi += 1


func on_out(size: int) -> void:
	_roll()
	_bo += size
	_po += 1


func on_snapshot(size: int) -> void:
	max_snapshot = maxi(max_snapshot, size)
	snapshot_sizes.add(size)


func wire_bytes_in_per_s() -> int:
	_roll()
	return bytes_in_per_s + packets_in_per_s * WIRE_OVERHEAD


func wire_bytes_out_per_s() -> int:
	_roll()
	return bytes_out_per_s + packets_out_per_s * WIRE_OVERHEAD


func _roll() -> void:
	var now := Time.get_ticks_msec()
	if now - _window_start >= 2000:
		# Idle for a whole window: nothing was sent or received.
		_bi = 0
		_bo = 0
		_pi = 0
		_po = 0
	if now - _window_start >= 1000:
		bytes_in_per_s = _bi
		bytes_out_per_s = _bo
		packets_in_per_s = _pi
		packets_out_per_s = _po
		_bi = 0
		_bo = 0
		_pi = 0
		_po = 0
		_window_start = now

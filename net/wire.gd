class_name Wire
extends RefCounted
## Binary wire helpers. Little-endian everywhere. The reader is bounds-checked:
## any out-of-range read sets `ok = false` and returns 0, so malformed packets
## can never crash the decoder (PLAN §3.7).

## Position quantization: 1 mm, signed 24 bit (±8388 m).
const POS_SCALE := 1000.0
const POS_LIMIT := 8388607
## Velocity: 1 cm/s, signed 16 bit.
const VEL_SCALE := 100.0


class Writer:
	var _b := StreamPeerBuffer.new()

	func u8(v: int) -> Writer:
		_b.put_u8(v & 0xFF)
		return self

	func i8(v: int) -> Writer:
		_b.put_8(clampi(v, -128, 127))
		return self

	func u16(v: int) -> Writer:
		_b.put_u16(v & 0xFFFF)
		return self

	func i16(v: int) -> Writer:
		_b.put_16(clampi(v, -32768, 32767))
		return self

	func u32(v: int) -> Writer:
		_b.put_u32(v & 0xFFFFFFFF)
		return self

	func f32(v: float) -> Writer:
		_b.put_float(v)
		return self

	func i24(v: int) -> Writer:
		v = clampi(v, -POS_LIMIT, POS_LIMIT) & 0xFFFFFF
		_b.put_u8(v & 0xFF)
		_b.put_u8((v >> 8) & 0xFF)
		_b.put_u8((v >> 16) & 0xFF)
		return self

	func vec_f32(v: Vector3) -> Writer:
		return f32(v.x).f32(v.y).f32(v.z)

	func pos(v: Vector3) -> Writer:
		return i24(roundi(v.x * POS_SCALE)).i24(roundi(v.y * POS_SCALE)).i24(roundi(v.z * POS_SCALE))

	func vel(v: Vector3) -> Writer:
		return i16(roundi(v.x * VEL_SCALE)).i16(roundi(v.y * VEL_SCALE)).i16(roundi(v.z * VEL_SCALE))

	func bytes(data: PackedByteArray) -> Writer:
		_b.put_data(data)
		return self

	func str8(s: String) -> Writer:
		var d := s.to_utf8_buffer()
		if d.size() > 255:
			d = d.slice(0, 255)
		u8(d.size())
		return bytes(d)

	func size() -> int:
		return _b.data_array.size()

	func data() -> PackedByteArray:
		return _b.data_array


class Reader:
	var ok: bool = true
	var _d: PackedByteArray
	var _p: int = 0

	func _init(data: PackedByteArray) -> void:
		_d = data

	func remaining() -> int:
		return _d.size() - _p

	func _need(n: int) -> bool:
		if not ok or _p + n > _d.size():
			ok = false
			return false
		return true

	func u8() -> int:
		if not _need(1):
			return 0
		_p += 1
		return _d.decode_u8(_p - 1)

	func i8() -> int:
		if not _need(1):
			return 0
		_p += 1
		return _d.decode_s8(_p - 1)

	func u16() -> int:
		if not _need(2):
			return 0
		_p += 2
		return _d.decode_u16(_p - 2)

	func i16() -> int:
		if not _need(2):
			return 0
		_p += 2
		return _d.decode_s16(_p - 2)

	func u32() -> int:
		if not _need(4):
			return 0
		_p += 4
		return _d.decode_u32(_p - 4)

	func f32() -> float:
		if not _need(4):
			return 0.0
		_p += 4
		var v := _d.decode_float(_p - 4)
		if is_nan(v) or is_inf(v):
			ok = false
			return 0.0
		return v

	func i24() -> int:
		if not _need(3):
			return 0
		var v := _d[_p] | (_d[_p + 1] << 8) | (_d[_p + 2] << 16)
		_p += 3
		if v & 0x800000:
			v -= 0x1000000
		return v

	func vec_f32() -> Vector3:
		return Vector3(f32(), f32(), f32())

	func pos() -> Vector3:
		return Vector3(i24() / POS_SCALE, i24() / POS_SCALE, i24() / POS_SCALE)

	func vel() -> Vector3:
		return Vector3(i16() / VEL_SCALE, i16() / VEL_SCALE, i16() / VEL_SCALE)

	func str8(max_len: int = 255) -> String:
		var n := u8()
		if n > max_len or not _need(n):
			ok = false
			return ""
		_p += n
		return _d.slice(_p - n, _p).get_string_from_utf8()

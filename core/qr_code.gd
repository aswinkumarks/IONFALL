class_name QrCode
extends RefCounted
## Minimal QR Code encoder for join links (PLAN §3.6): byte mode, error
## correction level M, versions 1-6 (up to 106 bytes), best of the 8 masks
## by the standard penalty rules. Follows the structure of Project Nayuki's
## reference implementation (ISO/IEC 18004).

## Per version (index = version): [error-correction codewords per block,
## number of blocks] at level M; all blocks are the same size up to v6.
const ECC_M := [[], [10, 1], [16, 1], [26, 1], [18, 2], [24, 2], [16, 4]]
const ALIGN := [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34]]
const MAX_VERSION := 6
const ECL_M_BITS := 0  ## format bits for level M

var size: int = 0
var _modules: Array[PackedByteArray] = []  ## [y][x], 1 = dark
var _function: Array[PackedByteArray] = []  ## [y][x], 1 = function pattern


## `text` as a QR code, or null if it doesn't fit version 6.
static func encode(text: String) -> QrCode:
	var data := text.to_utf8_buffer()
	for version in range(1, MAX_VERSION + 1):
		if data.size() <= _capacity(version):
			var qr := QrCode.new()
			qr._build(version, data)
			return qr
	return null


func is_dark(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < size and y < size and _modules[y][x] == 1


## The code as an image: `scale` pixels per module, a 4-module quiet zone.
func to_image(scale: int = 8) -> Image:
	var n := (size + 8) * scale
	var img := Image.create(n, n, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	for y in size:
		for x in size:
			if _modules[y][x] == 1:
				img.fill_rect(Rect2i((x + 4) * scale, (y + 4) * scale, scale, scale), Color.BLACK)
	return img


static func _raw_modules(version: int) -> int:
	var result := (16 * version + 128) * version + 64
	if version >= 2:
		var num_align := version / 7 + 2
		result -= (25 * num_align - 10) * num_align - 55
	return result


static func _data_codewords(version: int) -> int:
	return _raw_modules(version) / 8 - ECC_M[version][0] * ECC_M[version][1]


## Bytes that fit: 4 mode bits and an 8-bit length (versions 1-9).
static func _capacity(version: int) -> int:
	return (_data_codewords(version) * 8 - 12) / 8


func _build(version: int, data: PackedByteArray) -> void:
	size = version * 4 + 17
	for y in size:
		var row := PackedByteArray()
		row.resize(size)
		_modules.append(row)
		_function.append(row.duplicate())
	_draw_function_patterns(version)
	_draw_codewords(_add_ecc(version, _data_bits(version, data)))
	# The mask with the lowest penalty.
	var best := 0
	var best_penalty := 1 << 30
	for mask in 8:
		_apply_mask(mask)
		_draw_format(mask)
		var p := _penalty()
		if p < best_penalty:
			best_penalty = p
			best = mask
		_apply_mask(mask)  # XOR again undoes it
	_apply_mask(best)
	_draw_format(best)


# --- Data and error correction ---

func _data_bits(version: int, data: PackedByteArray) -> PackedByteArray:
	var bits := PackedByteArray()
	_append_bits(bits, 0x4, 4)  # byte mode
	_append_bits(bits, data.size(), 8)
	for b in data:
		_append_bits(bits, b, 8)
	var capacity := _data_codewords(version) * 8
	_append_bits(bits, 0, mini(4, capacity - bits.size()))
	_append_bits(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < capacity:
		_append_bits(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var out := PackedByteArray()
	out.resize(bits.size() / 8)
	for i in bits.size():
		out[i >> 3] |= bits[i] << (7 - (i & 7))
	return out


static func _append_bits(bits: PackedByteArray, value: int, count: int) -> void:
	for i in range(count - 1, -1, -1):
		bits.append((value >> i) & 1)


## Splits into blocks, adds each block's Reed-Solomon codewords and
## interleaves them.
func _add_ecc(version: int, data: PackedByteArray) -> PackedByteArray:
	var ecc_len: int = ECC_M[version][0]
	var blocks: int = ECC_M[version][1]
	var block_len := data.size() / blocks
	var divisor := _rs_divisor(ecc_len)
	var data_blocks: Array[PackedByteArray] = []
	var ecc_blocks: Array[PackedByteArray] = []
	for b in blocks:
		var d := data.slice(b * block_len, (b + 1) * block_len)
		data_blocks.append(d)
		ecc_blocks.append(_rs_remainder(d, divisor))
	var out := PackedByteArray()
	for i in block_len:
		for b in blocks:
			out.append(data_blocks[b][i])
	for i in ecc_len:
		for b in blocks:
			out.append(ecc_blocks[b][i])
	return out


static func _rs_divisor(degree: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(degree)
	result[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			result[j] = _gf_mul(result[j], root)
			if j + 1 < degree:
				result[j] ^= result[j + 1]
		root = _gf_mul(root, 0x02)
	return result


static func _rs_remainder(data: PackedByteArray, divisor: PackedByteArray) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(divisor.size())
	for b in data:
		var factor := b ^ result[0]
		result = result.slice(1)
		result.append(0)
		for i in divisor.size():
			result[i] ^= _gf_mul(divisor[i], factor)
	return result


## Multiplication in GF(2^8) modulo x^8 + x^4 + x^3 + x^2 + 1.
static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xFF


# --- Layout ---

func _set_function(x: int, y: int, dark: bool) -> void:
	_modules[y][x] = 1 if dark else 0
	_function[y][x] = 1


func _draw_function_patterns(version: int) -> void:
	for i in size:
		_set_function(6, i, i % 2 == 0)
		_set_function(i, 6, i % 2 == 0)
	for c: Vector2i in [Vector2i(3, 3), Vector2i(size - 4, 3), Vector2i(3, size - 4)]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x := c.x + dx
				var y := c.y + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					var dist := maxi(absi(dx), absi(dy))
					_set_function(x, y, dist != 2 and dist != 4)
	var pos: Array = ALIGN[version]
	for i in pos.size():
		for j in pos.size():
			if (i == 0 and j == 0) or (i == 0 and j == pos.size() - 1) or (i == pos.size() - 1 and j == 0):
				continue  # finder corners
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_set_function(pos[i] + dx, pos[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	_draw_format(0)  # reserves the format areas (redrawn with the real mask)


func _draw_format(mask: int) -> void:
	var data := ECL_M_BITS << 3 | mask
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := (data << 10 | rem) ^ 0x5412
	var bit := func(i: int) -> bool: return ((bits >> i) & 1) != 0
	for i in range(0, 6):
		_set_function(8, i, bit.call(i))
	_set_function(8, 7, bit.call(6))
	_set_function(8, 8, bit.call(7))
	_set_function(7, 8, bit.call(8))
	for i in range(9, 15):
		_set_function(14 - i, 8, bit.call(i))
	for i in range(0, 8):
		_set_function(size - 1 - i, 8, bit.call(i))
	for i in range(8, 15):
		_set_function(8, size - 15 + i, bit.call(i))
	_set_function(8, size - 8, true)  # the dark module


func _draw_codewords(data: PackedByteArray) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if _function[y][x] == 0 and i < data.size() * 8:
					_modules[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


func _apply_mask(mask: int) -> void:
	for y in size:
		for x in size:
			if _function[y][x] == 1:
				continue
			var invert := false
			match mask:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				_modules[y][x] ^= 1


# --- Penalty (mask choice) ---

## The standard penalty: runs of 5+ same-colour modules, 2x2 blocks,
## finder-like 1:1:3:1:1 patterns with 4 light modules beside them, and
## dark/light imbalance. Only picks the mask; any mask decodes.
func _penalty() -> int:
	var result := 0
	for horizontal in [true, false]:
		for a in size:
			var line := PackedByteArray()
			for b in size:
				line.append(_modules[a][b] if horizontal else _modules[b][a])
			var run := 1
			for b in range(1, size + 1):
				if b < size and line[b] == line[b - 1]:
					run += 1
				else:
					if run >= 5:
						result += run - 2
					run = 1
			for b in size - 6:
				if _finder_at(line, b):
					var before := b >= 4 and line.slice(b - 4, b).count(1) == 0
					var after := b + 11 <= size and line.slice(b + 7, b + 11).count(1) == 0
					if before or after or b < 4 or b + 11 > size:
						result += 40
	for y in size - 1:
		for x in size - 1:
			var c := _modules[y][x]
			if c == _modules[y][x + 1] and c == _modules[y + 1][x] and c == _modules[y + 1][x + 1]:
				result += 3
	var dark := 0
	for y in size:
		dark += _modules[y].count(1)
	var total := size * size
	result += maxi(ceili(absi(dark * 20 - total * 10) / float(total)) - 1, 0) * 10
	return result


static func _finder_at(line: PackedByteArray, i: int) -> bool:
	const PATTERN := [1, 0, 1, 1, 1, 0, 1]
	for k in 7:
		if line[i + k] != PATTERN[k]:
			return false
	return true

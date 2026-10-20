extends GutTest
## QR join codes (PLAN §3.6). Decoded independently while developing
## (scratch Python decoder: format bits, Reed-Solomon syndromes and text all
## matched for versions 1, 3, 4 and 6); these guard the structure.


func test_versions_and_function_patterns() -> void:
	assert_eq(QrCode.encode("HI").size, 21, "version 1")
	var qr := QrCode.encode("ionfall://join?host=192.168.1.42&port=47710")
	assert_eq(qr.size, 33, "a join link fits version 4")
	# Finder corners: dark ring, light ring, dark 3x3 centre.
	for c: Vector2i in [Vector2i(0, 0), Vector2i(qr.size - 7, 0), Vector2i(0, qr.size - 7)]:
		assert_true(qr.is_dark(c.x, c.y))
		assert_false(qr.is_dark(c.x + 1, c.y + 1))
		assert_true(qr.is_dark(c.x + 3, c.y + 3))
	# Timing pattern alternates; the dark module is set.
	for i in range(8, qr.size - 8):
		assert_eq(qr.is_dark(6, i), i % 2 == 0)
	assert_true(qr.is_dark(8, qr.size - 8))
	assert_null(QrCode.encode("x".repeat(200)), "too long for version 6")


func test_reed_solomon_remainder() -> void:
	# The remainder of data + its ECC by the generator is zero.
	var divisor := QrCode._rs_divisor(10)
	var data := PackedByteArray([0x40, 0x24, 0x84, 0x90, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11, 0xEC, 0x11])
	var ecc := QrCode._rs_remainder(data, divisor)
	var all := data + ecc
	assert_eq(QrCode._rs_remainder(all, divisor), PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))

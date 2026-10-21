extends GutTest
## Internet play (decision 0005): invite codes. The EOS round trip itself is
## covered by the two-instance laptop test in docs/online.md, not here (it
## needs Epic's services).

func test_codes_are_normalized() -> void:
	assert_eq(Online.parse_code("kfs7wq"), "KFS7WQ")
	assert_eq(Online.parse_code(" KFS-7WQ "), "KFS7WQ")
	assert_eq(Online.parse_code("kfs 7wq"), "KFS7WQ")


func test_addresses_and_look_alikes_are_not_codes() -> void:
	assert_eq(Online.parse_code("192.168.0.9"), "")
	assert_eq(Online.parse_code("ABC12"), "", "too short")
	assert_eq(Online.parse_code("ABCDEFG"), "", "too long")
	assert_eq(Online.parse_code("ABCDE0"), "", "0 is never used (looks like O)")
	assert_eq(Online.parse_code("ABCDEI"), "", "I is never used (looks like 1)")


func test_generated_codes_parse() -> void:
	for i in 200:
		var code: String = Online.new_code()
		assert_eq(Online.parse_code(code), code)

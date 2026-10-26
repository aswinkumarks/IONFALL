extends GutTest
## PlayerSimState.copy() lists its fields by hand (for speed): it must
## carry every script field, and the arrays must not be shared.


## Every field set to something no new state has.
func _distinct() -> PlayerSimState:
	var s := PlayerSimState.new()
	var k := 1
	for name: String in s._fields():
		var v: Variant = s.get(name)
		match typeof(v):
			TYPE_BOOL:
				s.set(name, not v)
			TYPE_INT:
				s.set(name, (v as int) + 7 + k)
			TYPE_FLOAT:
				s.set(name, (v as float) + 0.25 * k)
			TYPE_VECTOR2:
				s.set(name, Vector2(k, -k))
			TYPE_VECTOR3:
				s.set(name, Vector3(k, 2 * k, -k))
			TYPE_PACKED_INT32_ARRAY:
				s.set(name, PackedInt32Array([k, k + 1]))
			TYPE_PACKED_BYTE_ARRAY:
				s.set(name, PackedByteArray([k, k + 1, k + 2]))
			_:
				fail_test("%s: copy() test doesn't know type %s" % [name, type_string(typeof(v))])
		k += 1
	return s


func test_copy_carries_every_field() -> void:
	var s := _distinct()
	var fresh := PlayerSimState.new()
	for name: String in s._fields():
		assert_ne(s.get(name), fresh.get(name), "%s was set" % name)
	assert_eq(s.copy().diff(s), "", "copy() matches on every field")


func test_copy_arrays_are_independent() -> void:
	var s := _distinct()
	var c := s.copy()
	for name: String in s._fields():
		var v: Variant = s.get(name)
		if v is PackedInt32Array or v is PackedByteArray:
			v[0] = 99
			assert_ne(c.get(name)[0], 99, "%s isn't shared" % name)

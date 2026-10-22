extends GutTest
## InputAdapter: held mouse buttons must not get stuck when the cursor is
## freed while they're down (dying while firing frees it for the loadout bar).

var adapter: InputAdapter


func before_each() -> void:
	adapter = InputAdapter.new()
	add_child_autofree(adapter)


func _mouse(button: int, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	return e


func _fire_held() -> bool:
	return (adapter.build_command(1).held & PlayerCommand.Held.FIRE) != 0


func test_release_with_free_cursor_stops_firing() -> void:
	adapter._mouse_fire = true  # pressed while captured
	assert_true(_fire_held())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	adapter._unhandled_input(_mouse(MOUSE_BUTTON_LEFT, false))
	assert_false(_fire_held(), "released while the cursor was free")


func test_release_mouse_lets_go_of_fire_and_held_aim() -> void:
	adapter._mouse_fire = true
	adapter._mouse_aim = true
	adapter.release_mouse()
	var held := adapter.build_command(1).held
	assert_eq(held & PlayerCommand.Held.FIRE, 0)
	if not Settings.get_value("input", "aim_toggle"):
		assert_eq(held & PlayerCommand.Held.AIM, 0)

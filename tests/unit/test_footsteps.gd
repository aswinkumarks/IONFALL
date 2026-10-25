extends GutTest
## Footsteps (GameAudio.update_player): walking makes them, crouch-walking
## doesn't.


func _steps_played(stance: int) -> int:
	var audio := GameAudio.new()
	add_child_autofree(audio)
	var s := PlayerSimState.new()
	s.alive = true
	s.move_state = PlayerSimState.Move.GROUND
	s.stance = stance
	s.position = Vector3.ZERO
	audio.update_player(7, s, false)
	for i in 120:  # 6 m in 5 cm steps
		s.position.x += 0.05
		audio.update_player(7, s, false)
	var played := 0
	for v: Variant in audio._meta:
		if audio._meta[v].category == "Footsteps":
			played += 1
	return played


func test_walking_makes_footsteps() -> void:
	assert_gt(_steps_played(PlayerSimState.Stance.STAND), 0)


func test_crouch_walking_is_silent() -> void:
	assert_eq(_steps_played(PlayerSimState.Stance.CROUCH), 0)

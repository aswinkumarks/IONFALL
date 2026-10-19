class_name MovementConfig
extends Resource
## Movement tuning (PLAN §2.1). Part of the compatibility hash, since every
## value changes simulation results.

@export_group("Speeds (m/s)")
@export var walk_speed: float = 6.0
@export var sprint_speed: float = 8.5
@export var crouch_speed: float = 3.0
@export var air_wish_speed_cap: float = 1.2

@export_group("Acceleration")
@export var ground_accel: float = 12.0
@export var air_accel: float = 40.0
@export var friction: float = 7.0
@export var stop_speed: float = 3.0
@export var gravity: float = 15.0

@export_group("Jumping")
@export var jump_velocity: float = 6.0
@export var double_jump_velocity: float = 5.6
## How much of the horizontal velocity turns toward the input on a double jump.
@export_range(0.0, 1.0) var double_jump_redirect: float = 0.5
@export var coyote_ticks: int = 6
@export var jump_buffer_ticks: int = 6

@export_group("Slide")
@export var slide_min_speed: float = 7.0
@export var slide_boost: float = 2.5
@export var slide_max_speed: float = 12.0
@export var slide_friction: float = 0.8
@export var slide_ticks: int = 60
@export var slide_end_speed: float = 4.0

@export_group("Mantle")
@export var mantle_min_height: float = 0.5
@export var mantle_max_height: float = 1.8
@export var mantle_reach: float = 0.5
@export var mantle_ticks: int = 18
@export var mantle_exit_speed: float = 3.0

@export_group("Body")
@export var capsule_radius: float = 0.4
@export var stand_height: float = 1.8
@export var crouch_height: float = 1.2
@export var eye_stand: float = 1.6
@export var eye_crouch: float = 1.0
@export var eye_slide: float = 0.8
@export var max_floor_angle_deg: float = 46.0
@export var snap_length: float = 0.3


func height_for(stance: PlayerSimState.Stance) -> float:
	return stand_height if stance == PlayerSimState.Stance.STAND else crouch_height


func eye_for(stance: PlayerSimState.Stance) -> float:
	match stance:
		PlayerSimState.Stance.CROUCH:
			return eye_crouch
		PlayerSimState.Stance.SLIDE:
			return eye_slide
	return eye_stand

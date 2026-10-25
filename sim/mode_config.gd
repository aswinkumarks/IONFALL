class_name ModeConfig
extends Resource
## Match and game-mode balance (data/modes.tres, read through
## Balance.MODES): score limits, respawn delays, match timers, Capture the
## Flag and co-op waves. Part of the compatibility hash, like everything in
## data/. Times are ticks (60 per second).

@export_group("Score limits")
## Kills that win a free-for-all.
@export var ffa_score_limit: int = 25
## Team kills that win team deathmatch.
@export var tdm_score_limit: int = 50
## Captures that win Capture the Flag.
@export var ctf_score_limit: int = 3
## Waves to clear to win co-op.
@export var wave_count: int = 10

@export_group("Respawning")
@export var ffa_respawn_ticks: int = 180
## Team deathmatch and Capture the Flag (co-op brings fallen players back
## when the wave is cleared).
@export var team_respawn_ticks: int = 300

@export_group("Match timers")
@export var countdown_ticks: int = 300
## The scoreboard after a match, before the lobby.
@export var post_match_ticks: int = 900
## Time limit when the lobby doesn't set one.
@export var default_time_limit_ticks: int = 36000
## A tie at the time limit: the next score decides, for at most this long,
## then it's a draw.
@export var sudden_death_ticks: int = 7200

@export_group("Capture the Flag")
## A dropped flag goes back to its base after this long.
@export var flag_return_ticks: int = 1800
## Personal score for capturing and for returning a flag.
@export var capture_points: int = 5
@export var return_points: int = 1

@export_group("Co-op waves")
## The pause before the first wave and between waves.
@export var wave_intermission_ticks: int = 480
## Wave n has first_wave_bots + (n - 1) * extra_bots_per_wave bots, plus
## extra_bots_per_human for each human after the first.
@export var first_wave_bots: int = 2
@export var extra_bots_per_wave: int = 1
@export var extra_bots_per_human: int = 1
## Bots get one difficulty level harder every this many waves.
@export var waves_per_difficulty_step: int = 3

extends Node
class_name TurnManager

# Two phases: Player and Enemy.
enum Phase { PLAYER, ENEMY }

# Emitted whenever the phase changes.
signal phase_changed(new_phase: Phase)

# Track which phase we're currently in.
var current_phase: Phase = Phase.PLAYER

# Optional safety: prevents double end_turn in the same frame.
var _pending_phase_start: bool = false


func _ready() -> void:
	# Start the game in the PLAYER phase.
	# Defer to avoid edge cases if something calls end_turn during _ready chains.
	call_deferred("_start_player_phase")


func is_player_turn() -> bool:
	return current_phase == Phase.PLAYER


func end_turn() -> void:
	# Prevent accidental re-entrant calls (common when phase_changed handlers also end turns).
	if _pending_phase_start:
		return

	_pending_phase_start = true

	# Flip phase FIRST, then defer the start to break recursion.
	if current_phase == Phase.PLAYER:
		current_phase = Phase.ENEMY
		call_deferred("_start_enemy_phase")
	else:
		current_phase = Phase.PLAYER
		call_deferred("_start_player_phase")


func _start_player_phase() -> void:
	_pending_phase_start = false
	print("TurnManager: start PLAYER phase")
	current_phase = Phase.PLAYER
	phase_changed.emit(Phase.PLAYER)


func _start_enemy_phase() -> void:
	_pending_phase_start = false
	print("TurnManager: start ENEMY phase")
	current_phase = Phase.ENEMY
	phase_changed.emit(Phase.ENEMY)

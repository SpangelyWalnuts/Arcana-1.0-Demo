extends Node
class_name TurnManager

# Two phases: Player and Enemy.
enum Phase { PLAYER, ENEMY }

# Emitted whenever the phase changes.
signal phase_changed(new_phase: Phase)

# Track which phase we're currently in.
var current_phase: Phase = Phase.PLAYER


func _ready() -> void:
	# Start the game in the PLAYER phase.
	# This will notify Main.gd via the phase_changed signal.
	_start_player_phase()


func is_player_turn() -> bool:
	# Helper for Main.gd to know whose turn it is.
	return current_phase == Phase.PLAYER


func end_turn() -> void:
	# Called by Main.gd when the current side is done acting.
	# We flip the phase and start the next one.
	if current_phase == Phase.PLAYER:
		# Player just finished → go to enemy phase.
		current_phase = Phase.ENEMY
		_start_enemy_phase()
	else:
		# Enemy just finished → go back to player phase.
		current_phase = Phase.PLAYER
		_start_player_phase()


func _start_player_phase() -> void:
	# DO NOT call end_turn() from here.
	# Just emit the signal so Main.gd can set up the player turn.
	print("TurnManager: start PLAYER phase")
	current_phase = Phase.PLAYER
	emit_signal("phase_changed", Phase.PLAYER)


func _start_enemy_phase() -> void:
	# DO NOT call end_turn() from here either.
	# Just notify Main.gd that the enemy phase began.
	print("TurnManager: start ENEMY phase")
	current_phase = Phase.ENEMY
	emit_signal("phase_changed", Phase.ENEMY)

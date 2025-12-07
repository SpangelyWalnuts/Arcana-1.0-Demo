extends Node2D
class_name TerrainEffect

@export var key: String = "wall"      # e.g. "wall", "vines", "spikes"
@export var blocks_movement: bool = false
@export var move_cost_bonus: int = 0  # extra move cost if tile has this
@export var duration_turns: int = -1  # -1 = infinite, >= 0 = ticks down

var grid_position: Vector2i = Vector2i.ZERO

func is_expired() -> bool:
	return duration_turns == 0


func tick_duration() -> void:
	# -1 means permanent
	if duration_turns < 0:
		return

	duration_turns -= 1

	if duration_turns <= 0:
		queue_free()


func on_unit_enter(unit: Node) -> void:
	# Override in subclasses or check `key` in here if you want
	# e.g. if key == "spikes": deal damage, etc.
	pass


func on_unit_exit(unit: Node) -> void:
	pass


func on_turn_start(for_team: String) -> void:
	# Called once per player phase from Main.gd (for now)
	pass


func on_turn_end(for_team: String) -> void:
	# You can call this in the future if you want end-of-phase behavior
	pass

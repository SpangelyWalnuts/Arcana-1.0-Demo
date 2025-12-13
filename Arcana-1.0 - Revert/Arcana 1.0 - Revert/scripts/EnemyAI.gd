extends Node
class_name EnemyAI

# Default tuning knobs (used as fallback)
@export var move_cost_weight: float = 0.75
@export var defense_weight: float = 0.75
@export var hazard_weight: float = 0.0
@export var threat_bonus: float = 5.0
@export var prefer_threat_tiles: bool = true


# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------
func take_turn(main: Node, enemy: Node, players: Array) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if enemy.hp <= 0:
		return
	if players.is_empty():
		return

	var target: Node = _find_closest_player(main, enemy, players)
	if target == null or not is_instance_valid(target):
		return

	# One action per turn: attack OR move OR wait
	var dist_to_target: int = _distance(enemy.grid_position, target.grid_position)
	if dist_to_target <= int(enemy.attack_range):
		if main.combat_manager != null:
			main.combat_manager.perform_attack(enemy, target)
		return

	if StatusManager != null and StatusManager.unit_has_flag(enemy, "prevent_move"):
		return

	var final_tile: Vector2i = _choose_greedy_destination(main, enemy, target)
	if final_tile == enemy.grid_position:
		return
	print(enemy.name, "role=", _get_ai_role(enemy))

	_move_enemy_to_tile(main, enemy, final_tile)


func get_intent(main: Node, enemy: Node, players: Array) -> String:
	if enemy == null or not is_instance_valid(enemy) or enemy.hp <= 0:
		return ""
	if players.is_empty():
		return ""

	var target: Node = _find_closest_player(main, enemy, players)
	if target == null or not is_instance_valid(target):
		return ""

	var dist_to_target: int = _distance(enemy.grid_position, target.grid_position)
	if dist_to_target <= int(enemy.attack_range):
		return "attack"

	if StatusManager != null and StatusManager.unit_has_flag(enemy, "prevent_move"):
		return "wait"

	var dest: Vector2i = _choose_greedy_destination(main, enemy, target)
	return "move" if dest != enemy.grid_position else "wait"


# ------------------------------------------------------------
# Role Profiles
# ------------------------------------------------------------
func _get_ai_role(enemy: Node) -> String:
	if enemy != null and enemy.has_meta("ai_role"):
		return String(enemy.get_meta("ai_role"))
	return "offense"


func _get_profile_weights(role: String) -> Dictionary:
	match role:
		"offense":
			return {
				"move_cost_weight": 0.6,
				"defense_weight": 0.3,
				"threat_bonus": 7.0,
			}
		"defense":
			return {
				"move_cost_weight": 1.0,
				"defense_weight": 1.2,
				"threat_bonus": 3.0,
			}
		"support":
			# Placeholder until enemies cast/support:
			return {
				"move_cost_weight": 0.9,
				"defense_weight": 1.0,
				"threat_bonus": 2.0,
			}
		_:
			return {
				"move_cost_weight": move_cost_weight,
				"defense_weight": defense_weight,
				"threat_bonus": threat_bonus,
			}


func _get_effective_weights(main: Node, enemy: Node) -> Dictionary:
	var role: String = _get_ai_role(enemy)
	var w := _get_profile_weights(role)

	var aggression := _get_objective_aggression(main)

	return {
		"move_cost_weight": float(w.get("move_cost_weight", move_cost_weight)),
		"defense_weight": float(w.get("defense_weight", defense_weight)) * (2.0 - aggression),
		"threat_bonus": float(w.get("threat_bonus", threat_bonus)) * aggression,
		"role": role,
	}



# ------------------------------------------------------------
# Greedy multi-tile movement
# ------------------------------------------------------------
func _choose_greedy_destination(main: Node, enemy: Node, target: Node) -> Vector2i:
	var move_points: int = _get_move_budget(enemy)
	if move_points <= 0:
		return enemy.grid_position

	var w := _get_effective_weights(main, enemy)
	var e_move_cost_weight: float = float(w["move_cost_weight"])
	var e_defense_weight: float = float(w["defense_weight"])
	var e_threat_bonus: float = float(w["threat_bonus"])

	var current: Vector2i = enemy.grid_position
	var best_reached: Vector2i = current
	var ar: int = int(enemy.attack_range)

	var best_score: float = _tile_score(main, current, target.grid_position, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)

	var visited: Dictionary = {}
	visited[current] = true

	while move_points > 0:
		var next: Vector2i = _choose_best_neighbor(
			main,
			enemy,
			current,
			target.grid_position,
			move_points,
			visited,
			e_move_cost_weight,
			e_defense_weight,
			e_threat_bonus
		)

		if next == current:
			break

		var cost: int = 1
		if main.grid != null and main.grid.has_method("get_move_cost"):
			cost = int(main.grid.get_move_cost(next))
		if cost <= 0:
			cost = 1

		move_points -= cost
		current = next
		visited[current] = true

		var s: float = _tile_score(main, current, target.grid_position, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
		if s < best_score:
			best_score = s
			best_reached = current

	if best_reached == enemy.grid_position and current != enemy.grid_position:
		best_reached = current

	return best_reached


func _choose_best_neighbor(
	main: Node,
	enemy: Node,
	from: Vector2i,
	target_pos: Vector2i,
	move_points_left: int,
	visited: Dictionary,
	e_move_cost_weight: float,
	e_defense_weight: float,
	e_threat_bonus: float
) -> Vector2i:
	var candidates: Array[Vector2i] = [
		from + Vector2i(1, 0),
		from + Vector2i(-1, 0),
		from + Vector2i(0, 1),
		from + Vector2i(0, -1)
	]

	var best_tile: Vector2i = from
	var best_score: float = INF
	var cur_d: int = _distance(from, target_pos)
	var ar: int = int(enemy.attack_range)

	for t in candidates:
		if visited.has(t):
			continue
		if not _enemy_can_step_to(main, enemy, t):
			continue

		var cost: int = 1
		if main.grid != null and main.grid.has_method("get_move_cost"):
			cost = int(main.grid.get_move_cost(t))
		if cost <= 0:
			cost = 1
		if cost > move_points_left:
			continue

		var s: float = _tile_score(main, t, target_pos, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)

		# discourage steps that increase distance (reduces wobble)
		var next_d: int = _distance(t, target_pos)
		if next_d > cur_d:
			s += 0.5

		if s < best_score:
			best_score = s
			best_tile = t

	return best_tile


func _tile_score(
	main: Node,
	tile: Vector2i,
	target_pos: Vector2i,
	attack_range: int,
	e_move_cost_weight: float,
	e_defense_weight: float,
	e_threat_bonus: float
) -> float:
	var d: int = _distance(tile, target_pos)

	var move_cost: int = 1
	if main.grid != null and main.grid.has_method("get_move_cost"):
		move_cost = int(main.grid.get_move_cost(tile))

	var def_bonus: int = 0
	if main.grid != null and main.grid.has_method("get_defense_bonus"):
		def_bonus = int(main.grid.get_defense_bonus(tile))

	var hazard: float = 0.0

	var score: float = float(d) + float(move_cost) * e_move_cost_weight + hazard * hazard_weight

	if prefer_threat_tiles and d <= attack_range:
		score -= e_threat_bonus

	score -= float(def_bonus) * e_defense_weight

	return score


func _enemy_can_step_to(main: Node, enemy: Node, tile: Vector2i) -> bool:
	if main.grid != null and main.grid.has_method("is_walkable"):
		if not bool(main.grid.is_walkable(tile)):
			return false

	if main.has_method("_get_unit_at_tile"):
		var occ = main._get_unit_at_tile(tile)
		if occ != null and occ != enemy:
			return false

	if main.has_method("_get_terrain_effect_at_tile"):
		var eff = main._get_terrain_effect_at_tile(tile)
		if eff != null and eff.blocks_movement:
			return false

	return true


func _get_move_budget(enemy: Node) -> int:
	var bonus: int = 0
	if StatusManager != null and StatusManager.has_method("get_move_bonus"):
		bonus = int(StatusManager.get_move_bonus(enemy))

	var total: int = int(enemy.move_range) + bonus
	if total < 0:
		total = 0
	return total


# ------------------------------------------------------------
# Move + terrain hooks
# ------------------------------------------------------------
func _move_enemy_to_tile(main: Node, enemy: Node, tile: Vector2i) -> void:
	var old_tile: Vector2i = enemy.grid_position

	if main.has_method("_get_terrain_effect_at_tile"):
		var old_eff = main._get_terrain_effect_at_tile(old_tile)
		if old_eff != null:
			old_eff.on_unit_exit(enemy)

	enemy.grid_position = tile
	if main.grid != null and main.grid.has_method("tile_to_world"):
		enemy.position = main.grid.tile_to_world(tile)

	if main.has_method("_get_terrain_effect_at_tile"):
		var new_eff = main._get_terrain_effect_at_tile(tile)
		if new_eff != null:
			new_eff.on_unit_enter(enemy)


# ------------------------------------------------------------
# Targeting helpers
# ------------------------------------------------------------
func _find_closest_player(main: Node, enemy: Node, players: Array) -> Node:
	var closest: Node = null
	var best_dist: int = 999999

	for p in players:
		if p == null or not is_instance_valid(p):
			continue
		if p.hp <= 0:
			continue
		var d: int = _distance(enemy.grid_position, p.grid_position)
		if d < best_dist:
			best_dist = d
			closest = p

	return closest


func _distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


#OBJECTIVE AGGRO HELPER
func _get_objective_aggression(main: Node) -> float:
	if main == null or not main.has_method("get_current_objective_type"):
		return 1.0

	var obj := String(main.get_current_objective_type())

	match obj:
		"rout", "survive", "defeat_amount":
			return 1.25   # aggressive
		"defend", "escape", "activate":
			return 0.7    # cautious
		"boss":
			return 1.0
		_:
			return 1.0

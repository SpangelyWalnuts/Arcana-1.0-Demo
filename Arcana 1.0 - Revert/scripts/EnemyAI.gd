extends Node
class_name EnemyAI

# -----------------------------
# Movement / scoring tuning
# -----------------------------
@export var move_cost_weight: float = 0.75
@export var defense_weight: float = 0.75
@export var hazard_weight: float = 0.0 # future: fire/spikes/etc.
@export var threat_bonus: float = 5.0
@export var prefer_threat_tiles: bool = true

# Hold-vs-move decision (prevents wobble)
@export var hold_margin_base: float = 0.75
@export var hold_margin_defense_role: float = 1.25
@export var hold_margin_support_role: float = 0.75
@export var hold_margin_offense_role: float = 0.25

# Arcana (casting) tuning
@export var arcana_intent_enabled: bool = true


# -----------------------------
# Public API
# -----------------------------
func take_turn(main: Node, enemy: Node, players: Array) -> void:
	# One action per turn: cast OR attack OR move OR wait
	if enemy == null or not is_instance_valid(enemy):
		return
	if _get_int(enemy, "hp", 0) <= 0:
		return
	if players.is_empty():
		return

	var target: Node = _find_closest_player(enemy, players)
	if target == null or not is_instance_valid(target):
		return

	# 0) Cast arcana if possible (so intent "cast" is truthful)
	if arcana_intent_enabled:
		var cast_plan: Dictionary = _choose_cast_plan(enemy, players)
		if not cast_plan.is_empty():
			_execute_cast_plan(main, enemy, cast_plan)
			return

	# 1) Attack if already in range
	var dist_to_target: int = _distance(_get_v2i(enemy, "grid_position", Vector2i.ZERO), _get_v2i(target, "grid_position", Vector2i.ZERO))
	var attack_range: int = _get_int(enemy, "attack_range", 1)
	if dist_to_target <= attack_range:
		var cm: Node = _get_child_or_prop(main, "combat_manager")
		if cm != null and cm.has_method("perform_attack"):
			print("[AI] %s BASIC ATTACK start -> %s" % [enemy.name, target.name])
			cm.perform_attack(enemy, target)

			if cm.has_signal("attack_sequence_finished"):
				# Timeout safety so we never hard-hang during debugging.
				var timeout := get_tree().create_timer(1.0)
				while true:
					var emitted_attacker = await cm.attack_sequence_finished
					print("[AI] attack_sequence_finished emitted for:", emitted_attacker)
					if emitted_attacker == enemy:
						print("[AI] %s BASIC ATTACK end (signal)" % enemy.name)
						break
					if timeout.time_left <= 0.0:
						print("[AI] %s BASIC ATTACK end (TIMEOUT FALLBACK)" % enemy.name)
						break
			else:
				print("[AI] %s no attack_sequence_finished signal; using timer fallback" % enemy.name)
				await get_tree().create_timer(0.25).timeout
				print("[AI] %s BASIC ATTACK end (timer)" % enemy.name)
		return


	# 2) If prevented from moving, wait
	if StatusManager != null and StatusManager.has_method("unit_has_flag") and StatusManager.unit_has_flag(enemy, "prevent_move"):
		return

	# 3) Otherwise MOVE (multi-tile greedy), then end action
	var final_tile: Vector2i = _choose_greedy_destination(main, enemy, target)
	var enemy_tile: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)
	if final_tile == enemy_tile:
		return

	_move_enemy_to_tile(main, enemy, final_tile)


func get_intent(main: Node, enemy: Node, players: Array) -> String:
	if enemy == null or not is_instance_valid(enemy) or _get_int(enemy, "hp", 0) <= 0:
		return ""
	if players.is_empty():
		return ""

# Clear intent payload by default
	_set_intent_skill(enemy, null)

# If we can/plan to cast, show cast intent + store which skill
	if arcana_intent_enabled:
		var cast_plan: Dictionary = _choose_cast_plan(enemy, players)
		if not cast_plan.is_empty():
			if cast_plan.has("skill"):
				_set_intent_skill(enemy, cast_plan["skill"])
			return "cast"


	var target: Node = _find_closest_player(enemy, players)
	if target == null or not is_instance_valid(target):
		return ""

	var enemy_tile: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)
	var target_tile: Vector2i = _get_v2i(target, "grid_position", Vector2i.ZERO)

	var dist_to_target: int = _distance(enemy_tile, target_tile)
	var attack_range: int = _get_int(enemy, "attack_range", 1)

	if dist_to_target <= attack_range:
		return "attack"

	if StatusManager != null and StatusManager.has_method("unit_has_flag") and StatusManager.unit_has_flag(enemy, "prevent_move"):
		return "wait"

	var dest: Vector2i = _choose_greedy_destination(main, enemy, target)
	if dest != enemy_tile:
		if not _should_move(main, enemy, target, dest):
			return "wait"
		return "move"

	return "wait"


# -----------------------------
# Casting (Arcana) planning
# -----------------------------
func _choose_cast_plan(enemy: Node, players: Array) -> Dictionary:
	# Returns {} if no cast. Otherwise:
	# { "skill": Skill, "target_unit": Node, "center_tile": Vector2i }
	if enemy == null or not is_instance_valid(enemy):
		return {}
	if StatusManager != null and StatusManager.has_method("unit_has_flag") and StatusManager.unit_has_flag(enemy, "prevent_arcana"):
		return {}

	# Needs skills array on Unit (your Unit has: var skills: Array[Skill] = [] ) :contentReference[oaicite:0]{index=0}
	if not _has_prop(enemy, "skills"):
		return {}
	var skills: Array = enemy.get("skills")
	if skills == null or skills.is_empty():
		return {}

	for s in skills:
		var skill = s
		if skill == null:
			continue

		# Must have mana
		var mana_cost: int = _get_int(skill, "mana_cost", 0)
		if _has_prop(enemy, "mana"):
			var mana: int = _get_int(enemy, "mana", 0)
			if mana < mana_cost:
				continue

		# Ignore terrain-object skills for now (you can enable later)
		if _has_prop(skill, "is_terrain_object_skill") and bool(skill.get("is_terrain_object_skill")):
			continue
		# effect_type == 3 (terrain) in your scheme; safe-check
		if _has_prop(skill, "effect_type") and int(skill.get("effect_type")) == 3:
			continue

		var pick: Dictionary = _pick_cast_target(enemy, players, skill)
		if pick.is_empty():
			continue
		return pick

	return {}


func _pick_cast_target(enemy: Node, players: Array, skill) -> Dictionary:
	var best_target: Node = null
	var best_dist: int = 999999

	var enemy_tile: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)

	for p in players:
		if p == null or not is_instance_valid(p):
			continue
		if _get_int(p, "hp", 0) <= 0:
			continue

		var p_tile: Vector2i = _get_v2i(p, "grid_position", Vector2i.ZERO)
		var d: int = _distance(enemy_tile, p_tile)
		if d < best_dist:
			best_dist = d
			best_target = p

	if best_target == null:
		return {}

	var cast_range: int = _get_int(skill, "cast_range", 0)
	if best_dist > cast_range:
		return {}

	var best_target_tile: Vector2i = _get_v2i(best_target, "grid_position", Vector2i.ZERO)

	# AoE: use target tile as center for now
	var aoe_radius: int = _get_int(skill, "aoe_radius", 0)
	if aoe_radius > 0:
		return {
			"skill": skill,
			"target_unit": best_target,
			"center_tile": best_target_tile
		}

	# Single target
	return {
		"skill": skill,
		"target_unit": best_target,
		"center_tile": best_target_tile
	}


func _execute_cast_plan(main: Node, enemy: Node, plan: Dictionary) -> void:
	if main == null or enemy == null:
		return
	if not plan.has("skill"):
		return

	var skill = plan["skill"]
	var center_tile: Vector2i = Vector2i.ZERO
	if plan.has("center_tile"):
		center_tile = plan["center_tile"]

	# Let systems spend mana if they already do.
	# If your CombatManager/SkillSystem DOES NOT spend mana for enemies, uncomment:
	# if _has_prop(enemy, "mana"):
	#     enemy.set("mana", _get_int(enemy, "mana", 0) - _get_int(skill, "mana_cost", 0))

	var aoe_radius: int = _get_int(skill, "aoe_radius", 0)

	# AoE skills: route through CombatManager if available
	if aoe_radius > 0:
		var cm: Node = _get_child_or_prop(main, "combat_manager")
		if cm != null and cm.has_method("use_skill"):
			cm.use_skill(enemy, skill, center_tile)
			var cm_wait: Node = _get_child_or_prop(main, "combat_manager")
			if cm_wait != null and cm_wait.has_signal("skill_sequence_finished"):
				while true:
					var emitted = await cm_wait.skill_sequence_finished

					# Godot: if the signal emits one arg, `emitted` is that arg.
					# If it emits multiple args, `emitted` is an Array.
					var caster = emitted
					if emitted is Array and emitted.size() > 0:
						caster = emitted[0]

					if caster == enemy:
						break
			return

	# Single-target: route through SkillSystem if available
	if plan.has("target_unit"):
		var target_unit: Node = plan["target_unit"]
		var ss: Node = _get_child_or_prop(main, "skill_system")
		if ss != null and ss.has_method("execute_skill_on_target"):
			ss.execute_skill_on_target(enemy, target_unit, skill)
			var cm_wait: Node = _get_child_or_prop(main, "combat_manager")
			if cm_wait != null and cm_wait.has_signal("skill_sequence_finished"):
				while true:
					var emitted = await cm_wait.skill_sequence_finished

					# Godot: if the signal emits one arg, `emitted` is that arg.
					# If it emits multiple args, `emitted` is an Array.
					var caster = emitted
					if emitted is Array and emitted.size() > 0:
						caster = emitted[0]

					if caster == enemy:
						break
			return

	# Fallback: basic attack if we have CombatManager
	var cm2: Node = _get_child_or_prop(main, "combat_manager")
	if cm2 != null and cm2.has_method("perform_attack") and plan.has("target_unit"):
		cm2.perform_attack(enemy, plan["target_unit"])

	# small readability pause after casting
	await get_tree().create_timer(0.2).timeout

# -----------------------------
# Role Profiles
# -----------------------------
func _get_ai_role(enemy: Node) -> String:
	if enemy == null:
		return "offense"
	if enemy.has_meta("ai_role"):
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
	var w: Dictionary = _get_profile_weights(role)
	var aggression: float = _get_objective_aggression(main)

	return {
		"move_cost_weight": float(w.get("move_cost_weight", move_cost_weight)),
		"defense_weight": float(w.get("defense_weight", defense_weight)) * (2.0 - aggression),
		"threat_bonus": float(w.get("threat_bonus", threat_bonus)) * aggression,
		"role": role,
	}


func _get_objective_aggression(main: Node) -> float:
	if main == null:
		return 1.0
	if not main.has_method("get_current_objective_type"):
		return 1.0

	var t: String = String(main.get_current_objective_type())
	match t:
		"ROUT":
			return 1.25
		"SURVIVE":
			return 0.85
		"DEFEND":
			return 0.75
		"ESCAPE":
			return 0.8
		_:
			return 1.0


# -----------------------------
# Greedy multi-tile movement
# -----------------------------
func _choose_greedy_destination(main: Node, enemy: Node, target: Node) -> Vector2i:
	var move_points: int = _get_move_budget(enemy)
	if move_points <= 0:
		return _get_v2i(enemy, "grid_position", Vector2i.ZERO)

	var w: Dictionary = _get_effective_weights(main, enemy)
	var e_move_cost_weight: float = float(w.get("move_cost_weight", move_cost_weight))
	var e_defense_weight: float = float(w.get("defense_weight", defense_weight))
	var e_threat_bonus: float = float(w.get("threat_bonus", threat_bonus))

	var current: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)
	var best_reached: Vector2i = current
	var ar: int = _get_int(enemy, "attack_range", 1)

	var best_score: float = _tile_score(main, current, _get_v2i(target, "grid_position", Vector2i.ZERO), ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)

	var visited: Dictionary = {}
	visited[current] = true

	while move_points > 0:
		var next: Vector2i = _choose_best_neighbor(main, enemy, current, _get_v2i(target, "grid_position", Vector2i.ZERO), move_points, visited, e_move_cost_weight, e_defense_weight, e_threat_bonus)
		if next == current:
			break

		var cost: int = 1
		var grid_node: Node = _get_child_or_prop(main, "grid")
		if grid_node != null and grid_node.has_method("get_move_cost"):
			cost = int(grid_node.get_move_cost(next))

		move_points -= cost
		current = next
		visited[current] = true

		var s: float = _tile_score(main, current, _get_v2i(target, "grid_position", Vector2i.ZERO), ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
		if s < best_score:
			best_score = s
			best_reached = current

	if best_reached == _get_v2i(enemy, "grid_position", Vector2i.ZERO) and current != _get_v2i(enemy, "grid_position", Vector2i.ZERO):
		best_reached = current

	return best_reached


func _choose_best_neighbor(
	main: Node,
	enemy: Node,
	current: Vector2i,
	target_pos: Vector2i,
	budget: int,
	visited: Dictionary,
	e_move_cost_weight: float,
	e_defense_weight: float,
	e_threat_bonus: float
) -> Vector2i:
	var best: Vector2i = current
	var best_score: float = 999999.0
	var ar: int = _get_int(enemy, "attack_range", 1)

	var dirs: Array = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for dir in dirs:
		var n: Vector2i = current + dir
		if visited.has(n):
			continue

		if not _enemy_can_step_to(main, enemy, n):
			continue

		var cost: int = 1
		var grid_node: Node = _get_child_or_prop(main, "grid")
		if grid_node != null and grid_node.has_method("get_move_cost"):
			cost = int(grid_node.get_move_cost(n))

		if cost > budget:
			continue

		var score: float = _tile_score(main, n, target_pos, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
		if score < best_score:
			best_score = score
			best = n

	return best


func _should_move(main: Node, enemy: Node, target: Node, dest: Vector2i) -> bool:
	var w: Dictionary = _get_effective_weights(main, enemy)
	var e_move_cost_weight: float = float(w.get("move_cost_weight", move_cost_weight))
	var e_defense_weight: float = float(w.get("defense_weight", defense_weight))
	var e_threat_bonus: float = float(w.get("threat_bonus", threat_bonus))
	var role: String = String(w.get("role", "offense"))

	var ar: int = _get_int(enemy, "attack_range", 1)

	var stay_score: float = _tile_score(main, _get_v2i(enemy, "grid_position", Vector2i.ZERO), _get_v2i(target, "grid_position", Vector2i.ZERO), ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
	var move_score: float = _tile_score(main, dest, _get_v2i(target, "grid_position", Vector2i.ZERO), ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)

	var aggression: float = _get_objective_aggression(main)

	var margin: float = hold_margin_base
	if aggression < 1.0:
		margin += (1.0 - aggression) * 2.0

	match role:
		"defense":
			margin += hold_margin_defense_role
		"support":
			margin += hold_margin_support_role
		"offense":
			margin += hold_margin_offense_role
		_:
			pass

	return move_score < (stay_score - margin)


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
	var grid_node: Node = _get_child_or_prop(main, "grid")
	if grid_node != null and grid_node.has_method("get_move_cost"):
		move_cost = int(grid_node.get_move_cost(tile))

	var def_bonus: int = 0
	if grid_node != null and grid_node.has_method("get_defense_bonus"):
		def_bonus = int(grid_node.get_defense_bonus(tile))

	var hazard: float = 0.0
	var score: float = float(d) + float(move_cost) * e_move_cost_weight + hazard * hazard_weight

	if prefer_threat_tiles and d <= attack_range:
		score -= e_threat_bonus

	score -= float(def_bonus) * e_defense_weight
	return score


func _enemy_can_step_to(main: Node, enemy: Node, tile: Vector2i) -> bool:
	var grid_node: Node = _get_child_or_prop(main, "grid")
	if grid_node != null and grid_node.has_method("is_walkable"):
		if not bool(grid_node.is_walkable(tile)):
			return false

	if main != null and main.has_method("_get_unit_at_tile"):
		var occ = main._get_unit_at_tile(tile)
		if occ != null and occ != enemy:
			return false

	if main != null and main.has_method("_get_terrain_effect_at_tile"):
		var eff = main._get_terrain_effect_at_tile(tile)
		if eff != null and _has_prop(eff, "blocks_movement") and bool(eff.get("blocks_movement")):
			return false

	return true


func _get_move_budget(enemy: Node) -> int:
	var bonus: int = 0
	if StatusManager != null and StatusManager.has_method("get_move_bonus"):
		bonus = int(StatusManager.get_move_bonus(enemy))

	var total: int = _get_int(enemy, "move_range", 0) + bonus
	if total < 0:
		total = 0
	return total


func _move_enemy_to_tile(main: Node, enemy: Node, tile: Vector2i) -> void:
	var old_tile: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)

	# exit effects immediately
	if main != null and main.has_method("_get_terrain_effect_at_tile"):
		var old_eff = main._get_terrain_effect_at_tile(old_tile)
		if old_eff != null and old_eff.has_method("on_unit_exit"):
			old_eff.on_unit_exit(enemy)

	# update logical position immediately (so occupancy/pathing stays correct)
	enemy.set("grid_position", tile)

	var grid_node: Node = _get_child_or_prop(main, "grid")
	if grid_node != null and grid_node.has_method("tile_to_world") and enemy is Node2D:
		var n2 := enemy as Node2D
		var target_pos: Vector2 = grid_node.tile_to_world(tile)

		# ✅ tween movement (duration tweakable)
		var tween := n2.create_tween()
		tween.tween_property(n2, "global_position", target_pos, 0.18)\
			.set_trans(Tween.TRANS_SINE)\
			.set_ease(Tween.EASE_IN_OUT)

		await tween.finished

	# enter effects after arriving
	if main != null and main.has_method("_get_terrain_effect_at_tile"):
		var new_eff = main._get_terrain_effect_at_tile(tile)
		if new_eff != null and new_eff.has_method("on_unit_enter"):
			new_eff.on_unit_enter(enemy)



# -----------------------------
# Targeting helpers
# -----------------------------
func _find_closest_player(enemy: Node, players: Array) -> Node:
	var closest: Node = null
	var best_dist: int = 999999

	var enemy_tile: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)

	for p in players:
		if p == null or not is_instance_valid(p):
			continue
		if _get_int(p, "hp", 0) <= 0:
			continue

		var d: int = _distance(enemy_tile, _get_v2i(p, "grid_position", Vector2i.ZERO))
		if d < best_dist:
			best_dist = d
			closest = p

	return closest


func _distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


# -----------------------------
# Safe property helpers (Godot 4)
# -----------------------------
func _has_prop(obj: Object, prop_name: String) -> bool:
	if obj == null:
		return false
	for p in obj.get_property_list():
		if String(p.name) == prop_name:
			return true
	return false


func _get_int(obj: Object, prop: String, fallback: int) -> int:
	if obj == null:
		return fallback
	if _has_prop(obj, prop):
		return int(obj.get(prop))
	return fallback


func _get_v2i(obj: Object, prop: String, fallback: Vector2i) -> Vector2i:
	if obj == null:
		return fallback
	if _has_prop(obj, prop):
		return obj.get(prop) as Vector2i
	return fallback


func _get_child_or_prop(obj: Object, name: String) -> Node:
	# Works if main has a member variable OR a child node named "Grid"/"CombatManager" etc.
	if obj == null:
		return null

	# Property
	if _has_prop(obj, name):
		var v = obj.get(name)
		if v is Node:
			return v

	# Child node
	if obj is Node:
		var n := obj as Node
		if n.has_node(name):
			return n.get_node(name) as Node

	return null

#HELPER  FOR SIGNAL WAITNG
func _await_signal_for_unit(emitter: Object, signal_name: StringName, unit: Object) -> void:
	if emitter == null:
		return
	while true:
		var emitted = await emitter.get(signal_name)
		var first = emitted
		if emitted is Array and emitted.size() > 0:
			first = emitted[0]
		if first == unit:
			return

#SKILL INTENT HELPER
func _set_intent_skill(enemy: Node, skill) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if skill == null:
		if enemy.has_meta("intent_skill"):
			enemy.remove_meta("intent_skill")
	else:
		enemy.set_meta("intent_skill", skill)

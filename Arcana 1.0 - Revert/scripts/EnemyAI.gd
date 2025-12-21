extends Node
class_name EnemyAI

# -----------------------------
# AI Debug
# -----------------------------
@export var ai_debug_enabled: bool = true
@export var ai_debug_print: bool = true # if true, prints debug lines each time action is chosen

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

# Buff casting distance gating (prevents buffing from across the map)
@export var buff_cast_min_player_distance: int = 6  # only cast buffs if within this manhattan distance
@export var buff_cast_when_rooted: bool = true      # if can't move, allow buff regardless of distance

class AIContext:
	var main: Node
	var enemy: Node
	var players: Array

	var enemy_tile: Vector2i
	var nearest_player: Node
	var nearest_player_tile: Vector2i
	var nearest_player_dist: int

	var attack_range: int
	var move_budget: int

	var cannot_move: bool
	var cannot_cast: bool

	var role: String
	var aggression: float
	var effective_weights: Dictionary

	var arcana_enabled: bool
	var opening_priority: StringName
	var goal: StringName
	var sentry_leash_distance: int
	var sentry_hold_margin_bonus: float
	var skirmisher_avoid_adjacent_penalty: float
	var skirmisher_prefer_max_range_bonus: float
	var skirmisher_hold_margin_reduction: float


func _build_ai_context(main: Node, enemy: Node, players: Array) -> AIContext:
	var ctx := AIContext.new()
	ctx.main = main
	ctx.enemy = enemy
	ctx.players = players
	ctx.enemy_tile = _get_v2i(enemy, "grid_position", Vector2i.ZERO)

	ctx.nearest_player = _find_closest_player(enemy, players)
	if ctx.nearest_player != null and is_instance_valid(ctx.nearest_player):
		ctx.nearest_player_tile = _get_v2i(ctx.nearest_player, "grid_position", Vector2i.ZERO)
		ctx.nearest_player_dist = _distance(ctx.enemy_tile, ctx.nearest_player_tile)
	else:
		ctx.nearest_player_tile = Vector2i.ZERO
		ctx.nearest_player_dist = 999999

	ctx.attack_range = _get_int(enemy, "attack_range", 1)
	ctx.move_budget = _get_move_budget(enemy)

	ctx.cannot_move = _unit_cannot_move(enemy)
	ctx.cannot_cast = _unit_cannot_cast(enemy)

	ctx.role = _get_ai_role(enemy)
	ctx.aggression = _get_objective_aggression(main)
	ctx.effective_weights = _get_effective_weights(main, enemy)

	ctx.arcana_enabled = _effective_arcana_intent_enabled(enemy)
	var p := _get_ai_profile(enemy)
	print("[AICTX] profile=", p.resource_path if p != null else "NULL", " enemy=", enemy.name)
	ctx.opening_priority = _effective_opening_priority(enemy)
	ctx.goal = _effective_goal(enemy)
	ctx.sentry_leash_distance = _effective_sentry_leash_distance(enemy)
	ctx.sentry_hold_margin_bonus = _effective_sentry_hold_margin_bonus(enemy)
	ctx.skirmisher_avoid_adjacent_penalty = _effective_skirmisher_avoid_adjacent_penalty(enemy)
	ctx.skirmisher_prefer_max_range_bonus = _effective_skirmisher_prefer_max_range_bonus(enemy)
	ctx.skirmisher_hold_margin_reduction = _effective_skirmisher_hold_margin_reduction(enemy)



	return ctx

#STATUS INFLUENCE
func _has_status(unit: Node, key: StringName) -> bool:
	if unit == null:
		return false
	if StatusManager == null:
		return false
	if StatusManager.has_method("has_status"):
		return bool(StatusManager.has_status(unit, key))
	return false

func _unit_cannot_move(unit: Node) -> bool:
	# Existing flag path
	if StatusManager != null and StatusManager.has_method("unit_has_flag"):
		if bool(StatusManager.unit_has_flag(unit, "prevent_move")):
			return true

	# New: explicit status keys
	if _has_status(unit, &"shocked"):
		return true
	if _has_status(unit, &"frozen"):
		return true

	return false

func _unit_cannot_cast(unit: Node) -> bool:
	if StatusManager != null and StatusManager.has_method("unit_has_flag"):
		return bool(StatusManager.unit_has_flag(unit, "prevent_arcana"))
	return false

func _unit_is_chilled(unit: Node) -> bool:
	return _has_status(unit, &"chilled")

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

	var ctx: AIContext = _build_ai_context(main, enemy, players)

	var target: Node = ctx.nearest_player
	if target == null or not is_instance_valid(target):
		return

	_tick_ai_cooldowns(enemy)

	if ai_debug_enabled:
		_ai_debug_reset(enemy)
		_ai_debug_set(enemy, &"opening_priority", ctx.opening_priority)
		_ai_debug_set(enemy, &"goal", ctx.goal)
		_ai_debug_set(enemy, &"nearest_dist", ctx.nearest_player_dist)
		_ai_debug_set(enemy, &"attack_range", ctx.attack_range)
		_ai_debug_set(enemy, &"cannot_move", ctx.cannot_move)
		_ai_debug_set(enemy, &"cannot_cast", ctx.cannot_cast)
		_ai_debug_line(enemy, "prio=%s goal=%s dist=%d ar=%d" % [
			String(ctx.opening_priority), String(ctx.goal), ctx.nearest_player_dist, ctx.attack_range
		])

	var prio: StringName = ctx.opening_priority

	match prio:
		&"attack_first":
			if await _attempt_attack(ctx, target):
				return
			if await _attempt_cast(ctx):
				return
			if await _attempt_move(ctx, target):
				return
			return

		&"move_first":
			if await _attempt_move(ctx, target):
				return
			if await _attempt_cast(ctx):
				return
			if await _attempt_attack(ctx, target):
				return
			return

		&"wait_first":
			# Sentry behavior: only attack if already in range, otherwise do nothing.
			if await _attempt_attack(ctx, target):
				return
			return

		_:
			# &"cast_first" default (current behavior)
			if await _attempt_cast(ctx):
				return
			if await _attempt_attack(ctx, target):
				return
			if await _attempt_move(ctx, target):
				return
			return



func _wait_skill_finished_safe(main: Node, enemy: Node, timeout_sec: float = 0.6) -> void:
	if main == null or enemy == null or not is_instance_valid(enemy):
		return

	var cm: Node = _get_child_or_prop(main, "combat_manager")
	if cm == null:
		# Fallback: just give a tiny pacing delay
		await get_tree().create_timer(0.15).timeout
		return

	# If the signal doesn't exist, also fallback.
	if not cm.has_signal("skill_sequence_finished"):
		await get_tree().create_timer(0.15).timeout
		return

	var done: bool = false

	# One-shot listener: marks done only when THIS enemy is the caster
	var cb := func(emitted):
		var caster = emitted
		if emitted is Array and emitted.size() > 0:
			caster = emitted[0]
		if caster == enemy:
			done = true

	cm.skill_sequence_finished.connect(cb, CONNECT_ONE_SHOT)

	var t := get_tree().create_timer(timeout_sec)
	while true:
		if done:
			return
		if t.time_left <= 0.0:
			print("[AI] skill_sequence_finished TIMEOUT for:", enemy.name)
			return
		await get_tree().process_frame

func get_intent(main: Node, enemy: Node, players: Array) -> String:
	if enemy == null or not is_instance_valid(enemy) or _get_int(enemy, "hp", 0) <= 0:
		return ""
	if players.is_empty():
		return ""

	var ctx: AIContext = _build_ai_context(main, enemy, players)

	# Clear intent payload by default
	_set_intent_skill(enemy, null)

	var prio: StringName = ctx.opening_priority

	match prio:
		&"attack_first":
			if _can_attack_now(ctx):
				return "attack"
			if ctx.arcana_enabled:
				var cast_plan_a: Dictionary = _choose_cast_plan_ctx(ctx)
				if not cast_plan_a.is_empty():
					if cast_plan_a.has("skill"):
						_set_intent_skill(enemy, cast_plan_a["skill"])
					return "cast"
			return _intent_move_or_wait(ctx)

		&"move_first":
			var intent_m: String = _intent_move_or_wait(ctx)
			if intent_m == "move":
				return "move"
			if ctx.arcana_enabled:
				var cast_plan_m: Dictionary = _choose_cast_plan_ctx(ctx)
				if not cast_plan_m.is_empty():
					if cast_plan_m.has("skill"):
						_set_intent_skill(enemy, cast_plan_m["skill"])
					return "cast"
			if _can_attack_now(ctx):
				return "attack"
			return "wait"

		&"wait_first":
			if _can_attack_now(ctx):
				return "attack"
			return "wait"

		_:
			# &"cast_first" default (current behavior)
			if ctx.arcana_enabled:
				var cast_plan: Dictionary = _choose_cast_plan_ctx(ctx)
				if not cast_plan.is_empty():
					if cast_plan.has("skill"):
						_set_intent_skill(enemy, cast_plan["skill"])
					return "cast"

			if _can_attack_now(ctx):
				return "attack"

			return _intent_move_or_wait(ctx)

func _can_attack_now(ctx: AIContext) -> bool:
	if ctx == null:
		return false
	if ctx.nearest_player == null or not is_instance_valid(ctx.nearest_player):
		return false
	return ctx.nearest_player_dist <= ctx.attack_range


func _intent_move_or_wait(ctx: AIContext) -> String:
	if ctx == null:
		return "wait"
	if ctx.cannot_move:
		return "wait"

	var enemy_tile: Vector2i = ctx.enemy_tile
	var target: Node = ctx.nearest_player
	if target == null or not is_instance_valid(target):
		return "wait"

	var dest: Vector2i = _choose_greedy_destination_ctx(ctx, target)
	if dest != enemy_tile:
		if not _should_move_ctx(ctx, target, dest):
			return "wait"
		return "move"

	return "wait"


func _attempt_cast(ctx: AIContext) -> bool:
	if ctx == null:
		return false
	var enemy: Node = ctx.enemy
	if enemy == null or not is_instance_valid(enemy):
		return false

	if not ctx.arcana_enabled:
		_ai_debug_line(enemy, "cast? arcana disabled")
		return false
	if ctx.cannot_cast:
		_ai_debug_line(enemy, "cast? cannot_cast=true")
		return false

	var plan: Dictionary = _choose_cast_plan_ctx(ctx)
	if plan.is_empty():
		_ai_debug_line(enemy, "cast? no valid plan")
		return false

	var skill = plan.get("skill", null)
	var skill_name: String = ""
	if skill != null and _has_prop(skill, "name"):
		skill_name = String(skill.get("name"))

	var score_val: float = float(plan.get("score", 0.0))

	_ai_debug_action(enemy, &"cast")
	_ai_debug_set(enemy, &"cast_skill", skill_name)
	_ai_debug_set(enemy, &"cast_score", score_val)
	_ai_debug_line(enemy, "cast? picked=%s score=%.2f" % [skill_name, score_val])

	await _execute_cast_plan(ctx.main, enemy, plan)
	return true



func _attempt_attack(ctx: AIContext, target: Node) -> bool:
	if ctx == null:
		return false
	var enemy: Node = ctx.enemy
	if enemy == null or not is_instance_valid(enemy):
		return false
	if target == null or not is_instance_valid(target):
		_ai_debug_line(enemy, "attack? no target")
		return false

	var can_attack: bool = _can_attack_now(ctx)
	_ai_debug_line(enemy, "attack? dist=%d range=%d -> %s" % [
		ctx.nearest_player_dist, ctx.attack_range, "yes" if can_attack else "no"
	])

	if not can_attack:
		return false

	var cm: Node = _get_child_or_prop(ctx.main, "combat_manager")
	if cm != null and cm.has_method("perform_attack"):
		_ai_debug_action(enemy, &"attack")
		_ai_debug_set(enemy, &"attack_target", target.name)

		print("[AI] %s BASIC ATTACK start -> %s" % [enemy.name, target.name])
		cm.perform_attack(enemy, target)

		if cm.has_signal("attack_sequence_finished"):
			var timeout := get_tree().create_timer(1.0)
			while true:
				var emitted_attacker = await cm.attack_sequence_finished
				if emitted_attacker == enemy:
					print("[AI] %s BASIC ATTACK end (signal)" % enemy.name)
					break
				if timeout.time_left <= 0.0:
					print("[AI] %s BASIC ATTACK end (TIMEOUT FALLBACK)" % enemy.name)
					break
		else:
			await get_tree().create_timer(0.25).timeout

		return true

	_ai_debug_line(enemy, "attack? combat_manager missing perform_attack")
	return false



func _attempt_move(ctx: AIContext, target: Node) -> bool:
	if ctx == null:
		return false
	var enemy: Node = ctx.enemy
	if enemy == null or not is_instance_valid(enemy):
		return false

	if ctx.cannot_move:
		_ai_debug_line(enemy, "move? cannot_move=true")
		return false
	if target == null or not is_instance_valid(target):
		_ai_debug_line(enemy, "move? no target")
		return false

	# Goal: Sentry leash gate
	if ctx.goal == &"sentry":
		if ctx.nearest_player_dist > ctx.sentry_leash_distance:
			_ai_debug_line(enemy, "move? blocked by sentry leash (dist %d > %d)" % [
				ctx.nearest_player_dist, ctx.sentry_leash_distance
			])
			return false

	var final_tile: Vector2i = _choose_greedy_destination_ctx(ctx, target)
	if final_tile == ctx.enemy_tile:
		_ai_debug_line(enemy, "move? dest==current")
		return false

	# Log should-move decision details (function logs too—this is the high-level gate)
	var ok: bool = _should_move_ctx(ctx, target, final_tile)
	_ai_debug_line(enemy, "move? dest=%s -> %s" % [str(final_tile), "yes" if ok else "no"])
	if not ok:
		return false

	_ai_debug_action(enemy, &"move")
	_ai_debug_set(enemy, &"move_dest", final_tile)

	_move_enemy_to_tile(ctx.main, enemy, final_tile)
	return true





# -----------------------------
# Casting (Arcana) planning
# -----------------------------
func _choose_cast_plan(enemy: Node, players: Array) -> Dictionary:
	# Keep signature for compatibility; internally use context.
	if enemy == null or not is_instance_valid(enemy):
		return {}
	if players == null or players.is_empty():
		return {}

	# _choose_cast_plan never needed main; context builder accepts null.
	var ctx: AIContext = _build_ai_context(null, enemy, players)
	return _choose_cast_plan_ctx(ctx)

func _pick_cast_target(enemy: Node, players: Array, skill) -> Dictionary:
	var best_target: Node = null
	var best_score: float = -999999.0

	var enemy_tile: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)

	for p in players:
		if p == null or not is_instance_valid(p):
			continue
		if _get_int(p, "hp", 0) <= 0:
			continue

		var p_tile: Vector2i = _get_v2i(p, "grid_position", Vector2i.ZERO)
		var d: int = _distance(enemy_tile, p_tile)

		var cast_range: int = _get_int(skill, "cast_range", 0)
		if d > cast_range:
			continue

		# Base: prefer closer targets slightly
		var score: float = 10.0 - float(d)

		# Reaction visibility: lightning prefers wet targets (Wet consumed -> Shocked in your reactions)
		if _skill_has_tag(skill, &"lightning") and _has_status(p, &"wet"):
			score += 6.0

		# (Optional) Ice prefers wet targets too if you want to show Wet->Chilled more often:
		# if _skill_has_tag(skill, &"ice") and _has_status(p, &"wet"):
		#     score += 6.0

		# Prefer finishing low HP targets slightly (readability / threat)
		var hp: int = _get_int(p, "hp", 0)
		var max_hp: int = _get_int(p, "max_hp", 0)
		
		# DONT PICK TARGETS ALREADY BUFFED BY THE SAME SKILL
		if _is_buff_skill(skill) and _unit_has_buff_from_skill(p, skill):
			continue

		if _is_heal_skill(skill):
			if max_hp <= 0:
				continue
			if max_hp > 0:
				var missing: int = max_hp - hp
				if missing <= 0:
					continue # don't heal full HP
				score += float(missing) * 0.35 # prefer more missing HP

		if not _is_heal_skill(skill) and hp > 0:
			score += clamp(6.0 - float(hp) * 0.25, 0.0, 6.0)


		if score > best_score:
			best_score = score
			best_target = p

	if best_target == null:
		return {}

	var best_target_tile: Vector2i = _get_v2i(best_target, "grid_position", Vector2i.ZERO)
	var aoe_radius: int = _get_int(skill, "aoe_radius", 0)

	if aoe_radius > 0:
		return {
			"skill": skill,
			"target_unit": best_target,
			"center_tile": best_target_tile
		}

	return {
		"skill": skill,
		"target_unit": best_target,
		"center_tile": best_target_tile,
		"score": best_score
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

	var aoe_radius: int = _get_int(skill, "aoe_radius", 0)

	# --- AoE skills: use CombatManager ---
	if aoe_radius > 0:
		var cm: Node = _get_child_or_prop(main, "combat_manager")
		if cm != null and cm.has_method("use_skill"):
			cm.use_skill(enemy, skill, center_tile)

			# ✅ Never hang
			await _wait_skill_finished_safe(main, enemy, 0.6)

			if _is_buff_skill(skill):
				_apply_buff_cooldown_after_cast(enemy, skill)
			return

	# --- Single-target skills: use SkillSystem ---
	if plan.has("target_unit"):
		var target_unit: Node = plan["target_unit"]
		var ss: Node = _get_child_or_prop(main, "skill_system")
		if ss != null and ss.has_method("execute_skill_on_target"):
			ss.execute_skill_on_target(enemy, target_unit, skill)

			# ✅ Never hang
			await _wait_skill_finished_safe(main, enemy, 0.6)

			if _is_buff_skill(skill):
				_apply_buff_cooldown_after_cast(enemy, skill)
			return

	# --- Fallback: basic attack if CombatManager exists ---
	var cm2: Node = _get_child_or_prop(main, "combat_manager")
	if cm2 != null and cm2.has_method("perform_attack") and plan.has("target_unit"):
		cm2.perform_attack(enemy, plan["target_unit"])

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
	var aggression: float = _get_objective_aggression(main)

	# Start with role weights (existing behavior)
	var w: Dictionary = _get_profile_weights(role)

	# If an AIProfile is assigned, override base weights from it
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		w["move_cost_weight"] = float(p.move_cost_weight)
		w["defense_weight"] = float(p.defense_weight)
		w["threat_bonus"] = float(p.threat_bonus)

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

func _get_ai_profile(enemy: Node) -> AIProfile:
	if enemy == null or not is_instance_valid(enemy):
		return null

	# Prefer UnitData.ai_profile if present
	if _has_prop(enemy, "unit_data"):
		var ud = enemy.get("unit_data")
		if ud != null and is_instance_valid(ud) and ("ai_profile" in ud):
			var p = ud.ai_profile
			if p != null:
				return p as AIProfile

	return null


func _effective_arcana_intent_enabled(enemy: Node) -> bool:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return bool(p.arcana_intent_enabled)
	return arcana_intent_enabled
	
func _effective_opening_priority(enemy: Node) -> StringName:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return p.opening_priority
	return &"cast_first"


func _effective_buff_cast_min_player_distance(enemy: Node) -> int:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return int(p.buff_cast_min_player_distance)
	return buff_cast_min_player_distance


func _effective_buff_cast_when_rooted(enemy: Node) -> bool:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return bool(p.buff_cast_when_rooted)
	return buff_cast_when_rooted


func _effective_hold_margin_base(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.hold_margin_base)
	return hold_margin_base


func _effective_hold_margin_defense_role(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.hold_margin_defense_role)
	return hold_margin_defense_role


func _effective_hold_margin_support_role(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.hold_margin_support_role)
	return hold_margin_support_role


func _effective_hold_margin_offense_role(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.hold_margin_offense_role)
	return hold_margin_offense_role

func _effective_goal(enemy: Node) -> StringName:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return p.goal
	return &"none"


func _effective_sentry_leash_distance(enemy: Node) -> int:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return int(p.sentry_leash_distance)
	return 8


func _effective_sentry_hold_margin_bonus(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.sentry_hold_margin_bonus)
	return 1.25

func _effective_skirmisher_avoid_adjacent_penalty(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.skirmisher_avoid_adjacent_penalty)
	return 3.0


func _effective_skirmisher_prefer_max_range_bonus(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.skirmisher_prefer_max_range_bonus)
	return 1.5


func _effective_skirmisher_hold_margin_reduction(enemy: Node) -> float:
	var p: AIProfile = _get_ai_profile(enemy)
	if p != null:
		return float(p.skirmisher_hold_margin_reduction)
	return 0.75

# -----------------------------
# Greedy multi-tile movement
# -----------------------------
func _choose_greedy_destination(main: Node, enemy: Node, target: Node) -> Vector2i:
	if enemy == null or not is_instance_valid(enemy):
		return Vector2i.ZERO
	if target == null or not is_instance_valid(target):
		return _get_v2i(enemy, "grid_position", Vector2i.ZERO)

	var ctx: AIContext = _build_ai_context(main, enemy, [])
	return _choose_greedy_destination_ctx(ctx, target)



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
		
			# --- Fallback: if we couldn't find a good scored neighbor, force a simple "chase step"
	# This prevents stalling around mountains/water when a detour is needed.
	if best == current:
		var best_d: int = _distance(current, target_pos)
		var chase_best: Vector2i = current

		for dir2 in dirs:
			var n2: Vector2i = current + dir2
			if not _enemy_can_step_to(main, enemy, n2):
				continue

			var cost2: int = 1
			var grid_node2: Node = _get_child_or_prop(main, "grid")
			if grid_node2 != null and grid_node2.has_method("get_move_cost"):
				cost2 = int(grid_node2.get_move_cost(n2))
			if cost2 > budget:
				continue

			var d2: int = _distance(n2, target_pos)
			if d2 < best_d:
				best_d = d2
				chase_best = n2

		if chase_best != current:
			return chase_best

	return best


func _should_move(main: Node, enemy: Node, target: Node, dest: Vector2i) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return false
	if target == null or not is_instance_valid(target):
		return false

	var ctx: AIContext = _build_ai_context(main, enemy, [])
	return _should_move_ctx(ctx, target, dest)



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

func _min_distance_to_players(enemy: Node, players: Array) -> int:
	var enemy_tile: Vector2i = _get_v2i(enemy, "grid_position", Vector2i.ZERO)
	var best: int = 999999

	for p in players:
		if p == null or not is_instance_valid(p):
			continue
		if _get_int(p, "hp", 0) <= 0:
			continue
		var p_tile: Vector2i = _get_v2i(p, "grid_position", Vector2i.ZERO)
		var d: int = _distance(enemy_tile, p_tile)
		if d < best:
			best = d

	return best

func _skill_priority_bias(skill) -> float:
	# Small biases so enemies feel smarter without huge refactors.
	# Higher = more likely to be chosen.
	if skill == null:
		return 0.0

	if _is_heal_skill(skill):
		return 4.0
	if _is_damage_skill(skill):
		return 2.0
	if _is_buff_skill(skill):
		return 1.0

	# debuffs / others
	return 0.5

func _distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

#SKILL TAG HELPER
func _skill_has_tag(skill, tag: StringName) -> bool:
	if skill == null:
		return false
	# Skills may store tags as Array[StringName] (your Skill.gd does)
	if _has_prop(skill, "tags"):
		var tags: Array = skill.get("tags")
		for t in tags:
			if t == tag:
				return true
	return false

#HEALER/BUFF HELPERS
func _is_heal_skill(skill) -> bool:
	if skill == null:
		return false
	# Prefer effect_type if present
	if _has_prop(skill, "effect_type"):
		# Skill.EffectType.HEAL == 1 per your enum ordering in Skill.gd
		# (DAMAGE=0, HEAL=1, BUFF=2, DEBUFF=3, TERRAIN=4)
		if int(skill.get("effect_type")) == 1:
			return true
	# Backwards-compatible flag
	if _has_prop(skill, "is_heal") and bool(skill.get("is_heal")):
		return true
	return false

func _get_enemy_allies(enemy: Node) -> Array:
	var allies: Array = []
	if enemy == null or not is_instance_valid(enemy):
		return allies

	# Enemy units group is already used elsewhere in your project
	var group_allies := get_tree().get_nodes_in_group("enemy_units")
	for a in group_allies:
		if a == null or not is_instance_valid(a):
			continue
		if _get_int(a, "hp", 0) <= 0:
			continue
		allies.append(a)

	return allies

func _is_buff_skill(skill) -> bool:
	if skill == null:
		return false
	if _has_prop(skill, "effect_type"):
		return int(skill.get("effect_type")) == 2 # Skill.EffectType.BUFF
	return false

func _is_damage_skill(skill) -> bool:
	if skill == null:
		return false
	if _has_prop(skill, "effect_type"):
		return int(skill.get("effect_type")) == 0 # Skill.EffectType.DAMAGE
	return false


func _unit_has_buff_from_skill(unit: Node, skill) -> bool:
	if unit == null or not is_instance_valid(unit) or skill == null:
		return false
	if StatusManager == null or not StatusManager.has_method("get_statuses_for_unit"):
		return false

	var statuses: Array = StatusManager.get_statuses_for_unit(unit)
	for st in statuses:
		if typeof(st) != TYPE_DICTIONARY:
			continue
		var s = st.get("skill", null)
		if s == null:
			continue

		# Prefer reference equality
		if s == skill:
			return true

		# Fallback: match by name (safer across duplicated resources)
		if _has_prop(s, "name") and _has_prop(skill, "name"):
			if String(s.get("name")) == String(skill.get("name")):
				return true

	return false

func _skill_id(skill) -> String:
	# Stable key: resource_path if available, otherwise name
	if skill == null:
		return ""
	if _has_prop(skill, "resource_path"):
		var rp: String = String(skill.get("resource_path"))
		if rp != "":
			return rp
	if _has_prop(skill, "name"):
		return String(skill.get("name"))
	return str(skill)


func _get_ai_cooldowns(enemy: Node) -> Dictionary:
	if enemy == null:
		return {}
	if enemy.has_meta("ai_cooldowns"):
		var d = enemy.get_meta("ai_cooldowns")
		if typeof(d) == TYPE_DICTIONARY:
			return d
	var fresh: Dictionary = {}
	enemy.set_meta("ai_cooldowns", fresh)
	return fresh


func _tick_ai_cooldowns(enemy: Node) -> void:
	var cds: Dictionary = _get_ai_cooldowns(enemy)
	if cds.is_empty():
		return

	var keys := cds.keys()
	for k in keys:
		var v = cds[k]
		if typeof(v) != TYPE_INT:
			continue
		var nv: int = int(v) - 1
		if nv <= 0:
			cds.erase(k)
		else:
			cds[k] = nv
	enemy.set_meta("ai_cooldowns", cds)


func _get_skill_cooldown(enemy: Node, skill) -> int:
	var cds: Dictionary = _get_ai_cooldowns(enemy)
	var key: String = _skill_id(skill)
	if key == "":
		return 0
	if cds.has(key):
		return int(cds[key])
	return 0


func _set_skill_cooldown(enemy: Node, skill, turns: int) -> void:
	if enemy == null or skill == null:
		return
	var key: String = _skill_id(skill)
	if key == "":
		return
	var cds: Dictionary = _get_ai_cooldowns(enemy)
	cds[key] = max(1, int(turns))
	enemy.set_meta("ai_cooldowns", cds)

# Buff cleaner HELPER to avoid duplicate code
func _apply_buff_cooldown_after_cast(enemy: Node, skill) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if skill == null:
		return
	if not _is_buff_skill(skill):
		return

	var cd: int = 2
	if _has_prop(skill, "duration_turns"):
		cd = max(2, int(skill.get("duration_turns")))

	_set_skill_cooldown(enemy, skill, cd)

#DEBUG HELPER FUNCTIONS
func _ai_debug_reset(enemy: Node) -> void:
	if not ai_debug_enabled:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	enemy.set_meta("ai_debug", {})
	enemy.set_meta("ai_debug_lines", [])


func _ai_debug_set(enemy: Node, key: StringName, value) -> void:
	if not ai_debug_enabled:
		return
	if enemy == null or not is_instance_valid(enemy):
		return
	if not enemy.has_meta("ai_debug"):
		enemy.set_meta("ai_debug", {})
	var d = enemy.get_meta("ai_debug")
	if typeof(d) != TYPE_DICTIONARY:
		d = {}
	d[key] = value
	enemy.set_meta("ai_debug", d)


func _ai_debug_line(enemy: Node, text: String) -> void:
	if not ai_debug_enabled:
		return
	if enemy == null or not is_instance_valid(enemy):
		return

	if not enemy.has_meta("ai_debug_lines"):
		enemy.set_meta("ai_debug_lines", [])

	var arr = enemy.get_meta("ai_debug_lines")
	if typeof(arr) != TYPE_ARRAY:
		arr = []

	arr.append(text)
	enemy.set_meta("ai_debug_lines", arr)

	if ai_debug_print:
		print("[AIDBG] ", enemy.name, " | ", text)


func _ai_debug_action(enemy: Node, action: StringName) -> void:
	_ai_debug_set(enemy, &"action", action)
	_ai_debug_line(enemy, "ACTION=" + String(action))

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

#SKILL WAIT HELPER
func _await_skill_finished_or_timeout(main: Node, enemy: Node, timeout_sec: float = 0.8) -> void:
	# Waits for CombatManager.skill_sequence_finished for this enemy, but never hangs forever.
	if main == null or enemy == null:
		return

	var cm_wait: Node = _get_child_or_prop(main, "combat_manager")
	if cm_wait == null:
		await get_tree().create_timer(0.15).timeout
		return

	if not cm_wait.has_signal("skill_sequence_finished"):
		await get_tree().create_timer(0.15).timeout
		return

	var timeout := get_tree().create_timer(timeout_sec)

	while true:
		# If the timer is up, bail out safely.
		if timeout.time_left <= 0.0:
			print("[AI] skill_sequence_finished TIMEOUT for:", enemy.name)
			return

		# Wait one frame while also listening for the signal.
		# This avoids being stuck inside a signal wait forever if it never fires.
		await get_tree().process_frame

		# Non-blocking poll: check if any signal already queued this frame (not available),
		# so we instead do a blocking wait but with a short timer slice.
		var slice := get_tree().create_timer(0.05)
		var emitted = await cm_wait.skill_sequence_finished if cm_wait != null else null

		var caster = emitted
		if emitted is Array and emitted.size() > 0:
			caster = emitted[0]

		if caster == enemy:
			return

func _choose_cast_plan_ctx(ctx: AIContext) -> Dictionary:
	# Returns {} if no cast. Otherwise:
	# { "skill": Skill, "target_unit": Node, "center_tile": Vector2i, "score": float }

	if ctx == null:
		return {}
	var enemy: Node = ctx.enemy
	if enemy == null or not is_instance_valid(enemy):
		return {}
	if ctx.cannot_cast:
		return {}

	if not _has_prop(enemy, "skills"):
		return {}
	var skills: Array = enemy.get("skills")
	if skills == null or skills.is_empty():
		return {}

	var best_pick: Dictionary = {}
	var best_value: float = -999999.0

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
		if _has_prop(skill, "effect_type") and int(skill.get("effect_type")) == 4:
			continue

		# --- Buff distance gating ---
		# Only cast buffs when we're close enough to the players to matter.
		if _is_buff_skill(skill):
			var buff_min_dist: int = _effective_buff_cast_min_player_distance(enemy)
			var buff_when_rooted: bool = _effective_buff_cast_when_rooted(enemy)

			var far_ok: bool = false
			if buff_when_rooted and ctx.cannot_move:
				far_ok = true

			if not far_ok:
				# Use cached nearest distance (Stage 1)
				var nearest_player_d: int = ctx.nearest_player_dist
				if nearest_player_d > buff_min_dist:
					continue

		# Buff cooldown gate (AI-only)
		if _is_buff_skill(skill):
			if _get_skill_cooldown(enemy, skill) > 0:
				continue

		# -------------------------
		# Target pool selection
		# -------------------------
		var target_pool: Array = ctx.players

		if _has_prop(skill, "target_type"):
			var tt: int = int(skill.get("target_type"))
			match tt:
				2: # ALLY_UNITS
					target_pool = _get_enemy_allies(enemy)

				3: # SELF
					target_pool = [enemy]

				1: # ALL_UNITS
					# Enemies should not friendly-fire with DAMAGE skills by default.
					if _is_damage_skill(skill):
						target_pool = ctx.players
					else:
						target_pool = []
						target_pool.append_array(ctx.players)
						target_pool.append_array(_get_enemy_allies(enemy))

				0: # ENEMY_UNITS
					target_pool = ctx.players

				_:
					target_pool = ctx.players

		# Healing should never target players even if misconfigured
		if _is_heal_skill(skill):
			target_pool = _get_enemy_allies(enemy)

		# -------------------------
		# Prevent buff spam on already-buffed targets
		# (only works for buffs that create status entries)
		# -------------------------
		if _is_buff_skill(skill):
			var any_valid: bool = false
			for t in target_pool:
				if t == null or not is_instance_valid(t):
					continue
				if _get_int(t, "hp", 0) <= 0:
					continue
				if _unit_has_buff_from_skill(t, skill):
					continue
				any_valid = true
				break
			if not any_valid:
				continue

		# Pick best target for this skill
		var pick: Dictionary = _pick_cast_target(enemy, target_pool, skill)
		if pick.is_empty():
			continue

		# -------------------------
		# Priority ordering
		# -------------------------
		var v: float = 0.0
		if pick.has("score"):
			v = float(pick["score"])

		# Bias by skill type so enemies feel smarter.
		if _is_heal_skill(skill):
			v += 4.0
		elif _is_damage_skill(skill):
			v += 2.0
		elif _is_buff_skill(skill):
			v += 1.0
		else:
			v += 0.5

		if v > best_value:
			best_value = v
			best_pick = pick

	if not best_pick.is_empty():
		return best_pick
	return {}
#MOVEMENT CONTEXT HELPER
func _choose_greedy_destination_ctx(ctx: AIContext, target: Node) -> Vector2i:
	if ctx == null:
		return Vector2i.ZERO
	var enemy: Node = ctx.enemy
	if enemy == null or not is_instance_valid(enemy):
		return Vector2i.ZERO

	var move_points: int = ctx.move_budget
	if move_points <= 0:
		return ctx.enemy_tile

	var w: Dictionary = ctx.effective_weights
	var e_move_cost_weight: float = float(w.get("move_cost_weight", move_cost_weight))
	var e_defense_weight: float = float(w.get("defense_weight", defense_weight))
	var e_threat_bonus: float = float(w.get("threat_bonus", threat_bonus))

	var current: Vector2i = ctx.enemy_tile
	var best_reached: Vector2i = current
	var ar: int = ctx.attack_range

	var target_tile: Vector2i = _get_v2i(target, "grid_position", Vector2i.ZERO)
	var raw_best: float = _tile_score(ctx.main, current, target_tile, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
	var best_score: float = _goal_adjusted_tile_score(ctx, current, target_tile, raw_best)

	var visited: Dictionary = {}
	visited[current] = true

	while move_points > 0:
		var next: Vector2i = _choose_best_neighbor(ctx.main, enemy, current, target_tile, move_points, visited, e_move_cost_weight, e_defense_weight, e_threat_bonus)
		if next == current:
			break

		var cost: int = 1
		var grid_node: Node = _get_child_or_prop(ctx.main, "grid")
		if grid_node != null and grid_node.has_method("get_move_cost"):
			cost = int(grid_node.get_move_cost(next))

		move_points -= cost
		current = next
		visited[current] = true

		var raw_s: float = _tile_score(ctx.main, current, target_tile, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
		var s: float = _goal_adjusted_tile_score(ctx, current, target_tile, raw_s)
		if s < best_score:
			best_score = s
			best_reached = current

	if best_reached == ctx.enemy_tile and current != ctx.enemy_tile:
		best_reached = current

	return best_reached


func _should_move_ctx(ctx: AIContext, target: Node, dest: Vector2i) -> bool:
	if ctx == null:
		return false
	var enemy: Node = ctx.enemy
	if enemy == null or not is_instance_valid(enemy):
		return false

	var w: Dictionary = ctx.effective_weights
	var e_move_cost_weight: float = float(w.get("move_cost_weight", move_cost_weight))
	var e_defense_weight: float = float(w.get("defense_weight", defense_weight))
	var e_threat_bonus: float = float(w.get("threat_bonus", threat_bonus))
	var role: String = String(w.get("role", "offense"))

	var ar: int = ctx.attack_range
	var target_tile: Vector2i = _get_v2i(target, "grid_position", Vector2i.ZERO)

	var raw_stay: float = _tile_score(ctx.main, ctx.enemy_tile, target_tile, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
	var raw_move: float = _tile_score(ctx.main, dest, target_tile, ar, e_move_cost_weight, e_defense_weight, e_threat_bonus)
	var stay_score: float = _goal_adjusted_tile_score(ctx, ctx.enemy_tile, target_tile, raw_stay)
	var move_score: float = _goal_adjusted_tile_score(ctx, dest, target_tile, raw_move)

	var aggression: float = ctx.aggression

	var margin: float = _effective_hold_margin_base(enemy)
	if aggression < 1.0:
		margin += (1.0 - aggression) * 2.0
# Goal: Sentry holds position more aggressively (harder to convince it to move)
	if ctx.goal == &"sentry":
		margin += ctx.sentry_hold_margin_bonus

	# Goal: Skirmisher is more willing to reposition (reduce the "hold" bias)
	if ctx.goal == &"skirmisher":
		margin = max(0.0, margin - ctx.skirmisher_hold_margin_reduction)

	match role:
		"defense":
			margin += _effective_hold_margin_defense_role(enemy)
		"support":
			# Intentionally preserve your current behavior here (uses the exported var)
			margin += _effective_hold_margin_support_role(enemy)
		"offense":
			# Intentionally preserve your current behavior here (uses the exported var)
			margin += _effective_hold_margin_offense_role(enemy)
		_:
			pass

	# Chilled units are less eager to reposition (helps readability, matches theme)
	if _unit_is_chilled(enemy):
		margin += 0.75
	if ai_debug_enabled:
		_ai_debug_set(enemy, &"stay_score", stay_score)
		_ai_debug_set(enemy, &"move_score", move_score)
		_ai_debug_set(enemy, &"hold_margin", margin)
		_ai_debug_line(enemy, "should_move? stay=%.2f move=%.2f margin=%.2f -> %s" % [
			stay_score, move_score, margin, "move" if (move_score < (stay_score - margin)) else "hold"
		])
	return move_score < (stay_score - margin)

func _goal_adjusted_tile_score(ctx: AIContext, tile: Vector2i, target_tile: Vector2i, base_score: float) -> float:
	if ctx == null:
		return base_score

	if ctx.goal != &"skirmisher":
		return base_score

	var dist: int = _distance(tile, target_tile)

	# 1) Avoid ending adjacent (dist 1) unless forced.
	if dist <= 1:
		base_score += ctx.skirmisher_avoid_adjacent_penalty

	# 2) Prefer ideal fighting distance.
	# - Ranged units: prefer max attack range
	# - Melee units: prefer distance 2 (just outside adjacency)
	var desired: int = 2
	if ctx.attack_range > 1:
		desired = ctx.attack_range

	# Bonus when exactly at desired distance; small penalty the farther away we are.
	if dist == desired:
		base_score -= ctx.skirmisher_prefer_max_range_bonus
	else:
		base_score += float(abs(dist - desired)) * 0.25

	return base_score

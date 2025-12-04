extends Node

@export var default_skill_aoe_includes_caster: bool = false  # tweakable

@onready var grid         = $"../Grid"
@onready var turn_manager = $"../TurnManager"
@onready var units_root   = $"../Units"

signal unit_died(unit)
signal unit_attacked(attacker, defender, damage, is_counter)

func perform_attack(attacker, defender, is_counter: bool = false) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	var terrain_def: int = grid.get_defense_bonus(defender.grid_position)
	var raw_damage: int = attacker.atk - (defender.defense + terrain_def)
	var damage: int = max(raw_damage, 0)

	print(attacker.name, " attacks ", defender.name, " for ", damage, " dmg (terrain def +", terrain_def, ")")
	unit_attacked.emit(attacker, defender, damage, is_counter)

	var defender_survived: bool = defender.take_damage(damage)

	if not is_counter:
		attacker.has_acted = true

		if attacker.has_node("Sprite2D"):
			attacker.get_node("Sprite2D").modulate = Color.WHITE

		# Counterattack
		if defender_survived and _is_in_attack_range(defender, attacker):
			print(defender.name, " counterattacks!")
			perform_attack(defender, attacker, true)

		# Auto-end turn if all player units are done
		if _all_player_units_have_acted():
			turn_manager.end_turn()
	else:
		# Counterattacks don't consume action
		pass


func _is_in_attack_range(attacker, target) -> bool:
	var dist: int = abs(attacker.grid_position.x - target.grid_position.x) \
		+ abs(attacker.grid_position.y - target.grid_position.y)
	return dist <= attacker.attack_range


func _all_player_units_have_acted() -> bool:
	for child in units_root.get_children():
		if child.team == "player" and not child.has_acted:
			return false
	return true

func _get_units_on_tiles(tiles: Array[Vector2i]) -> Array:
	var result: Array = []
	for child in units_root.get_children():
		if not child.has_method("get"):
			continue
		if child.grid_position in tiles:
			result.append(child)
	return result

func use_skill(caster, skill: Skill, center_tile: Vector2i) -> void:
	if caster == null or skill == null:
		return

	# Mana check
	if caster.mana < skill.mana_cost:
		print(caster.name, "does not have enough mana for", skill.name)
		return

	# Range check: can we target this center tile?
	var dist_to_center: int = abs(caster.grid_position.x - center_tile.x) \
		+ abs(caster.grid_position.y - center_tile.y)
	if dist_to_center > skill.cast_range:
		print("Target tile out of cast range for", skill.name)
		return

	# Compute AoE tiles
	var affected_tiles: Array[Vector2i] = []
	if skill.aoe_radius <= 0:
		affected_tiles.append(center_tile)
	else:
		for dx in range(-skill.aoe_radius, skill.aoe_radius + 1):
			for dy in range(-skill.aoe_radius, skill.aoe_radius + 1):
				var d: int = abs(dx) + abs(dy)
				if d <= skill.aoe_radius:
					var tile := center_tile + Vector2i(dx, dy)
					affected_tiles.append(tile)

	# Find units on those tiles
	var units_in_area: Array = _get_units_on_tiles(affected_tiles)

	if units_in_area.is_empty():
		print("No targets in skill area for", skill.name)
		return

	# Pay mana
	caster.mana -= skill.mana_cost
	print(caster.name, "casts", skill.name, "on", center_tile,
		" (mana:", caster.mana, "/", caster.max_mana, ")")

	# Apply effect
	for target in units_in_area:
		if not _skill_can_affect_target(caster, target, skill):
			continue

		_apply_skill_damage(caster, target, skill)

	# Using a skill consumes the action (for now)
	caster.has_acted = true
	if caster.has_node("Sprite2D"):
		caster.get_node("Sprite2D").modulate = Color.WHITE

	# You can hook selection clearing via Main, or optionally emit a signal
	if _all_player_units_have_acted():
		turn_manager.end_turn()

func _skill_can_affect_target(caster, target, skill: Skill) -> bool:
	match skill.target_type:
		Skill.TargetType.ENEMY_UNITS:
			return target.team != caster.team
		Skill.TargetType.ALLY_UNITS:
			return target.team == caster.team and target != caster
		Skill.TargetType.SELF:
			return target == caster
		Skill.TargetType.ALL_UNITS:
			return true
		Skill.TargetType.TILE:
			return false  # not affecting units, just the tile (future)
	return false


func _apply_skill_damage(caster, target, skill: Skill) -> void:
	# Terrain defense still applies to target
	var terrain_def: int = grid.get_defense_bonus(target.grid_position)

	var scaled_atk: float = float(caster.atk) * skill.power_multiplier
	var raw_damage: int = int(round(scaled_atk)) - (target.defense + terrain_def)
	var damage: int = max(raw_damage, 0)

	print("  ", caster.name, "hits", target.name, "with", skill.name,
		"for", damage, "damage (terrain def +", terrain_def, ")")

	var survived: bool = target.take_damage(damage)
	unit_attacked.emit(caster, target, damage, false)

	# No counterattacks for skills for now – you can add later if desired

extends Node

@export var default_skill_aoe_includes_caster: bool = false  # tweakable

@onready var grid         = $"../Grid"
@onready var turn_manager = $"../TurnManager"
@onready var units_root   = $"../Units"
@onready var terrain_effects_root: Node = $"../TerrainEffects"

signal unit_died(unit)
signal unit_attacked(attacker, defender, damage, is_counter)


func _ready() -> void:
	add_to_group("combat_manager")


# ------------------------------------------------------------
# BASIC ATTACKS
# ------------------------------------------------------------
func perform_attack(attacker, defender, is_counter: bool = false) -> void:
	if attacker == null or defender == null:
		return
	if not is_instance_valid(attacker) or not is_instance_valid(defender):
		return

	# Effective stats with buffs/debuffs
	var atk_bonus: int = StatusManager.get_atk_bonus(attacker)
	var def_bonus: int = StatusManager.get_def_bonus(defender)

	var effective_atk: int = attacker.atk + atk_bonus
	var effective_def: int = defender.defense + def_bonus

	var terrain_def: int = grid.get_defense_bonus(defender.grid_position)

	var raw_damage: int = effective_atk - (effective_def + terrain_def)
	var damage: int = max(raw_damage, 0)

	print(attacker.name, " attacks ", defender.name,
		" for ", damage, " dmg (atk=", effective_atk,
		", def=", effective_def, ", terrain def +", terrain_def, ")")

	if CombatLog != null:
		var tag: String = "COUNTER " if is_counter else ""
		CombatLog.add("%s%s attacks %s for %d (atk=%d, def=%d, terrain=%d)" % [
			tag, attacker.name, defender.name, damage, effective_atk, effective_def, terrain_def
			], {"type":"attack", "counter": is_counter})

	unit_attacked.emit(attacker, defender, damage, is_counter)

	var defender_survived: bool = defender.take_damage(damage)
	
	if CombatLog != null and not defender_survived:
		CombatLog.add("%s is defeated!" % defender.name, {"type":"ko"})


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


func _is_in_attack_range(attacker, target) -> bool:
	var dist: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.y - target.grid_position.y)
	return dist <= attacker.attack_range


func _all_player_units_have_acted() -> bool:
	for child in units_root.get_children():
		if child.team == "player" and not child.has_acted:
			return false
	return true


# ------------------------------------------------------------
# AOE SKILLS BY CENTER TILE
# ------------------------------------------------------------
func _get_units_on_tiles(tiles: Array[Vector2i]) -> Array:
	var result: Array = []
	for child in units_root.get_children():
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
	var dist_to_center: int = abs(caster.grid_position.x - center_tile.x) + abs(caster.grid_position.y - center_tile.y)
	if dist_to_center > skill.cast_range:
		print("Target tile out of cast range for", skill.name)
		return

	# Compute AoE tiles
	var affected_tiles: Array[Vector2i] = _get_aoe_tiles(center_tile, skill.aoe_radius)

	# Find units on those tiles
	var units_in_area: Array = _get_units_on_tiles(affected_tiles)

	if units_in_area.is_empty():
		print("No targets in skill area for", skill.name)
		return

	# Pay mana
	caster.mana -= skill.mana_cost
	print(caster.name, "casts", skill.name, "on", center_tile,
		" (mana:", caster.mana, "/", caster.max_mana, ")")

	if CombatLog != null:
		CombatLog.add("%s casts %s at %s" % [caster.name, skill.name, str(center_tile)],
			{"type":"cast", "skill": skill.name, "tile": center_tile, "aoe": int(skill.aoe_radius)})

	# Apply effect per unit using the SAME pipeline as unit-target skills.
	for target in units_in_area:
		if not _skill_can_affect_target(caster, target, skill):
			continue

		# Terrain skills shouldn't resolve "on units" here (tile-terrain handled elsewhere)
		if skill.effect_type == Skill.EffectType.TERRAIN:
			continue

		if CombatLog != null:
			CombatLog.add("  -> affects %s" % target.name, {"type":"cast_hit", "skill": skill.name})

		execute_skill_on_target(caster, target, skill)

	# Using a skill consumes the action (for now)
	caster.has_acted = true
	if caster.has_node("Sprite2D"):
		caster.get_node("Sprite2D").modulate = Color.WHITE

	if _all_player_units_have_acted():
		turn_manager.end_turn()


func _skill_can_affect_target(caster, target, skill: Skill) -> bool:
	match skill.target_type:
		Skill.TargetType.ENEMY_UNITS:
			return target.team != caster.team
		Skill.TargetType.ALLY_UNITS:
			return target.team == caster.team and (skill.can_target_self or target != caster)
		Skill.TargetType.SELF:
			return target == caster
		Skill.TargetType.ALL_UNITS:
			return true
		Skill.TargetType.TILE:
			return false
	return false


# ------------------------------------------------------------
# UNIT-TARGET SKILLS (single pipeline)
# ------------------------------------------------------------
func execute_skill_on_target(user, target, skill: Skill) -> void:
	if user == null or target == null or skill == null:
		return

	# Combat log headline (one line per resolved target)
	if CombatLog != null:
		var kind: String = str(skill.effect_type)
		CombatLog.add("%s uses %s on %s" % [user.name, skill.name, target.name], {
			"type": "skill_resolve",
			"skill": skill.name,
			"effect_type": kind,
			"user": user.name,
			"target": target.name
		})

	match skill.effect_type:
		Skill.EffectType.HEAL:
			_apply_skill_heal(user, target, skill)
		Skill.EffectType.BUFF, Skill.EffectType.DEBUFF:
			_apply_status_skill(user, target, skill)
		Skill.EffectType.DAMAGE:
			_apply_skill_damage(user, target, skill)
		Skill.EffectType.TERRAIN:
			print("CombatManager: Terrain skill targeted a unit; ignored.")
			if CombatLog != null:
				CombatLog.add("  -> terrain skill ignored (unit-target)", {"type":"terrain_ignored", "skill": skill.name})
		_:
			_apply_skill_damage(user, target, skill)



func _apply_skill_heal(user, target, skill: Skill) -> void:
	if user == null or target == null or skill == null:
		return

	var base_magic: int = user.atk
	var raw: float = float(base_magic) * float(skill.power_multiplier) + float(skill.flat_power)
	var amount: int = int(round(raw))
	if amount < 1:
		amount = 1

	var before_hp: int = int(target.hp)
	var new_hp: int = min(before_hp + amount, int(target.max_hp))
	var actual_heal: int = new_hp - before_hp
	if actual_heal <= 0:
		# Optional: log wasted heals for debugging
		if CombatLog != null:
			CombatLog.add("  -> %s is already full HP" % target.name, {"type":"heal_waste", "skill": skill.name})
		return

	target.hp = new_hp
	if target.has_method("update_hp_bar"):
		target.update_hp_bar()

	if CombatLog != null:
		CombatLog.add("  -> heals %s for %d (HP %d/%d → %d/%d)" % [
			target.name,
			actual_heal,
			before_hp, int(target.max_hp),
			int(target.hp), int(target.max_hp)
		], {"type":"heal", "skill": skill.name, "amount": actual_heal})



func _apply_skill_damage(user, target, skill: Skill) -> void:
	if user == null or target == null or skill == null:
		return

	# NOTE: simple formula for now: atk * mult + flat
	var base_attack: int = user.atk
	var raw: float = float(base_attack) * float(skill.power_multiplier) + float(skill.flat_power)
	var amount: int = int(round(raw))
	if amount < 1:
		amount = 1

	var before_hp: int = int(target.hp)
	var survived: bool = target.take_damage(amount)

	# Keep your print if you want it in the console too
	print(user.name, " hits ", target.name, " with ", skill.name, " for ", amount, " damage (skill).")

	if CombatLog != null:
		CombatLog.add("  -> hits %s for %d (HP %d/%d → %d/%d)%s" % [
			target.name,
			amount,
			before_hp, int(target.max_hp),
			int(target.hp), int(target.max_hp),
			"" if survived else " (KO)"
		], {"type":"damage", "skill": skill.name, "amount": amount, "killed": not survived})



func _apply_status_skill(user, target, skill: Skill) -> void:
	if user == null or target == null or skill == null:
		return

	if StatusManager != null and StatusManager.has_method("apply_status_to_unit"):
		StatusManager.apply_status_to_unit(target, skill, user)

		if CombatLog != null:
			CombatLog.add("  -> applies %s to %s (%d turns)" % [
				skill.name, target.name, int(skill.duration_turns)
			], {"type":"status", "skill": skill.name, "target": target.name, "duration": int(skill.duration_turns)})
	else:
		push_warning("StatusManager missing or has no apply_status_to_unit(). Did you set it as an Autoload named 'StatusManager'?")

	if target.has_method("refresh_status_icons"):
		target.refresh_status_icons()



# ------------------------------------------------------------
# TILE-TARGET SKILLS (Raise Wall first, then modifiers like Vines)
# ------------------------------------------------------------
func execute_skill_on_tile(caster, skill: Skill, center_tile: Vector2i) -> void:
	if caster == null or skill == null:
		return

	# Arcana lockout
	if StatusManager != null and StatusManager.unit_has_flag(caster, "prevent_arcana"):
		print(caster.name, "cannot cast right now (prevent_arcana).")
		return

	# Range check
	var dist: int = abs(caster.grid_position.x - center_tile.x) + abs(caster.grid_position.y - center_tile.y)
	if dist > skill.cast_range:
		print("Tile is out of cast range for", skill.name)
		return

	# Mana check
	if caster.mana < skill.mana_cost:
		print("Not enough mana for", skill.name)
		return

	# Spend mana
	caster.mana -= skill.mana_cost
	
	if CombatLog != null:
		CombatLog.add("%s casts %s at %s" % [caster.name, skill.name, str(center_tile)],
		{"type":"cast_tile", "skill": skill.name, "tile": center_tile})

	# Resolve AoE tiles (supports future AoE terrain/modifiers)
	var tiles: Array[Vector2i] = _get_aoe_tiles(center_tile, skill.aoe_radius)

	# Terrain-object skill: change tile (SET_TILE) + spawn object (scene)
	if skill.is_terrain_object_skill:
		for t in tiles:
			# 1) Apply terrain tile change (this makes it non-walkable if wall is configured in TERRAIN_TABLE)
			if grid != null and grid.has_method("apply_terrain_skill"):
				grid.apply_terrain_skill(t, caster, skill)

			# 2) Spawn the terrain object scene (visual/destructible/etc.)
			_spawn_terrain_object_on_tile(skill, t, caster)
			
			if CombatLog != null:
				CombatLog.add("  -> %s modifies tile %s" % [skill.name, str(t)],
				{"type":"terrain", "skill": skill.name, "tile": t})

		caster.has_acted = true
		return

	if CombatLog != null:
		CombatLog.add("%s applies %s modifier to %d tiles" % [caster.name, skill.name, tiles.size()],
		{"type":"tile_modifier", "skill": skill.name, "count": tiles.size()})

	# Otherwise: tile modifier (vines now; later fire, ice, poison, etc.)
	_apply_tile_modifier_on_tiles(skill, tiles, caster)

	caster.has_acted = true


func _get_aoe_tiles(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if radius <= 0:
		out.append(center)
		return out

	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if abs(dx) + abs(dy) <= radius:
				out.append(center + Vector2i(dx, dy))
	return out


func _spawn_terrain_object_on_tile(skill: Skill, tile: Vector2i, caster) -> void:
	if skill.terrain_object_scene == null:
		push_warning("Terrain object skill has no terrain_object_scene: %s" % skill.name)
		return

	var obj := skill.terrain_object_scene.instantiate()
	if obj == null:
		push_warning("Failed to instantiate terrain_object_scene for %s" % skill.name)
		return

	# Position using GridController (exists in your project)
	var world_pos := Vector2.ZERO
	if grid != null and grid.has_method("tile_to_world"):
		world_pos = grid.tile_to_world(tile)

	if obj is Node2D:
		(obj as Node2D).global_position = world_pos
	elif obj is Node3D:
		(obj as Node3D).global_position = Vector3(world_pos.x, world_pos.y, 0.0)

	# Add under TerrainEffects if present
	if terrain_effects_root != null:
		terrain_effects_root.add_child(obj)
	else:
		add_child(obj)

	# Always-safe metadata
	obj.set_meta("grid_position", tile)
	obj.set_meta("source_unit", caster)
	obj.set_meta("terrain_object_key", skill.terrain_object_key)

	# Optional init hook
	if obj.has_method("init_from_skill"):
		obj.init_from_skill(skill, tile, caster)

	print("Spawned terrain object:", skill.name, "at", tile)


func _apply_tile_modifier_on_tiles(skill: Skill, tiles: Array[Vector2i], caster) -> void:
	# Apply tile changes via GridController (vines/fire/etc.)
	if grid != null and grid.has_method("apply_terrain_skill"):
		for t in tiles:
			# NEW: track duration FIRST so we capture the original tile before overwriting it
			if skill.duration_turns > 0 and grid.has_method("apply_tile_effect"):
				grid.apply_tile_effect(t, StringName(skill.terrain_tile_key), int(skill.duration_turns))

			# Then apply the actual tile change (SET_TILE to vines, spikes, etc.)
			grid.apply_terrain_skill(t, caster, skill)

	# Optional: spawn a purely-visual overlay on each affected tile (if provided)
	if skill.terrain_object_scene != null:
		for t2 in tiles:
			var key := StringName(skill.terrain_tile_key)

			if grid != null and grid.has_method("clear_tile_overlays_if_key_diff"):
				grid.clear_tile_overlays_if_key_diff(t2, key)

			if grid != null and grid.has_method("has_overlay_key") and grid.has_overlay_key(t2, key):
				if grid.has_method("clear_tile_overlays"):
					grid.clear_tile_overlays(t2)

			_spawn_tile_overlay(skill, t2, caster)






func _spawn_tile_overlay(skill: Skill, tile: Vector2i, caster) -> void:
	var obj := skill.terrain_object_scene.instantiate()
	if obj == null:
		return

	var world_pos := Vector2.ZERO
	if grid != null and grid.has_method("tile_to_world"):
		world_pos = grid.tile_to_world(tile)

	if obj is Node2D:
		(obj as Node2D).global_position = world_pos
	elif obj is Node3D:
		(obj as Node3D).global_position = Vector3(world_pos.x, world_pos.y, 0.0)

	if terrain_effects_root != null:
		terrain_effects_root.add_child(obj)
	else:
		add_child(obj)

	obj.set_meta("grid_position", tile)
	obj.set_meta("source_unit", caster)
	obj.set_meta("tile_modifier_key", skill.terrain_tile_key)

	# NEW: register overlay so GridController can delete it on expiry
	if grid != null and grid.has_method("register_tile_overlay"):
		grid.register_tile_overlay(tile, obj, StringName(skill.terrain_tile_key))

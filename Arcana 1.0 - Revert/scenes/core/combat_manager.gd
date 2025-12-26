extends Node

@export var default_skill_aoe_includes_caster: bool = false  # tweakable

@onready var grid         = $"../Grid"
@onready var turn_manager = $"../TurnManager"
@onready var units_root   = $"../Units"
@onready var terrain_effects_root: Node = $"../TerrainEffects"

@export var heal_circle_vfx_scene: PackedScene

# --- COMBAT FEEL / FX ---
@export var enable_hitstop: bool = true
@export var hitstop_time_scale: float = 0.15
@export var hitstop_duration: float = 0.06

@export var enable_screen_shake: bool = true
@export var shake_distance: float = 6.0
@export var shake_duration: float = 0.10
@export var cast_dim_min_visible: float = 0.08 # seconds (tweak 0.06–0.12)
var _cast_dim_on_time_sec: float = -1.0
@export var impact_flash_alpha: float = 0.12
@export var impact_flash_time: float = 0.08
@export var cast_dim_post_impact_hold: float = 0.10
@export var target_overlay_fade_out: float = 0.5
var _cast_flash_done: bool = false

# Optional VFX scenes (drop your lightning bolt here later)
@export var top_fx_root_path: NodePath
@export var hit_spark_vfx_scene: PackedScene
@export var lightning_strike_vfx_scene: PackedScene
@export var ice_spear_vfx_scene: PackedScene
@export var target_pulse_light_scene: PackedScene
@export var target_outline_shader: ShaderMaterial # assign outline_flow.tres here
# Where to put floating text (if null, we fall back to Main/UI)
@export var floating_text_root_path: NodePath

@export var screen_fx_path: NodePath

var _target_outline_overlays: Array[Node2D] = []

signal unit_died(unit)
signal unit_attacked(attacker, defender, damage, is_counter)
signal attack_sequence_finished(attacker)
signal skill_sequence_finished(caster)


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
	var temp_atk: int = _get_temp_atk_bonus(attacker)

	var effective_atk: int = attacker.atk + atk_bonus + temp_atk
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
# ✅ Procedural attack lunge
	if attacker != null and attacker.has_method("play_attack_anim"):
		var target_pos: Vector2 = Vector2.ZERO
		if defender is Node2D:
			target_pos = (defender as Node2D).global_position
			attacker.play_attack_anim(target_pos)

# ✅ Hit react on defender (only if damage > 0)
	if damage > 0 and defender != null and defender.has_method("play_hit_react"):
		defender.play_hit_react()
		
	# ✅ FEEL FX (hit-stop, shake, numbers, sparks)
	if damage > 0:
		_do_hitstop()
		_do_screen_shake()
		_spawn_floating_text(_fx_world_pos_for_unit(defender), "-%d" % damage, false)
		if hit_spark_vfx_scene != null:
			_spawn_vfx_at_world(hit_spark_vfx_scene, _fx_world_pos_for_unit(defender))

	var defender_survived: bool = defender.take_damage(damage)
	if not defender_survived:
		_apply_on_kill_rewards(attacker, defender)

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

# ✅ tell AI (or anyone) the attack chain is finished
		if not is_counter:
			call_deferred("_emit_attack_sequence_finished_deferred", attacker)

func _is_in_attack_range(attacker, target) -> bool:
	var dist: int = abs(attacker.grid_position.x - target.grid_position.x) + abs(attacker.grid_position.y - target.grid_position.y)
	return dist <= attacker.attack_range

func _emit_attack_sequence_finished_deferred(attacker) -> void:
	attack_sequence_finished.emit(attacker)

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

	# Range check
	var dist_to_center: int = abs(caster.grid_position.x - center_tile.x) + abs(caster.grid_position.y - center_tile.y)
	if dist_to_center > skill.cast_range:
		print("Target tile out of cast range for", skill.name)
		return

	# Compute AoE tiles + units
	var affected_tiles: Array[Vector2i] = _get_aoe_tiles(center_tile, skill.aoe_radius)
	var units_in_area: Array = _get_units_on_tiles(affected_tiles)

	if units_in_area.is_empty():
		print("No targets in skill area for", skill.name)
		return

	# ✅ INSERT A: Build final target list + apply outline NOW (before windup)
	var valid_targets: Array = []
	_clear_target_outline_overlays()
	for t in units_in_area:
		if t == null:
			continue
		if not _skill_can_affect_target(caster, t, skill):
			continue
		if skill.effect_type == Skill.EffectType.TERRAIN:
			continue
		valid_targets.append(t)

	if valid_targets.is_empty():
		print("No valid targets in skill area for", skill.name)
		return

	_clear_target_outline_overlays()
	for t in valid_targets:
		var ov := _spawn_target_outline_overlay(t)
		if ov != null:
			_target_outline_overlays.append(ov)

	# Turn outlines on (flow outline)
	var outlined: Array = []
	for t in valid_targets:
		if t.has_method("set_outline_enabled"):
			t.call("set_outline_enabled", true, Color(0.2, 0.8, 1.0, 1.0))
			outlined.append(t)

	# Pay mana
	caster.mana -= skill.mana_cost
	print(caster.name, "casts", skill.name, "on", center_tile,
		" (mana:", caster.mana, "/", caster.max_mana, ")")

	if caster.has_method("play_cast_anim"):
		caster.play_cast_anim()

	await _screen_fx_begin_cast()

	# Wind-up delay (JRPG beat) — once per cast
	if skill.cast_windup > 0.0:
		await get_tree().create_timer(skill.cast_windup).timeout

	await _screen_fx_impact_flash_once()

	if CombatLog != null:
		CombatLog.add("%s casts %s at %s" % [caster.name, skill.name, str(center_tile)],
			{"type":"cast", "skill": skill.name, "tile": center_tile, "aoe": int(skill.aoe_radius)})

	# VFX: healing circle at AoE center (plays once)
	if skill.effect_type == Skill.EffectType.HEAL and heal_circle_vfx_scene != null:
		var vfx := heal_circle_vfx_scene.instantiate()
		var world_pos: Vector2 = Vector2.ZERO
		if grid != null and grid.has_method("tile_to_world"):
			world_pos = grid.tile_to_world(center_tile)
		if vfx is Node2D:
			(vfx as Node2D).global_position = world_pos
		if terrain_effects_root != null:
			terrain_effects_root.add_child(vfx)
		else:
			add_child(vfx)

	# ✅ INSERT B: Loop ONLY valid targets (no extra filtering needed)
	for target in valid_targets:
		if CombatLog != null:
			CombatLog.add("  -> affects %s" % target.name, {"type":"cast_hit", "skill": skill.name})

		await execute_skill_on_target(caster, target, skill, false)

	# ✅ INSERT C: Clear outlines BEFORE undim
	for t in outlined:
		if t != null and is_instance_valid(t) and t.has_method("set_outline_enabled"):
			t.call("set_outline_enabled", false)

	# Using a skill consumes the action
	caster.has_acted = true
	if caster.has_node("Sprite2D"):
		caster.get_node("Sprite2D").modulate = Color.WHITE

	if _all_player_units_have_acted():
		turn_manager.end_turn()

	_clear_target_outline_overlays()
	await _screen_fx_end_cast()
	skill_sequence_finished.emit(caster)


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

# SKILL TAG HELPER
func _skill_has_tag(skill: Skill, tag: StringName) -> bool:
	if skill == null:
		return false
	for t in skill.tags:
		if t == tag:
			return true
	return false


# ------------------------------------------------------------
# UNIT-TARGET SKILLS (single pipeline)
# ------------------------------------------------------------
func execute_skill_on_target(user, target, skill: Skill, play_cast: bool = true) -> void:
	if user == null or target == null or skill == null:
		return

	if play_cast:
		if user.has_method("play_cast_anim"):
			user.play_cast_anim()

		await _screen_fx_begin_cast()
		
		_clear_target_outline_overlays()
		var ov := _spawn_target_outline_overlay(target)
		if ov != null:
			_target_outline_overlays.append(ov)

		if target != null and target.has_method("set_outline_enabled"):
			target.call("set_outline_enabled", true, Color(0.2, 0.8, 1.0, 1.0))

		if target_pulse_light_scene != null:
			_spawn_vfx_at_world(target_pulse_light_scene, _fx_world_pos_for_unit(target), false)

		if skill.cast_windup > 0.0:
			await get_tree().create_timer(skill.cast_windup).timeout

		# flash once at impact moment
		await _screen_fx_impact_flash_once()

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

	_resolve_status_reactions(user, target, skill)

	match skill.effect_type:
		Skill.EffectType.HEAL:
			_apply_skill_heal(user, target, skill)
		Skill.EffectType.BUFF, Skill.EffectType.DEBUFF:
			_apply_status_skill(user, target, skill)
		Skill.EffectType.DAMAGE:
			await _play_skill_impact_vfx_and_wait(user, target, skill)
			_apply_skill_damage(user, target, skill)
		Skill.EffectType.TERRAIN:
			print("CombatManager: Terrain skill targeted a unit; ignored.")
			if CombatLog != null:
				CombatLog.add("  -> terrain skill ignored (unit-target)", {"type":"terrain_ignored", "skill": skill.name})
		_:
			_apply_skill_damage(user, target, skill)

	if play_cast:
		# Turn off outline first so it doesn't linger during undim
		if target != null and target.has_method("set_outline_enabled"):
			target.call("set_outline_enabled", false)

		_clear_target_outline_overlays()
		await _screen_fx_end_cast()


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
		_spawn_floating_text(_fx_world_pos_for_unit(target), "+%d" % actual_heal, true)

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

	# Effective stats with buffs/debuffs
	var atk_bonus: int = 0
	var def_bonus: int = 0
	if StatusManager != null:
		atk_bonus = StatusManager.get_atk_bonus(user)
		def_bonus = StatusManager.get_def_bonus(target)

	var temp_atk: int = _get_temp_atk_bonus(user)

	var effective_atk: int = int(user.atk) + atk_bonus + temp_atk
	var effective_def: int = int(target.defense) + def_bonus

	var terrain_def: int = 0
	if grid != null and ("grid_position" in target):
		terrain_def = int(grid.get_defense_bonus(target.grid_position))

	# Skill formula (now respects defense/terrain):
	# atk * mult + flat - (def + terrain_def)
	var raw: float = float(effective_atk) * float(skill.power_multiplier) + float(skill.flat_power)
	raw -= float(effective_def + terrain_def)

	var amount: int = int(round(raw))
	if amount < 1:
		amount = 1
		
	

# Apply damage exactly at impact
	var before_hp: int = int(target.hp)
	var survived: bool = target.take_damage(amount)

	_do_hitstop()
	_do_screen_shake()
	_spawn_floating_text(_fx_world_pos_for_unit(target), "-%d" % amount, false)


	if not survived:
		_apply_on_kill_rewards(user, target)

	print(user.name, " hits ", target.name, " with ", skill.name,
		" for ", amount, " damage (skill) (atk=", effective_atk,
		", def=", effective_def, ", terrain def +", terrain_def, ")")

	if CombatLog != null:
		CombatLog.add("  -> %s hits %s with %s for %d (atk=%d, def=%d, terrain=%d) (HP %d/%d → %d/%d)%s" % [
			user.name,
			target.name,
			skill.name,
			amount,
			effective_atk,
			effective_def,
			terrain_def,
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
	
	if caster != null and caster.has_method("play_cast_anim"):
		caster.play_cast_anim()

	_screen_fx_set_cast_dim(true)
	await get_tree().process_frame
	if skill.cast_windup > 0.0:
		await get_tree().create_timer(skill.cast_windup).timeout

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
		skill_sequence_finished.emit(caster)
		_screen_fx_set_cast_dim(false)
		return

	if CombatLog != null:
		CombatLog.add("%s applies %s modifier to %d tiles" % [caster.name, skill.name, tiles.size()],
		{"type":"tile_modifier", "skill": skill.name, "count": tiles.size()})

	# Otherwise: tile modifier (vines now; later fire, ice, poison, etc.)
	_apply_tile_modifier_on_tiles(skill, tiles, caster)

	_screen_fx_set_cast_dim(false)
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
		
		
#STATUS REACTION HELPER
func _resolve_status_reactions(user, target, skill: Skill) -> void:
	if user == null or target == null or skill == null:
		return
	if StatusManager == null:
		return

	# Ice on Wet => replace Wet with Chilled (your choice A)
	if _skill_has_tag(skill, &"ice") and StatusManager.has_status(target, &"wet"):
		StatusManager.remove_status(target, &"wet")

		var chilled_skill: Skill = RunManager.get_chilled_status_skill() if RunManager != null and RunManager.has_method("get_chilled_status_skill") else null
		if chilled_skill != null:
			StatusManager.apply_status_to_unit(target, chilled_skill, user)

		if CombatLog != null:
			CombatLog.add("  -> reaction: Wet + Ice = Chilled on %s" % target.name,
				{"type":"reaction", "target": target.name})
		
	# Wet + Lightning => Shocked (Wet consumed)
	if _skill_has_tag(skill, &"lightning") and StatusManager.has_status(target, &"wet"):
		StatusManager.remove_status(target, &"wet")

		if RunManager != null and RunManager.has_method("get_shocked_status_skill"):
			var shocked: Skill = RunManager.get_shocked_status_skill()
			StatusManager.apply_status_to_unit(target, shocked, user)

		if CombatLog != null:
			CombatLog.add("Reaction: Wet + Lightning → Shocked (%s)" % target.name, {"type":"reaction"})
			
	# Chilled + Ice => Frozen (Wet consumed)
	if _skill_has_tag(skill, &"ice") and StatusManager.has_status(target, &"chilled"):
		StatusManager.remove_status(target, &"chilled")

		if RunManager != null and RunManager.has_method("get_frozen_status_skill"):
			var frozen: Skill = RunManager.get_frozen_status_skill()
			StatusManager.apply_status_to_unit(target, frozen, user)

		if CombatLog != null:
			CombatLog.add("Reaction: Chilled + Ice → Frozen (%s)" % target.name, {"type":"reaction"})

	# Wet + Fire => Wet Consumed
	if _skill_has_tag(skill, &"fire") and StatusManager.has_status(target, &"wet"):
		StatusManager.remove_status(target, &"wet")
	if CombatLog != null:
		CombatLog.add("Reaction: Wet + Fire → Dry (%s)" % target.name, {"type":"reaction"})
	# Wet + Chilled => Chilled Consumed
	if _skill_has_tag(skill, &"fire") and StatusManager.has_status(target, &"chilled"):
		StatusManager.remove_status(target, &"chilled")
		if CombatLog != null:
			CombatLog.add("Reaction: Chilled + Fire → Warm (%s)" % target.name, {"type":"reaction"})
	# Frozen + Fire => Wet (Frozen Consumed)
	if _skill_has_tag(skill, &"fire") and StatusManager.has_status(target, &"frozen"):
		StatusManager.remove_status(target, &"frozen")

		var chilled_skill: Skill = RunManager.get_chilled_status_skill() if RunManager != null and RunManager.has_method("get_chilled_status_skill") else null
		if chilled_skill != null:
			StatusManager.apply_status_to_unit(target, chilled_skill, user)

		if CombatLog != null:
			CombatLog.add("  -> reaction: Frozen + Fire = Wet on %s" % target.name,
				{"type":"reaction", "target": target.name})

const META_TEMP_ATK_BONUS := &"temp_atk_bonus"

func _get_temp_atk_bonus(unit) -> int:
	if unit == null or not is_instance_valid(unit):
		return 0
	if unit.has_meta(META_TEMP_ATK_BONUS):
		return int(unit.get_meta(META_TEMP_ATK_BONUS))
	return 0


func _get_equipment_list(unit) -> Array:
	if unit == null or not is_instance_valid(unit):
		return []
	if "unit_data" in unit and unit.unit_data != null and "equipment_slots" in unit.unit_data:
		var arr = unit.unit_data.equipment_slots
		if typeof(arr) == TYPE_ARRAY:
			return arr
	return []

#KILL REWARDS HELPERS
func _apply_on_kill_rewards(killer, victim) -> void:
	if killer == null or victim == null:
		return
	if not is_instance_valid(killer) or not is_instance_valid(victim):
		return

	var eq_list: Array = _get_equipment_list(killer)
	if eq_list.is_empty():
		return

	var atk_gain: int = 0
	var mana_gain: int = 0

	for eq in eq_list:
		if eq == null:
			continue
		if "on_kill_atk_bonus" in eq:
			atk_gain += int(eq.on_kill_atk_bonus)
		if "on_kill_mana_restore" in eq:
			mana_gain += int(eq.on_kill_mana_restore)

	if atk_gain <= 0 and mana_gain <= 0:
		return

	if atk_gain > 0:
		var cur: int = _get_temp_atk_bonus(killer)
		killer.set_meta(META_TEMP_ATK_BONUS, cur + atk_gain)

		if CombatLog != null:
			CombatLog.add("%s gains +%d ATK (kill reward) until battle ends." % [killer.name, atk_gain],
				{"type":"buff", "source": killer.name})

	if mana_gain > 0 and ("mana" in killer) and ("max_mana" in killer):
		var before: int = int(killer.mana)
		var maxm: int = int(killer.max_mana)
		killer.mana = min(maxm, before + mana_gain)

		if CombatLog != null:
			CombatLog.add("%s restores %d mana (kill reward)." % [killer.name, mana_gain],
				{"type":"mana", "source": killer.name})

func _get_camera_controller() -> Node:
	# Best: mark your Camera2D node with group "camera_controller"
	var cam := get_tree().get_first_node_in_group("camera_controller")
	if cam != null:
		return cam

	# Fallback: try to find a Camera2D under Main (parent)
	var p := get_parent()
	if p != null:
		# If your camera is literally named "Camera2D"
		var c := p.get_node_or_null("Camera2D")
		if c != null:
			return c
	return null

func _fx_world_pos_for_unit(u) -> Vector2:
	if u is Node2D:
		return (u as Node2D).global_position
	return Vector2.ZERO

func _spawn_vfx_at_world(scene: PackedScene, world_pos: Vector2, undimmed: bool = false) -> void:
	if scene == null:
		return

	var v := scene.instantiate()
	if v == null:
		return

	if v is Node2D:
		(v as Node2D).global_position = world_pos

	if undimmed:
		var top := _get_top_fx_root()
		if top != null:
			top.add_child(v)
			return

	# default: regular world VFX root
	if terrain_effects_root != null:
		terrain_effects_root.add_child(v)
	else:
		add_child(v)

func _do_hitstop() -> void:
	if not enable_hitstop:
		return
	# Avoid stacking hitstop calls in the same moment
	if Engine.time_scale < 1.0:
		return
	Engine.time_scale = hitstop_time_scale
	call_deferred("_end_hitstop_deferred")

func _end_hitstop_deferred() -> void:
	await get_tree().create_timer(hitstop_duration, true).timeout
	Engine.time_scale = 1.0

func _find_camera_2d() -> Node:
	# Try common patterns. Add your camera to a group "camera" if you want it deterministic.
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null:
		return cam
	var main := get_parent()
	if main != null:
		var c := main.get_node_or_null("Camera2D")
		if c != null:
			return c
	return null

func _do_screen_shake() -> void:
	if not enable_screen_shake:
		return
	var cam := _get_camera_controller()
	if cam != null and cam.has_method("shake"):
		cam.call("shake", shake_distance, shake_duration)


func _get_floating_text_root() -> Node:
	if floating_text_root_path != NodePath():
		var n := get_node_or_null(floating_text_root_path)
		if n != null:
			return n
	# Fallback: try parent (Main) then self
	var p := get_parent()
	return p if p != null else self

func _spawn_floating_text(world_pos: Vector2, text: String, is_heal: bool) -> void:
	var root := _get_floating_text_root()
	if root == null:
		return

	var lbl := Label.new()
	lbl.text = text
	lbl.z_index = 999
	lbl.modulate = Color(0.6, 1.0, 0.6, 1.0) if is_heal else Color(1.0, 0.8, 0.8, 1.0)

	# Put it in world space if root is Node2D, otherwise screen-ish
	if root is Node2D:
		(root as Node2D).add_child(lbl)
		lbl.global_position = world_pos
	else:
		root.add_child(lbl)
		lbl.position = world_pos

	var up := Vector2(0, -20)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position", lbl.position + up, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.finished.connect(func(): if is_instance_valid(lbl): lbl.queue_free(), CONNECT_ONE_SHOT)

func _screen_fx_set_cast_dim(on: bool) -> void:
	if screen_fx_path == NodePath():
		return

	var fx := get_node_or_null(screen_fx_path)
	if fx == null or not fx.has_method("set_cast_dim"):
		return

	if on:
		_cast_dim_on_time_sec = Time.get_ticks_msec() / 1000.0
		fx.call("set_cast_dim", true)
	else:
		# Ensure dim stays visible for at least cast_dim_min_visible
		if _cast_dim_on_time_sec >= 0.0 and cast_dim_min_visible > 0.0:
			var now := Time.get_ticks_msec() / 1000.0
			var elapsed := now - _cast_dim_on_time_sec
			var remaining := cast_dim_min_visible - elapsed
			if remaining > 0.0:
				await get_tree().create_timer(remaining).timeout

		fx.call("set_cast_dim", false)
		_cast_dim_on_time_sec = -1.0

func _screen_fx_begin_cast() -> void:
	_cast_flash_done = false
	_screen_fx_set_cast_dim(true)
	# ensure at least one frame so dim becomes visible even on instant casts
	await get_tree().process_frame

func _screen_fx_impact_flash_once() -> void:
	if _cast_flash_done:
		return
	_cast_flash_done = true

	if screen_fx_path == NodePath():
		return
	var fx := get_node_or_null(screen_fx_path)
	if fx != null and fx.has_method("impact_flash"):
		fx.call("impact_flash", impact_flash_alpha, impact_flash_time)
		# let the flash play (small, but helps the beat)
		await get_tree().create_timer(impact_flash_time).timeout

func _screen_fx_end_cast() -> void:
	# hold dim briefly so the impact is readable (snow maps!)
	if cast_dim_post_impact_hold > 0.0:
		await get_tree().create_timer(cast_dim_post_impact_hold).timeout
	await _screen_fx_set_cast_dim(false) # your min-visible-aware off

func _screen_fx_impact_flash() -> void:
	if screen_fx_path == NodePath():
		return
	var fx := get_node_or_null(screen_fx_path)
	if fx == null:
		return
	if fx.has_method("impact_flash"):
		fx.call("impact_flash", impact_flash_alpha, impact_flash_time)
		# wait for the flash to complete so sequencing feels right
		await get_tree().create_timer(impact_flash_time).timeout

func _screen_fx_set_cast_dim_off_after_min() -> void:
	# ensure at least one frame so the impact is seen under dim
	await get_tree().process_frame
	if cast_dim_post_impact_hold > 0.0:
		await get_tree().create_timer(cast_dim_post_impact_hold).timeout
	await _screen_fx_set_cast_dim(false) # your min-visible dim-aware version

func _get_top_fx_root() -> Node:
	if top_fx_root_path == NodePath():
		return null
	return get_node_or_null(top_fx_root_path)

func _spawn_target_outline_overlay(target) -> Node2D:
	if target == null:
		return null

	var top: Node = _get_top_fx_root()
	if top == null:
		return null

	# Grab the target's AnimatedSprite2D
	var src_node: Node = target.get_node_or_null("AnimatedSprite2D")
	if src_node == null or not (src_node is AnimatedSprite2D):
		return null
	var src_anim: AnimatedSprite2D = src_node as AnimatedSprite2D

	# Create overlay sprite
	var overlay := AnimatedSprite2D.new()
	overlay.modulate.a = 1.0
	overlay.sprite_frames = src_anim.sprite_frames
	overlay.animation = src_anim.animation
	overlay.frame = src_anim.frame
	overlay.frame_progress = src_anim.frame_progress
	overlay.flip_h = src_anim.flip_h
	overlay.flip_v = src_anim.flip_v
	overlay.scale = src_anim.scale  # use LOCAL scale (not global)

# Pixel-art filtering
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED

# Snap to pixels to avoid blur
	overlay.global_position = src_anim.global_position.round()
	overlay.global_rotation = src_anim.global_rotation
	overlay.z_index = 999

# Animate
	overlay.play(overlay.animation)
	overlay.speed_scale = src_anim.speed_scale


	# Apply outline shader (duplicate so params are per-instance)
	if target_outline_shader != null:
		var mat := target_outline_shader.duplicate() as ShaderMaterial
		overlay.material = mat
		mat.set_shader_parameter("enabled", true)
		# You can tweak this per spell type later
		mat.set_shader_parameter("outline_color", Color(0.2, 0.8, 1.0, 1.0))

	top.add_child(overlay)
	return overlay

func _clear_target_outline_overlays() -> void:
	for o in _target_outline_overlays:
		if o == null or not is_instance_valid(o):
			continue

		# If fade is 0, just remove immediately
		if target_overlay_fade_out <= 0.0:
			o.queue_free()
			continue

		# Prevent double-fading
		if o.has_meta(&"fading_out"):
			continue
		o.set_meta(&"fading_out", true)

		var t := o.create_tween()
		t.tween_property(o, "modulate:a", 0.0, target_overlay_fade_out)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		t.tween_callback(o.queue_free)

	_target_outline_overlays.clear()


func _vfx_impact_delay_for_skill(skill: Skill) -> float:
	# Example tags:
	# vfx_lightning_bolt, vfx_your_new_anim
	if _skill_has_tag(skill, &"vfx_lightning_bolt"):
		return 0.5 # frame 7 at 12 fps -> 6/12
	if _skill_has_tag(skill, &"vfx_ice_spear"):
		return 0.75 # frame 10 at 12 fps -> 9/12
	return 0.0

func _play_skill_impact_vfx_and_wait(user, target, skill: Skill) -> void:
	# Spawn the VFX at the start of the impact window
	if _skill_has_tag(skill, &"vfx_lightning_bolt") and lightning_strike_vfx_scene != null:
		_spawn_vfx_at_world(lightning_strike_vfx_scene, _fx_world_pos_for_unit(target), true)
	elif _skill_has_tag(skill, &"vfx_ice_spear") and ice_spear_vfx_scene != null:
		_spawn_vfx_at_world(ice_spear_vfx_scene, _fx_world_pos_for_unit(target), true)

	var d := _vfx_impact_delay_for_skill(skill)
	if d > 0.0:
		await get_tree().create_timer(d).timeout

extends Node2D

enum InputMode { FREE, AWAIT_ACTION, MOVE, ATTACK, SKILL_TARGET }

var _unit_cycle_index: int = -1
var current_turn: int = 1
var _turn_initialized: bool = false
var input_mode: InputMode = InputMode.FREE
var pending_skill = null
var _current_skill: Skill = null
var _initial_player_unit_count: int = 0
var _hitstop_in_progress: bool = false

# --- Run statistics for summary panel ---
var run_turns: int = 1              # Turn count (starts at player phase 1)
var enemies_defeated: int = 0       # Total enemy units killed this battle
var players_defeated: int = 0       # Total player units killed this battle
var battle_finished: bool = false

# Helper to avoid incrementing turn before the first real player phase
var _first_player_phase_done: bool = false

@export var selection_ring_scene: PackedScene

var _selection_ring: Node2D = null
var _selection_ring_tween: Tween = null

@onready var skill_system: SkillSystem = $SkillSystem
@export var use_procedural_map: bool = false
@onready var map_generator: Node = $MapGenerator
@onready var units_root: Node = $Units
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var turn_label: Label = $UI/TurnPanel/Panel/TurnLabel
@onready var grid      = $Grid
@onready var terrain: TileMap = $Grid/Terrain
@onready var units: Node2D    = $Units
@onready var overlay: Node2D  = $Overlay
@onready var turn_manager     = $TurnManager
@onready var combat_manager = $CombatManager
@onready var action_menu: Control = $UI/ActionMenu
@onready var skill_menu: Control  = $UI/SkillMenu
@onready var camera: Camera2D = $Camera2D
@onready var phase_banner: Control = $UI/PhaseBanner
@onready var combat_forecast_panel: Control = $UI/CombatForecastPanel
@onready var sfx_select: AudioStreamPlayer  = $SFX/SelectSFX
@onready var sfx_deselect: AudioStreamPlayer = $SFX/SelectSFX
@onready var sfx_confirm: AudioStreamPlayer = $SFX/SelectSFX
@onready var sfx_cancel: AudioStreamPlayer  = $SFX/SelectSFX
@onready var victory_panel: Control      = $UI/VictoryPanel
@onready var defeat_panel: Control       = $UI/DefeatPanel
@onready var victory_detail_label: Label = $UI/VictoryPanel/Panel/VBoxContainer/DetailLabel
@onready var defeat_detail_label: Label  = $UI/DefeatPanel/Panel/VBoxContainer/DetailLabel
@onready var victory_restart_button: Button = $UI/VictoryPanel/Panel/VBoxContainer/ButtonRow/RestartButton
@onready var victory_title_button: Button   = $UI/VictoryPanel/Panel/VBoxContainer/ButtonRow/TitleButton
@onready var defeat_restart_button: Button  = $UI/DefeatPanel/Panel/VBoxContainer/ButtonRow/RestartButton
@onready var defeat_title_button: Button    = $UI/DefeatPanel/Panel/VBoxContainer/ButtonRow/TitleButton
@onready var victory_summary_label: Label = $UI/VictoryPanel/Panel/VBoxContainer/SummaryLabel
@onready var defeat_summary_label: Label  = $UI/DefeatPanel/Panel/VBoxContainer/SummaryLabel
@onready var level_up_panel: LevelUpPanel = $UI/LevelUpPanel
@onready var terrain_effects_root: Node2D = $TerrainEffects
@onready var enemy_spawner: EnemySpawnManager = $EnemySpawnManager

@export var floating_text_scene: PackedScene
@export var hitstop_duration: float = 0.06
@export var hitstop_time_scale: float = 0.05
@export var hit_shake_strength: float = 8.0
@export var hit_shake_duration: float = 0.12

@export var enemy_think_delay: float = 0.30
@export var enemy_between_enemies_delay: float = 0.18
@export var battle_objective: BattleObjective
@export var unit_scene: PackedScene
@export var range_tile_scene: PackedScene
@export var attack_tile_scene: PackedScene     # NEW: attack range
@export_file("*.tscn") var title_scene_path: String = "res://scenes/ui/TitleScreen.tscn"

var _pending_victory_reason: String = ""

var player_unit
var selected_unit

@onready var combat_log_panel: Control = $UI/CombatLogPanel
@onready var enemy_ai: EnemyAI = $EnemyAI
var active_range_tiles: Array[Node2D] = []
var active_attack_tiles: Array[Node2D] = []    # NEW: attack tiles
var active_skill_preview_tiles: Array = []
var last_preview_tile: Vector2i = Vector2i(-999, -999)
# Enemy hover attack-preview tiles
var active_enemy_attack_tiles: Array[Node2D] = []
var _enemy_preview_unit: Node2D = null


func _ready() -> void:
	spawn_units_from_run()
	turn_manager.phase_changed.connect(_on_phase_changed)
	action_menu.action_selected.connect(_on_action_menu_selected)
	skill_menu.skill_selected.connect(_on_skill_menu_selected)
	skill_menu.skill_selected.connect(_on_skill_menu_skill_selected)
	_update_turn_label()
	
	if combat_manager != null and combat_manager.has_signal("unit_attacked"):
		combat_manager.unit_attacked.connect(_on_unit_attacked_feedback)

		# --- Selection ring setup ---
	if selection_ring_scene != null:
		_selection_ring = selection_ring_scene.instantiate()
		overlay.add_child(_selection_ring)  # put it above the map
		_selection_ring.visible = false
		
	if music_player != null:
		music_player.play()
		# Make sure end-of-battle panels start hidden
	victory_panel.visible = false
	defeat_panel.visible = false

	# Connect 'died' signal for any units already placed in the scene.
	for child in units.get_children():
		_connect_unit_signals(child)

	# Connect buttons for restart / return to title
	victory_restart_button.pressed.connect(_go_to_rewards_screen)
	victory_title_button.pressed.connect(_on_return_to_title_pressed)
	defeat_restart_button.pressed.connect(_on_restart_pressed)
	defeat_title_button.pressed.connect(_on_return_to_title_pressed)
	
	if level_up_panel != null:
		level_up_panel.finished.connect(_on_levelup_panel_finished)


	

	# Make sure victory/defeat panels are hidden initially
	victory_panel.visible = false
	defeat_panel.visible = false
	combat_log_panel.visible = false
	
	if use_procedural_map and map_generator != null:
		map_generator.build_random_map()

	# After map is built, you can now spawn units based on terrain, etc.
	# ...

	battle_finished = false

	_initial_player_unit_count = get_tree().get_nodes_in_group("player_units").size()
	
	
func spawn_test_units() -> void:
	if unit_scene == null:
		push_error("Assign 'unit_scene' in the Inspector on Main")
		return

	# Player unit
	var p_pos := Vector2i(2, 2)
	var p    := _spawn_unit(unit_scene, p_pos, "player")
	p.name = "PlayerUnit"
	p.position = grid.tile_to_world(p_pos)
	if p.has_node("Sprite2D"):
		p.get_node("Sprite2D").modulate = Color(0.7, 0.9, 1.0)

	# Enemy unit
	var e_pos := Vector2i(5, 2)
	var e    := _spawn_unit(unit_scene, e_pos, "enemy")
	e.name = "EnemyUnit"
	e.position = grid.tile_to_world(e_pos)
	if e.has_node("Sprite2D"):
		e.get_node("Sprite2D").modulate = Color(1.0, 0.6, 0.6)


func _input(event: InputEvent) -> void:
	if battle_finished:
		return
		# ✅ Always allow toggling combat log (even during enemy turn / UI hover / battle end)
	if event.is_action_pressed("toggle_combat_log"):
		_toggle_combat_log()
		return
		# If battle is finished, ignore gameplay input
	if battle_finished:
		return
	# -----------------------------------------
	#  CANCEL INPUT (Right Click or X)
	# -----------------------------------------
	if event.is_pressed():

		# Right Click cancel
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_current_action()
			return

		# X key cancel
		if event is InputEventKey and event.keycode == KEY_X:
			_cancel_current_action()
			return

		# TAB → Cycle to next un-acted player unit
		if event is InputEventKey and event.keycode == KEY_TAB:
			_cycle_next_unit()
			return

		# ENTER → End turn
		if event is InputEventKey and event.keycode == KEY_ENTER:
			turn_manager.end_turn()
			return
			
		if event.is_action_pressed("toggle_combat_log"):
			_toggle_combat_log()
			return

	# -----------------------------------------
	#  UI CLICK BLOCKING — DO NOT CLICK THROUGH UI
	# -----------------------------------------
	if event is InputEventMouseButton and event.pressed:
		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered != null:
			return

	# -----------------------------------------
	#  IGNORE INPUT IF NOT PLAYER TURN
	# -----------------------------------------
	if not turn_manager.is_player_turn():
		return

	# -----------------------------------------
	#  LEFT CLICK — MAIN BOARD INTERACTIONS
	# -----------------------------------------
	if event is InputEventMouseButton \
	and event.button_index == MOUSE_BUTTON_LEFT \
	and event.pressed:

		var tile: Vector2i = grid.cursor_tile
		print("Left click on tile:", tile, " mode:", input_mode)

		# No unit selected yet → try selecting one
		if selected_unit == null:
			_try_select_unit_at_tile(tile)
			return

		# Unit is selected → act based on mode
		match input_mode:
			InputMode.MOVE:
				_handle_move_click(tile)
				return

			InputMode.ATTACK:
				_handle_attack_click(tile)
				return

			InputMode.SKILL_TARGET:
				_handle_skill_target_click(tile)
				return

			InputMode.AWAIT_ACTION, InputMode.FREE:
				_try_select_unit_at_tile(tile)
				return

func _toggle_combat_log() -> void:
	if combat_log_panel == null:
		return
	combat_log_panel.visible = not combat_log_panel.visible
	
	if combat_log_panel.visible and combat_log_panel.has_method("refresh_now"):
		combat_log_panel.refresh_now()
	
func _debug_tilemap_identity(grid: Node, map_generator: Node) -> void:
	var grid_tm: TileMap = grid.get_node("Terrain") as TileMap
	var mg_tm: TileMap = null
	if "terrain" in map_generator:
		mg_tm = map_generator.terrain as TileMap

	print("--- TILEMAP IDENTITY DEBUG ---")
	print("Grid Terrain:", grid_tm.get_path(), " id:", grid_tm.get_instance_id(), " global:", grid_tm.global_position)
	if mg_tm != null:
		print("MapGen Terrain:", mg_tm.get_path(), " id:", mg_tm.get_instance_id(), " global:", mg_tm.global_position)
	else:
		print("MapGen terrain is null or not present.")
	print("------------------------------")


func _connect_unit_signals(u: Node) -> void:
	if not u.has_signal("died"):
		return
	var c := Callable(self, "_on_unit_died").bind(u)
	if not u.died.is_connected(c):
		u.died.connect(c)


func _handle_move_click(tile: Vector2i) -> void:
	if selected_unit == null:
		return

	_try_move_selected_unit_to_tile(tile)

	# If the unit is still valid and selected after moving, re-center camera
	if selected_unit != null and is_instance_valid(selected_unit):
		_focus_camera_on_unit(selected_unit)

	input_mode = InputMode.FREE
	action_menu.hide_menu()
	skill_menu.hide_menu()
	_queue_enemy_intents_refresh()
func get_current_objective_type() -> String:
	if battle_objective == null:
		return "rout"

	# battle_objective is a Resource (BattleObjective), using victory_type enum
	match battle_objective.victory_type:
		BattleObjective.VictoryType.ROUT:
			return "rout"
		BattleObjective.VictoryType.DEFEAT_BOSS:
			return "boss"
		BattleObjective.VictoryType.DEFEAT_AMOUNT:
			return "defeat_amount"
		BattleObjective.VictoryType.ESCAPE:
			return "escape"
		BattleObjective.VictoryType.DEFEND:
			return "defend"
		BattleObjective.VictoryType.ACTIVATE:
			return "activate"
		_:
			return "rout"



func _handle_attack_click(tile: Vector2i) -> void:
	if selected_unit == null:
		return

	var target = _get_unit_at_tile(tile)
	if target == null:
		return
	if not selected_unit.is_enemy_of(target):
		return
	if not _is_in_attack_range(selected_unit, target):
		print("Enemy is out of attack range.")
		return

	combat_manager.perform_attack(selected_unit, target)
	selected_unit = null
	_update_selection_ring(null)
	input_mode = InputMode.FREE
	clear_all_ranges()
	action_menu.hide_menu()
	skill_menu.hide_menu()
	_queue_enemy_intents_refresh()

func _handle_skill_target_click(tile: Vector2i) -> void:
	print("DEBUG SKILL TARGET: selected_unit =", selected_unit, " _current_skill =", _current_skill)

	if selected_unit == null or _current_skill == null:
		print("Skill target click aborted: no selected_unit or _current_skill")
		return

	var skill: Skill = _current_skill
	var target = _get_unit_at_tile(tile)

	print("Skill click:", skill.name, "at tile:", tile, "target:", target)

	# -------------------------------------------------
	# TILE-TARGET SKILLS (Terrain objects + tile modifiers like vines/fire)
	# -------------------------------------------------
	if skill.target_type == Skill.TargetType.TILE or skill.effect_type == Skill.EffectType.TERRAIN:
		if combat_manager == null:
			push_error("Tile-skill cast failed: combat_manager is null.")
			return

		combat_manager.execute_skill_on_tile(selected_unit, skill, tile)

		_play_deselect_fx(selected_unit)
		selected_unit = null
		_update_selection_ring(null)
		clear_all_ranges()

		if action_menu.has_method("hide_menu"):
			action_menu.hide_menu()
		else:
			action_menu.hide()

		if skill_menu.has_method("hide_menu"):
			skill_menu.hide_menu()
		else:
			skill_menu.hide()

		input_mode = InputMode.FREE
		_queue_enemy_intents_refresh()
		return

	# -------------------------------------------------
	# AOE SKILLS (unit effects centered on tile)
	# -------------------------------------------------
	if skill.aoe_radius > 0:
		if combat_manager == null:
			push_error("AoE skill cast failed: combat_manager is null.")
			return

		combat_manager.use_skill(selected_unit, skill, tile)

		_play_deselect_fx(selected_unit)
		selected_unit = null
		_update_selection_ring(null)
		clear_all_ranges()

		if action_menu.has_method("hide_menu"):
			action_menu.hide_menu()
		else:
			action_menu.hide()

		if skill_menu.has_method("hide_menu"):
			skill_menu.hide_menu()
		else:
			skill_menu.hide()

		input_mode = InputMode.FREE
		_queue_enemy_intents_refresh()
		return

	# -------------------------------------------------
	# SINGLE-TARGET UNIT SKILLS
	# -------------------------------------------------
	if not _is_valid_skill_target(selected_unit, target, skill):
		print(" -> invalid target for this skill")
		return

	if selected_unit.mana < skill.mana_cost:
		print("Not enough mana.")
		return

	selected_unit.mana -= skill.mana_cost

	if skill_system != null:
		skill_system.execute_skill_on_target(selected_unit, target, skill)
	else:
		_execute_skill_on_target(selected_unit, target, skill)

	selected_unit.has_acted = true

	_play_deselect_fx(selected_unit)
	selected_unit = null
	_update_selection_ring(null)
	clear_all_ranges()

	if action_menu.has_method("hide_menu"):
		action_menu.hide_menu()
	else:
		action_menu.hide()

	if skill_menu.has_method("hide_menu"):
		skill_menu.hide_menu()
	else:
		skill_menu.hide()

	input_mode = InputMode.FREE
	_queue_enemy_intents_refresh()








func _try_cast_skill_at_tile(tile: Vector2i) -> void:
	if selected_unit == null:
		return
	if selected_unit.team != "player":
		return
	if selected_unit.has_acted:
		return

	if selected_unit.skills.is_empty():
		print(selected_unit.name, "has no skills.")
		return

	var skill = selected_unit.skills[0]  # first skill for now
	if skill == null:
		return

	combat_manager.use_skill(selected_unit, skill, tile)

	# Clear selection and range after casting
	selected_unit = null
	_update_selection_ring(null)
	clear_all_ranges()

func _try_select_unit_at_tile(tile: Vector2i) -> void:
	var unit = _get_unit_at_tile(tile)
	print("Tile:", tile, "unit:", unit)

	# Clicked on a player unit
	if unit != null and unit.team == "player":
		if unit.has_acted:
			print("Unit already acted this turn.")
			return

		# Clear previous selection visuals
		if selected_unit != null and selected_unit.has_node("Sprite2D"):
			selected_unit.get_node("Sprite2D").modulate = Color.WHITE
			_play_deselect_fx(selected_unit)

		selected_unit = unit
		_update_selection_ring(selected_unit)
		_focus_camera_on_unit(selected_unit)
		input_mode = InputMode.AWAIT_ACTION
		clear_all_ranges()

		if selected_unit.has_node("Sprite2D"):
			selected_unit.get_node("Sprite2D").modulate = Color(0.7, 1.0, 0.7)

		action_menu.show_for_unit(selected_unit)

	else:
		# Clicked empty or non-player: clear selection
		if selected_unit != null and selected_unit.has_node("Sprite2D"):
			selected_unit.get_node("Sprite2D").modulate = Color.WHITE
				# 🔹 Apply tile hazards (e.g. spikes) AFTER finishing the move
		_apply_tile_hazard_for_unit(selected_unit)
		selected_unit = null
		input_mode = InputMode.FREE
		_play_select_fx(selected_unit)
		clear_all_ranges()
		action_menu.hide_menu()
		skill_menu.hide_menu()
		# 🔹 Hide ring
		_update_selection_ring(null)

func _try_move_selected_unit_to_tile(tile: Vector2i) -> void:
	if selected_unit == null:
		return

	if selected_unit.team != "player":
		return

	# Check debuff like Fatigue / Root
	if not _unit_can_move(selected_unit):
		return

	# 🔹 NEW: movement lock debuff check
	if selected_unit.has_method("has_status_prevent_move") and selected_unit.has_status_prevent_move():
		print(selected_unit.name, "is affected by a movement-lock debuff and can't move.")
		return

	var target_unit = _get_unit_at_tile(tile)

	# 1) If there's an enemy on this tile and it's in attack range -> ATTACK
	if target_unit != null and selected_unit.is_enemy_of(target_unit):
		if _is_in_attack_range(selected_unit, target_unit):
			combat_manager.perform_attack(selected_unit, target_unit)
		else:
			print("Enemy is out of attack range.")
			selected_unit = null
			_update_selection_ring(null)
			clear_all_ranges()
		return

	# 2) Otherwise, try to MOVE (only if tile is empty)
	if target_unit != null:
		# Occupied by ally or something else – no movement
		return

	# Use terrain-aware reachable tiles
	var reachable_tiles: Array[Vector2i] = get_reachable_tiles_for_unit(selected_unit)
	if not reachable_tiles.has(tile):
		print("Tile is not reachable according to terrain/pathfinding.")
		return

	# If we get here, tile is reachable and free
	selected_unit.grid_position = tile
	selected_unit.position = grid.tile_to_world(tile)
	selected_unit.has_acted = true
	_queue_enemy_intents_refresh()

	if selected_unit.has_node("Sprite2D"):
		selected_unit.get_node("Sprite2D").modulate = Color.WHITE

	selected_unit = null
	_update_selection_ring(null)
	clear_all_ranges()

	if _all_player_units_have_acted():
		turn_manager.end_turn()


#SKILL HELPER PLS
# --- SKILL EXECUTION HELPERS ---------------------------------
# This is the main entry point for applying a skill to a unit.
func _execute_skill_on_target(user, target, skill: Skill) -> void:
	if user == null or skill == null:
		return

	match skill.effect_type:
		Skill.EffectType.HEAL:
			_apply_skill_heal(user, target, skill)

		Skill.EffectType.BUFF, Skill.EffectType.DEBUFF:
			_apply_status_skill(user, target, skill)

		Skill.EffectType.TERRAIN:
			# Terrain manipulation skills are usually handled via tile targeting
			# (is_terrain_object_skill path). If a TERRAIN skill somehow targets
			# a unit, we just log it for now.
			print("Terrain skill targeted a unit; no direct unit effect implemented.")

		Skill.EffectType.DAMAGE:
			# 🔹 This is what Fireball / Lightning Bolt / etc. need
			_apply_skill_damage(user, target, skill)

		_:
			# Fallback: treat unknown types as damage, just in case.
			_apply_skill_damage(user, target, skill)



func _apply_skill_heal(user, target, skill: Skill) -> void:
	if target == null or skill == null:
		return

	var base_magic: int = user.atk  # later you can use user.magic if you add it
	var raw: float = float(base_magic) * skill.power_multiplier + float(skill.flat_power)
	var amount: int = int(round(raw))
	if amount < 1:
		amount = 1

	var new_hp: int = min(target.hp + amount, target.max_hp)
	var actual_heal: int = new_hp - target.hp
	if actual_heal <= 0:
		return

	target.hp = new_hp
	if target.has_method("update_hp_bar"):
		target.update_hp_bar()

	# Optional: heal popup / SFX here


func _apply_skill_damage(user, target, skill: Skill) -> void:
	if user == null or target == null or skill == null:
		return

	# Base offensive stat – later you can branch on magic vs physical
	var base_attack: int = user.atk

	var raw: float = float(base_attack) * skill.power_multiplier + float(skill.flat_power)
	var amount: int = int(round(raw))
	if amount < 1:
		amount = 1

	# 🔹 Use the same damage pipeline as basic attacks
	var survived: bool = target.take_damage(amount)

	# Optional: print / popups / SFX
	print(user.name, " hits ", target.name, " with ", skill.name, " for ", amount, " damage (skill).")

	# If you want, you can branch on survived:
	# if not survived:
	#     # extra VFX or log on kill
	#     pass




func _is_valid_skill_target(user, target, skill: Skill) -> bool:
	if target == null:
		return false
	if target.hp <= 0:
		return false
	if target == user and not skill.can_target_self:
		return false

	var is_ally: bool = (target.team == user.team)
	var is_enemy: bool = (target.team != user.team)

	match skill.target_type:
		Skill.TargetType.ENEMY_UNITS:
			return is_enemy
		Skill.TargetType.ALLY_UNITS:
			return is_ally
		Skill.TargetType.ALL_UNITS:
			return true
		Skill.TargetType.SELF:
			return target == user
		Skill.TargetType.TILE:
			return true  # tile targeting only

	return false


# --- BUFF / DEBUFF APPLICATION -------------------------
func _apply_status_skill(user, target, skill: Skill) -> void:
	if user == null or target == null or skill == null:
		return

	# StatusManager should be an Autoload (Project Settings → Autoload)
	if StatusManager != null and StatusManager.has_method("apply_status_to_unit"):
		StatusManager.apply_status_to_unit(target, skill, user)
	else:
		push_warning("StatusManager missing or has no apply_status_to_unit(). Did you set it as an Autoload named 'StatusManager'?")

	# Optional immediate refresh (if your unit has such a method)
	if target.has_method("refresh_status_icons"):
		target.refresh_status_icons()


func _all_player_units_have_acted() -> bool:
	for child in units.get_children():
		if child.team == "player" and not child.has_acted:
			return false
	return true


func _get_unit_at_tile(tile: Vector2i):
	for child in units.get_children():
		if child.grid_position == tile:
			return child
	return null


func get_move_range(center: Vector2i, max_range: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-max_range, max_range + 1):
		for dy in range(-max_range, max_range + 1):
			var pos := center + Vector2i(dx, dy)
			if abs(dx) + abs(dy) <= max_range:
				result.append(pos)
	return result

#UNIT CAN MOVE HELPER
func _unit_can_move(u) -> bool:
	if u == null:
		return false

	# If the unit has no status system, just allow movement
	if not u.has_method("has_status_flag"):
		return true

	if u.has_status_flag("prevent_move"):
		print(u.name, "is afflicted by fatigue and cannot move!")
		return false

	return true


func show_move_range(unit) -> void:
	# If unit is rooted / fatigued, do not show any move tiles
	if not _unit_can_move(unit):
		return

	clear_move_range()

	if range_tile_scene == null:
		push_error("range_tile_scene is not assigned in the inspector!")
		return

	var tiles: Array[Vector2i] = get_reachable_tiles_for_unit(unit)

	for tile in tiles:
		var rt = range_tile_scene.instantiate()
		overlay.add_child(rt)
		rt.position = grid.tile_to_world(tile)
		active_range_tiles.append(rt)


func clear_move_range() -> void:
	for rt in active_range_tiles:
		if is_instance_valid(rt):
			rt.queue_free()
	active_range_tiles.clear()

func _on_phase_changed(new_phase) -> void:
	match new_phase:
		turn_manager.Phase.PLAYER:
			if battle_finished:
				return

			
			# Tick player timed statuses at the start of their phase
			if StatusManager != null and StatusManager.has_method("tick_team"):
				StatusManager.tick_team("player")
				
			# Tick tile effects at start of PLAYER phase (Option A)
			if grid != null and grid.has_method("tick_tile_effects"):
				grid.tick_tile_effects()


			# Player's turn begins.
			if _first_player_phase_done:
				run_turns += 1

			else:
				_first_player_phase_done = true
				
			if CombatLog != null:
				CombatLog.set_turn_index(run_turns)
				print("PLAYER PHASE - Turn:", run_turns)
				
			_reset_player_units()
			# ⚠️ Legacy terrain-effect ticking:
			# If this function also decrements vines/fire/etc durations,
			# you should remove that logic to avoid double-ticking.
			_advance_terrain_effects_one_turn()
			_log_turn_banner("PLAYER")
			# Recompute enemy intents at the start of player phase
			_update_enemy_intents()

		turn_manager.Phase.ENEMY:
			if battle_finished:
				return
			if CombatLog != null:
				CombatLog.set_turn_index(run_turns)
			_log_turn_banner("ENEMY")
			# Tick enemy timed statuses at the start of their phase
			if StatusManager != null and StatusManager.has_method("tick_team"):
				StatusManager.tick_team("enemy")

			# Tick tile effects at start of ENEMY phase (Option A)
			if grid != null and grid.has_method("tick_tile_effects"):
				grid.tick_tile_effects()



			print("ENEMY PHASE")
			_run_enemy_turn()




func _reset_player_units() -> void:
	for child in units.get_children():
		if child.team == "player":
			child.reset_for_new_turn()
			# Optional: clear any "acted" tint
			if child.has_node("Sprite2D"):
				child.get_node("Sprite2D").modulate = Color.WHITE

#ATTACK
func _distance(a: Vector2i, b: Vector2i) -> int: # I'm not redoing the grid range math
	return abs(a.x - b.x) + abs(a.y - b.y)


func _is_in_attack_range(attacker, target) -> bool:
	return _distance(attacker.grid_position, target.grid_position) <= attacker.attack_range

func get_attack_range(center: Vector2i, range: int) -> Array[Vector2i]:
	# For now, same diamond shape as move range but based on attack_range
	return get_move_range(center, range)



func show_attack_range(unit) -> void:
	clear_attack_range()

	if attack_tile_scene == null:
		push_error("attack_tile_scene is not assigned in the inspector!")
		return

	var tiles: Array[Vector2i] = get_fe_attack_range(unit)
	# Optional debug:
	# print("FE attack tiles:", tiles.size())

	for tile in tiles:
		var at = attack_tile_scene.instantiate()
		overlay.add_child(at)
		at.position = grid.tile_to_world(tile)
		active_attack_tiles.append(at)

func _show_enemy_attack_preview(enemy: Node2D) -> void:
	_clear_enemy_attack_preview()

	if attack_tile_scene == null:
		push_error("attack_tile_scene is not assigned in the inspector!")
		return

	# Reuse your FE-style attack range helper
	var tiles: Array[Vector2i] = get_fe_attack_range(enemy)

	for tile in tiles:
		var at: Node2D = attack_tile_scene.instantiate()
		overlay.add_child(at)
		at.position = grid.tile_to_world(tile)
		active_enemy_attack_tiles.append(at)


func clear_attack_range() -> void:
	for at in active_attack_tiles:
		if is_instance_valid(at):
			at.queue_free()
	active_attack_tiles.clear()
	
func _clear_enemy_attack_preview() -> void:
	for at in active_enemy_attack_tiles:
		if is_instance_valid(at):
			at.queue_free()
	active_enemy_attack_tiles.clear()
	_enemy_preview_unit = null

func clear_all_ranges() -> void:
	clear_move_range()
	clear_attack_range()
	clear_skill_preview()
	_clear_enemy_attack_preview()

func clear_skill_preview() -> void:
	for node in active_skill_preview_tiles:
		if is_instance_valid(node):
			node.queue_free()
	active_skill_preview_tiles.clear()
	last_preview_tile = Vector2i(-999, -999)

func get_reachable_tiles_for_unit(unit) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var frontier: Array[Vector2i] = []
	var cost_so_far: Dictionary = {}

	var start: Vector2i = unit.grid_position
	frontier.append(start)
	cost_so_far[start] = 0

	# 🔹 Include move buffs/debuffs
	var move_bonus: int = StatusManager.get_move_bonus(unit)
	var max_steps: int = unit.move_range + move_bonus
	if max_steps < 0:
		max_steps = 0

	var directions: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]

	while frontier.size() > 0:
		var current: Vector2i = frontier.pop_front()
		var current_cost: int = cost_so_far[current]
		result.append(current)

		for dir in directions:
			var next: Vector2i = current + dir

			if not grid.is_walkable(next):
				continue

			var occupant = _get_unit_at_tile(next)
			if occupant != null and occupant != unit:
				continue

			var move_cost: int = grid.get_move_cost(next)
			if move_cost < 0:
				continue

			var new_cost: int = current_cost + move_cost
			if new_cost > max_steps:
				continue

			if cost_so_far.has(next) and new_cost >= cost_so_far[next]:
				continue

			cost_so_far[next] = new_cost
			frontier.append(next)

	result.erase(unit.grid_position)
	return result





func get_fe_attack_range(unit) -> Array[Vector2i]:
	var result := {}  # acts like a set: tile_string -> tile Vector2i

	var move_tiles: Array[Vector2i] = get_reachable_tiles_for_unit(unit)

	# Include current tile because you don't have to move to attack
	move_tiles.append(unit.grid_position)

	for move_tile in move_tiles:
		for dx in range(-unit.attack_range, unit.attack_range + 1):
			for dy in range(-unit.attack_range, unit.attack_range + 1):
				var dist: int = abs(dx) + abs(dy)     # <-- explicitly typed
				if dist == 0:
					continue  # don't attack your own tile
				if dist <= unit.attack_range:
					var attack_tile := move_tile + Vector2i(dx, dy)
					result[str(attack_tile)] = attack_tile

	# Convert dictionary values to Array[Vector2i]
	var tiles: Array[Vector2i] = []
	for key in result.keys():
		tiles.append(result[key])

	return tiles

func _get_player_units() -> Array: #Enemy AI SECTION
	var result: Array = []
	for child in units.get_children():
		if child.team == "player":
			result.append(child)
	return result


func _get_enemy_units() -> Array:
	var result: Array = []
	for child in units.get_children():
		if child.team == "enemy":
			result.append(child)
	return result


func _is_tile_occupied(tile: Vector2i) -> bool:
	# Units block
	if _get_unit_at_tile(tile) != null:
		return true

	# Non-walkable terrain blocks
	if grid != null and grid.has_method("is_walkable"):
		if not grid.is_walkable(tile):
			return true

	# Terrain effect scenes that block movement also block
	var eff: TerrainEffect = _get_terrain_effect_at_tile(tile)
	if eff != null and eff.blocks_movement:
		return true

	return false

func _run_enemy_turn() -> void:
	print("Enemy phase: starting AI")

	var enemies: Array = _get_enemy_units()
	var players: Array = _get_player_units()

	if players.is_empty():
		print("No player units left.")
		turn_manager.end_turn()
		return

	for enemy in enemies:
		if battle_finished:
			return
		if enemy == null or not is_instance_valid(enemy):
			continue
		if enemy.hp <= 0:
			continue

		if enemy_ai != null:
			# Soft focus camera on the acting enemy (if the camera supports it)
			if camera != null and camera.has_method("soft_focus_unit"):
				camera.soft_focus_unit(enemy, 1.78, 0.18)
			# small "thinking" pause before this enemy acts
			await get_tree().create_timer(enemy_think_delay).timeout
			# ✅ SEQUENTIAL: wait for this enemy's move/attack/cast to finish
			await enemy_ai.take_turn(self, enemy, players)
			# readability pause between enemies
			await get_tree().create_timer(enemy_between_enemies_delay).timeout
		# small readability pause between enemies (tweak to taste)
		await get_tree().create_timer(0.30).timeout

	print("Enemy phase done, back to player.")
	# Give control back to player camera (if supported)
	if camera != null and camera.has_method("restore_player_control"):
		camera.restore_player_control(0.18)
	turn_manager.end_turn()


func _on_unit_died(unit) -> void:
	print("Unit died in Main:", unit.name, "team:", unit.team)
	if unit == null:
		return
	if CombatLog != null:
		CombatLog.add("%s has fallen!" % unit.name, {"type":"ko"})
		
	if unit.team == "enemy":
		enemies_defeated += 1
	elif unit.team == "player":
		players_defeated += 1

	# Defer to ensure groups / tree update is complete
	call_deferred("_check_victory_defeat")


# UNITS FOR RUN SPAWN CODE
func spawn_units_from_run() -> void:
	if unit_scene == null:
		push_error("Main: 'unit_scene' is not assigned!")
		return

	# If no run is active or no deployed units, fall back to old test spawn.
	if not RunManager.run_active or RunManager.deployed_units.is_empty():
		print("Main: No deployed_units found, falling back to spawn_test_units().")
		spawn_test_units()
		return

	# Simple starting positions for player units (tile coords).
	# You can change these later or use proper spawn markers.
	var spawn_tiles: Array[Vector2i] = [
		Vector2i(2, 2),
		Vector2i(3, 2),
		Vector2i(2, 3),
		Vector2i(3, 3),
	]

	var i: int = 0
	for data in RunManager.deployed_units:
		if i >= spawn_tiles.size():
			break
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		var tile: Vector2i = spawn_tiles[i]

		var u: Node2D = unit_scene.instantiate()

		u.team = "player"
		u.unit_class = cls
		u.level = data.level
		u.exp = data.exp
		u.unit_data = data      # direct assignment so Unit.gd can read it

		u.name = cls.display_name
		u.grid_position = tile
		u.position = grid.tile_to_world(tile)

		units.add_child(u)
		i += 1
		_hook_unit_for_combat_log(u)

# After all player units are spawned, spawn enemies.
	if enemy_spawner != null:
		enemy_spawner.spawn_enemies_for_floor(RunManager.current_floor, spawn_tiles)

		# ✅ IMPORTANT: EnemySpawnManager awaits a frame before add_child(),
		# so connect signals *after* that frame.
		await get_tree().process_frame
		for child in units.get_children():
			_connect_unit_signals(child)
	else:
	# existing fallback...

		# Fallback: spawn a single generic enemy so you can still test combat
		var enemy_tile := Vector2i(8, 4)
		var e: Node2D = unit_scene.instantiate()
		e.team = "enemy"
		e.name = "Enemy"
		e.grid_position = enemy_tile
		e.position = grid.tile_to_world(enemy_tile)
		units.add_child(e)
	

	_initial_player_unit_count = get_tree().get_nodes_in_group("player_units").size()


#ENEMY INTENT ICON HELPER
func _update_enemy_intents() -> void:
	var enemies: Array = _get_enemy_units()
	var players: Array = _get_player_units()

	for e in enemies:
		if e == null or e.hp <= 0:
			continue

		var intent: String = "wait"
		if enemy_ai != null:
			intent = enemy_ai.get_intent(self, e, players)

		if e.has_method("set_intent_icon"):
			e.set_intent_icon(intent)



# Menu Handler
func _on_action_menu_selected(action_name: String) -> void:
	print("[Main] Action selected:", action_name)
	
		# 🔊 Confirm sound for menu option
	if sfx_confirm != null:
		sfx_confirm.play()

	if selected_unit == null:
		print("[Main] No selected unit when action chosen.")
		return

	clear_all_ranges()

	match action_name:
		"move":
	# Check for movement-preventing debuff (e.g. Fatigue)
			if not _unit_can_move(selected_unit):
		# Optional: play a “bonk” SFX or flash the unit
				return

			input_mode = InputMode.MOVE
			show_move_range(selected_unit)


		"attack":
			input_mode = InputMode.ATTACK
			show_attack_range(selected_unit)

		"skill":
						# 🔹 Check for silence / prevent_arcana
			if selected_unit.has_method("can_cast_arcana") and not selected_unit.can_cast_arcana():
				print("This unit cannot cast Arcana right now.")
				return
			input_mode = InputMode.AWAIT_ACTION
			skill_menu.show_for_unit(selected_unit)

		"wait":
			selected_unit.has_acted = true
			
			
			# 🔹 Apply hazard when the unit ends its action on this tile
			_apply_tile_hazard_for_unit(selected_unit)
	
			if selected_unit.has_node("Sprite2D"):
				selected_unit.get_node("Sprite2D").modulate = Color.WHITE

			selected_unit = null
			_update_selection_ring(null)
			input_mode = InputMode.FREE
			clear_all_ranges()
			skill_menu.hide_menu()
			action_menu.hide_menu()
			_queue_enemy_intents_refresh()

			if _all_player_units_have_acted():
				turn_manager.end_turn()


func _on_skill_menu_selected(skill) -> void:
	print("[Main] Skill chosen:", skill.name)

	if selected_unit == null:
		print("[Main] No unit selected for skill.")
		return

	pending_skill = skill
	input_mode = InputMode.SKILL_TARGET
	clear_all_ranges()

func _on_skill_menu_skill_selected(skill: Skill) -> void:
	if selected_unit == null:
		print("Skill selected but no selected_unit!")
		return

	_current_skill = skill
	input_mode = InputMode.SKILL_TARGET
	clear_all_ranges()

	print("Skill selected:", _current_skill.name, "for unit:", selected_unit.name)


	
# AOE Skill danger zone
func _get_skill_aoe_tiles(skill, center_tile: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	if skill.aoe_radius <= 0:
		tiles.append(center_tile)
		return tiles

	for dx in range(-skill.aoe_radius, skill.aoe_radius + 1):
		for dy in range(-skill.aoe_radius, skill.aoe_radius + 1):
			var d: int = abs(dx) + abs(dy)
			if d <= skill.aoe_radius:
				tiles.append(center_tile + Vector2i(dx, dy))

	return tiles

func _process(_delta: float) -> void:
	# Only preview AoE while selecting a target for a skill
	if input_mode == InputMode.SKILL_TARGET and pending_skill != null and selected_unit != null:
		var tile: Vector2i = grid.cursor_tile

		# Optional: only preview if tile is within cast range
		var dist_to_center: int = abs(selected_unit.grid_position.x - tile.x) \
			+ abs(selected_unit.grid_position.y - tile.y)
		if dist_to_center > pending_skill.cast_range:
			clear_skill_preview()
			return

		if tile != last_preview_tile:
			clear_skill_preview()

			var aoe_tiles: Array[Vector2i] = _get_skill_aoe_tiles(pending_skill, tile)
			for t in aoe_tiles:
				var inst = range_tile_scene.instantiate()
				overlay.add_child(inst)
				inst.position = grid.tile_to_world(t)
				active_skill_preview_tiles.append(inst)

			last_preview_tile = tile
	else:
		# Not in skill targeting mode – make sure preview is off
		if active_skill_preview_tiles.size() > 0:
			clear_skill_preview()
	# --- Combat forecast logic ---
	_update_combat_forecast()
	#ENEMY HOVER ATTACK PREVIEW
	_update_enemy_hover_preview()
# Camera Helper
func _focus_camera_on_unit(unit) -> void:
	if unit == null:
		return
	# Simple lerp each frame: call this from _process instead
	camera.global_position = unit.global_position

func _cancel_current_action() -> void:
	if sfx_cancel != null:
		sfx_cancel.play()
	# Always clear any range highlights / previews
	clear_all_ranges()

	# Hide skill menu if it's open
	if skill_menu != null:
		if skill_menu.has_method("hide_menu"):
			skill_menu.hide_menu()
		else:
			skill_menu.hide()

	# If we have a selected unit, decide if we go back to its action menu
	if selected_unit != null:
		match input_mode:
			InputMode.ATTACK, InputMode.SKILL_TARGET, InputMode.MOVE:
				# Go back to action selection for this unit
				action_menu.show_for_unit(selected_unit)
				input_mode = InputMode.AWAIT_ACTION
				return

			InputMode.AWAIT_ACTION:
				# Cancel selection entirely
				if selected_unit.has_node("Sprite2D"):
					selected_unit.get_node("Sprite2D").modulate = Color.WHITE
					_play_deselect_fx(selected_unit)
					_update_selection_ring(null)
				selected_unit = null
				if action_menu.has_method("hide_menu"):
					action_menu.hide_menu()
				else:
					action_menu.hide()
				input_mode = InputMode.FREE
				return

	# If we got here with no selected unit, just make sure menus are closed
	if action_menu != null:
		if action_menu.has_method("hide_menu"):
			action_menu.hide_menu()
		else:
			action_menu.hide()

	input_mode = InputMode.FREE
	_update_selection_ring(null)

func _update_combat_forecast() -> void:
	# Only show forecast when we're in ATTACK mode with a selected unit
	if input_mode != InputMode.ATTACK or selected_unit == null:
		if combat_forecast_panel != null:
			combat_forecast_panel.hide_forecast()
		return

	var tile: Vector2i = grid.cursor_tile
	var target = _get_unit_at_tile(tile)

	if target != null and target.team == "enemy":
		if combat_forecast_panel != null:
			combat_forecast_panel.show_forecast(selected_unit, target)
	else:
		if combat_forecast_panel != null:
			combat_forecast_panel.hide_forecast()

#ENEMY HOVER RANGE UPDATE HELPER
func _update_enemy_hover_preview() -> void:
	# Optional: disable enemy preview when in the middle of player actions
	if input_mode == InputMode.ATTACK \
	or input_mode == InputMode.MOVE \
	or input_mode == InputMode.SKILL_TARGET:
		_clear_enemy_attack_preview()
		return

	if grid == null:
		return

	var tile: Vector2i = grid.cursor_tile
	var unit = _get_unit_at_tile(tile)

	# Only preview enemies
	if unit != null and unit.team == "enemy" and is_instance_valid(unit):
		# If we're still hovering the same enemy, do nothing
		if unit == _enemy_preview_unit:
			return

		_enemy_preview_unit = unit
		_show_enemy_attack_preview(unit)
	else:
		_clear_enemy_attack_preview()

#TURN LABEL HELPER
func _update_turn_label() -> void:
	if turn_label != null:
		turn_label.text = "Turn %d" % current_turn

#UNIT INDEX HELPER
func _get_unacted_player_units() -> Array:
	var result: Array = []
	var units := get_tree().get_nodes_in_group("player_units")
	for u in units:
		if not u.has_acted:
			result.append(u)
	return result

func _select_unit_from_cycle(unit: Node) -> void:
	if unit == null:
		return

	# Clear previous selection visuals
	if selected_unit != null and selected_unit.has_node("Sprite2D"):
		selected_unit.get_node("Sprite2D").modulate = Color.WHITE
		_play_deselect_fx(selected_unit)
		


	selected_unit = unit
	_update_selection_ring(selected_unit)
	_focus_camera_on_unit(selected_unit)
	input_mode = InputMode.AWAIT_ACTION
	clear_all_ranges()

	if selected_unit.has_node("Sprite2D"):
		selected_unit.get_node("Sprite2D").modulate = Color(0.7, 1.0, 0.7)

	_play_select_fx(selected_unit)
	action_menu.show_for_unit(selected_unit)

func _cycle_next_unit() -> void:
	var unacted := _get_unacted_player_units()

	if unacted.is_empty():
		# Optional: feedback when everyone has acted
		print("No player units remaining that can act.")
		return

	# If we already have a selected unit that's still in the list,
	# start from its index
	if selected_unit != null and unacted.has(selected_unit):
		_unit_cycle_index = unacted.find(selected_unit)
	else:
		_unit_cycle_index = -1

	_unit_cycle_index += 1
	if _unit_cycle_index >= unacted.size():
		_unit_cycle_index = 0

	var target: Node2D = unacted[_unit_cycle_index]
	_select_unit_from_cycle(target)

#Select FX helpers
func _play_select_fx(unit: Node2D) -> void:
	if unit == null:
		return
	if not unit.has_node("Sprite2D"):
		return
		
	if sfx_select != null:
		sfx_select.play()
		
	var sprite: Sprite2D = unit.get_node("Sprite2D")

	# Kill any existing tween stored on the sprite (optional safety)
	if sprite.has_meta("select_tween"):
		var old_tween: Tween = sprite.get_meta("select_tween")
		if old_tween != null and old_tween.is_running():
			old_tween.kill()

	# Start from normal
	sprite.scale = Vector2.ONE
	sprite.modulate = Color(0.7, 1.0, 0.7)  # green-ish tint to show selection

	var t: Tween = create_tween()
	sprite.set_meta("select_tween", t)

	# Tiny "pop": scale up then back down
	t.tween_property(sprite, "scale", Vector2(1.12, 1.12), 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _play_deselect_fx(unit: Node2D) -> void:
	if sfx_deselect != null:
		sfx_deselect.play()
	if unit == null:
		return
	if not unit.has_node("Sprite2D"):
		return

	var sprite: Sprite2D = unit.get_node("Sprite2D")

	# Kill any existing tween
	if sprite.has_meta("select_tween"):
		var old_tween: Tween = sprite.get_meta("select_tween")
		if old_tween != null and old_tween.is_running():
			old_tween.kill()

	var t: Tween = create_tween()
	sprite.set_meta("select_tween", t)

	# Quick dim then restore to white
	t.tween_property(sprite, "modulate", Color(0.5, 0.5, 0.5, 1.0), 0.05) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(sprite, "modulate", Color.WHITE, 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)



#VICTORY AND DEFEAT
func _check_victory_defeat() -> void:
	# Don't evaluate win/lose if already finished.
	if battle_finished:
		return

	var player_units := get_tree().get_nodes_in_group("player_units")
	var enemy_units  := get_tree().get_nodes_in_group("enemy_units")

	print("CHECK VICTORY: players =", player_units.size(), " enemies =", enemy_units.size())

	# --- Defeat: all player units gone ---
	if player_units.is_empty():
		print(" -> All player units gone: DEFEAT")
		_on_defeat("All allied units have fallen.")
		return

	# --- Victory condition: default rout if no objective assigned ---
	if battle_objective == null:
		if enemy_units.is_empty():
			print(" -> No enemies and no battle_objective: VICTORY (fallback rout)")
			_on_victory("All enemies defeated.")
		return

	# --- Victory based on objective ---
	match battle_objective.victory_type:
		BattleObjective.VictoryType.ROUT:
			if enemy_units.is_empty():
				print(" -> ROUT objective and no enemies: VICTORY")
				_on_victory("All enemies defeated.")
		_:
			if enemy_units.is_empty():
				print(" -> Unhandled objective type but no enemies: VICTORY as rout")
				_on_victory("All enemies defeated.")



func _on_victory(reason: String) -> void:
	if battle_finished:
		return
	battle_finished = true

	print("VICTORY:", reason)

	_pending_victory_reason = reason

	# 1) Grant post-battle EXP and record who got what
	RunManager.grant_post_battle_exp(enemies_defeated)

	# 2) Spawn EXP popups over each player unit (still on map)
	_show_exp_popups_for_battle()

	# 3) Check if there are any level-up events
	var levelups: Array = RunManager.get_last_levelup_events()
	if levelups.is_empty():
		# No level-ups → go straight to victory UI
		_show_victory_ui()
	else:
		# Show level-up panel first, then victory once finished
		level_up_panel.show_for_report(levelups)


#HELPER FOR POPUP
func _show_exp_popups_for_battle() -> void:
	var report: Array = RunManager.get_last_exp_report()
	print("_show_exp_popups_for_battle: report size =", report.size())
	if report.is_empty():
		return

	# Build a lookup from UnitData -> report entry
	var by_data: Dictionary = {}
	for entry in report:
		if not entry.has("data"):
			continue
		var data = entry["data"]
		by_data[data] = entry

	# For each player unit on the map, show its gain.
	for child in units.get_children():
		# We assume children are your Unit nodes (unit.gd)
		# If you ever add non-unit children under Units, you can add a guard here.

		# Skip non-player teams
		if child.team != "player":
			continue

		# Skip if no UnitData attached
		var data = child.unit_data
		if data == null:
			continue

		if not by_data.has(data):
			continue

		var entry = by_data[data]
		var gain: int = int(entry.get("exp_gained", 0))
		var level_before: int = int(entry.get("level_before", 0))
		var level_after: int  = int(entry.get("level_after", 0))

		var leveled_up: bool = level_after > level_before

		_spawn_exp_popup_for_unit(child, gain, leveled_up)


func _build_exp_summary_text() -> String:
	var report: Array = RunManager.get_last_exp_report()
	if report.is_empty():
		return "EXP Gains: (none)"

	var text := "EXP Gains:\n"
	for entry in report:
		var name: String = entry.get("name", "Unknown")
		var gain: int = int(entry.get("exp_gained", 0))
		var lvl_b: int = int(entry.get("level_before", 0))
		var lvl_a: int = int(entry.get("level_after", 0))

		if lvl_a > lvl_b:
			text += "  %s: +%d EXP  (Lv %d → %d)\n" % [name, gain, lvl_b, lvl_a]
		else:
			text += "  %s: +%d EXP  (Lv %d)\n" % [name, gain, lvl_a]

	return text



func _on_defeat(reason: String) -> void:
	if battle_finished:
		return
	battle_finished = true

	print("DEFEAT:", reason)

	var summary_text := _build_run_summary_text()

	# Show the defeat panel UI
	defeat_detail_label.text = reason
	defeat_summary_label.text = summary_text

	defeat_panel.visible = true
	victory_panel.visible = false
	


func _on_restart_pressed() -> void:
	# Only valid if we won and the run is still active
	if not RunManager.run_active:
		# Run is over; just go back to title
		RunManager.return_to_title()
		return

	# Ask RunManager to advance the floor
	if RunManager.advance_floor():
		# There IS another floor → reload Main as next map
		get_tree().reload_current_scene()
	else:
		# No more floors → run complete. For now, also go to title.
		RunManager.return_to_title()



func _on_return_to_title_pressed() -> void:
	RunManager.return_to_title()

#HELPER FOR SUMMARY
func _build_run_summary_text() -> String:
	# Build a simple multi-line string summarizing this battle.
	var text := ""
	text += "Turns taken: %d\n" % run_turns
	text += "Enemies defeated: %d\n" % enemies_defeated
	text += "Allies lost: %d" % players_defeated
	return text
# PLAYER COUNT HELPERS
func _count_player_units_alive() -> int:
	return get_tree().get_nodes_in_group("player_units").size()


func _count_player_units_lost() -> int:
	var alive: int = _count_player_units_alive()
	var lost: int = _initial_player_unit_count - alive
	if lost < 0:
		lost = 0
	return lost

# SPawn Helper
func _spawn_unit(scene: PackedScene, grid_pos: Vector2i, team: String) -> Node2D:
	var u: Node2D = scene.instantiate()

	# Set important data BEFORE entering the tree
	u.team = team
	u.grid_position = grid_pos

	# Add under Units root so _ready() runs with correct team
	units.add_child(u)

	# Connect death signal to main handler
	if u.has_signal("died"):
		u.died.connect(_on_unit_died.bind(u))

	return u

#Rewards Screen Helper
func _go_to_rewards_screen() -> void:
	# Create rewards for this floor
	RunManager.generate_rewards_for_floor(RunManager.current_floor)

	var err = get_tree().change_scene_to_file("res://scenes/ui/RewardsScreen.tscn")
	if err != OK:
		push_error("Main: Failed to change to RewardsScreen, check path.")

# EXP POPUP HELPER

func _spawn_exp_popup_for_unit(u: Node2D, exp_gain: int, leveled_up: bool) -> void:
	if floating_text_scene == null:
		return
	if u == null or not is_instance_valid(u):
		return

	var inst: Node2D = floating_text_scene.instantiate()
	# We'll attach it under Overlay so it follows the camera like tiles
	overlay.add_child(inst)

	# Position over the unit's position
	inst.global_position = u.global_position + Vector2(0, -16)

	# Kick off its animation/text
	if inst.has_method("show_exp"):
		inst.show_exp(exp_gain, leveled_up)

#VICTORY UI HELPER
func _show_victory_ui() -> void:
	var battle_summary_text: String = _build_run_summary_text()
	var exp_summary_text: String    = _build_exp_summary_text()

	victory_detail_label.text = _pending_victory_reason
	victory_summary_label.text = battle_summary_text + "\n\n" + exp_summary_text

	victory_panel.visible = true
	defeat_panel.visible = false

#LEVELUPPANEL CALLBACK
func _on_levelup_panel_finished() -> void:
	_show_victory_ui()

#SKILL BUFF HELPERS
func _consume_next_attack_buffs(user) -> void:
	var remaining: Array = []
	for s in user.active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			remaining.append(s)
			continue

		var extra: float = float(s.get("next_attack_damage_mul", 0.0))
		if extra != 0.0:
			# This was a one-shot "next attack" modifier; drop it.
			continue

		remaining.append(s)

	user.active_statuses = remaining

func _apply_status_from_skill(user, target, skill: Skill, is_buff: bool) -> void:
	if target == null:
		return

	# Build a status dictionary from the skill's exported fields
	var status: Dictionary = {
		"id": skill.name.to_lower(),
		"name": skill.name,
		"remaining_turns": skill.duration_turns,

		"atk_mod": skill.atk_mod,
		"def_mod": skill.def_mod,
		"move_mod": skill.move_mod,
		"mana_regen_mod": skill.mana_regen_mod,

		"prevent_arcana": skill.prevent_arcana,
		"prevent_move": skill.prevent_move,

		"next_attack_damage_mul": skill.next_attack_damage_mul,
		"next_arcana_aoe_bonus": skill.next_arcana_aoe_bonus,
	}

	# For debuffs, invert positive stat bonuses
	if not is_buff:
		status["atk_mod"] = -int(status["atk_mod"])
		status["def_mod"] = -int(status["def_mod"])
		status["move_mod"] = -int(status["move_mod"])
		status["mana_regen_mod"] = -int(status["mana_regen_mod"])

	# Attach to the target unit
	target.active_statuses.append(status)
	print("Applied status", status["name"], "to", target.name)

# Terrain skill helper
func _apply_terrain_skill_at_tile(tile: Vector2i, user, skill: Skill) -> void:
	# For now we let Grid/terrain controller decide what to do.
	if grid != null and grid.has_method("apply_terrain_skill"):
		grid.apply_terrain_skill(tile, user, skill)
	else:
		print("Terrain skill cast at", tile, "but grid.apply_terrain_skill() is not implemented.")

#HAZARD TILES HELPER
func _apply_tile_hazard_for_unit(u) -> void:
	if u == null or not is_instance_valid(u):
		return

	# Use the unit's grid_position to check the terrain
	var tile: Vector2i = u.grid_position
	var info: Dictionary = grid.get_terrain_info(tile)

	var terrain_name: String = str(info.get("name", ""))
	terrain_name = terrain_name.to_lower()

	# 🔹 Simple rule for now: "spikes" terrain deals damage
	if terrain_name == "spikes":
		var dmg: int = 2   # tweak to taste
		print(u.name, "takes", dmg, "damage from spikes on tile", tile)

		# Apply damage via your existing method
		if u.has_method("take_damage"):
			u.take_damage(dmg)

#TERRAIN EFFECTS HELPER
func _get_terrain_effect_at_tile(tile: Vector2i) -> TerrainEffect:
	if terrain_effects_root == null:
		return null

	for child in terrain_effects_root.get_children():
		var eff: TerrainEffect = child as TerrainEffect
		if eff == null:
			continue
		if eff.grid_position == tile:
			return eff

	return null

func _spawn_terrain_effect(skill: Skill, tile: Vector2i, user) -> void:
	if skill.terrain_object_scene == null:
		push_error("Terrain-object skill '%s' has no terrain_object_scene set!" % skill.name)
		return

	if terrain_effects_root == null:
		push_error("Main: terrain_effects_root ($TerrainEffects) is missing.")
		return

	var inst: Node2D = skill.terrain_object_scene.instantiate()
	terrain_effects_root.add_child(inst)

	# Position in world
	inst.position = grid.tile_to_world(tile)

	# If it has TerrainEffect script, configure it
	var eff: TerrainEffect = inst as TerrainEffect
	if eff != null:
		eff.grid_position = tile

		# Key: either from skill or keep the scene default
		if skill.terrain_object_key != "":
			eff.key = skill.terrain_object_key

		# Duration: if skill has a value other than 0, override
		if skill.terrain_object_duration != 0:
			eff.duration_turns = skill.terrain_object_duration

		eff.blocks_movement = skill.terrain_object_blocks_movement
		eff.move_cost_bonus = skill.terrain_object_move_cost_bonus

	print("Spawned terrain effect for skill", skill.name, "at tile", tile)

# TERRAIN EFFECT TICK HELPER
func _advance_terrain_effects_one_turn() -> void:
	if terrain_effects_root == null:
		return

	# We tick all terrain effects once per player phase.
	for child in terrain_effects_root.get_children():
		var eff: TerrainEffect = child as TerrainEffect
		if eff == null:
			continue

		# Hook for custom logic
		eff.on_turn_start("player")

		# Duration handling
		eff.tick_duration()

#SLECTION RING HELPER
func _update_selection_ring(unit: Node2D) -> void:
	if _selection_ring == null:
		return

	# No unit → hide ring
	if unit == null or not is_instance_valid(unit):
		_selection_ring.visible = false
		if _selection_ring_tween != null and _selection_ring_tween.is_running():
			_selection_ring_tween.kill()
		return

	# Position ring
	_selection_ring.global_position = unit.global_position
	_selection_ring.visible = true

	# Kill old tween if any
	if _selection_ring_tween != null and _selection_ring_tween.is_running():
		_selection_ring_tween.kill()

	# Start a pulsing tween (scale in/out loop)
	_selection_ring.scale = Vector2.ONE
	_selection_ring_tween = create_tween()
	_selection_ring_tween.set_loops()  # infinite loop

	_selection_ring_tween.tween_property(
		_selection_ring,
		"scale",
		Vector2(1.15, 1.15),
		0.4
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_selection_ring_tween.tween_property(
		_selection_ring,
		"scale",
		Vector2(0.95, 0.95),
		0.4
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

#INTENT DEBOUNCER 
var _enemy_intents_refresh_queued: bool = false

func _queue_enemy_intents_refresh() -> void:
	if _enemy_intents_refresh_queued:
		return
	_enemy_intents_refresh_queued = true
	call_deferred("_do_enemy_intents_refresh")

func _do_enemy_intents_refresh() -> void:
	_enemy_intents_refresh_queued = false
	_update_enemy_intents()

# TURN LOG BANNER HELPER
func _log_turn_banner(phase_name: String) -> void:
	if CombatLog == null:
		return
	CombatLog.add("==== TURN %d — %s PHASE ====" % [run_turns, phase_name], {"type":"turn"})

func _hook_unit_for_combat_log(unit: Node) -> void:
	if unit == null:
		return
	if not unit.has_signal("died"):
		return

	# Connect once with a bound parameter so we know who died.
	var cb: Callable = Callable(self, "_on_unit_died").bind(unit)
	# Godot 4: use is_connected(signal_name, callable)
	if not unit.is_connected("died", cb):
		unit.connect("died", cb)

# HIt stop HANDLER
func _on_unit_attacked_feedback(attacker, defender, damage: int, is_counter: bool) -> void:
	if battle_finished:
		return
	if damage <= 0:
		return

	# Camera shake (non-invasive)
	if camera != null and camera.has_method("shake"):
		camera.shake(hit_shake_strength, hit_shake_duration)

	# Hit-stop (brief freeze)
	_do_hitstop(hitstop_duration, hitstop_time_scale)

func _do_hitstop(duration: float, scale: float) -> void:
	if _hitstop_in_progress:
		return
	_hitstop_in_progress = true
	_hitstop_async(duration, scale)

func _hitstop_async(duration: float, scale: float) -> void:
	# Run async without blocking callers
	await _hitstop_coroutine(duration, scale)

func _hitstop_coroutine(duration: float, scale: float) -> void:
	var prev := Engine.time_scale
	Engine.time_scale = scale

	# ✅ ignore_time_scale=true so this timer still counts down while frozen
	await get_tree().create_timer(duration, false, false, true).timeout

	Engine.time_scale = prev
	_hitstop_in_progress = false

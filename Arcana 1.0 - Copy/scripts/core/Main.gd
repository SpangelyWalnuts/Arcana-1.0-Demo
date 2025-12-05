extends Node2D

enum InputMode { FREE, AWAIT_ACTION, MOVE, ATTACK, SKILL_TARGET }

var _unit_cycle_index: int = -1
var current_turn: int = 1
var _turn_initialized: bool = false
var input_mode: InputMode = InputMode.FREE
var pending_skill = null
var _current_skill: Skill = null
var _initial_player_unit_count: int = 0

# --- Run statistics for summary panel ---
var run_turns: int = 1              # Turn count (starts at player phase 1)
var enemies_defeated: int = 0       # Total enemy units killed this battle
var players_defeated: int = 0       # Total player units killed this battle
var battle_finished: bool = false

# Helper to avoid incrementing turn before the first real player phase
var _first_player_phase_done: bool = false

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


@export var battle_objective: BattleObjective
@export var unit_scene: PackedScene
@export var range_tile_scene: PackedScene
@export var attack_tile_scene: PackedScene     # NEW: attack range
@export_file("*.tscn") var title_scene_path: String = "res://scenes/ui/TitleScreen.tscn"
var player_unit
var selected_unit

var active_range_tiles: Array[Node2D] = []
var active_attack_tiles: Array[Node2D] = []    # NEW: attack tiles
var active_skill_preview_tiles: Array = []
var last_preview_tile: Vector2i = Vector2i(-999, -999)


func _ready() -> void:
	spawn_units_from_run()
	turn_manager.phase_changed.connect(_on_phase_changed)
	action_menu.action_selected.connect(_on_action_menu_selected)
	skill_menu.skill_selected.connect(_on_skill_menu_selected)
	skill_menu.skill_selected.connect(_on_skill_menu_skill_selected)
	_update_turn_label()
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
	
		# Connect 'died' signal for any units already placed in the scene.
	for child in units_root.get_children():
		if child.has_signal("died"):
			child.died.connect(_on_unit_died.bind(child))

	# Make sure victory/defeat panels are hidden initially
	victory_panel.visible = false
	defeat_panel.visible = false
	
	
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


func _connect_unit_signals(u: Node) -> void:
	# Only connect if the unit actually has the signal
	if u.has_signal("died"):
		# Avoid double-connecting in case this is called more than once
		if not u.died.is_connected(_on_unit_died):
			u.died.connect(_on_unit_died.bind(u))


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
	input_mode = InputMode.FREE
	clear_all_ranges()
	action_menu.hide_menu()
	skill_menu.hide_menu()


func _handle_skill_target_click(tile: Vector2i) -> void:
	print("DEBUG SKILL TARGET: selected_unit =", selected_unit, " _current_skill =", _current_skill)
	if selected_unit == null or _current_skill == null:
		print("Skill target click aborted: no selected_unit or _current_skill")
		return

	var target = _get_unit_at_tile(tile)
	print("Skill click:", _current_skill.name, " at tile:", tile, " target:", target)

	# Generic check (works for damage + heal)
	if not _is_valid_skill_target(selected_unit, target, _current_skill):
		print(" -> invalid target for this skill")
		return

	# Mana check
	if selected_unit.mana < _current_skill.mana_cost:
		print("Not enough mana.")
		return

	# Spend mana
	selected_unit.mana -= _current_skill.mana_cost

	# Execute the effect (damage or heal)
	_execute_skill_on_target(selected_unit, target, _current_skill)

	# Mark unit as having acted and clean up
	selected_unit.has_acted = true

	_play_deselect_fx(selected_unit)
	selected_unit = null
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
		selected_unit = null
		input_mode = InputMode.FREE
		_play_select_fx(selected_unit)
		clear_all_ranges()
		action_menu.hide_menu()
		skill_menu.hide_menu()


func _try_move_selected_unit_to_tile(tile: Vector2i) -> void:
	if selected_unit == null:
		return

	if selected_unit.team != "player":
		return

	var target_unit = _get_unit_at_tile(tile)

	# 1) If there's an enemy on this tile and it's in attack range -> ATTACK
	if target_unit != null and selected_unit.is_enemy_of(target_unit):
		if _is_in_attack_range(selected_unit, target_unit):
			combat_manager.perform_attack(selected_unit, target_unit)
		else:
			print("Enemy is out of attack range.")
			selected_unit = null
			clear_all_ranges()
		return

	# 2) Otherwise, try to MOVE (only if tile is empty)
	if target_unit != null:
		# Occupied by ally or something else – no movement
		return

	# ✅ NEW: Use terrain-aware reachable tiles instead of raw distance
	var reachable_tiles: Array[Vector2i] = get_reachable_tiles_for_unit(selected_unit)
	if not reachable_tiles.has(tile):
		print("Tile is not reachable according to terrain/pathfinding.")
		return

	# If we get here, tile is reachable and free
	selected_unit.grid_position = tile
	selected_unit.position = grid.tile_to_world(tile)
	selected_unit.has_acted = true

	if selected_unit.has_node("Sprite2D"):
		selected_unit.get_node("Sprite2D").modulate = Color.WHITE

	selected_unit = null
	clear_all_ranges()

	if _all_player_units_have_acted():
		turn_manager.end_turn()




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


func show_move_range(unit) -> void:
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
			# Player's turn begins.
			if _first_player_phase_done:
				run_turns += 1
			else:
				_first_player_phase_done = true

			print("PLAYER PHASE - Turn:", run_turns)
			_reset_player_units()

		turn_manager.Phase.ENEMY:
			# Enemy's turn begins.
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



func clear_attack_range() -> void:
	for at in active_attack_tiles:
		if is_instance_valid(at):
			at.queue_free()
	active_attack_tiles.clear()

func clear_all_ranges() -> void:
	clear_move_range()
	clear_attack_range()
	clear_skill_preview()

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

			# 1) Must be walkable terrain
			if not grid.is_walkable(next):
				continue

			# 2) Don't step onto other units (but allow own starting tile)
			var occupant = _get_unit_at_tile(next)
			if occupant != null and occupant != unit:
				continue

			# 3) Add terrain move cost
			var move_cost: int = grid.get_move_cost(next)
			if move_cost < 0:
				continue

			var new_cost: int = current_cost + move_cost
			if new_cost > unit.move_range:
				continue

			# 4) If we've seen this tile with cheaper cost, skip
			if cost_so_far.has(next) and new_cost >= cost_so_far[next]:
				continue

			cost_so_far[next] = new_cost
			frontier.append(next)

	# Optional: you may want to exclude the starting tile from "move tiles"
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
	return _get_unit_at_tile(tile) != null

func _find_closest_player(enemy) -> Node:
	var players = _get_player_units()
	var closest = null
	var best_dist := 999999

	for p in players:
		var d: int = _distance(enemy.grid_position, p.grid_position)
		if d < best_dist:
			best_dist = d
			closest = p

	return closest

func _get_step_toward(from: Vector2i, to: Vector2i) -> Vector2i:
	var delta := to - from
	var step := Vector2i.ZERO

	# Move along the axis with greater distance first (simple heuristic)
	if abs(delta.x) > abs(delta.y):
		step.x = sign(delta.x)
	elif abs(delta.y) > 0:
		step.y = sign(delta.y)

	return from + step

func _run_enemy_turn() -> void:
	print("Enemy phase: starting AI")

	var enemies = _get_enemy_units()
	var players = _get_player_units()

	if players.is_empty():
		print("No player units left.")
		turn_manager.end_turn()
		return

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.hp <= 0:
			continue

		var target = _find_closest_player(enemy)
		if target == null or not is_instance_valid(target):
			continue

		var dist_to_target: int = _distance(enemy.grid_position, target.grid_position)

		# If in attack range, attack
		if dist_to_target <= enemy.attack_range:
			print(enemy.name, "attacks", target.name, "during enemy phase.")
			combat_manager.perform_attack(enemy, target)  # uses existing combat logic
		else:
			# Try to move one step toward the target
			var next_tile: Vector2i = _get_step_toward(enemy.grid_position, target.grid_position)

			# Don't walk into occupied tiles
			if not _is_tile_occupied(next_tile):
				enemy.grid_position = next_tile
				enemy.position = grid.tile_to_world(next_tile)
				print(enemy.name, "moves to", next_tile)
			else:
				print(enemy.name, "wanted to move, but tile", next_tile, "is occupied.")

	print("Enemy phase done, back to player.")
	turn_manager.end_turn()

func _on_unit_died(unit) -> void:
	print("Unit died in Main:", unit.name, "team:", unit.team)

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

	if not RunManager.run_active or RunManager.deployed_units.is_empty():
		print("Main: No deployed_units found, falling back to spawn_test_units().")
		spawn_test_units()
		return

	var spawn_tiles: Array[Vector2i] = [
		Vector2i(2, 2),
		Vector2i(3, 2),
		Vector2i(2, 3),
		Vector2i(3, 3),
	]

	var i := 0
	for data in RunManager.deployed_units:
		if i >= spawn_tiles.size():
			break
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		var tile: Vector2i = spawn_tiles[i]

		var u = unit_scene.instantiate()

		u.team = "player"
		u.unit_class = cls
		u.level = data.level
		u.exp = data.exp
		u.unit_data = data      # ✅ direct assignment

		u.name = cls.display_name
		u.grid_position = tile
		u.position = grid.tile_to_world(tile)

		units.add_child(u)
		i += 1

	var enemy_tile := Vector2i(8, 4)
	var e = unit_scene.instantiate()
	e.team = "enemy"
	e.name = "Enemy"
	e.grid_position = enemy_tile
	e.position = grid.tile_to_world(enemy_tile)
	units.add_child(e)

	_initial_player_unit_count = get_tree().get_nodes_in_group("player_units").size()



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
			input_mode = InputMode.MOVE
			show_move_range(selected_unit)

		"attack":
			input_mode = InputMode.ATTACK
			show_attack_range(selected_unit)

		"skill":
			input_mode = InputMode.AWAIT_ACTION
			skill_menu.show_for_unit(selected_unit)

		"wait":
			selected_unit.has_acted = true
			if selected_unit.has_node("Sprite2D"):
				selected_unit.get_node("Sprite2D").modulate = Color.WHITE

			selected_unit = null
			input_mode = InputMode.FREE
			clear_all_ranges()
			skill_menu.hide_menu()
			action_menu.hide_menu()

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

#SKILL STUFF HEALING
func _execute_skill_on_target(user, target, skill: Skill) -> void:
	if skill == null or target == null:
		return

	if skill.is_heal:
		_apply_skill_heal(user, target, skill)
	else:
		_apply_skill_damage(user, target, skill)



func _apply_skill_heal(user, target, skill: Skill) -> void:
	# You can switch to user.magic later if you add that stat
	var base_magic: int = user.atk

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

	# Optional: heal popup / SFX
	# _spawn_heal_popup(target, actual_heal)


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
			return true

	return false



func _apply_skill_damage(user, target, skill: Skill) -> void:
	# Base offensive stat – if you later add user.magic, you can branch here per skill
	var base_attack: int = user.atk

	var raw: float = float(base_attack) * skill.power_multiplier + float(skill.flat_power)
	var amount: int = int(round(raw))
	if amount < 1:
		amount = 1

	target.hp = max(target.hp - amount, 0)
	if target.has_method("update_hp_bar"):
		target.update_hp_bar()

	# Optional: damage popup / SFX
	# _spawn_damage_popup(target, amount)

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

	# Build summary text from your tracked run stats
	var summary_text := _build_run_summary_text()

	# Show the victory panel UI
	victory_detail_label.text = reason
	victory_summary_label.text = summary_text

	victory_panel.visible = true
	defeat_panel.visible = false


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

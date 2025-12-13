extends Node
class_name EnemySpawnManager

# --- References you set in the inspector ---
@export var grid: Node                   # your GridController (has get_terrain_info, tile_to_world, etc.)
@export var units_root: Node2D           # usually $Units
@export var unit_scene: PackedScene      # your Unit.tscn

# --- Class pools by ROLE ---
@export var offense_classes: Array[UnitClass] = []
@export var defense_classes: Array[UnitClass] = []
@export var support_classes: Array[UnitClass] = []

# Minimum distance in tiles from player spawn tiles
@export var min_spawn_distance: int = 4

const MAX_TILE_ATTEMPTS: int = 200


# ----------------------------------------------------
#  PUBLIC ENTRY POINT
# ----------------------------------------------------
func spawn_enemies_for_floor(
	floor: int,
	player_spawn_tiles: Array[Vector2i]
) -> void:
	if grid == null or units_root == null or unit_scene == null:
		push_error("EnemySpawnManager: missing grid / units_root / unit_scene references.")
		return

	var enemy_count: int     = _get_enemy_count_for_floor(floor)
	var elite_chance: float  = _get_elite_chance_for_floor(floor)
	var arcana_chance: float = _get_arcana_chance_for_floor(floor)

	print("EnemySpawnManager: spawning %d enemies (floor %d)" % [enemy_count, floor])

	var candidate_tiles: Array[Vector2i] = _collect_candidate_tiles(player_spawn_tiles)
	print("EnemySpawnManager: candidate tiles (filtered) =", candidate_tiles.size())
	if candidate_tiles.is_empty():
		push_warning("EnemySpawnManager: no candidate tiles found, aborting.")
		return

	for i in range(enemy_count):
		var pick := _pick_role_and_class_for_floor(floor)
		if pick.is_empty():
			continue

		var role: String = String(pick.get("role", "offense"))
		var cls: UnitClass = pick.get("class", null)
		if cls == null:
			continue

		if candidate_tiles.is_empty():
			break

		var tile: Vector2i = _pick_spawn_tile(candidate_tiles)
		var is_elite: bool = randf() < elite_chance

		_spawn_enemy_at_tile(role, cls, tile, floor, is_elite, arcana_chance)


# ----------------------------------------------------
#  ENEMY COUNT / SCALING HELPERS
# ----------------------------------------------------
func _get_enemy_count_for_floor(floor: int) -> int:
	if floor <= 4:
		return randi_range(4, 6)
	elif floor <= 8:
		return randi_range(6, 9)
	elif floor <= 12:
		return randi_range(8, 12)
	else:
		return randi_range(10, 16)


func _get_elite_chance_for_floor(floor: int) -> float:
	if floor <= 4:
		return 0.05
	elif floor <= 8:
		return 0.15
	elif floor <= 12:
		return 0.3
	else:
		return 0.5


func _get_arcana_chance_for_floor(floor: int) -> float:
	if floor <= 4:
		return 0.1
	elif floor <= 8:
		return 0.25
	elif floor <= 12:
		return 0.5
	else:
		return 0.75


# ----------------------------------------------------
#  ROLE-BASED CLASS PICKING
# ----------------------------------------------------
func _pick_role_and_class_for_floor(floor: int) -> Dictionary:
	var w_offense: float
	var w_defense: float
	var w_support: float

	if floor <= 4:
		w_offense = 0.5
		w_defense = 0.4
		w_support = 0.1
	elif floor <= 8:
		w_offense = 0.4
		w_defense = 0.35
		w_support = 0.25
	else:
		w_offense = 0.35
		w_defense = 0.3
		w_support = 0.35

	var total: float = w_offense + w_defense + w_support
	if total <= 0.0:
		var fallback: Array[UnitClass] = []
		fallback.append_array(offense_classes)
		fallback.append_array(defense_classes)
		fallback.append_array(support_classes)
		if fallback.is_empty():
			push_error("EnemySpawnManager: no enemy classes configured!")
			return {}
		return {"role": "offense", "class": fallback[randi() % fallback.size()]}

	var roll: float = randf() * total

	if roll < w_offense and offense_classes.size() > 0:
		return {"role": "offense", "class": offense_classes[randi() % offense_classes.size()]}
	roll -= w_offense

	if roll < w_defense and defense_classes.size() > 0:
		return {"role": "defense", "class": defense_classes[randi() % defense_classes.size()]}
	roll -= w_defense

	if support_classes.size() > 0:
		return {"role": "support", "class": support_classes[randi() % support_classes.size()]}

	# fallback
	var all_classes: Array[UnitClass] = []
	all_classes.append_array(offense_classes)
	all_classes.append_array(defense_classes)
	all_classes.append_array(support_classes)
	if all_classes.is_empty():
		push_error("EnemySpawnManager: no classes at all.")
		return {}
	return {"role": "offense", "class": all_classes[randi() % all_classes.size()]}


# ----------------------------------------------------
#  TILE SELECTION (using grid.get_terrain_info)
# ----------------------------------------------------
func _collect_candidate_tiles(player_spawns: Array[Vector2i]) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []

	if grid == null:
		return candidates

	var terrain: TileMap = grid.get_node("Terrain") as TileMap
	if terrain == null:
		push_warning("EnemySpawnManager: grid has no Terrain child.")
		return candidates

	# layer 0 – adjust if your map uses another TileMap layer index
	var used_cells: Array[Vector2i] = terrain.get_used_cells(0)

	for cell in used_cells:
		var info: Dictionary = grid.get_terrain_info(cell)

		var name: String = "void"
		var walkable: bool = false
		var move_cost: int = 99

		if info.has("name"):
			name = String(info["name"])
		if info.has("walkable"):
			walkable = bool(info["walkable"])
		if info.has("move_cost"):
			move_cost = int(info["move_cost"])

		# Reject void / non-walkable / huge move cost tiles
		if not walkable:
			continue
		if name == "void":
			continue
		if move_cost >= 50:
			continue

		# Keep distance from player start
		var too_close: bool = false
		for ps in player_spawns:
			var dist: int = abs(ps.x - cell.x) + abs(ps.y - cell.y)
			if dist < min_spawn_distance:
				too_close = true
				break
		if too_close:
			continue

		# Skip tiles already occupied by any unit
		if _has_unit_on_tile(cell):
			continue

		candidates.append(cell)

	return candidates


func _pick_spawn_tile(candidates: Array[Vector2i]) -> Vector2i:
	if candidates.is_empty():
		return Vector2i.ZERO
	return candidates.pop_front()


func _has_unit_on_tile(tile: Vector2i) -> bool:
	if units_root == null:
		return false

	for child in units_root.get_children():
		var u: Node2D = child as Node2D
		if u == null:
			continue
		if not u.has_method("take_damage"):
			continue
		if u.grid_position == tile:
			return true

	return false


# ----------------------------------------------------
#  ENEMY INSTANTIATION
# ----------------------------------------------------
func _spawn_enemy_at_tile(
	role: String,
	cls: UnitClass,
	tile: Vector2i,
	floor: int,
	is_elite: bool,
	arcana_chance: float
) -> void:
	if cls == null or unit_scene == null:
		return

	var enemy: Node2D = unit_scene.instantiate()
	if enemy == null:
		return

	# Build temporary UnitData to scale enemy stats with floor
	var data := UnitData.new()
	data.unit_class = cls

	var enemy_level: int = 1 + int(floor / 3)
	if is_elite:
		enemy_level += 1
	data.level = enemy_level
	data.exp = 0

	var bonus_levels: int = max(enemy_level - 1, 0)
	data.bonus_max_hp   = bonus_levels * 2
	data.bonus_atk      = int(bonus_levels / 2)
	data.bonus_defense  = int(bonus_levels / 2)
	data.bonus_move     = 0
	data.bonus_max_mana = int(bonus_levels / 2)

	# Arcana loadout
	data.equipped_arcana = []
	if cls.skills.size() > 0:
		if randf() < arcana_chance:
			var shuffled: Array = cls.skills.duplicate()
			shuffled.shuffle()
			for s in shuffled:
				if s != null and data.equipped_arcana.size() < 3:
					data.equipped_arcana.append(s)
		else:
			if randf() < 0.5:
				var choice = cls.skills[int(randi() % cls.skills.size())]
				if choice != null:
					data.equipped_arcana.append(choice)

	enemy.set("team", "enemy")
	enemy.set("unit_class", cls)
	enemy.set("unit_data", data)
	enemy.set("grid_position", tile)

	# ✅ Role assigned by spawn pack/group selection
	enemy.set_meta("ai_role", role)

	var world_pos: Vector2 = grid.tile_to_world(tile)
	enemy.position = world_pos

	# Elite visual: yellow-ish tint
	if is_elite and enemy.has_node("Sprite2D"):
		var sprite: Sprite2D = enemy.get_node("Sprite2D") as Sprite2D
		if sprite != null:
			sprite.modulate = Color(1.2, 1.2, 0.4, 1.0)

	var elite_tag: String = ""
	if is_elite:
		elite_tag = " (Elite)"
	enemy.name = "%s%s" % [cls.display_name, elite_tag]

	units_root.add_child(enemy)

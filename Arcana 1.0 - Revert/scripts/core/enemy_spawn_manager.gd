extends Node
class_name EnemySpawnManager

@export var grid: NodePath
@export var units_root: NodePath

@export var enemy_unit_scene: PackedScene
@export var enemies_per_floor: int = 6

# --- Class pools by ROLE (drag your UnitClass resources here) ---
@export var offense_classes: Array = []
@export var defense_classes: Array = []
@export var support_classes: Array = []

# Role weights (tweak later)
@export var weight_offense: float = 0.5
@export var weight_defense: float = 0.35
@export var weight_support: float = 0.15

# Minimum manhattan distance from any player unit's tile
@export var min_spawn_distance: int = 6

# If you want enemies to not clump, enforce a minimum spacing between enemies
@export var min_enemy_spacing: int = 1

# Arcana chance (optional)
@export var arcana_chance: float = 0.25

# Elite chance (optional)
@export var elite_chance: float = 0.10

var _rng := RandomNumberGenerator.new()

const INVALID_TILE: Vector2i = Vector2i(999999, 999999)

func _ready() -> void:
	_rng.randomize()


func spawn_enemies_for_floor(floor: int, player_tiles: Array[Vector2i]) -> void:
	var grid_node := get_node_or_null(grid)
	var units_node := get_node_or_null(units_root)

	if grid_node == null:
		push_error("EnemySpawnManager: grid path not set / invalid.")
		return
	if units_node == null:
		push_error("EnemySpawnManager: units_root path not set / invalid.")
		return
	if enemy_unit_scene == null:
		push_error("EnemySpawnManager: enemy_unit_scene is not assigned.")
		return

	# If you build the map right before spawning, give TileMap one frame
	await get_tree().process_frame

	# Get the Terrain TileMap from GridController
	var terrain: TileMap = null
	if grid_node.has_node("Terrain"):
		terrain = grid_node.get_node("Terrain") as TileMap
	elif grid_node.has_method("get_terrain_tilemap"):
		terrain = grid_node.get_terrain_tilemap() as TileMap
	else:
		push_error("EnemySpawnManager: GridController has no 'Terrain' TileMap and no get_terrain_tilemap() method.")
		return

	if terrain == null:
		push_error("EnemySpawnManager: Could not access Terrain TileMap.")
		return

	var count: int = enemies_per_floor
	print("EnemySpawnManager: spawning %d enemies (floor %d)" % [count, floor])

	# Use the actual stamped map bounds.
	var used_rect: Rect2i = terrain.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		push_error("EnemySpawnManager: terrain.get_used_rect() is empty. Map not built?")
		return

	var candidates: Array[Vector2i] = _gather_spawn_candidates(grid_node, terrain, used_rect, player_tiles, units_node)
	print("EnemySpawnManager: candidate tiles (filtered) =%d" % candidates.size())
	if candidates.size() > 0:
		print("Candidates sample:", candidates.slice(0, min(10, candidates.size())))

	if candidates.is_empty():
		push_warning("EnemySpawnManager: No valid spawn tiles found.")
		return

	_shuffle_vec2i_array(candidates)

	var spawned_tiles: Array[Vector2i] = []
	var safety: int = 0

	while spawned_tiles.size() < count and safety < 5000:
		safety += 1
		if candidates.is_empty():
			break

		# Typed pop (avoid Variant warnings-as-errors)
		var last_i: int = candidates.size() - 1
		var tile: Vector2i = candidates[last_i]
		candidates.remove_at(last_i)

		# Optional: avoid enemy clumping
		if min_enemy_spacing > 0 and _too_close_to_existing_enemies(tile, spawned_tiles, min_enemy_spacing):
			continue

		var role: String = _pick_role()
		var cls = _pick_class_for_role(role)
		if cls == null:
			push_warning("EnemySpawnManager: No UnitClass available for role '%s' (check your pools)." % role)
			continue

		var is_elite: bool = _rng.randf() < elite_chance

		_spawn_enemy_instance(grid_node, units_node, terrain, cls, role, tile, floor, is_elite)

		spawned_tiles.append(tile)

	if spawned_tiles.size() < count:
		push_warning("EnemySpawnManager: only spawned %d/%d (ran out of valid candidates)." % [spawned_tiles.size(), count])


# ----------------------------------------------------
#  Spawn one enemy (assign data BEFORE add_child, place AFTER)
# ----------------------------------------------------
func _spawn_enemy_instance(
	grid_node: Node,
	units_node: Node,
	terrain: TileMap,
	cls,
	role: String,
	tile: Vector2i,
	floor: int,
	is_elite: bool
) -> void:
	var enemy = enemy_unit_scene.instantiate()
	if enemy == null:
		return

	# --- Build UnitData safely (no compile error if you rename it later) ---
	var data: Object = null
	if ClassDB.class_exists("UnitData"):
		data = ClassDB.instantiate("UnitData")

	# Scale / setup data if possible
	if data != null:
		# unit_class
		if _has_prop(data, "unit_class"):
			data.set("unit_class", cls)

		# level
		var enemy_level: int = 1 + int(floor / 3)
		if is_elite:
			enemy_level += 1
		if _has_prop(data, "level"):
			data.set("level", enemy_level)
		if _has_prop(data, "exp"):
			data.set("exp", 0)

		# basic bonuses (optional; safe if properties exist)
		var bonus_levels: int = max(enemy_level - 1, 0)
		_set_if_has(data, "bonus_max_hp", bonus_levels * 2)
		_set_if_has(data, "bonus_atk", int(bonus_levels / 2))
		_set_if_has(data, "bonus_defense", int(bonus_levels / 2))
		_set_if_has(data, "bonus_move", 0)
		_set_if_has(data, "bonus_max_mana", int(bonus_levels / 2))

		# arcana loadout (optional)
		if _has_prop(data, "equipped_arcana") and _has_prop(cls, "skills"):
			var skills = cls.get("skills")
			if skills is Array and skills.size() > 0 and _rng.randf() < arcana_chance:
				var pool: Array = skills.duplicate()
				pool.shuffle()
				var equipped: Array = []
				for s in pool:
					if s != null and equipped.size() < 3:
						equipped.append(s)
				data.set("equipped_arcana", equipped)

	# --- IMPORTANT: assign BEFORE add_child so Unit._ready() sees it ---
	if _has_prop(enemy, "team"):
		enemy.set("team", "enemy")

	if _has_prop(enemy, "unit_class"):
		enemy.set("unit_class", cls)

	if data != null and _has_prop(enemy, "unit_data"):
		enemy.set("unit_data", data)

	if _has_prop(enemy, "grid_position"):
		enemy.set("grid_position", tile)

	# helpful metadata for AI later
	enemy.set_meta("ai_role", role)

	# Add to tree (triggers _ready())
	units_node.add_child(enemy)

	# Place (your GridController has tile_to_world; fallback to tilemap transform)
	var world_pos: Vector2
	if grid_node.has_method("tile_to_world"):
		world_pos = grid_node.tile_to_world(tile)
	else:
		var local_pos := terrain.map_to_local(tile)
		world_pos = terrain.to_global(local_pos)

	if enemy is Node2D:
		(enemy as Node2D).global_position = world_pos

	# Optional sanity
	# print("Spawned", role, "tile=", tile, "world=", world_pos, "class=", cls)


# ----------------------------------------------------
#  Candidate gathering
# ----------------------------------------------------
func _gather_spawn_candidates(grid_node, terrain: TileMap, rect: Rect2i, player_tiles: Array[Vector2i], units_node: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var t: Vector2i = Vector2i(x, y)

			if terrain.get_cell_source_id(0, t) == -1:
				continue

			if grid_node.has_method("is_walkable"):
				if not grid_node.is_walkable(t):
					continue

			if _too_close_to_any_player(t, player_tiles, min_spawn_distance):
				continue

			if _tile_occupied_by_unit(t, units_node):
				continue

			out.append(t)

	return out


func _too_close_to_any_player(tile: Vector2i, player_tiles: Array[Vector2i], min_dist: int) -> bool:
	if min_dist <= 0:
		return false
	for p in player_tiles:
		var d: int = abs(p.x - tile.x) + abs(p.y - tile.y)
		if d < min_dist:
			return true
	return false


func _too_close_to_existing_enemies(tile: Vector2i, existing: Array[Vector2i], min_spacing: int) -> bool:
	for e in existing:
		var d: int = abs(e.x - tile.x) + abs(e.y - tile.y)
		if d <= min_spacing:
			return true
	return false


func _tile_occupied_by_unit(tile: Vector2i, units_node: Node) -> bool:
	for child in units_node.get_children():
		if child == null:
			continue
		if _has_prop(child, "grid_position"):
			if child.get("grid_position") == tile:
				return true
	return false


# ----------------------------------------------------
#  Role + class selection
# ----------------------------------------------------
func _pick_role() -> String:
	var total: float = weight_offense + weight_defense + weight_support
	if total <= 0.0001:
		total = 1.0

	var r: float = _rng.randf() * total

	if r < weight_offense:
		return "offense"
	r -= weight_offense

	if r < weight_defense:
		return "defense"

	return "support"



func _pick_class_for_role(role: String):
	match role:
		"offense":
			return _pick_from_pool(offense_classes)
		"defense":
			return _pick_from_pool(defense_classes)
		"support":
			return _pick_from_pool(support_classes)
		_:
			pass

	# fallback: any pool
	var all: Array = []
	all.append_array(offense_classes)
	all.append_array(defense_classes)
	all.append_array(support_classes)
	return _pick_from_pool(all)


func _pick_from_pool(pool: Array):
	if pool == null or pool.is_empty():
		return null
	return pool[_rng.randi_range(0, pool.size() - 1)]


# ----------------------------------------------------
#  Utilities
# ----------------------------------------------------
func _shuffle_vec2i_array(arr: Array[Vector2i]) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Vector2i = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _has_prop(obj: Object, prop_name: String) -> bool:
	for p in obj.get_property_list():
		if String(p.name) == prop_name:
			return true
	return false


func _set_if_has(obj: Object, prop: String, value) -> void:
	if _has_prop(obj, prop):
		obj.set(prop, value)

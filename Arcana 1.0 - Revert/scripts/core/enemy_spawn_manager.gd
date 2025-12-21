extends Node
class_name EnemySpawnManager

@export var grid: NodePath
@export var units_root: NodePath

@export var enemy_unit_scene: PackedScene
@export var enemies_per_floor: int = 6

@export var boss_group_name: StringName = &"boss"
@export var boss_floor: bool = false
@export var encounter_tag: StringName = &"none"

# --- Class pools by ROLE (drag your UnitClass resources here) ---
@export var offense_classes: Array = []
@export var defense_classes: Array = []
@export var support_classes: Array = []

# Role weights (tweak later)
@export var weight_offense: float = 0.5
@export var weight_defense: float = 0.35
@export var weight_support: float = 0.15

# --- AI Profiles by ROLE (optional; drag AIProfile .tres here) ---
@export var offense_profiles: Array[AIProfile] = []
@export var defense_profiles: Array[AIProfile] = []
@export var support_profiles: Array[AIProfile] = []

# Minimum manhattan distance from any player unit's tile
@export var min_spawn_distance: int = 6

# If you want enemies to not clump, enforce a minimum spacing between enemies
@export var min_enemy_spacing: int = 1

# Arcana chance (optional)
@export var arcana_chance: float = 1

# Elite chance (optional)
@export var elite_chance: float = 0.10

var _rng := RandomNumberGenerator.new()

const INVALID_TILE: Vector2i = Vector2i(999999, 999999)

const DIRS_4: Array[Vector2i] = [
	Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN
]

# ----------------------------------------------------
#  Encounter compositions (group spawn plans)
# ----------------------------------------------------
const ROLE_OFFENSE: StringName = &"offense"
const ROLE_DEFENSE: StringName = &"defense"
const ROLE_SUPPORT: StringName = &"support"

# Each slot is a Dictionary:
# {
#   "role": StringName,              # required: offense/defense/support
#   "force_elite": bool,             # optional
#   "force_profile": AIProfile,      # optional (null = role pool)
#   "force_class": Resource          # optional UnitClass (null = role pool)
# }

func _flood_fill_reachable(
	grid_node: Node,
	terrain: TileMap,
	rect: Rect2i,
	starts: Array[Vector2i]
) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []

	# Seed with valid starts
	for s: Vector2i in starts:
		if not rect.has_point(s):
			continue
		if terrain.get_cell_source_id(0, s) == -1:
			continue
		if grid_node.has_method("is_walkable") and not grid_node.is_walkable(s):
			continue
		if visited.has(s):
			continue

		visited[s] = true
		queue.append(s)

	while not queue.is_empty():
		var cur: Vector2i = queue[0]
		queue.remove_at(0)

		for d: Vector2i in DIRS_4:
			var n: Vector2i = cur + d

			if not rect.has_point(n):
				continue
			if visited.has(n):
				continue
			if terrain.get_cell_source_id(0, n) == -1:
				continue
			if grid_node.has_method("is_walkable") and not grid_node.is_walkable(n):
				continue

			visited[n] = true
			queue.append(n)

	return visited


func _ready() -> void:
	_rng.randomize()

func _build_spawn_plan(tag: StringName, count: int) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	
	# Helper: push a slot
	var push_slot := func(role: StringName, force_elite: bool, force_profile: AIProfile, force_class: Resource) -> void:
		plan.append({
			"role": role,
			"force_elite": force_elite,
			"force_profile": force_profile,
			"force_class": force_class
		})

	# Default: no composition
	if tag == &"none":
		return plan

	# --- Compositions by tag (starter set) ---
	match tag:
		&"elite_guard":
			# "Anchor + Escorts" feel
			# - 1 elite defense anchor
			# - 1 support backliner
			# - rest offense pressure
			push_slot.call(ROLE_DEFENSE, true, null, null)
			if count >= 2:
				push_slot.call(ROLE_SUPPORT, false, null, null)
			for i: int in range(plan.size(), count):
				push_slot.call(ROLE_OFFENSE, false, null, null)

		&"caster_heavy":
			# "Backline battery"
			# - 2 supports
			# - 1 defense
			# - rest offense
			push_slot.call(ROLE_SUPPORT, false, null, null)
			if count >= 2:
				push_slot.call(ROLE_SUPPORT, false, null, null)
			if count >= 3:
				push_slot.call(ROLE_DEFENSE, false, null, null)
			for i2: int in range(plan.size(), count):
				push_slot.call(ROLE_OFFENSE, false, null, null)

		&"swarm":
			# "Harass pack"
			# - mostly offense, occasional support
			for i3: int in range(count):
				var r: float = _rng.randf()
				if r < 0.80:
					push_slot.call(ROLE_OFFENSE, false, null, null)
				else:
					push_slot.call(ROLE_SUPPORT, false, null, null)

		_:
			# Unknown tag: no plan
			pass
	
	return plan

func spawn_enemies_for_floor(floor: int, player_tiles: Array[Vector2i]) -> void:
	print("[BOSS DEBUG] spawn_enemies_for_floor floor=", floor, " boss_floor=", boss_floor, " elite_chance=", elite_chance)
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

	# --- Encounter tag modifiers (local, safe) ---
	var local_count: int = enemies_per_floor
	var local_elite_chance: float = elite_chance
	var local_arcana_chance: float = arcana_chance

	var local_weight_offense: float = weight_offense
	var local_weight_defense: float = weight_defense
	var local_weight_support: float = weight_support

# Boss floors already have a special identity; keep tags off there for clarity.
	var tag: StringName = encounter_tag
	if boss_floor:
		tag = &"none"

	match tag:
		&"swarm":
		# More bodies, slightly fewer elites (readability).
			local_count += 3
			local_elite_chance = max(0.0, local_elite_chance - 0.05)

		&"elite_guard":
		# Guarantee one elite (handled in loop), keep count the same.
			pass

		&"caster_heavy":
		# More "support" role + more arcana usage.
			local_weight_support += 0.25
			local_weight_offense = max(0.05, local_weight_offense - 0.10)
			local_weight_defense = max(0.05, local_weight_defense - 0.15)
			local_arcana_chance = min(1.0, local_arcana_chance + 0.20)
		_:
			pass
	var weather: StringName = &"clear"
	if RunManager != null and "current_weather" in RunManager:
		weather = RunManager.current_weather
	elif RunManager != null and RunManager.has_method("get_weather"):
		weather = RunManager.get_weather()

	var wdict: Dictionary = _apply_weather_to_role_weights(weather, local_weight_offense, local_weight_defense, local_weight_support)
	local_weight_offense = float(wdict["off"])
	local_weight_defense = float(wdict["def"])
	local_weight_support = float(wdict["sup"])


	var count: int = local_count
	var plan: Array[Dictionary] = _build_spawn_plan(tag, count)
	var plan_index: int = 0

	print("EnemySpawnManager: spawning %d enemies (floor %d) tag=%s" % [count, floor, String(tag)])

	

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
	
	var mark_boss_assigned: bool = false
	var spawned_tiles: Array[Vector2i] = []
	var safety: int = 0
	var elite_guard_assigned: bool = false


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

		var role: String = ""
		var force_elite: bool = false
		var force_profile: AIProfile = null
		var force_class: Resource = null

		if plan_index < plan.size():
			var slot: Dictionary = plan[plan_index]
			plan_index += 1

			role = String(slot.get("role", ROLE_OFFENSE))
			force_elite = bool(slot.get("force_elite", false))
			force_profile = slot.get("force_profile") as AIProfile
			force_class = slot.get("force_class") as Resource
		else:
			role = _pick_role(local_weight_offense, local_weight_defense, local_weight_support)

		var cls = null
		if force_class != null:
			cls = force_class
		else:
			cls = _pick_class_for_role(role)

		if cls == null:
			push_warning("EnemySpawnManager: No UnitClass available for role '%s' (check your pools)." % role)
			continue


		var mark_boss: bool = false

		var is_elite: bool = _rng.randf() < local_elite_chance
		if force_elite:
			is_elite = true

		# Encounter tag: guarantee one elite on elite_guard floors (non-boss).
		if tag == &"elite_guard" and not boss_floor and not elite_guard_assigned:
			is_elite = true
			elite_guard_assigned = true



		if boss_floor and not mark_boss_assigned:
			mark_boss = true
			mark_boss_assigned = true
			is_elite = true # treat boss as elite for now
			
		var saved_arcana_chance: float = arcana_chance
		arcana_chance = local_arcana_chance
		
		_spawn_enemy_instance(grid_node, units_node, terrain, cls, role, tile, floor, is_elite, mark_boss, force_profile)
		spawned_tiles.append(tile)
		
		arcana_chance = saved_arcana_chance

	if spawned_tiles.size() < count:
		push_warning("EnemySpawnManager: only spawned %d/%d (ran out of valid candidates)." % [spawned_tiles.size(), count])

	print("[BOSS DEBUG] bosses alive:", get_tree().get_nodes_in_group("boss").size())

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
	is_elite: bool,
	mark_boss: bool,
	force_profile: AIProfile = null
) -> void:
	print("[EnemySpawnManager] _spawn_enemy_instance called")
	var enemy = enemy_unit_scene.instantiate()
	if enemy == null:
		return

# --- Build UnitData (reliable for script classes) ---
	var data: UnitData = UnitData.new()

	if data != null and _has_prop(data, "ai_profile"):
		var profile: AIProfile = force_profile
		if profile == null:
			profile = _pick_profile_for_role(role)

		if profile != null:
			print("[SPAWN] assigned ai_profile:", profile.resource_path, " role=", role)
			data.set("ai_profile", profile)

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
		print("[EnemySpawnManager] data has equipped_arcana=", _has_prop(data, "equipped_arcana"),
	  " cls has skills=", _has_prop(cls, "skills"))
		if _has_prop(data, "equipped_arcana") and _has_prop(cls, "skills"):
			var skills = cls.get("skills")
			if skills is Array and skills.size() > 0:
				# Treat arcana_chance as 0..1 (clamp for safety)
				var chance := clampf(arcana_chance, 0.0, 1.0)
				var roll := _rng.randf()

				# Debug (leave this in until you're confident)
				print("[SPAWN] arcana roll=", roll, " chance=", chance, " class=", cls.get("display_name"), " pool=", skills.size())

				if roll < chance:
					var pool: Array = skills.duplicate()
					pool.shuffle()

					var equipped: Array = []
					for s in pool:
						if s != null and equipped.size() < 3:
							equipped.append(s)

					# 1) Store on UnitData (truth for UI hover/tooltips)
					data.set("equipped_arcana", equipped)

					# 2) ALSO store directly on the Unit node (truth for EnemyAI even if UnitData fails)
					if _has_prop(enemy, "skills"):
						enemy.set("skills", equipped.duplicate())

					print("[SPAWN] Enemy arcana equipped:", equipped.size(), " class=", cls.get("display_name"))
				else:
					# Explicitly clear so there's no stale data
					data.set("equipped_arcana", [])
					if _has_prop(enemy, "skills"):
						enemy.set("skills", [])



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

	if mark_boss:
		enemy.add_to_group(boss_group_name)
		enemy.set_meta("is_boss", true)
		print("[BOSS DEBUG] MARKED BOSS:", enemy.name, " group=", boss_group_name)

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
func _gather_spawn_candidates(
	grid_node: Node,
	terrain: TileMap,
	rect: Rect2i,
	player_tiles: Array[Vector2i],
	units_node: Node
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []

	# NEW: reachable region from player deployment tiles
	var reachable: Dictionary = {}
	if player_tiles != null and not player_tiles.is_empty():
		reachable = _flood_fill_reachable(grid_node, terrain, rect, player_tiles)

	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var t: Vector2i = Vector2i(x, y)

			if terrain.get_cell_source_id(0, t) == -1:
				continue

			if grid_node.has_method("is_walkable"):
				if not grid_node.is_walkable(t):
					continue

			# NEW: require reachability (only when we have valid starts)
			if not reachable.is_empty() and not reachable.has(t):
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
func _pick_role(
	w_offense: float = -1.0,
	w_defense: float = -1.0,
	w_support: float = -1.0
) -> String:
	var wo: float = weight_offense if w_offense < 0.0 else w_offense
	var wd: float = weight_defense if w_defense < 0.0 else w_defense
	var ws: float = weight_support if w_support < 0.0 else w_support

	var total: float = wo + wd + ws
	if total <= 0.0001:
		total = 1.0

	var r: float = _rng.randf() * total

	if r < wo:
		return "offense"
	r -= wo

	if r < wd:
		return "defense"

	return "support"

func _pick_profile_for_role(role: String) -> AIProfile:
	var pool: Array[AIProfile] = []
	match role:
		"offense":
			pool = offense_profiles
		"defense":
			pool = defense_profiles
		"support":
			pool = support_profiles
		_:
			pool = []

	if pool == null or pool.is_empty():
		return null

	var idx: int = _rng.randi_range(0, pool.size() - 1)
	return pool[idx]



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

#WEATHER MODIFIER HELPER
func _apply_weather_to_role_weights(weather: StringName, w_off: float, w_def: float, w_sup: float) -> Dictionary:
	var off: float = w_off
	var def: float = w_def
	var sup: float = w_sup

	match weather:
		&"snow":
			# Snow: more durable frontlines, fewer supports
			def *= 1.35
			off *= 0.95
			sup *= 0.80
		_:
			pass

	# Normalize so proportions stay sane
	var sum: float = off + def + sup
	if sum <= 0.0001:
		return {"off": 1.0, "def": 1.0, "sup": 1.0}

	return {"off": off / sum, "def": def / sum, "sup": sup / sum}

extends Node

@export var terrain: TileMap # Assign Main/Map/Terrain here in the inspector

# Backward-compatible fallback pool (used if biome pool is empty)
@export var chunk_scenes: Array[PackedScene] = []
@export var debug_chunk_gen: bool = true

# Biome-specific pools (preferred)
@export var ruins_chunk_scenes: Array[PackedScene] = []
@export var forest_chunk_scenes: Array[PackedScene] = []
@export var catacombs_chunk_scenes: Array[PackedScene] = []
@export var taiga_chunk_scenes: Array[PackedScene] = []
@export var volcano_chunk_scenes: Array[PackedScene] = []

@export var biome: StringName = &"ruins"
@export var ruins_db: BiomeChunkDB
@export var forest_db: BiomeChunkDB
@export var catacombs_db: BiomeChunkDB
@export var taiga_db: BiomeChunkDB
@export var volcano_db: BiomeChunkDB

# How many chunks wide/tall the map will be
@export var chunks_wide: int = 2
@export var chunks_high: int = 2

# Chunk size in tiles (must match how you designed the chunk TileMaps)
@export var chunk_width: int = 14
@export var chunk_height: int = 8

var _rng := RandomNumberGenerator.new()

func set_seed(seed: int) -> void:
	_rng.seed = seed

func set_biome(new_biome: StringName) -> void:
	biome = new_biome


func _get_active_chunk_pool() -> Array[PackedScene]:
	var pool: Array[PackedScene] = []

	match biome:
		&"ruins":
			pool = ruins_chunk_scenes
		&"forest":
			pool = forest_chunk_scenes
		&"catacombs":
			pool = catacombs_chunk_scenes
		&"taiga":
			pool = taiga_chunk_scenes
		&"volcano":
			pool = volcano_chunk_scenes
		_:
			pool = chunk_scenes

	# Fallback if biome pool not assigned yet
	if pool.is_empty():
		pool = chunk_scenes

	return pool

func _get_active_db() -> BiomeChunkDB:
	match biome:
		&"ruins": return ruins_db
		&"forest": return forest_db
		&"catacombs": return catacombs_db
		&"taiga": return taiga_db
		&"volcano": return volcano_db
		_: return null

@export var max_attempts: int = 50

func build_random_map() -> void:
	if terrain == null:
		push_error("MapGenerator: 'terrain' is not assigned.")
		return

	var db: BiomeChunkDB = _get_active_db()
	print("[CHUNKGEN] biome=", String(biome),
		" db=", (db.resource_path if db != null else "<null>"))

	var pool: Array[PackedScene] = []

	if db != null:
		pool = db.get_all_chunks()
		# Only allow chunks that actually have an entry (strict mode).
		var filtered: Array[PackedScene] = []
		for s in pool:
			if s == null:
				continue
			if db.get_entry(s) == null:
				push_warning("MapGenerator: Chunk missing DB entry (excluded): %s" % s.resource_path)
				continue
			filtered.append(s)
		pool = filtered
	else:
		# Fallback: old behavior if DB not assigned yet
		pool = _get_active_chunk_pool()

# Fallback is only for the legacy (no DB) mode.
	if pool.is_empty():
		if db == null:
			pool = _get_any_available_chunks()

	if pool.is_empty():
		push_error("MapGenerator: No chunks available for biome '%s' and no fallback chunks found." % String(biome))
		return


	for attempt in range(max_attempts):
		terrain.clear()

		var chosen: Array[PackedScene] = []
		chosen.resize(chunks_wide * chunks_high)

		var failed: bool = false

		for cy in range(chunks_high):
			for cx in range(chunks_wide):
				var candidates: Array[PackedScene] = pool.duplicate()
				if debug_chunk_gen:
					print("[CHUNKGEN] cell=", Vector2i(cx, cy), " biome=", String(biome), " pool=", pool.size())


				# Apply WEST constraint: must be in left.allow_east
				if db != null and cx > 0:
					var left_scene: PackedScene = chosen[cy * chunks_wide + (cx - 1)]
					var left_entry: ChunkAdjacencyEntry = db.get_entry(left_scene)

					# STRICT: empty allow_east means "nothing allowed"
					if left_entry == null:
						candidates.clear()
					else:
						candidates = _intersect_scene_lists(candidates, left_entry.allow_east)
				if debug_chunk_gen and db != null and cx > 0:
					var left_scene_dbg: PackedScene = chosen[cy * chunks_wide + (cx - 1)]
					print("[CHUNKGEN]  from WEST:", left_scene_dbg.resource_path,
						" allow_east size=", db.get_entry(left_scene_dbg).allow_east.size(),
						" candidates now=", candidates.size())

				# Apply NORTH constraint: must be in up.allow_south
				if db != null and cy > 0:
					var up_scene: PackedScene = chosen[(cy - 1) * chunks_wide + cx]
					var up_entry: ChunkAdjacencyEntry = db.get_entry(up_scene)

					# STRICT: empty allow_south means "nothing allowed"
					if up_entry == null:
						candidates.clear()
					else:
						candidates = _intersect_scene_lists(candidates, up_entry.allow_south)
				
				if debug_chunk_gen and db != null and cy > 0:
					var up_scene_dbg: PackedScene = chosen[(cy - 1) * chunks_wide + cx]
					print("[CHUNKGEN]  from NORTH:", up_scene_dbg.resource_path,
						" allow_south size=", db.get_entry(up_scene_dbg).allow_south.size(),
						" candidates now=", candidates.size())


				if candidates.is_empty():
					failed = true
					break
#				 Optional: forbid same chunk adjacent (west/north)
				if cx > 0:
					candidates.erase(chosen[cy * chunks_wide + (cx - 1)])
				if cy > 0:
					candidates.erase(chosen[(cy - 1) * chunks_wide + cx])
				
				var picked: PackedScene = _pick_weighted(db, candidates)
				chosen[cy * chunks_wide + cx] = picked
				_stamp_chunk(picked, cx, cy)
				if debug_chunk_gen:
					print("[CHUNKGEN]  picked=", picked.resource_path)


			if failed:
				break

		if not failed:
			return

	push_warning("MapGenerator: Failed to build a valid layout after %d attempts (biome=%s)." % [max_attempts, String(biome)])

func _intersect_scene_lists(a: Array[PackedScene], b: Array[PackedScene]) -> Array[PackedScene]:
	var set_b: Dictionary = {}
	for s in b:
		if s != null:
			set_b[s] = true

	var out: Array[PackedScene] = []
	for s in a:
		if s != null and set_b.has(s):
			out.append(s)
	return out

func _pick_weighted(db: BiomeChunkDB, candidates: Array[PackedScene]) -> PackedScene:
	# If no DB, or missing entries, fallback random
	if db == null:
		return candidates.pick_random()

	var total: float = 0.0
	for s in candidates:
		var e: ChunkAdjacencyEntry = db.get_entry(s)
		var w: float = 1.0
		if e != null:
			w = max(0.0, e.weight)
		total += w

	if candidates.size() > 0:
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
	var r: float = _rng.randf() * total
	for s in candidates:
		var e2: ChunkAdjacencyEntry = db.get_entry(s)
		var w2: float = 1.0
		if e2 != null:
			w2 = max(0.0, e2.weight)

		r -= w2
		if r <= 0.0:
			return s

	return candidates[candidates.size() - 1]


func _scene_key(scene: PackedScene) -> String:
	if scene == null:
		return ""
	if scene.resource_path != "":
		return scene.resource_path
	return str(scene.get_instance_id())

func _intersect_keys(a: Dictionary, b: Dictionary) -> Dictionary:
	# dictionaries as "set": key -> true
	if a.is_empty():
		return b.duplicate()
	if b.is_empty():
		return a.duplicate()

	var out: Dictionary = {}
	for k in a.keys():
		if b.has(k):
			out[k] = true
	return out


func _stamp_chunk(chunk_scene: PackedScene, cx: int, cy: int) -> void:
	var chunk_instance: Node2D = chunk_scene.instantiate()
	var chunk_tilemap: TileMap = chunk_instance.get_node("Terrain") as TileMap
	if chunk_tilemap == null:
		push_error("MapGenerator: Chunk scene %s has no 'Terrain' TileMap." % [chunk_scene.resource_path])
		chunk_instance.queue_free()
		return

	var offset := Vector2i(cx * chunk_width, cy * chunk_height)
	var layer := 0

	for cell in chunk_tilemap.get_used_cells(layer):
		var source_id := chunk_tilemap.get_cell_source_id(layer, cell)
		if source_id == -1:
			continue
		var atlas_coords := chunk_tilemap.get_cell_atlas_coords(layer, cell)
		var alternative := chunk_tilemap.get_cell_alternative_tile(layer, cell)
		terrain.set_cell(layer, cell + offset, source_id, atlas_coords, alternative)

	chunk_instance.queue_free()

func _get_any_available_chunks() -> Array[PackedScene]:
	var out: Array[PackedScene] = []

	# Prefer DBs first
	var dbs: Array[BiomeChunkDB] = [ruins_db, forest_db, catacombs_db, taiga_db, volcano_db]
	for db in dbs:
		if db == null:
			continue
		for s in db.get_all_chunks():
			if s != null:
				out.append(s)

	# If still empty, fallback to exported biome arrays + legacy chunk_scenes
	if out.is_empty():
		var arrays: Array = [
			ruins_chunk_scenes, forest_chunk_scenes, catacombs_chunk_scenes,
			taiga_chunk_scenes, volcano_chunk_scenes, chunk_scenes
		]
		for arr in arrays:
			for s in arr:
				if s != null:
					out.append(s)

	return out

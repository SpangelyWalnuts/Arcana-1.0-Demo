extends Node

@export var terrain: TileMap # Assign Main/Map/Terrain here in the inspector

# Backward-compatible fallback pool (used if biome pool is empty)
@export var chunk_scenes: Array[PackedScene] = []

# Biome-specific pools (preferred)
@export var ruins_chunk_scenes: Array[PackedScene] = []
@export var forest_chunk_scenes: Array[PackedScene] = []
@export var catacombs_chunk_scenes: Array[PackedScene] = []
@export var taiga_chunk_scenes: Array[PackedScene] = []
@export var volcano_chunk_scenes: Array[PackedScene] = []

@export var biome: StringName = &"ruins"

# How many chunks wide/tall the map will be
@export var chunks_wide: int = 2
@export var chunks_high: int = 2

# Chunk size in tiles (must match how you designed the chunk TileMaps)
@export var chunk_width: int = 14
@export var chunk_height: int = 8


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


func build_random_map() -> void:
	if terrain == null:
		push_error("MapGenerator: 'terrain' is not assigned.")
		return

	var pool: Array[PackedScene] = _get_active_chunk_pool()
	if pool.is_empty():
		push_error("MapGenerator: No chunk scenes assigned (biome '%s')." % String(biome))
		return

	terrain.clear()

	var layer := 0

	for cy in range(chunks_high):
		for cx in range(chunks_wide):
			var chunk_scene: PackedScene = pool.pick_random()
			var chunk_instance: Node2D = chunk_scene.instantiate()

			var chunk_tilemap: TileMap = chunk_instance.get_node("Terrain") as TileMap
			if chunk_tilemap == null:
				push_error("MapGenerator: Chunk scene %s has no 'Terrain' TileMap." % [chunk_scene.resource_path])
				chunk_instance.queue_free()
				continue

			var offset := Vector2i(cx * chunk_width, cy * chunk_height)

			for cell in chunk_tilemap.get_used_cells(layer):
				var source_id := chunk_tilemap.get_cell_source_id(layer, cell)
				if source_id == -1:
					continue

				var atlas_coords := chunk_tilemap.get_cell_atlas_coords(layer, cell)
				var alternative := chunk_tilemap.get_cell_alternative_tile(layer, cell)
				var target_cell := cell + offset

				terrain.set_cell(layer, target_cell, source_id, atlas_coords, alternative)

			chunk_instance.queue_free()

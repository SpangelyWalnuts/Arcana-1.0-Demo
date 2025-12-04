extends Node

@export var terrain: TileMap          # Assign Main/Map/Terrain here in the inspector
@export var chunk_scenes: Array[PackedScene] = []

# How many chunks wide/tall the map will be
@export var chunks_wide: int = 2
@export var chunks_high: int = 2

# Chunk size in tiles (must match how you designed the chunk TileMaps)
@export var chunk_width: int = 14
@export var chunk_height: int = 8


func build_random_map() -> void:
	if terrain == null:
		push_error("MapGenerator: 'terrain' is not assigned.")
		return

	if chunk_scenes.is_empty():
		push_error("MapGenerator: 'chunk_scenes' is empty.")
		return

	# Clear existing tiles
	terrain.clear()

	# For now assume single TileMap layer (layer 0)
	var layer := 0

	# Loop over chunk grid positions
	for cy in range(chunks_high):
		for cx in range(chunks_wide):
			var chunk_scene: PackedScene = chunk_scenes.pick_random()
			var chunk_instance: Node2D = chunk_scene.instantiate()

			# Expect a TileMap named "Terrain" under the chunk
			var chunk_tilemap: TileMap = chunk_instance.get_node("Terrain") as TileMap
			if chunk_tilemap == null:
				push_error("MapGenerator: Chunk scene %s has no 'Terrain' TileMap." % [chunk_scene.resource_path])
				continue

			# Offset in tiles where this chunk should be stamped
			var offset := Vector2i(cx * chunk_width, cy * chunk_height)

			# Copy all used cells from chunk_tilemap into main terrain with offset
			for cell in chunk_tilemap.get_used_cells(layer):
				var source_id := chunk_tilemap.get_cell_source_id(layer, cell)
				if source_id == -1:
					continue


				var atlas_coords := chunk_tilemap.get_cell_atlas_coords(layer, cell)
				var alternative := chunk_tilemap.get_cell_alternative_tile(layer, cell)

				var target_cell := cell + offset
				terrain.set_cell(layer, target_cell, source_id, atlas_coords, alternative)

			# Optional: free instance (we only needed it as a template)
			chunk_instance.queue_free()

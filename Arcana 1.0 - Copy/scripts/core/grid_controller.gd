# scripts/grid_controller.gd
extends Node2D
# or whatever you already have

@onready var terrain: TileMap = $Terrain


# We only have 1 atlas source, so we hardcode source_id = 0.
const TERRAIN_SOURCE_ID: int = 1

# Map logical terrain keys to atlas coords
# 🔹 CHANGE these coords to match what you see in the TileSet editor.
@export var terrain_atlas_coords: Dictionary = {
	"wall": Vector2i(4, 5),   # example
	"vines": Vector2i(5, 5),   # example
	"spikes": Vector2i(6, 5)   # example
}


@onready var cursor: Node2D  = $Cursor

var cursor_tile: Vector2i = Vector2i.ZERO

func _process(_delta: float) -> void:
	cursor_tile = get_hovered_tile()
	_update_cursor_position(cursor_tile)

func get_hovered_tile() -> Vector2i:
	var mouse_pos: Vector2 = terrain.get_local_mouse_position()
	return terrain.local_to_map(mouse_pos)

func tile_to_world(tile: Vector2i) -> Vector2:
	# IMPORTANT: use the same math that currently works for your unit/cursor.
	# If you were using offsets like -Vector2(16,16), apply them here.
	var local_pos: Vector2 = terrain.map_to_local(tile)
	var world_pos: Vector2 = terrain.to_global(local_pos)
	return world_pos - Vector2(16,16) # or world_pos - Vector2(16,16) if that’s what you use

func _update_cursor_position(tile: Vector2i) -> void:
	var world_pos: Vector2 = tile_to_world(tile)
	cursor.global_position = world_pos

# 🔹 Terrain table: key = tile source ID from your TileSet
# You MUST adjust these IDs (0,1,2,3) to match your actual tiles.
const TERRAIN_TABLE := {
	# Grass
	Vector3i(1, 7, 0): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 8, 0): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 9, 0): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 10, 0): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 11, 0): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 12, 0): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 13, 0): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 8, 1): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 9, 1): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 10, 1): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 11, 1): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 13, 1): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 12, 2): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 13, 2): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 11, 2): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 10, 2): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 9, 2): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 8, 2): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 11, 3): { "name": "grass", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 8, 4): { "name": "road", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 11, 5): { "name": "road", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 12, 5): { "name": "road", "move_cost": 1, "def": 0, "walkable": true },
	Vector3i(1, 13, 5): { "name": "road", "move_cost": 1, "def": 0, "walkable": true },
	

	# Forest
	Vector3i(1, 6, 3): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 7, 3): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 8, 3): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 9, 3): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 10, 3): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 0, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 1, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 2, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 3, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 4, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 5, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 6, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 7, 4): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 0, 5): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 1, 5): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 2, 5): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	Vector3i(1, 3, 5): { "name": "forest", "move_cost": 2, "def": 1, "walkable": true },
	#HAZARD
	Vector3i(1, 6, 5): { "name": "spikes", "move_cost": 1, "def": 0, "walkable": true },
	#FORT/CASTLE
	Vector3i(1, 5, 5): { "name": "Fort", "move_cost": 3, "def": 3, "walkable": true },
	# Mountain variants
	Vector3i(1, 0, 1): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 2, 1): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 3, 1): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 4, 1): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 5, 1): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 6, 1): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 0, 2): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 2, 2): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 3, 2): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 4, 2): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 5, 2): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 0, 3): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 2, 3): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 3, 3): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 4, 3): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
	Vector3i(1, 5, 3): { "name": "mountain", "move_cost": 99, "def": 2, "walkable": false },
}

func _get_terrain_key(tile: Vector2i) -> Vector3i:
	var layer := 0
	var source_id: int = terrain.get_cell_source_id(layer, tile)
	var atlas: Vector2i = terrain.get_cell_atlas_coords(layer, tile)
	return Vector3i(source_id, atlas.x, atlas.y)


func get_terrain_id_at(tile: Vector2i) -> int:
	# Layer 0 – adjust if your terrain is on another layer
	var id: int = terrain.get_cell_source_id(0, tile)
	return id


func get_terrain_info(tile: Vector2i) -> Dictionary:
	var key := _get_terrain_key(tile)
	if TERRAIN_TABLE.has(key):
		return TERRAIN_TABLE[key]
	# default
	return { "name": "void", "move_cost": 99, "def": 0, "walkable": false }


func get_move_cost(tile: Vector2i) -> int:
	var info: Dictionary = get_terrain_info(tile)
	return int(info["move_cost"])


func get_defense_bonus(tile: Vector2i) -> int:
	var info: Dictionary = get_terrain_info(tile)
	return int(info["def"])


func is_walkable(tile: Vector2i) -> bool:
	var info: Dictionary = get_terrain_info(tile)
	return bool(info["walkable"])

func apply_terrain_skill(tile: Vector2i, user, skill: Skill) -> void:
	if skill.terrain_tile_key == "":
		print("apply_terrain_skill: Skill", skill.name, "has empty terrain_tile_key.")
		return

	match skill.terrain_action:
		Skill.TerrainAction.SET_TILE:
			_set_terrain_tile(tile, skill.terrain_tile_key)

		Skill.TerrainAction.CLEAR_TILE:
			_clear_terrain_tile(tile)

		_:
			print("apply_terrain_skill: Unsupported TerrainAction on skill", skill.name)


#TErrain skill helpers
func _set_terrain_tile(tile: Vector2i, key: String) -> void:
	if not terrain_atlas_coords.has(key):
		print("Grid: Unknown terrain key:", key)
		return

	var atlas: Vector2i = terrain_atlas_coords[key]

	# layer = 0, source_id = TERRAIN_SOURCE_ID, atlas_coords = atlas, alt = 0
	terrain.set_cell(0, tile, TERRAIN_SOURCE_ID, atlas, 0)
	print("Grid: set tile", tile, "to", key, "atlas:", atlas)



func _clear_terrain_tile(tile: Vector2i) -> void:
	# Either erase:
	terrain.erase_cell(0, tile)
	# Or you can set_cell with -1 to clear:
	# terrain.set_cell(0, tile, -1)
	print("Grid: cleared tile", tile)

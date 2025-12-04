extends TileMap
# scripts/terrain.gd
func get_hovered_tile() -> Vector2i:
	# Use LOCAL mouse position, not global
	var mouse_pos: Vector2 = get_local_mouse_position()
	return local_to_map(mouse_pos)

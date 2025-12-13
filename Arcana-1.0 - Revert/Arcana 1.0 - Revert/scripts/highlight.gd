extends TileMap
# scripts/highlight.gd

func highlight_tile(tile: Vector2i) -> void:
	clear()
	set_cell(0, tile, 0)  # if your tile ID isn't 0, change this

func _ready() -> void:
	# Quick test: highlight (0,0) on start
	highlight_tile(Vector2i(0, 0))

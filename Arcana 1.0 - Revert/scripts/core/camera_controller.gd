extends Camera2D

@export var terrain: TileMap              # Assign your Terrain TileMap in the inspector
@export var pan_speed: float = 500.0      # pixels per second
@export var zoom_step: float = 0.1        # scroll wheel zoom step
@export var min_zoom: float = 0.5         # closer
@export var max_zoom: float = 3.0         # farther

var map_rect: Rect2 = Rect2()             # world-space rect covering the map


func _ready() -> void:
	if terrain == null:
		push_error("Camera2D: 'terrain' is not assigned.")
		return

	_compute_map_rect()
	_center_on_map()


func _compute_map_rect() -> void:
	var used: Rect2i = terrain.get_used_rect()

	if used.size == Vector2i.ZERO:
		map_rect = Rect2(Vector2.ZERO, Vector2.ZERO)
		return

	# Get tile size (in pixels)
	var tile_size: Vector2 = Vector2(32, 32)
	if terrain.tile_set != null:
		tile_size = Vector2(terrain.tile_set.tile_size)

	# Convert tile coords to pixel coords (local space of the TileMap)
	var top_left: Vector2 = Vector2(used.position) * tile_size
	var bottom_right: Vector2 = Vector2(used.position + used.size) * tile_size

	# If your Terrain node is offset, add terrain.position here
	map_rect = Rect2(
		top_left,
		bottom_right - top_left
	)


func _center_on_map() -> void:
	if map_rect.size == Vector2.ZERO:
		return

	var center: Vector2 = map_rect.position + map_rect.size * 0.5
	global_position = center
	_clamp_camera()


func _process(delta: float) -> void:
	var dir: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("camera_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("camera_right"):
		dir.x += 1.0
	if Input.is_action_pressed("camera_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("camera_down"):
		dir.y += 1.0

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		global_position += dir * pan_speed * delta
		_clamp_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(-zoom_step)   # wheel up = zoom in
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(zoom_step)    # wheel down = zoom out


func _change_zoom(amount: float) -> void:
	var new_zoom_value: float = zoom.x + amount
	new_zoom_value = clamp(new_zoom_value, min_zoom, max_zoom)

	zoom = Vector2(new_zoom_value, new_zoom_value)
	_clamp_camera()


func _clamp_camera() -> void:
	# If we don't have a valid map yet, don't clamp
	if map_rect.size == Vector2.ZERO:
		return

	# How far outside the map you're allowed to see (in pixels)
	var margin: float = 64.0

	var min_x: float = map_rect.position.x - margin
	var max_x: float = map_rect.position.x + map_rect.size.x + margin

	var min_y: float = map_rect.position.y - margin
	var max_y: float = map_rect.position.y + map_rect.size.y + margin

	global_position.x = clamp(global_position.x, min_x, max_x)
	global_position.y = clamp(global_position.y, min_y, max_y)

extends Camera2D

@export var terrain: TileMap
@export var pan_speed: float = 500.0
@export var zoom_step: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 3.0

var map_rect: Rect2


func _ready() -> void:
	_compute_map_rect()


func _compute_map_rect() -> void:
	var used: Rect2i = terrain.get_used_rect()

	var top_left     = terrain.map_to_local(used.position)
	var bottom_right = terrain.map_to_local(used.position + used.size)

	map_rect = Rect2(
		top_left,
		bottom_right - top_left
	)


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
		global_position += dir.normalized() * pan_speed * delta
		_clamp_camera()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_change_zoom(-zoom_step)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_change_zoom(zoom_step)


func _change_zoom(amount: float) -> void:
	var new_zoom = zoom.x + amount
	new_zoom = clamp(new_zoom, min_zoom, max_zoom)

	zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera()


func _clamp_camera() -> void:
	if map_rect.size == Vector2.ZERO:
		return

	var half_screen := get_viewport_rect().size * 0.5 * zoom

	var min_x = map_rect.position.x + half_screen.x
	var max_x = map_rect.position.x + map_rect.size.x - half_screen.x

	var min_y = map_rect.position.y + half_screen.y
	var max_y = map_rect.position.y + map_rect.size.y - half_screen.y

	global_position.x = clamp(global_position.x, min_x, max_x)
	global_position.y = clamp(global_position.y, min_y, max_y)

extends Camera2D

@export var terrain: TileMap              # Assign your Terrain TileMap in the inspector
@export var pan_speed: float = 500.0      # pixels per second
@export var zoom_step: float = 0.1        # scroll wheel zoom step
@export var min_zoom: float = 0.5         # closer
@export var max_zoom: float = 3.0         # farther

var map_rect: Rect2 = Rect2()             # world-space rect covering the map
var _cam_tween: Tween
var _default_zoom: Vector2
var _controls_locked: bool = false
var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
var _shake_rng := RandomNumberGenerator.new()


func _ready() -> void:
	if terrain == null:
		push_error("Camera2D: 'terrain' is not assigned.")
		return
	_default_zoom = zoom
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
	# ✅ Shake should update even when controls are locked
	if _shake_time_left > 0.0:
		_shake_time_left -= delta
		offset = Vector2(
			_shake_rng.randf_range(-_shake_strength, _shake_strength),
			_shake_rng.randf_range(-_shake_strength, _shake_strength)
		)
	else:
		offset = Vector2.ZERO

	if _controls_locked:
		return

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

	
	# ✅ Shake applies regardless of lock state (uses offset so it won't fight soft focus)
	if _shake_time_left > 0.0:
		_shake_time_left -= delta
		offset = Vector2(
			_shake_rng.randf_range(-_shake_strength, _shake_strength),
			_shake_rng.randf_range(-_shake_strength, _shake_strength)
		)
	else:
		offset = Vector2.ZERO
	
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

#SOFT CAMERA PAN ON ENEMY TURN
func soft_focus_world_pos(world_pos: Vector2, zoom_in: float = 0.92, duration: float = 0.18) -> void:
	_controls_locked = true

	if _cam_tween != null and _cam_tween.is_running():
		_cam_tween.kill()

	_cam_tween = create_tween()
	_cam_tween.tween_property(self, "global_position", world_pos, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(self, "zoom", Vector2(zoom_in, zoom_in), duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

#ADJUST ENEMY TURN CAMERA SOFT FOCUS SYNC WITH PATCH IN MAIN
func soft_focus_unit(unit: Node, zoom_in: float = 2.2, duration: float = 0.18) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit is Node2D:
		soft_focus_world_pos((unit as Node2D).global_position, zoom_in, duration)

func restore_player_control(duration: float = 0.18) -> void:
	if _cam_tween != null and _cam_tween.is_running():
		_cam_tween.kill()

	_cam_tween = create_tween()
	_cam_tween.tween_property(self, "zoom", _default_zoom, duration)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_IN_OUT)

	# unlock after the tween completes
	_cam_tween.finished.connect(func(): _controls_locked = false)

#CAMERA SHAKE
func shake(strength: float = 8.0, duration: float = 0.12) -> void:
	_shake_strength = max(strength, 0.0)
	_shake_duration = max(duration, 0.0)
	_shake_time_left = _shake_duration
	if _shake_rng.seed == 0:
		_shake_rng.randomize()

	# ✅ immediate nudge so it doesn't “wait” for next process tick
	offset = Vector2(
		_shake_rng.randf_range(-_shake_strength, _shake_strength),
		_shake_rng.randf_range(-_shake_strength, _shake_strength)
	)

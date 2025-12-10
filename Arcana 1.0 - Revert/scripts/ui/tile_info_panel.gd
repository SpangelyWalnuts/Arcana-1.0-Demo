extends Control

@export var grid: Node          # Assign Grid node in inspector

@onready var terrain_label: Label     = $Panel/VBoxContainer/TerrainLabel
@onready var move_cost_label: Label   = $Panel/VBoxContainer/MoveCostLabel
@onready var defense_label: Label     = $Panel/VBoxContainer/DefenseLabel

@onready var unit_name_label: Label   = $Panel2/VBoxContainer/UnitNameLabel
@onready var unit_hp_label: Label     = $Panel2/VBoxContainer/UnitHPLabel
@onready var unit_stats_label: Label  = $Panel2/VBoxContainer/UnitStatsLabel
@onready var unit_portrait: TextureRect = $Panel2/UnitPortrait
@onready var status_icon_container: HBoxContainer = $Panel2/StatusIcons

var _last_tile: Vector2i = Vector2i(-999, -999)

var _home_position: Vector2
var _hidden_position: Vector2
var _current_tween: Tween = null


func _ready() -> void:
	# Remember where the panel sits in the editor (visible position)
	_home_position = position

	# If Panel size isn't initialized yet, fall back to a default width
	var panel_width: float = $Panel.size.x
	if panel_width <= 0.0:
		panel_width = 200.0

	_hidden_position = Vector2(_home_position.x - panel_width - 16.0, _home_position.y)

	position = _hidden_position
	visible = false


func show_panel() -> void:
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()

	visible = true
	position = _hidden_position

	_current_tween = create_tween()
	_current_tween.tween_property(
		self,
		"position",
		_home_position,
		0.2
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func hide_panel() -> void:
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()

	_current_tween = create_tween()
	_current_tween.tween_property(
		self,
		"position",
		_hidden_position,
		0.2
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_current_tween.finished.connect(func() -> void:
		visible = false
		_current_tween = null
	)


func _process(_delta: float) -> void:
	if grid == null:
		return

	var tile: Vector2i = grid.cursor_tile

	# Tile changed → ensure panel is visible & animate in once
	if tile != _last_tile:
		_last_tile = tile
		if not visible:
			show_panel()

	# --- Terrain info ---
	var info: Dictionary = grid.get_terrain_info(tile)
	var name: String = info.get("name", "Unknown")
	var move_cost: int = int(info.get("move_cost", 0))
	var defense: int = int(info.get("def", 0))

	terrain_label.text = "Terrain: %s" % name
	move_cost_label.text = "Move Cost: %d" % move_cost
	defense_label.text = "Defense: +%d" % defense

	# --- Unit info ---
	var unit = _get_unit_at_tile(tile)
	if unit != null:
		unit_name_label.text = "Unit: %s" % unit.name
		unit_hp_label.text = "HP: %d / %d" % [unit.hp, unit.max_hp]
		unit_stats_label.text = "ATK: %d   DEF: %d" % [unit.atk, unit.defense]

		# Portrait from unit_class (if set)
		if unit_portrait != null:
			var tex: Texture2D = null
			if unit.unit_class != null and unit.unit_class.portrait_texture != null:
				tex = unit.unit_class.portrait_texture
			unit_portrait.texture = tex

		_update_status_icons(unit)
	else:
		unit_name_label.text = "Unit: -"
		unit_hp_label.text = "HP: -"
		unit_stats_label.text = ""
		if unit_portrait != null:
			unit_portrait.texture = null

		_update_status_icons(null)


func _get_unit_at_tile(tile: Vector2i):
	# Look for a unit at this tile among both player and enemy units
	var units: Array = []
	units += get_tree().get_nodes_in_group("player_units")
	units += get_tree().get_nodes_in_group("enemy_units")

	for u in units:
		if u.grid_position == tile and u.hp > 0:
			return u

	return null


func _update_status_icons(unit) -> void:
	if status_icon_container == null:
		return

	# Clear existing icons
	for child in status_icon_container.get_children():
		child.queue_free()

	if unit == null:
		status_icon_container.visible = false
		return

	# Get flags from StatusManager (autoload)
	var flags: Dictionary = StatusManager.get_flags_for_unit(unit)
	if flags.is_empty():
		status_icon_container.visible = false
		return

	for flag_name in flags.keys():
		if not bool(flags[flag_name]):
			continue

		var tex: Texture2D = StatusManager.get_icon_for_flag(flag_name)
		if tex == null:
			continue

		var icon_rect := TextureRect.new()
		icon_rect.texture = tex
		icon_rect.custom_min_size = Vector2(16, 16)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		status_icon_container.add_child(icon_rect)

	status_icon_container.visible = status_icon_container.get_child_count() > 0

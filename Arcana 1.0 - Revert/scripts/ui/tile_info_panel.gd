extends Control

@export var grid: Node          # Assign Grid node in inspector

@onready var terrain_label: Label      = $Panel/VBoxContainer/TerrainLabel
@onready var move_cost_label: Label    = $Panel/VBoxContainer/MoveCostLabel
@onready var defense_label: Label      = $Panel/VBoxContainer/DefenseLabel

@onready var unit_name_label: Label    = $Panel2/VBoxContainer/UnitNameLabel
@onready var unit_hp_label: Label      = $Panel2/VBoxContainer/UnitHPLabel
@onready var unit_stats_label: Label   = $Panel2/VBoxContainer/UnitStatsLabel
@onready var unit_portrait: TextureRect = $Panel2/UnitPortrait
@onready var unit_status_icons: HBoxContainer = $Panel2/StatusIcons  # 🔹 NEW
@onready var unit_arcana_icons: HBoxContainer = $Panel2/ArcanaIcons

var _last_tile: Vector2i = Vector2i(-999, -999)

var _last_status_unit_id: int = 0
var _last_status_signature: String = ""
var _last_arcana_unit_id: int = 0
var _last_arcana_signature: String = ""

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

		_update_status_icons(unit)   # 🔹 icons when there IS a unit
		_update_arcana_icons(unit)

	else:
		unit_name_label.text = "Unit: -"
		unit_hp_label.text = "HP: -"
		unit_stats_label.text = ""
		if unit_portrait != null:
			unit_portrait.texture = null

		_update_status_icons(null)   # 🔹 clear icons when no unit
		_update_arcana_icons(unit)


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
	if unit_status_icons == null:
		return

	# Clear if no unit
	if unit == null:
		_last_status_unit_id = 0
		_last_status_signature = ""
		for child in unit_status_icons.get_children():
			child.queue_free()
		return

	# Build a small signature so we only refresh when statuses change
	var unit_id: int = unit.get_instance_id()

	var sig_parts: Array[String] = []
	if StatusManager != null and StatusManager.has_method("get_statuses_for_unit"):
		var statuses: Array = StatusManager.get_statuses_for_unit(unit)
		for st in statuses:
			if typeof(st) != TYPE_DICTIONARY:
				continue
			var turns: int = int(st.get("remaining_turns", -1))

			# We include the key flags that drive icons
			if bool(st.get("prevent_move", false)):
				sig_parts.append("prevent_move:%d" % turns)
			if bool(st.get("prevent_arcana", false)):
				sig_parts.append("prevent_arcana:%d" % turns)
			if int(st.get("atk_mod", 0)) != 0:
				sig_parts.append("atk_mod:%d" % turns)
			if int(st.get("def_mod", 0)) != 0:
				sig_parts.append("def_mod:%d" % turns)

	sig_parts.sort()
	var signature: String = "|".join(sig_parts)

	# If same unit + same signature, do nothing
	if unit_id == _last_status_unit_id and signature == _last_status_signature:
		return

	_last_status_unit_id = unit_id
	_last_status_signature = signature

	# Rebuild icons
	for child in unit_status_icons.get_children():
		child.queue_free()

	if StatusManager != null and StatusManager.has_method("refresh_icons_for_unit"):
		StatusManager.refresh_icons_for_unit(unit, unit_status_icons)

func _update_arcana_icons(unit) -> void:
	if unit_arcana_icons == null:
		return

	# Clear if no unit
	if unit == null:
		_last_arcana_unit_id = 0
		_last_arcana_signature = ""
		for child in unit_arcana_icons.get_children():
			child.queue_free()
		unit_arcana_icons.visible = false
		return

	# Only use equipped arcana (no fallback)
	var arcana: Array = []
	if unit.has_method("get"):
		var ud = unit.get("unit_data")
		if ud != null and ud.has_method("get"):
			var eq = ud.get("equipped_arcana")
			if eq is Array:
				arcana = eq

	print("[HOVER] unit=", unit.name, " team=", unit.get("team"), " equipped_arcana=", arcana.size())

	# If none equipped, show nothing (prevents misleading info)
	if arcana.is_empty():
		_last_arcana_unit_id = unit.get_instance_id()
		_last_arcana_signature = ""
		for child in unit_arcana_icons.get_children():
			child.queue_free()
		unit_arcana_icons.visible = false
		return

	unit_arcana_icons.visible = true

	var unit_id: int = unit.get_instance_id()

	# Build signature so we only rebuild when it changes
	var sig_parts: Array[String] = []
	for s in arcana:
		if s == null:
			continue
		if s.has_method("get"):
			sig_parts.append(str(s.get("name")))
	sig_parts.sort()
	var signature: String = "|".join(sig_parts)

	if unit_id == _last_arcana_unit_id and signature == _last_arcana_signature:
		return

	_last_arcana_unit_id = unit_id
	_last_arcana_signature = signature

	# Rebuild icons
	for child in unit_arcana_icons.get_children():
		child.queue_free()

	for s in arcana:
		if s == null:
			continue

		var tex: Texture2D = null
		if s.has_method("get"):
			tex = s.get("icon_texture")

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(28, 28)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = tex
		icon.tooltip_text = str(s.get("name"))

		unit_arcana_icons.add_child(icon)

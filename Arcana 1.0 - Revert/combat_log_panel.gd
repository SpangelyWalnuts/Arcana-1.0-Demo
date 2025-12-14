extends Control

@onready var log_text: RichTextLabel = $PanelContainer2/VBoxContainer/LogText
@onready var filter_option: OptionButton = $PanelContainer2/VBoxContainer/HBoxContainer/FilterOption
@onready var clear_button: Button = $PanelContainer2/VBoxContainer/HBoxContainer/ClearButton

@export var auto_scroll: bool = true
var _current_filter: String = "all"

func _ready() -> void:
	if CombatLog != null:
		if not CombatLog.entry_added.is_connected(_on_entry_added):
			CombatLog.entry_added.connect(_on_entry_added)
	log_text.clear()
	log_text.append_text("DEBUG: panel can write to LogText\n")

	_setup_controls()
	_refresh_full()

func _setup_controls() -> void:
	if clear_button != null:
		if not clear_button.pressed.is_connected(_on_clear_pressed):
			clear_button.pressed.connect(_on_clear_pressed)

	if filter_option != null:
		filter_option.clear()
		filter_option.add_item("All", 0)
		filter_option.add_item("Attacks", 1)
		filter_option.add_item("Skills", 2)
		filter_option.add_item("Status", 3)
		filter_option.add_item("Movement", 4)
		filter_option.add_item("Other", 5)
		filter_option.selected = 0
		if not filter_option.item_selected.is_connected(_on_filter_selected):
			filter_option.item_selected.connect(_on_filter_selected)

func _on_clear_pressed() -> void:
	if CombatLog != null and CombatLog.has_method("clear"):
		CombatLog.clear()
	_refresh_full()

func _on_filter_selected(idx: int) -> void:
	match idx:
		0: _current_filter = "all"
		1: _current_filter = "attack"
		2: _current_filter = "skill"
		3: _current_filter = "status"
		4: _current_filter = "move"
		_: _current_filter = "other"
	_refresh_full()

func _refresh_full() -> void:
	if log_text == null:
		return
	log_text.clear()
	if CombatLog == null:
		return
	for e in CombatLog.get_entries():
		if _passes_filter(e):
			_append_entry(e)

func _on_entry_added(entry: Dictionary) -> void:
	if not visible:
		return
	if not _passes_filter(entry):
		return
	_append_entry(entry)

func _passes_filter(entry: Dictionary) -> bool:
	var data: Dictionary = entry.get("data", {}) as Dictionary
	var t: String = str(data.get("type", ""))

	# Always show turn separators, even when filtering
	if t == "turn":
		return true

	if _current_filter == "all":
		return true

	var is_attack: bool = (t == "attack" or t == "damage" or t == "ko")
	var is_skill: bool = (t.begins_with("cast") or t.begins_with("skill") or t == "heal" or t == "skill_resolve" or t == "cast_hit")
	var is_status: bool = (t.begins_with("status") or t == "status" or t == "status_apply" or t == "status_tick")
	var is_move: bool = (t == "move" or t == "movement")

	match _current_filter:
		"attack": return is_attack
		"skill": return is_skill
		"status": return is_status
		"move": return is_move
		"other": return not (is_attack or is_skill or is_status or is_move)

	return true

func _append_entry(entry: Dictionary) -> void:
	if log_text == null:
		return

	var turn_i: int = int(entry.get("turn", 0))
	var msg: String = str(entry.get("msg", ""))

	var data: Dictionary = entry.get("data", {}) as Dictionary
	var t: String = str(data.get("type", ""))

	# Color by type
	var color_tag: String = ""
	match t:
		"turn":
			color_tag = "yellow"
		"attack", "damage", "ko":
			color_tag = "red"
		"heal":
			color_tag = "green"
		"status", "status_apply", "status_tick":
			color_tag = "purple"
		"cast", "cast_hit", "skill_resolve", "cast_tile", "tile_modifier":
			color_tag = "cyan"
		"terrain", "terrain_ignored":
			color_tag = "orange"
		_:
			color_tag = "white"

	# Turn prefix in gray, message in type color
	log_text.append_text("[color=gray]T%d[/color] [color=%s]%s[/color]\n" % [turn_i, color_tag, msg])

	if auto_scroll:
		log_text.scroll_to_line(log_text.get_line_count())

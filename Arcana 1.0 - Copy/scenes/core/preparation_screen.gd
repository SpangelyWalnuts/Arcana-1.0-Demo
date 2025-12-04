extends Control

@onready var floor_label: Label          = $Panel/VBoxContainer/FloorLabel
@onready var hint_label: Label           = $Panel/VBoxContainer/HintLabel
@onready var roster_list: ItemList       = $Panel/VBoxContainer/HBoxContainer/RosterBox/RosterList
@onready var deploy_list: ItemList       = $Panel/VBoxContainer/HBoxContainer/DeployBox/DeployList
@onready var start_button: Button        = $Panel/VBoxContainer/HBoxContainer/HBoxContainer/StartBattleButton
@onready var title_button: Button        = $Panel/VBoxContainer/HBoxContainer/HBoxContainer/ReturnToTitleButton
@onready var class_name_label: Label = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ClassNameLabel
@onready var stats_label: Label      = $Panel/VBoxContainer/HBoxContainer/DetailsBox/StatsLabel
@onready var mana_label: Label       = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ManaLabel
@onready var range_label: Label      = $Panel/VBoxContainer/HBoxContainer/DetailsBox/RangeLabel
@onready var arcana_label: Label     = $Panel/VBoxContainer/HBoxContainer/DetailsBox/ArcanaLabel
@onready var level_label: Label      = $Panel/VBoxContainer/HBoxContainer/DetailsBox/LevelLabel

# Temporary: limit on how many units can be deployed this floor.
# Later we’ll hook this to map size / enemy count via some floor config.
@export var max_deploy_slots: int = 4

# Indices into RunManager.roster that are currently deployed
var _deployed_indices: Array[int] = []


func _ready() -> void:
	if not RunManager.run_active:
		RunManager.return_to_title()
		return

	floor_label.text = "Floor %d" % RunManager.current_floor
	hint_label.text = "Select up to %d units to deploy." % max_deploy_slots

	_populate_roster_lists()

	# Double-click to move units between lists
	roster_list.item_activated.connect(_on_roster_item_activated)
	deploy_list.item_activated.connect(_on_deploy_item_activated)

	# Single-click to show details
	roster_list.item_selected.connect(_on_roster_item_selected)
	deploy_list.item_selected.connect(_on_deploy_item_selected)

	start_button.pressed.connect(_on_start_battle_pressed)
	title_button.pressed.connect(_on_return_to_title_pressed)

	_clear_details_panel()

#HANDLERS
func _on_roster_item_selected(index: int) -> void:
	_show_unit_details_from_roster_index(index)


func _on_deploy_item_selected(index: int) -> void:
	# index here is the position in deploy_list, not roster index.
	if index < 0 or index >= _deployed_indices.size():
		return

	var roster_index := _deployed_indices[index]
	_show_unit_details_from_roster_index(roster_index)

func _show_unit_details_from_roster_index(roster_index: int) -> void:
	var roster = RunManager.roster
	if roster_index < 0 or roster_index >= roster.size():
		_clear_details_panel()
		return

	var data: UnitData = roster[roster_index]
	if data == null or data.unit_class == null:
		_clear_details_panel()
		return

	var cls: UnitClass = data.unit_class

	# Basic class name
	class_name_label.text = "Class: %s" % cls.display_name

	# Level / EXP
	level_label.text = "Level: %d   EXP: %d" % [data.level, data.exp]

	# Core stats
	stats_label.text = "HP: %d   ATK: %d   DEF: %d" % [
		cls.max_hp,
		cls.atk,
		cls.defense
	]

	# Mana info
	mana_label.text = "Mana: %d (Regen: %d/turn)" % [
		cls.max_mana,
		cls.mana_regen_per_turn
	]

	# Movement / range
	range_label.text = "Move: %d   Range: %d" % [
		cls.move_range,
		cls.attack_range
	]

	# Arcana / skills (just list names)
	if cls.skills.size() == 0:
		arcana_label.text = "Arcana: (none)"
	else:
		var names: Array[String] = []
		for s in cls.skills:
			if s != null:
				names.append(s.name)
		if names.is_empty():
			arcana_label.text = "Arcana: (none)"
		else:
			arcana_label.text = "Arcana: " + ", ".join(names)


#CLEAR DETAILS HELPER 
func _clear_details_panel() -> void:
	class_name_label.text = "Class: -"
	level_label.text      = "Level: -   EXP: -"
	stats_label.text      = "HP: -   ATK: -   DEF: -"
	mana_label.text       = "Mana: -"
	range_label.text      = "Move: -   Range: -"
	arcana_label.text     = "Arcana: -"


func _populate_roster_lists() -> void:
	roster_list.clear()
	deploy_list.clear()
	_deployed_indices.clear()

	var roster = RunManager.roster

	for i in range(roster.size()):
		var data: UnitData = roster[i]
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		var label_text := "%s (Lv %d)" % [cls.display_name, data.level]
		roster_list.add_item(label_text)



func _on_roster_item_activated(index: int) -> void:
	# Move from roster → deploy if we have room
	if _deployed_indices.size() >= max_deploy_slots:
		return

	if _deployed_indices.has(index):
		return

	_deployed_indices.append(index)
	_refresh_lists()


func _on_deploy_item_activated(index: int) -> void:
	# index here is position in deploy_list, not roster index
	if index < 0 or index >= _deployed_indices.size():
		return

	_deployed_indices.remove_at(index)
	_refresh_lists()


func _refresh_lists() -> void:
	roster_list.clear()
	deploy_list.clear()

	var roster = RunManager.roster

	# --- Rebuild roster list ---
	for i in range(roster.size()):
		var data: UnitData = roster[i]
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		var text := "%s (Lv %d)" % [cls.display_name, data.level]

		if _deployed_indices.has(i):
			text += " [DEPLOYED]"

		roster_list.add_item(text)

	# --- Rebuild deployed list in the same order as _deployed_indices ---
	for roster_index in _deployed_indices:
		if roster_index < 0 or roster_index >= roster.size():
			continue

		var data: UnitData = roster[roster_index]
		if data == null or data.unit_class == null:
			continue

		var cls: UnitClass = data.unit_class
		deploy_list.add_item("%s (Lv %d)" % [cls.display_name, data.level])


func _on_start_battle_pressed() -> void:
	if _deployed_indices.is_empty():
		return  # Maybe later show a warning: "Select at least one unit."

	var roster = RunManager.roster
	RunManager.deployed_units.clear()

	for idx in _deployed_indices:
		if idx < 0 or idx >= roster.size():
			continue

		var data: UnitData = roster[idx]
		if data != null:
			RunManager.deployed_units.append(data)

	# Go to battle scene
	RunManager.goto_battle_scene()


func _on_return_to_title_pressed() -> void:
	RunManager.return_to_title()

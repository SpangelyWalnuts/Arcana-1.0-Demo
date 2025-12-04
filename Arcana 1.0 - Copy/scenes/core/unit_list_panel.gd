extends Control

signal unit_entry_selected(unit)

@onready var header_label: Label        = $Panel/VBoxContainer/HeaderLabel
@onready var units_vbox: VBoxContainer  = $Panel/VBoxContainer/ScrollContainer/UnitsVBox


func _ready() -> void:
	visible = false


func show_for_team(team: String) -> void:
	# Clear old entries
	for child in units_vbox.get_children():
		child.queue_free()

	var group_name := ""
	if team == "player":
		group_name = "player_units"
	elif team == "enemy":
		group_name = "enemy_units"
	else:
		push_error("UnitListPanel: unknown team '%s'" % team)
		return

	var units := get_tree().get_nodes_in_group(group_name)
	var count := 0

	for unit in units:
		# Optional debug print so you can see what it finds:
		# print("UnitList candidate:", unit.name, " team:", unit.team)
		_add_unit_entry(unit)
		count += 1

	# print("UnitList: added", count, "entries for team", team)

	visible = true


func hide_panel() -> void:
	visible = false


func _add_unit_entry(unit: Node) -> void:
	var btn := Button.new()

	var text := "%s   HP: %d / %d" % [unit.name, unit.hp, unit.max_hp]
	if unit.has_acted:
		text += "  (Acted)"

	btn.text = text
	# If this errors, just comment it out:
	# btn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	btn.pressed.connect(_on_unit_button_pressed.bind(unit))
	units_vbox.add_child(btn)


func _on_unit_button_pressed(unit: Node) -> void:
	unit_entry_selected.emit(unit)
	hide_panel()

extends Control

signal skill_selected(skill)

@onready var vbox: VBoxContainer = $Panel/VBoxContainer

var current_skills: Array = []
var current_unit = null


func _ready() -> void:
	visible = false


func show_for_unit(unit) -> void:
	current_unit = unit
	current_skills.clear()

	# Remove old buttons
	for child in vbox.get_children():
		child.queue_free()

	if unit.skills.is_empty():
		visible = false
		return

	for i in range(unit.skills.size()):
		var s = unit.skills[i]
		if s == null:
			continue

		current_skills.append(s)

		var btn := Button.new()
		btn.text = "%s (Cost: %d)" % [s.name, s.mana_cost]
		btn.disabled = unit.mana < s.mana_cost
		# Pass the index 'i' to the handler
		btn.pressed.connect(_on_skill_button_pressed.bind(i))
		vbox.add_child(btn)

	visible = true


func hide_menu() -> void:
	visible = false
	current_unit = null
	current_skills.clear()


# ✅ Take an int index, not a Skill directly
func _on_skill_button_pressed(index: int) -> void:
	if index < 0 or index >= current_skills.size():
		return

	var skill = current_skills[index]
	if skill == null:
		return

	# Emit the actual Skill resource to Main.gd
	skill_selected.emit(skill)

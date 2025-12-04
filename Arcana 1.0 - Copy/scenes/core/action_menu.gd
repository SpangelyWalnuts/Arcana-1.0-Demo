extends Control

signal action_selected(action_name: String)

@onready var move_button: Button   = $Panel/VBoxContainer/MoveButton
@onready var attack_button: Button = $Panel/VBoxContainer/AttackButton
@onready var skill_button: Button  = $Panel/VBoxContainer/SkillButton
@onready var wait_button: Button   = $Panel/VBoxContainer/WaitButton

func _ready() -> void:
	visible = false
	move_button.pressed.connect(_on_move_pressed)
	attack_button.pressed.connect(_on_attack_pressed)
	skill_button.pressed.connect(_on_skill_pressed)
	wait_button.pressed.connect(_on_wait_pressed)


func show_for_unit(unit) -> void:
	visible = true

	if unit.has_acted:
		move_button.disabled = true
		attack_button.disabled = true
		skill_button.disabled = true
		wait_button.disabled = true
	else:
		move_button.disabled = false
		attack_button.disabled = false
		skill_button.disabled = unit.skills.is_empty()
		wait_button.disabled = false


func hide_menu() -> void:
	visible = false


func _on_move_pressed() -> void:
	print("[ActionMenu] Move pressed")
	action_selected.emit("move")
	hide_menu()


func _on_attack_pressed() -> void:
	print("[ActionMenu] Attack pressed")
	action_selected.emit("attack")
	hide_menu()


func _on_skill_pressed() -> void:
	print("[ActionMenu] Skill pressed")
	action_selected.emit("skill")
	hide_menu()


func _on_wait_pressed() -> void:
	print("[ActionMenu] Wait pressed")
	action_selected.emit("wait")
	hide_menu()

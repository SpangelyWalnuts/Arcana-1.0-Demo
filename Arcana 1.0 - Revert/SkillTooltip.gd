extends PanelContainer
class_name SkillTooltip

@onready var icon: TextureRect = $VBoxContainer/HBoxContainer/Icon
@onready var name_label: Label = $VBoxContainer/HBoxContainer/VBoxContainer/NameLabel
@onready var meta_label: Label = $VBoxContainer/HBoxContainer/VBoxContainer/MetaLabel
@onready var desc_label: Label = $VBoxContainer/DescLabel

func show_skill(skill: Skill, at_screen_pos: Vector2) -> void:
	if skill == null:
		hide()
		return

	icon.texture = skill.icon_texture
	name_label.text = skill.name

	# Simple readable meta line (adjust as you like)
	meta_label.text = "Mana %d  Range %d  AoE %d" % [skill.mana_cost, skill.cast_range, skill.aoe_radius]
	desc_label.text = skill.description

	# Position near mouse, with a small offset
	global_position = at_screen_pos + Vector2(16, 16)
	visible = true

	# Clamp inside viewport
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var r := get_global_rect()
	global_position.x = clamp(global_position.x, 0.0, vp.x - r.size.x)
	global_position.y = clamp(global_position.y, 0.0, vp.y - r.size.y)

func hide_tooltip() -> void:
	visible = false

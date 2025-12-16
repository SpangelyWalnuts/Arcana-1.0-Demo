extends Button
class_name DraftCard

@onready var name_label: Label = $VBoxContainer/NameLabel
@onready var skills_row: FlowContainer = $SkillsRow
@onready var anim: AnimatedSprite2D = $HBoxContainer/UnitPreview/SubViewport/Pivot/Anim
@onready var static_sprite: Sprite2D = get_node_or_null("HBoxContainer/UnitPreview/SubViewport/Pivot/Static")
@onready var viewport: SubViewport = $HBoxContainer/UnitPreview/SubViewport
@onready var pivot: Node2D = $HBoxContainer/UnitPreview/SubViewport/Pivot
@onready var stats_label: Label = $VBoxContainer/StatsLabel
var _tooltip: SkillTooltip

func _ready() -> void:
	_center_preview()

func _center_preview() -> void:
	pivot.position = Vector2(viewport.size) * 0.5

func set_data(unit_class: UnitClass) -> void:
	name_label.text = unit_class.display_name
	stats_label.text = "HP %d  MANA %d\nATK %d  DEF %d  MOV %d" % [
	unit_class.max_hp,
	unit_class.max_mana,
	unit_class.atk,
	unit_class.defense,
	unit_class.move_range
]
	# Unit preview (prefer idle anim)
	if unit_class.idle_frames != null:
		anim.sprite_frames = unit_class.idle_frames
		anim.animation = unit_class.idle_anim_name
		anim.visible = true
		anim.play()
		if static_sprite != null:
			static_sprite.visible = false
	elif unit_class.sprite_texture != null:
		if static_sprite != null:
			static_sprite.texture = unit_class.sprite_texture
			static_sprite.visible = true
		anim.visible = false
	else:
		anim.visible = false
		if static_sprite != null:
			static_sprite.visible = false

	# Skill icons
	for c in skills_row.get_children():
		c.queue_free()

	for s in unit_class.skills:
		if s == null:
			continue

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = s.icon_texture
		# Hover -> show panel tooltip
		icon.mouse_entered.connect(func():
			var tip := _find_tooltip()
			if tip != null:
				tip.show_skill(s, get_viewport().get_mouse_position())
)
# Exit -> hide panel tooltip
		icon.mouse_exited.connect(func():
			var tip := _find_tooltip()
			if tip != null:
				tip.hide_tooltip()
)

		skills_row.add_child(icon)

#TOOLTIP HELPER
func _find_tooltip() -> SkillTooltip:
	if _tooltip != null and is_instance_valid(_tooltip):
		return _tooltip
	_tooltip = get_tree().root.get_node_or_null("DraftScreen/SkillTooltip") as SkillTooltip
	return _tooltip

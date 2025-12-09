extends Control
class_name LevelUpPanel

signal finished

@onready var title_label: Label      = $Panel/MarginContainer/VBoxContainer/TitleLabel
@onready var unit_name_label: Label  = $Panel/MarginContainer/VBoxContainer/UnitNameLabel
@onready var stats_vbox: VBoxContainer = $Panel/MarginContainer/VBoxContainer/StatsVBox
@onready var hp_label: Label         = $Panel/MarginContainer/VBoxContainer/StatsVBox/HPLabel
@onready var atk_label: Label        = $Panel/MarginContainer/VBoxContainer/StatsVBox/ATKLabel
@onready var def_label: Label        = $Panel/MarginContainer/VBoxContainer/StatsVBox/DEFLabel
@onready var move_label: Label       = $Panel/MarginContainer/VBoxContainer/StatsVBox/MoveLabel
@onready var mana_label: Label       = $Panel/MarginContainer/VBoxContainer/StatsVBox/ManaLabel
@onready var unlock_label: Label     = $Panel/MarginContainer/VBoxContainer/UnlockLabel
@onready var next_button: Button     = $Panel/MarginContainer/VBoxContainer/ButtonRow/NextButton
@onready var skip_button: Button     = $Panel/MarginContainer/VBoxContainer/ButtonRow/SkipButton

var _events: Array = []
var _index: int = 0

func _ready() -> void:
	visible = false
	title_label.text = "Level Up!"
	unlock_label.text = ""
	next_button.text = "Next"
	skip_button.text = "Skip"

	next_button.pressed.connect(_on_next_pressed)
	skip_button.pressed.connect(_on_skip_pressed)


func show_for_report(events: Array) -> void:
	_events = events.duplicate()
	_index = 0

	if _events.is_empty():
		visible = false
		emit_signal("finished")
		return

	visible = true
	_show_current_event()
	_animate_in()


func _show_current_event() -> void:
	if _index < 0 or _index >= _events.size():
		_close_panel()
		return

	var evt: Dictionary = _events[_index]

	var name: String      = evt.get("name", "Unit")
	var new_level: int    = int(evt.get("new_level", 1))
	var hp_gain: int      = int(evt.get("hp_gain", 0))
	var atk_gain: int     = int(evt.get("atk_gain", 0))
	var def_gain: int     = int(evt.get("def_gain", 0))
	var move_gain: int    = int(evt.get("move_gain", 0))
	var mana_gain: int    = int(evt.get("mana_gain", 0))

	# Old level is always new_level - 1 here
	var old_level: int = new_level - 1
	if old_level < 1:
		old_level = 1

	unit_name_label.text = "%s   Lv %d → Lv %d" % [name, old_level, new_level]

	hp_label.text   = "HP:   +%d" % hp_gain
	atk_label.text  = "ATK:  +%d" % atk_gain
	def_label.text  = "DEF:  +%d" % def_gain
	move_label.text = "MOVE: +%d" % move_gain
	mana_label.text = "MANA: +%d" % mana_gain

	# For now, no unlocks:
	unlock_label.text = ""


func _on_next_pressed() -> void:
	_index += 1
	if _index >= _events.size():
		_close_panel()
	else:
		_show_current_event()
		_animate_in()


func _on_skip_pressed() -> void:
	_close_panel()


func _close_panel() -> void:
	visible = false
	emit_signal("finished")


func _animate_in() -> void:
	# Small scale pop-in animation
	scale = Vector2(0.9, 0.9)
	modulate.a = 0.0

	var t: Tween = create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.12) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

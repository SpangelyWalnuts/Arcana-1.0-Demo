extends Control

@onready var title_label: Label    = $MarginContainer/VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/SubtitleLabel
@onready var hint_label: Label     = $MarginContainer/VBoxContainer/HintLabel

@onready var card0: Button = $MarginContainer/VBoxContainer/CardsRow/Card0
@onready var card1: Button = $MarginContainer/VBoxContainer/CardsRow/Card1
@onready var card2: Button = $MarginContainer/VBoxContainer/CardsRow/Card2
@onready var card3: Button = $MarginContainer/VBoxContainer/CardsRow/Card3

@onready var continue_button: Button = $MarginContainer/VBoxContainer/ContinueButton

var _cards: Array[Button] = []


func _ready() -> void:
	_cards = [card0, card1, card2, card3]

	for i in range(_cards.size()):
		var btn := _cards[i]
		if btn == null:
			continue

		# Avoid double-connecting if the scene reloads
		if btn.pressed.is_connected(_on_card_pressed.bind(i)):
			continue
		btn.pressed.connect(_on_card_pressed.bind(i))

	if continue_button != null and not continue_button.pressed.is_connected(_on_continue_pressed):
		continue_button.pressed.connect(_on_continue_pressed)

	_refresh_cards()



func _refresh_cards() -> void:
	var opts: Array = []
	if RunManager != null:
		opts = RunManager.current_draft_options

	for i in range(_cards.size()):
		var btn: Button = _cards[i]
		if btn == null:
			continue

		if i >= opts.size():
			btn.visible = false
			continue

		btn.visible = true
		var cls: UnitClass = opts[i]

		# If this is a DraftCard instance, populate visuals
		if btn is DraftCard:
			(btn as DraftCard).set_data(cls)
		else:
			# Fallback: plain text button
			var line1 := cls.display_name
			var line2 := "HP %d  ATK %d  DEF %d  MOV %d" % [
				cls.max_hp,
				cls.atk,
				cls.defense,
				cls.move_range
			]
			btn.text = "%s\n%s" % [line1, line2]
			btn.disabled = false




func _on_card_pressed(idx: int) -> void:
	if RunManager != null and RunManager.has_method("choose_draft_unit"):
		RunManager.choose_draft_unit(idx)


func _on_continue_pressed() -> void:
	# Optional: if you ever want a "Skip" / "Auto-pick" behavior.
	# For now, we can just auto-pick the first option if it exists.
	if RunManager.current_draft_options.size() > 0:
		RunManager.choose_draft_unit(0)

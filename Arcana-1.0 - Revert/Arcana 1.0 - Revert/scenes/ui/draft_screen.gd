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

	# Set static texts
	title_label.text = "Choose Your Unit"
	hint_label.text  = "Pick 1 of 4. You will build a party of %d units." % RunManager.max_draft_picks

	# Connect card signals
	card0.pressed.connect(_on_card_pressed.bind(0))
	card1.pressed.connect(_on_card_pressed.bind(1))
	card2.pressed.connect(_on_card_pressed.bind(2))
	card3.pressed.connect(_on_card_pressed.bind(3))

	continue_button.pressed.connect(_on_continue_pressed)

	_refresh_cards()


func _refresh_cards() -> void:
	var round_num: int = RunManager.draft_round
	if round_num <= 0:
		round_num = 1

	subtitle_label.text = "Draft pick %d of %d" % [round_num, RunManager.max_draft_picks]

	var options: Array = RunManager.current_draft_options

	for i in range(_cards.size()):
		var btn: Button = _cards[i]

		if i >= options.size():
			btn.text = "No option"
			btn.disabled = true
			continue

		var cls: UnitClass = options[i]
		if cls == null:
			btn.text = "???"
			btn.disabled = true
			continue

		var line1 := cls.display_name
		var line2 := "HP %d  ATK %d  DEF %d  MOV %d" % [
			cls.max_hp,
			cls.atk,
			cls.defense,
			cls.move_range
		]

		btn.disabled = false
		btn.text = "%s\n%s" % [line1, line2]


func _on_card_pressed(index: int) -> void:
	if index < 0 or index >= RunManager.current_draft_options.size():
		return

	RunManager.choose_draft_unit(index)
	# After calling choose_draft_unit, RunManager will either:
	#  - start the next draft round (and reload DraftScreen), or
	#  - go to the Preparation screen once draft is finished.


func _on_continue_pressed() -> void:
	# Optional: if you ever want a "Skip" / "Auto-pick" behavior.
	# For now, we can just auto-pick the first option if it exists.
	if RunManager.current_draft_options.size() > 0:
		RunManager.choose_draft_unit(0)

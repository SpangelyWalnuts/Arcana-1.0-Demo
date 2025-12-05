extends Control

@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel
@onready var info_label: Label  = $MarginContainer/VBoxContainer/InfoLabel
@onready var cards_container: HBoxContainer = $MarginContainer/VBoxContainer/CardsContainer

@onready var card1: Button = $MarginContainer/VBoxContainer/CardsContainer/Card1
@onready var card2: Button = $MarginContainer/VBoxContainer/CardsContainer/Card2
@onready var card3: Button = $MarginContainer/VBoxContainer/CardsContainer/Card3
@onready var card4: Button = $MarginContainer/VBoxContainer/CardsContainer/Card4

@onready var skip_button: Button = $MarginContainer/VBoxContainer/SkipButton
@onready var hint_label: Label   = $MarginContainer/VBoxContainer/HintLabel

var _options: Array = []


func _ready() -> void:
	# Ensure we have rewards; if not, generate some.
	if RunManager.pending_rewards.is_empty():
		RunManager.generate_rewards_for_floor(RunManager.current_floor)

	_options = RunManager.pending_rewards

	title_label.text = "Choose Your Reward"
	info_label.text = "Floor %d Cleared" % RunManager.current_floor
	hint_label.text = "Click a card to take a reward, or skip to take nothing."

	# Set up card texts
	_set_card(card1, 0)
	_set_card(card2, 1)
	_set_card(card3, 2)
	_set_card(card4, 3)

	card1.pressed.connect(_on_card_pressed.bind(0))
	card2.pressed.connect(_on_card_pressed.bind(1))
	card3.pressed.connect(_on_card_pressed.bind(2))
	card4.pressed.connect(_on_card_pressed.bind(3))

	skip_button.pressed.connect(_on_skip_pressed)


func _set_card(btn: Button, index: int) -> void:
	if index >= _options.size():
		btn.text = "No reward"
		btn.disabled = true
		return

	var opt: Dictionary = _options[index]
	var reward_type = int(opt.get("type", RunManager.RewardType.GOLD))
	var desc: String = String(opt.get("desc", ""))

	var header: String = ""

	match reward_type:
		RunManager.RewardType.GOLD:
			header = "Gold"
		RunManager.RewardType.ITEM:
			header = "Item"
		RunManager.RewardType.EQUIPMENT:
			header = "Equipment"
		RunManager.RewardType.EXP_BOOST:
			header = "EXP Boost"
		RunManager.RewardType.ARTIFACT:
			header = "Artifact"
		_:
			header = "Reward"

	btn.disabled = false
	btn.text = "%s\n\n%s" % [header, desc]


func _on_card_pressed(index: int) -> void:
	if index < 0 or index >= _options.size():
		return

	var opt: Dictionary = _options[index]

	# Apply the chosen reward
	RunManager.apply_reward(opt)

	# Move to next floor and prep screen
	RunManager.advance_floor()
	_go_to_preparation_screen()


func _on_skip_pressed() -> void:
	# Skip: no reward, just advance floor
	RunManager.pending_rewards.clear()
	RunManager.advance_floor()
	_go_to_preparation_screen()


func _go_to_preparation_screen() -> void:
	var err = get_tree().change_scene_to_file("res://scenes/ui/PreparationScreen.tscn")
	if err != OK:
		push_error("RewardsScreen: Failed to change to PreparationScreen, check path.")

extends Control

@onready var title_label: Label    = $MarginContainer/VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $MarginContainer/VBoxContainer/SubtitleLabel
@onready var hint_label: Label     = $MarginContainer/VBoxContainer/HintLabel

@onready var card0: Button = $MarginContainer/VBoxContainer/CardsRow/Card0
@onready var card1: Button = $MarginContainer/VBoxContainer/CardsRow/Card1
@onready var card2: Button = $MarginContainer/VBoxContainer/CardsRow/Card2
@onready var card3: Button = $MarginContainer/VBoxContainer/CardsRow/Card3

@onready var continue_button: Button = $MarginContainer/VBoxContainer/ContinueButton

var _is_picking: bool = false

@export var pick_anim_duration: float = 0.28
@export var pick_selected_scale: float = 1.10
@export var pick_others_fade_alpha: float = 0.45

@export var pick_selected_slide_y: float = -14.0
@export var pick_others_slide_y: float = 10.0

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
	# Reset visuals each refresh (prevents stuck scaling/dimming)
	for b in _cards:
		if b != null:
			b.scale = Vector2.ONE
			b.modulate = Color(1, 1, 1, 1)
			b.disabled = false
			b.z_index = 0
			b.position = Vector2.ZERO


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
	if _is_picking:
		return
	if RunManager == null or not RunManager.has_method("choose_draft_unit"):
		return

	_is_picking = true

	# Disable all cards during the confirm anim
	for b in _cards:
		if b != null:
			b.disabled = true

	var selected: Button = _cards[idx]

	# Animate selection
	var tween := create_tween()
	tween.set_parallel(true)

# Other cards fade, shrink, and slide down slightly
	for i in range(_cards.size()):
		var b: Button = _cards[i]
		if b == null:
			continue
		if i == idx:
			continue

		tween.tween_property(b, "modulate:a", pick_others_fade_alpha, pick_anim_duration)

		tween.tween_property(
			b,
			"scale",
			Vector2.ONE * 0.97,
			pick_anim_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		tween.tween_property(
			b,
			"position:y",
			b.position.y + pick_others_slide_y,
			pick_anim_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


	# Selected card pop
	if selected != null:
		selected.z_index = 100

# Scale up
		tween.tween_property(
			selected,
			"scale",
			Vector2.ONE * pick_selected_scale,
			pick_anim_duration
		).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Slide upward slightly
		tween.tween_property(
			selected,
			"position:y",
			selected.position.y + pick_selected_slide_y,
			pick_anim_duration
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


		# Flash
		var flash := create_tween()
		flash.tween_property(selected, "modulate", Color(1.25, 1.25, 1.25, 1.0), 0.08)
		flash.tween_property(selected, "modulate", Color(1, 1, 1, 1), 0.10)

	await tween.finished

	# Do the actual pick AFTER the animation
	RunManager.choose_draft_unit(idx)

	# If DraftScreen stays visible for the next pick, refresh and reset visuals
	_refresh_cards()

	_is_picking = false



func _on_continue_pressed() -> void:
	# Optional: if you ever want a "Skip" / "Auto-pick" behavior.
	# For now, we can just auto-pick the first option if it exists.
	if RunManager.current_draft_options.size() > 0:
		RunManager.choose_draft_unit(0)

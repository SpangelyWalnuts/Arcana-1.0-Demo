extends Node2D

@onready var label: Label = $Label

func show_exp(exp_amount: int, leveled_up: bool) -> void:
	var text := "+%d EXP" % exp_amount
	if leveled_up:
		text += "  LV UP!"

	label.text = text

	# Start slightly above origin
	position += Vector2(0, -8)

	# Animate: float up & fade out then free
	var t := create_tween()
	t.tween_property(self, "position:y", position.y - 24.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.finished.connect(queue_free)

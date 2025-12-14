extends Control

@onready var panel: Panel = $Panel
@onready var label: Label = $Panel/Label

var _current_tween: Tween = null


func _ready() -> void:
	visible = false
	modulate.a = 0.0


func play_phase(phase_text: String, color: Color) -> void:
	# Set text and color
	label.text = phase_text
	panel.self_modulate = color

	# Kill any existing animation
	if _current_tween != null and _current_tween.is_running():
		_current_tween.kill()

	visible = true
	modulate.a = 0.0

	# Fade in → hold → fade out
	var t: Tween = create_tween()
	_current_tween = t

	t.tween_property(self, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_interval(0.6)
	t.tween_property(self, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.finished.connect(_on_tween_finished)


func _on_tween_finished() -> void:
	visible = false
	_current_tween = null

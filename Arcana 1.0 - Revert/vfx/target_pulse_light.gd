extends Node2D

@onready var light: PointLight2D = $Light2D

@export var peak_energy: float = 1.2
@export var up_time: float = 0.06
@export var down_time: float = 0.18

func _ready() -> void:
	if light == null:
		queue_free()
		return

	light.energy = 0.0
	var t := create_tween()
	t.tween_property(light, "energy", peak_energy, up_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(light, "energy", 0.0, down_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	t.tween_callback(queue_free)

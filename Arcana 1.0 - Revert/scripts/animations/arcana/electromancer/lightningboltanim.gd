extends Node2D

@onready var anim: AnimatedSprite2D = $Anim

@onready var light: PointLight2D = $ImpactLight

func _ready() -> void:
	anim.play("lightningbolt")

	if light:
		light.energy = 0.0
		var t := create_tween()
		t.tween_property(light, "energy", 5.0, 0.03)
		t.tween_property(light, "energy", 0.0, 0.18)

	anim.animation_finished.connect(queue_free, CONNECT_ONE_SHOT)

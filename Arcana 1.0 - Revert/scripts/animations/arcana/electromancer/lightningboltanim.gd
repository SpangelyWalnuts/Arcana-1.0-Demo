extends Node2D

@onready var anim: AnimatedSprite2D = $Anim

func _ready() -> void:
	anim.play("lightningbolt")
	anim.animation_finished.connect(func():
		queue_free()
	)

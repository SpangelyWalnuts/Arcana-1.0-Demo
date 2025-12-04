extends Control

@export_file("*.tscn") var main_scene_path: String = "res://scenes/core/Main.tscn"

@onready var start_button: Button = $StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)



func _on_start_pressed() -> void:
	RunManager.start_new_run()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

extends Node

var run_active: bool = false
var current_floor: int = 0
var gold: int = 0

# All units the player owns this run (UnitClass resources)
var roster: Array[UnitClass] = []

# Units chosen to be deployed in the next battle
var deployed_units: Array[UnitClass] = []

var artifacts: Array[Resource] = []

# 👉 Hardcode starting unit classes by resource path for now.
#    Replace these with your actual UnitClass .tres paths.
const STARTING_UNIT_CLASS_PATHS := [
	"res://data/unit_classes/Geomancer.tres",
	"res://data/unit_classes/Druid.tres",
	"res://data/unit_classes/Pyromancer.tres",
	"res://data/unit_classes/Cleric.tres",
]

const PREP_SCENE_PATH  := "res://scenes/core/preparation_screen.tscn"
const BATTLE_SCENE_PATH := "res://scenes/core/Main.tscn"
const TITLE_SCENE_PATH  := "res://scenes/core/TitleScreen.tscn"


func start_new_run() -> void:
	run_active = true
	current_floor = 1
	gold = 0
	artifacts.clear()
	_setup_starting_roster()
	_goto_preparation()


func _setup_starting_roster() -> void:
	roster.clear()
	deployed_units.clear()

	for path in STARTING_UNIT_CLASS_PATHS:
		var res := load(path)
		if res is UnitClass:
			roster.append(res)
			print("RunManager: added UnitClass from", path)
		else:
			push_warning("RunManager: Could not load UnitClass at %s" % path)

	if roster.is_empty():
		push_warning("RunManager: STARTING_UNIT_CLASS_PATHS is empty or invalid.")


func _goto_preparation() -> void:
	var packed := load(PREP_SCENE_PATH)
	if packed == null:
		push_error("RunManager: Could not load Preparation scene at %s" % PREP_SCENE_PATH)
		return
	get_tree().change_scene_to_packed(packed)


func goto_battle_scene() -> void:
	var packed := load(BATTLE_SCENE_PATH)
	if packed == null:
		push_error("RunManager: Could not load battle scene at %s" % BATTLE_SCENE_PATH)
		return
	get_tree().change_scene_to_packed(packed)


func return_to_title() -> void:
	run_active = false
	current_floor = 0
	gold = 0
	roster.clear()
	deployed_units.clear()
	artifacts.clear()

	var packed := load(TITLE_SCENE_PATH)
	if packed == null:
		push_error("RunManager: Could not load title scene at %s" % TITLE_SCENE_PATH)
		return
	get_tree().change_scene_to_packed(packed)


func advance_floor() -> bool:
	current_floor += 1
	print("Advancing to floor", current_floor)
	return true

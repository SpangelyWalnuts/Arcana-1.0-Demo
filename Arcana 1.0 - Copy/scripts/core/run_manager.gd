extends Node

var run_active: bool = false
var current_floor: int = 0
var gold: int = 0

# All units the player owns this run (UnitClass resources)
var roster: Array[UnitData] = []
var deployed_units: Array[UnitData] = []


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
			var data := UnitData.new()
			data.unit_class = res
			data.level = 1
			data.exp = 0
			roster.append(data)
			print("RunManager: added", res.display_name, "at level", data.level)
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

# XP AND LEVEL UP HELPERS
func _grant_post_battle_xp(summary: Dictionary, victory: bool) -> void:
	# Basic XP per battle, scaled by floor
	var floor: int = int(summary.get("floor", current_floor))
	var enemies_defeated: int = int(summary.get("enemies_defeated", 0))

	var base_xp: int = 25 + 5 * max(floor - 1, 0)
	var kill_bonus: int = enemies_defeated * 3

	var total_xp: int = base_xp + kill_bonus

	# Deployed units get full, undeployed get half
	var deployed: Array[UnitData] = deployed_units
	var roster_copy: Array[UnitData] = roster

	var deployed_set: Array[UnitData] = deployed.duplicate()

	for data in roster_copy:
		if data == null:
			continue

		var gain: int
		if deployed_set.has(data):
			gain = total_xp
		else:
			gain = int(round(float(total_xp) * 0.5))

		_add_xp_to_unit(data, gain)


func _add_xp_to_unit(data: UnitData, amount: int) -> void:
	if data == null or data.unit_class == null:
		return

	data.exp += amount
	while data.exp >= 100:
		data.exp -= 100
		_level_up_unit(data)


func _level_up_unit(data: UnitData) -> void:
	var cls: UnitClass = data.unit_class
	if cls == null:
		return

	data.level += 1
	print("Level up!", cls.display_name, "is now level", data.level)

	# Roll growths
	if randf() < cls.growth_hp:
		data.bonus_max_hp += 1
	if randf() < cls.growth_atk:
		data.bonus_atk += 1
	if randf() < cls.growth_defense:
		data.bonus_defense += 1
	if randf() < cls.growth_move:
		data.bonus_move += 1
	if randf() < cls.growth_mana:
		data.bonus_max_mana += 1

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

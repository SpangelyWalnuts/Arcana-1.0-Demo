extends Node

var run_active: bool = false
var current_floor: int = 0
var gold: int = 0

# All units the player owns this run (UnitClass resources)
var roster: Array[UnitData] = []
var deployed_units: Array[UnitData] = []

var artifacts: Array[Resource] = []

@export var available_equipment: Array = []  # list of Equipment resources to choose from
@export var available_items: Array = []      # list of Item resources to choose from

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

const ITEM_DEF_PATHS := [
	"res://data/items/healingpowder.tres",
	"res://data/items/AckuhRoot.tres",
]

const EQUIPMENT_DEF_PATHS := [
	"res://data/equipment/Steel_Shield.tres",
	"res://data/equipment/Boots.tres",
]

var item_defs: Array[Item] = []
var equipment_defs: Array[Equipment] = []

# Run-wide inventory: how many of each thing the player owns
var inventory_items: Dictionary = {}      # key: Item (Resource), value: int
var inventory_equipment: Dictionary = {}  # key: Equipment, value: int

# Shop stock for the current floor.
# Each entry is a Dictionary:
# { "resource": Resource, "type": "item"/"equipment", "price": int, "stock": int }
var shop_stock: Array = []

func _ready() -> void:
	randomize()

func start_new_run() -> void:
	run_active = true
	current_floor = 1
	gold = 100
	artifacts.clear()
	_load_item_defs()
	_load_equipment_defs()
	_setup_starting_roster()
	_goto_preparation()
	_setup_starting_inventory()
	generate_shop_stock(current_floor)


func _setup_starting_roster() -> void:
	roster.clear()

	for path in STARTING_UNIT_CLASS_PATHS:
		var res := load(path)

		if res is UnitClass:
			var data := UnitData.new()
			data.unit_class = res
			data.level = 1
			data.exp = 0

			# Default: equip up to 3 arcana from the class skill list
			data.equipped_arcana = []

			for s in res.skills:
				if s != null and data.equipped_arcana.size() < 3:
					data.equipped_arcana.append(s)

			roster.append(data)

			print("RunManager: added", res.display_name, "at level", data.level)



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

#EQUIPMENT AND ITEM LOAD

func _load_item_defs() -> void:
	item_defs.clear()
	for path in ITEM_DEF_PATHS:
		var res := load(path)
		if res is Item:
			item_defs.append(res)
		else:
			push_warning("RunManager: Failed to load Item at %s" % path)


func _load_equipment_defs() -> void:
	equipment_defs.clear()
	for path in EQUIPMENT_DEF_PATHS:
		var res := load(path)
		if res is Equipment:
			equipment_defs.append(res)
		else:
			push_warning("RunManager: Failed to load Equipment at %s" % path)

# ITEM EQUIPMENT STARTING HELPER 

func _setup_starting_inventory() -> void:
	inventory_items.clear()
	inventory_equipment.clear()

	# Example: give the player 3 small potions and 1 Steel_Shield if they exist
	if item_defs.size() > 0:
		var potion: Item = item_defs[0]
		inventory_items[potion] = 3

	if equipment_defs.size() > 0:
		var shield: Equipment = equipment_defs[0]
		inventory_equipment[shield] = 1

#STORE GENERATOR 
func generate_shop_stock(floor: int) -> void:
	shop_stock.clear()

	var base_item_price: int = 20 + floor * 5
	var base_equip_price: int = 40 + floor * 10

	var num_items: int = min(3, item_defs.size())
	var num_equips: int = min(3, equipment_defs.size())

	# Randomize selection
	var items_pool: Array = item_defs.duplicate()
	var equips_pool: Array = equipment_defs.duplicate()
	items_pool.shuffle()
	equips_pool.shuffle()

	# Items
	for i in range(num_items):
		var it = items_pool[i]
		var entry_item := {
			"resource": it,
			"type": "item",
			"price": base_item_price,
			"stock": 3
		}
		shop_stock.append(entry_item)

	# Equipment
	for j in range(num_equips):
		var eq = equips_pool[j]
		var entry_eq := {
			"resource": eq,
			"type": "equipment",
			"price": base_equip_price,
			"stock": 1
		}
		shop_stock.append(entry_eq)

#BUY HELPER
func try_buy_from_shop(index: int) -> Dictionary:
	var result := {
		"success": false,
		"reason": "",
		"entry": null
	}

	if index < 0 or index >= shop_stock.size():
		result["reason"] = "Invalid selection."
		return result

	var entry = shop_stock[index]
	var price: int = int(entry.get("price", 0))
	var stock: int = int(entry.get("stock", 0))
	var res = entry.get("resource", null)
	var type_str: String = String(entry.get("type", ""))

	if stock <= 0:
		result["reason"] = "Out of stock."
		return result

	if gold < price:
		result["reason"] = "Not enough gold."
		return result

	# Deduct gold and decrease stock
	gold -= price
	stock -= 1
	entry["stock"] = stock
	shop_stock[index] = entry

	# Add to run inventory
	if type_str == "item":
		var current: int = int(inventory_items.get(res, 0))
		inventory_items[res] = current + 1
	elif type_str == "equipment":
		var current2: int = int(inventory_equipment.get(res, 0))
		inventory_equipment[res] = current2 + 1

	result["success"] = true
	result["entry"] = entry
	return result

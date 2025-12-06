extends Node

var run_active: bool = false
var current_floor: int = 0
var gold: int = 0

# All units the player owns this run (UnitClass resources)
var roster: Array[UnitData] = []
var deployed_units: Array[UnitData] = []

var artifacts: Array[Resource] = []

var last_levelup_events: Array = []
# Each entry:
# {
#   "data": UnitData,
#   "name": String,
#   "new_level": int,
#   "hp_gain": int,
#   "atk_gain": int,
#   "def_gain": int,
#   "move_gain": int,
#   "mana_gain": int
# }

var last_exp_report: Array = [] 
# Each entry: {
#   "data": UnitData,
#   "name": String,
#   "exp_gained": int,
#   "level_before": int,
#   "level_after": int,
#   "exp_before": int,
#   "exp_after": int
# }


enum RewardType { GOLD, ITEM, EQUIPMENT, EXP_BOOST, ARTIFACT }

# The four options shown on the rewards screen after a battle.
# Each is a Dictionary:
# { "type": RewardType, "resource": Resource or null, "amount": int, "desc": String }
var pending_rewards: Array = []

@export var available_equipment: Array = []  # list of Equipment resources to choose from
@export var available_items: Array = []      # list of Item resources to choose from

const LEVEL_CAP: int = 20

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

func get_last_levelup_events() -> Array:
	return last_levelup_events


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
func _grant_post_battle_exp(enemies_defeated: int) -> void:
	last_exp_report.clear()

	# Base EXP scales with floor + enemies defeated
	var base_exp_deployed: int = 20 + current_floor * 5 + enemies_defeated * 3
	var base_exp_bench: int    = int(base_exp_deployed / 2)

	print("Granting post-battle EXP:",
		" deployed =", base_exp_deployed,
		" bench =", base_exp_bench)

	for data in roster:
		if data == null or data.unit_class == null:
			continue

		var exp_gain: int = 0
		if deployed_units.has(data):
			exp_gain = base_exp_deployed
		else:
			exp_gain = base_exp_bench

		var before_level: int = data.level
		var before_exp: int   = data.exp

		data.exp += exp_gain

		# Will increment level / bonuses as needed
		_process_level_ups_for_unit(data)

		var after_level: int = data.level
		var after_exp: int   = data.exp

		var entry := {
			"data": data,
			"name": data.unit_class.display_name,
			"exp_gained": exp_gain,
			"level_before": before_level,
			"level_after": after_level,
			"exp_before": before_exp,
			"exp_after": after_exp
		}

		last_exp_report.append(entry)


func _add_xp_to_unit(data: UnitData, amount: int) -> void:
	if data == null or data.unit_class == null:
		return

	data.exp += amount
	while data.exp >= 100:
		data.exp -= 100
		_level_up_unit(data)

#EXPORT FOR UI
func get_last_exp_report() -> Array:
	return last_exp_report


func _level_up_unit(data: UnitData) -> void:
	var cls: UnitClass = data.unit_class
	if cls == null:
		return

	# Track how much this specific level gave
	var hp_gain: int   = 0
	var atk_gain: int  = 0
	var def_gain: int  = 0
	var move_gain: int = 0
	var mana_gain: int = 0

	data.level += 1
	print("Level up!", cls.display_name, "is now level", data.level)

	# FE-style growth rolls
	if randf() < cls.growth_hp:
		data.bonus_max_hp += 1
		hp_gain += 1
	if randf() < cls.growth_atk:
		data.bonus_atk += 1
		atk_gain += 1
	if randf() < cls.growth_defense:
		data.bonus_defense += 1
		def_gain += 1
	if randf() < cls.growth_move:
		data.bonus_move += 1
		move_gain += 1
	if randf() < cls.growth_mana:
		data.bonus_max_mana += 1
		mana_gain += 1

	# Record this single level-up as an event
	var evt: Dictionary = {
		"data": data,
		"name": cls.display_name,
		"new_level": data.level,
		"hp_gain": hp_gain,
		"atk_gain": atk_gain,
		"def_gain": def_gain,
		"move_gain": move_gain,
		"mana_gain": mana_gain
	}
	last_levelup_events.append(evt)


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

#RUN REWARDS
func generate_rewards_for_floor(floor: int) -> void:
	pending_rewards.clear()

	# We always generate 4 options.
	for i in range(4):
		var option = _make_random_reward(floor, i)
		pending_rewards.append(option)


func _make_random_reward(floor: int, index: int) -> Dictionary:
	# Simple weighting by index:
	# 0–1: items/gold, 2: equipment/exp, 3: artifact / rare stuff
	var r = randi() % 100
	var reward_type: int

	match index:
		0, 1:
			# More likely to be gold or item
			if r < 40:
				reward_type = RewardType.GOLD
			elif r < 80:
				reward_type = RewardType.ITEM
			else:
				reward_type = RewardType.EQUIPMENT
		2:
			# More likely equipment or exp
			if r < 40:
				reward_type = RewardType.EQUIPMENT
			elif r < 80:
				reward_type = RewardType.EXP_BOOST
			else:
				reward_type = RewardType.GOLD
		3:
			# Rare-ish: artifact placeholder, exp, or equipment
			if r < 40:
				reward_type = RewardType.ARTIFACT
			elif r < 80:
				reward_type = RewardType.EXP_BOOST
			else:
				reward_type = RewardType.EQUIPMENT

	var option: Dictionary = {
		"type": reward_type,
		"resource": null,
		"amount": 0,
		"desc": ""
	}

	match reward_type:
		RewardType.GOLD:
			var base = 40 + floor * 10
			var variance = 20 + floor * 5
			var gold_amount = base + int(randi() % variance)
			option["amount"] = gold_amount
			option["desc"] = "Gain %d gold." % gold_amount

		RewardType.ITEM:
			if item_defs.size() == 0:
				# Fallback to gold if no items defined
				option["type"] = RewardType.GOLD
				var g = 50 + floor * 8
				option["amount"] = g
				option["desc"] = "Gain %d gold." % g
			else:
				var item = item_defs[int(randi() % item_defs.size())]
				var count = 1 + int(randi() % 2)  # 1–2 copies
				option["resource"] = item
				option["amount"] = count
				option["desc"] = "Receive %dx %s." % [count, item.name]

		RewardType.EQUIPMENT:
			if equipment_defs.size() == 0:
				# Fallback to gold
				option["type"] = RewardType.GOLD
				var g2 = 60 + floor * 12
				option["amount"] = g2
				option["desc"] = "Gain %d gold." % g2
			else:
				var eq = equipment_defs[int(randi() % equipment_defs.size())]
				option["resource"] = eq
				option["amount"] = 1
				option["desc"] = "Receive %s." % eq.name

		RewardType.EXP_BOOST:
			# Extra EXP to all units in the roster
			var exp_amount = 10 + floor * 3
			option["amount"] = exp_amount
			option["desc"] = "All allies gain %d bonus EXP." % exp_amount

		RewardType.ARTIFACT:
			# Placeholder for now. Later you can substitute real artifact resources.
			option["amount"] = 0
			option["desc"] = "Obtain a mysterious artifact (not yet implemented)."

	return option

#APPLY REWARDS
func apply_reward(option: Dictionary) -> void:
	if option.is_empty():
		return

	var reward_type = int(option.get("type", RewardType.GOLD))
	var res = option.get("resource", null)
	var amount = int(option.get("amount", 0))

	match reward_type:
		RewardType.GOLD:
			gold += amount

		RewardType.ITEM:
			if res is Item:
				var current = int(inventory_items.get(res, 0))
				inventory_items[res] = current + amount

		RewardType.EQUIPMENT:
			if res is Equipment:
				var current2 = int(inventory_equipment.get(res, 0))
				inventory_equipment[res] = current2 + amount

		RewardType.EXP_BOOST:
			# Simple version: add EXP to everyone in the roster
			for data in roster:
				if data == null:
					continue
				data.exp += amount
				# You can handle level-ups later when EXP crosses threshold

		RewardType.ARTIFACT:
			# TODO: hook into your future artifact system.
			# For now we just print.
			print("Artifact reward chosen (not implemented yet).")

	# Once a reward is taken, clear the list to avoid reusing it accidentally.
	pending_rewards.clear()

#POST BATTLE EXP
func grant_post_battle_exp(enemies_defeated: int) -> void:
	last_exp_report.clear()
	last_levelup_events.clear()  # 🔹 also clear old level-up events

	var base_exp_deployed: int = 20 + current_floor * 5 + enemies_defeated * 3
	var base_exp_bench: int    = int(base_exp_deployed / 2)

	print("Granting post-battle EXP:",
		" deployed =", base_exp_deployed,
		" bench =", base_exp_bench)

	if roster.is_empty():
		print("grant_post_battle_exp: roster is empty!")
		return

	for data in roster:
		if data == null or data.unit_class == null:
			continue

		var exp_gain: int = 0
		if deployed_units.has(data):
			exp_gain = base_exp_deployed
		else:
			exp_gain = base_exp_bench

		var before_level: int = data.level
		var before_exp: int   = data.exp

		data.exp += exp_gain

		# This will also append entries into last_levelup_events
		_process_level_ups_for_unit(data)

		var after_level: int = data.level
		var after_exp: int   = data.exp

		var entry: Dictionary = {
			"data": data,
			"name": data.unit_class.display_name,
			"exp_gained": exp_gain,
			"level_before": before_level,
			"level_after": after_level,
			"exp_before": before_exp,
			"exp_after": after_exp
		}

		last_exp_report.append(entry)

	print("grant_post_battle_exp: recorded", last_exp_report.size(), "entries in last_exp_report")
	print("grant_post_battle_exp: recorded", last_levelup_events.size(), "level-up events")

#LEVEL UP PROCESSING
func _process_all_level_ups() -> void:
	for data in roster:
		if data == null or data.unit_class == null:
			continue
		_process_level_ups_for_unit(data)


func _process_level_ups_for_unit(data: UnitData) -> void:
	var cls: UnitClass = data.unit_class
	if cls == null:
		return

	var exp_needed: int = max(cls.exp_per_level, 1)

	# Loop in case one big EXP gain gives multiple levels
	while data.level < LEVEL_CAP and data.exp >= exp_needed:
		data.exp -= exp_needed
		_level_up_unit(data)

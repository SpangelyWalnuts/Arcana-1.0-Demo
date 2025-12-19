extends Node

var run_active: bool = false
var current_floor: int = 0
var gold: int = 0

# --- Floor scaling (Option B) ---
var current_enemy_count: int = 4
var current_elite_chance: float = 0.08
var current_map_chunks: Vector2i = Vector2i(2, 2)
var current_deploy_limit: int = 4
var is_boss_floor: bool = false

# --- Weather (biome-driven) ---
var current_weather: StringName = &"clear"

# --- Biomes ---
var current_biome: StringName = &"ruins"

#--- Status Skills ---
var _wet_status_skill: Skill
var _chilled_status_skill: Skill

# --- Encounter tags ---
var current_encounter_tag: StringName = &"none"
@export_range(0.0, 1.0, 0.05) var encounter_tag_chance: float = 0.60 # 60% tagged, 40% none

# All units the player owns this run (per-unit data)
var roster: Array[UnitData] = []
var deployed_units: Array[UnitData] = []

# --- Draft system ---
var all_unit_classes: Array[UnitClass] = []          # pool of all possible draftable classes
var draft_round: int = 0
var max_draft_picks: int = 4                         # pick 1 of 4, 4 times
var current_draft_options: Array[UnitClass] = []     # options in the current draft round

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
# Each entry:
# {
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

# 👉 All possible unit classes for this run (starting pool).
#    You can expand this over time.
const STARTING_UNIT_CLASS_PATHS := [
	"res://data/unit_classes/Geomancer.tres",
	"res://data/unit_classes/Druid.tres",
	"res://data/unit_classes/Pyromancer.tres",
	"res://data/unit_classes/Cleric.tres",
	"res://data/unit_classes/Artificer.tres",
	"res://data/unit_classes/Cryomancer.tres",
	"res://data/unit_classes/Shaman.tres",
	"res://data/unit_classes/Electromancer.tres",
]

# If/when you add a dedicated draft UI scene:
const DRAFT_SCENE_PATH  := "res://scenes/ui/DraftScreen.tscn"

const PREP_SCENE_PATH   := "res://scenes/core/preparation_screen.tscn"
const BATTLE_SCENE_PATH := "res://scenes/core/Main.tscn"
const TITLE_SCENE_PATH  := "res://scenes/core/TitleScreen.tscn"

const ITEM_DEF_PATHS := [
	"res://data/items/healingpowder.tres",
	"res://data/items/AckuhRoot.tres",
]

const EQUIPMENT_DEF_PATHS := [
	"res://data/equipment/common/Book.tres",
	"res://data/equipment/uncommon/Boots.tres",
	"res://data/equipment/common/RefinedRing.tres",
	"res://data/equipment/common/ProtectionStone.tres",
	"res://data/equipment/legendary/ParallelThought.tres",
	"res://data/equipment/rare/StartingGear.tres",
	"res://data/equipment/common/VitalityStone.tres",
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


# -------------------------------------------------------------------
#  START / END OF RUN
# -------------------------------------------------------------------
func start_new_run() -> void:
	run_active = true
	current_floor = 1
	refresh_floor_config()
	gold = 100
	artifacts.clear()

	# Reset state
	roster.clear()
	deployed_units.clear()
	last_exp_report.clear()
	last_levelup_events.clear()

	_load_item_defs()
	_load_equipment_defs()
	_load_all_unit_classes()

	draft_round = 0
	# Start the first draft round (also changes scene to DraftScreen)
	_start_draft_round()


func return_to_title() -> void:
	run_active = false
	current_floor = 0
	gold = 0
	roster.clear()
	deployed_units.clear()
	artifacts.clear()

	var packed: PackedScene = load(TITLE_SCENE_PATH)
	if packed == null:
		push_error("RunManager: Could not load title scene at %s" % TITLE_SCENE_PATH)
		return
	get_tree().change_scene_to_packed(packed)


func advance_floor() -> bool:
	current_floor += 1
	refresh_floor_config()
	print("Advancing to floor", current_floor)
	return true

func get_floor_config(floor: int) -> Dictionary:
	# Floor bands: every 3 floors increases map size + baseline counts.
	var band: int = int((floor - 1) / 3)
# Map size progression:
# 2x1 -> 2x2 -> 3x3 -> 4x4 -> 5x5 (then stay at 5x5)
	var stage: int = clampi(band, 0, 4)

	var map_chunks: Vector2i
	match stage:
		0:
			map_chunks = Vector2i(2, 1)
		1:
			map_chunks = Vector2i(2, 2)
		2:
			map_chunks = Vector2i(3, 3)
		3:
			map_chunks = Vector2i(4, 4)
		_:
			map_chunks = Vector2i(5, 5)
# Biome rotates every floor:
# 1 ruins, 2 forest, 3 catacombs, 4 tundra, 5 volcano, 6 ruins...
	var biome: StringName = &"taiga"
	var biome_index: int = (floor - 1) % 5
	var weather: StringName = _roll_weather_for_biome(biome)


	match biome_index:
		0:
			biome = &"ruins"
		1:
			biome = &"forest"
		2:
			biome = &"catacombs"
		3:
			biome = &"taiga"
		_:
			biome = &"volcano"

	# Boss floors
	var boss: bool = (floor % 5) == 0

	# Enemy count grows with band; boss floors add pressure
	var enemy_count: int = 4 + (band * 2)
	if boss:
		enemy_count += 2

	# Elite chance ramps slowly with floor (clamped)
	var elite: float = clampf(0.08 + (0.02 * float(floor - 1)), 0.08, 0.35)

	# Deploy limit scales with map size but never exceeds enemy count
	var deploy: int = clampi(3 + band, 3, 6)
	deploy = mini(deploy, enemy_count)
	var encounter_tag: StringName = _roll_encounter_tag(floor, boss)

	return {
		"floor": floor,
		"band": band,
		"map_chunks": map_chunks,
		"enemy_count": enemy_count,
		"elite_chance": elite,
		"deploy_limit": deploy,
		"encounter_tag": encounter_tag,
		"biome": biome,
		"weather": weather,
		"is_boss_floor": boss
	}


func refresh_floor_config() -> void:
	var cfg: Dictionary = get_floor_config(current_floor)

	current_encounter_tag = StringName(cfg.get("encounter_tag", &"none"))
	current_map_chunks = cfg["map_chunks"] as Vector2i
	current_enemy_count = int(cfg["enemy_count"])
	current_elite_chance = float(cfg["elite_chance"])
	current_deploy_limit = int(cfg["deploy_limit"])
	is_boss_floor = bool(cfg["is_boss_floor"])
	current_biome = StringName(cfg.get("biome", &"ruins"))
	current_weather = StringName(cfg.get("weather", &"clear"))

#UI ACCESSOR
func get_biome() -> StringName:
	return current_biome

# ENCOUNTERS
func _roll_encounter_tag(floor: int, boss: bool) -> StringName:
	# Boss floors are special already; keep tags off for clarity.
	if boss:
		return &"none"

	# 70/30: "none" vs "tag"
	var roll: float = randf()
	if roll >= encounter_tag_chance:
		return &"none"

	# Pick a tag. Start simple: equal weights.
	var tags: Array[StringName] = [&"swarm", &"elite_guard", &"caster_heavy"]
	return tags[int(randi() % tags.size())]

func get_deploy_limit() -> int:
	# Safe accessor for UI scenes.
	return current_deploy_limit

# -------------------------------------------------------------------
#  DRAFT SYSTEM
# -------------------------------------------------------------------
func _build_all_unit_classes() -> void:
	all_unit_classes.clear()
	for path in STARTING_UNIT_CLASS_PATHS:
		var res: Resource = load(path)
		if res is UnitClass:
			all_unit_classes.append(res as UnitClass)
		else:
			push_warning("RunManager: Failed to load UnitClass at %s" % path)


# Simple fallback: auto-draft 4 units randomly (used when no DraftScreen yet).
func _auto_draft_starting_party() -> void:
	roster.clear()

	if all_unit_classes.is_empty():
		_build_all_unit_classes()

	var pool: Array[UnitClass] = all_unit_classes.duplicate()
	pool.shuffle()

	var picks: int = min(max_draft_picks, pool.size())
	for i in range(picks):
		var cls: UnitClass = pool[i]
		var data: UnitData = UnitData.new()
		data.unit_class = cls
		data.level = 1
		data.exp = 0

		# Default: equip up to 3 arcana from the class skill list
		data.equipped_arcana = []
		for s in cls.skills:
			if s != null and data.equipped_arcana.size() < 3:
				data.equipped_arcana.append(s)

		roster.append(data)
		print("RunManager [auto-draft]: added", cls.display_name, "at level", data.level)


# Multi-round draft: “pick 1 of 4, 4 times”.
func _start_next_draft_round() -> void:
	if draft_round >= max_draft_picks:
		# Draft complete → go to Preparation
		print("Draft complete; roster size:", roster.size())
		_setup_starting_inventory()
		generate_shop_stock(current_floor)
		_goto_preparation()
		return

	draft_round += 1
	current_draft_options.clear()

	if all_unit_classes.is_empty():
		_build_all_unit_classes()

	var pool: Array[UnitClass] = all_unit_classes.duplicate()
	pool.shuffle()

	var picks: int = min(4, pool.size())
	for i in range(picks):
		current_draft_options.append(pool[i])

	_show_draft_screen()


# TODO UI hook: for now just logs. Later you’ll create DraftScreen.tscn and pass these options to it.
func _show_draft_screen() -> void:
	print("=== DRAFT ROUND %d ===" % draft_round)
	for i in range(current_draft_options.size()):
		var cls: UnitClass = current_draft_options[i]
		print("  Option %d: %s" % [i, cls.display_name])
	# In your DraftScreen script, you’ll call RunManager.choose_unit_from_draft(index).


# Called by DraftScreen when player chooses one of the 4 options (by index).
func choose_unit_from_draft(index: int) -> void:
	if index < 0 or index >= current_draft_options.size():
		return

	var cls: UnitClass = current_draft_options[index]

	var data: UnitData = UnitData.new()
	data.unit_class = cls
	data.level = 1
	data.exp = 0

	data.equipped_arcana = []
	for s in cls.skills:
		if s != null and data.equipped_arcana.size() < 3:
			data.equipped_arcana.append(s)

	roster.append(data)
	print("Draft pick:", cls.display_name, " -> roster size now:", roster.size())

	# Proceed to next round (or prep when done)
	_start_next_draft_round()


func get_current_draft_options() -> Array[UnitClass]:
	return current_draft_options


# -------------------------------------------------------------------
#  SCENE TRANSITIONS
# -------------------------------------------------------------------
func _goto_preparation() -> void:
	var packed: PackedScene = load(PREP_SCENE_PATH)
	if packed == null:
		push_error("RunManager: Could not load Preparation scene at %s" % PREP_SCENE_PATH)
		return
	get_tree().change_scene_to_packed(packed)


func goto_battle_scene() -> void:
	var packed: PackedScene = load(BATTLE_SCENE_PATH)
	if packed == null:
		push_error("RunManager: Could not load battle scene at %s" % BATTLE_SCENE_PATH)
		return
	get_tree().change_scene_to_packed(packed)


# -------------------------------------------------------------------
#  EXP / LEVEL UP
# -------------------------------------------------------------------
func get_last_levelup_events() -> Array:
	return last_levelup_events


func get_last_exp_report() -> Array:
	return last_exp_report


func _add_xp_to_unit(data: UnitData, amount: int) -> void:
	if data == null or data.unit_class == null:
		return

	data.exp += amount
	while data.exp >= 100 and data.level < LEVEL_CAP:
		data.exp -= 100
		_level_up_unit(data)


func _level_up_unit(data: UnitData) -> void:
	var cls: UnitClass = data.unit_class
	if cls == null:
		return

	var hp_gain: int   = 0
	var atk_gain: int  = 0
	var def_gain: int  = 0
	var move_gain: int = 0
	var mana_gain: int = 0

	data.level += 1
	print("Level up!", cls.display_name, "is now level", data.level)

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

	var evt: Dictionary = {
		"data": data,
		"name": cls.display_name,
		"new_level": data.level,
		"hp_gain": hp_gain,
		"atk_gain": atk_gain,
		"def_gain": def_gain,
		"move_gain": move_gain,
		"mana_gain": mana_gain,
	}
	last_levelup_events.append(evt)


func grant_post_battle_exp(enemies_defeated: int) -> void:
	last_exp_report.clear()
	last_levelup_events.clear()

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

	while data.level < LEVEL_CAP and data.exp >= exp_needed:
		data.exp -= exp_needed
		_level_up_unit(data)


# -------------------------------------------------------------------
#  ITEM / EQUIPMENT DEFINITIONS + INVENTORY
# -------------------------------------------------------------------
func _load_item_defs() -> void:
	item_defs.clear()
	for path in ITEM_DEF_PATHS:
		var res: Resource = load(path)
		if res is Item:
			item_defs.append(res as Item)
		else:
			push_warning("RunManager: Failed to load Item at %s" % path)


func _load_equipment_defs() -> void:
	equipment_defs.clear()
	for path in EQUIPMENT_DEF_PATHS:
		var res: Resource = load(path)
		if res is Equipment:
			equipment_defs.append(res as Equipment)
		else:
			push_warning("RunManager: Failed to load Equipment at %s" % path)


func _setup_starting_inventory() -> void:
	inventory_items.clear()
	inventory_equipment.clear()

	if item_defs.size() > 0:
		var potion: Item = item_defs[0]
		inventory_items[potion] = 3

	if equipment_defs.size() > 0:
		var shield: Equipment = equipment_defs[0]
		inventory_equipment[shield] = 1


# -------------------------------------------------------------------
#  SHOP
# -------------------------------------------------------------------
func generate_shop_stock(floor: int) -> void:
	shop_stock.clear()

	var base_item_price: int = 20 + floor * 5
	var base_equip_price: int = 40 + floor * 10

	var num_items: int = min(3, item_defs.size())
	var num_equips: int = min(3, equipment_defs.size())

	var items_pool: Array[Item] = item_defs.duplicate()
	var equips_pool: Array[Equipment] = equipment_defs.duplicate()
	items_pool.shuffle()
	equips_pool.shuffle()

	for i in range(num_items):
		var it: Item = items_pool[i]
		var entry_item: Dictionary = {
			"resource": it,
			"type": "item",
			"price": base_item_price,
			"stock": 3
		}
		shop_stock.append(entry_item)

	for j in range(num_equips):
		var eq: Equipment = equips_pool[j]
		var entry_eq: Dictionary = {
			"resource": eq,
			"type": "equipment",
			"price": base_equip_price,
			"stock": 1
		}
		shop_stock.append(entry_eq)


func try_buy_from_shop(index: int) -> Dictionary:
	var result: Dictionary = {
		"success": false,
		"reason": "",
		"entry": null
	}

	if index < 0 or index >= shop_stock.size():
		result["reason"] = "Invalid selection."
		return result

	var entry: Dictionary = shop_stock[index]
	var price: int = int(entry.get("price", 0))
	var stock: int = int(entry.get("stock", 0))
	var res: Resource = entry.get("resource", null)
	var type_str: String = String(entry.get("type", ""))

	if stock <= 0:
		result["reason"] = "Out of stock."
		return result

	if gold < price:
		result["reason"] = "Not enough gold."
		return result

	gold -= price
	stock -= 1
	entry["stock"] = stock
	shop_stock[index] = entry

	if type_str == "item":
		var current: int = int(inventory_items.get(res, 0))
		inventory_items[res] = current + 1
	elif type_str == "equipment":
		var current2: int = int(inventory_equipment.get(res, 0))
		inventory_equipment[res] = current2 + 1

	result["success"] = true
	result["entry"] = entry
	return result


# -------------------------------------------------------------------
#  RUN REWARDS
# -------------------------------------------------------------------
func generate_rewards_for_floor(floor: int) -> void:
	pending_rewards.clear()
	for i in range(4):
		var option: Dictionary = _make_random_reward(floor, i)
		pending_rewards.append(option)


func _make_random_reward(floor: int, index: int) -> Dictionary:
	var r: int = int(randi() % 100)
	var reward_type: int

	match index:
		0, 1:
			if r < 40:
				reward_type = RewardType.GOLD
			elif r < 80:
				reward_type = RewardType.ITEM
			else:
				reward_type = RewardType.EQUIPMENT
		2:
			if r < 40:
				reward_type = RewardType.EQUIPMENT
			elif r < 80:
				reward_type = RewardType.EXP_BOOST
			else:
				reward_type = RewardType.GOLD
		3:
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
			var base: int = 40 + floor * 10
			var variance: int = 20 + floor * 5
			var gold_amount: int = base + int(randi() % variance)
			option["amount"] = gold_amount
			option["desc"] = "Gain %d gold." % gold_amount

		RewardType.ITEM:
			if item_defs.size() == 0:
				option["type"] = RewardType.GOLD
				var g: int = 50 + floor * 8
				option["amount"] = g
				option["desc"] = "Gain %d gold." % g
			else:
				var item: Item = item_defs[int(randi() % item_defs.size())]
				var count: int = 1 + int(randi() % 2)
				option["resource"] = item
				option["amount"] = count
				option["desc"] = "Receive %dx %s." % [count, item.name]

		RewardType.EQUIPMENT:
			if equipment_defs.size() == 0:
				option["type"] = RewardType.GOLD
				var g2: int = 60 + floor * 12
				option["amount"] = g2
				option["desc"] = "Gain %d gold." % g2
			else:
				var eq: Equipment = equipment_defs[int(randi() % equipment_defs.size())]
				option["resource"] = eq
				option["amount"] = 1
				option["desc"] = "Receive %s." % eq.name

		RewardType.EXP_BOOST:
			var exp_amount: int = 10 + floor * 3
			option["amount"] = exp_amount
			option["desc"] = "All allies gain %d bonus EXP." % exp_amount

		RewardType.ARTIFACT:
			option["amount"] = 0
			option["desc"] = "Obtain a mysterious artifact (not yet implemented)."

	return option


func apply_reward(option: Dictionary) -> void:
	if option.is_empty():
		return

	var reward_type: int = int(option.get("type", RewardType.GOLD))
	var res: Resource = option.get("resource", null)
	var amount: int = int(option.get("amount", 0))

	match reward_type:
		RewardType.GOLD:
			gold += amount

		RewardType.ITEM:
			if res is Item:
				var current: int = int(inventory_items.get(res, 0))
				inventory_items[res] = current + amount

		RewardType.EQUIPMENT:
			if res is Equipment:
				var current2: int = int(inventory_equipment.get(res, 0))
				inventory_equipment[res] = current2 + amount

		RewardType.EXP_BOOST:
			for data in roster:
				if data == null:
					continue
				data.exp += amount
				# Level-ups for reward EXP are handled later with _process_level_ups_for_unit if you want.

		RewardType.ARTIFACT:
			print("Artifact reward chosen (not implemented yet).")

	pending_rewards.clear()

# Load unit HELPER

func _load_all_unit_classes() -> void:
	all_unit_classes.clear()

	for path in STARTING_UNIT_CLASS_PATHS:
		var res := load(path)
		if res is UnitClass:
			all_unit_classes.append(res)
		else:
			push_warning("RunManager: Failed to load UnitClass at %s" % path)

	if all_unit_classes.is_empty():
		push_error("RunManager: all_unit_classes is empty! Check STARTING_UNIT_CLASS_PATHS.")

#DRAFT STARTER
func _start_draft_round() -> void:
	if all_unit_classes.is_empty():
		# Fallback: if something went wrong, just create a basic roster and go to prep.
		
		_setup_starting_inventory()
		generate_shop_stock(current_floor)
		_goto_preparation()
		return

	draft_round += 1
	current_draft_options.clear()

	# Pick up to 4 random classes out of all_unit_classes
	var pool: Array[UnitClass] = all_unit_classes.duplicate()
	pool.shuffle()

	var count: int = min(4, pool.size())
	for i in range(count):
		current_draft_options.append(pool[i])

	# Go to DraftScreen
	var packed := load(DRAFT_SCENE_PATH)
	if packed == null:
		push_error("RunManager: Could not load DraftScreen at %s" % DRAFT_SCENE_PATH)
		# Fallback: if draft screen cannot be loaded, just skip to prep
		
		_setup_starting_inventory()
		generate_shop_stock(current_floor)
		_goto_preparation()
		return

	get_tree().change_scene_to_packed(packed)

#CHOOSE DRAFT UNIT
func choose_draft_unit(choice_index: int) -> void:
	if choice_index < 0 or choice_index >= current_draft_options.size():
		return

	var cls: UnitClass = current_draft_options[choice_index]
	if cls == null:
		return

	# Build a new UnitData entry for this pick
	var data := UnitData.new()
	data.unit_class = cls
	data.level = 1
	data.exp = 0

	# Default: equip up to 3 arcana from the class skill list
	data.equipped_arcana = []
	for s in cls.skills:
		if s != null and data.equipped_arcana.size() < 3:
			data.equipped_arcana.append(s)

	roster.append(data)
	print("Draft pick:", cls.display_name, " -> roster size now", roster.size())

	# If we haven't finished all picks, start another draft round
	if draft_round < max_draft_picks:
		_start_draft_round()
		return

	# Draft complete: set deployed units to your newly drafted roster for floor 1
	deployed_units.clear()
	for d in roster:
		deployed_units.append(d)

	_setup_starting_inventory()
	generate_shop_stock(current_floor)

	# Now go to the normal preparation screen
	_goto_preparation()

#WEATHER HELPERS
func _roll_weather_for_biome(biome: StringName) -> StringName:
	# v1 weather list: clear, snow
	# Only taiga has snow for now (per your art support).
	if biome == &"taiga":
		# 30% snow, 70% clear (tweak anytime)
		var r: float = randf()
		if r < .90:
			return &"snow"
		return &"clear"

	# All other biomes: clear (for now)
	return &"clear"


func get_weather() -> StringName:
	return current_weather

#STATUS SKILL STUFF
func get_wet_status_skill() -> Skill:
	if _wet_status_skill == null:
		_wet_status_skill = Skill.new()
		_wet_status_skill.name = "Wet"
		_wet_status_skill.effect_type = Skill.EffectType.DEBUFF
		_wet_status_skill.duration_turns = 4
		_wet_status_skill.status_key = &"wet"
		_wet_status_skill.tags = [&"water"]
	return _wet_status_skill

func get_chilled_status_skill() -> Skill:
	if _chilled_status_skill == null:
		_chilled_status_skill = Skill.new()
		_chilled_status_skill.name = "Chilled"
		_chilled_status_skill.effect_type = Skill.EffectType.DEBUFF
		_chilled_status_skill.duration_turns = 4
		_chilled_status_skill.move_mod = -1
		_chilled_status_skill.status_key = &"chilled"
		_chilled_status_skill.tags = [&"ice"]
	return _chilled_status_skill

var _shocked_status_skill: Skill

func get_shocked_status_skill() -> Skill:
	if _shocked_status_skill == null:
		_shocked_status_skill = Skill.new()
		_shocked_status_skill.name = "Shocked"
		_shocked_status_skill.effect_type = Skill.EffectType.DEBUFF
		_shocked_status_skill.duration_turns = 2
		_shocked_status_skill.prevent_move = true
		_shocked_status_skill.status_key = &"shocked"
		_shocked_status_skill.tags = [&"lightning"]
	return _shocked_status_skill
	
var _frozen_status_skill: Skill

func get_frozen_status_skill() -> Skill:
	if _frozen_status_skill == null:
		_frozen_status_skill = Skill.new()
		_frozen_status_skill.name = "Frozen"
		_frozen_status_skill.effect_type = Skill.EffectType.DEBUFF
		_frozen_status_skill.duration_turns = 2
		_frozen_status_skill.prevent_move = true
		_frozen_status_skill.status_key = &"frozen"
		_frozen_status_skill.tags = [&"ice"]
	return _frozen_status_skill

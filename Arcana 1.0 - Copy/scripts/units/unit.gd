extends Node2D

# --- Mana / Skills ---
var max_mana: int = 5
var mana: int = 5
var mana_regen_per_turn: int = 1
var skills: Array = []   # array of Skill resources
var level: int = 1
var exp: int = 0
var unit_data: UnitData = null

@export var unit_class: UnitClass
@export var is_active: bool = true

var grid_position: Vector2i
var move_range: int = 4

# --- STATUS SYSTEM: buffs / debuffs live here as Dictionaries ---
var active_statuses: Array = []  # each entry is a Dictionary

var team: String = "player"   # "player" or "enemy"
var has_acted: bool = false

var max_hp: int = 10
var hp: int = 10
var atk: int = 4
var defense: int = 1
var attack_range: int = 1

@onready var hp_bg: ColorRect   = $HPBar/BG
@onready var hp_fill: ColorRect = $HPBar/Fill


func _ready() -> void:
	if not is_active:
		return

	# 1) Decide source of class / level / exp
	if unit_data != null and unit_data.unit_class != null:
		# If we have UnitData, let it drive everything
		unit_class = unit_data.unit_class
		level = unit_data.level
		exp   = unit_data.exp
	elif unit_class != null:
		# Fallback: class only, no UnitData
		level = 1
		exp   = 0

	# 2) Base stats from class (or some safe defaults if no class)
	if unit_class != null:
		max_hp       = unit_class.max_hp
		atk          = unit_class.atk
		defense      = unit_class.defense
		attack_range = unit_class.attack_range
		move_range   = unit_class.move_range
		team         = unit_class.team

		max_mana             = unit_class.max_mana
		mana_regen_per_turn  = unit_class.mana_regen_per_turn
	else:
		# In case something was spawned without a class at all
		max_hp       = 10
		atk          = 1
		defense      = 0
		attack_range = 1
		move_range   = 4
		max_mana     = 0
		mana_regen_per_turn = 0

	# 3) Apply permanent per-unit bonuses from UnitData (level-ups, artifacts, etc.)
	if unit_data != null:
		max_hp     += unit_data.bonus_max_hp
		atk        += unit_data.bonus_atk
		defense    += unit_data.bonus_defense
		move_range += unit_data.bonus_move
		max_mana   += unit_data.bonus_max_mana

	# 4) Apply equipment bonuses on top
	if unit_data != null and unit_data.equipment_slots.size() > 0:
		for eq in unit_data.equipment_slots:
			if eq == null:
				continue
			var e := eq as Equipment
			if e == null:
				continue

			max_hp     += e.bonus_max_hp
			atk        += e.bonus_atk
			defense    += e.bonus_defense
			move_range += e.bonus_move
			max_mana   += e.bonus_max_mana

	# 5) Finally set current HP / Mana to the *final* max values
	hp   = max_hp
	mana = max_mana

	# 6) Decide skills: prefer equipped arcana, otherwise class defaults
	if unit_data != null and unit_data.equipped_arcana.size() > 0:
		skills = unit_data.equipped_arcana.duplicate()
	elif unit_class != null:
		skills = unit_class.skills.duplicate()
	else:
		skills = []

	# 7) Update HP bar & groups
	_update_hp_bar()

	if team == "player":
		add_to_group("player_units")
	elif team == "enemy":
		add_to_group("enemy_units")


# --- STATUS SYSTEM HELPERS ---

func regenerate_mana() -> void:
	var regen: int = mana_regen_per_turn

	# Allow statuses to modify mana regen
	for s in active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		regen += int(s.get("mana_regen_mod", 0))

	if regen < 0:
		regen = 0

	mana += regen
	if mana > max_mana:
		mana = max_mana


func reset_for_new_turn() -> void:
	has_acted = false
	regenerate_mana()
	_tick_status_effects()


func _tick_status_effects() -> void:
	var remaining: Array = []
	for s in active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue

		var turns: int = int(s.get("remaining_turns", 0))
		if turns > 0:
			turns -= 1
			if turns > 0:
				s["remaining_turns"] = turns
				remaining.append(s)
			# if turns == 0, it expires
		else:
			# 0 or negative duration means "until consumed" or permanent
			remaining.append(s)

	active_statuses = remaining


func get_effective_atk() -> int:
	var result: int = atk
	for s in active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		result += int(s.get("atk_mod", 0))
	return max(result, 0)


func get_effective_defense() -> int:
	var result: int = defense
	for s in active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		result += int(s.get("def_mod", 0))
	return max(result, 0)


func get_effective_move_range() -> int:
	var result: int = move_range
	for s in active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		result += int(s.get("move_mod", 0))
	return max(result, 0)


func can_cast_arcana() -> bool:
	for s in active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if s.get("prevent_arcana", false):
			return false
	return true


func can_move() -> bool:
	for s in active_statuses:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		if s.get("prevent_move", false):
			return false
	return true


func is_enemy_of(other) -> bool:
	return team != other.team


func take_damage(amount: int) -> bool:
	hp -= amount
	print(name, " took ", amount, " damage. HP now: ", hp)

	_update_hp_bar()

	if hp <= 0:
		die()
		return false

	return true


signal died

func die() -> void:
	print(name, " has been defeated.")

	# Notify listeners (Main.gd, etc.)
	died.emit()

	# Make sure we are no longer in unit groups
	if team == "enemy":
		remove_from_group("enemy_units")
	elif team == "player":
		remove_from_group("player_units")

	# Finally destroy the node
	queue_free()


func _update_hp_bar() -> void:
	if hp_fill == null or hp_bg == null:
		return

	var ratio: float = clamp(float(hp) / float(max_hp), 0.0, 1.0) as float

	# Use the background bar width as the "full" width
	var full_width: float = hp_bg.size.x
	hp_fill.size.x = full_width * ratio


func update_hp_bar() -> void:
	_update_hp_bar()

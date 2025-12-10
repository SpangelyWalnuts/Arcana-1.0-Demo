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
var active_statuses: Array = []  # list of Dictionaries for now

var team: String = "player"   # "player" or "enemy"
var has_acted: bool = false

var max_hp: int = 10
var hp: int = 10
var atk: int = 4
var defense: int = 1
var attack_range: int = 1


@onready var hp_bg: ColorRect   = $HPBar/BG
@onready var hp_fill: ColorRect = $HPBar/Fill
@onready var status_icons_root: HBoxContainer = $StatusIcons
@onready var sprite: Sprite2D = $Sprite2D




#HELPERS
func add_status(status: Dictionary) -> void:
	active_statuses.append(status)


func has_status_flag(flag: String) -> bool:
	for st in active_statuses:
		if st is Dictionary and st.get(flag, false):
			return true
	return false

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

		# DO **NOT** override team here anymore.
		max_mana            = unit_class.max_mana
		mana_regen_per_turn = unit_class.mana_regen_per_turn
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
		level = unit_data.level
		exp   = unit_data.exp

		max_hp       += unit_data.bonus_max_hp
		atk          += unit_data.bonus_atk
		defense      += unit_data.bonus_defense
		move_range   += unit_data.bonus_move
		max_mana     += unit_data.bonus_max_mana

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

	# 7) Add to correct group
	# If team somehow isn't set, default to player.
	if team != "player" and team != "enemy":
		team = "player"

	if team == "player":
		add_to_group("player_units")
	elif team == "enemy":
		add_to_group("enemy_units")

	# Cache status icon root if present
	if has_node("StatusIcons"):
		status_icons_root = $StatusIcons
		
	# 6.5) Set sprite based on UnitClass
	if sprite != null and unit_class != null and unit_class.sprite_texture != null:
		sprite.texture = unit_class.sprite_texture

	_update_hp_bar()
	refresh_status_icons()  # start empty, but keeps UI clean

	# 🔹 Listen for status changes (to update icons)
	if Engine.has_singleton("StatusManager"):
		StatusManager.status_changed.connect(_on_status_changed)

func _on_status_changed(changed_unit) -> void:
	if changed_unit == self:
		refresh_status_icons()

func regenerate_mana() -> void:
	var bonus_regen: int = 0
	if Engine.has_singleton("StatusManager"):
		# If you use Autoload named StatusManager
		bonus_regen = StatusManager.get_mana_regen_bonus(self)

	mana += mana_regen_per_turn + bonus_regen
	if mana > max_mana:
		mana = max_mana




func reset_for_new_turn() -> void:
	has_acted = false
	regenerate_mana()
	# Later, when you add duration ticking, you'll update active_statuses
	# and then call refresh_status_icons() here.



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


# -------------------------------------------------
#  STATUS + UI HELPERS
# -------------------------------------------------


func can_move() -> bool:
	return not has_status_flag("prevent_move")

func can_cast_arcana() -> bool:
	return not has_status_flag("prevent_arcana")

func refresh_status_icons() -> void:
	if status_icons_root == null:
		return

	# Clear existing icons/labels
	for child in status_icons_root.get_children():
		child.queue_free()

	# Ask StatusManager for this unit's statuses
	var statuses: Array = []
	if Engine.has_singleton("StatusManager"):
		statuses = StatusManager.get_statuses_for_unit(self)

	if statuses.is_empty():
		return

	# Combine flags (so we don't show duplicate icons for multiple statuses)
	var flags := {
		"prevent_arcana": false,
		"prevent_move":   false
	}

	for s in statuses:
		if typeof(s) == TYPE_DICTIONARY:
			if s.get("prevent_arcana", false):
				flags["prevent_arcana"] = true
			if s.get("prevent_move", false):
				flags["prevent_move"] = true

	# For now we show simple text labels; you can swap these for TextureRect icons later
	if flags["prevent_arcana"]:
		var lbl := Label.new()
		lbl.text = "⛔ Arcana"
		status_icons_root.add_child(lbl)

	if flags["prevent_move"]:
		var lbl2 := Label.new()
		lbl2.text = "⛔ Move"
		status_icons_root.add_child(lbl2)

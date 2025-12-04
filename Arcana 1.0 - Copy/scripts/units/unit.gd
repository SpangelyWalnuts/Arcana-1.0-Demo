extends Node2D

# --- Mana / Skills ---
var max_mana: int = 5
var mana: int = 5
var mana_regen_per_turn: int = 1
var skills: Array = []   # array of Skill resources

@export var unit_class: UnitClass
@export var is_active: bool = true

var grid_position: Vector2i
var move_range: int = 4

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

	if unit_class != null:
		print("Unit spawned: name=", name,
			"  class=", unit_class.display_name,
			"  hp=", unit_class.max_hp,
			"  atk=", unit_class.atk,
			"  def=", unit_class.defense)

		max_hp       = unit_class.max_hp
		hp           = max_hp
		atk          = unit_class.atk
		defense      = unit_class.defense
		attack_range = unit_class.attack_range
		move_range   = unit_class.move_range
		team         = unit_class.team

		max_mana          = unit_class.max_mana
		mana              = max_mana
		mana_regen_per_turn = unit_class.mana_regen_per_turn
		skills            = unit_class.skills.duplicate()

	_update_hp_bar()

	if team == "player":
		add_to_group("player_units")
	elif team == "enemy":
		add_to_group("enemy_units")

func regenerate_mana() -> void:
	mana += mana_regen_per_turn
	if mana > max_mana:
		mana = max_mana

func reset_for_new_turn() -> void:
	has_acted = false
	regenerate_mana()



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
	died.emit()
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

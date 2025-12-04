extends Resource
class_name UnitClass

@export var display_name: String = "Unit"
@export var max_hp: int = 10
@export var atk: int = 4
@export var defense: int = 1
@export var attack_range: int = 1
@export var move_range: int = 4
@export var team: String = "player"

# --- Mana / Arcana ---
@export var max_mana: int = 5
@export var mana_regen_per_turn: int = 1

# Skills that this class can use
@export var skills: Array[Resource] = []  # will be Skill resources

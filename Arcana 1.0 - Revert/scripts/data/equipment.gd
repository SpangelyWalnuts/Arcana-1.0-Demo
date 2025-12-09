extends Resource
class_name Equipment

@export var name: String = "Equipment"
@export_multiline var description: String = ""

@export_enum("Common", "Uncommon", "Rare", "Legendary")
var rarity: String = "Common"

# Stat bonuses this equipment gives
@export var bonus_max_hp: int = 0
@export var bonus_atk: int = 0
@export var bonus_defense: int = 0
@export var bonus_move: int = 0
@export var bonus_max_mana: int = 0

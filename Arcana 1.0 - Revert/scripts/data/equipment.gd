extends Resource
class_name Equipment

@export var name: String = "Equipment"
@export_multiline var description: String = ""

@export_enum("Common", "Uncommon", "Rare", "Legendary")
var rarity: String = "Common"

@export var icon_texture: Texture2D 
# Stat bonuses this equipment gives
@export var bonus_max_hp: int = 0
@export var bonus_atk: int = 0
@export var bonus_defense: int = 0
@export var bonus_move: int = 0
@export var bonus_max_mana: int = 0

# -----------------------------
# Status interaction (Phase 1)
# -----------------------------

# If true: immune to any NEGATIVE status (debuffs, prevent_move/arcana, negative mods)
@export var immune_negative_statuses: bool = false

# Immune to specific status keys (e.g. [&"wet", &"chilled"])
@export var immune_status_keys: Array[StringName] = []

# If > 0: statuses YOU apply last longer by this many turns (e.g. +1)
@export var bonus_status_duration_applied: int = 0

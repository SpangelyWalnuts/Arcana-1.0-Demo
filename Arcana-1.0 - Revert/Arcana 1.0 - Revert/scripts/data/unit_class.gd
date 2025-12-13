extends Resource
class_name UnitClass

@export var display_name: String = "Unit"

# --- Base stats ---
@export var max_hp: int = 10
@export var atk: int = 4
@export var defense: int = 1
@export var attack_range: int = 1
@export var move_range: int = 4
@export var team: String = "player"

# --- Mana / Arcana ---
@export var max_mana: int = 5
@export var mana_regen_per_turn: int = 1

# Skills that this class can use (Arcana)
@export var skills: Array[Skill] = []


# --- Level / EXP config ---
@export var exp_per_level: int = 100

# FE-style percentage growths (0.0–1.0).
# Your _level_up_unit() uses these names:
@export_range(0.0, 1.0, 0.01) var growth_hp: float      = 0.8
@export_range(0.0, 1.0, 0.01) var growth_atk: float     = 0.6
@export_range(0.0, 1.0, 0.01) var growth_defense: float = 0.5
@export_range(0.0, 1.0, 0.01) var growth_move: float    = 0.1
@export_range(0.0, 1.0, 0.01) var growth_mana: float    = 0.7

#TEXTURES
@export var sprite_texture: Texture2D    # used for the in-battle Sprite2D
@export var portrait_texture: Texture2D  # optional, for UI (prep, etc.)
@export var icon_texture: Texture2D      # optional, small class icon

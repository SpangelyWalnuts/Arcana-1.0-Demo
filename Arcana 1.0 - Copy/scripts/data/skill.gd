extends Resource
class_name Skill

enum TargetType { ENEMY_UNITS, ALL_UNITS, ALLY_UNITS, SELF, TILE }
enum EffectType { DAMAGE, HEAL, BUFF, DEBUFF, TERRAIN }

# 🔹 What the terrain skill actually does
enum TerrainAction {
	SET_TILE,   # Set this tile to a specific terrain (e.g., wall, vines)
	CLEAR_TILE, # Remove tile / revert to "empty"
	# You can add more later like RAISE_LOWER_HEIGHT, SPREAD_FIRE, etc.
}

@export var name: String = "Skill"
@export var description: String = ""

@export var mana_cost: int = 2

# Effect type: controls what Execute does
@export var effect_type: EffectType = EffectType.DAMAGE

# Backwards-compatible: if true and effect_type is default, treat as HEAL
@export var is_heal: bool = false

# Range from the caster’s current tile to the center of the effect
@export var cast_range: int = 3

# Radius around the chosen tile for AoE (Manhattan distance)
@export var aoe_radius: int = 0  # 0 = single target

# Damage / heal scaling
@export var power_multiplier: float = 1.0
@export var flat_power: int = 0

@export var target_type: TargetType = TargetType.ENEMY_UNITS

# Can the caster target their own tile/unit?
@export var can_target_self: bool = false


# --- Status / Buff / Debuff parameters ---

@export var atk_mod: int = 0
@export var def_mod: int = 0
@export var move_mod: int = 0
@export var mana_regen_mod: int = 0

# Number of turns the status lasts (0 = until consumed or permanent)
@export var duration_turns: int = 1

# Lockout flags (for debuffs like Silence, Root)
@export var prevent_arcana: bool = false
@export var prevent_move: bool = false

# One-shot modifiers (consumed on use)
# e.g. 0.5 = +50% damage to next basic attack / damage skill
@export var next_attack_damage_mul: float = 0.0

# e.g. +1 radius on next arcana AoE
@export var next_arcana_aoe_bonus: int = 0


# --- Terrain manipulation parameters ---

# What kind of terrain action is this skill performing?
@export var terrain_action: TerrainAction = TerrainAction.SET_TILE

# A logical key like "wall", "vines", "spikes" – Grid will map this to a tile.
@export var terrain_tile_key: String = ""

#TERRAIN OBJECT EXPORTS
@export var is_terrain_object_skill: bool = false
@export var terrain_object_scene: PackedScene
@export var terrain_object_key: String = ""      # optional, overrides the effect key
@export var terrain_object_duration: int = -1    # -1 = permanent
@export var terrain_object_blocks_movement: bool = false
@export var terrain_object_move_cost_bonus: int = 0

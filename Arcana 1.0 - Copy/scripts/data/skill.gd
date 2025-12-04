extends Resource
class_name Skill

enum TargetType { ENEMY_UNITS, ALL_UNITS, ALLY_UNITS, SELF, TILE }

@export var name: String = "Skill"
@export var description: String = ""

@export var mana_cost: int = 2

# ✅ Is this a healing skill? (if false, treat as damage)
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

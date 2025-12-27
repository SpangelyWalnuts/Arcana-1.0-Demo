extends Resource
class_name CombatEffect

@export var effect_id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

# Called when the owner is hit by a basic attack (melee or ranged).
# ctx expected keys:
#   attacker, defender, damage, is_counter
func on_basic_attack_taken(owner, ctx: Dictionary) -> void:
	pass

# Called before damage is applied to the owner.
# Effects may modify ctx["damage"] (int).
# ctx expected keys (at minimum): attacker, defender, damage, is_basic, is_melee, skill (optional)
func on_before_damage_taken(owner, ctx: Dictionary) -> void:
	pass

# Called before damage is applied to the defender, on the attacker side.
# Effects may modify ctx["damage"] (int).
func on_before_damage_dealt(owner, ctx: Dictionary) -> void:
	pass

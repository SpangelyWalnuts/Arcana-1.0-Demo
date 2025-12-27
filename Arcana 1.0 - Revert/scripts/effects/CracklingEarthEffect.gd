extends CombatEffect
class_name CracklingEarthEffect

@export var retaliate_damage: int = 2
@export var melee_only: bool = true

func _init() -> void:
	effect_id = &"crackling_earth_effect"
	display_name = "Crackling Earth"
	description = "When hit by a basic attack, deal damage to the attacker."

func on_basic_attack_taken(owner, ctx: Dictionary) -> void:
	if owner == null:
		return
	if ctx == null:
		return

	var attacker := ctx.get("attacker", null) as Node
	if attacker == null:
		return
	if not is_instance_valid(attacker):
		return

	if melee_only:
		var is_melee := ctx.get("is_melee", true) as bool
		if not is_melee:
			return

	if attacker.has_method("take_damage"):
		attacker.take_damage(retaliate_damage)

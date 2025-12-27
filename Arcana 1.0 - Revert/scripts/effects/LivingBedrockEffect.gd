extends CombatEffect
class_name LivingBedrockEffect

@export var defense_ratio: float = 0.4
@export var min_damage_taken: int = 1

func _init() -> void:
	effect_id = &"living_bedrock_effect"
	display_name = "Living Bedrock"
	description = "Reduces damage taken based on Defense before damage is applied."

func on_before_damage_taken(owner, ctx: Dictionary) -> void:
	if owner == null or ctx == null:
		return

	var incoming_damage := ctx.get("damage", 0) as int
	if incoming_damage <= 0:
		return

	if not owner.has_method("get_defense"):
		return

	var defense := owner.get_defense() as int
	var reduction: int = int(float(defense) * defense_ratio)
	if reduction <= 0:
		return

	var reduced_damage: int = incoming_damage - reduction
	if reduced_damage < min_damage_taken:
		reduced_damage = min_damage_taken

	ctx["damage"] = reduced_damage

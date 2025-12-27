extends CombatEffect
class_name StaticRetaliationEffect

@export var shocked_duration_turns: int = 1

var _shocked_skill: Skill = null

func _init() -> void:
	effect_id = &"static_retaliation_effect"
	display_name = "Static Retaliation"
	description = "When hit by a basic attack, apply Shocked to the attacker."

func on_basic_attack_taken(owner, ctx: Dictionary) -> void:
	if owner == null:
		return
	if ctx == null:
		return
	if StatusManager == null:
		return
	if not StatusManager.has_method("apply_status_to_unit"):
		return

	var attacker: Node = ctx.get("attacker", null) as Node
	if attacker == null:
		return
	if not is_instance_valid(attacker):
		return

	_ensure_status_skill()
	StatusManager.apply_status_to_unit(attacker, _shocked_skill, owner)

func _ensure_status_skill() -> void:
	if _shocked_skill == null:
		_shocked_skill = Skill.new()
		_shocked_skill.name = "Static Retaliation (Shocked)"
		_shocked_skill.effect_type = Skill.EffectType.DEBUFF
		_shocked_skill.status_key = &"shocked"
		_shocked_skill.duration_turns = shocked_duration_turns

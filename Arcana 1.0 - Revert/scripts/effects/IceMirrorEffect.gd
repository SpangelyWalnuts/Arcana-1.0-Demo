extends CombatEffect
class_name IceMirrorEffect

@export var chilled_duration_turns: int = 1
@export var frozen_duration_turns: int = 1
@export var apply_frozen_if_attacker_wet: bool = true

var _chilled_skill: Skill = null
var _frozen_skill: Skill = null

func _init() -> void:
	effect_id = &"ice_mirror_effect"
	display_name = "Ice Mirror"
	description = "When hit by a basic attack, apply Chilled to the attacker. If the attacker is Wet, apply Frozen instead."

func on_basic_attack_taken(owner, ctx: Dictionary) -> void:
	if owner == null:
		return
	if ctx == null:
		return
	if StatusManager == null:
		return
	if not StatusManager.has_method("apply_status_to_unit"):
		return

	var attacker = ctx.get("attacker", null)
	if attacker == null:
		return
	if not is_instance_valid(attacker):
		return

	_ensure_status_skills()

	var apply_frozen: bool = false
	if apply_frozen_if_attacker_wet and StatusManager.has_method("has_status"):
		if StatusManager.has_status(attacker, &"wet"):
			apply_frozen = true

	if apply_frozen:
		StatusManager.apply_status_to_unit(attacker, _frozen_skill, owner)
	else:
		StatusManager.apply_status_to_unit(attacker, _chilled_skill, owner)

func _ensure_status_skills() -> void:
	if _chilled_skill == null:
		_chilled_skill = Skill.new()
		_chilled_skill.name = "Ice Mirror (Chilled)"
		_chilled_skill.effect_type = Skill.EffectType.DEBUFF
		_chilled_skill.status_key = &"chilled"
		_chilled_skill.duration_turns = chilled_duration_turns

	if _frozen_skill == null:
		_frozen_skill = Skill.new()
		_frozen_skill.name = "Ice Mirror (Frozen)"
		_frozen_skill.effect_type = Skill.EffectType.DEBUFF
		_frozen_skill.status_key = &"frozen"
		_frozen_skill.duration_turns = frozen_duration_turns

extends Node
class_name SkillSystem

func execute_skill_on_target(user, target, skill: Skill) -> void:
	var main := get_parent()
	if main == null:
		push_error("SkillSystem: Missing parent (Main).")
		return

	var cm := main.get_node_or_null("CombatManager")
	if cm != null and cm.has_method("execute_skill_on_target"):
		cm.execute_skill_on_target(user, target, skill)

		# ✅ IMPORTANT: single-target casts must emit this too (AoE already emits in use_skill()).
		if cm.has_signal("skill_sequence_finished"):
			cm.skill_sequence_finished.emit(user)
	else:
		push_error("SkillSystem: Could not find CombatManager node or method execute_skill_on_target().")

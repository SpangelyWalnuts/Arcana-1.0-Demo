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
	else:
		push_error("SkillSystem: Could not find CombatManager node or method execute_skill_on_target().")

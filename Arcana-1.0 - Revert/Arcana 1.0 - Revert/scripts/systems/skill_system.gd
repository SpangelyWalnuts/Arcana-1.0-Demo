extends Node
class_name SkillSystem

func execute_skill_on_target(user, target, skill: Skill) -> void:
	# Thin wrapper: call back into Main.gd’s existing helper.
	var main := get_parent()
	if main != null and main.has_method("_execute_skill_on_target"):
		main._execute_skill_on_target(user, target, skill)
	else:
		push_error("SkillSystem: parent has no _execute_skill_on_target, cannot execute skill.")

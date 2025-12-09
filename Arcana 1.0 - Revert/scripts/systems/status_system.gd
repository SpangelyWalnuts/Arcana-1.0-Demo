extends Node

# We use the Unit script's active_statuses array as the storage.
const STATUS_LIST_KEY := "active_statuses"

# -------------------------------------------------
# INTERNAL: fetch / ensure the status list on a unit
# -------------------------------------------------
func _get_status_list(unit) -> Array:
	if unit == null:
		return []

	# We assume your Unit script defines: var active_statuses: Array = []
	# So we just read/write that.
	if not unit.has_method("get"):
		return []

	var list = unit.get(STATUS_LIST_KEY)
	if typeof(list) != TYPE_ARRAY:
		list = []
		unit.set(STATUS_LIST_KEY, list)

	return list

# -------------------------------------------------
# APPLYING A STATUS FROM A SKILL
# -------------------------------------------------
func apply_status_to_unit(unit, skill: Skill, source_unit: Node = null) -> void:
	if unit == null or skill == null:
		return

	var list: Array = _get_status_list(unit)

	var status: Dictionary = {
		"skill": skill,
		"source": source_unit,
		"remaining_turns": skill.duration_turns,

		# numeric buffs/debuffs
		"atk_mod": skill.atk_mod,
		"def_mod": skill.def_mod,
		"move_mod": skill.move_mod,
		"mana_regen_mod": skill.mana_regen_mod,

		# flags
		"prevent_arcana": skill.prevent_arcana,
		"prevent_move":  skill.prevent_move,

		# one-shot modifiers
		"next_attack_damage_mul": skill.next_attack_damage_mul,
		"next_arcana_aoe_bonus":  skill.next_arcana_aoe_bonus
	}

	list.append(status)
	unit.set(STATUS_LIST_KEY, list)

# -------------------------------------------------
# NUMERIC AGGREGATES
# -------------------------------------------------
func _sum_mod(unit, key: String) -> int:
	if unit == null:
		return 0

	var list: Array = _get_status_list(unit)
	var total: int = 0
	for s in list:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		total += int(s.get(key))
	return total

func get_move_bonus(unit) -> int:
	return _sum_mod(unit, "move_mod")

func get_mana_regen_bonus(unit) -> int:
	return _sum_mod(unit, "mana_regen_mod")

func get_atk_bonus(unit) -> int:
	return _sum_mod(unit, "atk_mod")

func get_def_bonus(unit) -> int:
	return _sum_mod(unit, "def_mod")

# -------------------------------------------------
# FLAGS (e.g. prevent_move, prevent_arcana)
# -------------------------------------------------
func unit_has_flag(unit, flag_name: String) -> bool:
	if unit == null:
		return false

	var list: Array = _get_status_list(unit)
	for s in list:
		if typeof(s) != TYPE_DICTIONARY:
			continue

		# direct key on the status dictionary
		if s.has(flag_name) and s[flag_name]:
			return true

		# optional nested "flags" dictionary
		var nested = s.get("flags")
		if typeof(nested) == TYPE_DICTIONARY:
			var flags: Dictionary = nested
			if flags.has(flag_name) and flags[flag_name]:
				return true

	return false

extends Node

signal status_changed(unit)
# We use the Unit script's active_statuses array as the storage.
const STATUS_LIST_KEY := "active_statuses"
# status_system.gd

# Map status flags → icon textures
var status_icon_map: Dictionary = {}
# Map status keys → icon textures
var STATUS_ICON_TEXTURES: Dictionary = {
	# debuffs
	"prevent_move": preload("res://art/ui/status_icons/fatigue.png"),
	"prevent_arcana": preload("res://art/ui/status_icons/silence.png"),

	# optional: buffs (if you want icons for them too)
	"atk_mod": preload("res://art/ui/status_icons/buff_atk.png"),
	"def_mod": preload("res://art/ui/status_icons/buff_def.png"),
	"mov_mod": preload("res://art/ui/status_icons/buff_mov.png"),
}
# Human-readable info for each status flag (used for tooltips)
var STATUS_FLAG_INFO: Dictionary = {
	"prevent_move": {
		"name": "Fatigued",
		"description": "Cannot move this turn."
	},
	"prevent_arcana": {
		"name": "Silenced",
		"description": "Cannot cast arcana."
	},
	"atk_mod": {
		"name": "Power Up",
		"description": "Attack increased."
	},
	"def_mod": {
		"name": "Guard Up",
		"description": "Defense increased."
	},
}


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

	# 🔔 Tell listeners (units) to update UI (icons, etc.)
	status_changed.emit(unit)


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
func get_flags_for_unit(unit) -> Dictionary:
	if unit == null:
		return {}

	var flags: Dictionary = {}
	var list: Array = _get_status_list(unit)

	for st in list:
		if not (st is Dictionary):
			continue

		# These are the main boolean flags we care about for icons
		if st.get("prevent_move", false):
			flags["prevent_move"] = true
		if st.get("prevent_arcana", false):
			flags["prevent_arcana"] = true

		# (Optional) if you want buff icons too:
		if st.get("atk_mod", 0) != 0:
			flags["atk_mod"] = true
		if st.get("def_mod", 0) != 0:
			flags["def_mod"] = true
		# You can add more here (move_mod, mana_regen_mod, etc.)

	return flags

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
	
#STATUS ICON HELPER
func get_statuses_for_unit(unit) -> Array:
	if unit == null:
		return []
	var list: Array = _get_status_list(unit)
	return list


#TICK HELPER
func refresh_icons_for_unit(unit, container: HBoxContainer) -> void:
	if unit == null or container == null:
		return

	# Clear old icons
	for child in container.get_children():
		child.queue_free()

	# Get combined flags for the unit
	var flags: Dictionary = get_flags_for_unit(unit)

	for key in flags.keys():
		var value = flags[key]

		if typeof(value) == TYPE_BOOL and value:
			if STATUS_ICON_TEXTURES.has(key):
				var tex: Texture2D = STATUS_ICON_TEXTURES[key]

				var icon := TextureRect.new()
				icon.texture = tex
				icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon.custom_minimum_size = Vector2(12, 12)

				# 🔹 Tooltip: name + description
				var info: Dictionary = STATUS_FLAG_INFO.get(key, {})
				var label: String = String(info.get("name", key.capitalize()))
				var desc: String  = String(info.get("description", ""))

				var tooltip: String = label
				if desc != "":
					tooltip += "\n" + desc

				icon.tooltip_text = tooltip

				container.add_child(icon)



#MAP ICON HELPER CODE
func get_icon_for_flag(flag_name: String) -> Texture2D:
	if status_icon_map.has(flag_name):
		return status_icon_map[flag_name]
	return null

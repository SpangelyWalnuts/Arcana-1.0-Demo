extends Node
# Autoload this as: StatusManager

signal status_changed(unit)

const STATUS_LIST_KEY := "active_statuses"

# Map status keys → icon textures
const STATUS_ICON_TEXTURES: Dictionary = {
	"prevent_move": preload("res://art/ui/status_icons/fatigue.png"),
	"prevent_arcana": preload("res://art/ui/status_icons/silence.png"),
	"atk_mod": preload("res://art/ui/status_icons/buff_atk.png"),
	"def_mod": preload("res://art/ui/status_icons/buff_def.png"),
	"wet": preload("res://art/ui/status_icons/wet.png"),
	"chilled": preload("res://art/ui/status_icons/chilled.png"),
	"shocked": preload("res://art/ui/status_icons/fatigue.png"),
	"frozen": preload("res://art/ui/status_icons/fatigue.png"),


}

# -----------------------------------------
# INTERNAL: get/create status list
# -----------------------------------------
func _get_status_list(unit) -> Array:
	if unit == null:
		return []

	# Unit has: var active_statuses: Array = []
	var list = unit.get(STATUS_LIST_KEY)
	if typeof(list) != TYPE_ARRAY:
		list = []
		unit.set(STATUS_LIST_KEY, list)
	return list


# -----------------------------------------
# APPLY
# -----------------------------------------
func apply_status_to_unit(unit, skill: Skill, source_unit: Node = null) -> void:
	if unit == null or skill == null:
		return

	var list: Array = _get_status_list(unit)

	var status: Dictionary = {
		"skill": skill,
		"source": source_unit,
		"remaining_turns": int(skill.duration_turns),
		"status_key": skill.status_key,

		# numeric mods
		"atk_mod": int(skill.atk_mod),
		"def_mod": int(skill.def_mod),
		"move_mod": int(skill.move_mod),
		"mana_regen_mod": int(skill.mana_regen_mod),

		# flags
		"prevent_arcana": bool(skill.prevent_arcana),
		"prevent_move": bool(skill.prevent_move),

		# one-shots
		"next_attack_damage_mul": float(skill.next_attack_damage_mul),
		"next_arcana_aoe_bonus": int(skill.next_arcana_aoe_bonus),
	}

	list.append(status)
	
	if CombatLog != null:
		var src_name: String = source_unit.name if source_unit != null else "<?>"
		CombatLog.add("%s applies %s to %s (%d turns)" % [src_name, skill.name, unit.name, int(skill.duration_turns)],
			{"type":"status_apply", "skill": skill.name, "target": unit.name, "duration": int(skill.duration_turns)})
	print("[STATUS APPLY] unit=", unit.name, " skill=", skill.name, " status_key=", skill.status_key)

	# IMPORTANT: deferred emit avoids re-entrancy/stack overflow
	call_deferred("_emit_status_changed", unit)

func _emit_status_changed(unit) -> void:
	if unit != null:
		status_changed.emit(unit)

#STATUS ADD AND REMOVAL HELPER
func has_status(unit, key: StringName) -> bool:
	var list: Array = _get_status_list(unit)
	for st in list:
		if typeof(st) != TYPE_DICTIONARY:
			continue
		if StringName(st.get("status_key", &"")) == key:
			return true
	return false


func remove_status(unit, key: StringName) -> bool:
	var list: Array = _get_status_list(unit)
	var removed: bool = false

	for i in range(list.size() - 1, -1, -1):
		var st = list[i]
		if typeof(st) != TYPE_DICTIONARY:
			continue
		if StringName(st.get("status_key", &"")) == key:
			list.remove_at(i)
			removed = true

	if removed:
		call_deferred("_emit_status_changed", unit)

	return removed


# -----------------------------------------
# TICKING (durations)
# Call once per PHASE START for that team.
# -----------------------------------------
func tick_team(team: String) -> void:
	var group_name := "player_units" if team == "player" else "enemy_units"
	var units: Array = get_tree().get_nodes_in_group(group_name)
	for u in units:
		tick_unit(u)

func tick_unit(unit) -> void:
	if unit == null:
		return

	var list: Array = _get_status_list(unit)
	if list.is_empty():
		return

	var changed := false

	# Iterate backwards so removals are safe
	for i in range(list.size() - 1, -1, -1):
		var st = list[i]
		if typeof(st) != TYPE_DICTIONARY:
			list.remove_at(i)
			changed = true
			continue

		var turns: int = int(st.get("remaining_turns", 0))

		# Only tick timed statuses
		if turns > 0:
			turns -= 1
			st["remaining_turns"] = turns
			list[i] = st
			changed = true

			# ✅ SANITY CHECK (safe formatting)
			var skill_name := "UNKNOWN"
			if st.has("skill") and st["skill"] != null:
				skill_name = st["skill"].name

			print(
				"[STATUS TICK]",
				unit.name,
				":",
				skill_name,
				"→",
				turns,
				"turns remaining"
			)

			if turns <= 0:
				print("[STATUS EXPIRE]", unit.name, ":", skill_name)
				list.remove_at(i)
				changed = true

	if changed:
		call_deferred("_emit_status_changed", unit)



# -----------------------------------------
# AGGREGATES
# -----------------------------------------
func _sum_mod(unit, key: String) -> int:
	var list: Array = _get_status_list(unit)
	var total: int = 0
	for st in list:
		if typeof(st) != TYPE_DICTIONARY:
			continue
		total += int(st.get(key, 0))
	return total

func get_move_bonus(unit) -> int:
	return _sum_mod(unit, "move_mod")

func get_mana_regen_bonus(unit) -> int:
	return _sum_mod(unit, "mana_regen_mod")

func get_atk_bonus(unit) -> int:
	return _sum_mod(unit, "atk_mod")

func get_def_bonus(unit) -> int:
	return _sum_mod(unit, "def_mod")


# -----------------------------------------
# FLAGS
# -----------------------------------------
func unit_has_flag(unit, flag_name: String) -> bool:
	var list: Array = _get_status_list(unit)
	for st in list:
		if typeof(st) != TYPE_DICTIONARY:
			continue
		if bool(st.get(flag_name, false)):
			return true
	return false

func get_flags_for_unit(unit) -> Dictionary:
	var flags: Dictionary = {}
	var list: Array = _get_status_list(unit)

	for st in list:
		if typeof(st) != TYPE_DICTIONARY:
			continue

		# NEW: show icons for status_key (wet, chilled, etc.)
		var skey: StringName = StringName(st.get("status_key", &""))
		if skey != &"":
			flags[String(skey)] = true

		if bool(st.get("prevent_move", false)):
			flags["prevent_move"] = true
		if bool(st.get("prevent_arcana", false)):
			flags["prevent_arcana"] = true
		if int(st.get("atk_mod", 0)) != 0:
			flags["atk_mod"] = true
		if int(st.get("def_mod", 0)) != 0:
			flags["def_mod"] = true

	return flags



# -----------------------------------------
# ICON UI helper (your tile info panel uses this)
# -----------------------------------------
func refresh_icons_for_unit(unit, container: HBoxContainer) -> void:
	if unit == null or container == null:
		return

	for child in container.get_children():
		child.queue_free()

	var flags: Dictionary = get_flags_for_unit(unit)
	for key in flags.keys():
		if not bool(flags[key]):
			continue
		if not STATUS_ICON_TEXTURES.has(key):
			continue

		var tex: Texture2D = STATUS_ICON_TEXTURES[key]
		var icon := TextureRect.new()
		icon.texture = tex
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.custom_minimum_size = Vector2(12, 12) # Godot 4 property name
		container.add_child(icon)

#STATUS DISPLAY HELPER
func get_status_display_name(key: StringName) -> String:
	match key:
		&"wet": return "Wet"
		&"chilled": return "Chilled"
		&"shocked": return "Shocked"
		&"frozen": return "Frozen"
		_: return String(key)

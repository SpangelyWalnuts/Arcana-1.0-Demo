extends Node

signal entry_added(entry: Dictionary)

@export var max_entries: int = 200

var _entries: Array[Dictionary] = []
var _turn_index: int = 0

func set_turn_index(turn_i: int) -> void:
	_turn_index = turn_i

func clear() -> void:
	_entries.clear()

func get_entries() -> Array[Dictionary]:
	return _entries.duplicate(true)

func add(message: String, data: Dictionary = {}) -> void:
	var entry: Dictionary = {
		"time_ms": Time.get_ticks_msec(),
		"turn": _turn_index,
		"msg": message,
		"data": data
	}

	_entries.append(entry)
	if _entries.size() > max_entries:
		_entries.pop_front()

	emit_signal("entry_added", entry)

# Convenience helpers (optional)
func log_attack(attacker: Node, target: Node, amount: int, killed: bool = false) -> void:
	var a := _safe_name(attacker)
	var t := _safe_name(target)
	var msg := "%s attacks %s for %d" % [a, t, amount]
	if killed:
		msg += " (KO)"
	add(msg, {"type":"attack","attacker":a,"target":t,"amount":amount,"killed":killed})

func log_cast(caster: Node, skill, center_tile: Vector2i, targets: Array = []) -> void:
	var c := _safe_name(caster)
	var sname := _safe_skill_name(skill)
	var msg := "%s casts %s at %s" % [c, sname, str(center_tile)]
	add(msg, {"type":"cast","caster":c,"skill":sname,"tile":center_tile,"targets":targets})

func log_status_applied(source: Node, target: Node, status_name: String, duration: int) -> void:
	add("%s applies %s to %s (%d)" % [_safe_name(source), status_name, _safe_name(target), duration],
		{"type":"status_apply","source":_safe_name(source),"target":_safe_name(target),"status":status_name,"duration":duration})

func log_status_tick(target: Node, status_name: String, remaining: int) -> void:
	add("%s: %s (%d)" % [_safe_name(target), status_name, remaining],
		{"type":"status_tick","target":_safe_name(target),"status":status_name,"remaining":remaining})

func _safe_name(n: Node) -> String:
	if n == null: return "<?>"
	if not is_instance_valid(n): return "<freed>"
	return n.name

func _safe_skill_name(skill) -> String:
	if skill == null: return "<Skill?>"
	if skill is Resource and "name" in skill:
		return str(skill.name)
	if skill is Object and skill.has_method("get") and _has_prop(skill, "name"):
		return str(skill.get("name"))
	return str(skill)
	
func _has_prop(obj: Object, prop_name: String) -> bool:
	for p in obj.get_property_list():
		if String(p.name) == prop_name:
			return true
	return false

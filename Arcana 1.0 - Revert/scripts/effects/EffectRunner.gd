extends Node
class_name EffectRunner

var unit: Node = null

var _ice_mirror_effect: IceMirrorEffect = null
var _static_retaliation_effect: StaticRetaliationEffect = null
var _crackling_earth_effect: CracklingEarthEffect = null
var _living_bedrock_effect: LivingBedrockEffect = null


func setup(p_unit: Node) -> void:
	unit = p_unit


func gather_effects() -> Array:
	var out: Array = []

	if unit == null:
		return out

	# Reset cached effects each gather
	_ice_mirror_effect = null
	_static_retaliation_effect = null
	_crackling_earth_effect = null
	_living_bedrock_effect = null

	# -------------------------
	# Ice Mirror (Cryomancer)
	# -------------------------
	if StatusManager.has_status(unit, &"ice_mirror"):
		if _ice_mirror_effect == null:
			_ice_mirror_effect = IceMirrorEffect.new()
		_append_unique(out, _ice_mirror_effect)

	# --------------------------------
	# Static Retaliation (Electromancer)
	# --------------------------------
	if StatusManager.has_status(unit, &"static_retaliation"):
		if _static_retaliation_effect == null:
			_static_retaliation_effect = StaticRetaliationEffect.new()
		_append_unique(out, _static_retaliation_effect)

	# -------------------------
	# Crackling Earth (Geomancer)
	# -------------------------
	if StatusManager.has_status(unit, &"crackling_earth"):
		if _crackling_earth_effect == null:
			_crackling_earth_effect = CracklingEarthEffect.new()
		_append_unique(out, _crackling_earth_effect)

	# -------------------------
	# Living Bedrock (Geomancer)
	# -------------------------
	if StatusManager.has_status(unit, &"living_bedrock"):
		if _living_bedrock_effect == null:
			_living_bedrock_effect = LivingBedrockEffect.new()
		_append_unique(out, _living_bedrock_effect)

	_gather_equipment_effects(out)
	return out




func _append_unique(arr: Array, effect: CombatEffect) -> void:
	if effect == null:
		return
	if not arr.has(effect):
		arr.append(effect)

func _gather_equipment_effects(out: Array) -> void:
	if unit == null:
		return
	if not unit.has_method("get_equipment"):
		return

	var equips: Array = unit.get_equipment()
	for eq in equips:
		if eq == null:
			continue
		for eff in eq.effects:
			if eff == null:
				continue
			_append_unique(out, eff)

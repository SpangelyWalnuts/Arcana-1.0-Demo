extends Control

@onready var attacker_label: Label     = $Panel/VBoxContainer/AttackerLabel
@onready var attacker_hp_label: Label  = $Panel/VBoxContainer/AttackerHPLabel
@onready var defender_label: Label     = $Panel/VBoxContainer/DefenderLabel
@onready var defender_hp_label: Label  = $Panel/VBoxContainer/DefenderHPLabel
@onready var damage_label: Label       = $Panel/VBoxContainer/DamageLabel
@onready var counter_label: Label      = $Panel/VBoxContainer/CounterLabel


func _ready() -> void:
	visible = false


func show_forecast(attacker, defender) -> void:
	if attacker == null or defender == null:
		hide_forecast()
		return

	# --- Your attack ---
	var dmg_to_def: int = _compute_basic_damage(attacker, defender)
	var defender_hp_after: int = max(defender.hp - dmg_to_def, 0)

	# --- Potential counterattack ---
	var can_counter: bool = _can_counterattack(attacker, defender)
	var dmg_to_att: int = 0
	var attacker_hp_after: int = attacker.hp

	if can_counter:
		dmg_to_att = _compute_basic_damage(defender, attacker)
		attacker_hp_after = max(attacker.hp - dmg_to_att, 0)

	# --- Fill labels ---
	attacker_label.text = "Attacker: %s" % attacker.name
	if can_counter:
		attacker_hp_label.text = "HP: %d → %d" % [attacker.hp, attacker_hp_after]
	else:
		attacker_hp_label.text = "HP: %d / %d" % [attacker.hp, attacker.max_hp]

	defender_label.text = "Defender: %s" % defender.name
	defender_hp_label.text = "HP: %d → %d" % [defender.hp, defender_hp_after]

	damage_label.text = "Your Damage: %d" % dmg_to_def

	if can_counter:
		counter_label.text = "Counter Damage: %d" % dmg_to_att
	else:
		counter_label.text = "Counter: -"

	visible = true


func hide_forecast() -> void:
	visible = false


func _compute_basic_damage(attacker, defender) -> int:
	var raw: int = attacker.atk - defender.defense
	if raw < 1:
		raw = 1
	return raw


func _can_counterattack(attacker, defender) -> bool:
	# Basic assumptions:
	# - Different teams
	# - Defender alive
	# - Adjacent tiles (melee range) – you can expand this later for ranged units
	if defender.team == attacker.team:
		return false
	if defender.hp <= 0:
		return false

	var dist_x: int = abs(attacker.grid_position.x - defender.grid_position.x)
	var dist_y: int = abs(attacker.grid_position.y - defender.grid_position.y)
	var manhattan: int = dist_x + dist_y

	# Simple melee counter condition: distance 1
	return manhattan == 1
